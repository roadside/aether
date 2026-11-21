"""A „Mi ez, és mire jó?” téma-magyarázat offline tesztjei (szintetikus "TESZT" adatokkal)."""
import json
import unittest

from aether_lab import topic
from aether_lab.literature import Paper


def fetch(url, *a, **k):
    raise AssertionError("a téma-magyarázat nem tölthet le semmit közvetlenül (Wikipédiát sem)")


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

    def test_uses_ai_on_review_abstracts_only(self):
        ai = FakeAI()
        r = topic.build("biochar review", fetch, ai, "hu", log=lambda *_: None, search_reviews=reviews,
                        title="Mennyi CO2-t vonhat ki a bioszén?")
        self.assertNotIn("wiki", r)
        self.assertEqual(r["tipus"], "ai")
        self.assertEqual(r["magyarazat"]["hatranyok"], "c")
        self.assertIn("TESZT abstract", ai.user)
        self.assertNotIn("wikipedia", ai.user.lower())
        self.assertNotIn("absztrakt", r["cikkek"][0])

    def test_without_ai(self):
        r = topic.build("biochar review", fetch, None, "en", log=lambda *_: None, search_reviews=reviews)
        self.assertEqual(r["tipus"], "forras")
        self.assertEqual(r["cikkek"][0]["link"], "https://doi.org/10.1/x")


class TestTitleAllWords(unittest.TestCase):
    def test_barley_is_not_maize(self):
        from aether_lab.topic import title_matches
        self.assertFalse(title_matches("Drought tolerance in barley", "drought tolerance maize"))
        self.assertTrue(title_matches("Biochar", "biochar"))


if __name__ == "__main__":
    unittest.main()


class TestCleanExplanation(unittest.TestCase):
    def test_echo_dropped_and_hungarianized(self):
        m = topic.clean_explanation({"mi_ez": "Egy témában a klímajáték játékosának magyarázatát készítjük.",
                                     "mire_jo": "A biochar 0.5 GtCO2/év kivonást adhat."}, "hu")
        self.assertEqual(m["mi_ez"], "")
        self.assertIn("bioszén", m["mire_jo"])
        self.assertIn("0,5", m["mire_jo"])
