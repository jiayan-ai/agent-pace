#!/bin/bash
set -euo pipefail
identity="${AGENT_PACE_SIGN_IDENTITY:--}"
if [[ "$identity" != - ]]; then
    # Accept an exact certificate name or SHA-1 identity, never a broad match.
    identities="$(security find-identity -v -p codesigning)"
    matches="$(printf '%s\n' "$identities" | awk -v wanted="$identity" '
        /Developer ID Application:/ {
            name=$0; sub(/^[^"]*"/, "", name); sub(/".*$/, "", name)
            if ($2 == wanted || name == wanted) count++
        }
        END { print count+0 }')"
    if [[ "$matches" != 1 ]]; then
        printf '需要唯一、有效且带私钥的 Developer ID Application 证书。\n' >&2
        exit 1
    fi
fi
if [[ "${1:-}" == --check ]]; then exit 0; fi
app="${1:?Usage: bash scripts/sign-app.sh APP_PATH | --check}"
if [[ "$identity" == - ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --sign "$identity" --options runtime --timestamp "$app"
fi
codesign --verify --deep --strict "$app"
