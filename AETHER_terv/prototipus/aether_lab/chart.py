"""Függőség nélküli SVG-grafikon a hőmérsékleti pályákról (bizonytalansági sávval)."""
from __future__ import annotations

from typing import Dict, List

from .climate import Scenario, run_ensemble

PALETTE = ["#9aa4b1", "#d9a441", "#c8553d", "#5b9bd5", "#3fa37a", "#2e7d5b", "#a06cd5"]


def scenarios_svg(scenarios: List[Scenario], width=980, height=520) -> str:
    x0, x1, y0, y1 = 70, width - 330, 30, height - 50
    tmin, tmax = 0.6, 3.6

    def X(year):
        return x0 + (year - 2025) / 75 * (x1 - x0)

    def Y(t):
        return y1 - (t - tmin) / (tmax - tmin) * (y1 - y0)

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" font-family="Inter, Segoe UI, sans-serif" font-size="13">',
           f'<rect width="{width}" height="{height}" fill="#0f1420"/>']
    for t in [1.0, 1.5, 2.0, 2.5, 3.0, 3.5]:
        dash = ' stroke-dasharray="5 4"' if t in (1.5, 2.0) else ""
        col = "#e0b050" if t == 1.5 else ("#e07050" if t == 2.0 else "#2a3346")
        out.append(f'<line x1="{x0}" x2="{x1}" y1="{Y(t):.1f}" y2="{Y(t):.1f}" stroke="{col}"{dash}/>')
        out.append(f'<text x="{x0-8}" y="{Y(t)+4:.1f}" fill="#8b95a7" text-anchor="end">{t:.1f} °C</text>')
    for yr in range(2030, 2101, 10):
        out.append(f'<text x="{X(yr):.1f}" y="{y1+20}" fill="#8b95a7" text-anchor="middle">{yr}</text>')
    for i, s in enumerate(scenarios):
        col = PALETTE[i % len(PALETTE)]
        res = run_ensemble(s)
        lo, mid, hi = res["alacsony"], res["kozep"], res["magas"]
        band = [f"{X(y):.1f},{Y(t):.1f}" for y, t in zip(hi.years, hi.temp)] + \
               [f"{X(y):.1f},{Y(t):.1f}" for y, t in reversed(list(zip(lo.years, lo.temp)))]
        out.append(f'<polygon points="{" ".join(band)}" fill="{col}" opacity="0.12"/>')
        pts = " ".join(f"{X(y):.1f},{Y(t):.1f}" for y, t in zip(mid.years, mid.temp))
        out.append(f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="2.5"/>')
        ly = y0 + 10 + i * 26
        out.append(f'<rect x="{x1+20}" y="{ly-9}" width="14" height="4" fill="{col}"/>')
        label = s.nev if len(s.nev) < 44 else s.nev[:42] + "…"
        out.append(f'<text x="{x1+40}" y="{ly-3}" fill="#d8dee9">{label}</text>')
    out.append(f'<text x="{x0}" y="{height-12}" fill="#6b7587" font-size="11">AETHER-mini játékmodell. Vonal: közép érzékenység; sáv: IPCC AR6 valószínű tartomány (TCRE 0.27–0.63, ECS 2.5–4.0). Nem előrejelzés.</text>')
    out.append("</svg>")
    return "\n".join(out)
