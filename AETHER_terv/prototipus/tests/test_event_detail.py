"""Az esemény-részletek offline tesztjei (szintetikus "TESZT" adatokkal)."""
import json
import tempfile
import unittest
from pathlib import Path

from aether_lab import event_detail as ed

PAGE = """<html><head><meta property="og:image" content="/img/map_big.png"><script>var x=1;</script></head>
<body><nav>Menu</nav><h1>TESZT Drought</h1><p>The drought has lasted for 10 months. Impact in 1121702 km2.</p>
<p>TESZT filler paragraph describing the situation in plain words so that the source is long enough for a
summary. Farmers report dry soils, rivers are low and pastures are poor across the TESZT region. Local
authorities monitor the situation and update the report every week with new satellite observations.</p>
<script>var arraymaps = [{"title":"TESZT map","image":"/contentdata/maps/daily/DR/1/ECDM_TESZT.png","link":"","pubdate":""}];</script>
<img src="/images/logo.png" alt="logo"><img src="maps/drought_map.jpg" alt="Drought map" width="800">
<img src="tiny.png" width="16" height="16"></body></html>"""

API = {"properties": {"alertlevel": "Orange", "fromdate": "2025-12-30T00:00:00", "todate": "2026-10-30T00:00:00",
                      "severitydata": {"severitytext": "Medium impact for agricultural drought in 1121702 km2"},
                      "images": {"thumbnailmap": "https://www.gdacs.org/TESZT_thumb.png"},
                      "affectedcountries": [{"countryname": "TESZT-A"}, {"countryname": "TESZT-B"}]}}


def fake_fetch(url, *a, **k):
    if "geteventdata" in url:
        return json.dumps(API).encode()
    if url.endswith((".png", ".jpg")):
        return b"\x89PNG" + b"0" * 9000
    return PAGE.encode()


class FakeAI:
    name = "teszt"

    def json_call(self, system, user, schema, max_tokens=0):
        return {"osszegzes": "TESZT összefoglaló.",
                "fobb_szamok": [{"ertek": "10", "jelentes": "hónap", "idezet": "The drought has lasted for 10 months"},
                                {"ertek": "99", "jelentes": "kitalált", "idezet": "lasted for 99 months"}]}


EVENT = {"forras": "GDACS", "cim": "TESZT", "orszag": "TESZT-A, TESZT-B, TESZT-C, TESZT-D",
         "link": "https://www.gdacs.org/report.aspx?eventid=1&eventtype=DR", "leiras": ""}


class TestHtml(unittest.TestCase):
    def test_text_and_images(self):
        t = ed.html_text(PAGE)
        self.assertIn("lasted for 10 months", t)
        self.assertNotIn("var x", t)
        imgs = [i["url"] for i in ed.html_images(PAGE, "https://ex.org/a/b.html")]
        self.assertEqual(imgs, ["https://ex.org/img/map_big.png", "https://ex.org/a/maps/drought_map.jpg"])

    def test_api_url(self):
        self.assertIn("eventtype=DR", ed.gdacs_api_url(EVENT["link"]))
        self.assertIsNone(ed.gdacs_api_url("https://example.org/x"))


class TestBuild(unittest.TestCase):
    def test_with_ai_verifies_numbers(self):
        with tempfile.TemporaryDirectory() as d:
            r = ed.build(EVENT, Path(d), fake_fetch, FakeAI(), "hu", log=lambda *_: None)
            self.assertEqual(r["osszegzes_tipus"], "ai")
            self.assertEqual([x["ertek"] for x in r["fobb_szamok"]], ["10"])   # a kitalált 99 kiesett
            # GDACS: a saját térképei (API + arraymaps), nem az oldal <img> elemei
            self.assertEqual([k["url"] for k in r["kepek"]],
                             ["https://www.gdacs.org/TESZT_thumb.png",
                              "https://www.gdacs.org/contentdata/maps/daily/DR/1/ECDM_TESZT.png"])
            self.assertTrue(Path(r["kepek"][0]["fajl"]).exists())
            self.assertTrue(any(f["nev"] == "Időtartam" and f["ertek"] == "304 nap" for f in r["tenyek"]))

    def test_without_ai(self):
        with tempfile.TemporaryDirectory() as d:
            r = ed.build(EVENT, Path(d), fake_fetch, None, "en", log=lambda *_: None)
            self.assertEqual(r["osszegzes_tipus"], "forras")
            self.assertIn("4 countries", r["osszegzes"])
            self.assertIn("Medium impact", r["osszegzes"])


class HallucinatingAI:
    name = "teszt"

    def json_call(self, system, user, schema, max_tokens=0):
        return {"osszegzes": "A jéghegy kb. 45 km² nagy.", "miert_fontos": "TESZT", "fobb_szamok": []}


class TestHonesty(unittest.TestCase):
    def test_invented_number_rejects_summary(self):
        with tempfile.TemporaryDirectory() as d:
            r = ed.build(EVENT, Path(d), fake_fetch, HallucinatingAI(), "hu", log=lambda *_: None)
            self.assertEqual(r["osszegzes_tipus"], "forras")
            self.assertNotIn("45", r["osszegzes"])

    def test_thin_or_non_html_source_skips_ai(self):
        ev = {"forras": "NASA EONET", "cim": "Iceberg TESZT", "kategoria": "jeg", "lat": -66.2, "lon": -48.1,
              "link": "https://example.org/data.csv"}
        csv = lambda url, *a, **k: b"date,lat,lon\n2026-11-20,-66.2,-48.1\n"  # noqa: E731
        with tempfile.TemporaryDirectory() as d:
            r = ed.build(ev, Path(d), csv, HallucinatingAI(), "hu", log=lambda *_: None)
            self.assertEqual(r["osszegzes_tipus"], "forras")
            self.assertIn("66,2° D", r["osszegzes"])

    def test_unsupported_numbers(self):
        self.assertEqual(ed.unsupported_numbers("12 000 ember, CO₂", "12,000 people"), [])
        self.assertEqual(ed.unsupported_numbers("45 km²", "TESZT"), [45.0])


if __name__ == "__main__":
    unittest.main()
