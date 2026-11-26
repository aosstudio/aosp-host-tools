#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
[[ $(uname -sm) == 'Linux x86_64' ]]
group=$1
jobs=$2
python=${PYTHON:-python3}
mkdir -p out/dist
work=$(mktemp -d "$root/out/$group.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
export LC_ALL=C TZ=UTC TMPDIR="$work/tmp"
mkdir -p "$TMPDIR"
case "$group" in
  bootstrap) inputs=(bootstrap) ;;
  generators) inputs=(bootstrap generators) ;;
  java) inputs=(java) ;;
  *) exit 2 ;;
esac
"$python" scripts/inputs.py "${inputs[@]}" --source "$work/source"
name="aosstudio-aosp-host-tools-$group-17.0.0_r1-linux-x86_64"
package="$work/$name"
mkdir -p "$package/share"
bash "scripts/$group.sh" "$root" "$work" "$package" "$jobs"
install -m 0644 locks/inputs.json "$package/share/inputs.json"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@1780617600 \
  -czf "$work/$name.tar.gz" -C "$work" "$name"
mv -- "$work/$name.tar.gz" "$root/out/dist/"
