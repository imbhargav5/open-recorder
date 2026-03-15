#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec node "$script_dir/dispatch-release-build.mjs" "$@"
