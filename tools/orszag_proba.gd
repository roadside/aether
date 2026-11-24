extends SceneTree
## Fej nélkül kiírja, mit kapnának az AI-országok egy új játék elején (godot --headless -s tools/orszag_proba.gd [-- en]).
## Minden csoporthoz két kérés: a legkönnyebb cél két kártyával, és a kör végi saját lépés. A tools/orszag_proba.py olvassa.
const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")
const Nation := preload("res://scripts/nation.gd")


func _init() -> void:
	var en := "en" in OS.get_cmdline_user_args()
	var w = World.new()
	w.new_game(2026)
	for g in w.groups:
		var cards: Array = []
		for th in g["felelmek"]:
			var open: Array = Cards.open_in(th, w.max_era(), [])
			if not open.is_empty() and cards.size() < 2:
				cards.append(open[0])
		var ts: Array = w.targets_for(g)
		print("ORSZAGKERES " + JSON.stringify({"csoport": g["id"], "fajta": "keres", "cel": int(ts[0]), "hangulat": Nation.mood(w, g), "uzenetek": Nation.prompt(w, g, int(ts[0]), cards, en)}))
		print("ORSZAGKERES " + JSON.stringify({"csoport": g["id"], "fajta": "sajat_lepes", "hangulat": Nation.mood(w, g), "uzenetek": Nation.prompt_round(w, g, en)}))
	quit()
