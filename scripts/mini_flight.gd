extends Control
## Minijáték: Kondenzcsík-kerülő. A játékos egy repülőgépet vezet, és a fel/le nyíllal kikerüli a párás,
## hideg légrétegeket, ahol a kondenzcsík nem tűnik el, hanem fátyolfelhővé terül szét.
## A végén a repülés valódi melegítő összetevői (Lee és mtsai 2021) és egy valódi kitérítési vizsgálat
## (Teoh és mtsai 2020) számai jelennek meg (adatok/repules_lee2021.json, a forrás a fájlban).
## Játékszabály: a légrétegek helye, a repülések száma és hossza kitalált; a csíkok alakja jelkép.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const LEVELS := 5
const LY0 := 270.0            # a legmagasabb repülési szint képernyő-magassága
const LSTEP := 105.0
const X0 := 90.0
const X1 := 1510.0
const FLIGHT_SECONDS := 10.0  # játékszabály: egy repülés hossza
const FLIGHTS := 3            # játékszabály
const START_LEVEL := 2
const ALT_KM := [12.0, 11.5, 11.0, 10.5, 10.0]   # jelkép: utazómagasságok, nem mért légrétegek

var data_path := "res://adatok/repules_lee2021.json"
var auto := false             # próbafutás: magától kitér
var done_t := -1.0            # a befejezés óta eltelt idő; < 0 = még tart
var parts: Array = []         # [{name, erf}]
var net := 0.0
var non_co2 := 0.0
var growth := 0.0
var teoh := {}
var source := ""
var source2 := ""
var flight := 0
var level := START_LEVEL
var changes := 0
var in_patch := 0.0           # a játékos útja párás rétegben (képpont)
var baseline := 0.0           # ennyi lett volna, ha egyenesen repül
var _ft := 0.0                # az aktuális repülés ideje
var _py := 0.0
var _patches: Array = []      # [szint, x0, x1]
var _trail: Array = []        # [x, y, tartós, születés]
var _t := 0.0
var _prev_x := X0
var _info: Label
var _read: Label
var _end: VBoxContainer
var _clouds: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 14:
		_clouds.append([rng.randf_range(0.0, W), rng.randf_range(760.0, 840.0), rng.randf_range(40.0, 110.0)])
	var title := UI.heading(L.t("Kondenzcsík-kerülő"), 34)
	title.position = Vector2(60, 28)
	add_child(title)
	_info = UI.label(L.t("Fel és le nyíllal válts magasságot! A kék, párás rétegben a csík nem tűnik el, hanem felhővé terül, és melegít."), 18, UI.SOFT)
	_info.position = Vector2(60, 84)
	_info.size = Vector2(900, 60)
	add_child(_info)
	_read = UI.label("", 20, UI.CYAN, true, false)
	_read.position = Vector2(1060, 40)
	add_child(_read)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(60, 560)
	_end.size = Vector2(1480, 300)
	_end.visible = false
	add_child(_end)
	_start_flight()
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	var en := L.is_en()
	source = str(j.get("forras_en" if en else "forras", ""))
	net = float(j.get("netto", 0.0))
	non_co2 = float(j.get("nem_co2_arany", 0.0))
	growth = float(j.get("co2_novekedes_1960_2018", 0.0))
	for p in j.get("osszetevok", []):
		parts.append({"name": str(p["en"] if en else p["hu"]), "erf": float(p["erf"]), "id": str(p["id"])})
	var k: Variant = j.get("kiteres", {})
	if typeof(k) == TYPE_DICTIONARY:
		teoh = k
		source2 = str(k.get("forras_en" if en else "forras", ""))


func ok() -> bool:
	return parts.size() >= 4 and net > 0.0 and not teoh.is_empty()


func _ly(l: float) -> float:
	return LY0 + l * LSTEP


## Játékszabály: a párás rétegek helye minden repülésnél más (rögzített véletlen mag).
func _start_flight() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + flight * 17
	_patches.clear()
	var x := 260.0
	var k := 0
	while x < X1 - 120.0:
		var w := rng.randf_range(170.0, 330.0)
		var lv := START_LEVEL if k % 2 == 0 else rng.randi_range(0, LEVELS - 1)   # az egyenes út mindig belefut néhányba
		_patches.append([lv, x, minf(x + w, X1)])
		if rng.randf() < 0.5:      # néha két szomszédos réteg is párás
			var lv2 := clampi(lv + (1 if rng.randf() < 0.5 else -1), 0, LEVELS - 1)
			_patches.append([lv2, x + w * 0.3, minf(x + w * 1.2, X1)])
		x += w + rng.randf_range(120.0, 260.0)
		k += 1
	for p in _patches:
		if int(p[0]) == START_LEVEL:
			baseline += float(p[2]) - float(p[1])
	level = START_LEVEL
	_py = _ly(level)
	_ft = 0.0
	_prev_x = X0
	_update_read()


func _patch_at(l: int, x: float) -> bool:
	for p in _patches:
		if int(p[0]) == l and x >= float(p[1]) and x <= float(p[2]):
			return true
	return false


func _move(d: int) -> void:
	var n := clampi(level + d, 0, LEVELS - 1)
	if n != level:
		level = n
		changes += 1


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			finished.emit(done_t >= 0.0)
		elif done_t < 0.0 and event.keycode in [KEY_UP, KEY_W]:
			get_viewport().set_input_as_handled()
			_move(-1)
		elif done_t < 0.0 and event.keycode in [KEY_DOWN, KEY_S]:
			get_viewport().set_input_as_handled()
			_move(1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if done_t < 0.0:
			_move(-1 if event.position.y < _py else 1)


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
		queue_redraw()
		return
	if auto:
		_auto_step()
	_ft += delta
	var x := _plane_x()
	_py = move_toward(_py, _ly(level), delta * 260.0)
	var lv_now := int(round((_py - LY0) / LSTEP))
	var wet := absf(_py - _ly(lv_now)) < 30.0 and _patch_at(lv_now, x)
	if wet:
		in_patch += x - _prev_x
	_prev_x = x
	if _trail.is_empty() or x - float(_trail[-1][0]) > 9.0:
		_trail.append([x - 30.0, _py + 6.0, wet, _t])
	_update_read()
	if _ft >= FLIGHT_SECONDS:
		flight += 1
		if flight >= FLIGHTS:
			_finish()
		else:
			_trail = _trail.filter(func(tr: Array) -> bool: return bool(tr[2]))
			_start_flight()
	queue_redraw()


func _plane_x() -> float:
	return lerpf(X0, X1, clampf(_ft / FLIGHT_SECONDS, 0.0, 1.0))


## A próbafutás: ha előttünk párás réteg van, a legközelebbi száraz szintre vált.
func _auto_step() -> void:
	var x := _plane_x()
	var ahead := false
	for dx in [40.0, 120.0, 220.0]:
		if _patch_at(level, x + dx):
			ahead = true
	if not ahead:
		return
	for d in [1, -1, 2, -2]:
		var n: int = level + d
		if n < 0 or n >= LEVELS:
			continue
		var dry := true
		for dx in [0.0, 120.0, 260.0]:
			if _patch_at(n, x + dx):
				dry = false
		if dry:
			_move(signi(d))
			return


func _update_read() -> void:
	_read.text = L.t("Repülés: %d / %d    Magasságváltás: %d") % [mini(flight + 1, FLIGHTS), FLIGHTS, changes]


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_info.visible = false
	_read.visible = false
	var share := 100.0 * in_patch / maxf(baseline, 1.0)
	_end.visible = true
	_end.add_child(UI.label(L.t("A kitéréseiddel %s%%-kal kevesebb tartós kondenzcsíkot húztál, mint ha egyenesen repültél volna.") % L.num(clampf(100.0 - share, 0.0, 100.0), 0), 20, UI.CYAN, true))
	_end.add_child(UI.label(L.t("A valóságban a légi közlekedés melegítő hatásának %s%%-a nem a CO2-kibocsátásból származik – ennek a legnagyobb részét a kondenzcsíkok adják.") % L.num(non_co2 * 100.0, 0), 19, UI.TEXT, true))
	_end.add_child(UI.label(L.t("Egy japán kutatás szerint %s%% járat útvonalának módosításával akár 59%%-kal is csökkenthetné a csíkok hatását, mindössze 0,014%%-kal több üzemanyagköltséggel.") % L.num(float(teoh.get("kiteritett_jaratok", 0.0)), 1), 19, UI.TEXT))
	_end.add_child(UI.label(L.t("Forrás: %s; %s") % [source, source2], 13, UI.MUTE))
	var b := UI.button(L.t("Tovább") + " →", true)
	b.pressed.connect(func() -> void: finished.emit(true))
	b.position = Vector2(1390, 30)
	add_child(b)


func _draw_plane(p: Vector2) -> void:
	var c := Color("#e8edf5")
	draw_colored_polygon(PackedVector2Array([p + Vector2(34, 0), p + Vector2(22, -6), p + Vector2(-30, -5), p + Vector2(-36, 0), p + Vector2(-30, 5), p + Vector2(22, 6)]), c)
	draw_colored_polygon(PackedVector2Array([p + Vector2(6, 0), p + Vector2(-8, 0), p + Vector2(-20, 22), p + Vector2(-12, 22)]), Color("#c9d1de"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(6, 0), p + Vector2(-8, 0), p + Vector2(-14, -14), p + Vector2(-8, -14)]), Color("#aeb8c8"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-26, -4), p + Vector2(-34, -4), p + Vector2(-40, -18), p + Vector2(-34, -18)]), Color("#aeb8c8"))
	draw_circle(p + Vector2(26, -2), 2.5, Color("#33476b"))


func _draw() -> void:
	var font := get_theme_default_font()
	# --- ég: sötétkéktől a látóhatár felé világosodik ---
	for i in 45:
		var f := i / 44.0
		draw_rect(Rect2(0, f * H, W, H / 44.0 + 1.0), Color("#0a1838").lerp(Color("#3f6aa0"), pow(f, 1.3)))
	for c in _clouds:      # felhőtakaró lent (jelkép)
		draw_circle(Vector2(fmod(float(c[0]) - _t * 12.0 + W * 2.0, W + 200.0) - 100.0, float(c[1])), float(c[2]), Color(1, 1, 1, 0.12))
	if done_t < 0.0:
		# repülési szintek
		for l in LEVELS:
			var y := _ly(l)
			draw_dashed_line(Vector2(X0 - 20.0, y), Vector2(X1 + 40.0, y), Color(1, 1, 1, 0.08), 1.0, 8.0)
			draw_string(font, Vector2(16, y + 5), L.num(float(ALT_KM[l]), 1) + " km", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.MUTE)
		# párás, hideg rétegek
		for p in _patches:
			var y := _ly(float(p[0]))
			var r := Rect2(float(p[1]), y - 34.0, float(p[2]) - float(p[1]), 68.0)
			draw_rect(r, Color(0.56, 0.88, 0.84, 0.24))
			draw_rect(r, Color(0.7, 0.95, 0.95, 0.45), false, 1.5)
			for s in 6:
				var sx := r.position.x + r.size.x * (s + 0.5) / 6.0
				draw_circle(Vector2(sx + sin(_t + s) * 6.0, y + cos(_t * 0.7 + s) * 8.0), 2.0, Color(0.85, 0.97, 1.0, 0.35))
		# cél
		draw_line(Vector2(X1 + 30.0, LY0 - 50.0), Vector2(X1 + 30.0, _ly(LEVELS - 1) + 50.0), Color(UI.GOLD, 0.5), 2.0)
	# --- csíkok: a tartós szétterül, a rövid gyorsan eltűnik ---
	for tr in _trail:
		var age := _t - float(tr[3])
		var p := Vector2(float(tr[0]), float(tr[1]))
		if bool(tr[2]):
			var r := minf(3.0 + age * 5.0, 26.0)
			draw_circle(p + Vector2(0, age * 1.5), r, Color(1, 1, 1, clampf(0.45 - age * 0.012, 0.18, 0.45)))
		elif age < 0.7:
			draw_circle(p, 2.5, Color(1, 1, 1, 0.6 * (1.0 - age / 0.7)))
	if done_t < 0.0:
		_draw_plane(Vector2(_plane_x(), _py))
		return
	# --- a vég: a repülés melegítő összetevői 2018-ban (valódi számok) ---
	var a := clampf(done_t / 1.2, 0.0, 1.0)
	draw_rect(Rect2(40, 150, 1520, 400), Color(0.043, 0.063, 0.114, 0.85 * a))
	draw_string(font, Vector2(70, 190), L.t("A repülés melegítő hatása 2018-ban (mW/m²)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UI.GOLD, a))
	var zx := 560.0
	var sc := 12.0
	var y0 := 222.0
	for i in parts.size():
		var p: Dictionary = parts[i]
		var v: float = p["erf"]
		var y := y0 + i * 44.0
		var col := UI.EMBER if v > 0.0 else UI.CYAN
		if str(p["id"]) == "csik":
			col = Color("#f2f4f8")
		draw_string(font, Vector2(70, y + 22), str(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, 470, 17, Color(UI.TEXT, a))
		var w := v * sc * a
		draw_rect(Rect2(zx + minf(w, 0.0), y + 4, absf(w), 26), Color(col, 0.85))
		draw_string(font, Vector2(zx + maxf(w, 0.0) + 10.0, y + 24), L.num(v, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UI.SOFT, a))
	draw_line(Vector2(zx, y0), Vector2(zx, y0 + parts.size() * 44.0), Color(UI.MUTE, a), 1.0)
	draw_string(font, Vector2(70, y0 + parts.size() * 44.0 + 24.0), L.t("Összesen: %s mW/m²") % L.num(net, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UI.GOLD, a))
