.PHONY: setup build-macos dev-macos package-macos package-macos-dev install-macos install-macos-dev run-macos run-macos-dev reset-macos-permissions reset-macos-dev-permissions test-macos clean-macos

RUST_SERVICE := $(CURDIR)/apps/rust-service/target/debug/open-recorder-service

setup:
	pnpm install --frozen-lockfile
	pnpm --dir apps/landing install --frozen-lockfile
	cargo fetch --locked --manifest-path apps/rust-service/Cargo.toml

build-macos:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo build
	cd apps/macos && swift build

dev-macos: run-macos-dev

package-macos:
	zsh scripts/package-macos-production-app.zsh

package-macos-dev:
	zsh scripts/package-macos-development-app.zsh

install-macos:
	zsh scripts/package-macos-production-app.zsh --install

install-macos-dev:
	zsh scripts/package-macos-development-app.zsh --install

run-macos:
	zsh scripts/package-macos-production-app.zsh --install --launch

run-macos-dev:
	zsh scripts/package-macos-development-app.zsh --install --launch

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

.PHONY: test-macos-release
test-macos-release:
	cd apps/rust-service && CARGO_INCREMENTAL=0 cargo test --release
	cd apps/macos && swift test -c release -Xswiftc -DOPEN_RECORDER_TESTING

.PHONY: package-macos-nightly install-macos-nightly run-macos-nightly
package-macos-nightly:
	zsh scripts/package-macos-nightly-app.zsh

install-macos-nightly:
	zsh scripts/package-macos-nightly-app.zsh --install

run-macos-nightly:
	zsh scripts/package-macos-nightly-app.zsh --install --launch
