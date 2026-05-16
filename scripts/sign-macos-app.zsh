#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_dir="${1:-$repo_root/release/Open Recorder.app}"
entitlements_plist="${OPEN_RECORDER_ENTITLEMENTS_PLIST:-$repo_root/apps/macos/Resources/OpenRecorder.entitlements}"

if [[ ! -d "$bundle_dir" ]]; then
	print -u2 -- "App bundle not found: $bundle_dir"
	exit 1
fi

macos_dir="$bundle_dir/Contents/MacOS"
swift_binary="$macos_dir/OpenRecorderMac"
service_binary="$macos_dir/open-recorder-service"

if [[ ! -f "$swift_binary" ]]; then
	print -u2 -- "App executable not found: $swift_binary"
	exit 1
fi

if [[ ! -f "$service_binary" ]]; then
	print -u2 -- "Service executable not found: $service_binary"
	exit 1
fi

find_codesign_identity() {
	local pattern="$1"
	local line hash name
	line="$(
		security find-identity -v -p codesigning 2>/dev/null \
			| grep -F "\"$pattern" \
			| head -n 1 || true
	)"
	[[ -n "$line" ]] || return 0
	hash="$(print -- "$line" | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*\([A-Fa-f0-9]\{40,\}\).*/\1/p')"
	name="$(print -- "$line" | sed -n 's/.*"\([^"]*\)".*/\1/p')"
	[[ -n "$hash" ]] && print -- "$hash\t$name"
}

resolve_codesign_identity() {
	local explicit_identity="${CODE_SIGN_IDENTITY:-}"
	if [[ -n "$explicit_identity" ]]; then
		print -- "$explicit_identity\t$explicit_identity"
		return
	fi

	local signing_purpose="${OPEN_RECORDER_SIGNING_PURPOSE:-production}"
	if [[ "$signing_purpose" == "production" ]]; then
		local production_developer_id_identity
		production_developer_id_identity="$(find_codesign_identity "Developer ID Application:")"
		if [[ -n "$production_developer_id_identity" ]]; then
			print -- "$production_developer_id_identity"
			return
		fi
	fi

	local dev_identity="${OPEN_RECORDER_DEV_CODESIGN_IDENTITY:-}"
	if [[ -n "$dev_identity" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$dev_identity\""; then
		print -- "$dev_identity\t$dev_identity"
		return
	fi

	local apple_development_identity
	apple_development_identity="$(find_codesign_identity "Apple Development:")"
	if [[ -n "$apple_development_identity" ]]; then
		print -- "$apple_development_identity"
		return
	fi

	# When an Apple development certificate is not available, a stable local
	# certificate keeps macOS TCC grants from being pinned to each rebuilt
	# executable hash.
	local stable_local_identity
	stable_local_identity="$(find_codesign_identity "arni-dev")"
	if [[ -n "$stable_local_identity" ]]; then
		print -- "$stable_local_identity"
		return
	fi

	local developer_id_identity
	developer_id_identity="$(find_codesign_identity "Developer ID Application:")"
	if [[ -n "$developer_id_identity" ]]; then
		print -- "$developer_id_identity"
		return
	fi

	print -- "-\tAd-hoc"
}

clean_signing_metadata() {
	find "$bundle_dir" \( -name '._*' -o -name '.__CodeSignature' \) -delete
}

sign_code() {
	local target="$1"
	shift

	codesign "$@" "$target" >/dev/null
	clean_signing_metadata
	codesign --verify --strict "$target" >/dev/null
}

sign_sparkle_framework() {
	local framework_root="$bundle_dir/Contents/Frameworks/Sparkle.framework"
	[[ -d "$framework_root" ]] || return 0

	local versioned="$framework_root/Versions/B"
	if [[ ! -d "$versioned" ]]; then
		versioned="$(find "$framework_root/Versions" -maxdepth 1 -mindepth 1 -type d ! -name 'Current' -print -quit 2>/dev/null)"
	fi
	[[ -n "$versioned" && -d "$versioned" ]] || return 0

	local nested_targets=(
		"$versioned/XPCServices/Installer.xpc/Contents/MacOS/Installer"
		"$versioned/XPCServices/Installer.xpc"
		"$versioned/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
		"$versioned/XPCServices/Downloader.xpc"
		"$versioned/Updater.app/Contents/MacOS/Updater"
		"$versioned/Updater.app"
		"$versioned/Autoupdate"
		"$framework_root"
	)

	local target
	for target in "${nested_targets[@]}"; do
		if [[ -e "$target" ]]; then
			sign_code "$target" "${codesign_args[@]}"
		fi
	done
}

if command -v codesign >/dev/null 2>&1; then
	identity_line="$(resolve_codesign_identity)"
	sign_identity="${identity_line%%$'\t'*}"
	sign_identity_name="${identity_line#*$'\t'}"

	codesign_args=(--force --options runtime --sign "$sign_identity")
	if [[ "$sign_identity_name" == Developer\ ID\ Application:* ]]; then
		codesign_args+=(--timestamp)
	else
		codesign_args+=(--timestamp=none)
	fi
	app_codesign_args=("${codesign_args[@]}")
	if [[ -f "$entitlements_plist" ]]; then
		app_codesign_args+=(--entitlements "$entitlements_plist")
	fi

	sign_sparkle_framework
	sign_code "$service_binary" "${codesign_args[@]}"
	sign_code "$swift_binary" "${app_codesign_args[@]}"
	sign_code "$bundle_dir" "${app_codesign_args[@]}"
	print -- "Signed $bundle_dir with $sign_identity_name"
else
	print -- "codesign not found; leaving $bundle_dir unsigned"
fi
