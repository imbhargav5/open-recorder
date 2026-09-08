#!/bin/zsh
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# Pin a real Developer ID identity; never use the development/ad-hoc fallback.
identity_args=(-v -p codesigning)
[[ -z "${OPEN_RECORDER_SIGNING_KEYCHAIN:-}" ]] || identity_args+=("$OPEN_RECORDER_SIGNING_KEYCHAIN")
identities="$(security find-identity "${identity_args[@]}")"
candidates="$(print -r -- "$identities" | grep -F '"Developer ID Application:' || true)"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    candidates="$(print -r -- "$candidates" | grep -F -- "$CODE_SIGN_IDENTITY" || true)"
fi
if [[ -z "$candidates" || "$(print -r -- "$candidates" | wc -l | tr -d ' ')" != 1 ]]; then
    print -u2 -- "Nightly requires one valid Developer ID Application identity with its private key. Import it into Keychain; if multiple exist, select one with CODE_SIGN_IDENTITY."
    exit 1
fi
export CODE_SIGN_IDENTITY="$(print -r -- "$candidates" | sed -n 's/.*"\([^"]*\)".*/\1/p')"
# GitHub uses the existing release secrets; local builds use a Keychain profile.
if [[ -n "${OPEN_RECORDER_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool history --keychain-profile "$OPEN_RECORDER_NOTARY_PROFILE" >/dev/null
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    : # The notarization helper consumes these existing CI credentials.
else
    export OPEN_RECORDER_NOTARY_PROFILE="OpenRecorderNightly"
    xcrun notarytool history --keychain-profile "$OPEN_RECORDER_NOTARY_PROFILE" >/dev/null
fi
for arg in "$@"; do
    case "$arg" in
        --install|--launch) ;;
        *) print -u2 -- "Unknown argument: $arg"; exit 2 ;;
    esac
done
exec zsh "$repo_root/scripts/package-macos-app-shared.zsh" --nightly "$@"
