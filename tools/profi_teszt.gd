extends SceneTree
## Mit érhet el egy törekvő játékos? Mindig a legkorábbi elérhető célt kéri, metánt és kivonást is indít.
const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")

func _init() -> void:
	for seed_v in [1, 2, 3, 4, 5, 6, 7, 8]:
		var w := World.new()
		w.new_game(seed_v)
		while not w.over():
			while w.steps > 0:
				var acted := false
				for g in w.groups:
					var ts := w.targets_for(g)
					ts.reverse()                      # a legkorábbi cél elöl
					for t in ts:
						var need := w.cards_needed(g, t)
						if w.usable(g).size() >= need:
							acted = w.negotiate(g, t, w.usable(g).slice(0, need))
							break
					if acted:
						break
					if int(g["metan"]) == 0 and not w.methane_cards(g).is_empty():
						acted = w.pledge_methane(g, w.methane_cards(g)[0])
						if acted:
							break
				if not acted:
					for id in w.cdr_available():
						acted = w.start_cdr(id)
						break
				if not acted:
					var ths: Array = Cards.THEMES.keys()
					var of := w.research_offers(ths[w.rng.randi_range(0, ths.size() - 1)])
					if of.is_empty():
						break
					w.research(of[0])
			w.advance()
		var r := w.result()
		var cel: Array = []
		for g in w.groups:
			cel.append(int(g["cel"]))
		print("PROFI mag=%d erz=%.2f T2100=%.2f alap=%.2f csucs=%.2f kuszob=%d celok=%s kivonas=%d" % [seed_v, r["sens"], r["T"], r["alap"], r["csucs"], r["billenes"], str(cel), w.cdr.size()])
	quit()
