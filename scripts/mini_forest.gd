extends Control
## Minijáték: Erdőnyomozó. Műholdképszerű rajzokon a játékos kitalálja, mi tüntette el az erdőt
## (mezőgazdaság, fakitermelés, tűz, váltogató művelés, bánya, település). A végén a valódi világadat:
## a faborítás-vesztés okai évente 2001 és 2024 között (Global Forest Watch; adatok/erdovesztes_okai.json).
## Játékszabály: a képek kódból rajzolt jelképek (nem valódi felvételek), a körök száma és sorrendje kitalált.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const TILE := Rect2(80, 170, 640, 640)
const QUIZ := ["allando_mezogazdasag", "tuz", "fakitermeles", "banyaszat", "valtogato_muveles", "telepules", "allando_mezogazdasag", "tuz"]   # játékszabály
const COLORS := {"telepules": Color("#9aa4b5"), "banyaszat": Color("#b07a4a"), "egyeb_termeszeti": Color("#6f8f7a"), "valtogato_muveles": Color("#c9b45a"), "fakitermeles": Color("#5fb3a8"), "allando_mezogazdasag": Color("#e2a64b"), "tuz": Color("#ec8559")}
const HINTS := {
	"allando_mezogazdasag": "Egyenes szélű, nagy táblák: itt szántó, legelő vagy ültetvény lett az erdőből.",
	"tuz": "Szabálytalan, fekete folt, utak és táblák nélkül: tűz égette le.",
	"fakitermeles": "Halszálka-minta: egy főútról oldalutak ágaznak el, közben az erdő visszanő.",
	"banyaszat": "Teraszos gödör, mellette víztározó: bánya.",
	"valtogato_muveles": "Sok kis, szabálytalan irtás, a régebbiek már újra zöldülnek.",
	"telepules": "Sűrű utcák és házak: település nőtt az erdő helyén.",
}

var data_path := "res://adatok/erdovesztes_okai.json"
var auto := false             # próbafutás: mindig jól válaszol
var done_t := -1.0            # a befejezés óta eltelt idő; < 0 = még tart
var causes: Array = []        # [{id, name}]
var years: Array = []         # [év, 7 ok értéke Mha-ban]
var source := ""
var round_i := 0
var correct := 0
var _answer := ""             # az utolsó válasz (feedback alatt)
var _answer_t := -10.0
var _t := 0.0
var _auto_t := 0.0
var _next_btn: Button
var _info: Label
var _read: Label
var _hint: Label
var _buttons: VBoxContainer
var _end: VBoxContainer
var _tile: Control             # erre rajzoljuk a képet; levágja, ami kilóg
var _shapes: Array = []       # az aktuális kép elemei


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	_tile = Control.new()
	_tile.position = TILE.position
	_tile.size = TILE.size
	_tile.clip_contents = true
	_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile.draw.connect(_draw_tile)
	add_child(_tile)
	var title := UI.heading(L.t("Erdőnyomozó"), 34)
	title.position = Vector2(80, 28)
	add_child(title)
	_info = UI.label(L.t("Ez egy műholdkép egy erdőről. Mi tüntette el a fákat? Válaszd ki!"), 18, UI.SOFT)
	_info.position = Vector2(80, 84)
	_info.size = Vector2(900, 60)
	add_child(_info)
	_read = UI.label("", 20, UI.CYAN, true, false)
	_read.position = Vector2(800, 170)
	add_child(_read)
	_hint = UI.label("", 18, UI.GOLD, false)
	_hint.position = Vector2(800, 690)
	_hint.size = Vector2(720, 120)
	add_child(_hint)
	_buttons = UI.vbox(10)
	_buttons.position = Vector2(800, 220)
	add_child(_buttons)
	for c in causes:
		if str(c["id"]) == "egyeb_termeszeti":
			continue
		var b := UI.button(str(c["name"]), false)
		b.custom_minimum_size = Vector2(420, 0)
		var cid := str(c["id"])
		b.pressed.connect(func() -> void: _pick(cid))
		_buttons.add_child(b)
	_next_btn = UI.button(L.t("Tovább") + " →", true)
	_next_btn.position = Vector2(800, 800)
	_next_btn.visible = false
	_next_btn.pressed.connect(_next)
	add_child(_next_btn)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(1000, 170)
	_end.size = Vector2(540, 660)
	_end.visible = false
	add_child(_end)
	_make_tile()
	_update_read()
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	var en := L.is_en()
	source = str(j.get("forras_en" if en else "forras", ""))
	for c in j.get("okok", []):
		causes.append({"id": str(c["id"]), "name": str(c["en"] if en else c["hu"])})
	years = j.get("evek", [])


func ok() -> bool:
	return causes.size() == 7 and years.size() >= 20


func _update_read() -> void:
	_read.text = L.t("Kép: %d / %d    Jó válasz: %d") % [mini(round_i + 1, QUIZ.size()), QUIZ.size(), correct]


func _pick(id: String) -> void:
	if done_t >= 0.0 or _answer != "":
		return
	var right := str(QUIZ[round_i])
	if id == right:
		correct += 1
		_hint.text = L.t("Igen!") + " " + L.t(str(HINTS[right]))
	else:
		_hint.text = L.t("Nem egészen.") + " " + L.t(str(HINTS[right]))
	_answer = id
	_answer_t = _t
	_next_btn.visible = true
	for b in _buttons.get_children():
		(b as Button).disabled = true
	_update_read()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		finished.emit(done_t >= 0.0)
	elif event is InputEventKey and not event.echo and event.pressed and event.keycode in [KEY_SPACE, KEY_ENTER] and _answer != "" and done_t < 0.0:
		get_viewport().set_input_as_handled()
		_next()


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
	elif auto and _answer != "" and _t - _answer_t >= 1.6:
		_next()
	elif auto and _answer == "":
		_auto_t += delta
		if _auto_t >= 2.2:
			_auto_t = 0.0
			_pick(str(QUIZ[round_i]))
	_tile.queue_redraw()
	queue_redraw()


## A válasz és a magyarázat után a játékos lép tovább a következő képre.
func _next() -> void:
	if _answer == "" or done_t >= 0.0:
		return
	_answer = ""
	_hint.text = ""
	_next_btn.visible = false
	for b in _buttons.get_children():
		(b as Button).disabled = false
	round_i += 1
	if round_i >= QUIZ.size():
		_finish()
	else:
		_make_tile()
		_update_read()


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_tile.visible = false
	_info.visible = false
	_buttons.visible = false
	_hint.visible = false
	_read.text = L.t("Jó válasz: %d / %d") % [correct, QUIZ.size()]
	var sums: Array = []
	sums.resize(7)
	sums.fill(0.0)
	var total := 0.0
	for y in years:
		for i in 7:
			sums[i] = float(sums[i]) + float(y[i + 1])
			total += float(y[i + 1])
	var last: Array = years[-1]
	var ia := _idx("allando_mezogazdasag")
	var it := _idx("tuz")
	_end.visible = true
	_end.add_child(UI.label(L.t("A valóságban 2001 és %d között %s millió hektár faborítás tűnt el a Földön.") % [int(last[0]), L.num(total, 0)], 20, UI.CYAN, true))
	_end.add_child(UI.label(L.t("A legnagyobb ok az állandó mezőgazdaság (%s%%). Ez végleges: az erdő helyén szántó, legelő vagy ültetvény lesz.") % L.num(100.0 * float(sums[ia]) / total, 0), 18, UI.TEXT))
	_end.add_child(UI.label(L.t("Fakitermelés és váltogató művelés után gyakran visszanő az erdő."), 18, UI.TEXT))
	_end.add_child(UI.label(L.t("Az adatsor utolsó évében (%d) a tűz %s millió hektárt pusztított el, többet, mint bármelyik korábbi évben.") % [int(last[0]), L.num(float(last[it + 1]), 1)], 18, UI.EMBER, true))
	_end.add_child(UI.label(L.t("Forrás: %s") % source, 13, UI.MUTE))
	var b := UI.button(L.t("Tovább") + " →", true)
	b.pressed.connect(func() -> void: finished.emit(true))
	b.position = Vector2(1390, 30)
	add_child(b)


func _idx(id: String) -> int:
	for i in causes.size():
		if str(causes[i]["id"]) == id:
			return i
	return 0


## Zajos szélű folt a középpont körül (csillag alakú, ezért nem metszi önmagát).
func _noisy(c: Vector2, r: float, n: int, rng: RandomNumberGenerator, j: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r * rng.randf_range(1.0 - j, 1.0 + j))
	return pts


## A kép elemei: [fajta, adatok...]; minden körben más véletlen mag (játékszabály). A kép 640×640-es.
func _make_tile() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + round_i * 13
	_shapes.clear()
	var kind := str(QUIZ[round_i])
	var green := [Color("#2f6a34"), Color("#3f7f3c"), Color("#356f38")]
	match kind:
		"allando_mezogazdasag":
			var x0 := rng.randf_range(60.0, 100.0)
			var y0 := rng.randf_range(60.0, 100.0)
			var cw := [150.0, 132.0, 168.0]
			var rh := [132.0, 158.0, 150.0]
			var crops := [Color("#d6bc5c"), Color("#9cc766"), Color("#6aa24f"), Color("#93714c"), Color("#e2d25a"), Color("#b7cf74")]
			_shapes.append(["rect", Rect2(x0 - 16.0, y0 - 16.0, 498.0, 488.0), Color("#77704a")])      # letarolt föld a táblák körül
			var yard := Rect2()
			var cy := y0
			for gy in 3:
				var cx := x0
				for gx in 3:
					var cell := Rect2(cx, cy, cw[gx] - 8.0, rh[gy] - 8.0)
					if gx == 2 and gy == 2:
						yard = cell
					elif rng.randf() < 0.5 and cell.size.x > 120.0:      # kettéosztott tábla
						var half := cell.size.x * rng.randf_range(0.4, 0.6)
						_shapes.append(["field", Rect2(cell.position, Vector2(half - 3.0, cell.size.y)), crops[rng.randi() % crops.size()], true])
						_shapes.append(["field", Rect2(cell.position + Vector2(half + 3.0, 0), Vector2(cell.size.x - half - 3.0, cell.size.y)), crops[rng.randi() % crops.size()], false])
					else:
						_shapes.append(["field", cell, crops[rng.randi() % crops.size()], rng.randf() < 0.5])
					cx += cw[gx]
				cy += rh[gy]
			# --- tanya: udvar, lakóház, pajta, silók, bekötőút a kép széléig ---
			_shapes.append(["rect", yard, Color("#b39d6f")])
			var gate := yard.position + Vector2(yard.size.x, yard.size.y * 0.5)
			_shapes.append(["path", PackedVector2Array([yard.position + Vector2(20.0, yard.size.y * 0.5), gate, gate + Vector2(60.0, 10.0), Vector2(660.0, gate.y + 40.0)]), Color("#b9a070"), 11.0])
			_shapes.append(["path", PackedVector2Array([Vector2(x0 - 16.0, y0 + rh[0] - 4.0), Vector2(x0 + 482.0, y0 + rh[0] - 4.0)]), Color("#a8946a"), 5.0])
			_shapes.append(["path", PackedVector2Array([Vector2(x0 + cw[0] - 4.0, y0 - 16.0), Vector2(x0 + cw[0] - 4.0, y0 + 440.0)]), Color("#a8946a"), 5.0])
			_shapes.append(["house", Rect2(yard.position + Vector2(14.0, 14.0), Vector2(50.0, 30.0)), Color("#b04a3c")])
			_shapes.append(["house", Rect2(yard.position + Vector2(84.0, 12.0), Vector2(34.0, 62.0)), Color("#8a5a3e")])
			_shapes.append(["house", Rect2(yard.position + Vector2(16.0, 96.0), Vector2(30.0, 22.0)), Color("#9aa0a8")])
			for k in 3:
				_shapes.append(["silo", yard.position + Vector2(134.0, 22.0 + k * 24.0), 10.0])
			_shapes.append(["blob", yard.position + Vector2(70.0, 110.0), 15.0, Color("#3f8a9a")])      # itató
			for k in 8:      # tehenek az első táblán
				var cp := Vector2(x0 + rng.randf_range(14.0, cw[0] - 24.0), y0 + rng.randf_range(14.0, rh[0] - 24.0))
				_shapes.append(["blob", cp + Vector2(1.5, 2.0), 3.2, Color(0, 0, 0, 0.3)])
				_shapes.append(["blob", cp, 3.2, Color("#f2efe6") if k % 3 != 0 else Color("#5a4030")])
			_shapes.append(["rect", Rect2(gate + Vector2(22.0, -1.0), Vector2(16.0, 9.0)), Color("#2f6fb0")])      # teherautó a bekötőúton
			_shapes.append(["rect", Rect2(gate + Vector2(38.0, 0.0), Vector2(7.0, 7.0)), Color("#c9d1de")])
			_shapes.append(["tree", yard.position + Vector2(20.0, 66.0), 13.0, green[1]])
			_shapes.append(["tree", yard.position + Vector2(118.0, 104.0), 11.0, green[0]])
			for k in 46:      # az erdő széle belóg a táblák fölé
				var side := rng.randi() % 4
				var u := rng.randf_range(-20.0, 500.0)
				var p := Vector2(x0 + u, y0 - 20.0) if side == 0 else (Vector2(x0 + u, y0 + 474.0) if side == 1 else (Vector2(x0 - 20.0, y0 + u) if side == 2 else Vector2(x0 + 484.0, y0 + u)))
				if p.distance_to(gate + Vector2(40.0, 8.0)) > 50.0:
					_shapes.append(["tree", p + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0)), rng.randf_range(10.0, 17.0), green[rng.randi() % 3]])
		"tuz":
			var c := Vector2(rng.randf_range(270.0, 370.0), rng.randf_range(280.0, 370.0))
			_shapes.append(["poly", _noisy(c, 236.0, 30, rng, 0.2), Color("#4a3a26")])      # megperzselt perem
			_shapes.append(["poly", _noisy(c, 205.0, 30, rng, 0.24), Color("#1c1917")])
			for k in 12:
				var p := c + Vector2(rng.randf_range(-130.0, 130.0), rng.randf_range(-120.0, 120.0))
				_shapes.append(["poly", _noisy(p, rng.randf_range(24.0, 60.0), 10, rng, 0.3), Color("#3d3833") if k % 2 == 0 else Color("#2a2521")])
			for k in 150:      # elszenesedett törzsek
				var a := rng.randf() * TAU
				var p := c + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * 185.0
				_shapes.append(["blob", p, rng.randf_range(1.6, 3.2), Color("#0c0a09")])
			for k in 44:      # megbarnult, félig leégett fák a szélen
				var a := rng.randf() * TAU
				_shapes.append(["tree", c + Vector2(cos(a), sin(a)) * rng.randf_range(196.0, 246.0), rng.randf_range(9.0, 15.0), Color("#6d4a28").lerp(Color("#94642f"), rng.randf())])
			var a0 := rng.randf_range(-2.6, -0.6)      # a tűz frontja: itt még ég
			for k in 9:
				var a := a0 + (k - 4) * 0.11
				var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(196.0, 226.0)
				_shapes.append(["ember", p])
				if k % 2 == 0:
					_shapes.append(["smoke", p])
		"fakitermeles":
			var y := rng.randf_range(290.0, 350.0)
			var main := PackedVector2Array()
			for k in 9:
				main.append(Vector2(-20.0 + k * 85.0, y + sin(k * 1.3 + rng.randf()) * 16.0))
			for k in 8:
				var base: Vector2 = main[k].lerp(main[k + 1], 0.6)
				var up := -1.0 if k % 2 == 0 else 1.0
				var e := base + Vector2(rng.randf_range(-36.0, 36.0), up * rng.randf_range(170.0, 250.0))
				var age := rng.randf()      # 0 = friss vágás, 1 = régi, már visszanő
				for s in 3:
					var p := base.lerp(e, 0.36 + s * 0.3) + Vector2(rng.randf_range(-16.0, 16.0), 0)
					var rad := rng.randf_range(26.0, 40.0)
					_shapes.append(["poly", _noisy(p, rad, 10, rng, 0.22), Color("#a98d5f").lerp(Color("#5f8f49"), age)])
					for q in 9:
						var o := Vector2(rng.randf_range(-rad, rad), rng.randf_range(-rad, rad)) * 0.6
						if age < 0.45:
							_shapes.append(["blob", p + o, 2.2, Color("#5a4028")])      # tuskók
						else:
							_shapes.append(["tree", p + o, rng.randf_range(5.0, 8.0), Color("#7fb35e")])      # fiatal fák
				_shapes.append(["path", PackedVector2Array([base, base.lerp(e, 0.5) + Vector2(rng.randf_range(-10.0, 10.0), 0), e]), Color("#a59a7a"), 4.0])
			_shapes.append(["path", main, Color("#bba87f"), 10.0])
			var land: Vector2 = main[4] + Vector2(0, -34.0)      # rakodó a főút mellett
			_shapes.append(["poly", _noisy(land, 40.0, 10, rng, 0.15), Color("#a98d5f")])
			for k in 5:
				_shapes.append(["rect", Rect2(land + Vector2(-30.0, -22.0 + k * 6.0), Vector2(34.0, 4.0)), Color("#7a5230") if k % 2 == 0 else Color("#8f6238")])
			_shapes.append(["rect", Rect2(land + Vector2(10.0, 4.0), Vector2(24.0, 10.0)), Color("#e0b040")])      # rönkszállító
			_shapes.append(["rect", Rect2(land + Vector2(34.0, 5.0), Vector2(8.0, 8.0)), Color("#c9d1de")])
		"banyaszat":
			var c := Vector2(rng.randf_range(250.0, 310.0), rng.randf_range(270.0, 330.0))
			var noise: Array = []
			for i in 26:
				noise.append(rng.randf_range(0.86, 1.14))
			for k in 7:      # teraszok: egyre mélyebb, egyre sötétebb
				var pts := PackedVector2Array()
				var rad := 215.0 - k * 29.0
				for i in 26:
					var a := TAU * i / 26.0
					pts.append(c + Vector2(cos(a), sin(a) * 0.86) * rad * lerpf(float(noise[i]), 1.0, k / 8.0))
				_shapes.append(["poly", pts, Color("#b8935f").lerp(Color("#3a2a20"), k / 6.0) if k % 2 == 0 else Color("#a07c50").lerp(Color("#33241b"), k / 6.0)])
			_shapes.append(["blob", c + Vector2(4.0, 6.0), 26.0, Color("#2f7482")])      # víz a gödör alján
			var ramp := PackedVector2Array()
			for i in 34:      # csigavonalban felvezető út
				var a := -0.6 + i * 0.3
				ramp.append(c + Vector2(cos(a), sin(a) * 0.86) * (205.0 - i * 5.0))
			_shapes.append(["path", ramp, Color("#d6c096"), 4.0])
			for k in 4:      # dömperek a szállítóúton
				_shapes.append(["rect", Rect2(ramp[3 + k * 7] - Vector2(6.0, 4.0), Vector2(12.0, 8.0)), Color("#e8b62c")])
			var pond := c + Vector2(232.0, 190.0)
			_shapes.append(["poly", _noisy(pond, 82.0, 14, rng, 0.14), Color("#9c9079")])      # zagytározó gátja
			_shapes.append(["poly", _noisy(pond, 66.0, 14, rng, 0.12), Color("#4fa7b0")])
			_shapes.append(["poly", _noisy(pond + Vector2(-14.0, -10.0), 30.0, 10, rng, 0.2), Color("#7cc2c4")])
			for k in 3:      # meddőhányók
				var p := c + Vector2(-150.0 + k * 70.0, -236.0 + k * 12.0)
				_shapes.append(["poly", _noisy(p, 44.0, 10, rng, 0.2), Color("#9a8868")])
				_shapes.append(["poly", _noisy(p + Vector2(-5.0, -5.0), 24.0, 9, rng, 0.2), Color("#b7a684")])
			var out := c + Vector2(190.0, -110.0)
			_shapes.append(["path", PackedVector2Array([out, out + Vector2(80.0, -50.0), Vector2(660.0, 30.0)]), Color("#bba87f"), 10.0])
			_shapes.append(["house", Rect2(out + Vector2(30.0, 6.0), Vector2(46.0, 26.0)), Color("#8e949c")])
			_shapes.append(["house", Rect2(out + Vector2(86.0, -6.0), Vector2(26.0, 40.0)), Color("#737a84")])
			_shapes.append(["silo", out + Vector2(52.0, 52.0), 11.0])
			_shapes.append(["silo", out + Vector2(78.0, 56.0), 9.0])
		"valtogato_muveles":
			var spots: Array = []
			for k in 15:
				var p := Vector2(rng.randf_range(70.0, 570.0), rng.randf_range(70.0, 570.0))
				spots.append(p)
			spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
			for k in spots.size() - 1:      # gyalogösvények az irtások között
				var a: Vector2 = spots[k]
				var b: Vector2 = spots[k + 1]
				if a.distance_to(b) < 240.0:
					_shapes.append(["path", PackedVector2Array([a, a.lerp(b, 0.5) + Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-24.0, 24.0)), b]), Color("#8f8058"), 2.0])
			for p in spots:
				var age := rng.randf()      # 0 = most égetett irtás, 1 = régi, újra zöldül
				var rad := rng.randf_range(24.0, 44.0)
				_shapes.append(["poly", _noisy(p, rad, 9, rng, 0.3), Color("#c9ae5c").lerp(Color("#4f8544"), age)])
				if age < 0.35:
					_shapes.append(["poly", _noisy(p + Vector2(rad * 0.2, 0), rad * 0.5, 8, rng, 0.3), Color("#8a6a48")])      # frissen feltört föld
					_shapes.append(["house", Rect2(p + Vector2(-rad * 0.5, -rad * 0.4), Vector2(13.0, 10.0)), Color("#a57a3a")])      # kunyhó
					for q in 5:
						_shapes.append(["blob", p + Vector2(rng.randf_range(-rad, rad), rng.randf_range(-rad, rad)) * 0.6, 2.0, Color("#4a3524")])
				elif age > 0.6:
					for q in 7:
						_shapes.append(["tree", p + Vector2(rng.randf_range(-rad, rad), rng.randf_range(-rad, rad)) * 0.7, rng.randf_range(5.0, 9.0), Color("#6fa955")])
		"telepules":
			var x0 := rng.randf_range(70.0, 110.0)
			var y0 := rng.randf_range(70.0, 110.0)
			var bs := 74.0
			var roofs := [Color("#b0503f"), Color("#8a5a40"), Color("#8e949c"), Color("#c26a45"), Color("#a14a44")]
			var park := Vector2i(rng.randi_range(1, 4), rng.randi_range(1, 4))
			var school := Vector2i((park.x + 2) % 6, (park.y + 3) % 6)
			_shapes.append(["poly", _noisy(Vector2(x0 + bs * 3.0, y0 + bs * 3.0), bs * 3.5, 22, rng, 0.1), Color("#6f7f5a")])      # kiirtott, beépített terület
			for gx in 6:
				for gy in 6:
					var edge := gx == 0 or gy == 0 or gx == 5 or gy == 5
					if edge and rng.randf() < 0.3:
						continue      # a város széle egyenetlenül nő
					var b := Rect2(x0 + gx * bs + 5.0, y0 + gy * bs + 5.0, bs - 10.0, bs - 10.0)
					if Vector2i(gx, gy) == park:
						_shapes.append(["rect", b, Color("#4f9049")])
						_shapes.append(["blob", b.get_center() + Vector2(8.0, 6.0), 12.0, Color("#3f8a9a")])
						for q in 6:
							_shapes.append(["tree", b.position + Vector2(rng.randf_range(8.0, 56.0), rng.randf_range(8.0, 56.0)), rng.randf_range(6.0, 9.0), green[rng.randi() % 3]])
						continue
					_shapes.append(["rect", b, Color("#8fa06e").lerp(Color("#a59a84"), rng.randf())])      # kertek, udvarok
					if Vector2i(gx, gy) == school:
						_shapes.append(["house", Rect2(b.position + Vector2(8.0, 10.0), Vector2(48.0, 28.0)), Color("#9aa0a8")])
						_shapes.append(["rect", Rect2(b.position + Vector2(10.0, 44.0), Vector2(40.0, 14.0)), Color("#b8ad90")])
						continue
					for h in 4:
						if rng.randf() < 0.85:
							var hp := b.position + Vector2(4.0 + (h % 2) * 31.0 + rng.randf_range(0.0, 5.0), 4.0 + (h / 2) * 31.0 + rng.randf_range(0.0, 5.0))
							var sz := Vector2(22.0, 15.0) if rng.randf() < 0.5 else Vector2(15.0, 22.0)
							_shapes.append(["house", Rect2(hp, sz), roofs[rng.randi() % roofs.size()]])
					if rng.randf() < 0.6:
						_shapes.append(["tree", b.position + Vector2(rng.randf_range(24.0, 40.0), rng.randf_range(24.0, 40.0)), rng.randf_range(5.0, 7.0), green[rng.randi() % 3]])
			for g in 7:      # utcák
				var w := 9.0 if g == 3 else 5.0
				_shapes.append(["path", PackedVector2Array([Vector2(x0 + g * bs, y0 - 6.0), Vector2(x0 + g * bs, y0 + 6.0 * bs + 6.0)]), Color("#b4b9c0"), w])
				_shapes.append(["path", PackedVector2Array([Vector2(x0 - 6.0, y0 + g * bs), Vector2(x0 + 6.0 * bs + 6.0, y0 + g * bs)]), Color("#b4b9c0"), w])
			_shapes.append(["path", PackedVector2Array([Vector2(x0 + 3.0 * bs, y0 + 6.0 * bs), Vector2(x0 + 3.0 * bs + 20.0, 660.0)]), Color("#b4b9c0"), 9.0])      # országút kifelé
			var cars := [Color("#e8e8e8"), Color("#c0392b"), Color("#2f6fb0"), Color("#e0b030")]
			for k in 9:      # autók az utcákon
				if k % 2 == 0:
					_shapes.append(["rect", Rect2(Vector2(x0 + 3.0 * bs - 2.5, y0 + rng.randf_range(10.0, 6.0 * bs - 16.0)), Vector2(5.0, 9.0)), cars[k % 4]])
				else:
					_shapes.append(["rect", Rect2(Vector2(x0 + rng.randf_range(10.0, 6.0 * bs - 16.0), y0 + 3.0 * bs - 2.5), Vector2(9.0, 5.0)), cars[k % 4]])
			_shapes.append(["path", PackedVector2Array([Vector2(x0 + 6.0 * bs, y0 + 3.0 * bs), Vector2(660.0, y0 + 3.0 * bs - 30.0)]), Color("#b4b9c0"), 9.0])


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, W, H), Color("#0b1324"))
	if done_t < 0.0:
		return
	# --- a vég: a faborítás-vesztés okai évente (valódi adat), egymásra rakott oszlopok ---
	var a := clampf(done_t / 1.0, 0.0, 1.0)
	var x0 := 120.0
	var y0 := 780.0
	var bw := 30.0
	var sc := 16.0        # képpont / millió hektár
	draw_string(font, Vector2(80, 190), L.t("Faborítás-vesztés okai évente (millió hektár)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UI.GOLD, a))
	for i in years.size():
		var y: Array = years[i]
		var h := 0.0
		for k in 7:
			var v := float(y[k + 1]) * sc * a
			var col: Color = COLORS.get(str(causes[k]["id"]), UI.MUTE)
			draw_rect(Rect2(x0 + i * (bw + 4.0), y0 - h - v, bw, v), col)
			h += v
		if int(y[0]) % 5 == 0 or i == years.size() - 1:
			draw_string(font, Vector2(x0 + i * (bw + 4.0) - 6.0, y0 + 20.0), str(int(y[0])), HORIZONTAL_ALIGNMENT_CENTER, 44, 12, UI.MUTE)
	for v in [10.0, 20.0, 30.0]:
		draw_line(Vector2(x0 - 6.0, y0 - v * sc), Vector2(x0 + years.size() * (bw + 4.0), y0 - v * sc), Color(UI.MUTE, 0.2), 1.0)
		draw_string(font, Vector2(x0 - 44.0, y0 - v * sc + 5.0), L.num(v, 0), HORIZONTAL_ALIGNMENT_RIGHT, 36, 12, UI.MUTE)
	var ly := 230.0
	draw_rect(Rect2(x0 - 8.0, ly - 8.0, 350.0, 166.0), Color(0.043, 0.075, 0.141, 0.92 * a))
	for k in range(6, -1, -1):      # jelmagyarázat felülről lefelé, ahogy az oszlopban
		var col: Color = COLORS.get(str(causes[k]["id"]), UI.MUTE)
		draw_rect(Rect2(x0, ly, 16, 16), Color(col, a))
		draw_string(font, Vector2(x0 + 24.0, ly + 14.0), str(causes[k]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UI.SOFT, a))
		ly += 22.0


## Egy fa lombja felülről: árnyék, lomb, fényes folt.
func _tree(p: Vector2, rad: float, col: Color) -> void:
	_tile.draw_circle(p + Vector2(rad * 0.28, rad * 0.34), rad, Color(0.02, 0.07, 0.03, 0.42))
	_tile.draw_circle(p, rad, col)
	_tile.draw_circle(p - Vector2(rad * 0.26, rad * 0.28), rad * 0.52, col.lightened(0.14))


## A kép: a _tile gyerekcsomópontra rajzolunk (levágja, ami kilóg), 640×640-es saját koordinátákkal.
func _draw_tile() -> void:
	var sz := TILE.size
	_tile.draw_rect(Rect2(Vector2.ZERO, sz), Color("#173120"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 60:      # az erdő talaja: sötétebb és világosabb foltok
		_tile.draw_circle(Vector2(rng.randf() * sz.x, rng.randf() * sz.y), rng.randf_range(30.0, 70.0), Color("#1d3c26") if k % 2 == 0 else Color("#142b1c"))
	for k in 520:      # fák lombja felülről
		var p := Vector2(rng.randf() * sz.x, rng.randf() * sz.y)
		_tree(p, rng.randf_range(9.0, 19.0), Color("#27562d").lerp(Color("#3f7f3c"), rng.randf()))
	for s in _shapes:
		match str(s[0]):
			"rect":
				_tile.draw_rect(s[1], s[2])
			"poly":
				_tile.draw_colored_polygon(s[1], s[2])
			"field":      # tábla, sorokba vetve
				var fr: Rect2 = s[1]
				var fc: Color = s[2]
				_tile.draw_rect(fr, fc)
				var dark := fc.darkened(0.13)
				if bool(s[3]):
					var x := fr.position.x + 3.0
					while x < fr.end.x - 1.0:
						_tile.draw_line(Vector2(x, fr.position.y + 2.0), Vector2(x, fr.end.y - 2.0), dark, 2.0)
						x += 7.0
				else:
					var y := fr.position.y + 3.0
					while y < fr.end.y - 1.0:
						_tile.draw_line(Vector2(fr.position.x + 2.0, y), Vector2(fr.end.x - 2.0, y), dark, 2.0)
						y += 7.0
				_tile.draw_rect(fr, fc.darkened(0.3), false, 1.5)
			"line":
				_tile.draw_line(s[1], s[2], s[3], float(s[4]))
			"path":
				var pp: PackedVector2Array = s[1]
				var pc: Color = s[2]
				_tile.draw_polyline(pp, pc.darkened(0.35), float(s[3]) + 2.5)
				_tile.draw_polyline(pp, pc, float(s[3]))
				for q in pp:
					_tile.draw_circle(q, float(s[3]) * 0.5, pc)
			"blob":
				_tile.draw_circle(s[1], float(s[2]), s[3])
			"tree":
				_tree(s[1], float(s[2]), s[3])
			"house":      # nyeregtető felülről: árnyék, két tetősík, gerinc
				var hr: Rect2 = s[1]
				var hc: Color = s[2]
				_tile.draw_rect(Rect2(hr.position + Vector2(4.0, 5.0), hr.size), Color(0, 0, 0, 0.38))
				_tile.draw_rect(hr, hc.darkened(0.16))
				if hr.size.x >= hr.size.y:
					_tile.draw_rect(Rect2(hr.position, Vector2(hr.size.x, hr.size.y * 0.5)), hc.lightened(0.12))
					_tile.draw_line(hr.position + Vector2(0, hr.size.y * 0.5), hr.position + Vector2(hr.size.x, hr.size.y * 0.5), hc.darkened(0.4), 1.5)
				else:
					_tile.draw_rect(Rect2(hr.position, Vector2(hr.size.x * 0.5, hr.size.y)), hc.lightened(0.12))
					_tile.draw_line(hr.position + Vector2(hr.size.x * 0.5, 0), hr.position + Vector2(hr.size.x * 0.5, hr.size.y), hc.darkened(0.4), 1.5)
			"silo":
				var sp: Vector2 = s[1]
				var sr := float(s[2])
				_tile.draw_circle(sp + Vector2(4.0, 5.0), sr, Color(0, 0, 0, 0.38))
				_tile.draw_circle(sp, sr, Color("#c2c7ce"))
				_tile.draw_circle(sp - Vector2(sr * 0.25, sr * 0.25), sr * 0.5, Color("#e3e7ec"))
			"ember":
				var ep: Vector2 = s[1]
				var fl := 0.6 + 0.4 * sin(_t * 7.0 + ep.x)
				_tile.draw_circle(ep, 13.0, Color(1.0, 0.45, 0.1, 0.22 * fl))
				_tile.draw_circle(ep, 6.0, Color(1.0, 0.55, 0.15, 0.9))
				_tile.draw_circle(ep, 3.0, Color(1.0, 0.85, 0.4, fl))
			"smoke":
				var mp: Vector2 = s[1]
				for i in 6:
					var u := fmod(_t * 0.16 + i / 6.0 + mp.x * 0.01, 1.0)
					_tile.draw_circle(mp + Vector2(90.0, -70.0) * u + Vector2(sin(_t + i) * 6.0, 0), 10.0 + 38.0 * u, Color(0.78, 0.78, 0.76, 0.2 * (1.0 - u)))
	if _answer != "":      # visszajelzés a képen
		var ok_ans := _answer == str(QUIZ[round_i])
		_tile.draw_rect(Rect2(Vector2(3, 3), sz - Vector2(6, 6)), Color(UI.GREEN if ok_ans else UI.EMBER, 0.9), false, 6.0)
	else:
		_tile.draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(UI.CYAN, 0.6), false, 2.0)
