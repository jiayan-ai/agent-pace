#!/bin/bash
# Sourced by build/test. Keep all compiler caches inside this project.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache"

# Some Command Line Tools upgrades leave a Swift 5 private PackageDescription
# interface beside a Swift 6 library. Use the matching public interface locally;
# never modify the installed developer tools.
toolchain_root="$(xcode-select -p)/usr/lib/swift/pm/ManifestAPI"
arch="$(uname -m)"
public_interface="$toolchain_root/PackageDescription.swiftmodule/$arch-apple-macos.swiftinterface"
private_interface="$toolchain_root/PackageDescription.swiftmodule/$arch-apple-macos.private.swiftinterface"
if [[ -f "$public_interface" && -f "$private_interface" ]] &&
    grep -q 'public enum SwiftLanguageMode' "$public_interface" &&
    grep -q 'public enum SwiftVersion' "$private_interface"; then
    local_manifest="$PWD/.build/SwiftPM/ManifestAPI"
    mkdir -p "$local_manifest/PackageDescription.swiftmodule"
    cp "$public_interface" "$local_manifest/PackageDescription.swiftmodule/"
    ln -sf "$toolchain_root/libPackageDescription.dylib" "$local_manifest/libPackageDescription.dylib"
    export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/SwiftPM"
fi
