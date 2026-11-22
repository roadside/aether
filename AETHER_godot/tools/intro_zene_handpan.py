"""AETHER – a kezdő animáció zenéje: lágy, handpan-szerű dallam (saját szintézis).

Nem felvétel és nem minta: minden hang matematikailag készül (szinusz-részhangok
lecsengéssel, enyhe lebegéssel, rövid "kézütés" zajjal, majd egyszerű tér-visszhang).
Hangsor: D kurd (D3 A3 B♭3 C4 D4 E4 F4 G4 A4), ahogy a legtöbb handpan.
A dallam a snittekhez igazodik (kb. 28 mp × PACE + lecsengés).

Futtatás (csak a Python standard könyvtára kell):
    py tools/intro_zene_handpan.py
Kimenet: assets/hang/intro_handpan.wav (sztereó, 22 050 Hz, 16 bit)
"""
import math
import os
import random
import struct
import wave

SR = 22050
PACE = 1.6            # ugyanaz, mint az intro.gd PACE-e: a snittek ennyivel lassabbak
LENGTH = 28.0 * PACE + 5.0
N = int(SR * LENGTH)

NOTE = {"D3": 146.83, "A3": 220.00, "Bb3": 233.08, "C4": 261.63, "D4": 293.66,
        "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00}
PAN = {"D3": 0.0, "A3": -0.35, "Bb3": 0.35, "C4": -0.5, "D4": 0.5,
       "E4": -0.25, "F4": 0.25, "G4": -0.4, "A4": 0.4}

# (idő mp PACE = 1 mellett, hang, erősség) – snittenként
SCORE = [
    # 1. űr
    (0.20, "D3", 0.90), (1.90, "A3", 0.50), (2.90, "D4", 0.40),
    # 2. „Ez a Föld ma.”
    (3.90, "D3", 0.80), (4.50, "A3", 0.50), (5.00, "D4", 0.50), (5.50, "F4", 0.55),
    (6.30, "E4", 0.45), (7.00, "D4", 0.40), (7.60, "A3", 0.45), (8.30, "C4", 0.40),
    # 3. hőmérséklet-eltérés (B♭: egy kis feszültség)
    (8.90, "D3", 0.70), (9.40, "Bb3", 0.55), (9.90, "D4", 0.50), (10.40, "F4", 0.55),
    (11.20, "G4", 0.50), (11.80, "F4", 0.40), (12.40, "E4", 0.45), (13.10, "C4", 0.40),
    # 4. események (kicsit sűrűbb)
    (13.90, "D3", 0.75), (14.30, "A3", 0.45), (14.70, "E4", 0.50), (15.10, "F4", 0.50),
    (15.50, "A4", 0.55), (16.20, "G4", 0.45), (16.60, "F4", 0.40), (17.00, "E4", 0.45),
    (17.60, "C4", 0.40), (18.20, "A3", 0.40),
    # 5. kutatóállomás (meleg, reményteli)
    (18.90, "D3", 0.80), (19.40, "A3", 0.50), (19.90, "D4", 0.50), (20.40, "E4", 0.50),
    (20.90, "F4", 0.55), (21.60, "A4", 0.50), (22.40, "G4", 0.45), (23.10, "E4", 0.45),
    # 6. zárás: feloldás D-re
    (23.90, "D3", 0.80), (23.92, "A3", 0.45), (24.60, "D4", 0.40), (25.60, "A4", 0.35),
    (27.00, "D3", 0.65), (27.03, "D4", 0.35),
]


def handpan(f, vel, out_l, out_r, start, pan):
    """Egy handpan-ütés: alaphang + oktáv + kvint fölötte, mindegyik másképp cseng le."""
    tau0 = 3.4 if f < 200 else 2.6          # mélyebb hang tovább zeng
    partials = [  # (frekvencia-szorzó, hangerő, lecsengési idő)
        (1.0, 1.00, tau0), (1.0 + 0.6 / f, 0.30, tau0 * 0.9),   # lassú lebegés
        (2.0, 0.42, tau0 * 0.42), (3.0, 0.16, tau0 * 0.22), (4.02, 0.05, 0.25)]
    dur = min(N - start, int(SR * tau0 * 4))
    gl = math.cos((pan + 1) * math.pi / 4)
    gr = math.sin((pan + 1) * math.pi / 4)
    lp = 0.0
    rnd = random.Random(int(f * 100) + start)
    phase = [rnd.random() * 0.2 for _ in partials]
    for i in range(dur):
        t = i / SR
        att = min(1.0, t / 0.006)               # lágy, kézzel ütött indulás
        s = 0.0
        for (m, a, tau), ph in zip(partials, phase):
            s += a * math.exp(-t / tau) * math.sin(2 * math.pi * f * m * t + ph)
        if i < SR * 0.02:                       # rövid, tompa "kézütés" zaj
            lp += 0.15 * ((rnd.random() * 2 - 1) - lp)
            s += lp * 0.25 * (1 - i / (SR * 0.02))
        v = s * att * vel * 0.22
        out_l[start + i] += v * gl
        out_r[start + i] += v * gr


def reverb(x, offset):
    """Egyszerű Schroeder-visszhang (4 fésűszűrő + 2 mindentáteresztő), csillapítással."""
    combs = [int(d * SR / 44100) + offset for d in (1116, 1188, 1277, 1356)]
    out = [0.0] * len(x)
    for d in combs:
        buf = [0.0] * d
        idx = 0
        store = 0.0
        for i in range(len(x)):
            y = buf[idx]
            store = y * 0.6 + store * 0.4          # magas hangok gyorsabban halnak el
            buf[idx] = x[i] + store * 0.84
            idx = (idx + 1) % d
            out[i] += y
    for d in (int(556 * SR / 44100) + offset, int(441 * SR / 44100)):
        buf = [0.0] * d
        idx = 0
        for i in range(len(out)):
            b = buf[idx]
            y = -out[i] + b
            buf[idx] = out[i] + b * 0.5
            idx = (idx + 1) % d
            out[i] = y
    return out


def main():
    rnd = random.Random(2026)
    L = [0.0] * N
    R = [0.0] * N
    for t, n, v in SCORE:
        t = t * PACE + rnd.uniform(-0.015, 0.015)          # emberi időzítés
        handpan(NOTE[n], v, L, R, max(0, int(t * SR)), PAN[n])
    # nagyon halk, meleg alapzúgás (D2 + A2), hogy ne legyen „üres” a tér
    for i in range(N):
        t = i / SR
        env = min(1.0, max(0.0, (t - 3.0) / 5.0)) * min(1.0, max(0.0, (LENGTH - 2.5 - t) / 3.0))
        d = 0.018 * env * (math.sin(2 * math.pi * 73.42 * t) + 0.6 * math.sin(2 * math.pi * 110.0 * t + 0.4 * math.sin(0.3 * t)))
        L[i] += d
        R[i] += d
    wl = reverb(L, 0)
    wr = reverb(R, 23)
    mix_l = [a * 0.75 + b * 0.09 for a, b in zip(L, wl)]
    mix_r = [a * 0.75 + b * 0.09 for a, b in zip(R, wr)]
    peak = max(max(abs(v) for v in mix_l), max(abs(v) for v in mix_r))
    g = 0.7 / peak
    fade = int(SR * 2.5)
    frames = bytearray()
    for i in range(N):
        f = min(1.0, (N - i) / fade)
        frames += struct.pack("<hh", int(mix_l[i] * g * f * 32767), int(mix_r[i] * g * f * 32767))
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(here, "..", "assets", "hang")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "intro_handpan.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("kész:", os.path.normpath(path), "csúcs-szorzó %.2f" % g)


if __name__ == "__main__":
    main()
