#!/usr/bin/env python3
"""Local-only OpenAI-compatible adapter for the official Qwen3-TTS package."""

from __future__ import annotations

import io
import os
import base64
import gc
import threading
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
# Only the 1.7B CustomVoice checkpoint honours style instructions; the 0.6B one
# silently drops them. It is loaded lazily, only when a tone is requested.
TONE_MODEL_ID = os.environ.get("OPEN_RECORDER_QWEN_TTS_TONE_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")
CLONE_MODEL_ID = os.environ.get("OPEN_RECORDER_QWEN_TTS_CLONE_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-Base")


class SpeechRequest(BaseModel):
    model: str = MODEL_ID
    input: str = Field(min_length=1)
    voice: str = "Vivian"
    language: str = "English"
    response_format: str = "wav"
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    pitch: float = Field(default=1.0, ge=0.5, le=2.0)
    reference_audio_b64: str | None = None
    reference_text: str | None = None
    instruct: str | None = Field(default=None, max_length=500)


def load_model(model_id: str) -> Qwen3TTSModel:
    # MPS float16 can produce NaNs and MPS bfloat16 can produce corrupted audio
    # in Qwen's autoregressive decoder. Use full-precision CPU inference until
    # the upstream MPS path is reliable; it is slower but produces valid speech.
    device = "cpu"
    dtype = torch.float32
    # Loading otherwise phones home to the Hugging Face hub (observed: 45 s on a
    # slow network) even when the checkpoint is cached. Prefer the local cache
    # and only go online if the checkpoint is genuinely missing.
    try:
        return Qwen3TTSModel.from_pretrained(model_id, device_map=device, dtype=dtype, local_files_only=True)
    except Exception:
        return Qwen3TTSModel.from_pretrained(model_id, device_map=device, dtype=dtype)


# One CPU-bound generation at a time. Overlapping requests (e.g. a preview and a
# full narration) would otherwise fight for cores and could swap/unload the
# checkpoint another request is still using.
GENERATION_LOCK = threading.Lock()


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
        unload_model(app, "tone_model")
        model = load_model(MODEL_ID)
        app.state.custom_model = model
    return model


def tone_model(app: FastAPI) -> Qwen3TTSModel:
    model = getattr(app.state, "tone_model", None)
    if model is None:
        unload_model(app, "custom_model")
        unload_model(app, "clone_model")
        model = load_model(TONE_MODEL_ID)
        app.state.tone_model = model
    return model


def clone_model(app: FastAPI) -> Qwen3TTSModel:
    model = getattr(app.state, "clone_model", None)
    if model is None:
        # A clone uses the Base checkpoint, not the CustomVoice checkpoint.
        # Release the normal TTS model first so both models are never resident.
        unload_model(app, "custom_model")
        unload_model(app, "tone_model")
        model = load_model(CLONE_MODEL_ID)
        app.state.clone_model = model
    return model


MAX_ATTEMPTS = 3


def is_audible(samples) -> bool:
    import numpy as np

    data = np.asarray(samples, dtype=np.float32)
    # Healthy output peaks well above 0.05; the silent failures peak near 0.01.
    return (
        data.size > 2_400
        and not np.isnan(data).any()
        and float(np.abs(data).max()) >= 0.03
        and float(np.sqrt((data**2).mean())) >= 0.003
    )


def is_plausible_length(samples, sample_rate: int, text: str) -> bool:
    """Reject runaway output (rambling/noise) and truncated output (the model
    emitting end-of-speech early and dropping the last words).

    Natural narration runs ~10-18 characters/second. Clips outside roughly
    8-24 characters/second are not a faithful reading of the text."""
    seconds = len(samples) / sample_rate
    characters = len(text.strip())
    return characters / 24 - 0.5 <= seconds <= characters / 8 + 1.5


def generation_limit(text: str) -> int:
    """Keep a malformed/no-EOS response from occupying CPU for several minutes.

    Qwen defaults to 2,048 codec tokens. At 12 Hz that can be almost three
    minutes of audio, even for a one-line narration. The allowance below still
    leaves generous headroom for normal speech while scaling with the script.
    Longer narrations should be sent as separate sentences by the client.
    """
    # Speech is ~15 characters/s, i.e. under 1 codec token per character at 12 Hz;
    # 2 per character plus slack matches is_plausible_length and bounds runaways.
    return max(36, min(768, len(text.strip()) * 2 + 30))


def adjust_speed_and_pitch(samples, sample_rate: int, speed: float, pitch: float):
    """Apply speed and pitch independently (pitch shifts without changing tempo).

    Resample by `pitch` (changes pitch and duration), then phase-vocoder time
    stretch so the final duration is original / speed.
    """
    import numpy as np

    if abs(speed - 1.0) < 1e-3 and abs(pitch - 1.0) < 1e-3:
        return samples
    wave = torch.as_tensor(np.asarray(samples), dtype=torch.float32).reshape(-1)
    if abs(pitch - 1.0) >= 1e-3:
        target = max(1, round(wave.numel() / pitch))
        wave = F.interpolate(wave.reshape(1, 1, -1), size=target, mode="linear", align_corners=False).reshape(-1)
    rate = speed / pitch
    if abs(rate - 1.0) >= 1e-3:
        n_fft, hop = 1024, 256
        window = torch.hann_window(n_fft)
        spec = torch.stft(wave, n_fft, hop_length=hop, window=window, return_complex=True)
        steps = torch.arange(0, spec.shape[-1], rate)
        spec = F.pad(spec, (0, 2))
        phase_advance = torch.linspace(0, torch.pi * hop, spec.shape[0]).unsqueeze(-1)
        phase_acc = torch.angle(spec[:, :1])
        out = []
        for step in steps:
            idx = int(step)
            frac = step - idx
            c0, c1 = spec[:, idx], spec[:, idx + 1]
            mag = (1 - frac) * c0.abs() + frac * c1.abs()
            out.append((mag * torch.exp(1j * phase_acc.squeeze(-1))).unsqueeze(-1))
            delta = torch.angle(c1) - torch.angle(c0) - phase_advance.squeeze(-1)
            delta = delta - 2 * torch.pi * torch.round(delta / (2 * torch.pi))
            phase_acc = phase_acc + (phase_advance.squeeze(-1) + delta).unsqueeze(-1)
        stretched = torch.cat(out, dim=-1)
        wave = torch.istft(stretched, n_fft, hop_length=hop, window=window)
    return wave.numpy()


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    unload_model(app, "custom_model")
    unload_model(app, "clone_model")
    unload_model(app, "tone_model")


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
        with GENERATION_LOCK:
            # The sampler occasionally yields near-silent audio (the clone then
            # "speaks" but nothing is audible). Sampling is stochastic, so retry.
            # Cloning with a transcript follows the sample's delivery more closely
            # but derails when the transcript is wrong. Try it first, then fall
            # back to the speaker embedding alone, which ignores the transcript.
            modes = [True, False, False, False] if request.reference_text and request.reference_text.strip() else [False] * MAX_ATTEMPTS
            for use_transcript in modes:
                samples, sample_rate = generate_speech(request, use_transcript)
                if is_audible(samples) and is_plausible_length(samples, sample_rate, request.input):
                    break
            else:
                raise ValueError(
                    "The voice model produced silent audio. Re-record the voice sample "
                    "closer to the microphone, or confirm the sample transcript matches what you said."
                )
        audio = io.BytesIO()
        sf.write(audio, adjust_speed_and_pitch(samples, sample_rate, request.speed, request.pitch), sample_rate, format="WAV")
        return Response(content=audio.getvalue(), media_type="audio/wav")
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


def generate_speech(request: SpeechRequest, use_transcript: bool = True):
    if True:
        max_new_tokens = generation_limit(request.input)
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
                ref_text=(request.reference_text or None) if use_transcript else None,
                x_vector_only_mode=not (use_transcript and bool(request.reference_text and request.reference_text.strip())),
                # Avoid the streaming path's speaking-rate drift. We return a
                # completed WAV response, so streaming provides no UI benefit.
                non_streaming_mode=True,
                max_new_tokens=max_new_tokens,
            )
        else:
            instruct = (request.instruct or "").strip()
            wavs, sample_rate = (tone_model(app) if instruct else custom_model(app)).generate_custom_voice(
                text=request.input,
                language=request.language,
                speaker=request.voice,
                instruct=instruct or None,
                max_new_tokens=max_new_tokens,
            )
        return wavs[0], sample_rate
