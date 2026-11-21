"""A Godot-híd offline tesztjei (szintetikus "TESZT" adatokkal)."""
import json
import tempfile
import types
import unittest
from pathlib import Path

from aether_lab import godot_bridge as gb


def _pub(params):
    return {"azonosito": "AETHER-teszt", "kerdes": "TESZT biochar kérdés", "osszesitett_parameterek": params,
            "allitasok": [], "cikkek": {}}


def _agg(param, sub, med, unit="GtCO2/év", conf="közepes"):
    return {"parameter": param, "alkategoria": sub, "egyseg": unit, "sulyozott_median": med,
            "tartomany": [med * 0.5, med * 1.5], "forrasok_szama": 2, "bizonyossag": conf}


class TestJavaslatok(unittest.TestCase):
    def test_cdr_mapped_and_capped(self):
        j = gb.javaslatok(_pub({"a": _agg("cdr_potencial_gtco2_ev", "biochar", 9.0)}))
        self.assertEqual(j[0]["kar"], "cdr:bioszen")
        self.assertEqual(j[0]["kar_ertek"], 2.0)          # Fuss et al. felső határ
        self.assertIn("felső határ", j[0]["megjegyzes"])

    def test_cdr_method_from_question_when_subcategory_vague(self):
        j = gb.javaslatok(_pub({"a": _agg("cdr_potencial_gtco2_ev", "global", 1.2)}))
        self.assertEqual(j[0]["kar"], "cdr:bioszen")
        self.assertEqual(j[0]["kar_ertek"], 1.2)

    def test_adaptation_lever(self):
        j = gb.javaslatok(_pub({"a": _agg("alkalmazkodas_hozam_elony_pct", "maize", 25.0, "%")}))
        self.assertEqual(j[0]["kar"], "alkalmazkodas")
        self.assertIn("nem hűti", j[0]["jelentes"])

    def test_informative_only(self):
        j = gb.javaslatok(_pub({"a": _agg("cdr_koltseg_usd_tco2", "biochar", 100.0, "USD/tCO2")}))
        self.assertIsNone(j[0]["kar"])
        self.assertIn("Tájékoztató", j[0]["megjegyzes"])
        self.assertTrue(j[0]["bizonyossag_szoveg"])


class TestJavaslatokEnglish(unittest.TestCase):
    def test_codes_stay_texts_translate(self):
        j = gb.javaslatok(_pub({"a": _agg("cdr_potencial_gtco2_ev", "biochar", 9.0)}), lang="en")[0]
        self.assertEqual(j["kar"], "cdr:bioszen")          # a kód nyelvfüggetlen
        self.assertEqual(j["bizonyossag"], "közepes")
        self.assertEqual(j["kar_nev"], "Biochar")
        self.assertEqual(j["egyseg"], "GtCO2/yr")
        self.assertIn("upper limit", j["megjegyzes"])
        self.assertIn("billion tonnes", j["jelentes"])
        self.assertTrue(j["bizonyossag_szoveg"].startswith("Medium"))


class TestModel(unittest.TestCase):
    def test_series_and_plain_text(self):
        out = gb.model_series({"nev": "t", "co2_cel_ev": 2050, "co2_cel_ertek": 0.0})
        self.assertEqual(len(out["evek"]), len(out["terv"]["kozep"]["homerseklet"]))
        self.assertLess(out["osszegzes"]["kozep"]["T2100"], out["alapeset_osszegzes"]["kozep"]["T2100"])
        self.assertIn("kevesebb", out["jelentes"])
        self.assertIn(",", out["jelentes"])  # magyar tizedesvessző

    def test_english_text(self):
        out = gb.model_series({"nev": "t", "co2_cel_ev": 2050, "co2_cel_ertek": 0.0}, lang="en")
        self.assertIn("less than if nothing changed", out["jelentes"])
        self.assertNotIn(",", out["jelentes"].split("(")[0])  # angol tizedespont

    def test_unknown_field_rejected(self):
        with self.assertRaises(ValueError):
            gb.model_series({"hamis_mezo": 1})


class TestKutat(unittest.TestCase):
    def test_status_and_result_files(self):
        def fake_research(q, provider, log=print, **kw):
            log("1/4 Kérdés pontosítása...")
            log("4/4 Determinisztikus ellenőrzés...")
            return {"azonosito": "AETHER-x", "kerdes": q, "cikkek": {"P1": {}},
                    "allitasok": [{"statusz": "ellenorizve"}, {"statusz": "elutasitva"}],
                    "osszesitett_parameterek": {"a": _agg("cdr_potencial_gtco2_ev", "enhanced weathering", 2.5)}}
        with tempfile.TemporaryDirectory() as d:
            args = types.SimpleNamespace(kerdes="TESZT", ai="none", mappa=d, cikkek=3, forrasonkent=2)
            gb.cmd_kutat(args, run_research=fake_research, get_provider=lambda n: None)
            st = json.loads((Path(d) / "allapot.json").read_text(encoding="utf-8"))
            res = json.loads((Path(d) / "eredmeny.json").read_text(encoding="utf-8"))
        self.assertEqual(st["allapot"], "kesz")
        self.assertEqual(st["lepes"], 4)
        self.assertEqual(res["osszefoglalo"]["elutasitva"], 1)
        self.assertEqual(res["javaslatok"][0]["kar"], "cdr:kozetmallasztas")

    def test_error_is_reported_not_crashed(self):
        def boom(*a, **k):
            raise RuntimeError("nincs hálózat")
        with tempfile.TemporaryDirectory() as d:
            args = types.SimpleNamespace(kerdes="TESZT", ai="none", mappa=d, cikkek=3, forrasonkent=2)
            gb.cmd_kutat(args, run_research=boom, get_provider=lambda n: None)
            st = json.loads((Path(d) / "allapot.json").read_text(encoding="utf-8"))
        self.assertEqual(st["allapot"], "hiba")
        self.assertIn("nincs hálózat", st["uzenet"])


if __name__ == "__main__":
    unittest.main()
