extends SceneTree
## Egyensúly-mérés: négy játékostípus, sok Föld. Fej nélkül, ablak és fájlírás nélkül:
##   godot --headless --path . -s tools/egyensuly_teszt.gd -- [N]
## kezdő:   mindig a legkésőbbi (legkönnyebb) célt kéri, metánt és kivonást nem indít;
## átlagos: véletlen sorrendben, véletlen elérhető célt kér, metánt is vállal;
## profi:   mindig a legkorábbi elérhető célt kéri, metánt és kivonást is indít;
## okos:    a legnagyobb kibocsátókkal kezd, az ő aggodalmaikhoz kutat, a legkorábbi elérhető célt kéri.
const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")


func _choose_target(w, g, kind: String, rng: RandomNumberGenerator):
	var n: int = w.usable(g).size()
	var ok: Array = w.targets_for(g).filter(func(t): return n >= w.cards_needed(g, t))
	if ok.is_empty():
		return null
	match kind:
		"kezdo":
			return ok[0]                         # a legkésőbbi (legkönnyebb) cél
		"atlagos":
			return ok[rng.randi_range(0, ok.size() - 1)]
		_:
			return ok[ok.size() - 1]             # a legkorábbi elérhető cél


func _play(kind: String, seed_v: int) -> Dictionary:
	var w = World.new()
	w.new_game(seed_v)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 7
	var st := {"csak_kutatas_kor": 0, "elso_egyezseg": 0, "egyezseg": 0, "metan": 0, "kivonas": 0,
		"visszalepes": 0, "kitartott": 0, "felkeszult": 0}
	while not w.over():
		var only_research := true
		while w.steps > 0:
			var acted := false
			var order: Array = w.groups.duplicate()
			if kind == "okos":
				order.sort_custom(func(a, b): return float(a["co2_resz"]) > float(b["co2_resz"]))
			elif kind != "profi":
				order.shuffle()
			for g in order:
				var t = _choose_target(w, g, kind, rng)
				if t != null:
					acted = w.negotiate(g, t, w.usable(g).slice(0, w.cards_needed(g, t)))
					if acted:
						st["egyezseg"] += 1
						if st["elso_egyezseg"] == 0:
							st["elso_egyezseg"] = w.year()
						break
				if kind != "kezdo" and int(g["metan"]) == 0:
					var mc: Array = w.methane_cards(g)
					if mc.size() >= w.methane_needed(g):
						acted = w.pledge_methane(g, mc.slice(0, w.methane_needed(g)))
						if acted:
							st["metan"] += 1
							break
			if acted:
				only_research = false
				continue
			if kind in ["profi", "okos"]:
				for id in w.cdr_available():
					acted = w.start_cdr(id)
					if acted:
						st["kivonas"] += 1
						only_research = false
					break
			if acted:
				continue
			if kind in ["profi", "okos"] and w.has_method("prepare"):
				for g in order:
					if not g.get("felkeszult", false) and int(g["cel"]) > 0 and not w.prepare_cards(g).is_empty():
						acted = w.prepare(g, w.prepare_cards(g)[0])
						if acted:
							st["felkeszult"] += 1
							only_research = false
							break
			if acted:
				continue
			var ths: Array = Cards.THEMES.keys()
			if kind == "okos":
				ths = []
				for g in order.slice(0, 3):
					ths.append_array(g["felelmek"])
			var of: Array = w.research_offers(ths[rng.randi_range(0, ths.size() - 1)])
			if of.is_empty():
				w.steps -= 1
				continue
			w.research(of[0])
		if only_research:
			st["csak_kutatas_kor"] += 1
		w.advance()
		for n in w.news:
			if n["fajta"] == "visszalepett":
				st["visszalepes"] += 1
			elif n["fajta"] == "kitartott":
				st["kitartott"] += 1
	var r: Dictionary = w.result()
	st["T"] = float(r["T"])
	st["billenes"] = int(r["billenes"])
	return st


func _q(vals: Array, f: float) -> float:
	var v := vals.duplicate()
	v.sort()
	return float(v[clampi(int(f * (v.size() - 1)), 0, v.size() - 1)])


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n: int = int(a[0]) if a.size() > 0 else 100
	for kind in ["kezdo", "atlagos", "profi", "okos"]:
		var runs: Array = []
		for i in n:
			runs.append(_play(kind, 1000 + i))
		var ts: Array = runs.map(func(r): return r["T"])
		var b15 := runs.filter(func(r): return r["T"] < 1.6).size()
		var b20 := runs.filter(func(r): return r["T"] >= 1.6 and r["T"] < 2.0).size()
		var bx := runs.filter(func(r): return r["T"] >= 2.0).size()
		print("== %s (%d Föld) ==  T2100 10%%/közép/90%%: %.2f / %.2f / %.2f   <1,6: %d  1,6–2,0: %d  >=2,0: %d" % [kind, n, _q(ts, 0.1), _q(ts, 0.5), _q(ts, 0.9), b15, b20, bx])
		var line := "  "
		for key in ["egyezseg", "elso_egyezseg", "metan", "kivonas", "felkeszult", "csak_kutatas_kor", "visszalepes", "kitartott", "billenes"]:
			var vals: Array = runs.map(func(r): return float(r[key]))
			line += " %s %.0f/%.0f/%.0f" % [key, _q(vals, 0.1), _q(vals, 0.5), _q(vals, 0.9)]
		print(line)
	quit()
