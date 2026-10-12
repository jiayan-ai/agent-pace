#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
record="$PWD/dist/notarization/$version"
profile="${AGENT_PACE_NOTARY_PROFILE:-agent-pace-notary}"
archive="Agent-Pace-$version-universal-notarized.zip"
case "$mode" in
    submit)
        if [[ -z "${AGENT_PACE_SIGN_IDENTITY:-}" || "$AGENT_PACE_SIGN_IDENTITY" == - ]]; then
            printf '请先设置 AGENT_PACE_SIGN_IDENTITY 为 Developer ID Application 名称或 SHA-1。\n' >&2
            exit 1
        fi
        bash scripts/sign-app.sh --check
        if [[ -e "$record/submission.json" ]]; then
            printf '此版本已有提交记录，请先运行 status，勿重复提交。\n' >&2
            exit 1
        fi
        # Validate the named local profile before spending time on a build.
        xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
        bash scripts/build.sh --universal
        staging="$(mktemp -d "${TMPDIR:-/tmp/}AgentPace.notary.XXXXXX")"
        trap 'rm -rf "$staging"' EXIT
        ditto --norsrc --noextattr 'dist/Agent Pace.app' "$staging/Agent Pace.app"
        xattr -cr "$staging/Agent Pace.app"
        codesign --verify --deep --strict "$staging/Agent Pace.app"
        mkdir -p "$record"
        ditto -c -k --keepParent --norsrc --noextattr "$staging/Agent Pace.app" "$record/upload.zip"
        (cd "$record" && shasum -a 256 upload.zip > upload.zip.sha256)
        # No passwords or private keys are passed as command-line arguments.
        # Preserve even an incomplete response so an unknown outcome is audited.
        xcrun notarytool submit "$record/upload.zip" --keychain-profile "$profile" \
            --no-wait --output-format json > "$record/submission.json"
        plutil -extract id raw "$record/submission.json"
        printf '已提交；稍后运行 bash scripts/notarize-release.sh status。\n'
        ;;
    status|finish)
        if [[ ! -s "$record/submission.json" ]]; then
            printf '没有完整提交记录。如曾上传中断，请先用 notarytool history 核实，勿直接重传。\n' >&2
            exit 1
        fi
        submission_id="$(plutil -extract id raw "$record/submission.json")"
        xcrun notarytool info "$submission_id" --keychain-profile "$profile" \
            --output-format json > "$record/status.json"
        status="$(plutil -extract status raw "$record/status.json")"
        printf '公证状态：%s\n' "$status"
        if [[ "$mode" == status ]]; then exit 0; fi
        if [[ "$status" != Accepted ]]; then
            if [[ "$status" == Invalid || "$status" == Rejected ]]; then
                xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$record/log.json"
                printf '请查看 %s/log.json\n' "$record" >&2
            fi
            exit 1
        fi
        (cd "$record" && shasum -a 256 -c upload.zip.sha256)
        staging="$(mktemp -d "${TMPDIR:-/tmp/}AgentPace.staple.XXXXXX")"
        trap 'rm -rf "$staging"' EXIT
        # Staple the exact submitted app, never a later rebuild.
        ditto -x -k "$record/upload.zip" "$staging"
        app="$staging/Agent Pace.app"
        xcrun stapler staple "$app"
        xcrun stapler validate "$app"
        codesign --verify --deep --strict "$app"
        spctl --assess --type execute --verbose=2 "$app"
        ditto -c -k --keepParent --norsrc --noextattr "$app" "$staging/$archive"
        cp "$staging/$archive" "dist/$archive"
        (cd dist && shasum -a 256 "$archive" > "$archive.sha256")
        printf '签名及公证验证通过：%s/dist/%s\n' "$PWD" "$archive"
        ;;
    *) printf 'Usage: bash scripts/notarize-release.sh submit | status | finish\n' >&2; exit 2 ;;
esac
