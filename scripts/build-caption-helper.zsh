#!/bin/zsh
# Build the pinned local speech helper. No speech models are downloaded by packaging.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
whisper_revision=2eeeba56e9edd762b4b38467bab96c2517163158 # whisper.cpp v1.8.3
caption_arch="${CAPTION_HELPER_ARCH:-$(uname -m)}"
source_dir="$repo_root/apps/macos/.build/whisper-source"
build_dir="${CAPTION_HELPER_BUILD_DIR:-$repo_root/apps/macos/.build/caption-helper}"
cmake_command="${CMAKE_COMMAND:-cmake}"
if ! command -v "$cmake_command" >/dev/null 2>&1; then
    print -u2 -- 'CMake is required to build captions. Install CMake, then retry packaging.'
    exit 1
fi
mkdir -p "$repo_root/apps/macos/.build"
if [[ ! -d "$source_dir/.git" ]]; then
    git clone --no-checkout https://github.com/ggml-org/whisper.cpp.git "$source_dir"
fi
if ! git -C "$source_dir" cat-file -e "$whisper_revision^{commit}" 2>/dev/null; then
    git -C "$source_dir" fetch origin "$whisper_revision"
fi
git -C "$source_dir" checkout --detach "$whisper_revision"
"$cmake_command" -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$caption_arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON \
    -DGGML_NATIVE=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
"$cmake_command" --build "$build_dir" --config Release --target whisper-cli --parallel 4
cp "$source_dir/LICENSE" "$build_dir/whisper-LICENSE"
print -- "Built $build_dir/bin/whisper-cli ($caption_arch)"
