#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="Open Recorder"
bundle_dir="$repo_root/release/${app_name}.app"
contents_dir="$bundle_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
swift_binary="$repo_root/apps/macos/.build/debug/OpenRecorderMac"
service_binary="$repo_root/apps/rust-service/target/debug/open-recorder-service"
info_plist="$repo_root/apps/macos/Resources/Info.plist"
icon_source="$repo_root/apps/desktop/icons/icons/mac/icon.icns"

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
	sign_identity="${CODE_SIGN_IDENTITY:-}"
	if [[ -z "$sign_identity" ]] && command -v security >/dev/null 2>&1; then
		sign_identity="$(
			security find-identity -v -p codesigning 2>/dev/null \
				| sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*\([A-Fa-f0-9]\{40,\}\)[[:space:]].*"Developer ID Application:.*/\1/p' \
				| head -n 1
		)"
	fi
	if [[ -z "$sign_identity" ]] && command -v security >/dev/null 2>&1; then
		sign_identity="$(
			security find-identity -v -p codesigning 2>/dev/null \
				| sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*\([A-Fa-f0-9]\{40,\}\)[[:space:]].*"Apple Development:.*/\1/p' \
				| tail -n 1
		)"
	fi
	if [[ -z "$sign_identity" ]]; then
		sign_identity="-"
	fi

	codesign --force --timestamp=none --sign "$sign_identity" "$macos_dir/OpenRecorderMac" >/dev/null
	codesign --force --timestamp=none --sign "$sign_identity" "$macos_dir/open-recorder-service" >/dev/null
	find "$bundle_dir" \( -name '._*' -o -name '.__CodeSignature' \) -delete
	codesign --force --timestamp=none --sign "$sign_identity" "$bundle_dir" >/dev/null
	find "$bundle_dir" \( -name '._*' -o -name '.__CodeSignature' \) -delete
fi

print -- "Packaged $bundle_dir"
