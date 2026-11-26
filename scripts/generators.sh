#!/usr/bin/env bash
set -euo pipefail

root=$1
work=$2
package=$3
jobs=$4
source_dir="$work/source"
cache="$root/out/inputs/tool"
python=${PYTHON:-python3}
mkdir -p "$package/bin" "$package/share/licenses" "$work/generated" "$work/rust" "$work/jdk"
tar -xzf "$cache/aosstudio-jdk-21.0.13.1-2-linux-x86_64.tar.gz" -C "$work/jdk"

bootstrap="$root/out/dist/aosstudio-aosp-host-tools-bootstrap-17.0.0_r1-linux-x86_64.tar.gz"
tar -xzf "$bootstrap" -C "$work"
bootstrap_bin="$work/aosstudio-aosp-host-tools-bootstrap-17.0.0_r1-linux-x86_64/bin"
release="$work/release"
mkdir "$release"
(
  cd "$source_dir"
  "$bootstrap_bin/release-config" --quiet --product sdk --release cp2a --variant userdebug \
    --out_dir "$release" --map build/release/release_config_map.textproto
)
release_flags="$release/release_config-sdk-cp2a.varmk"
grep -F 'RELEASE_PLATFORM_SDK_VERSION :=$= 37' "$release_flags"

for tool in rustc cargo rust-std; do
  archive="$tool-1.93.0-x86_64-unknown-linux-gnu"
  tar -xJf "$cache/$archive.tar.xz" -C "$work"
  bash "$work/$archive/install.sh" --prefix="$work/rust" --disable-ldconfig >/dev/null
done
export PATH="$work/rust/bin:$PATH"
export CARGO_HOME="$work/cargo" CARGO_TARGET_DIR="$work/cargo-target"
export CC=clang-21 CXX=clang++-21 CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=clang-21
rustc --version
"$python" "$root/scripts/crates.py" "$work" "$package/share/licenses"
mkdir -p "$CARGO_HOME"
cat > "$CARGO_HOME/config.toml" <<EOF_CARGO
[source.crates-io]
replace-with = "vendor"

[source.vendor]
directory = "$work/vendor"

[net]
offline = true
EOF_CARGO

(
  cd "$source_dir/build/make/tools/aconfig"
  patch --batch -p1 -i "$root/patches/aconfig-host-cargo.patch"
  cp -- "$root/locks/aconfig-Cargo.lock" Cargo.lock
  mkdir -p "$source_dir/prebuilts/sdk"
  cargo build --frozen --release --jobs "$jobs" --package aconfig
)
install -m 0755 "$CARGO_TARGET_DIR/release/aconfig" "$package/bin/aconfig"
flags_app="$work/flags-app"
mkdir -p "$flags_app/protos"
install -m 0644 "$source_dir/build/soong/scripts/aconfig-to-metalava-flags.py" "$flags_app/__main__.py"
proto_dir="$source_dir/build/make/tools/aconfig/aconfig_protos"
protoc -I "$proto_dir" --python_out="$flags_app" "$proto_dir/protos/aconfig.proto"
"$python" -m zipapp "$flags_app" -p /usr/bin/python3 -o "$package/bin/aconfig-to-metalava-flags"
bash "$root/scripts/resource-flags.sh" "$source_dir" "$work" "$package/bin/aconfig" "$release_flags"
"$package/bin/aconfig-to-metalava-flags" "$work/android-content-res.pb" > "$work/metalava-flags.xml"
grep -F 'android.content.res' "$work/metalava-flags.xml" >/dev/null

for deb in "$cache"/libc++{,-22-dev,abi-22-dev}*.deb "$cache"/libunwind-22-dev*.deb; do
  if [[ -f "$deb" ]]; then
    dpkg-deb -x "$deb" "$work/llvm"
  fi
done
libcxx="$work/llvm/usr/lib/x86_64-linux-gnu"
mkdir "$work/static-runtime"
(
  cd "$work/static-runtime"
  printf 'CREATE libc++.a\nADDLIB %s/libc++.a\nADDLIB %s/libc++abi.a\nADDLIB %s/libunwind.a\nSAVE\nEND\n' \
    "$libcxx" "$libcxx" "$libcxx" | llvm-ar-21 -M
)

install -m 0755 "$cache/protoc-4.33.5-linux-x86_64.exe" "$work/protoc"
"$work/protoc" --version
cmake -S "$root/native" -B "$work/aapt2" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 \
  "-DCMAKE_CXX_FLAGS=-stdlib=libc++ -nostdinc++ -isystem $work/llvm/usr/lib/llvm-22/include/c++/v1" \
  "-DCMAKE_EXE_LINKER_FLAGS=-L$work/static-runtime -static-libstdc++" \
  -DCMAKE_CXX_FLAGS_RELEASE='-O2 -DNDEBUG' \
  "-DAOSP_SOURCE=$source_dir" "-DAOSP_WORK=$work" "-DAOSP_JDK=$work/jdk" "-DAOSP_PROTOC=$work/protoc"
cmake --build "$work/aapt2" --parallel "$jobs" --target aapt2
install -m 0755 "$work/aapt2/aapt2" "$package/bin/aapt2"
"$package/bin/aapt2" version

install -m 0644 "$source_dir/build/soong/licenses/LICENSE" "$package/share/licenses/AOSP"
for project in external/{abseil-cpp,fmtlib,protobuf,rust/cxx} system/{libbase,libziparchive}; do
  for notice in "$source_dir/$project"/LICENSE* "$source_dir/$project"/NOTICE*; do
    [[ -f "$notice" ]] || continue
    install -m 0644 "$notice" "$package/share/licenses/${project//\//-}-${notice##*/}"
  done
done
for library in "$work/llvm/usr/share/doc/"{libc++-22-dev,libc++abi-22-dev,libunwind-22-dev}; do
  install -m 0644 "$library/copyright" "$package/share/licenses/${library##*/}"
done
install -m 0644 /usr/share/doc/zlib1g-dev/copyright "$package/share/licenses/zlib"
install -m 0644 /usr/share/doc/libpng-dev/copyright "$package/share/licenses/libpng"
install -m 0644 /usr/share/doc/libexpat1-dev/copyright "$package/share/licenses/expat"
