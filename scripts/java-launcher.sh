#!/usr/bin/env bash
set -euo pipefail
launcher=$(realpath -- "$0")
tool=${launcher##*/}
root=$(cd -- "$(dirname -- "$launcher")/.." && pwd)
java_args=()
while [[ ${1-} == -J* ]]; do
  option=${1#-J}
  java_args+=("-${option#-}")
  shift
done
java=${JAVA_HOME:+$JAVA_HOME/bin/}java
exec "$java" "${java_args[@]}" -jar "$root/framework/$tool.jar" "$@"
