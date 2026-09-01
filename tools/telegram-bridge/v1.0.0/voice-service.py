from __future__ import annotations

import argparse
import gc
import json
import os
import tempfile
import threading
import time
from pathlib import Path

from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from faster_whisper import WhisperModel
import uvicorn


parser = argparse.ArgumentParser(description="BeeForge local speech-to-text service")
parser.add_argument("--host", default="127.0.0.1")
parser.add_argument("--port", type=int, required=True)
parser.add_argument("--key-file", required=True)
parser.add_argument("--model", default="small")
parser.add_argument("--model-root", required=True)
parser.add_argument("--idle-seconds", type=int, default=900)
args = parser.parse_args()

if args.host not in {"127.0.0.1", "::1"}:
    raise SystemExit("Voice service may bind only to loopback")

EXPECTED_KEY = Path(args.key_file).read_text(encoding="utf-8").strip()
MODEL_ROOT = Path(args.model_root).resolve()
MODEL_ROOT.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="BeeForge Voice", docs_url=None, redoc_url=None, openapi_url=None)
model_lock = threading.Lock()
model: WhisperModel | None = None
last_used = 0.0


def require_key(value: str | None) -> None:
    if not value or value != EXPECTED_KEY:
        raise HTTPException(status_code=401, detail="unauthorized")


def get_model() -> WhisperModel:
    global model, last_used
    with model_lock:
        if model is None:
            # BeeLlama normally occupies almost all VRAM. CPU INT8 prevents the
            # speech service from evicting or destabilising the active LLM.
            model = WhisperModel(
                args.model,
                device="cpu",
                compute_type="int8",
                cpu_threads=max(2, min(8, (os.cpu_count() or 4) // 2)),
                download_root=str(MODEL_ROOT),
            )
        last_used = time.time()
        return model


def idle_unloader() -> None:
    global model
    while True:
        time.sleep(30)
        with model_lock:
            if model is not None and time.time() - last_used >= args.idle_seconds:
                model = None
                gc.collect()


@app.get("/health")
def health(x_beeforge_key: str | None = Header(default=None)) -> JSONResponse:
    require_key(x_beeforge_key)
    return JSONResponse({"ok": True, "model": args.model, "loaded": model is not None, "device": "cpu", "computeType": "int8"})


@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    language: str = "auto",
    x_beeforge_key: str | None = Header(default=None),
) -> JSONResponse:
    require_key(x_beeforge_key)
    suffix = Path(file.filename or "voice.ogg").suffix[:12] or ".ogg"
    payload = await file.read(20 * 1024 * 1024 + 1)
    if not payload:
        raise HTTPException(status_code=400, detail="empty audio")
    if len(payload) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="audio exceeds 20 MB")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix="beeforge-voice-", suffix=suffix, delete=False) as stream:
            stream.write(payload)
            temporary = stream.name
        whisper = get_model()
        segments, info = whisper.transcribe(
            temporary,
            language=None if language in {"", "auto"} else language,
            task="transcribe",
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=True,
        )
        text = " ".join(segment.text.strip() for segment in segments if segment.text.strip()).strip()
        return JSONResponse({
            "text": text,
            "language": getattr(info, "language", None),
            "languageProbability": getattr(info, "language_probability", None),
            "duration": getattr(info, "duration", None),
            "model": args.model,
        })
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass


threading.Thread(target=idle_unloader, daemon=True).start()
uvicorn.run(app, host=args.host, port=args.port, log_level="warning", access_log=False)
