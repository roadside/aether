"""A kezdőanimáció zenéje: lágy, handpan hangzású saját dallam, teljesen kódból előállítva.

Nincs benne felvett hang vagy más zenéjéből vett részlet: minden hangot ez a program számol ki
(alaphang + oktáv + kvint felhang, gyors megütés, lassú lecsengés, a végén zengetés).
Hangolás: d-moll („kurd”) handpan skála: D3 · A3 B3(b) C4 D4 E4 F4 G4 A4.
Csak a Python alapkönyvtára kell hozzá.

Használat:  python tools/intro_zene.py            ->  assets/hang/intro.wav
"""
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 32000
LENGTH = 42.0
NOTE = {"D3": 146.83, "A3": 220.00, "Bb3": 233.08, "C4": 261.63, "D4": 293.66, "E4": 329.63,
        "F4": 349.23, "G4": 392.00, "A4": 440.00, "C5": 523.25, "D5": 587.33}

# (idő mp, hang, erő): a snittekhez igazítva (0 űr · 5 földgömb · 13 képek · 21 állomás · 30 görbe · 36 cím)
SEQ = [
    # 0–5: csend az űrben, néhány mély, ritka hang
    (0.30, "D3", 0.75), (2.00, "A3", 0.45), (3.25, "D4", 0.40), (4.10, "A3", 0.30),
    # 5–13: lassú, ringó felbontás
    (5.00, "D3", 0.80), (5.42, "A3", 0.45), (5.83, "D4", 0.50), (6.25, "F4", 0.55), (6.67, "A4", 0.50),
    (7.08, "F4", 0.35), (7.50, "D4", 0.40), (7.92, "A3", 0.35),
    (8.33, "D3", 0.70), (8.75, "A3", 0.40), (9.17, "C4", 0.50), (9.58, "E4", 0.50), (10.00, "G4", 0.55),
    (10.42, "E4", 0.35), (10.83, "C4", 0.40), (11.25, "A3", 0.35),
    (11.67, "D3", 0.70), (12.08, "Bb3", 0.45), (12.50, "D4", 0.45),
    # 13–21: a négy kép: mélyebb, feszültebb, minden vágásra egy mély ütés
    (13.00, "D3", 0.95), (13.42, "Bb3", 0.50), (13.83, "E4", 0.45), (14.25, "Bb3", 0.35), (14.58, "C4", 0.30),
    (15.00, "D3", 0.95), (15.42, "C4", 0.50), (15.83, "E4", 0.50), (16.25, "G4", 0.45), (16.58, "E4", 0.30),
    (17.00, "D3", 0.95), (17.42, "Bb3", 0.50), (17.83, "D4", 0.50), (18.25, "F4", 0.45), (18.58, "E4", 0.35),
    (19.00, "D3", 0.95), (19.42, "A3", 0.50), (19.83, "C4", 0.50), (20.25, "E4", 0.50), (20.62, "G4", 0.40),
    # 21–30: az állomás: melegebb, világosabb (F–A–C körül)
    (21.00, "D3", 0.60), (21.00, "F4", 0.60), (21.42, "A4", 0.50), (21.83, "C5", 0.50), (22.25, "A4", 0.40),
    (22.67, "F4", 0.45), (23.08, "C4", 0.40), (23.50, "A3", 0.40), (23.92, "C4", 0.40),
    (24.33, "D3", 0.55), (24.33, "G4", 0.55), (24.75, "A4", 0.45), (25.17, "D5", 0.50), (25.58, "A4", 0.40),
    (26.00, "G4", 0.45), (26.42, "D4", 0.40), (26.83, "Bb3", 0.40), (27.25, "D4", 0.40),
    (27.67, "D3", 0.55), (27.67, "F4", 0.55), (28.08, "A4", 0.45), (28.50, "C5", 0.50), (28.92, "D5", 0.45),
    (29.33, "C5", 0.40), (29.67, "A4", 0.35),
    # 30–36: a görbe meghajlik: emelkedő, reményteli dallam
    (30.00, "D3", 0.80), (30.00, "D4", 0.55), (30.42, "F4", 0.50), (30.83, "A4", 0.55), (31.25, "D5", 0.55),
    (31.67, "A4", 0.40), (32.08, "F4", 0.40),
    (32.50, "D3", 0.70), (32.50, "E4", 0.50), (32.92, "G4", 0.50), (33.33, "C5", 0.55), (33.75, "D5", 0.50),
    (34.17, "C5", 0.40), (34.58, "A4", 0.45), (35.00, "G4", 0.40), (35.42, "A4", 0.45),
    # 36–40: a cím: nyitott D-hangzat, hagyjuk kicsengeni
    (36.00, "D3", 0.80), (36.06, "A3", 0.45), (36.12, "D4", 0.45), (36.18, "A4", 0.45), (36.26, "D5", 0.40),
    (37.25, "A4", 0.30), (37.67, "D5", 0.30), (38.50, "D4", 0.25),
]


def render_note(buf, t0, f, vel, rnd):
    """Egy handpan-hang: három összehangolt felhang (1 : 2 : 3), puha kéz-ütéssel."""
    n0 = int(t0 * RATE)
    dur = 3.4 if f < 200 else 2.8
    n = min(int(dur * RATE), len(buf) - n0)
    low = f < 200
    parts = [(1.0, 1.00, 1.50 if low else 1.10), (2.0, 0.50 if low else 0.42, 0.95), (3.0, 0.22, 0.60),
             (1.0 + 0.9 / f, 0.25, 1.30)]          # enyhén elhangolt pár: lassú lebegés
    w = [2.0 * math.pi * f * m / RATE for m, _a, _d in parts]
    dec = [math.exp(-1.0 / (d * RATE)) for _m, _a, d in parts]
    amp = [a * vel * 0.30 for _m, a, _d in parts]
    attack = int(0.006 * RATE)
    lp = 0.0
    for i in range(n):
        s = 0.0
        for k in range(len(parts)):
            s += amp[k] * math.sin(w[k] * i)
            amp[k] *= dec[k]
        if i < 700:                                   # az ujj koppanása: rövid, tompított zaj
            lp += 0.18 * (rnd.uniform(-1.0, 1.0) - lp)
            s += lp * vel * 0.35 * (1.0 - i / 700.0) ** 2
        if i < attack:
            s *= i / attack
        buf[n0 + i] += s


def reverb(x):
    """Egyszerű terem-zengetés: négy visszacsatolt késleltetés és két szóró szűrő."""
    out = [0.0] * len(x)
    for delay, fb in ((1557, 0.80), (1617, 0.79), (1491, 0.81), (1422, 0.82)):
        d = int(delay * RATE / 32000 * 1.35)
        ring = [0.0] * d
        damp = 0.0
        j = 0
        for i, v in enumerate(x):
            y = ring[j]
            damp += 0.45 * (y - damp)                 # a magas hangok hamarabb csengjenek le
            ring[j] = v + damp * fb
            out[i] += y
            j += 1
            if j == d:
                j = 0
    for delay in (225, 556):
        d = int(delay * RATE / 32000)
        ring = [0.0] * d
        j = 0
        for i, v in enumerate(out):
            b = ring[j]
            y = -0.5 * v + b
            ring[j] = v + 0.5 * y
            out[i] = y
            j += 1
            if j == d:
                j = 0
    return out


def main(path):
    rnd = random.Random(2026)
    n = int(LENGTH * RATE)
    dry = [0.0] * n
    for t, name, vel in SEQ:
        render_note(dry, t, NOTE[name], vel, rnd)
    # halk, mély alapzúgás (D2 + A2), lassan lélegzik
    for i in range(n):
        t = i / RATE
        swell = min(1.0, t / 6.0) * (0.75 + 0.25 * math.sin(2 * math.pi * t / 9.0))
        dry[i] += 0.035 * swell * (math.sin(2 * math.pi * 73.42 * t) + 0.5 * math.sin(2 * math.pi * 110.0 * t))
    wet = reverb(dry)
    mix = [d * 0.80 + w * 0.085 for d, w in zip(dry, wet)]
    peak = max(abs(v) for v in mix) or 1.0
    fade = int(2.0 * RATE)
    frames = bytearray()
    for i, v in enumerate(mix):
        g = 0.89 / peak
        if i > n - fade:
            g *= (n - i) / fade
        frames += struct.pack("<h", int(max(-1.0, min(1.0, v * g)) * 32767))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(bytes(frames))
    print(f"{path}: {LENGTH:.0f} mp, {len(frames) // 1024} kB, csúcs {peak:.2f}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "assets" / "hang" / "intro.wav")
