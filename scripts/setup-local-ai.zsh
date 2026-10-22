#!/bin/zsh
# Set up the optional local-AI caption cleanup stack and the required Whisper helper.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
model="${OPEN_RECORDER_OLLAMA_MODEL:-llama3.2:3b}"
speech_model_url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
speech_model_sha256="60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
caption_model_dir="${OPEN_RECORDER_CAPTION_MODEL_DIR:-$HOME/Library/Application Support/Open Recorder/CaptionModels}"
speech_model_path="$caption_model_dir/ggml-base.bin"

if ! command -v cmake >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        print -u2 -- 'CMake is required. Install CMake, then re-run this script.'
        exit 1
    fi
    brew install cmake
fi

if ! command -v ollama >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        print -u2 -- 'Ollama is optional but unavailable. Install it from https://ollama.com/download, then re-run this script.'
        exit 1
    fi
    brew install ollama
fi

if command -v brew >/dev/null 2>&1; then
    brew services start ollama >/dev/null 2>&1 || true
fi

for _ in {1..15}; do
    if ollama list >/dev/null 2>&1; then break; fi
    sleep 1
done
if ! ollama list >/dev/null 2>&1; then
    print -u2 -- 'Ollama did not start. Run `ollama serve` in another terminal, then re-run this script.'
    exit 1
fi

zsh "$repo_root/scripts/build-caption-helper.zsh"
ollama pull "$model"

if [[ ! -f "$speech_model_path" ]] || [[ "$(shasum -a 256 "$speech_model_path" | awk '{print $1}')" != "$speech_model_sha256" ]]; then
    mkdir -p "$caption_model_dir"
    temporary_model="$(mktemp "${TMPDIR:-/tmp}/open-recorder-whisper.XXXXXX")"
    trap 'rm -f "$temporary_model"' EXIT
    curl --fail --location --progress-bar "$speech_model_url" --output "$temporary_model"
    if [[ "$(shasum -a 256 "$temporary_model" | awk '{print $1}')" != "$speech_model_sha256" ]]; then
        print -u2 -- 'Downloaded Whisper model failed SHA-256 verification.'
        exit 1
    fi
    mv "$temporary_model" "$speech_model_path"
    trap - EXIT
fi

print -- "Local AI is ready: Whisper captions and Ollama model $model."
