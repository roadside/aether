extends SceneTree
## A klímacsúcs (scripts/summit.gd) próbája, fájlírás nélkül:
##   Godot --headless --path . -s tools/csucs_teszt.gd
## Minden sor végén „true” a várt eredmény.

const Campaign := preload("res://scripts/campaign.gd")
const Summit := preload("res://scripts/summit.gd")


func _init():
	var c = Campaign.new()
	c.autosave = false
	c.save_file = "aether_csucs_teszt.json"
	c.new_game(4242)
	print("2029-ben nincs csúcs: ", Summit.pick(c, 2029).is_empty())
	var d: Dictionary = Summit.pick(c, 2030)
	print("2030, terv nélkül tervet kér: ", d.get("fajta") == "terv")
	print("szöveg: ", Summit.ask_text(d))
	var t0: int = c.trust
	Summit.accept(c, d)
	print("vállalás után nincs újra csúcs 2030-ban: ", Summit.pick(c, 2030).is_empty())
	c.year = 2033
	var m0: int = c.money
	var n: String = Summit.check(c, 2033)
	print("határidő után terv nélkül elmulasztva: ", c.trust == maxi(0, t0 - Summit.FAIL_TRUST) and c.money == m0)
	print("  ", n)
	# terv bevezetve (2050-es CO2-nulla, 0% metán): 2035-ben CO2-t kér
	c.year = 2034
	c.timeline = [{"ev": 2030, "terv": {"co2_cel_ev": 2050, "metan_csokkentes_pct": 0.0, "cdr": {}}}]
	var d2: Dictionary = Summit.pick(c, 2035)
	print("2035, CO2-t kér 2045-re: ", d2.get("fajta") == "co2" and int(d2.get("cel", 0)) == 2045)
	print("szöveg: ", Summit.ask_text(d2))
	Summit.accept(c, d2)
	c.timeline.append({"ev": 2036, "terv": {"co2_cel_ev": 2045, "metan_csokkentes_pct": 0.0, "cdr": {}}})
	var m1: int = c.money
	Summit.check(c, 2038)
	print("teljesítve: jutalom jár: ", c.money == m1 + Summit.WIN_MONEY)
	c.era = 2
	var d3: Dictionary = Summit.pick(c, 2040)
	print("2040 (páratlan csúcs, II. korszak): metánt kér 10%-ra: ", d3.get("fajta") == "metan" and int(d3.get("cel", 0)) == 10)
	print("szöveg: ", Summit.ask_text(d3))
	var t1: int = c.trust
	Summit.decline(c, d3)
	print("elutasítás bizalomba kerül: ", c.trust == maxi(0, t1 - Summit.DECLINE_TRUST))
	c.timeline.append({"ev": 2041, "terv": {"co2_cel_ev": 2035, "metan_csokkentes_pct": 45.0, "cdr": {}}})
	c.money = 500
	var d4: Dictionary = Summit.pick(c, 2045)
	print("2045, a legerősebb tervnél klímaalapot kér (150): ", d4.get("fajta") == "alap" and int(d4.get("penz", 0)) == 150)
	print("szöveg: ", Summit.ask_text(d4))
	Summit.accept(c, d4)
	print("klímaalap azonnal fizet: ", c.money == 350)
	print("függő vállalás szövege üres (nincs függő): ", Summit.pending_text(c) == "")
	var p: Control = Summit.panel(c, Summit.pick(c, 2050), func(): pass)
	print("ablak elkészül: ", p != null)
	p.free()
	c.free()
	quit()
