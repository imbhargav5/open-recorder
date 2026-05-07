.PHONY: build-macos dev-macos package-macos install-macos run-macos reset-macos-permissions test-macos clean-macos

RUST_SERVICE := $(CURDIR)/apps/rust-service/target/debug/open-recorder-service

build-macos:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo build
	cd apps/macos && swift build

dev-macos: install-macos
	open -n "/Applications/Open Recorder.app"

package-macos:
	zsh scripts/package-macos-app.zsh

install-macos:
	zsh scripts/package-macos-app.zsh --install

run-macos:
	zsh scripts/package-macos-app.zsh --install --launch

reset-macos-permissions:
	tccutil reset ScreenCapture dev.openrecorder.app
	tccutil reset Microphone dev.openrecorder.app

test-macos:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo test
	cd apps/macos && swift test

clean-macos:
	cd apps/rust-service && cargo clean
	cd apps/macos && swift package clean
