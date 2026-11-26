#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
group=$1
python=${PYTHON:-python3}
name="aosstudio-aosp-host-tools-$group-17.0.0_r1-linux-x86_64"
work=$(mktemp -d "$root/out/verify-$group.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
export LC_ALL=C TZ=UTC TMPDIR="$work/tmp"
mkdir -p "$TMPDIR"
tar -xzf "out/dist/$name.tar.gz" -C "$work"
bin="$work/$name/bin"
cd "$work"

case "$group" in
  bootstrap)
    "$python" "$root/scripts/inputs.py" bootstrap --source "$work/source"
    mkdir "$work/release"
    tar -xzf "$root/out/inputs/tool/go1.25.4.linux-amd64.tar.gz" -C "$work"
    (
      cd "$work/source"
      soong_output=$(GOROOT="$work/go" OUT_DIR="$work/soong-out" "$bin/soong_ui" --dumpvar-mode OUT_DIR)
      [[ "$soong_output" == "$work/soong-out" ]]
    )
    (
      cd "$work/source"
      "$bin/release-config" --quiet --product sdk --release cp2a --variant userdebug \
        --out_dir "$work/release" --map build/release/release_config_map.textproto
    )
    grep -F 'RELEASE_PLATFORM_SDK_VERSION :=$= 37' "$work/release/release_config-sdk-cp2a.varmk"
    touch empty-flags.txt
    "$bin/ckati" --ninja -f "$root/tests/bootstrap.mk" probe.txt
    "$bin/ninja" -f build.ninja probe.txt
    [[ $(cat probe.txt) == 37 ]]
    "$bin/sbox" --sandbox-path "$work/sandbox" --output-dir sandbox-output \
      --manifest "$root/tests/sbox.textproto"
    [[ $(cat sandbox-output/probe.txt) == 37 ]]
    "$bin/toybox" sha256sum probe.txt > checksum.txt
    test -s checksum.txt
    "$bin/soong_zip" -o first.zip -C "$work" -f "$work/probe.txt"
    "$bin/merge_zips" combined.zip first.zip
    "$bin/zipsync" -d "$work/unpacked" combined.zip
    cmp probe.txt unpacked/probe.txt
    ;;
  generators)
    "$bin/aconfig" --help > aconfig-help.txt
    grep -F create-cache aconfig-help.txt
    "$bin/aconfig-to-metalava-flags" --help > metalava-flags-help.txt
    "$bin/aapt2" compile --dir "$root/tests/resources" -o resources.zip
    "$bin/aapt2" link --manifest "$root/tests/AndroidManifest.xml" -o probe.apk resources.zip
    "$bin/aapt2" dump resources probe.apk > resource-table.txt
    grep -F 'string/build_probe' resource-table.txt
    ;;
  java)
    export JAVA_HOME="$work/jdk"
    unset JDK_JAVA_OPTIONS JAVA_TOOL_OPTIONS _JAVA_OPTIONS CLASSPATH
    mkdir "$JAVA_HOME" classes
    tar -xzf "$root/out/inputs/tool/aosstudio-jdk-21.0.13.1-2-linux-x86_64.tar.gz" -C "$JAVA_HOME"
    "$bin/metalava" --version
    for provider in psi turbine; do
      "$bin/metalava" "-JDjava.io.tmpdir=$TMPDIR" --no-color --source-model-provider "$provider" \
        --jdk-home "$JAVA_HOME" --java-source 17 "$root/tests/java/sdk/probe/ApiProbe.java" \
        --api "$provider.txt" --stubs "$provider-stubs"
      grep -F 'public static final int API = 37;' "$provider.txt"
    done
    cmp psi.txt turbine.txt
    "$bin/turbine" --output header.jar --system "$JAVA_HOME" --sources "$root/tests/java/sdk/probe/ApiProbe.java"
    "$JAVA_HOME/bin/javap" -classpath header.jar -constants sdk.probe.ApiProbe | grep -F 'API = 37;'
    "$JAVA_HOME/bin/javac" --release 17 -d classes \
      "$root/tests/parcelables/android/os/Parcelable.java" "$root/tests/parcelables/sdk/probe/SampleParcelable.java"
    "$JAVA_HOME/bin/jar" --create --file parcelables.jar -C classes .
    "$bin/sdkparcelables" parcelables.jar framework.aidl
    grep -F 'parcelable sdk.probe.SampleParcelable;' framework.aidl
    ;;
  *) exit 2 ;;
esac
printf '%s package verified\n' "$group"
