#!/bin/zsh

set -euo pipefail

bundle_dir="${1:-}"
expected_team_id="${APPLE_TEAM_ID:-}"

if [[ -z "$bundle_dir" || ! -d "$bundle_dir" ]]; then
	print -u2 -- "Usage: zsh scripts/verify-macos-signature.zsh PATH_TO_APP"
	exit 2
fi

signature_details="$(codesign -dv --verbose=4 "$bundle_dir" 2>&1)"
print -- "$signature_details"

codesign --verify --strict --verbose=2 "$bundle_dir"

if print -- "$signature_details" | grep -Fq "Signature=adhoc"; then
	print -u2 -- "Expected a Developer ID signature, got an ad-hoc signature."
	exit 1
fi

if ! print -- "$signature_details" | grep -Fq "Authority=Developer ID Application:"; then
	print -u2 -- "Expected a Developer ID Application authority."
	exit 1
fi

if [[ -n "$expected_team_id" ]] && ! print -- "$signature_details" | grep -Fq "TeamIdentifier=$expected_team_id"; then
	print -u2 -- "Expected TeamIdentifier=$expected_team_id."
	exit 1
fi

print -- "Verified Developer ID signature for $bundle_dir"
