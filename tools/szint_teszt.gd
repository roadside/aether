extends SceneTree
## Szintlépcső mérése: az okos gép sorban végigjátssza a 0–5. szintet; a már felhasznált kártyák
## a következő szinteken tiltottak. Megmutatja, hány kártya fogy, és melyik témakörben kevés az új.
## godot --headless --path . -s tools/szint_teszt.gd -- [N]
const Agent := preload("res://scripts/agent.gd")
const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n: int = int(a[0]) if a.size() > 0 else 10
	var short := {}      # témakör -> hány létrán fogyott el az új kártya
	var per_level: Array = [0, 0, 0, 0, 0, 0]
	for i in n:
		var banned: Array = []
		for level in World.CHALLENGE_MAX + 1:
			var world = World.new()
			world.new_game(3000 + i * 7 + level, 4, level)
			world.ai = true
			world.banned = banned.duplicate()
			var ag = Agent.new(world, 3000 + i)
			var guard := 0
			while not world.over() and guard < 4000:
				guard += 1
				var act: Dictionary = ag.policy("okos")
				if act.is_empty() or not ag.apply(act):
					ag.apply({"type": "skip_summit"})
					if not world.dilemma.is_empty():
						world.resolve_dilemma(0)
					if not ag.apply({"type": "end_round"}):
						break
			var used: Array = world.used_cards()
			per_level[level] += used.size()
			for id in used:
				if id in banned:
					short[Cards.theme_of(id)] = int(short.get(Cards.theme_of(id), 0)) + 1
				else:
					banned.append(id)
	var line := ""
	for level in per_level.size():
		line += " %d.: %.1f" % [level, float(per_level[level]) / n]
	print("SZINT felhasznált kártya szintenként (átlag, %d létra):%s" % [n, line])
	var have := ""
	for th in Cards.talk_themes():
		have += " %s=%d" % [th, (Cards.TAGS[th] as Array).size()]
	print("SZINT kártyák témakörönként:%s" % have)
	print("SZINT ismétlődő (régi) kártya létránként, témakörönként: %s" % str(short.keys().map(func(k: String) -> String: return "%s=%.1f" % [k, float(short[k]) / n])))
	quit()
