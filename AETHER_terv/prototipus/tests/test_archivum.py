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
