#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/prepare-toolchain.sh
swift run --disable-sandbox \
    --cache-path .build/cache --config-path .build/config --security-path .build/security PaceCoreChecks
