"""Climate Pulse napi sor feldolgozása: hálózat nélkül, kitalált (teszt) számokkal."""
import datetime as dt
import json
import unittest

from aether_lab import pulse


def _csv(first=1990, last=2026, last_day=dt.date(2026, 11, 20), with_pi=True):
    """Minden év minden napja: 14 °C + 0,02 °C/év 1990 óta; az idei év csak last_day-ig."""
    lines = ["# teszt", "date,2t,clim_91-20,ano_91-20" + (",ano_pi" if with_pi else "")]
    d = dt.date(first, 1, 1)
    while d <= last_day and d.year <= last:
        v = 14.0 + 0.02 * (d.year - 1990)
        clim = 14.0 + 0.02 * 15.5          # az 1991–2020-as évek átlaga
        row = [d.isoformat(), f"{v:.3f}", f"{clim:.3f}", f"{v - clim:.3f}"]
        if with_pi:
            row.append(f"{v - clim + 0.88:.3f}")
        lines.append(",".join(row))
        d += dt.timedelta(days=1)
    return "\n".join(lines)


class TestPulse(unittest.TestCase):
    def test_summary(self):
        out = pulse.summarize(_csv())
        self.assertEqual(out["ma"]["datum"], "2026-11-20")
        self.assertEqual(out["ev"], 2026)
        self.assertEqual(out["elso_ev"], 1990)
        self.assertEqual(out["rang"], 1)                 # minden év melegebb az előzőnél
        self.assertEqual(out["evek_szama"], 37)
        self.assertAlmostEqual(out["ma"]["ertek"], 14.72, places=2)
        self.assertAlmostEqual(out["ma"]["elteres_1991_2020"], 0.41, places=2)
        self.assertAlmostEqual(out["ma"]["elteres_ipar_elott"], 1.29, places=2)
        self.assertEqual(len(out["atlag"]), 366)
        self.assertAlmostEqual(out["atlag"][0], 14.31, places=2)
        self.assertEqual(len(out["ev_gorbe"]), pulse._doy(dt.date(2026, 11, 20)) + 1)
        self.assertEqual(out["nap_evente"][0][0], 1990)
        self.assertEqual(out["nap_evente"][-1], [2026, 0.41])
        json.dumps(out)

    def test_leap_day_and_band(self):
        out = pulse.summarize(_csv())
        k = pulse._doy(dt.date(2024, 2, 29))
        self.assertEqual(k, 59)
        self.assertIsNotNone(out["atlag"][k])            # 1992, 1996, ... szökőévekből
        self.assertAlmostEqual(out["sav_min"][0], 14.0, places=2)
        self.assertAlmostEqual(out["sav_max"][0], 14.70, places=2)   # 2025, az idei év nincs a sávban
        self.assertIsNone(out["ev_gorbe"][59])           # 2026 nem szökőév

    def test_yearly(self):
        out = pulse.summarize(_csv())
        ev = out["evente"]
        self.assertEqual(ev[0][0], 1990)
        self.assertEqual(ev[-1][0], 2026)                # az idei év az eddigi napokból
        self.assertAlmostEqual(ev[0][1], -0.31, places=2)
        self.assertAlmostEqual(ev[-1][1], 0.41, places=2)
        self.assertAlmostEqual(ev[-1][2], 1.29, places=2)
        self.assertIsNone(pulse.summarize(_csv(with_pi=False))["evente"][-1][2])

    def test_build_uses_fetch(self):
        out = pulse.build("tenger", fetch=lambda url, timeout=0: _csv().encode())
        self.assertEqual(out["fajta"], "tenger")
        self.assertIn("Copernicus", out["forras"])

    def test_empty(self):
        with self.assertRaises(ValueError):
            pulse.summarize("# semmi\n")


if __name__ == "__main__":
    unittest.main()
