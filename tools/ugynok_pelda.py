#!/usr/bin/env python3
"""Példa külső ügynökre: a hídon keresztül végigjátszik egy játékot.

    python3 tools/ugynok_pelda.py [godot] [Föld-kód]

Az ügynök itt egyszerű szabályt követ (a legnagyobb hűlést ígérő lépést választja, különben kutat).
A `choose` függvény helyére bármilyen AI-t beköthetsz: megkapja az állapotot és a szabályos lépéseket,
és egy lépést ad vissza. Kulcsot ne írj a fájlba: környezeti változóból olvasd.
"""
import json
import subprocess
import sys


def choose(state):
    acts = state["actions"]
    for kind in ("refute", "reassure", "summit"):
        for a in acts:
            if a["type"] == kind:
                return a
    cooling = [a for a in acts if a["type"] in ("negotiate", "methane")]
    if cooling:
        return min(cooling, key=lambda a: a.get("cooling", 0.0))      # a legnagyobb hűlés (a szám negatív)
    for kind in ("cdr", "prepare", "research", "dilemma", "skip_summit"):
        for a in acts:
            if a["type"] == kind:
                return a
    return {"type": "end_round"}


def main():
    godot = sys.argv[1] if len(sys.argv) > 1 else "godot"
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 2026
    p = subprocess.Popen([godot, "--headless", "--path", ".", "-s", "tools/ugynok_hid.gd"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")

    def read():
        while True:
            line = p.stdout.readline()
            if not line:
                raise SystemExit("a híd leállt")
            if line.startswith("AETHER "):
                return json.loads(line[7:])

    def send(msg):
        p.stdin.write(json.dumps(msg) + "\n")
        p.stdin.flush()
        return read()

    read()
    state = send({"cmd": "new", "seed": seed})["state"]
    moves = 0
    while not state["over"]:
        action = choose(state)
        reply = send({"cmd": "act", "action": action})
        if not reply["ok"]:
            reply = send({"cmd": "act", "action": {"type": "end_round"}})
        state = reply["state"]
        moves += 1
    p.stdin.write(json.dumps({"cmd": "quit"}) + "\n")
    p.stdin.flush()
    r = state["result"]
    print("Föld-kód %d: %d lépés, 2100-ban +%.2f °C (ha semmi sem változik: +%.2f °C)" % (seed, moves, r["warming_2100"], r["if_nothing_changes"]))


if __name__ == "__main__":
    main()
