"""Rövid jelzőhangok a játékhoz (fordulópontok, záró jelenet), teljesen kódból előállítva.

Ugyanaz a saját handpan-hangzás, mint a tools/intro_zene.py-ban: nincs benne felvett hang
vagy más zenéjéből vett részlet.

Használat:  python tools/hangok.py   ->  assets/hang/jel_jo.wav, jel_rossz.wav, jel_evtized.wav, zaro.wav
"""
import random
import struct
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import intro_zene as Z  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "assets" / "hang"

SOUNDS = {
    # jó hír: emelkedő, nyitott hangzat
    "jel_jo": (4.5, [(0.00, "D3", 0.7), (0.05, "D4", 0.6), (0.22, "F4", 0.6), (0.40, "A4", 0.65), (0.62, "D5", 0.7)]),
    # rossz hír: két mély, ereszkedő hang
    "jel_rossz": (4.5, [(0.00, "D3", 0.95), (0.06, "Bb3", 0.6), (0.55, "A3", 0.55)]),
    # évtized: egyetlen lágy hang
    "jel_evtized": (3.5, [(0.00, "A3", 0.5), (0.18, "D4", 0.45)]),
    # záró jelenet: lassú, nyugodt dallam (kb. 30 mp)
    "zaro": (32.0, [
        (0.5, "D3", 0.8), (1.0, "A3", 0.45), (1.5, "D4", 0.5), (2.0, "F4", 0.5), (2.5, "A4", 0.5),
        (4.0, "D3", 0.7), (4.5, "Bb3", 0.45), (5.0, "D4", 0.5), (5.5, "G4", 0.5), (6.0, "Bb3", 0.35),
        (8.0, "D3", 0.75), (8.5, "C4", 0.45), (9.0, "E4", 0.5), (9.5, "G4", 0.5), (10.0, "C5", 0.5),
        (12.0, "D3", 0.75), (12.5, "A3", 0.45), (13.0, "D4", 0.5), (13.5, "F4", 0.55), (14.0, "A4", 0.55), (14.5, "D5", 0.55),
        (16.0, "D3", 0.7), (16.0, "F4", 0.5), (16.5, "A4", 0.45), (17.0, "C5", 0.5), (17.5, "A4", 0.4),
        (19.0, "D3", 0.7), (19.0, "G4", 0.5), (19.5, "A4", 0.45), (20.0, "D5", 0.5), (20.5, "A4", 0.4),
        (22.0, "D3", 0.8), (22.06, "A3", 0.45), (22.12, "D4", 0.45), (22.18, "A4", 0.45), (22.26, "D5", 0.4),
        (24.5, "A4", 0.3), (25.2, "D5", 0.3), (26.5, "D4", 0.25),
    ]),
}


def render(name, length, seq):
    rnd = random.Random(hash(name) & 0xFFFF)
    n = int(length * Z.RATE)
    dry = [0.0] * n
    for t, note, vel in seq:
        Z.render_note(dry, t, Z.NOTE[note], vel, rnd)
    wet = Z.reverb(dry)
    mix = [d * 0.80 + w * 0.085 for d, w in zip(dry, wet)]
    peak = max(abs(v) for v in mix) or 1.0
    fade = int(min(1.5, length * 0.3) * Z.RATE)
    frames = bytearray()
    for i, v in enumerate(mix):
        g = 0.85 / peak
        if i > n - fade:
            g *= (n - i) / fade
        frames += struct.pack("<h", int(max(-1.0, min(1.0, v * g)) * 32767))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(Z.RATE)
        w.writeframes(bytes(frames))


if __name__ == "__main__":
    for name, (length, seq) in SOUNDS.items():
        render(name, length, seq)
        print("kész:", OUT / f"{name}.wav")
