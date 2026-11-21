"""Ország -> IPCC AR6 referenciarégió (szárazföld), többségi szavazással az orszagok.json
rácspontjaiból. Forrás: IPCC-WGI-reference-regions-v4.geojson (Iturbide et al. 2020, CC BY 4.0).

Használat:  python orszag_regio.py <regions.geojson> <aether_lab/orszagok.json> <aether_lab/regionalis_skalazas.json>
"""
import json
import sys
from collections import Counter


def inside(lon, lat, ring):
    c = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi + 1e-12) + xi:
            c = not c
        j = i
    return c


def main(geo, orsz, out):
    feats = [f for f in json.load(open(geo))["features"] if f["properties"]["Type"] != "Ocean"]
    polys = []
    for f in feats:
        g = f["geometry"]
        rings = [g["coordinates"][0]] if g["type"] == "Polygon" else [p[0] for p in g["coordinates"]]
        polys.append((f["properties"]["Acronym"], rings))
    votes = {}
    for lat, lon, cc in json.load(open(orsz, encoding="utf-8"))["pontok"]:
        for acr, rings in polys:
            if any(inside(lon, lat, r) for r in rings):
                votes.setdefault(cc, Counter())[acr] += 1
                break
    d = json.load(open(out, encoding="utf-8"))
    d["orszag_regio"] = {cc: c.most_common(1)[0][0] for cc, c in sorted(votes.items())}
    d["regio_nevek"] = {f["properties"]["Acronym"]: f["properties"]["Name"] for f in feats}
    json.dump(d, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(len(d["orszag_regio"]), "ország; HU ->", d["orszag_regio"].get("HU"))


if __name__ == "__main__":
    main(*sys.argv[1:4])
