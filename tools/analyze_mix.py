#!/usr/bin/env python3
"""Objective checks of a Movie Maker capture's audio (NOT a listening test).

    ffmpeg -i work/movie/ride.avi -vn work/movie/ride.wav
    python3 tools/analyze_mix.py work/movie/ride.wav work/movie/ride.log

Prints peak/RMS per second, overall peak and clipping count, and for each event
in the log (lines "EVENT t=<sec> <kind> <strength>") the band energy just before
and after it, e.g. to confirm snow friction disappears in the air and returns
on landing, and that impacts carry low-frequency weight.
"""
import re
import sys
import wave
import numpy as np


def load(path):
    w = wave.open(path)
    n, ch, sr = w.getnframes(), w.getnchannels(), w.getframerate()
    x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
    return x.reshape(-1, ch), sr


def db(v):
    return 20 * np.log10(max(v, 1e-9))


def band_rms(x, sr, lo, hi):
    spec = np.fft.rfft(x * np.hanning(len(x)))
    f = np.fft.rfftfreq(len(x), 1 / sr)
    sel = (f >= lo) & (f < hi)
    return np.sqrt(np.sum(np.abs(spec[sel]) ** 2) / len(x)) / len(x) * 2


def main():
    audio, sr = load(sys.argv[1])
    mono = audio.mean(axis=1)
    peak = np.max(np.abs(audio))
    clipped = int(np.sum(np.abs(audio) > 0.999))
    print(f"duration {len(mono) / sr:.1f}s  peak {db(peak):.2f} dBFS  clipped samples {clipped}  overall RMS {db(np.sqrt(np.mean(mono ** 2))):.1f} dBFS")
    for s in range(int(len(mono) / sr)):
        seg = mono[s * sr:(s + 1) * sr]
        print(f"  t={s:3d}s rms {db(np.sqrt(np.mean(seg ** 2))):6.1f}  peak {db(np.max(np.abs(seg))):6.1f}  low<150Hz {db(band_rms(seg, sr, 20, 150)):6.1f}  hiss2-8k {db(band_rms(seg, sr, 2000, 8000)):6.1f}")
    if len(sys.argv) > 2:
        events = []
        for line in open(sys.argv[2], errors="ignore"):
            m = re.match(r"EVENT t=([\d.]+) (\w+) ([\d.]+)", line.strip())
            if m:
                events.append((float(m.group(1)), m.group(2), float(m.group(3))))
        win = int(0.15 * sr)
        for t, kind, strength in events:
            i = int(t * sr)
            before = mono[max(0, i - win):i]
            after = mono[i:i + win]
            if len(before) < win or len(after) < win:
                continue
            print(f"EVENT {kind:14s} t={t:6.2f}  hiss2-8k before {db(band_rms(before, sr, 2000, 8000)):6.1f} after {db(band_rms(after, sr, 2000, 8000)):6.1f}  low<150 after {db(band_rms(after, sr, 20, 150)):6.1f}  peak after {db(np.max(np.abs(after))):6.1f}")


if __name__ == "__main__":
    main()
