"""Milyen helyi AI-modell fér el a játékos gépén?

Megnézi a videókártyákat (NVIDIA: nvidia-smi; Windows: a rendszer kártyalistája;
Mac: Apple Silicon közös memória) és a gép memóriáját, és ajánl egy Ollama-modellt,
amely a kontextussal együtt teljesen elfér a videómemóriában (így gyors).

A beépített (pl. Intel) videókártyát az Ollama általában nem használja: ilyenkor
a processzor számol, ami lassabb. A játék ezt őszintén megmondja.
"""
from __future__ import annotations

import json
import os
import platform
import subprocess
from typing import Dict, List, Optional
from .biztos_iras import write_text

# (modell, letöltési méret GB, kb. igény GB a 8k kontextussal együtt)
MODELS = [
    ("qwen3:14b", 9.3, 11.0),
    ("qwen3:8b", 5.2, 7.0),
    ("qwen3:4b", 2.5, 4.0),
    ("qwen3:1.7b", 1.4, 2.5),
]


def _run(cmd: List[str], timeout: float = 8.0) -> str:
    try:
        flags = 0x08000000 if os.name == "nt" else 0   # CREATE_NO_WINDOW: ne villanjon fel ablak
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, creationflags=flags)
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def nvidia_gpus(run=_run) -> List[Dict]:
    out = run(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"])
    gpus = []
    for line in out.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 2:
            try:
                gpus.append({"nev": parts[0], "vram_gb": round(float(parts[1]) / 1024, 1), "gyarto": "NVIDIA",
                             "ollama_hasznalja": True})
            except ValueError:
                pass
    return gpus


def windows_gpus(run=_run) -> List[Dict]:
    """Minden kártya neve Windowson (a memóriaadat itt megbízhatatlan, ezért nem használjuk)."""
    out = run(["powershell", "-NoProfile", "-Command",
               "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name"])
    return [{"nev": l.strip()} for l in out.splitlines() if l.strip()]


def system_ram_gb() -> Optional[float]:
    try:
        if os.name == "nt":
            import ctypes

            class MS(ctypes.Structure):
                _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                            ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                            ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                            ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                            ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
            m = MS()
            m.dwLength = ctypes.sizeof(MS)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
            return round(m.ullTotalPhys / 1024 ** 3, 1)
        if platform.system() == "Darwin":
            return round(int(_run(["sysctl", "-n", "hw.memsize"]).strip()) / 1024 ** 3, 1)
        return round(os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 1024 ** 3, 1)
    except Exception:
        return None


def recommend(gpus: List[Dict], ram_gb: Optional[float], apple_silicon: bool = False, lang: str = "hu") -> Dict:
    """A legnagyobb modell, amely teljesen elfér (a legjobb GPU-n, vagy Apple Siliconon a közös memória ~2/3-án)."""
    en = lang.startswith("en")
    best = max((g for g in gpus if g.get("ollama_hasznalja") and g.get("vram_gb")), key=lambda g: g["vram_gb"],
               default=None)
    if best:
        budget, where = best["vram_gb"], "gpu"
    elif apple_silicon and ram_gb:
        budget, where = ram_gb * 0.66, "gpu"
    else:
        budget, where = (ram_gb or 8.0) * 0.5, "cpu"   # processzoron: a memória fele legyen szabad
    for name, dl, need in MODELS:
        if need <= budget:
            break
    else:
        name, dl, need = MODELS[-1]
    if where == "gpu":
        why = (f"Fits completely in the {best['nev'] if best else 'Apple'} graphics memory ({budget:.1f} GB), so it is fast."
               if en else
               f"Teljesen elfér a(z) {best['nev'] if best else 'Apple'} videómemóriájában ({budget:.1f} GB), ezért gyors.")
    else:
        why = ("No graphics card usable by Ollama was found, so the processor will compute: this works, but slowly."
               if en else
               "Nem találtam az Ollama által használható videókártyát, ezért a processzor számol: működik, de lassú.")
    return {"modell": name, "letoltes_gb": dl, "igeny_gb": need, "hol": where, "indoklas": why}


def detect(lang: str = "hu", run=_run) -> Dict:
    en = lang.startswith("en")
    gpus = nvidia_gpus(run)
    if os.name == "nt":
        known = {g["nev"] for g in gpus}
        for g in windows_gpus(run):
            if g["nev"] not in known:
                g["ollama_hasznalja"] = False
                g["megjegyzes"] = ("Ollama usually does not use this card (e.g. built-in Intel graphics)." if en else
                                   "Ezt a kártyát az Ollama általában nem használja (pl. beépített Intel).")
                gpus.append(g)
    apple = platform.system() == "Darwin" and platform.machine() == "arm64"
    ram = system_ram_gb()
    return {"kartyak": gpus, "memoria_gb": ram, "apple_silicon": apple, "ajanlas": recommend(gpus, ram, apple, lang)}


def pull(model: str, progress_path, host: Optional[str] = None) -> None:
    """Modell letöltése az Ollamával; a haladást progress_path JSON-fájlba írja (a játék ezt olvassa)."""
    import urllib.request
    from pathlib import Path
    host = (host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")).rstrip("/")
    p = Path(progress_path)

    def write(d):
        write_text(p, json.dumps(d, ensure_ascii=False))

    req = urllib.request.Request(host + "/api/pull", data=json.dumps({"model": model, "stream": True}).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=3600) as r:
            for line in r:
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                total, done = ev.get("total") or 0, ev.get("completed") or 0
                write({"allapot": ev.get("status", ""), "szazalek": round(done / total * 100) if total else None,
                       "kesz": ev.get("status") == "success"})
                if ev.get("error"):
                    write({"allapot": "hiba", "hiba": ev["error"], "kesz": False})
                    raise SystemExit(1)
    except SystemExit:
        raise
    except Exception as e:
        write({"allapot": "hiba", "hiba": str(e), "kesz": False})
        raise SystemExit(1)


def cmd_gep(args):
    from pathlib import Path
    Path(args.ki).write_text(json.dumps(detect(args.nyelv), ensure_ascii=False, indent=1), encoding="utf-8")


def cmd_letolt(args):
    pull(args.modell, args.allapot)


def add_parsers(sub):
    g = sub.add_parser("gep", help="videókártyák és ajánlott helyi AI-modell")
    g.add_argument("--ki", required=True)
    g.add_argument("--nyelv", default="hu", choices=["hu", "en"])
    g.set_defaults(fn=cmd_gep)
    d = sub.add_parser("ollama-letolt", help="Ollama-modell letöltése haladásjelzéssel")
    d.add_argument("modell")
    d.add_argument("--allapot", required=True)
    d.set_defaults(fn=cmd_letolt)
