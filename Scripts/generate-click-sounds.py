#!/usr/bin/env python3
"""Synthesizes the click sounds into the asset catalog.

Every sound is made here from simple waveforms and filtered noise, so there is no sample licensing to track.
Each sound has two hits: an accent for the downbeat and a normal hit for the other clicks.
They are written as mono 48 kHz 16-bit WAVs into data assets named
"Click <Name> Accent" and "Click <Name> Normal", which `ClickSound` reads by name.

Edit a recipe below and re-run:

    Scripts/generate-click-sounds.py

Uses only the Python standard library.
"""

import json
import math
import random
import shutil
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 48_000
ASSET_FOLDER = Path(__file__).resolve().parent.parent / "CuesLive" / "Assets.xcassets" / "Click Sounds"

# Peak levels, so every sound sits at the same loudness and the accent stands out by the same amount.
ACCENT_PEAK = 0.9
NORMAL_PEAK = 0.6


def frames(seconds):
    return int(seconds * SAMPLE_RATE)


def decay(t, seconds):
    """Exponential decay that falls to about -60 dB after `seconds`."""
    return math.exp(-6.9 * t / seconds)


def attack(t, seconds=0.0005):
    """A short fade-in so the hit starts without a DC click."""
    return min(1.0, t / seconds)


def tail_fade(samples, seconds=0.005):
    """Fades the last few milliseconds to exact silence."""
    count = min(len(samples), frames(seconds))
    for i in range(count):
        samples[len(samples) - 1 - i] *= i / count
    return samples


def normalized(samples, peak):
    loudest = max(abs(s) for s in samples) or 1.0
    return [s * peak / loudest for s in samples]


def beep(pitch, length=0.05):
    """A plain sine tone, the classic electronic metronome."""
    samples = []
    for n in range(frames(length)):
        t = n / SAMPLE_RATE
        samples.append(math.sin(2 * math.pi * pitch * t) * attack(t) * decay(t, length * 1.6))
    return tail_fade(samples)


def woodblock(pitch, partials, hold, release, ring_pitch, ring_gain, ring_decay,
              tail_gain, tail_decay, peak, tick_gain=0.25, tick_decay=0.5, seed=1):
    """A woodblock as drum machines play it: a held tone that is cut off short, over a bright
    attack, then a quiet resonance from the block. Times are in milliseconds.

    partials:   (ratio to pitch, level) pairs for the held tone
    hold:       how long the tone holds at full level before it is cut off
    release:    how long the cut-off takes
    ring_pitch: frequency of the attack's ring, which gives the hit its knock
    ring_gain:  level of that ring against the tone; ring_decay sets how fast it dies
    tail_gain:  level of the resonance left after the cut-off; tail_decay sets how fast it dies
    peak:       peak level of the hit, which sets the balance between a sound's two hits
    tick_gain:  level of the stick's noise tick at the very start; tick_decay sets its length
    seed:       noise seed, so re-running the script gives identical files
    """
    rng = random.Random(seed)
    # Resonant band-pass that turns noise into the block's ring, centred on the pitch.
    r = math.exp(-math.pi * 300 / SAMPLE_RATE)
    theta = 2 * math.pi * pitch / SAMPLE_RATE
    a1, a2, gain = -2 * r * math.cos(theta), r * r, 1 - r
    y1 = y2 = previous_noise = 0.0

    samples = []
    for n in range(frames((hold + release + tail_decay * 4) / 1000)):
        t = n / SAMPLE_RATE
        ms = t * 1000
        if ms < hold:
            level = 1.0
        elif ms < hold + release:
            level = 0.5 * (1 + math.cos(math.pi * (ms - hold) / release))
        else:
            level = 0.0
        tone = level * sum(g * math.sin(2 * math.pi * pitch * ratio * t) for ratio, g in partials)
        ring = ring_gain * math.sin(2 * math.pi * ring_pitch * t) * math.exp(-ms / ring_decay)

        noise = rng.uniform(-1, 1)
        tick = tick_gain * (noise - previous_noise) * math.exp(-ms / tick_decay)
        previous_noise = noise

        y = gain * rng.uniform(-1, 1) - a1 * y1 - a2 * y2
        y2, y1 = y1, y
        tail = tail_gain * y * math.exp(-ms / tail_decay) * min(1.0, ms / hold)

        samples.append((tone + ring + tick + tail) * attack(t, 0.00015))
    return normalized(tail_fade(samples), peak)


def pulse(rise, hold, peak, sag, tail_levels, tail_fade, overshoot=0.0, brightness=12_000):
    """An electronic pulse click: a near-square push that snaps back past zero, then a low,
    slow return that balances it out. All times are in milliseconds.

    rise:        ramp from silence up to `peak`
    hold:        how long the pulse stays up after the rise, sagging by `sag`
    tail_levels: (time, level) points for the negative tail after the pulse, joined by straight lines
    tail_fade:   final ramp from the last tail level back to silence
    overshoot:   a brief dip below the tail as the pulse drops, the snap of the click
    brightness:  low-pass cutoff in Hz; lower rounds the edges off for a softer click
    """
    ms = SAMPLE_RATE / 1000
    fall = rise + hold
    points = [(0, 0.0), (rise, peak), (fall, peak - sag)]
    points += [(fall + t, level) for t, level in tail_levels]
    last_time = points[-1][0]
    points.append((last_time + tail_fade, 0.0))

    samples = []
    segment = 0
    for n in range(int(points[-1][0] * ms) + 1):
        t = n / ms
        while segment < len(points) - 2 and t > points[segment + 1][0]:
            segment += 1
        (t0, v0), (t1, v1) = points[segment], points[segment + 1]
        # Points that share a time, like the drop from the pulse to the tail, make a step.
        value = v0 + (v1 - v0) * (t - t0) / (t1 - t0) if t1 > t0 else v1
        if t >= fall:
            value -= overshoot * math.exp(-(t - fall) * ms / 4)
        samples.append(value)
    return low_pass(samples, cutoff=brightness)


def low_pass(samples, cutoff):
    """One-pole low-pass, to round off edges the way analog circuitry would."""
    alpha = 1 - math.exp(-2 * math.pi * cutoff / SAMPLE_RATE)
    output, previous = [], 0.0
    for x in samples:
        previous += alpha * (x - previous)
        output.append(previous)
    return output


# Name shown in the app -> (accent hit, normal hit). The accent is usually higher as well as louder.
SOUNDS = {
    # Modelled on the original "Gentle" click WAVs: a short, bright pulse on the downbeat
    # and a longer, rounder one on the other beats.
    "Default": (
        lambda: pulse(
            rise=0.2, hold=1.05, peak=0.584, sag=0.08,
            tail_levels=[(0.0, -0.055), (1.0, -0.041), (3.0, -0.048), (5.5, -0.036),
                         (8.0, -0.032)],
            tail_fade=2.4, overshoot=0.2, brightness=12_000,
        ),
        lambda: pulse(
            rise=0.4, hold=2.05, peak=0.396, sag=0.07,
            tail_levels=[(0.0, -0.048), (1.5, -0.034), (2.5, -0.041), (5.0, -0.032),
                         (13.0, -0.032), (20.0, -0.023)],
            tail_fade=5.0, overshoot=0.08, brightness=7_000,
        ),
    ),
    # Modelled on the "Woodblock" click WAVs: a higher, softer knock on the downbeat.
    "Woodblock": (
        lambda: woodblock(
            pitch=963,
            partials=[(1, 0.62), (4.31, 0.15), (3.08, 0.075), (2.06, 0.05), (5.83, 0.05), (1.385, 0.04)],
            hold=10.0, release=3.5, ring_pitch=2_450, ring_gain=1.5, ring_decay=1.0,
            tail_gain=0.25, tail_decay=12, peak=0.398, seed=2,
        ),
        lambda: woodblock(
            pitch=809,
            partials=[(1, 1), (6.12, 0.22), (3.3, 0.05), (4.78, 0.05), (1.61, 0.06), (1.29, 0.05)],
            hold=10.6, release=1.2, ring_pitch=2_200, ring_gain=1.1, ring_decay=1.2,
            tail_gain=0.35, tail_decay=9, peak=0.583, seed=1,
        ),
    ),
    "Beep": (lambda: beep(1_500), lambda: beep(1_000)),
}


def write_wav(path, samples):
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(SAMPLE_RATE)
        file.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32_767)) for s in samples
        ))


def write_json(path, contents):
    path.write_text(json.dumps(contents, indent=2) + "\n")


def write_data_asset(asset_name, samples):
    folder = ASSET_FOLDER / f"{asset_name}.dataset"
    folder.mkdir(parents=True, exist_ok=True)
    for stale in folder.glob("*.wav"):
        stale.unlink()
    file_name = f"{asset_name}.wav"
    write_wav(folder / file_name, samples)
    write_json(folder / "Contents.json", {
        "data": [{"filename": file_name, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })


# Sounds whose accent and normal hit keep the level balance they were designed with, scaled
# together so the louder one peaks at ACCENT_PEAK, instead of each being set to its own peak.
KEEP_BALANCE = {"Default", "Woodblock"}


def peak(samples):
    return max(abs(s) for s in samples)


def main():
    ASSET_FOLDER.mkdir(parents=True, exist_ok=True)
    write_json(ASSET_FOLDER / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    written = set()
    for name, (make_accent, make_normal) in SOUNDS.items():
        accent, normal = make_accent(), make_normal()
        if name in KEEP_BALANCE:
            scale = ACCENT_PEAK / max(peak(accent), peak(normal))
            accent_peak, normal_peak = peak(accent) * scale, peak(normal) * scale
        else:
            accent_peak, normal_peak = ACCENT_PEAK, NORMAL_PEAK
        for asset_name, samples, level in (
            (f"Click {name} Accent", accent, accent_peak),
            (f"Click {name} Normal", normal, normal_peak),
        ):
            write_data_asset(asset_name, normalized(samples, level))
            written.add(f"{asset_name}.dataset")
        print(f"wrote {name}")

    # A sound taken out of SOUNDS leaves its old files behind; remove them.
    for folder in ASSET_FOLDER.glob("*.dataset"):
        if folder.name not in written:
            shutil.rmtree(folder)
            print(f"removed {folder.name}")


if __name__ == "__main__":
    main()
