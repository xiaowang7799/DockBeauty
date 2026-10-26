#!/bin/sh
set -eu
cd "$(dirname "$0")"

if [ "$#" -eq 0 ]; then
    set -- rootless roothide
elif [ "$#" -eq 1 ] && [ "$1" = all ]; then
    set -- rootful rootless roothide
fi

# Validate every scheme before starting a build.
for scheme in "$@"; do
    case "$scheme" in
        rootful|rootless|roothide) ;;
        *) printf 'Unknown scheme: %s\n' "$scheme" >&2; exit 2 ;;
    esac
done

: "${THEOS:?Set THEOS to a compatible Theos toolchain first}"

# 用一个临时产物目录，避免不同 scheme 的 deb 同名互相覆盖。
OUT="$PWD/.pkgs"
rm -rf "$OUT"
mkdir -p "$OUT"

for scheme in "$@"; do
    package_scheme="$scheme"
    if [ "$scheme" = rootful ]; then package_scheme=""; fi
    printf '\nBuilding %s\n' "$scheme"
    make clean THEOS_PACKAGE_SCHEME="$package_scheme" >/dev/null
    make package THEOS_PACKAGE_SCHEME="$package_scheme" >/dev/null
    # 把本次产出的 deb 重命名带上方案后缀，防止覆盖上一轮。
    for deb in ./packages/*.deb; do
        [ -e "$deb" ] || continue
        base="$(basename "$deb")"
        mv "$deb" "$OUT/${scheme}_${base}"
    done
done

mkdir -p ./packages
rm -f ./packages/*.deb
cp "$OUT"/*.deb ./packages/
rm -rf "$OUT"
echo "=== .deb files ==="
find ./packages -name "*.deb" -type f
