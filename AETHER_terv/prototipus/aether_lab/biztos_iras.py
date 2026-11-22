"""Biztonságos fájlírás a Godot-játéknak.

A játék fél másodpercenként olvassa az állapotfájlokat. Windowson az `os.replace`
„hozzáférés megtagadva” (WinError 5 / PermissionError) hibát ad, ha a célfájl épp nyitva van
olvasásra. Ettől korábban az egész kutatás leállt. Ezért néhányszor rövid szünettel újrapróbáljuk;
ha így sem megy, közvetlenül írjuk a fájlt (egy pillanatra félkész lehet, de a játék a hibás JSON-t
egyszerűen kihagyja, és a következő olvasásnál már jót kap). Az írás sosem állítja le a munkát.
"""
from __future__ import annotations

import os
import time
from pathlib import Path


def write_text(path: Path | str, text: str, tries: int = 10, wait: float = 0.05) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    for _ in range(tries):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(wait)
    try:
        path.write_text(text, encoding="utf-8")
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass
