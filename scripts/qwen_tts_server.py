#!/usr/bin/env python3
"""Local-only OpenAI-compatible adapter for the official Qwen3-TTS package."""

from __future__ import annotations

import io
import os
import base64
import gc
from contextlib import asynccontextmanager

# launchd starts with a minimal PATH; make Homebrew's SoX visible before Qwen imports.
os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + os.environ.get("PATH", "")

import soundfile as sf
import torch
import torch.nn.functional as F
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


def load_model(model_id: str) -> Qwen3TTSModel:
    # MPS float16 can produce NaNs and MPS bfloat16 can produce corrupted audio
    # in Qwen's autoregressive decoder. Use full-precision CPU inference until
    # the upstream MPS path is reliable; it is slower but produces valid speech.
    device = "cpu"
    dtype = torch.float32
    return Qwen3TTSModel.from_pretrained(model_id, device_map=device, dtype=dtype)


def unload_model(app: FastAPI, attribute: str) -> None:
    """Keep one Qwen checkpoint resident on a local Mac at a time.

    Loading CustomVoice and Base together can exhaust unified memory before the
    clone request begins. Switching is slower than keeping both warm, but is
    reliable on ordinary developer machines.
    """
    model = getattr(app.state, attribute, None)
    if model is not None:
        delattr(app.state, attribute)
        del model
        gc.collect()


def custom_model(app: FastAPI) -> Qwen3TTSModel:
    model = getattr(app.state, "custom_model", None)
    if model is None:
        unload_model(app, "clone_model")
        model = load_model(MODEL_ID)
        app.state.custom_model = model
    return model


def clone_model(app: FastAPI) -> Qwen3TTSModel:
    model = getattr(app.state, "clone_model", None)
    if model is None:
        # A clone uses the Base checkpoint, not the CustomVoice checkpoint.
        # Release the normal TTS model first so both models are never resident.
        unload_model(app, "custom_model")
        model = load_model(CLONE_MODEL_ID)
        app.state.clone_model = model
    return model


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    unload_model(app, "custom_model")
    unload_model(app, "clone_model")


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
            reference = base64.b64decode(request.reference_audio_b64, validate=True)
            samples, sample_rate = sf.read(io.BytesIO(reference), always_2d=False)
            if getattr(samples, "ndim", 1) > 1:
                # A reference must describe one speaker, not a stereo soundstage.
                samples = samples.mean(axis=1)
            if sample_rate != 24_000:
                # The speaker encoder is trained on 24 kHz mel features. Do the
                # conversion here for imported WAVs instead of relying on a
                # platform decoder or silently passing mismatched samples.
                waveform = torch.as_tensor(samples, dtype=torch.float32).reshape(1, 1, -1)
                target_frames = round(waveform.shape[-1] * 24_000 / sample_rate)
                samples = F.interpolate(waveform, size=target_frames, mode="linear", align_corners=False).reshape(-1).numpy()
                sample_rate = 24_000
            if len(samples) < sample_rate * 3:
                raise ValueError("A custom voice reference must contain at least 3 seconds of speech.")
            # 30 seconds is the app's quality/speed ceiling. The app records
            # exactly this much context, and exported imports are constrained
            # before they reach this adapter.
            samples = samples[: int(sample_rate * 30)]
            wavs, sample_rate = clone_model(app).generate_voice_clone(
                text=request.input,
                language=request.language,
                ref_audio=(samples, sample_rate),
                ref_text=request.reference_text or None,
                x_vector_only_mode=not bool(request.reference_text and request.reference_text.strip()),
                # Avoid the streaming path's speaking-rate drift. We return a
                # completed WAV response, so streaming provides no UI benefit.
                non_streaming_mode=True,
            )
        else:
            wavs, sample_rate = custom_model(app).generate_custom_voice(
                text=request.input,
                language=request.language,
                speaker=request.voice,
            )
        audio = io.BytesIO()
        sf.write(audio, wavs[0], sample_rate, format="WAV")
        return Response(content=audio.getvalue(), media_type="audio/wav")
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
