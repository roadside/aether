extends SceneTree
## Mennyi tennivaló marad a játék végére? Körönként megszámolja, hány lépést tett a gép kutatáson kívül,
## és hány körben nem volt már más lehetőség, csak kutatás. godot --headless --path . -s tools/keso_teszt.gd -- [N] [gép]
const Agent := preload("res://scripts/agent.gd")
const World := preload("res://scripts/world.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n: int = int(a[0]) if a.size() > 0 else 20
	var kind: String = a[1] if a.size() > 1 else "okos"
	var did: Array = []
	var could: Array = []
	for r in 15:
		did.append(0.0)
		could.append(0.0)
	for i in n:
		var world = World.new()
		world.new_game(5000 + i, 4, 0)
		world.ai = true
		var ag = Agent.new(world, 5000 + i)
		var guard := 0
		var seen := {}
		while not world.over() and guard < 4000:
			guard += 1
			var r: int = world.round_i
			if not seen.has(r):
				seen[r] = true
				if ag.actions().any(func(x: Dictionary) -> bool: return not (x["type"] in ["research", "end_round", "dilemma", "skip_summit"])):
					could[r] += 1.0
			var act: Dictionary = ag.policy(kind)
			if not act.is_empty() and not (act["type"] in ["research", "end_round", "dilemma", "skip_summit"]):
				did[r] += 1.0
			if act.is_empty() or not ag.apply(act):
				ag.apply({"type": "skip_summit"})
				if not world.dilemma.is_empty():
					world.resolve_dilemma(0)
				if not ag.apply({"type": "end_round"}):
					break
	var l1 := ""
	var l2 := ""
	for r in 15:
		l1 += " %d:%.1f" % [2026 + r * 5, did[r] / n]
		l2 += " %d:%d%%" % [2026 + r * 5, int(round(100.0 * could[r] / n))]
	print("KESO %s, nem kutató lépés körönként (átlag):%s" % [kind, l1])
	print("KESO %s, a kör elején volt-e más tennivaló, mint kutatás:%s" % [kind, l2])
	quit()
