"""AETHER kutatólabor – parancssoros prototípus.

Használat (Windows PowerShell / parancssor, a 'prototipus' mappából):

  python -m aether_lab demo
      A beépített forgatókönyvek futtatása (nem kell hozzá internet sem AI).

  python -m aether_lab kutat "Mennyivel növeli a szárazságtűrő kukorica a hozamot aszály alatt?" --ai claude
  python -m aether_lab kutat "biochar carbon removal potential" --ai ollama
  python -m aether_lab kutat "enhanced weathering" --ai none
      Valódi irodalomkeresés + AI-kivonatolás + ellenőrzés -> publikáció (JSON + Markdown).

  python -m aether_lab modell forgatokonyv.json
      Saját forgatókönyv futtatása (a mezők: lásd climate.Scenario).

  python -m aether_lab vilag --ki vilag.json
      A Föld mai állapota valós, ellenőrizhető forrásokból (GDACS, ReliefWeb,
      NASA EONET, NOAA, NSIDC), dátummal és linkkel.

  godot-ai / godot-kutat / godot-modell
      A Godot-kliens parancsai (lásd godot_bridge.py).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import fields
from pathlib import Path

from .climate import Scenario, builtin_scenarios, summarize
from .chart import scenarios_svg
from . import godot_bridge, world_state


def _print_summary(sm):
    print(f"\n■ {sm['nev']}\n  {sm['leiras']}")
    print("  érzékenység | 2050 | 2100 | csúcs (év) | 1.5°C | 2.0°C | kukorica 2050")
    for e, r in sm["eredmenyek"].items():
        print(f"  {e:11s} | {r['T2050']:.2f} | {r['T2100']:.2f} | {r['csucs']:.2f} ({r['csucs_ev']}) | "
              f"{r['1.5C_atlepes'] or '-'} | {r['2.0C_atlepes'] or '-'} | {r['kukorica_hozam_2050_pct']:+.1f}%")


def cmd_demo(args):
    out = Path(args.kimenet)
    out.mkdir(parents=True, exist_ok=True)
    scs = builtin_scenarios()
    sums = [summarize(s) for s in scs]
    for sm in sums:
        _print_summary(sm)
    (out / "demo_eredmenyek.json").write_text(json.dumps(sums, ensure_ascii=False, indent=2), encoding="utf-8")
    (out / "demo_homerseklet.svg").write_text(scenarios_svg(scs), encoding="utf-8")
    print(f"\nMentve: {out/'demo_eredmenyek.json'} és {out/'demo_homerseklet.svg'}")


def cmd_model(args):
    data = json.loads(Path(args.fajl).read_text(encoding="utf-8"))
    allowed = {f.name for f in fields(Scenario)}
    unknown = set(data) - allowed
    if unknown:
        sys.exit(f"Ismeretlen mezők: {unknown}. Engedélyezett: {sorted(allowed)}")
    s = Scenario(**data)
    _print_summary(summarize(s))


def cmd_research(args):
    from .llm import get_provider, LLMError
    from .research import run_research, to_markdown
    try:
        provider = get_provider(args.ai)
    except LLMError as e:
        sys.exit(str(e))
    try:
        pub = run_research(args.kerdes, provider, n_papers=args.cikkek, per_source=args.forrasonkent,
                           mailto=os.environ.get("AETHER_MAILTO", ""),
                           openalex_key=os.environ.get("OPENALEX_API_KEY", ""),
                           s2_key=os.environ.get("S2_API_KEY", ""), use_arxiv=not args.arxiv_nelkul)
    except LLMError as e:
        sys.exit(f"AI-hiba: {e}")
    out = Path(args.kimenet)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{pub['azonosito']}.json").write_text(json.dumps(pub, ensure_ascii=False, indent=2), encoding="utf-8")
    (out / f"{pub['azonosito']}.md").write_text(to_markdown(pub), encoding="utf-8")
    print(f"\nPublikáció: {out / (pub['azonosito'] + '.md')}")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="aether_lab", description="AETHER kutatólabor prototípus")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("demo"); d.add_argument("--kimenet", default="kimenet"); d.set_defaults(fn=cmd_demo)
    m = sub.add_parser("modell"); m.add_argument("fajl"); m.set_defaults(fn=cmd_model)
    r = sub.add_parser("kutat")
    r.add_argument("kerdes")
    r.add_argument("--ai", default="claude", choices=["claude", "ollama", "none"])
    r.add_argument("--cikkek", type=int, default=12)
    r.add_argument("--forrasonkent", type=int, default=6)
    r.add_argument("--arxiv-nelkul", action="store_true")
    r.add_argument("--kimenet", default="publikaciok")
    r.set_defaults(fn=cmd_research)
    godot_bridge.add_parsers(sub)
    world_state.add_parsers(sub)
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args.fn(args)


if __name__ == "__main__":
    main()
