#!/bin/zsh
# Install and start a local-only Qwen3-TTS server compatible with Open Recorder.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
python_command="${OPEN_RECORDER_QWEN_PYTHON:-python3.12}"
runtime_dir="${OPEN_RECORDER_QWEN_RUNTIME_DIR:-$HOME/Library/Application Support/Open Recorder/QwenTTS}"
venv_dir="$runtime_dir/venv"
log_file="$runtime_dir/server.log"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v "$python_command" >/dev/null 2>&1; then
    print -u2 -- 'Python 3.12 is required. Install it with `brew install python@3.12`, then retry.'
    exit 1
fi

if ! command -v sox >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        print -u2 -- 'SoX is required. Install it with `brew install sox`, then retry.'
        exit 1
    fi
    brew install sox
fi

mkdir -p "$runtime_dir"
if [[ ! -x "$venv_dir/bin/python" ]]; then
    "$python_command" -m venv "$venv_dir"
fi

"$venv_dir/bin/python" -m pip install --quiet --upgrade pip
"$venv_dir/bin/python" -m pip install --quiet --upgrade qwen-tts fastapi 'uvicorn[standard]'

if curl --fail --silent http://127.0.0.1:8880/v1/models >/dev/null 2>&1; then
    print -- 'Qwen TTS server is already running on port 8880.'
    exit 0
fi

launchctl bootout "gui/$(id -u)/dev.openrecorder.qwen-tts" 2>/dev/null || true
launchctl submit -l dev.openrecorder.qwen-tts -o "$log_file" -e "$log_file" -- \
    "$venv_dir/bin/python" -m uvicorn qwen_tts_server:app \
    --app-dir "$repo_root/scripts" --host 127.0.0.1 --port 8880

for _ in {1..120}; do
    if curl --fail --silent http://127.0.0.1:8880/v1/models >/dev/null 2>&1; then
        print -- 'Qwen TTS server is ready on http://127.0.0.1:8880.'
        exit 0
    fi
    sleep 1
done

print -u2 -- "Qwen TTS did not start. See $log_file"
exit 1
