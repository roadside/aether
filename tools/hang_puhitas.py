"""AETHER – a játék hangjainak puhítása (Zoltán kérése, 2026-11-27: „puhább és kevésbé zavaró hangok”).

A kódból készült hanghatásokat (nem a zenéket) lágyítja: kétszeres aluláteresztő szűrő (1500 Hz),
40 ms-os lágy indulás az éles ütés helyett, és kisebb hangerő (a csúcs 60%-a).
EGYSZER kell lefuttatni a tools/jatek_hangok.py friss kimenetén; ismételt futtatás tovább tompítana.

Futtatás:  python tools/hang_puhitas.py [mappa]     (alapból assets/hang)
"""
import math
import struct
import sys
import wave
from pathlib import Path

FILES = ["egyezseg", "megingas", "billenes", "kartya", "korvaltas", "jo_hir", "katasztrofa", "veszely", "lendulet",
         "ora", "jel_evtized", "jel_jo", "jel_rossz", "zaro"]
CUT_HZ = 1500.0
ATTACK_S = 0.04
GAIN = 0.6


def soften(path: Path) -> None:
    with wave.open(str(path), "rb") as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        print("kihagyva (nem 16 bites):", path.name)
        return
    data = list(struct.unpack("<%dh" % (n * ch), raw))
    a = 1.0 - math.exp(-2.0 * math.pi * CUT_HZ / sr)
    att = max(1, int(ATTACK_S * sr))
    for c in range(ch):
        y1 = y2 = 0.0
        for i in range(n):
            x = data[i * ch + c]
            y1 += a * (x - y1)
            y2 += a * (y1 - y2)
            v = y2 * GAIN
            if i < att:
                v *= 0.5 - 0.5 * math.cos(math.pi * i / att)
            data[i * ch + c] = int(max(-32767, min(32767, v)))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(struct.pack("<%dh" % (n * ch), *data))
    print("puhítva:", path.name)


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "assets" / "hang"
    for name in FILES:
        p = out / (name + ".wav")
        if p.exists():
            soften(p)


if __name__ == "__main__":
    main()
