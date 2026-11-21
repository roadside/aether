"""A „Mi ez, és mire jó?” téma-magyarázat offline tesztjei (szintetikus "TESZT" adatokkal)."""
import json
import unittest

from aether_lab import topic
from aether_lab.literature import Paper


def fetch(url, *a, **k):
    if "list=search" in url:
        if "hu.wikipedia" in url:
            return json.dumps({"query": {"search": []}}).encode()   # nincs magyar cikk
        return json.dumps({"query": {"search": [{"title": "TESZT Biochar"}]}}).encode()
    return json.dumps({"query": {"pages": {"1": {"extract": "TESZT intro sentence. " * 20 + "\n\nMore."}}}}).encode()


def reviews(q):
    return [Paper(source="openalex", source_id="1", title="TESZT review", year=2021, doi="10.1/x",
                  abstract="TESZT abstract")]


class FakeAI:
    def json_call(self, system, user, schema, max_tokens=0):
        self.user = user
        return {"mi_ez": "a", "mire_jo": "b", "hatranyok": "c", "mennyire_bizonyitott": "d"}


class TestTopic(unittest.TestCase):
    def test_title_match(self):
        self.assertFalse(topic.title_matches("Biogáz", "bioszén"))
        self.assertTrue(topic.title_matches("Bioszén", "bioszén"))
        self.assertTrue(topic.title_matches("Biochar", "biochar"))
        self.assertTrue(topic.title_matches("Enhanced weathering", "enhanced weathering"))
        self.assertTrue(topic.title_matches("Erdősítés", "erdősítés"))

    def test_falls_back_to_english_wiki_and_uses_ai(self):
        ai = FakeAI()
        r = topic.build("bioszén", "biochar", "biochar review", fetch, ai, "hu", log=lambda *_: None,
                        search_reviews=reviews)
        self.assertEqual(r["wiki"]["nyelv"], "en")
        self.assertIn("en.wikipedia.org/wiki/TESZT_Biochar", r["wiki"]["link"])
        self.assertEqual(r["tipus"], "ai")
        self.assertEqual(r["magyarazat"]["hatranyok"], "c")
        self.assertIn("TESZT abstract", ai.user)
        self.assertNotIn("absztrakt", r["cikkek"][0])

    def test_without_ai(self):
        r = topic.build("bioszén", "biochar", "biochar review", fetch, None, "en", log=lambda *_: None,
                        search_reviews=reviews)
        self.assertEqual(r["tipus"], "forras")
        self.assertTrue(r["wiki"]["bevezeto"].startswith("TESZT intro"))


if __name__ == "__main__":
    unittest.main()
