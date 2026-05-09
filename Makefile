.PHONY: build-macos dev-macos package-macos package-macos-dev install-macos install-macos-dev run-macos run-macos-dev reset-macos-permissions reset-macos-dev-permissions test-macos clean-macos

RUST_SERVICE := $(CURDIR)/apps/rust-service/target/debug/open-recorder-service

build-macos:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo build
	cd apps/macos && swift build

dev-macos: run-macos-dev

package-macos:
	zsh scripts/package-macos-app.zsh

package-macos-dev:
	zsh scripts/package-macos-app.zsh --dev

install-macos:
	zsh scripts/package-macos-app.zsh --install

install-macos-dev:
	zsh scripts/package-macos-app.zsh --dev --install

run-macos:
	zsh scripts/package-macos-app.zsh --install --launch

run-macos-dev:
	zsh scripts/package-macos-app.zsh --dev --install --launch

reset-macos-permissions:
	tccutil reset ScreenCapture dev.openrecorder.app
	tccutil reset Microphone dev.openrecorder.app

reset-macos-dev-permissions:
	tccutil reset ScreenCapture dev.openrecorder.app.dev
	tccutil reset Microphone dev.openrecorder.app.dev

test-macos:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo test
	cd apps/macos && swift test

clean-macos:
	cd apps/rust-service && cargo clean
	cd apps/macos && swift package clean
