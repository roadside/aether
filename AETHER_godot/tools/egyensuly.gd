extends SceneTree
## Egyensúly-mérés: sok véletlen Földön végigjátssza a 74 évet három egyszerű játékostípussal,
## és kiírja, hogyan alakul a pénz, a bizalom, a kár és a pontszám. Nem része a játéknak.
## Futtatás:  godot --headless --path . -s tools/egyensuly.gd -- <alap_modell.json> <terv_modell.json> [N]
## A két modellfájl a játék saját kimenete (terv nélküli alapeset, illetve egy bevezetett terv).

const Campaign := preload("res://scripts/campaign.gd")
const Events := preload("res://scripts/events.gd")
const Knowledge := preload("res://scripts/knowledge.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

const PLAN := {"cdr": {}, "co2_cel_ertek": 0.0, "co2_cel_ev": 2050, "metan_cel_ev": 2030, "metan_csokkentes_pct": 0.0}


func _pick_topic(c, rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for q in Knowledge.topics():
		if int(q["korszak"]) <= c.era and not (q["id"] in c.done):
			pool.append(q["id"])
	return "" if pool.is_empty() else str(pool[rng.randi() % pool.size()])


func _play(kind: String, seed_value: int, base: Dictionary, plan: Dictionary) -> Dictionary:
	var c = Campaign.new()
	c.autosave = false
	c.save_file = "aether_egyensuly.json"
	c.new_game(seed_value)
	c.model = base
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 1
	var st := {"nulla_ev": 0, "esemeny": 0, "kar": 0, "part": 0, "min_bizalom": 100, "penz2050": 0, "terv_ev": 0}
	while c.year < Campaign.END_YEAR:
		# a játékos lépései az évben
		if kind != "lusta":
			var want: int = 1 if kind == "atlagos" else c.research_limit()
			for i in want:
				if c.research_this_year >= c.research_limit():
					break
				var id := _pick_topic(c, rng)
				if id == "":      # minden téma megvan: csillagokat javít (újrakutatás)
					for d in c.done:
						if int(c.stars.get(d, 1)) < 3:
							id = str(d)
							break
					if id == "" or not c.can_research():
						break
					c.pay_research()
					c.mark_researched(id, int(c.stars.get(id, 1)) + 1)
					continue
				if c.can_research() and c.money >= c.research_cost() + 40:
					c.pay_research()
					if rng.randf() < 0.8:
						c.mark_researched(id, 1 + int(rng.randf() < 0.3))
						if rng.randf() < 0.15:
							c.reward_results(1)
				else:
					c.research_this_year += 1     # „Elolvastam, értem”: pénz nélkül, 1 csillag
					c.mark_researched(id, 1)
			var plan_from: int = 2028 if kind == "atlagos" else 2027
			if c.timeline.is_empty() and c.year >= plan_from and c.adopt_problem(PLAN) == "":
				c.adopt(PLAN, plan)
				st["terv_ev"] = c.year
			if kind == "szorgalmas" and c.building.is_empty():
				for mod in ["ai_mag", "uveghaz", "archivum"]:
					if c.module_cost(mod) > 0 and c.money >= c.module_cost(mod) + 120:
						c.build(mod)
						break
		var before: int = c.money
		var cc: int = c.coast_cost(c.year + 1)
		c.advance()
		st["part"] += cc
		var evs: Array = Events.draw(c, c.year)
		Events.apply(c, evs)
		for e in evs:
			if not e.get("jo", false):
				st["esemeny"] += 1
				st["kar"] += int(e["kar_penz"])
		if c.money <= 0:
			st["nulla_ev"] += 1
		st["min_bizalom"] = mini(int(st["min_bizalom"]), c.trust)
		if c.year == 2050:
			st["penz2050"] = c.money
	st["penz2100"] = c.money
	st["bizalom2100"] = c.trust
	st["temak"] = c.done.size()
	st["korszak"] = c.era
	st["T2100"] = c.real_t2100()
	st["pont"] = c.score()
	st["vulkan"] = c.volcanoes.size()
	c.free()
	return st


func _q(vals: Array, f: float) -> float:
	var v := vals.duplicate()
	v.sort()
	return float(v[clampi(int(f * (v.size() - 1)), 0, v.size() - 1)])


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var base: Variant = Bridge.read_json(a[0])
	var plan: Variant = Bridge.read_json(a[1])
	var n: int = int(a[2]) if a.size() > 2 else 200
	if typeof(base) != TYPE_DICTIONARY or typeof(plan) != TYPE_DICTIONARY:
		print("Nem olvasható a modellfájl.")
		quit(1)
		return
	for kind in ["lusta", "atlagos", "szorgalmas"]:
		var runs: Array = []
		for i in n:
			runs.append(_play(kind, 100000 + i * 37, base, plan))
		print("== ", kind, " (", n, " Föld) ==")
		for key in ["penz2050", "penz2100", "bizalom2100", "min_bizalom", "nulla_ev", "esemeny", "kar", "part", "temak", "korszak", "terv_ev", "T2100", "pont", "vulkan"]:
			var vals: Array = runs.map(func(r): return float(r[key]))
			print("  %-12s  10%%: %7.1f   közép: %7.1f   90%%: %7.1f" % [key, _q(vals, 0.1), _q(vals, 0.5), _q(vals, 0.9)])
	quit()
