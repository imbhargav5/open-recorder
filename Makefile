.PHONY: build-macos dev-macos package-macos test-macos clean-macos

RUST_SERVICE := $(CURDIR)/apps/rust-service/target/debug/open-recorder-service

build-macos:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo build
	cd apps/macos && swift build

dev-macos: build-macos
	cd apps/macos && OPEN_RECORDER_SERVICE_PATH="$(RUST_SERVICE)" swift run OpenRecorderMac

package-macos:
	zsh scripts/package-macos-app.zsh

test-macos:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo test
	cd apps/macos && swift test

clean-macos:
	cd apps/rust-service && cargo clean
	cd apps/macos && swift package clean
