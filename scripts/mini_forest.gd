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
var _shapes: Array = []       # az aktuális kép elemei


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
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


## A kép elemei: [fajta, adatok...]; minden körben más véletlen mag (játékszabály).
func _make_tile() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + round_i * 13
	_shapes.clear()
	var kind := str(QUIZ[round_i])
	match kind:
		"allando_mezogazdasag":
			var x0 := rng.randf_range(60.0, 160.0)
			var y0 := rng.randf_range(60.0, 160.0)
			for gx in 3:
				for gy in 3:
					if rng.randf() < 0.85:
						var col := Color("#c9b45a").lerp(Color("#9bc36a"), rng.randf())
						_shapes.append(["rect", Rect2(x0 + gx * 130.0, y0 + gy * 120.0, 122.0, 112.0), col])
			_shapes.append(["line", Vector2(x0 - 10.0, y0 + 3.0 * 120.0 + 6.0), Vector2(640.0, y0 + 3.0 * 120.0 + 6.0), Color("#8a6e4b"), 9.0])      # földút a táblák alatt, a kép széléig
		"tuz":
			var c := Vector2(rng.randf_range(260.0, 380.0), rng.randf_range(260.0, 380.0))
			for k in 26:
				var p := c + Vector2(rng.randf_range(-170.0, 170.0), rng.randf_range(-150.0, 150.0))
				_shapes.append(["blob", p, rng.randf_range(40.0, 90.0), Color("#2a2622")])
			for k in 14:
				var a := rng.randf() * TAU
				_shapes.append(["blob", c + Vector2(cos(a), sin(a)) * rng.randf_range(170.0, 220.0), rng.randf_range(14.0, 30.0), Color("#7a4a2a")])
		"fakitermeles":
			var y := rng.randf_range(280.0, 360.0)
			_shapes.append(["line", Vector2(0, y), Vector2(640, y + rng.randf_range(-40.0, 40.0)), Color("#b9a988"), 6.0])
			for k in 8:
				var x := 50.0 + k * 75.0 + rng.randf_range(-10.0, 10.0)
				var up := -1.0 if k % 2 == 0 else 1.0
				var e := Vector2(x + rng.randf_range(-40.0, 40.0), y + up * rng.randf_range(150.0, 240.0))
				_shapes.append(["line", Vector2(x, y), e, Color("#a59a7a"), 3.0])
				for s in 4:
					var p := Vector2(x, y).lerp(e, 0.25 + s * 0.2)
					_shapes.append(["blob", p + Vector2(rng.randf_range(-14.0, 14.0), 0), rng.randf_range(10.0, 18.0), Color("#7fa95e")])
		"banyaszat":
			var c := Vector2(rng.randf_range(260.0, 360.0), rng.randf_range(260.0, 360.0))
			for k in 6:
				_shapes.append(["blob", c, 200.0 - k * 30.0, Color("#8a6040").lerp(Color("#4a3426"), k / 5.0)])
			_shapes.append(["blob", c + Vector2(190, 150), 60.0, Color("#3f8a9a")])
			_shapes.append(["line", c + Vector2(150, -120), Vector2(640, 40), Color("#b9a988"), 6.0])
		"valtogato_muveles":
			for k in 14:
				var p := Vector2(rng.randf_range(60.0, 580.0), rng.randf_range(60.0, 580.0))
				var age := rng.randf()
				_shapes.append(["blob", p, rng.randf_range(18.0, 38.0), Color("#c9b45a").lerp(Color("#5d8a4a"), age)])
		"telepules":
			var x0 := rng.randf_range(80.0, 160.0)
			var y0 := rng.randf_range(80.0, 160.0)
			for gx in 7:
				_shapes.append(["line", Vector2(x0 + gx * 62.0, y0 - 20.0), Vector2(x0 + gx * 62.0, y0 + 400.0), Color("#c2c6cc"), 3.0])
			for gy in 7:
				_shapes.append(["line", Vector2(x0 - 20.0, y0 + gy * 62.0), Vector2(x0 + 400.0, y0 + gy * 62.0), Color("#c2c6cc"), 3.0])
			for gx in 6:
				for gy in 6:
					for h in 2:
						_shapes.append(["rect", Rect2(x0 + gx * 62.0 + 8.0 + h * 24.0, y0 + gy * 62.0 + 10.0 + rng.randf_range(0.0, 20.0), 18.0, 16.0), Color("#d9d2c4").lerp(Color("#a8504a"), rng.randf() * 0.6)])


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, W, H), Color("#0b1324"))
	if done_t < 0.0:
		_draw_tile()
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


func _draw_tile() -> void:
	var r := TILE
	draw_rect(r, Color("#1f3d24"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 260:      # fák lombja felülről
		var p := r.position + Vector2(20.0 + rng.randf() * (r.size.x - 40.0), 20.0 + rng.randf() * (r.size.y - 40.0))
		draw_circle(p, rng.randf_range(8.0, 20.0), Color("#2c5a30").lerp(Color("#3f7a3c"), rng.randf()))
	for s in _shapes:
		match str(s[0]):
			"rect":
				var rr: Rect2 = s[1]
				draw_rect(Rect2(r.position + rr.position, rr.size).intersection(r), s[2])
			"line":
				draw_line(r.position + (s[1] as Vector2).clamp(Vector2.ZERO, r.size), r.position + (s[2] as Vector2).clamp(Vector2.ZERO, r.size), s[3], float(s[4]))
			"blob":
				var p: Vector2 = r.position + s[1]
				var rad: float = s[2]
				if r.grow(-4.0).has_point(p):
					draw_circle(p, minf(rad, minf(p.x - r.position.x, r.end.x - p.x)), s[3])
	draw_rect(r, Color(UI.CYAN, 0.6), false, 2.0)
	var font := get_theme_default_font()
	if _answer != "":      # visszajelzés a képen
		var ok_ans := _answer == str(QUIZ[round_i])
		draw_rect(r, Color(UI.GREEN if ok_ans else UI.EMBER, 0.9), false, 6.0)
