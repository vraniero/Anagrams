"""Live speech in, words and their language out (ported from Etymon, single speaker).

    WS /listen
      in   binary frames: 16 kHz mono PCM, 16-bit little-endian, any chunk size
           text frames (JSON):
             {"type": "finish"}   the user is done: transcribe what's pending, then "done"
             {"type": "reset"}    start a new sentence, restart the clock
      out  {"type": "ready"}                       models loaded
           {"type": "speech", "start": 12.40}      the user started talking
           {"type": "silence", "end": 15.10}       ... and stopped
           {"type": "transcribing", "start": 12.4} that stretch is being transcribed
           {"type": "utterance", "id": 3, "lang": "it", "start": 12.4, "end": 15.1,
            "text": "La farmacia è aperta"}
           {"type": "discarded", "start": 12.4}    ... and had no words in it (a cough)
           {"type": "done"}                        after "finish": nothing more will come

Speech is cut into utterances at pauses. Each one is transcribed with Whisper, which
detects the language per utterance, so the user can switch languages mid-sentence.

ANAGRAMS_LANGUAGES=it,en,fr  (optional) limits the languages accepted. An utterance
detected as anything else (usually a misdetection) is transcribed again in the language
heard last.

Needs: pip install -r requirements-speech.txt (Apple Silicon; whisper-large-v3-turbo,
about 1.6 GB, downloads on first use).
"""
import asyncio
import json
import logging
import os
import threading

import numpy as np
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

RATE = 16_000
FRAME = 480  # 30 ms
WHISPER_MODEL = os.environ.get("ANAGRAMS_WHISPER", "mlx-community/whisper-large-v3-turbo")
LANGUAGES = {c.strip() for c in os.environ.get("ANAGRAMS_LANGUAGES", "").split(",") if c.strip()}

log = logging.getLogger("anagrams")
router = APIRouter()


# --- cutting the stream into utterances ------------------------------------------------

class Segmenter:
    """Energy-based voice activity: an utterance runs from the first loud frame to a pause.

    The noise floor follows the quiet frames, so a noisy room needs louder speech. An
    utterance ends after `pause` seconds of quiet, or is cut at `longest` seconds. Anything
    shorter than `shortest` is noise.
    """

    def __init__(self, pause=0.7, longest=12.0, shortest=0.4, floor=0.004):
        self.pause, self.longest, self.shortest = pause, longest, shortest
        self.floor = floor
        self.samples = 0  # stream position, in samples
        self._pending = np.zeros(0, np.float32)
        self._utterance: list[np.ndarray] = []
        self._start = 0
        self._quiet = 0  # frames of quiet inside the current utterance

    @property
    def talking(self):
        return bool(self._utterance)

    def feed(self, audio: np.ndarray):
        """Yield ("speech", start) / ("utterance", start, audio) / ("silence", end) events."""
        self._pending = np.concatenate([self._pending, audio])
        while len(self._pending) >= FRAME:
            frame, self._pending = self._pending[:FRAME], self._pending[FRAME:]
            yield from self._frame(frame)

    def _frame(self, frame):
        rms = float(np.sqrt(np.mean(frame ** 2)))
        loud = rms > max(self.floor * 3, 0.008)
        if not loud:  # adapt slowly to the room
            self.floor = 0.95 * self.floor + 0.05 * rms
        position = self.samples
        self.samples += len(frame)
        if not self._utterance:
            if loud:
                self._start, self._quiet = position, 0
                self._utterance = [frame]
                yield ("speech", position / RATE)
            return
        self._utterance.append(frame)
        self._quiet = 0 if loud else self._quiet + 1
        length = len(self._utterance) * FRAME / RATE
        if self._quiet * FRAME / RATE >= self.pause or length >= self.longest:
            yield from self._close()

    def flush(self):
        if self._utterance:
            yield from self._close()

    def _close(self):
        frames = self._utterance[:len(self._utterance) - self._quiet] or self._utterance
        audio = np.concatenate(frames)
        start = self._start / RATE
        self._utterance, self._quiet = [], 0
        yield ("silence", start + len(audio) / RATE)
        if len(audio) / RATE >= self.shortest:
            yield ("utterance", start, audio)


# --- model ------------------------------------------------------------------------------

class Engine:
    """Whisper: the words and the language. Loaded once, used one call at a time."""

    def __init__(self):
        self._lock = threading.Lock()
        self._whisper = None

    def load(self):
        with self._lock:
            if self._whisper is None:
                import mlx_whisper
                self._whisper = mlx_whisper
                # a second of silence makes Whisper load its weights now, not mid-sentence
                mlx_whisper.transcribe(np.zeros(RATE, np.float32), path_or_hf_repo=WHISPER_MODEL)

    def transcribe(self, audio: np.ndarray, fallback: str | None) -> tuple[str | None, str]:
        """The language spoken and the text. A language outside LANGUAGES is retried as
        `fallback`, the language heard last."""
        with self._lock:
            kw = dict(path_or_hf_repo=WHISPER_MODEL, condition_on_previous_text=False)
            result = self._whisper.transcribe(audio, **kw)
            lang = result.get("language")
            if LANGUAGES and lang not in LANGUAGES and fallback:
                result = self._whisper.transcribe(audio, language=fallback, **kw)
                lang = fallback
        if LANGUAGES and lang not in LANGUAGES:
            lang = None
        return lang, speech_text(result)


def speech_text(result: dict) -> str:
    """The transcript without segments Whisper made up from near-silence ("You", "Thank
    you."): those it rates as probably not speech and isn't confident about."""
    segments = result.get("segments")
    if segments is None:
        return result.get("text", "").strip()
    kept = [s["text"].strip() for s in segments
            if not (s.get("no_speech_prob", 0) > 0.5 and s.get("avg_logprob", 0) < -0.8)]
    return " ".join(t for t in kept if t)


engine = Engine()


# --- the stream ------------------------------------------------------------------------

class Session:
    """One phone listening: its clock, its utterances in order, the language heard last."""

    def __init__(self, engine):
        self.engine = engine
        self.segmenter = Segmenter()
        self.lang: str | None = None
        self.next_id = 1

    def hear(self, start: float, audio: np.ndarray) -> dict | None:
        lang, text = self.engine.transcribe(audio, fallback=self.lang)
        if not text:  # a cough, a door: not speech after all
            return None
        if lang:
            self.lang = lang
        out = {"type": "utterance", "id": self.next_id, "lang": lang,
               "start": round(start, 2), "end": round(start + len(audio) / RATE, 2),
               "text": text}
        self.next_id += 1
        return out


@router.websocket("/listen")
async def listen(ws: WebSocket):
    await ws.accept()
    await asyncio.to_thread(engine.load)
    session = Session(engine)
    queue: asyncio.Queue = asyncio.Queue()
    generation = [0]  # bumped by "reset": utterances from before it are dropped
    await ws.send_json({"type": "ready"})
    log.info("listen  connected")

    async def work():
        # utterances are transcribed one after another, in the order they were spoken
        while True:
            item = await queue.get()
            if item == "done":
                await ws.send_json({"type": "done"})
                continue
            start, audio, gen = item
            out = await asyncio.to_thread(session.hear, start, audio)
            if gen != generation[0]:
                continue
            if out:
                log.info(f"listen  [{out['lang'] or '--'}] {out['text']}")
                await ws.send_json(out)
            else:  # nothing worth writing down: tell the phone to stop waiting for it
                await ws.send_json({"type": "discarded", "start": round(start, 2)})

    async def events(found):
        for event in found:
            if event[0] == "utterance":
                queue.put_nowait((event[1], event[2], generation[0]))
                # heard: the phone shows it's being worked on until the words (or "discarded") come
                await ws.send_json({"type": "transcribing", "start": round(event[1], 2)})
            else:
                key = "start" if event[0] == "speech" else "end"
                await ws.send_json({"type": event[0], key: round(event[1], 2)})

    worker = asyncio.create_task(work())
    finished = False
    try:
        while True:
            message = await ws.receive()
            if message.get("type") == "websocket.disconnect":
                break
            if (data := message.get("bytes")) is not None:
                if finished:
                    continue  # after "finish" no further words are recognized
                audio = np.frombuffer(data[: len(data) // 2 * 2], "<i2").astype(np.float32) / 32768
                await events(session.segmenter.feed(audio))
            elif (text := message.get("text")) is not None:
                command = json.loads(text)
                if command.get("type") == "finish":
                    finished = True
                    await events(session.segmenter.flush())
                    queue.put_nowait("done")
                elif command.get("type") == "reset":
                    finished = False
                    generation[0] += 1
                    session.segmenter = Segmenter()
                    session.lang = None
    except WebSocketDisconnect:
        pass
    finally:
        worker.cancel()
        log.info("listen  disconnected")
