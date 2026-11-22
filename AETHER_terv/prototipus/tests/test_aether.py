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
        # szénben (nem CO2-ben) és nem évente megadott teljes potenciál: nem fogadjuk el
        self.assertFalse(unit_in_quote("cdr_potencial_gtco2_ev", "0.0066 to 2.0 Pg C using a biochar rate of 2 t ha−1"))


class TestCandidateSentences(unittest.TestCase):
    def test_only_number_with_unit(self):
        from aether_lab.research import candidate_sentences
        a = ("Negative emissions are needed. Potentials are 0.5–2 GtCO 2 yr −1 for biochar. "
             "Warming is limited to 1.5°C. Costs are US$90 per tCO2.")
        self.assertEqual(candidate_sentences(a, ["cdr_potencial_gtco2_ev"]),
                         ["Potentials are 0.5–2 GtCO 2 yr −1 for biochar."])

    def test_no_candidates_skips_ai(self):
        from aether_lab.research import extract
        from aether_lab.literature import Paper

        class Boom:
            def json_call(self, *a, **k):
                raise AssertionError("nem kellett volna AI-t hívni")
        p = Paper(source="teszt", source_id="1", title="TESZT", year=2020, abstract="Warming is limited to 1.5°C.")
        r = extract(Boom(), "TESZT", {"P1": p}, ["cdr_potencial_gtco2_ev"])
        self.assertEqual(r["allitasok"], [])


class TestAdaptationQuote(unittest.TestCase):
    def test_loss_and_adoption_share_rejected(self):
        from aether_lab.evidence import quote_fits
        p = "alkalmazkodas_hozam_elony_pct"
        self.assertTrue(quote_fits(p, "9 to 26% more grain yields than the best commercial hybrid"))
        self.assertFalse(quote_fits(p, "yield losses of 10–25 %"))
        self.assertFalse(quote_fits(p, "30% of the sampled households were growing DT maize"))

    def test_same_plan_without_adaptation(self):
        from aether_lab.godot_bridge import model_series
        o = model_series({"nev": "t", "cdr": {}, "co2_cel_ev": 2050, "co2_cel_ertek": 0.0,
                          "alkalmazkodas_hozam_kompenzacio_pct": 10.0})
        a, b = o["osszegzes"]["kozep"], o["alkalmazkodas_nelkul_osszegzes"]["kozep"]
        self.assertEqual(a["T2100"], b["T2100"])
        self.assertGreater(a["kukorica_hozam_2050_pct"], b["kukorica_hozam_2050_pct"])


class TestHomeCountry(unittest.TestCase):
    def _p(self, i, countries):
        from aether_lab.literature import Paper
        return Paper(source="openalex", source_id=str(i), title=f"TESZT {i}", year=2020, doi=f"10.1/{i}",
                     abstract="x", orszagok=countries)

    def test_home_papers_get_two_slots(self):
        from aether_lab.research import select_papers
        ranked = [self._p(i, ["US"]) for i in range(10)] + [self._p(10, ["HU", "DE"]), self._p(11, ["HU"])]
        chosen = select_papers(ranked, 5, "HU")
        self.assertEqual(len(chosen), 5)
        self.assertEqual(sum("HU" in p.orszagok for p in chosen), 2)
        self.assertEqual(select_papers(ranked, 5, ""), ranked[:5])

    def test_openalex_countries_and_filter(self):
        from aether_lab import literature as lit
        data = {"results": [{"id": "W1", "display_name": "TESZT", "publication_year": 2021,
                             "authorships": [{"author": {"display_name": "A"}, "countries": ["HU"]},
                                             {"author": {"display_name": "B"}, "countries": ["AT", "HU"]}]}]}
        self.assertEqual(lit.parse_openalex(data)[0].orszagok, ["AT", "HU"])
        data["results"][0]["authorships"][0]["institutions"] = [
            {"display_name": "Magyar Agrár- és Élettudományi Egyetem", "country_code": "HU"}]
        data["results"][0]["authorships"][1]["institutions"] = [
            {"display_name": "BOKU", "country_code": "AT"},
            {"display_name": "Magyar Agrár- és Élettudományi Egyetem", "country_code": "HU"}]
        self.assertEqual(lit.parse_openalex(data)[0].intezmenyek,
                         {"HU": ["Magyar Agrár- és Élettudományi Egyetem"], "AT": ["BOKU"]})
        seen = {}
        orig = lit._get
        lit._get = lambda url, *a, **k: (seen.setdefault("url", url), b'{"results": []}')[1]
        try:
            lit.search_openalex("biochar", 3, country="hu")
        finally:
            lit._get = orig
        self.assertIn("authorships.countries%3AHU", seen["url"])


class TestQuoteSpacing(unittest.TestCase):
    def test_broken_formula_spacing(self):
        from aether_lab.evidence import quote_in
        abstract = "potentials of 0.5–2 GtCO 2 yr −1 for biochar"
        self.assertTrue(quote_in("0.5–2 GtCO2 yr−1 for biochar", abstract))
        self.assertFalse(quote_in("0.5–3 GtCO2 yr−1 for biochar", abstract))
        self.assertFalse(quote_in("", abstract))


if __name__ == "__main__":
    unittest.main()


class TestHungarianize(unittest.TestCase):
    def test_terms_abbreviations_and_decimal_comma(self):
        from aether_lab.evidence import hungarianize
        t = hungarianize("BECCS (0.5–5 GtCO2/yr), DACCS és enhanced weathering, biochar 0.5-2")
        for bad in ("BECCS", "DACCS", "enhanced", "weathering", "biochar", "0.5", "GtCO2"):
            self.assertNotIn(bad, t)
        self.assertIn("0,5–5", t)
        self.assertIn("kőzetmállasztás", t)
        self.assertEqual(hungarianize("2026. január"), "2026. január")


def test_redact_hides_keys():
    from aether_lab.literature import redact
    s = redact("Nem sikerült lekérni: https://api.openalex.org/works?search=x&api_key=ABC123&mailto=a@b.hu (HTTP 429)")
    assert "ABC123" not in s and "a@b.hu" not in s and "search=x" in s and "api_key=REJTETT" in s


def test_osszegzesbol_kimarad_a_nem_ellenorzott_szam():
    from aether_lab import evidence as ev

    class C:
        def __init__(self, ertek, also=None, felso=None, statusz="ellenorizve"):
            self.ertek, self.also, self.felso, self.statusz = ertek, also, felso, statusz

    claims = [C(13.3), C(30.0, statusz="elutasitva")]
    text = ("Az aszálytűrő kukorica 13,3%-kal többet terem. Más cikk 30%-ot ír. "
            "Egy 2018-as áttekintés szerint az előny valós. A hatás 83.8 százalék is lehet!")
    out = ev.only_verified_numbers(text, claims)
    assert "13,3" in out and "2018" in out
    assert "30%" not in out and "83.8" not in out
    assert ev.only_verified_numbers("Csak 99 százalék.", claims) == ""
    assert ev.only_verified_numbers("", claims) == ""


def test_tengerszint_az_ipcc_tablazat_szerint():
    from aether_lab import climate as cl
    years = list(range(2025, 2101))
    s = cl.sea_level_series(1.8, years)          # SSP1-2.6 sora
    assert abs(s["kozep"][-1] - 0.44) < 0.002 and abs(s["also"][-1] - 0.32) < 0.002 and abs(s["felso"][-1] - 0.62) < 0.002
    assert abs(s["kozep"][years.index(2050)] - 0.19) < 0.002
    hot = cl.sea_level_series(2.7, years)["kozep"][-1]
    assert abs(hot - 0.56) < 0.002 and hot > s["kozep"][-1]
    assert cl.sea_level_series(9.0, years)["kozep"][-1] == cl.sea_level_series(4.4, years)["kozep"][-1]   # a táblázaton túl nem találunk ki számot
    assert all(b >= a for a, b in zip(s["kozep"], s["kozep"][1:]))   # 2100-ig végig emelkedik
