#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/prepare-toolchain.sh
build_args=(-c release --product AgentPace --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)
case "${1:-}" in
    "") architectures=("$(uname -m)") ;;
    --universal) architectures=(arm64 x86_64) ;;
    *) printf 'Usage: bash scripts/build.sh [--universal]\n' >&2; exit 2 ;;
esac
binaries=()
for architecture in "${architectures[@]}"; do
    swift build "${build_args[@]}" --arch "$architecture"
    binary_dir="$(swift build "${build_args[@]}" --arch "$architecture" --show-bin-path)"
    binaries+=("$binary_dir/AgentPace")
done

# Assemble and sign outside iCloud-synced folders, which can add Finder metadata.
staging="$(mktemp -d "${TMPDIR:-/tmp/}AgentPace.build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Agent Pace.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "${#binaries[@]}" -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/AgentPace"
else
    cp "${binaries[0]}" "$app/Contents/MacOS/AgentPace"
fi
strip -S "$app/Contents/MacOS/AgentPace"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset" "$app/Contents/Resources/AppIcon.icns"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p dist
ditto --norsrc --noextattr "$app" "$PWD/dist/Agent Pace.app"
printf '已构建：%s\n' "$PWD/dist/Agent Pace.app"
