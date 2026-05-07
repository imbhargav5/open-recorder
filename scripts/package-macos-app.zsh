#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="Open Recorder"
bundle_dir="$repo_root/release/${app_name}.app"
install=false
launch=false

for arg in "$@"; do
	case "$arg" in
		--install)
			install=true
			;;
		--launch)
			launch=true
			;;
		*)
			print -u2 -- "Unknown argument: $arg"
			exit 2
			;;
	esac
done

contents_dir="$bundle_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
swift_binary="$repo_root/apps/macos/.build/debug/OpenRecorderMac"
service_binary="$repo_root/apps/rust-service/target/debug/open-recorder-service"
info_plist="$repo_root/apps/macos/Resources/Info.plist"
entitlements_plist="$repo_root/apps/macos/Resources/OpenRecorder.entitlements"
icon_source="$repo_root/apps/desktop/icons/icons/mac/icon.icns"

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

	# Match the previous Electron/Tauri dev workflow when an Apple development
	# certificate is not available: a stable local certificate keeps macOS TCC
	# grants from being pinned to each rebuilt executable hash.
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

cd "$repo_root/apps/rust-service"
CARGO_INCREMENTAL=0 cargo build

cd "$repo_root/apps/macos"
swift build

rm -rf "$bundle_dir"
mkdir -p "$macos_dir" "$resources_dir"

cp "$swift_binary" "$macos_dir/OpenRecorderMac"
cp "$service_binary" "$macos_dir/open-recorder-service"
cp "$info_plist" "$contents_dir/Info.plist"

if [[ -f "$icon_source" ]]; then
	cp "$icon_source" "$resources_dir/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$contents_dir/Info.plist"
fi

chmod +x "$macos_dir/OpenRecorderMac" "$macos_dir/open-recorder-service"
find "$bundle_dir" \( -name '._*' -o -name '.__CodeSignature' \) -delete

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

	codesign "${app_codesign_args[@]}" "$macos_dir/OpenRecorderMac" >/dev/null
	codesign "${codesign_args[@]}" "$macos_dir/open-recorder-service" >/dev/null
	find "$bundle_dir" \( -name '._*' -o -name '.__CodeSignature' \) -delete
	codesign "${app_codesign_args[@]}" "$bundle_dir" >/dev/null
	find "$bundle_dir" \( -name '._*' -o -name '.__CodeSignature' \) -delete
	print -- "Signed with $sign_identity_name"
fi

print -- "Packaged $bundle_dir"

if [[ "$install" == true ]]; then
	install_dir="${OPEN_RECORDER_INSTALL_DIR:-/Applications}"
	installed_bundle="$install_dir/${app_name}.app"
	temp_bundle="$install_dir/.${app_name}.app.installing.$$"

	rm -rf "$temp_bundle"
	ditto "$bundle_dir" "$temp_bundle"
	find "$temp_bundle" \( -name '._*' -o -name '.__CodeSignature' \) -delete
	xattr -dr com.apple.quarantine "$temp_bundle" 2>/dev/null || true
	rm -rf "$installed_bundle"
	mv "$temp_bundle" "$installed_bundle"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed_bundle" 2>/dev/null || true
	print -- "Installed $installed_bundle"

	if [[ "$launch" == true ]]; then
		open -n "$installed_bundle"
	fi
elif [[ "$launch" == true ]]; then
	open -n "$bundle_dir"
fi
