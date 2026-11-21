"""Offline tesztek. Futtatás: python -m unittest discover -s tests

A tesztadatok SZINTETIKUSAK (kitalált "TESZT" cikkek), csak a kód
működését ellenőrzik, tudományos állítást nem tartalmaznak.
"""
import json
import unittest

from aether_lab import climate as cl
from aether_lab import evidence as ev
from aether_lab import literature as lit
from aether_lab.research import run_research, to_markdown


OPENALEX_FIXTURE = {"results": [{
    "id": "https://openalex.org/WTESZT1", "doi": "https://doi.org/10.0000/TESZT.1",
    "display_name": "TESZT cikk: szárazságtűrő fajták", "publication_year": 2021, "type": "article",
    "cited_by_count": 42, "is_retracted": False,
    "abstract_inverted_index": {"Yield": [0], "advantage": [1], "was": [2], "25%": [3], "under": [4], "drought.": [5]},
    "primary_location": {"source": {"display_name": "TESZT Journal"}},
    "authorships": [{"author": {"display_name": "Anna Teszt"}}, {"author": {"display_name": "Béla Próba"}}],
    "open_access": {"oa_url": None},
}, {
    "id": "https://openalex.org/WTESZT2", "doi": "https://doi.org/10.0000/TESZT.2",
    "display_name": "TESZT visszavont cikk", "publication_year": 2019, "type": "article",
    "cited_by_count": 5, "is_retracted": True,
    "abstract_inverted_index": {"Retracted": [0]}, "primary_location": None, "authorships": [],
}]}

ARXIV_FIXTURE = b"""<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
<entry><id>http://arxiv.org/abs/0000.00000v1</id><published>2024-03-01T00:00:00Z</published>
<title>TESZT preprint
 title</title><summary>We estimate 2 to 4 units.</summary>
<author><name>C. Teszt</name></author></entry></feed>"""


class FakeProvider:
    name = "fake"; model = "teszt"

    def json_call(self, system, user, schema, max_tokens=8000):
        if "angol_keresokifejezesek" in schema["properties"]:
            return {"kutatasi_kerdes_pontositva": "q", "angol_keresokifejezesek": ["drought"],
                    "keresett_parameterek": ["alkalmazkodas_hozam_elony_pct"], "megjegyzes": ""}
        return {"allitasok": [
            {"cikk_azonosito": "P1", "parameter": "alkalmazkodas_hozam_elony_pct", "alkategoria": "kukorica",
             "ertek": 25, "also": None, "felso": None, "egyseg": "%", "szo_szerinti_idezet": "advantage was 25% under drought",
             "vizsgalat_tipusa": "terepkiserlet", "regio": "", "korlatok": ""},
            {"cikk_azonosito": "P1", "parameter": "alkalmazkodas_hozam_elony_pct", "alkategoria": "kukorica",
             "ertek": 60, "also": None, "felso": None, "egyseg": "%", "szo_szerinti_idezet": "advantage was 60%",
             "vizsgalat_tipusa": "terepkiserlet", "regio": "", "korlatok": ""},
        ], "osszegzes": "teszt", "ellentmondasok": ""}


class TestClimate(unittest.TestCase):
    def test_baseline_warms(self):
        r = cl.run(cl.Scenario())
        self.assertAlmostEqual(r.temp[0], cl.T_START + 0.45e-3 * cl.E_CO2_NOW, places=3)
        self.assertGreater(r.at(2100), r.at(2050))

    def test_net_zero_stabilises(self):
        r = cl.run(cl.Scenario(co2_cel_ev=2050, co2_cel_ertek=0.0))
        self.assertAlmostEqual(r.at(2060), r.at(2100), places=3)

    def test_adaptation_does_not_cool(self):
        a = cl.run(cl.Scenario(alkalmazkodas_hozam_kompenzacio_pct=50))
        b = cl.run(cl.Scenario())
        self.assertEqual(a.temp, b.temp)
        self.assertGreater(a.crop_change_pct["kukorica"][-1], b.crop_change_pct["kukorica"][-1])

    def test_clean_air_unmasks_warming(self):
        a = cl.run(cl.Scenario(szulfat_csokkentes_pct=100))
        self.assertGreater(a.at(2050), cl.run(cl.Scenario()).at(2050))

    def test_methane_cut_magnitude(self):
        d = cl.run(cl.Scenario()).at(2045) - cl.run(cl.Scenario(metan_csokkentes_pct=45)).at(2045)
        self.assertTrue(0.1 < d < 0.35, d)  # GMA 2021: ~0.3 °C 2045-re (növekvő alapeshez képest)

    def test_sai_termination_shock(self):
        r = cl.run(cl.Scenario(sai_tg_so2=8, sai_kezdes=2035, sai_leallitas=2070))
        rate_after = (r.at(2076) - r.at(2070)) / 6
        self.assertGreater(rate_after, 0.06)  # sokszorosa a mai ~0.027 °C/év ütemnek

    def test_cdr_capped(self):
        s = cl.Scenario(cdr={"bioszen": 100})
        self.assertAlmostEqual(cl.cdr_removal(s, 2060), 2.0)


class TestLiterature(unittest.TestCase):
    def test_openalex_parse_and_retraction(self):
        ps = lit.parse_openalex(OPENALEX_FIXTURE)
        self.assertEqual(ps[0].abstract, "Yield advantage was 25% under drought.")
        self.assertEqual(ps[0].doi, "10.0000/teszt.1")
        self.assertEqual(len(lit.rank(ps)), 1)  # visszavont kiesik

    def test_arxiv_is_preprint(self):
        ps = lit.parse_arxiv(ARXIV_FIXTURE)
        self.assertEqual(ps[0].title, "TESZT preprint title")
        self.assertFalse(ps[0].peer_reviewed)

    def test_merge_dedupes_by_doi(self):
        a = lit.Paper("openalex", "1", "X", 2020, doi="10.1/a", abstract="short")
        b = lit.Paper("crossref", "2", "X", 2020, doi="10.1/A", abstract="much longer abstract", cited_by=9)
        m = lit.merge([a, b])
        self.assertEqual(len(m), 1)
        self.assertEqual(m[0].abstract, "much longer abstract")


class TestEvidence(unittest.TestCase):
    def test_pipeline_rejects_hallucinated_quote(self):
        papers = lit.parse_openalex(OPENALEX_FIXTURE)
        import aether_lab.research as rs
        orig = rs.search_all
        rs.search_all = lambda *a, **k: lit.rank(papers)
        try:
            pub = run_research("teszt", FakeProvider(), log=lambda *_: None)
        finally:
            rs.search_all = orig
        st = [c["statusz"] for c in pub["allitasok"]]
        self.assertEqual(st, ["ellenorizve", "elutasitva"])
        agg = list(pub["osszesitett_parameterek"].values())[0]
        self.assertEqual(agg["sulyozott_median"], 25)
        self.assertTrue(pub["azonosito"].startswith("AETHER-"))
        self.assertIn("Elutasítás oka", to_markdown(pub))

    def test_number_must_be_in_quote(self):
        p = {"P1": lit.Paper("x", "1", "t", 2020, abstract="Removal of 2-4 Gt per year.")}
        c = ev.Claim("P1", "cdr_potencial_gtco2_ev", "ew", 3.0, 2.0, 4.0, "Gt", "Removal of 2-4 Gt per year.",
                     "attekintes", "", "")
        ev.verify([c], p)
        self.assertIn("A(z) érték (3.0) nem szerepel az idézetben.", c.indokok)


class TestUnitCheck(unittest.TestCase):
    def test_target_temperature_is_not_cdr_potential(self):
        from aether_lab.evidence import unit_in_quote
        self.assertFalse(unit_in_quote("cdr_potencial_gtco2_ev", "limit warming to 1.5°C"))
        self.assertTrue(unit_in_quote("cdr_potencial_gtco2_ev", "0.5–2 GtCO 2 yr −1 for biochar"))
        self.assertTrue(unit_in_quote("cdr_koltseg_usd_tco2", "costs of US$90–120 per tonne"))


class TestQuoteSpacing(unittest.TestCase):
    def test_broken_formula_spacing(self):
        from aether_lab.evidence import quote_in
        abstract = "potentials of 0.5–2 GtCO 2 yr −1 for biochar"
        self.assertTrue(quote_in("0.5–2 GtCO2 yr−1 for biochar", abstract))
        self.assertFalse(quote_in("0.5–3 GtCO2 yr−1 for biochar", abstract))
        self.assertFalse(quote_in("", abstract))


if __name__ == "__main__":
    unittest.main()
