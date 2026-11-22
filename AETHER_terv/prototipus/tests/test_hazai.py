import json
import unittest

from aether_lab import hazai

PAGE = b"<html><body><p>A 2025. nyari idoszakban Szegeden 38,2 fokot mertek.</p><script>x=1</script></body></html>"


class HazaiTeszt(unittest.TestCase):
    def test_hivatalos_oldal_jo_idezet(self):
        r = hazai.check("https://www.met.hu/x", "Szegeden 38,2 fokot mertek", 38.2, lambda u: PAGE)
        self.assertTrue(r["elfogadhato"], r["okok"])

    def test_nem_hivatalos_domain(self):
        r = hazai.check("https://pelda-blog.hu/x", "Szegeden 38,2 fokot mertek", 38.2, lambda u: PAGE)
        self.assertFalse(r["elfogadhato"])
        self.assertIn("hivatalos", r["okok"][0])

    def test_rossz_idezet_es_szam(self):
        r = hazai.check("https://www.met.hu/x", "Szegeden 40 fokot mertek", 41, lambda u: PAGE)
        self.assertEqual(len(r["okok"]), 2)

    def test_doi_visszavont(self):
        meta = {"message": {"title": ["T"], "abstract": "<p>Yield increased by 6% under drought.</p>",
                            "update-to": [{"type": "retraction"}]}}
        r = hazai.check("10.1234/abc", "increased by 6%", 6, lambda u: json.dumps(meta).encode())
        self.assertFalse(r["elfogadhato"])
        self.assertIn("visszavonták", " ".join(r["okok"]))

    def test_doi_jo(self):
        meta = {"message": {"title": ["T"], "abstract": "<p>Yield increased by 6% under drought.</p>"}}
        r = hazai.check("https://doi.org/10.1234/abc", "increased by 6%", 6, lambda u: json.dumps(meta).encode())
        self.assertTrue(r["elfogadhato"], r["okok"])


if __name__ == "__main__":
    unittest.main()
