#!/bin/sh
set -eu
cd "$(dirname "$0")"

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[ -n "$sdk" ] || { echo "set ANDROID_HOME to an Android SDK" >&2; exit 1; }

d8=$(find "$sdk/build-tools" -name d8 -type f 2>/dev/null | sort -V | tail -n 1)
jar=$(find "$sdk/platforms" -name android.jar -type f 2>/dev/null | sort -V | tail -n 1)
[ -n "$d8" ] && [ -n "$jar" ] || { echo "no d8 or android.jar under $sdk" >&2; exit 1; }

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

javac -source 8 -target 8 -bootclasspath "$jar" -d "$out" Notify.java
"$d8" --min-api 34 --lib "$jar" --output "$out" "$out/Notify.class"
cp "$out/classes.dex" ../src/notify.dex
echo "wrote ../src/notify.dex"
