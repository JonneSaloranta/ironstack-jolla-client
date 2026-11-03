#!/usr/bin/env python3
"""Writes the stretching timer's chimes to qml/sounds/ - the same tones as
the web's timer-audio.js beep(): a sine per frequency, 0.18 s apart, each
fading in over 20 ms and out exponentially by 0.35 s.

    python3 -I tools/sounds/generate.py
"""
import math
import struct
import sys
import wave
from pathlib import Path

RATE = 22050
TONE_SECONDS = 0.35
STEP_SECONDS = 0.18
PEAK = 0.25 * 0.9  # the web's gain, a little headroom for overlapping tones

# The web's cues (static/js/stretch-timer.js).
CHIMES = {
    "hold": [988, 1319],        # a hold starts: higher, double
    "step": [660],              # any other step ends
    "done": [784, 988, 1319],   # the session is done
}


def envelope(t):
    """gain.setValueAtTime(0.001) -> exponential ramp to 0.25 at 20 ms ->
    exponential ramp to 0.001 at 350 ms."""
    low, attack = 0.001, 0.02
    if t < attack:
        return low * (PEAK / low) ** (t / attack)
    return PEAK * (low / PEAK) ** ((t - attack) / (TONE_SECONDS - attack))


def render(frequencies):
    length = int(RATE * (STEP_SECONDS * (len(frequencies) - 1) + TONE_SECONDS)) + 1
    samples = [0.0] * length
    for i, freq in enumerate(frequencies):
        start = int(RATE * STEP_SECONDS * i)
        for n in range(int(RATE * TONE_SECONDS)):
            t = n / RATE
            samples[start + n] += envelope(t) * math.sin(2 * math.pi * freq * t)
    return samples


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "qml" / "sounds")
    out.mkdir(parents=True, exist_ok=True)
    for name, frequencies in CHIMES.items():
        with wave.open(str(out / f"{name}.wav"), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(b"".join(
                struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in render(frequencies)))
        print(out / f"{name}.wav")


if __name__ == "__main__":
    main()
