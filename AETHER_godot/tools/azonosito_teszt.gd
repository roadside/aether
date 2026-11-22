## Az aláírás (scripts/identity.gd) próbája: Godot --headless --path . -s tools/azonosito_teszt.gd
## Kiírja: OK, ha minden eset a vártat adja.
extends SceneTree
func _init():
	var I = load("res://scripts/identity.gd")
	var t0 = Time.get_ticks_msec()
	var d := {"publikacio": {"kerdes": "teszt", "x": 1.5}, "archivum": {"nev": "Fenyő"}}
	var s = I.sign_dict(d)
	print("ID ", I.short_id(), " ", Time.get_ticks_msec() - t0, " ms")
	print("OK1 ", I.verify_dict(s))
	var t = s.duplicate(true); t["publikacio"]["x"] = 2.5
	print("HAMIS_TARTALOM ", I.verify_dict(t))
	var u = s.duplicate(true); u["alairas"]["azonosito"] = "AAAA-BBBB"
	print("HAMIS_ID ", I.verify_dict(u))
	# JSON-oda-vissza (mentés/beolvasás után is ellenőrizhető legyen)
	var back = JSON.parse_string(JSON.stringify(s))
	print("JSON_UTAN ", I.verify_dict(back))
	print("NINCS ", I.verify_dict(d))

	var d := {"a": 1, "b": [2, 3.0], "c": {"ev": 2026}}
	var s = I.sign_dict(d)
	var back = JSON.parse_string(JSON.stringify(s))
	print("INT_JSON_UTAN ", I.verify_dict(back), " ", JSON.stringify(back["a"]))
	quit()
