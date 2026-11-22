import json
import tempfile
import threading
import time
import unittest
from pathlib import Path

from aether_lab.biztos_iras import write_text


class BiztosIrasTeszt(unittest.TestCase):
    def test_sima_iras(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "allapot.json"
            write_text(p, json.dumps({"a": 1}))
            self.assertEqual(json.loads(p.read_text(encoding="utf-8")), {"a": 1})
            self.assertFalse(p.with_suffix(".json.tmp").exists())

    def test_nyitott_fajl_mellett_sem_all_le(self):
        # Windowson az olvasásra nyitott célfájl miatt az os.replace PermissionError-t ad;
        # az írásnak ilyenkor sem szabad kivételt dobnia, és a végén a jó tartalomnak kell ott lennie
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "allapot.json"
            p.write_text("{}", encoding="utf-8")
            f = open(p, "r", encoding="utf-8")
            t = threading.Timer(0.12, f.close)
            t.start()
            try:
                write_text(p, json.dumps({"lepes": 2}), tries=10, wait=0.05)
            finally:
                t.join()
                if not f.closed:
                    f.close()
            time.sleep(0.05)
            self.assertEqual(json.loads(p.read_text(encoding="utf-8")), {"lepes": 2})


if __name__ == "__main__":
    unittest.main()
