import json
import tempfile
import unittest
from pathlib import Path

from aether_lab import archivum


def _res(ok=1):
    return {"publikacio": {"allitasok": [{"statusz": "ellenorizve" if ok else "elutasitva"}]},
            "javaslatok": [], "osszefoglalo": {"ellenorizve": ok}, "archivum": {"datum": "2026-11-22", "ai": "x"}}


class ArchivumTeszt(unittest.TestCase):
    def test_index_es_frissites(self):
        with tempfile.TemporaryDirectory() as src, tempfile.TemporaryDirectory() as dst:
            (Path(src) / "kukorica_hu.json").write_text(json.dumps(_res()), encoding="utf-8")
            (Path(src) / "rossz_hu.json").write_text(json.dumps(_res(0)), encoding="utf-8")
            idx = archivum.index_keszites(Path(src))
            self.assertEqual([i["fajl"] for i in idx["fajlok"]], ["kukorica_hu.json"])
            fetch = lambda u: (Path(src) / u.rsplit("/", 1)[1]).read_bytes()
            r = archivum.frissites(Path(dst), fetch, "mem://x/", log=lambda m: None)
            self.assertEqual(r["uj"], ["kukorica_hu.json"])
            r = archivum.frissites(Path(dst), fetch, "mem://x/", log=lambda m: None)
            self.assertEqual(r, {"uj": [], "frissitett": [], "hibas": []})

    def test_hamis_ujjlenyomat_es_utvonal(self):
        with tempfile.TemporaryDirectory() as dst:
            files = {"index.json": json.dumps({"fajlok": [
                {"fajl": "kukorica_hu.json", "sha256": "0" * 64},
                {"fajl": "../ki.json", "sha256": "0" * 64}]}).encode(),
                "kukorica_hu.json": json.dumps(_res()).encode()}
            r = archivum.frissites(Path(dst), lambda u: files[u.rsplit("/", 1)[1]], "mem://x/", log=lambda m: None)
            self.assertEqual(len(r["hibas"]), 2)
            self.assertEqual(list(Path(dst).iterdir()), [])


if __name__ == "__main__":
    unittest.main()


class AtvetelTeszt(unittest.TestCase):
    """Kutatáscsere: az átvett fájl számait a kód a FRISSEN letöltött cikkekből igazolja újra."""
    SRC = Path(__file__).resolve().parents[3] / "AETHER_godot" / "archivum" / "bioszen_hu.json"

    def setUp(self):
        from aether_lab.literature import Paper
        self.orig = json.loads(self.SRC.read_text(encoding="utf-8"))
        real = self.orig["publikacio"]["cikkek"]
        # a „hálózat”: mindig az eredeti, valódi cikket adja vissza, bármit ír a fájl
        self.fetch = lambda old: Paper(**real[next(k for k, v in real.items() if v["source_id"] == old["source_id"])])

    def _take(self, data, fetch=None):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "bioszen_hu.json"
            f.write_text(json.dumps(data), encoding="utf-8")
            r = archivum.atvetel(f, Path(d) / "ki", "hu", fetch or self.fetch, log=lambda m: None)
            out = json.loads(Path(r["fajl"]).read_text(encoding="utf-8")) if r.get("ok") else None
            return r, out

    def test_becsuletes_fajl_atjon(self):
        r, out = self._take(self.orig)
        self.assertTrue(r["ok"])
        self.assertEqual(r["ellenorizve"], self.orig["osszefoglalo"]["ellenorizve"])
        self.assertEqual(out["publikacio"]["ai_osszegzes"], "")          # szabad szöveg nem jön át
        self.assertTrue(out["archivum"]["atvett"])
        self.assertEqual(archivum.valid_result(out), "")

    def test_atirt_szam_es_hamis_idezet_kiesik(self):
        bad = json.loads(json.dumps(self.orig))
        claims = [c for c in bad["publikacio"]["allitasok"] if c["statusz"].startswith("ellenorizve")]
        claims[0]["ertek"] = 99.0                       # a szám nincs az idézetben
        for c in claims[1:]:
            pid = c["cikk_azonosito"]                   # kitalált idézet, a fájlbeli absztraktba is beírva
            c["szo_szerinti_idezet"] = "biochar removes 50 GtCO2 per year"
            c["ertek"] = 50.0
            bad["publikacio"]["cikkek"][pid]["abstract"] += " biochar removes 50 GtCO2 per year"
        bad["javaslatok"] = [{"kar": "cdr:bioszen", "kar_ertek": 50.0}]
        r, out = self._take(bad)
        self.assertFalse(r["ok"])

    def test_halozat_nelkul_nem_veszi_at(self):
        r, _ = self._take(self.orig, fetch=lambda old: None)
        self.assertFalse(r["ok"])

    def test_ismeretlen_tema(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "nincsilyen_hu.json"
            f.write_text(json.dumps(self.orig), encoding="utf-8")
            self.assertFalse(archivum.atvetel(f, Path(d) / "ki", "hu", self.fetch, log=lambda m: None)["ok"])
