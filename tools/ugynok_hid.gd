extends SceneTree
## Híd külső AI-ügynököknek: a játék ablak nélkül, soronként egy JSON-nal irányítható (stdin → stdout).
##   godot --headless --path . -s tools/ugynok_hid.gd -- [--en]
## Be:  {"cmd":"new","seed":2026,"steps":4,"challenge":0} | {"cmd":"state"} | {"cmd":"act","action":{...}}
##      | {"cmd":"auto","agent":"okos"} (a beépített gép lép egyet) | {"cmd":"quit"}
## Ki:  {"ok":true|false,"error":"...","state":{...}} – a state "actions" mezője a most szabályos lépések listája.
## A válaszsorok elején "AETHER " áll, hogy a motor saját kiírásaitól meg lehessen különböztetni.
const World := preload("res://scripts/world.gd")
const Agent := preload("res://scripts/agent.gd")
const L := preload("res://scripts/i18n.gd")


func _say(d: Dictionary) -> void:
	print("AETHER " + JSON.stringify(d))


func _init() -> void:
	L.init()
	var w = World.new()
	w.new_game(2026)
	w.ai = true
	var ag = Agent.new(w, 2026)
	_say({"ok": true, "hello": "AETHER", "protocol": 1, "state": ag.observe()})
	while true:
		var line := OS.read_string_from_stdin().strip_edges()
		if line == "":
			break                                   # a bemenet véget ért
		var msg: Variant = JSON.parse_string(line)
		if typeof(msg) != TYPE_DICTIONARY:
			_say({"ok": false, "error": "not a JSON object"})
			continue
		match str(msg.get("cmd", "")):
			"new":
				w.new_game(int(msg.get("seed", -1)), int(msg.get("steps", 4)), int(msg.get("challenge", 0)))
				w.ai = true
				ag = Agent.new(w, w.seed_v)
				_say({"ok": true, "state": ag.observe()})
			"state":
				_say({"ok": true, "state": ag.observe()})
			"act":
				var a: Variant = msg.get("action", {})
				var ok: bool = typeof(a) == TYPE_DICTIONARY and ag.apply(a)
				_say({"ok": ok, "error": "" if ok else "illegal action", "state": ag.observe()})
			"auto":
				var p: Dictionary = ag.policy(str(msg.get("agent", "okos")))
				var ok2: bool = not p.is_empty() and ag.apply(p)
				_say({"ok": ok2, "action": p, "state": ag.observe()})
			"quit":
				break
			_:
				_say({"ok": false, "error": "unknown cmd"})
	quit()
