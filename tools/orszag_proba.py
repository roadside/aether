#!/usr/bin/env python3
"""Kipróbálja a saját gépen futó Ollamával, mit felelnek az AI-országok.

Használat:  python tools/orszag_proba.py <godot> [modell] [ismétlés]
A kérések csak a 127.0.0.1:11434 címre mennek (a saját gépre). Az eredmény a képernyőre kerül.
"""
import json, subprocess, sys, time, urllib.request

URL = "http://127.0.0.1:11434"


def post(path, payload, timeout=180):
    req = urllib.request.Request(URL + path, json.dumps(payload).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def main():
    godot = sys.argv[1]
    with urllib.request.urlopen(URL + "/api/tags", timeout=5) as r:
        models = [m["name"] for m in json.loads(r.read()).get("models", [])]
    if not models:
        sys.exit("Nincs letöltött modell az Ollamában.")
    model = sys.argv[2] if len(sys.argv) > 2 else models[0]
    times = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    out = subprocess.run([godot, "--headless", "--path", ".", "-s", "tools/orszag_proba.gd"], capture_output=True, text=True, encoding="utf-8").stdout
    asks = [json.loads(l[12:]) for l in out.splitlines() if l.startswith("ORSZAGKERES ")]
    print("modell: %s, kérés: %d, ismétlés: %d" % (model, len(asks), times))
    bad = 0
    for a in asks:
        for _ in range(times):
            t0 = time.time()
            try:
                rep = post("/api/chat", {"model": model, "stream": False, "format": "json", "think": False, "options": {"temperature": 0.2}, "messages": a["uzenetek"]})
                text = rep["message"]["content"]          # ugyanúgy tisztítjuk, mint a játék: gondolatmenet le, csak a JSON-rész
                if "</think>" in text:
                    text = text[text.rfind("</think>") + 8:]
                if "{" in text and "}" in text:
                    text = text[text.find("{"):text.rfind("}") + 1]
                ans = json.loads(text)
                k = "ABCDEF".find(str(ans.get("choice", "?")).strip().upper()[:1])
                dec = a["lehetosegek"][k] if 0 <= k < len(a["lehetosegek"]) else "SZABÁLYTALAN választás: %r" % ans.get("choice")
                if not (0 <= k < len(a["lehetosegek"])):
                    bad += 1
                text = "%s | valós helyzet a modell szerint: %s" % (ans.get("statement"), ans.get("real_record"))
                extra = ""
            except Exception as e:  # szabálytalan válasz: a játék ilyenkor az alapszabály szerint dönt
                bad += 1
                dec, text, extra = "SZABÁLYTALAN", str(e)[:80], ""
            print("%-7s %-11s hangulat %2d%%  %4.1f mp  %s%s | %s" % (a["csoport"], a["fajta"] + (" %d" % a["cel"] if "cel" in a else ""), round(a["hangulat"] * 100), time.time() - t0, dec, extra, text))
    print("szabálytalan válasz: %d" % bad)


if __name__ == "__main__":
    main()
