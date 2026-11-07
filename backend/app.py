"""Anagrams backend: speech recognition with language detection for the iOS app.

    GET  /health
    WS   /listen   live audio -> utterances with their language (see listen.py)

Run: .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 --no-access-log   (from backend/)
"""
import logging

from fastapi import FastAPI

from listen import LANGUAGES, WHISPER_MODEL
from listen import router as listen_router

app = FastAPI(title="Anagrams", version="0.1")

# Monitor: each utterance heard is printed on the server's console.
log = logging.getLogger("anagrams")
if not log.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(asctime)s  %(message)s", "%H:%M:%S"))
    log.addHandler(_handler)
    log.setLevel(logging.INFO)
    log.propagate = False


@app.get("/health")
def health():
    return {"ok": True, "model": WHISPER_MODEL, "languages": sorted(LANGUAGES) or "any"}


app.include_router(listen_router)
