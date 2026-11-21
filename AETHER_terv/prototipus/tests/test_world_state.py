"""A valós kiindulópont feldolgozóinak offline tesztjei.
A tesztadatok SZINTETIKUSAK ("TESZT"), csak a formátumot ellenőrzik."""
import datetime as dt
import json
import unittest

from aether_lab import world_state as ws

GDACS = {"features": [{"geometry": {"type": "Point", "coordinates": [36.8, -1.3]},
    "properties": {"eventtype": "DR", "eventid": 1, "name": "TESZT aszály", "alertlevel": "Orange",
                   "country": "TESZTország", "fromdate": "2026-10-01T00:00:00",
                   "url": {"report": "https://www.gdacs.org/report.aspx?eventid=1"},
                   "severitydata": {"severitytext": "TESZT súlyosság"}}}]}
RELIEF = {"data": [{"id": 1, "fields": {"title": "TESZT: food insecurity report", "url": "https://reliefweb.int/report/teszt",
    "date": {"created": "2026-11-20T10:00:00+00:00"},
    "primary_country": {"name": "TESZTország", "location": {"lat": 9.1, "lon": 40.5}},
    "source": [{"shortname": "WFP"}], "disaster_type": [{"name": "Drought"}]}}]}
EONET = {"events": [{"id": "E1", "title": "TESZT Wildfire", "link": "https://eonet.gsfc.nasa.gov/api/v3/events/E1",
    "categories": [{"id": "wildfires"}], "sources": [{"id": "IRWIN", "url": "https://example.org/teszt"}],
    "geometry": [{"date": "2026-11-18T00:00:00Z", "type": "Point", "coordinates": [-120.5, 38.2]}]},
    {"id": "E2", "title": "TESZT Iceberg", "link": "https://eonet.gsfc.nasa.gov/api/v3/events/E2",
    "categories": [{"id": "seaLakeIce"}], "sources": [],
    "geometry": [{"date": "2026-11-10T00:00:00Z", "type": "Polygon", "coordinates": [[[-60.0, -70.0], [-61.0, -70.5]]]}]}]}
CO2 = "# TESZT\nyear,month,decimal date,average,deseasonalized,ndays,sdev,unc\n2025,10,2025.79,400.00,401,20,0.3,0.1\n2026,10,2026.79,402.50,403,20,0.3,0.1\n"
ICE = "Year, Month, Day, Extent, Missing, Source Data\nYYYY, MM, DD, 10^6 sq km, 10^6 sq km, Source data\n" + \
      "".join(f"{y}, 11, 20, 10.0, 0.0, x\n" for y in range(1981, 2011)) + "2026, 11, 20, 9.0, 0.0, x\n"


class TestParsers(unittest.TestCase):
    def test_gdacs(self):
        e = ws.parse_gdacs(GDACS)[0]
        self.assertEqual((e["kategoria"], e["lat"], e["lon"], e["szint"]), ("aszaly", -1.3, 36.8, "orange"))
        self.assertTrue(e["link"].startswith("https://www.gdacs.org"))

    def test_gdacs_url_dates(self):
        u = ws.gdacs_url(days=30, today=dt.date(2026, 11, 21))
        self.assertIn("fromdate=2026-10-22", u)

    def test_reliefweb(self):
        e = ws.parse_reliefweb(RELIEF)[0]
        self.assertEqual(e["kategoria"], "ehezes")
        self.assertEqual(e["orszag"], "TESZTország")
        self.assertEqual(e["datum"], "2026-11-20")
        self.assertIn("WFP", e["forras"])

    def test_eonet_point_and_polygon(self):
        a, b = ws.parse_eonet(EONET)
        self.assertEqual((a["kategoria"], a["lat"], a["link"]), ("tuz", 38.2, "https://example.org/teszt"))
        self.assertEqual((b["kategoria"], b["lat"], b["lon"]), ("jeg", -70.0, -60.0))

    def test_co2(self):
        m = ws.parse_noaa_co2(CO2)
        self.assertEqual((m["ertek"], m["datum"], m["valtozas_1_ev"]), (402.5, "2026-10", 2.5))

    def test_ice(self):
        m = ws.parse_nsidc(ICE)
        self.assertEqual((m["ertek"], m["atlag_1981_2010"], m["elteres_pct"]), (9.0, 10.0, -10.0))


AIR = [{"current": {"time": "2026-11-21T17:00", "pm2_5": 160.0, "pm10": 200.0, "nitrogen_dioxide": 50.0,
                    "ozone": 20.0, "uv_index": 0.0, "european_aqi": 120}},
       {"current": {"time": "2026-11-21T17:00", "pm2_5": 8.0, "uv_index": 11.5}}]
CITIES2 = [("TESZT-Delhi", 28.61, 77.21), ("TESZT-Sydney", -33.87, 151.21)]


class TestOpenMeteo(unittest.TestCase):
    def test_air_rows_events_summary(self):
        rows = ws.parse_open_meteo_air(AIR, CITIES2)
        self.assertEqual(len(rows), 2)
        self.assertIn("latitude=28.61", rows[0]["link"])
        ev = ws.air_events(rows)
        kinds = sorted(e["kategoria"] for e in ev)
        self.assertEqual(kinds, ["levego", "uv"])
        self.assertEqual({e["szint"] for e in ev}, {"red"})
        self.assertEqual({e["orszag"] for e in ev}, {"India", "Australia"})
        s = ws.air_summary(rows)
        self.assertEqual((s["ertek"], s["legrosszabb"]), (1, "TESZT-Delhi"))
        self.assertIn("Modellbecslés", s["magyarazat"])

    def test_single_city_dict(self):
        rows = ws.parse_open_meteo_air(AIR[1], CITIES2[1:])
        self.assertEqual(rows[0]["uv"], 11.5)


class TestGeo(unittest.TestCase):
    def test_country(self):
        from aether_lab.geo import country_at
        self.assertEqual(country_at(47.5, 19.0), "Hungary")
        self.assertEqual(country_at(0.0, -140.0), "")   # nyílt óceán: nem találunk ki országot
        self.assertEqual(country_at(None, None), "")


class TestBuild(unittest.TestCase):
    def test_failures_are_reported_not_invented(self):
        def fetch(url, data=None):
            if "gdacs" in url:
                return json.dumps(GDACS).encode()
            if "eonet" in url:
                return json.dumps(EONET).encode()
            raise ConnectionError("TESZT: nincs hálózat")
        w = ws.build(fetch=fetch, log=lambda *_: None, today=dt.date(2026, 11, 21))
        self.assertTrue(w["forrasok"]["GDACS"]["ok"])
        self.assertFalse(w["forrasok"]["ReliefWeb"]["ok"])
        self.assertFalse(w["forrasok"]["NOAA CO2"]["ok"])
        self.assertEqual(w["meresek"], [])            # nincs kitalált pótadat
        self.assertFalse(w["forrasok"]["Levegő és UV (Open-Meteo/CAMS)"]["ok"])
        self.assertEqual(len(w["esemenyek"]), 3)
        self.assertEqual(w["esemenyek"][0]["orszag"], "United States")  # EONET-koordinátából
        self.assertEqual(w["esemenyek"][0]["datum"], "2026-11-18")  # legfrissebb elöl
        for e in w["esemenyek"]:
            self.assertTrue(e["link"])


if __name__ == "__main__":
    unittest.main()
