"""Generate original, deterministic simulator effects; no third-party samples."""

import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "godot/audio"
RATE = 22050
rng = random.Random(51)


def save(name, duration, sample):
    frames = []
    for i in range(int(RATE * duration)):
        t = i / RATE
        value = max(-0.85, min(0.85, sample(t, duration)))
        frames.append(struct.pack("<h", int(value * 32767)))
    with wave.open(str(ROOT / (name + ".wav")), "wb") as f:
        f.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        f.writeframes(b"".join(frames))


def tone(t, f):
    return math.sin(math.tau * f * t)


def chime(notes):
    def sample(t, duration):
        index = min(len(notes) - 1, int(t / (duration / len(notes))))
        local = t % (duration / len(notes))
        return (
            0.32 * tone(t, notes[index]) * min(1, local / 0.008) * math.exp(-local * 10)
        )

    return sample


ROOT.mkdir(parents=True, exist_ok=True)
save(
    "rotor",
    1,
    lambda t, d: (
        (0.18 * tone(t, 96) + 0.09 * tone(t, 192) + 0.04 * tone(t, 384))
        * (0.8 + 0.2 * tone(t, 24))
    ),
)
save(
    "kitchen",
    1,
    lambda t, d: (
        0.055 * tone(t, 180)
        + 0.035 * tone(t, 360)
        + 0.035 * tone(t, 1320) * (0.5 + 0.5 * tone(t, 8))
    ),
)
save(
    "packing",
    0.42,
    lambda t, d: (
        (rng.uniform(-0.18, 0.18) + 0.13 * tone(t, 320))
        * math.sin(math.pi * t / d) ** 2
    ),
)
save("order", 0.4, chime([660, 880]))
save("pickup", 0.5, chime([440, 660, 880]))
save("delivered", 0.8, chime([523.25, 659.25, 783.99, 1046.5]))
print("Generated six original mono WAV sound effects.")
