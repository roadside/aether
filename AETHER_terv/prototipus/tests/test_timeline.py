"""A telő idő modellje: a terv csak a bevezetés évétől hat, a múlt nem változik."""
import unittest

from aether_lab import climate as cl
from aether_lab.godot_bridge import model_series

ZERO_2050 = cl.Scenario(co2_cel_ev=2050, co2_cel_ertek=0.0, metan_csokkentes_pct=45)
BASE = cl.Scenario()


class TestTimeline(unittest.TestCase):
    def test_single_segment_is_plain_run(self):
        a = cl.run(ZERO_2050, "kozep")
        b = cl.run(ZERO_2050, "kozep", timeline=[(cl.START_YEAR, ZERO_2050)])
        self.assertEqual(a.temp, b.temp)

    def test_delay_costs_warming(self):
        t = [cl.run(ZERO_2050, "kozep", timeline=[(2025, BASE), (y, ZERO_2050)]).at(2100) for y in (2027, 2035, 2045)]
        self.assertLess(t[0], t[1])
        self.assertLess(t[1], t[2])

    def test_history_is_fixed(self):
        a = cl.run(ZERO_2050, "kozep", timeline=[(2025, BASE), (2030, ZERO_2050)])
        b = cl.run(BASE, "kozep", timeline=[(2025, BASE), (2030, ZERO_2050), (2040, BASE)])
        i = a.years.index(2040)
        self.assertEqual(a.temp[:i], b.temp[:i])
        # visszalépés után a kibocsátás ott marad, ahol volt (nem ugrik vissza a mai szintre)
        self.assertAlmostEqual(b.co2_net[i], b.co2_net[a.years.index(2060)])
        self.assertLess(b.co2_net[i], cl.E_CO2_NOW)

    def test_bridge_timeline(self):
        r = model_series({"idovonal": [{"ev": 2027, "terv": {"co2_cel_ev": 2050, "co2_cel_ertek": 0.0}}]})
        self.assertEqual(r["idovonal"][0]["ev"], cl.START_YEAR)   # a játék előtti évek: alapeset
        self.assertLess(r["osszegzes"]["kozep"]["T2100"], r["alapeset_osszegzes"]["kozep"]["T2100"])


if __name__ == "__main__":
    unittest.main()
