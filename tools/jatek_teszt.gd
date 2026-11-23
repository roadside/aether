extends SceneTree
## A szabályok próbája felület nélkül: egy egyszerű „játékos” végigjátszik néhány Földet.
##   godot --headless -s tools/jatek_teszt.gd
const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")

func _init() -> void:
	Cards.load_all()
	print("KARTYAK ", Cards.ids().size(), " besorolva: ", Cards.ids().filter(func(i: String) -> bool: return Cards.theme_of(i) != "").size())
	for seed_v in [1, 2, 3, 4, 5, 6]:
		var w := World.new()
		w.new_game(seed_v)
		var lazy: bool = seed_v == 6
		while not w.over():
			while w.steps > 0 and not lazy:
				var acted := false
				for g in w.groups:
					var ts: Array = w.targets_for(g)
					if ts.is_empty():
						continue
					var t: int = ts[0] if int(g["cel"]) == 0 else ts.max()
					var u: Array = w.usable(g)
					if u.size() >= w.cards_needed(g, t):
						acted = w.negotiate(g, t, u.slice(0, w.cards_needed(g, t)))
						if acted:
							break
				if not acted:
					for id in w.cdr_available():
						acted = w.start_cdr(id)
						break
				if not acted:
					var themes: Array = Cards.talk_themes()
					var offers: Array = w.research_offers(themes[w.rng.randi_range(0, themes.size() - 1)])
					if offers.is_empty():
						break
					w.research(offers[0])
			w.advance()
		var r := w.result()
		var d := w.to_dict()
		var w2 := World.new()
		var ok := w2.from_dict(JSON.parse_string(JSON.stringify(d)))
		print("FOLD mag=%d erz=%.2f T2100=%.2f alap=%.2f csucs=%.2f billenes=%d kartya=%d kivonas=%d celok=%s mentes=%s" % [seed_v, r["sens"], r["T"], r["alap"], r["csucs"],
			r["billenes"], w.hand.size(), w.cdr.size(), str(w.groups.map(func(g: Dictionary) -> int: return int(g["cel"]))), str(ok and w2.round_i == w.round_i)])
	# szabálypróba: bizonytalan csoport megerősítése, megingás, felkészülés
	var w3 := World.new()
	w3.new_game(77)
	var g: Dictionary = w3.groups[0]
	while w3.usable(g).size() < 2:
		for th in g["felelmek"]:
			var of := w3.research_offers(th)
			if not of.is_empty():
				w3.research(of[0])
		w3.steps = World.STEPS
	var t0: int = w3.targets_for(g)[0]
	var ok1 := w3.negotiate(g, t0, w3.usable(g).slice(0, 1))
	g["inog"] = true
	var ok2 := w3.reassure(g, w3.usable(g)[0])
	g["inog"] = true
	w3.rng.seed = 1
	w3.steps = 0
	w3.advance()
	var wavered: bool = int(g["cel"]) == mini(t0 + 10, 2100)
	g["felkeszult"] = true
	g["inog"] = true
	var c1 := int(g["cel"])
	w3.advance()
	print("SZABALY egyezseg=%s megerosites=%s megingas=%s felkeszult_kitart=%s naplo=%d" % [ok1, ok2 and true, wavered, int(g["cel"]) == c1, w3.naplo.size()])
	quit()
