#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_variant="production"
install=false
launch=false

for arg in "$@"; do
	case "$arg" in
		--dev)
			app_variant="development"
			;;
		--production)
			app_variant="production"
			;;
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

if [[ "$app_variant" == "development" ]]; then
	app_name="${OPEN_RECORDER_DEV_APP_NAME:-Open Recorder Dev}"
	bundle_identifier="${OPEN_RECORDER_DEV_BUNDLE_IDENTIFIER:-dev.openrecorder.app.dev}"
else
	app_name="${OPEN_RECORDER_APP_NAME:-Open Recorder}"
	bundle_identifier="${OPEN_RECORDER_BUNDLE_IDENTIFIER:-dev.openrecorder.app}"
fi

bundle_dir="$repo_root/release/${app_name}.app"
contents_dir="$bundle_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
swift_binary="$repo_root/apps/macos/.build/debug/OpenRecorderMac"
swift_resource_bundle_name="OpenRecorderMac_OpenRecorderMac.bundle"
swift_resource_bundle="$repo_root/apps/macos/.build/debug/$swift_resource_bundle_name"
service_binary="$repo_root/apps/rust-service/target/debug/open-recorder-service"
info_plist="$repo_root/apps/macos/Resources/Info.plist"
icon_source="$repo_root/apps/macos/Resources/AppIcon.icns"

set_plist_string() {
	local key="$1"
	local value="$2"

	if /usr/libexec/PlistBuddy -c "Print :$key" "$contents_dir/Info.plist" >/dev/null 2>&1; then
		/usr/libexec/PlistBuddy -c "Set :$key $value" "$contents_dir/Info.plist"
	else
		/usr/libexec/PlistBuddy -c "Add :$key string $value" "$contents_dir/Info.plist"
	fi
}

cd "$repo_root/apps/rust-service"
CARGO_INCREMENTAL=0 cargo build

cd "$repo_root/apps/macos"
swift build

if [[ ! -d "$swift_resource_bundle" ]]; then
	swift_resource_bundle="$(find "$repo_root/apps/macos/.build" -type d -name "$swift_resource_bundle_name" -print -quit)"
fi

if [[ ! -d "$swift_resource_bundle" ]]; then
	print -u2 -- "Swift resource bundle not found: $swift_resource_bundle_name"
	exit 1
fi

rm -rf "$bundle_dir"
mkdir -p "$macos_dir" "$resources_dir"

cp "$swift_binary" "$macos_dir/OpenRecorderMac"
cp "$service_binary" "$macos_dir/open-recorder-service"
cp "$info_plist" "$contents_dir/Info.plist"
cp -R "$swift_resource_bundle" "$resources_dir/"
set_plist_string "CFBundleName" "$app_name"
set_plist_string "CFBundleDisplayName" "$app_name"
set_plist_string "CFBundleIdentifier" "$bundle_identifier"

if [[ -f "$icon_source" ]]; then
	cp "$icon_source" "$resources_dir/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$contents_dir/Info.plist"
fi

chmod +x "$macos_dir/OpenRecorderMac" "$macos_dir/open-recorder-service"
find "$bundle_dir" \( -name '._*' -o -name '.__CodeSignature' \) -delete
OPEN_RECORDER_SIGNING_PURPOSE="$app_variant" zsh "$repo_root/scripts/sign-macos-app.zsh" "$bundle_dir"

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
