#!/bin/zsh

set -euo pipefail

certificate_base64="${CSC_LINK:-}"
certificate_password="${CSC_KEY_PASSWORD:-}"
requested_identity="${CODE_SIGN_IDENTITY:-${CSC_NAME:-}}"
runner_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
keychain_path="$runner_temp/open-recorder-signing.keychain-db"
certificate_path="$runner_temp/open-recorder-signing.p12"
keychain_password="$(uuidgen)"

die() {
	print -u2 -- "Error: $*"
	exit 1
}

find_developer_id_identity() {
	local filter="${1:-}"
	local line

	if [[ -n "$filter" ]]; then
		line="$(
			security find-identity -v -p codesigning "$keychain_path" 2>/dev/null \
				| grep -F '"Developer ID Application:' \
				| grep -F "$filter" \
				| head -n 1 || true
		)"
	else
		line="$(
			security find-identity -v -p codesigning "$keychain_path" 2>/dev/null \
				| grep -F '"Developer ID Application:' \
				| head -n 1 || true
		)"
	fi

	[[ -n "$line" ]] || return 0
	print -- "$line" | sed -n 's/.*"\([^"]*\)".*/\1/p'
}

[[ -n "$certificate_base64" ]] || die "Missing CSC_LINK or APPLE_CERTIFICATE secret."
[[ -n "$certificate_password" ]] || die "Missing CSC_KEY_PASSWORD or APPLE_CERTIFICATE_PASSWORD secret."

rm -f "$keychain_path" "$certificate_path"
print -rn -- "$certificate_base64" | openssl base64 -d -A -out "$certificate_path"

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" \
	-k "$keychain_path" \
	-P "$certificate_password" \
	-T /usr/bin/codesign \
	-T /usr/bin/security \
	-T /usr/bin/xcrun >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
existing_keychains=("${(@f)$(security list-keychains -d user | sed 's/[ "]//g')}")
security list-keychains -d user -s "$keychain_path" "${existing_keychains[@]}"
security default-keychain -s "$keychain_path"

if [[ "$requested_identity" == Developer\ ID\ Application:* ]]; then
	signing_identity="$(find_developer_id_identity "$requested_identity")"
elif [[ -n "$requested_identity" ]]; then
	signing_identity="$(find_developer_id_identity "$requested_identity")"
else
	signing_identity="$(find_developer_id_identity)"
fi

[[ -n "${signing_identity:-}" ]] || die "No Developer ID Application identity was found after importing CSC_LINK."

print -- "Imported macOS signing certificate: $signing_identity"
if [[ -n "${GITHUB_ENV:-}" ]]; then
	print -- "CODE_SIGN_IDENTITY=$signing_identity" >> "$GITHUB_ENV"
	print -- "OPEN_RECORDER_SIGNING_KEYCHAIN=$keychain_path" >> "$GITHUB_ENV"
fi
