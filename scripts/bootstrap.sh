#!/usr/bin/env bash
set -euo pipefail

root=$1
work=$2
source_dir="$work/source"
package=$3
jobs=$4
tool_input="$root/out/inputs/tool"
mkdir -p "$package/bin" "$package/share/licenses"

tar -xzf "$tool_input/go1.25.4.linux-amd64.tar.gz" -C "$work"
export GOROOT="$work/go" GOPATH="$work/gopath" GOCACHE="$work/go-cache"
export GO111MODULE=off GOENV=off GOTOOLCHAIN=local GOPROXY=off CGO_ENABLED=0
go="$GOROOT/bin/go"
"$go" version

# The upstream Go tools use import paths assigned by the AOSP bootstrap.
link_go_package() {
  local package_path="$GOPATH/src/$1"
  mkdir -p "$(dirname -- "$package_path")"
  ln -s -- "$source_dir/$2" "$package_path"
}
link_go_package android/soong build/soong
link_go_package github.com/google/blueprint build/blueprint
link_go_package rbcrun build/make/tools/rbcrun
link_go_package google.golang.org/protobuf external/golang-protobuf
link_go_package github.com/google/go-cmp external/go-cmp
link_go_package github.com/akrylysov/pogreb external/pogreb
link_go_package go.starlark.net external/starlark-go

"$go" build -trimpath -p "$jobs" -o "$package/bin/soong_ui" android/soong/cmd/soong_ui
"$go" build -trimpath -p "$jobs" -o "$package/bin/release-config" android/soong/cmd/release_config/release_config
"$go" build -trimpath -p "$jobs" -o "$package/bin/mk2rbc" android/soong/mk2rbc/mk2rbc
"$go" build -trimpath -p "$jobs" -o "$package/bin/rbcrun" rbcrun/rbcrun
"$go" build -trimpath -p "$jobs" -o "$package/bin/soong_zip" android/soong/zip/cmd
for tool in sbox merge_zips zipsync; do
  "$go" build -trimpath -p "$jobs" -o "$package/bin/$tool" "android/soong/cmd/$tool"
done

kati_commit=81362a8030f5639195cda24a3e651892c0a185f4
(
  cd "$source_dir/external/kati"
  patch --batch -p1 -i "$root/patches/ckati-handle-empty-file.patch"
  make -j"$jobs" KATI_VERSION="$kati_commit" \
    KATI_CXX=clang++-21 KATI_LD=clang++-21 \
    KATI_CXXFLAGS='-O2 -MMD -MP -DNOLOG -D_GLIBCXX_ASSERTIONS' ckati
  install -m 0755 ckati "$package/bin/ckati"
)
(
  cd "$source_dir/external/ninja"
  patch --batch -p1 -i "$root/patches/ninja-python-313.patch"
  mkdir -p "$work/host-bin"
  ln -sf -- "$(command -v "${PYTHON:-python3}")" "$work/host-bin/python"
  export PATH="$work/host-bin:$PATH"
  CXX=clang++-21 CFLAGS='-O2' CXXFLAGS='-O2' "${PYTHON:-python3}" configure.py --bootstrap
  install -m 0755 ninja "$package/bin/ninja"
)
(
  cd "$source_dir/external/toybox"
  cp config-linux .config
  make silentoldconfig </dev/null
  make -j"$jobs" CC=clang-21
  install -m 0755 toybox "$package/bin/toybox"
)

declare -A licenses=(
  [Go]="$GOROOT/LICENSE"
  [Soong]="$source_dir/build/soong/licenses/LICENSE"
  [Blueprint]="$source_dir/build/blueprint/LICENSE"
  [Go-Protobuf]="$source_dir/external/golang-protobuf/LICENSE"
  [Starlark]="$source_dir/external/starlark-go/LICENSE"
  [Pogreb]="$source_dir/external/pogreb/LICENSE"
  [Go-cmp]="$source_dir/external/go-cmp/LICENSE"
  [Kati]="$source_dir/external/kati/LICENSE"
  [Ninja]="$source_dir/external/ninja/COPYING"
  [Toybox]="$source_dir/external/toybox/LICENSE"
)
for name in "${!licenses[@]}"; do
  install -m 0644 "${licenses[$name]}" "$package/share/licenses/$name"
done
