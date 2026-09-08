#!/bin/zsh

set -euo pipefail

bundle_dir="${1:-}"
apple_id="${APPLE_ID:-}"
apple_password="${APPLE_APP_SPECIFIC_PASSWORD:-}"
apple_team_id="${APPLE_TEAM_ID:-}"
notary_profile="${OPEN_RECORDER_NOTARY_PROFILE:-}"
notary_max_attempts="${NOTARYTOOL_MAX_ATTEMPTS:-3}"
notary_retry_delay_seconds="${NOTARYTOOL_RETRY_DELAY_SECONDS:-15}"

die() {
	print -u2 -- "Error: $*"
	exit 1
}

submit_for_notarization() {
	local file_path="$1"
	local attempt=1
	local delay_seconds="$notary_retry_delay_seconds"
	local exit_status=0

	while (( attempt <= notary_max_attempts )); do
		print -- "Submitting $(basename "$file_path") for notarization (attempt ${attempt}/${notary_max_attempts})"
		if xcrun notarytool submit "$file_path" \
            "${notary_auth[@]}" \
			--wait --output-format json >"$tmp_dir/notary-result.json"; then
            if [[ "$(/usr/bin/plutil -extract status raw -o - "$tmp_dir/notary-result.json")" == "Accepted" ]]; then
                return 0
            fi
            print -u2 -- "Apple did not accept notarization."
            cat "$tmp_dir/notary-result.json" >&2
            return 1
        else
            exit_status=$?
        fi
		if (( attempt == notary_max_attempts )); then
			print -u2 -- "Notarization failed after ${notary_max_attempts} attempts."
			return "$exit_status"
		fi

		print -u2 -- "Notarization attempt ${attempt}/${notary_max_attempts} failed; retrying in ${delay_seconds}s."
		sleep "$delay_seconds"
		attempt=$(( attempt + 1 ))
		delay_seconds=$(( delay_seconds * 2 ))
	done
}

[[ -n "$bundle_dir" && -d "$bundle_dir" ]] || die "Usage: zsh scripts/notarize-macos-production-app.zsh PATH_TO_APP"
if [[ -n "$notary_profile" ]]; then
    notary_auth=(--keychain-profile "$notary_profile")
else
    [[ -n "$apple_id" ]] || die "Missing APPLE_ID secret."
    [[ -n "$apple_password" ]] || die "Missing APPLE_APP_SPECIFIC_PASSWORD secret."
    [[ -n "$apple_team_id" ]] || die "Missing APPLE_TEAM_ID secret."
    notary_auth=(--apple-id "$apple_id" --password "$apple_password" --team-id "$apple_team_id")
fi
[[ "$notary_max_attempts" == <-> && "$notary_max_attempts" -ge 1 ]] || die "NOTARYTOOL_MAX_ATTEMPTS must be a positive integer."
[[ "$notary_retry_delay_seconds" == <-> ]] || die "NOTARYTOOL_RETRY_DELAY_SECONDS must be a non-negative integer."

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

notary_zip="$tmp_dir/$(basename "$bundle_dir").zip"
ditto -c -k --keepParent "$bundle_dir" "$notary_zip"

submit_for_notarization "$notary_zip"

xcrun stapler staple "$bundle_dir"
xcrun stapler validate "$bundle_dir"
spctl -a -vv -t exec "$bundle_dir"

print -- "Notarized and stapled $bundle_dir"
