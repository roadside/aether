"""AETHER – a kezdő animáció zenéje: lágy, handpan-szerű dallam (saját szintézis).

Nem felvétel és nem minta: minden hang matematikailag készül (szinusz-részhangok
lecsengéssel, enyhe lebegéssel, rövid "kézütés" zajjal, majd egyszerű tér-visszhang).
Hangsor: D kurd (D3 A3 B♭3 C4 D4 E4 F4 G4 A4), ahogy a legtöbb handpan.
A dallam a bevezető snittjeihez igazodik (kb. 58,5 mp + lecsengés; lásd intro.gd).

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
LENGTH = 58.5 + 5.0
N = int(SR * LENGTH)

NOTE = {"D3": 146.83, "A3": 220.00, "Bb3": 233.08, "C4": 261.63, "D4": 293.66,
        "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00}
PAN = {"D3": 0.0, "A3": -0.35, "Bb3": 0.35, "C4": -0.5, "D4": 0.5,
       "E4": -0.25, "F4": 0.25, "G4": -0.4, "A4": 0.4}

# Snittenként: (kezdet mp, [(idő a snitten belül, hang, erősség), ...]).
# A kezdetek az intro.gd időbeosztását követik.
SECTIONS = [
    (0.0, [  # 1. űr, „2026.”
        (0.25, "D3", 0.90), (2.30, "A3", 0.50), (3.70, "D4", 0.40)]),
    (5.0, [  # 2. „Ez a Föld ma.”
        (0.0, "D3", 0.80), (0.7, "A3", 0.50), (1.3, "D4", 0.50), (1.9, "F4", 0.55),
        (2.9, "E4", 0.45), (3.7, "D4", 0.40), (4.4, "A3", 0.45), (5.2, "C4", 0.40)]),
    (11.0, [  # 3. évszámláló: lassan emelkedő dallam, ahogy telnek az évek
        (0.0, "D3", 0.75), (0.9, "A3", 0.45), (1.8, "C4", 0.45), (2.7, "D4", 0.48),
        (3.6, "E4", 0.50), (4.5, "F4", 0.52), (5.4, "G4", 0.52), (6.3, "A4", 0.55),
        (7.2, "G4", 0.42), (7.8, "F4", 0.40)]),
    (19.5, [  # 4. hőmérséklet-eltérés (B♭: egy kis feszültség)
        (0.0, "D3", 0.70), (0.6, "Bb3", 0.55), (1.2, "D4", 0.50), (1.8, "F4", 0.55),
        (2.8, "G4", 0.50), (3.5, "F4", 0.40), (4.2, "E4", 0.45), (5.0, "C4", 0.40)]),
    (25.5, [  # 5. négy festett kép, 4–4 mp
        (0.0, "D3", 0.75), (0.6, "A3", 0.45), (1.3, "E4", 0.48), (2.2, "F4", 0.48), (3.1, "E4", 0.40),
        (4.0, "Bb3", 0.65), (4.6, "D4", 0.45), (5.3, "F4", 0.48), (6.2, "E4", 0.42), (7.1, "C4", 0.40),
        (8.0, "D3", 0.70), (8.6, "A3", 0.45), (9.3, "C4", 0.45), (10.2, "D4", 0.45), (11.1, "Bb3", 0.42),
        (12.0, "D3", 0.75), (12.6, "Bb3", 0.50), (13.3, "F4", 0.50), (14.2, "G4", 0.50), (15.1, "F4", 0.42)]),
    (41.5, [  # 6. kutatóállomás (meleg, reményteli)
        (0.0, "D3", 0.80), (0.6, "A3", 0.50), (1.3, "D4", 0.50), (2.0, "E4", 0.50),
        (2.7, "F4", 0.55), (3.6, "A4", 0.50), (4.6, "G4", 0.45), (5.5, "E4", 0.45)]),
    (48.0, [  # 7. a jövő még nincs megírva: kérdés, aztán felfelé nyíló válasz
        (0.0, "Bb3", 0.60), (0.8, "D4", 0.45), (1.6, "F4", 0.45), (2.7, "C4", 0.42),
        (3.4, "E4", 0.48), (4.2, "G4", 0.50), (5.0, "A4", 0.55)]),
    (54.5, [  # 8. zárás: feloldás D-re, hosszú lecsengés
        (0.0, "D3", 0.80), (0.02, "A3", 0.45), (0.9, "D4", 0.40), (1.9, "A4", 0.35),
        (3.1, "D3", 0.60), (3.13, "D4", 0.35)]),
]
SCORE = [(start + t, n, v) for start, notes in SECTIONS for t, n, v in notes]


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
        t = t + rnd.uniform(-0.015, 0.015)          # emberi időzítés
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
