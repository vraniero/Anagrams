"""Listening: segmenting, language fallback, and the /listen protocol (model faked)."""
import numpy as np
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import listen
from listen import RATE, Segmenter, Session


def tone(seconds, freq=220.0, loud=0.2):
    t = np.arange(int(seconds * RATE)) / RATE
    return (loud * np.sin(2 * np.pi * freq * t)).astype(np.float32)


def quiet(seconds):
    return np.zeros(int(seconds * RATE), np.float32)


def pcm(audio):
    return (np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes()


class FakeEngine:
    """Says what it's told, in the language it's told."""

    def __init__(self, text="la farmacia è aperta", lang="it"):
        self.text, self.lang = text, lang
        self.fallbacks = []

    def load(self):
        pass

    def transcribe(self, audio, fallback):
        self.fallbacks.append(fallback)
        return self.lang, self.text


def events(segmenter, audio, chunk=1600):
    out = []
    for i in range(0, len(audio), chunk):
        out += list(segmenter.feed(audio[i:i + chunk]))
    return out


def test_segmenter_cuts_at_pauses_and_keeps_stream_time():
    audio = np.concatenate([quiet(0.5), tone(1.0), quiet(1.0), tone(1.5), quiet(1.0)])
    found = events(Segmenter(), audio)
    assert [e[0] for e in found] == ["speech", "silence", "utterance", "speech", "silence", "utterance"]
    starts = [e[1] for e in found if e[0] == "utterance"]
    assert starts == pytest.approx([0.5, 2.5], abs=0.04)
    lengths = [len(e[2]) / RATE for e in found if e[0] == "utterance"]
    assert lengths == pytest.approx([1.0, 1.5], abs=0.04)  # trailing quiet trimmed


def test_segmenter_drops_clicks_and_cuts_monologues():
    seg = Segmenter(longest=3.0)
    click = events(seg, np.concatenate([tone(0.1), quiet(1.0)]))
    assert [e[0] for e in click] == ["speech", "silence"]  # too short to be an utterance
    long = events(seg, tone(7.0))
    assert sum(e[0] == "utterance" for e in long) == 2  # cut at 3 s, 3 s; the rest pending
    assert [e[0] for e in seg.flush()] == ["silence", "utterance"]


def test_session_tracks_language_and_ignores_noise():
    engine = FakeEngine()
    session = Session(engine)
    first = session.hear(10.0, tone(1.0))
    assert first == {"type": "utterance", "id": 1, "lang": "it", "start": 10.0, "end": 11.0,
                     "text": "la farmacia è aperta"}
    engine.text, engine.lang = "and the night", "en"
    assert session.hear(12.0, tone(1.0))["lang"] == "en"  # languages can switch
    engine.text = ""
    assert session.hear(14.0, tone(1.0)) is None
    assert engine.fallbacks == [None, "it", "en"]  # the language heard last is the fallback


def test_made_up_segments_from_silence_are_dropped():
    result = {"text": " You Ciao", "segments": [
        {"text": " You", "no_speech_prob": 0.8, "avg_logprob": -1.2},
        {"text": " Ciao", "no_speech_prob": 0.1, "avg_logprob": -0.3}]}
    assert listen.speech_text(result) == "Ciao"
    assert listen.speech_text({"text": " hi "}) == "hi"


def test_listen_websocket_finish_flushes_then_ignores_audio(monkeypatch):
    monkeypatch.setattr(listen, "engine", FakeEngine())
    app = FastAPI()
    app.include_router(listen.router)
    with TestClient(app).websocket_connect("/listen") as ws:
        assert ws.receive_json() == {"type": "ready"}
        audio = np.concatenate([quiet(0.3), tone(1.0), quiet(1.0), tone(1.0)])  # still talking
        for i in range(0, len(audio), 3200):
            ws.send_bytes(pcm(audio[i:i + 3200]))
        ws.send_text('{"type": "finish"}')
        ws.send_bytes(pcm(np.concatenate([tone(1.0), quiet(1.0)])))  # after finish: ignored
        got = []
        while not got or got[-1]["type"] != "done":
            got.append(ws.receive_json())
        utterances = [m for m in got if m["type"] == "utterance"]
        assert [m["id"] for m in utterances] == [1, 2]  # the unfinished one was flushed
        assert utterances[0]["start"] == pytest.approx(0.3, abs=0.04)
        assert [m["type"] for m in got if m["type"] != "utterance"] == \
            ["speech", "silence", "transcribing", "speech", "silence", "transcribing", "done"]
