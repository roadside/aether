"""AETHER – a játék közbeni hangok és az alapzene, teljesen kódból előállítva (saját szintézis).

Nem felvétel és nem minta: minden hang matematikailag készül (handpan-szerű szinusz-részhangok
lecsengéssel, enyhe lebegéssel, rövid „kézütés” zajjal, egyszerű tér-visszhanggal), ugyanabban a
D kurd hangsorban, mint a nyitány zenéje. Nincs benne más szerző zenéje.

Hangok (assets/hang/):
  egyezseg.wav    – egyezség kötve: emelkedő, nyitott hangzat (kb. 4,5 mp)
  megingas.wav    – egy csoport megingott: ereszkedő, lebegő két hang (kb. 3,5 mp)
  billenes.wav    – billenőpont átlépve: mély morajlás és feszült hangköz (kb. 7 mp)
  kartya.wav      – új bizonyíték-kártya: rövid, csillanó két hang (kb. 2 mp)
  korvaltas.wav   – telik öt év: halk suhanás és két lágy hang (kb. 3 mp)
  kattintas.wav   – gombnyomás: egyetlen rövid, halk hang (0,5 mp)
  jo_hir.wav      – jó hír (egy csoport elérte a nullát): felfelé futó, derűs hangzat (kb. 3,5 mp)
  katasztrofa.wav – rossz hír (hőhullám, aszály, áradás, erdőtűz): mély ütés és feszült hangköz (kb. 5 mp)
  alapzene2.wav   – a második alapzene: más hangzatsor, ugyanabban a hangsorban (64 mp)
  alapzene.wav    – halk, ismétlődő alapzene játék közbe (64 mp, hézag nélkül ismételhető)

Futtatás (csak a Python standard könyvtára kell):  python tools/jatek_hangok.py [kimeneti mappa]
Alapból a projekt assets/hang mappájába ír.
"""
import math
import random
import struct
import sys
import wave
from pathlib import Path

SR = 22050
NOTE = {"D2": 73.42, "A2": 110.00, "D3": 146.83, "A3": 220.00, "Bb3": 233.08, "C4": 261.63, "D4": 293.66,
        "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00, "Bb4": 466.16, "C5": 523.25, "D5": 587.33}
PAN = {"D2": 0.0, "A2": 0.0, "D3": 0.0, "A3": -0.35, "Bb3": 0.35, "C4": -0.5, "D4": 0.5, "E4": -0.25,
       "F4": 0.25, "G4": -0.4, "A4": 0.4, "Bb4": -0.3, "C5": 0.3, "D5": -0.2}


class Buf:
    def __init__(self, seconds):
        self.n = int(SR * seconds)
        self.l = [0.0] * self.n
        self.r = [0.0] * self.n

    def add(self, i, vl, vr, wrap=False):
        if wrap:
            i %= self.n
        elif i >= self.n:
            return
        self.l[i] += vl
        self.r[i] += vr


def handpan(buf, t0, note, vel, wrap=False, tau_scale=1.0):
    """Egy handpan-ütés: alaphang + lebegő párja + oktáv + duodecima, eltérő lecsengéssel."""
    f = NOTE[note]
    tau0 = (3.4 if f < 200 else 2.6) * tau_scale
    partials = [(1.0, 1.00, tau0), (1.0 + 0.6 / f, 0.30, tau0 * 0.9), (2.0, 0.42, tau0 * 0.42),
                (3.0, 0.16, tau0 * 0.22), (4.02, 0.05, 0.25)]
    start = int(t0 * SR)
    dur = int(SR * tau0 * 4)
    pan = PAN.get(note, 0.0)
    gl, gr = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
    rnd = random.Random(int(f * 100) + start)
    phase = [rnd.random() * 0.2 for _ in partials]
    lp = 0.0
    for i in range(dur):
        t = i / SR
        att = min(1.0, t / 0.006)
        s = 0.0
        for (m, a, tau), ph in zip(partials, phase):
            e = math.exp(-t / tau)
            if e > 1e-4:
                s += a * e * math.sin(2 * math.pi * f * m * t + ph)
        if i < SR * 0.02:
            lp += 0.15 * ((rnd.random() * 2 - 1) - lp)
            s += lp * 0.25 * (1 - i / (SR * 0.02))
        v = s * att * vel * 0.32
        buf.add(start + i, v * gl, v * gr, wrap)


def rumble(buf, t0, seconds, vel, wrap=False):
    """Mély morajlás: szűrt zaj és egy lassan erősödő-halkuló D2–A2 alapzúgás."""
    rnd = random.Random(7)
    start = int(t0 * SR)
    n = int(seconds * SR)
    lp1 = lp2 = 0.0
    for i in range(n):
        t = i / SR
        env = math.sin(math.pi * min(1.0, t / seconds)) ** 1.5
        lp1 += 0.02 * ((rnd.random() * 2 - 1) - lp1)
        lp2 += 0.02 * (lp1 - lp2)
        drone = 0.55 * math.sin(2 * math.pi * NOTE["D2"] * t) + 0.25 * math.sin(2 * math.pi * NOTE["A2"] * t + 0.3)
        v = (lp2 * 6.0 + drone * 0.35) * env * vel * 0.30
        buf.add(start + i, v, v * 0.96, wrap)


def whoosh(buf, t0, seconds, vel):
    """Halk suhanás: sávszűrt zaj, ami balról jobbra úszik át."""
    rnd = random.Random(11)
    start = int(t0 * SR)
    n = int(seconds * SR)
    lp = 0.0
    for i in range(n):
        x = i / n
        env = math.sin(math.pi * x) ** 2
        w = rnd.random() * 2 - 1
        lp += 0.25 * (w - lp)
        v = lp * env * vel * 0.12
        buf.add(start + i, v * (1 - x), v * x)


def reverb(buf, wrap=False):
    """Egyszerű tér-visszhang: néhány késleltetett, halkuló visszaverődés (sztereó szétterítve)."""
    taps = [(0.043, 0.32), (0.071, 0.26), (0.113, 0.20), (0.167, 0.15), (0.229, 0.11), (0.311, 0.08)]
    ol, orr = buf.l[:], buf.r[:]
    for d, g in taps:
        dl = int(d * SR)
        dr = int((d * 1.07) * SR)
        for i in range(buf.n):
            j = i - dl
            if j >= 0 or wrap:
                buf.l[i] += ol[j % buf.n] * g
            j = i - dr
            if j >= 0 or wrap:
                buf.r[i] += orr[j % buf.n] * g


def write(buf, path, peak=0.8, fade_out=0.0):
    m = max(1e-9, max(max(abs(x) for x in buf.l), max(abs(x) for x in buf.r)))
    g = peak / m
    fo = int(fade_out * SR)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for i in range(buf.n):
            f = 1.0
            if fo and i > buf.n - fo:
                f = (buf.n - i) / fo
            frames += struct.pack("<hh", int(max(-1, min(1, buf.l[i] * g * f)) * 32767),
                                  int(max(-1, min(1, buf.r[i] * g * f)) * 32767))
        w.writeframes(bytes(frames))
    print(f"{path.name}: {buf.n / SR:.1f} mp")


def sound(seconds, notes, extra=None):
    b = Buf(seconds)
    for t, n, v in notes:
        handpan(b, t, n, v)
    if extra:
        extra(b)
    reverb(b)
    return b


def ambient(variant=1):
    """64 mp-es alapzene: lassú, nyugodt arpeggio a D kurd hangsorban, ismétlődve hézag nélkül.
    A lecsengések a fájl elejére „tekerednek”, így a vége és az eleje összeillik."""
    length = 64.0
    b = Buf(length)
    # négy 16 mp-es szakasz, mindegyik más hangzattal (D – B♭ – C – D), ütemenként 2 mp
    chords = [["D3", "A3", "D4", "F4", "E4", "A3", "C4", "A3"],
              ["D3", "Bb3", "D4", "F4", "G4", "F4", "D4", "Bb3"],
              ["D3", "C4", "E4", "G4", "A4", "G4", "E4", "C4"],
              ["D3", "A3", "D4", "E4", "F4", "E4", "D4", "A3"]]
    if variant == 2:   # második változat: magasabbról induló, B♭ – D – C – A hangzatsor
        chords = [["D3", "Bb3", "F4", "D4", "G4", "D4", "F4", "Bb3"],
                  ["D3", "A3", "E4", "A4", "F4", "E4", "D4", "A3"],
                  ["D3", "C4", "G4", "E4", "C5", "G4", "E4", "C4"],
                  ["D3", "A3", "C4", "E4", "A4", "E4", "D4", "A3"]]
    rnd = random.Random(2026 if variant == 1 else 2026 + variant)
    for s, ch in enumerate(chords):
        for k, note in enumerate(ch):
            t = s * 16.0 + k * 2.0 + rnd.uniform(-0.05, 0.05)
            vel = 0.55 if note == "D3" else 0.32 + rnd.uniform(-0.04, 0.04)
            handpan(b, t, note, vel, wrap=True, tau_scale=1.25)
            if k % 4 == 1 and rnd.random() < 0.5:   # ritka díszítőhang
                handpan(b, t + 1.0, rnd.choice(["A4", "G4", "F4"]), 0.18, wrap=True, tau_scale=1.25)
    reverb(b, wrap=True)
    return b


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "assets" / "hang"
    out.mkdir(parents=True, exist_ok=True)
    write(sound(4.5, [(0.00, "D3", 0.65), (0.05, "A3", 0.45), (0.25, "D4", 0.55), (0.45, "F4", 0.55),
                      (0.65, "A4", 0.6), (0.90, "D5", 0.65)]), out / "egyezseg.wav", fade_out=0.6)
    write(sound(3.5, [(0.00, "Bb3", 0.6), (0.04, "D4", 0.3), (0.60, "A3", 0.55), (0.64, "C4", 0.28)]),
          out / "megingas.wav", fade_out=0.6)
    write(sound(7.0, [(0.40, "D3", 0.9), (0.45, "Bb3", 0.55), (1.60, "A3", 0.5), (1.65, "Bb3", 0.4)],
                extra=lambda b: rumble(b, 0.0, 6.5, 1.0)), out / "billenes.wav", fade_out=1.0)
    write(sound(2.0, [(0.00, "A4", 0.45), (0.12, "D5", 0.55)]), out / "kartya.wav", fade_out=0.5)
    write(sound(3.0, [(0.55, "D3", 0.45), (0.75, "A3", 0.35)], extra=lambda b: whoosh(b, 0.0, 1.4, 1.0)),
          out / "korvaltas.wav", fade_out=0.6)
    write(sound(0.5, [(0.00, "D5", 0.35)]), out / "kattintas.wav", peak=0.35, fade_out=0.3)
    write(sound(3.5, [(0.00, "D4", 0.5), (0.18, "F4", 0.5), (0.36, "A4", 0.55), (0.60, "D5", 0.6), (0.62, "A4", 0.3)]),
          out / "jo_hir.wav", fade_out=0.6)
    write(sound(5.0, [(0.30, "D3", 0.8), (0.34, "A3", 0.5), (1.10, "Bb3", 0.55), (1.14, "E4", 0.4)],
                extra=lambda b: rumble(b, 0.0, 4.5, 0.7)), out / "katasztrofa.wav", fade_out=0.8)
    write(ambient(2), out / "alapzene2.wav", peak=0.55)
    write(ambient(), out / "alapzene.wav", peak=0.55)


if __name__ == "__main__":
    main()
