extends SceneTree
## Az aláírás (scripts/identity.gd) próbája:
##   Godot --headless --path . -s tools/azonosito_teszt.gd
## Minden sor végén „true” a várt eredmény.

func _init():
	var I = load("res://scripts/identity.gd")
	var d := {"publikacio": {"kerdes": "teszt", "x": 1.5, "n": 2}, "archivum": {"nev": "Fenyő"}}
	var s: Dictionary = I.sign_dict(d)
	print("azonosító: ", I.short_id())
	print("jó aláírás elfogadva: ", I.verify_dict(s))
	var t: Dictionary = s.duplicate(true)
	t["publikacio"]["x"] = 2.5
	print("megváltoztatott tartalom elutasítva: ", not I.verify_dict(t))
	var u: Dictionary = s.duplicate(true)
	u["alairas"]["azonosito"] = "AAAA-BBBB"
	print("hamis azonosító elutasítva: ", not I.verify_dict(u))
	print("JSON-mentés után is jó: ", I.verify_dict(JSON.parse_string(JSON.stringify(s))))
	print("aláírás nélkül elutasítva: ", not I.verify_dict(d))
	quit()
