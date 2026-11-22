"""A témakatalógus (tudásfa) épsége: minden téma kutatható legyen a játék kutatójával."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import temak  # noqa: E402
from aether_lab import evidence as ev, godot_bridge as gb  # noqa: E402


def test_catalog_valid():
    assert temak.validate() == []
    assert len(temak.TEMAK) >= 100


def test_every_era_has_topics():
    for era in (1, 2, 3, 4):
        assert sum(1 for t in temak.TEMAK if t["korszak"] == era) >= 10


def test_params_are_researchable():
    """Csak olyan paraméter lehet, amelyhez van mértékegység-szűrő és köznapi név (az "egyeb" nem jó:
    abból sosem lesz ellenőrzött javaslat, így a téma sosem lenne kész)."""
    for t in temak.TEMAK:
        for p in t["parameterek"].split(","):
            assert p != "egyeb", t["id"]
            assert p in ev.UNIT_PATTERNS, (t["id"], p)
            assert p in gb.PARAM_NEV and p in gb.PARAM_NEV_EN, (t["id"], p)
            assert gb.jelentes(p, 1.0, ev.PARAMETERS[p]["unit"]) != ""


def test_txt_round_trip():
    """A fájlba írás és visszaolvasás nem veszít adatot."""
    from aether_lab import temak_txt as tt
    for code in tt.TERULETEK:
        ts = [t for t in temak.TEMAK if t["terulet"] == code]
        assert tt.parse(tt.format_file(code, ts), code) == ts


def test_txt_continuation_and_sources():
    from aether_lab import temak_txt as tt
    text = ("\ufeff# megjegyzés\n=== proba ===\nKorszak: II.\nKérdés: Első sor\nfolytatás?\n"
            "Kérdés angolul: Q?\nForrás: Cikk (2024) – https://doi.org/10.1/x\nForrás: Wiki – https://w.org/a\n"
            "Lektorálva: igen\n--- technikai ---\nParaméter: hatasfok_pct\n")
    t = tt.parse(text, "fizika")[0]
    assert t["korszak"] == 2 and t["cim"] == "Első sor folytatás?" and t["cim_en"] == "Q?"
    assert t["lektoralva"] is True and t["parameterek"] == "hatasfok_pct"
    assert tt.source_link(t["forras"][0]) == {"cim": "Cikk (2024)", "link": "https://doi.org/10.1/x"}


def test_existing_topic_ids_kept():
    ids = {t["id"] for t in temak.TEMAK}
    for old in ("tcre", "termes", "kukorica", "metan_rizs", "metan_gaz", "ontozes", "bioszen", "kozet",
                "levegoszures", "novenyi_energia", "erdo", "talaj", "napernyo"):
        assert old in ids
