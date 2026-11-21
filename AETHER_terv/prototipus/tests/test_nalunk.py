"""„Mit jelent ez nálunk?” – offline teszt szintetikus (TESZT) napi adatokkal."""
import datetime as dt
import json
import unittest

from aether_lab import nalunk


def _fake_daily(base=24.0, trend=0.0):
    t, tx, pr = [], [], []
    d = dt.date(1961, 1, 1)
    while d.year <= 2025:
        t.append(d.isoformat())
        summer = 8.0 if d.month in (6, 7, 8) else (-10.0 if d.month in (12, 1, 2) else 0.0)
        tx.append(base + summer + (d.day % 7) + trend * (d.year - 1961))
        pr.append(1.0 if d.month in (6, 7, 8) else 2.0)
        d += dt.timedelta(days=1)
    return {"daily": {"time": t, "temperature_2m_max": tx, "precipitation_sum": pr}}


class TestNalunk(unittest.TestCase):
    def setUp(self):
        self.fake = json.dumps(_fake_daily(trend=0.03)).encode()

    def test_scaling_table_has_hungary(self):
        sc = nalunk.scaling()
        self.assertEqual(sc["orszag_regio"]["HU"], "WCE")
        self.assertGreater(sc["regiok"]["WCE"]["homerseklet_JJA"]["median"], 1.0)
        self.assertAlmostEqual(nalunk.gmst_mean(2006, 2025), 1.09, delta=0.1)

    def test_build_counts_and_projection(self):
        r = nalunk.build(47.5, 19.0, "HU", "TESZT", lambda u: self.fake)
        self.assertEqual(r["regio"], "WCE")
        self.assertGreater(r["mai"]["napok"], r["regi"]["napok"])        # a teszt-trend miatt
        self.assertEqual(r["mai"]["nyari_csapadek"], 92.0)                # 92 nyári nap × 1 mm
        days = [row["napok"] for row in r["tablazat"]]
        self.assertEqual(days, sorted(days))                              # melegebb világ: több forró nap
        rain = [row["nyari_csapadek"] for row in r["tablazat"]]
        self.assertGreater(rain[0], rain[-1])                             # WCE: szárazabb nyár
        two = next(row for row in r["tablazat"] if row["globalis"] == 2.0)
        self.assertLessEqual(two["napok_also"], two["napok"])
        self.assertLessEqual(two["napok"], two["napok_felso"])

    def test_unknown_country(self):
        with self.assertRaises(ValueError):
            nalunk.build(0, 0, "XX", "", lambda u: self.fake)
