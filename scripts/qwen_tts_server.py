#!/usr/bin/env python3
"""Local-only OpenAI-compatible adapter for the official Qwen3-TTS package."""

from __future__ import annotations

import io
import os
import base64
from contextlib import asynccontextmanager

# launchd starts with a minimal PATH; make Homebrew's SoX visible before Qwen imports.
os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + os.environ.get("PATH", "")

import soundfile as sf
import torch
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field
from qwen_tts import Qwen3TTSModel

MODEL_ID = os.environ.get("OPEN_RECORDER_QWEN_TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice")
CLONE_MODEL_ID = os.environ.get("OPEN_RECORDER_QWEN_TTS_CLONE_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-Base")


class SpeechRequest(BaseModel):
    model: str = MODEL_ID
    input: str = Field(min_length=1)
    voice: str = "Vivian"
    language: str = "English"
    response_format: str = "wav"
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    reference_audio_b64: str | None = None
    reference_text: str | None = None


def load_model() -> Qwen3TTSModel:
    # MPS float16 can produce NaNs and MPS bfloat16 can produce corrupted audio
    # in Qwen's autoregressive decoder. Use full-precision CPU inference until
    # the upstream MPS path is reliable; it is slower but produces valid speech.
    device = "cpu"
    dtype = torch.float32
    return Qwen3TTSModel.from_pretrained(MODEL_ID, device_map=device, dtype=dtype)


def clone_model(app: FastAPI) -> Qwen3TTSModel:
    model = getattr(app.state, "clone_model", None)
    if model is None:
        # Downloaded only when the user actually selects Custom voice.
        model = Qwen3TTSModel.from_pretrained(CLONE_MODEL_ID, device_map="cpu", dtype=torch.float32)
        app.state.clone_model = model
    return model


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.model = load_model()
    yield
    del app.state.model


app = FastAPI(title="Open Recorder local Qwen3-TTS", lifespan=lifespan)


@app.get("/v1/models")
def models() -> dict[str, list[dict[str, str]]]:
    return {"data": [{"id": MODEL_ID, "object": "model"}]}


@app.post("/v1/audio/speech")
def speech(request: SpeechRequest) -> Response:
    if request.response_format.lower() != "wav":
        raise HTTPException(status_code=400, detail="Only WAV output is supported.")
    if request.model != MODEL_ID:
        raise HTTPException(status_code=404, detail=f"Model {request.model!r} is not loaded.")
    try:
        if request.reference_audio_b64:
            reference = base64.b64decode(request.reference_audio_b64)
            samples, sample_rate = sf.read(io.BytesIO(reference), always_2d=False)
            # 30 seconds is a strong quality/speed balance for a local clone.
            samples = samples[: int(sample_rate * 30)]
            wavs, sample_rate = clone_model(app).generate_voice_clone(
                text=request.input,
                language=request.language,
                ref_audio=(samples, sample_rate),
                ref_text=request.reference_text or None,
                x_vector_only_mode=not bool(request.reference_text and request.reference_text.strip()),
            )
        else:
            wavs, sample_rate = app.state.model.generate_custom_voice(
                text=request.input,
                language=request.language,
                speaker=request.voice,
            )
        audio = io.BytesIO()
        sf.write(audio, wavs[0], sample_rate, format="WAV")
        return Response(content=audio.getvalue(), media_type="audio/wav")
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
