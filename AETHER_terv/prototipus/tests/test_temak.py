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


def test_generated_json_in_sync():
    data = json.loads(temak.OUT.read_text(encoding="utf-8"))
    assert data == temak.catalog(), "futtasd: python tools/temak.py"


def test_existing_topic_ids_kept():
    ids = {t["id"] for t in temak.TEMAK}
    for old in ("tcre", "termes", "kukorica", "metan_rizs", "metan_gaz", "ontozes", "bioszen", "kozet",
                "levegoszures", "novenyi_energia", "erdo", "talaj", "napernyo"):
        assert old in ids
