extends Control
## Minijáték: Jégfurat. A játékos lefúr az antarktiszi jégbe, és közben kirajzolódik a levegő CO2-tartalma
## az elmúlt 800 ezer évben. A görbe minden pontja valódi mérés (adatok/jegfurat_co2.json, a forrás a fájlban).
## Játékszabály: a fúró melegedése és a beragadás (a valódi fúrásnál is lassan, szakaszosan haladnak, de a számok itt kitaláltak).
## A függőleges tengely az idő (ezer éve), nem a mélység méterben: a mélység–kor összefüggést nem találjuk ki.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const TOP := 250.0            # a hó felszíne = ma
const BOTTOM := 850.0         # a furat alja = a legrégebbi minta
const DRILL_SECONDS := 34.0   # ennyi fúrás kell a teljes mélységhez
const HEAT_UP := 5.5          # ennyi másodperc folyamatos fúrás után forrósodik fel
const COOL := 2.6
const STUCK := 2.4
const PPM_MIN := 150.0
const PPM_MAX := 450.0
const GX0 := 900.0
const GX1 := 1520.0

var pts: Array = []           # [kor (év), ppm], a legfiatalabbtól a legöregebbig; csak az ipar előtti jégminták
var today := 0.0              # a legfrissebb mért érték
var today_year := 0
var source := ""
var oldest := 800000.0
var pre_min := 0.0
var pre_max := 0.0
var depth := 0.0              # 0..1
var heat := 0.0
var stuck := 0.0
var done_t := -1.0            # a befejezés óta eltelt idő
var auto := false             # próbafutás: magától fúr
var _t := 0.0
var _hold := false
var _info: Label
var _read: Label
var _end: VBoxContainer
var eras: Array = []          # megállók: mi volt akkor a Földön (adatok/jegfurat_korok.json, forrással)
var _auto_rest := false
var _era := -1                # a most mutatott megálló
var _era_next := 0            # a következő, még nem mutatott megálló (a jelentől a múlt felé)
var _era_on := false          # ennél a megállásnál van-e mit mutatni
var _was_resting := false
var _era_a := 0.0
var _era_box: VBoxContainer
var _era_text: Label
var _era_src: Label
var _era_age: Label
var _bubbles: Array = []
var _stars: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 150:
		_bubbles.append([rng.randf_range(40.0, 800.0), rng.randf_range(TOP + 14.0, H), rng.randf_range(0.8, 2.6), rng.randf()])
	for i in 90:
		_stars.append([rng.randf_range(0.0, 840.0), rng.randf_range(0.0, 170.0), rng.randf_range(0.5, 1.5), rng.randf() * TAU])
	var title := UI.heading(L.t("Jégfurat"), 34)
	title.position = Vector2(900, 36)
	add_child(title)
	_info = UI.label(L.t("Tartsd lenyomva a szóközt, és fúrj le a jégbe! Ha a fúró felforrósodik, engedd el."), 19, UI.SOFT)
	_info.position = Vector2(900, 92)
	_info.size = Vector2(640, 60)
	add_child(_info)
	_read = UI.label("", 24, UI.CYAN, true, false)
	_read.position = Vector2(900, 168)
	add_child(_read)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_era_box = UI.vbox(4)
	_era_box.position = Vector2(176, 18)
	_era_box.size = Vector2(620, 150)
	_era_box.modulate.a = 0.0
	_era_age = UI.label("", 20, UI.GOLD, true, false)
	_era_text = UI.label("", 18, UI.TEXT)
	_era_src = UI.label("", 12, UI.MUTE)
	for l in [_era_age, _era_text, _era_src]:
		l.custom_minimum_size.x = 600
		_era_box.add_child(l)
	add_child(_era_box)
	var je: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://adatok/jegfurat_korok.json"))
	if typeof(je) == TYPE_DICTIONARY:
		eras = je.get("korok", [])
	_end = UI.vbox(4)
	_end.position = Vector2(900, 84)
	_end.size = Vector2(640, 110)
	_end.visible = false
	add_child(_end)
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://adatok/jegfurat_co2.json"))
	if typeof(j) != TYPE_DICTIONARY:
		return
	source = str(j.get("forras", ""))
	var all: Array = j.get("pontok", [])
	var last_year := -1e9
	for p in all:
		var y := float(p[0])
		var v := float(p[1])
		if y > last_year:
			last_year = y
			today = v
			today_year = int(y)
	pre_min = 1e9
	pre_max = 0.0
	for p in all:
		if float(p[0]) < 1750.0:
			pts.append([last_year - float(p[0]), float(p[1])])
			pre_min = minf(pre_min, float(p[1]))
			pre_max = maxf(pre_max, float(p[1]))
	pts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if not pts.is_empty():
		oldest = float(pts[-1][0])
	var k: Variant = j.get("kulcs", {})      # a nyers adatsor szélső értékei (a pontok 4000 éves átlagok)
	if typeof(k) == TYPE_DICTIONARY:
		pre_min = float(k.get("jegkorszak_min", pre_min))
		pre_max = float(k.get("ipar_elotti_max", pre_max))
	if L.is_en():
		source = str(j.get("forras_en", source))


func ok() -> bool:
	return pts.size() > 10


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_ESCAPE and event.pressed:
			get_viewport().set_input_as_handled()
			finished.emit(done_t >= 0.0)
		elif event.keycode in [KEY_SPACE, KEY_ENTER]:
			_hold = event.pressed
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hold = event.pressed
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	if auto:      # a próbafutás is megáll hűlni, hogy a megállók látsszanak
		if heat >= 0.8:
			_auto_rest = true
		elif heat <= 0.05:
			_auto_rest = false
	if done_t >= 0.0:
		done_t += delta
	elif stuck > 0.0:
		stuck -= delta
		heat = maxf(0.0, heat - delta / (STUCK * 1.2))
	elif _hold or auto and not _auto_rest:
		depth = minf(1.0, depth + delta / DRILL_SECONDS)
		heat += delta / HEAT_UP
		if heat >= 1.0:
			stuck = STUCK
		if depth >= 1.0:
			_finish()
	else:
		heat = maxf(0.0, heat - delta / COOL)
	# megálláskor (hűl vagy beragadt a fúró) megjelenik, mi volt akkor a Földön. Minden megálló új szöveget ad,
	# a jelentől a múlt felé haladva: mindig a következő, még nem látott kor jön, ha a fúró már átért rajta.
	var resting := done_t < 0.0 and depth > 0.0 and (stuck > 0.0 or not (_hold or auto and not _auto_rest))
	if resting and not _was_resting:
		_era_on = false
		if _era_next < eras.size() and float(eras[_era_next]["ezer_eve"]) * 1000.0 <= depth * oldest:
			_era = _era_next
			_era_next += 1
			_era_on = true
			var e: Dictionary = eras[_era]
			_era_age.text = L.t("%s ezer éve") % L.num(float(e["ezer_eve"]), 1 if fmod(float(e["ezer_eve"]), 1.0) > 0.0 else 0)
			_era_text.text = str(e["en"] if L.is_en() else e["hu"])
			_era_src.text = str(e["forras"])
	_was_resting = resting
	_era_a = move_toward(_era_a, 1.0 if resting and _era_on else 0.0, delta * 2.5)
	_era_box.modulate.a = _era_a
	if done_t < 0.0:
		var age := depth * oldest
		_read.text = L.t("%s ezer éve: %s ppm") % [L.num(age / 1000.0, 0), L.num(_ppm_at(age), 0)] if depth > 0.0 else ""
	queue_redraw()


func _finish() -> void:
	done_t = 0.0
	_info.visible = false
	_read.text = ""
	_end.visible = true
	_end.add_child(UI.label(L.t("800 ezer évig a levegő CO2-tartalma %s és %s ppm között maradt.") % [L.num(pre_min, 0), L.num(pre_max, 0)], 19, UI.TEXT, true))
	_end.add_child(UI.label(L.t("%d-ben: %s ppm volt.") % [today_year, L.num(today, 0)], 24, UI.EMBER, true))
	_end.add_child(UI.label(L.t("Forrás: %s") % source, 14, UI.MUTE))
	var b := UI.button(L.t("Tovább") + " →", true)
	b.pressed.connect(func() -> void: finished.emit(true))
	b.position = Vector2(1390, 30)
	add_child(b)


## Egyszerű rajz a megállóhoz (jelkép, nem valódi személy vagy fénykép).
func _draw_era(kind: String, c: Vector2, a: float) -> void:
	var gold := Color(0.95, 0.78, 0.45, a)
	var ice := Color(0.85, 0.94, 1.0, a)
	draw_circle(c, 56.0, Color(0.09, 0.13, 0.22, a))
	draw_arc(c, 56.0, 0.0, TAU, 48, gold, 2.0, true)
	match kind:
		"erdo":
			for i in 3:
				var x := c.x - 30.0 + i * 30.0
				var h := 44.0 if i == 1 else 32.0
				draw_rect(Rect2(x - 3, c.y + 18, 6, 18), Color(0.55, 0.38, 0.22, a))
				draw_colored_polygon(PackedVector2Array([Vector2(x - 17, c.y + 20), Vector2(x + 17, c.y + 20), Vector2(x, c.y + 20 - h)]), Color(0.45, 0.8, 0.5, a))
				draw_colored_polygon(PackedVector2Array([Vector2(x - 12, c.y + 2), Vector2(x + 12, c.y + 2), Vector2(x, c.y + 8 - h)]), Color(0.55, 0.88, 0.58, a))
		"jeg":
			draw_circle(c + Vector2(0, 8), 40.0, Color(0.25, 0.5, 0.8, a))
			draw_arc(c + Vector2(0, 8), 34.0, PI * 1.12, PI * 1.88, 24, ice, 13.0, true)
			draw_arc(c + Vector2(0, 8), 39.0, PI * 1.2, PI * 1.8, 24, Color(1, 1, 1, a), 3.0, true)
			draw_circle(c + Vector2(-8, 20), 9.0, Color(0.45, 0.75, 0.5, a))
			draw_circle(c + Vector2(14, 26), 7.0, Color(0.45, 0.75, 0.5, a))
		"tenger":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-46, 34), c + Vector2(-10, -8), c + Vector2(10, 34)]), Color(0.78, 0.66, 0.45, a))
			for k in 2:
				var y := c.y + (14.0 if k == 0 else -6.0)
				var w := PackedVector2Array()
				for i in 25:
					w.append(Vector2(c.x - 48.0 + i * 4.0, y + 3.0 * sin(i * 0.9 + _t * 2.0 + k)))
				draw_polyline(w, Color(0.3, 0.63, 0.88, a) if k == 0 else Color(0.56, 0.88, 0.84, a * (0.5 + 0.5 * sin(_t * 1.5))), 3.0, true)
			draw_line(c + Vector2(34, 14), c + Vector2(34, -6), gold, 2.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(29, -4), c + Vector2(39, -4), c + Vector2(34, -13)]), gold)
		"ember":
			draw_circle(c + Vector2(0, -24), 11.0, gold)
			draw_line(c + Vector2(0, -13), c + Vector2(0, 14), gold, 5.0)
			draw_line(c + Vector2(0, -4), c + Vector2(-18, 8), gold, 4.0)
			draw_line(c + Vector2(0, -4), c + Vector2(20, -12), gold, 4.0)
			draw_line(c + Vector2(0, 14), c + Vector2(-12, 38), gold, 4.0)
			draw_line(c + Vector2(0, 14), c + Vector2(12, 38), gold, 4.0)
			draw_line(c + Vector2(20, -34), c + Vector2(20, 38), Color(0.75, 0.6, 0.4, a), 3.0)
		"iranytu":
			draw_arc(c, 40.0, 0.0, TAU, 40, ice, 3.0, true)
			var ang := PI * (0.5 + 0.5 * sin(_t * 0.9))      # a tű lassan átfordul
			var d := Vector2(sin(ang), -cos(ang))
			draw_colored_polygon(PackedVector2Array([c + d * 32.0, c + d.orthogonal() * 7.0, c - d.orthogonal() * 7.0]), Color(0.93, 0.52, 0.35, a))
			draw_colored_polygon(PackedVector2Array([c - d * 32.0, c + d.orthogonal() * 7.0, c - d.orthogonal() * 7.0]), ice)
			draw_circle(c, 4.0, Color(0.09, 0.13, 0.22, a))
		_:
			for i in 7:
				draw_arc(c + Vector2(sin(i * 2.4) * 26.0, cos(i * 1.7) * 26.0), 5.0 + (i % 3) * 3.0, 0.0, TAU, 20, ice, 2.0, true)


func _ppm_at(age: float) -> float:
	if pts.is_empty():
		return 0.0
	var lo := 0
	var hi := pts.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(pts[mid][0]) <= age:
			lo = mid
		else:
			hi = mid
	var a0 := float(pts[lo][0])
	var a1 := float(pts[hi][0])
	var f := clampf((age - a0) / maxf(a1 - a0, 1.0), 0.0, 1.0)
	return lerpf(float(pts[lo][1]), float(pts[hi][1]), f)


func _gx(ppm: float) -> float:
	return lerpf(GX0, GX1, (ppm - PPM_MIN) / (PPM_MAX - PPM_MIN))


func _gy(age: float) -> float:
	return lerpf(TOP, BOTTOM, age / oldest)


func _draw() -> void:
	var font := get_theme_default_font()
	# --- ég: sarki alkony, csillagok, alacsony nap ---
	for i in 50:
		var f := i / 49.0
		draw_rect(Rect2(0, f * TOP, 840, TOP / 49.0 + 1.0), Color("#0a1230").lerp(Color("#5a6fa8"), pow(f, 1.6)).lerp(Color("#f0b890"), pow(f, 6.0) * 0.75))
	for s in _stars:
		var a := (0.35 + 0.3 * sin(_t * 1.3 + float(s[3]))) * (1.0 - float(s[1]) / 190.0)
		draw_circle(Vector2(float(s[0]), float(s[1])), float(s[2]), Color(1, 1, 1, a))
	for i in 7:
		draw_circle(Vector2(650, TOP + 6), 90.0 - i * 11.0, Color(1.0, 0.8, 0.55, 0.05 + i * 0.012))
	draw_circle(Vector2(650, TOP + 6), 17.0, Color("#ffe6b8"))
	if _era_a > 0.0 and _era >= 0:      # a megálló kártyája és rajza
		draw_rect(Rect2(30, 10, 790, 140), Color(0.043, 0.063, 0.114, 0.9 * _era_a))
		draw_rect(Rect2(30, 10, 790, 140), Color(0.95, 0.78, 0.45, 0.5 * _era_a), false, 1.5)
		_draw_era(str(eras[_era]["rajz"]), Vector2(100, 80), _era_a)
		var ey := lerpf(TOP, BOTTOM, float(eras[_era]["ezer_eve"]) * 1000.0 / oldest)      # hol van ez a kor a jégben
		draw_line(Vector2(0, ey), Vector2(840, ey), Color(0.95, 0.78, 0.45, 0.55 * _era_a), 1.5)
	# távoli jéghátak
	var ridge := PackedVector2Array([Vector2(0, TOP)])
	for i in 22:
		ridge.append(Vector2(i * 40.0, TOP - 10.0 - 14.0 * absf(sin(i * 1.7)) - 8.0 * absf(sin(i * 0.61))))
	ridge.append(Vector2(840, TOP))
	draw_colored_polygon(ridge, Color("#8fa6d0"))
	# --- jég: rétegek, lefelé egyre sötétebb és kékebb ---
	for i in 130:
		var f := i / 129.0
		var y := lerpf(TOP, H, f)
		var band := 0.035 * sin(f * 95.0) + 0.02 * sin(f * 37.0 + 1.3)
		draw_rect(Rect2(0, y, 840, (H - TOP) / 129.0 + 1.0), Color("#e8f3ff").lerp(Color("#123a6e"), clampf(pow(f, 0.7) + band, 0.0, 1.0)))
	draw_rect(Rect2(0, TOP - 3, 840, 9), Color("#ffffff"))
	for b in _bubbles:      # a jégbe zárt régi levegő buborékai
		var bf := (float(b[1]) - TOP) / (H - TOP)
		draw_circle(Vector2(float(b[0]), float(b[1])), float(b[2]), Color(1, 1, 1, 0.10 + 0.25 * (1.0 - bf) + 0.08 * sin(_t * 0.8 + float(b[3]) * 6.0)))
	# --- furat és fúró ---
	var dx := 420.0
	var dy := lerpf(TOP, BOTTOM, depth)
	var shake := Vector2(sin(_t * 47.0), 0) * (1.6 if (_hold or auto) and stuck <= 0.0 and done_t < 0.0 else 0.0)
	draw_rect(Rect2(dx - 9, TOP, 18, dy - TOP), Color("#06142c"))
	draw_rect(Rect2(dx - 9, TOP, 3, dy - TOP), Color(1, 1, 1, 0.18))
	draw_line(Vector2(dx, TOP - 88) + shake, Vector2(dx, dy - 26) + shake, Color("#c9d1de"), 3.0)
	var hot := Color("#d8e2f0").lerp(Color("#ff5a3c"), clampf(heat, 0.0, 1.0))
	if stuck > 0.0 and int(_t * 6.0) % 2 == 0:
		hot = Color("#ffd0c0")
	draw_rect(Rect2(dx - 7 + shake.x, dy - 26, 14, 20), hot)
	draw_colored_polygon(PackedVector2Array([Vector2(dx - 7, dy - 6) + shake, Vector2(dx + 7, dy - 6) + shake, Vector2(dx, dy + 5) + shake]), hot.darkened(0.2))
	if (_hold or auto) and stuck <= 0.0 and done_t < 0.0 and depth > 0.0:      # jégforgács
		for i in 6:
			var ph := fmod(_t * 2.2 + i * 0.37, 1.0)
			draw_circle(Vector2(dx + (i - 2.5) * 5.0 * (1.0 + ph), dy - 8.0 - ph * 26.0), 1.6, Color(1, 1, 1, 0.8 * (1.0 - ph)))
	# torony és sátor
	draw_line(Vector2(dx - 34, TOP), Vector2(dx, TOP - 92), Color("#39445e"), 5.0)
	draw_line(Vector2(dx + 34, TOP), Vector2(dx, TOP - 92), Color("#39445e"), 5.0)
	draw_line(Vector2(dx - 22, TOP - 32), Vector2(dx + 22, TOP - 32), Color("#39445e"), 3.0)
	draw_line(Vector2(dx - 11, TOP - 62), Vector2(dx + 11, TOP - 62), Color("#39445e"), 3.0)
	draw_circle(Vector2(dx, TOP - 92), 5.0, Color("#ff5a3c") if int(_t * 2.0) % 2 == 0 else Color("#7a2a20"))
	draw_colored_polygon(PackedVector2Array([Vector2(250, TOP), Vector2(292, TOP - 40), Vector2(350, TOP - 40), Vector2(372, TOP)]), Color("#e0935a"))
	draw_colored_polygon(PackedVector2Array([Vector2(292, TOP - 40), Vector2(350, TOP - 40), Vector2(372, TOP), Vector2(330, TOP)]), Color("#b96c3c"))
	draw_line(Vector2(520, TOP), Vector2(520, TOP - 46), Color("#39445e"), 2.0)
	draw_rect(Rect2(520, TOP - 46, 26, 14), Color("#f1c873"))
	# hőmérő a fúróhoz
	draw_rect(Rect2(40, TOP + 30, 16, 150), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(40, TOP + 30 + 150.0 * (1.0 - clampf(heat, 0.0, 1.0)), 16, 150.0 * clampf(heat, 0.0, 1.0)), Color("#8fe0d6").lerp(Color("#ff5a3c"), clampf(heat, 0.0, 1.0)))
	draw_rect(Rect2(40, TOP + 30, 16, 150), Color(1, 1, 1, 0.5), false, 1.5)
	# --- a mérés: kor (lefelé) és CO2 (jobbra) ---
	draw_rect(Rect2(840, 0, W - 840, H), Color(0.043, 0.063, 0.114, 1.0))
	draw_rect(Rect2(840, 0, 2, H), Color(1, 1, 1, 0.12))
	for ppm in [200, 250, 300, 350, 400, 450]:
		draw_line(Vector2(_gx(ppm), TOP - 8), Vector2(_gx(ppm), BOTTOM), Color(1, 1, 1, 0.09), 1.0)
		draw_string(font, Vector2(_gx(ppm) - 16, TOP - 16), str(ppm), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.MUTE)
	draw_string(font, Vector2(GX1 - 20, TOP - 38), "ppm", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.MUTE)
	for k in range(0, int(oldest / 1000.0) + 1, 100):
		var y := _gy(k * 1000.0)
		draw_line(Vector2(GX0 - 6, y), Vector2(GX1, y), Color(1, 1, 1, 0.07), 1.0)
		draw_string(font, Vector2(GX0 - 52, y + 5), str(k), HORIZONTAL_ALIGNMENT_RIGHT, 42, 15, UI.MUTE)
	draw_string(font, Vector2(GX0 - 52, BOTTOM + 30), L.t("ezer éve"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.MUTE)
	var line := PackedVector2Array()
	var age_now := depth * oldest
	for p in pts:
		if float(p[0]) > age_now:
			break
		line.append(Vector2(_gx(float(p[1])), _gy(float(p[0]))))
	if depth > 0.0 and not pts.is_empty():
		line.append(Vector2(_gx(_ppm_at(age_now)), _gy(age_now)))
	if line.size() >= 2:
		draw_polyline(line, Color(0.56, 0.88, 0.84, 0.25), 7.0, true)
		draw_polyline(line, UI.CYAN, 2.5, true)
		draw_circle(line[-1], 5.0, Color.WHITE)
		draw_line(Vector2(dx + 9, dy), Vector2(GX0 - 40, line[-1].y), Color(1, 1, 1, 0.12), 1.0)
	if done_t >= 0.0:      # a 800 ezer év sávja, majd a mai érték kiugrik belőle
		var a := clampf(done_t / 0.8, 0.0, 1.0)
		draw_rect(Rect2(_gx(pre_min), TOP, _gx(pre_max) - _gx(pre_min), BOTTOM - TOP), Color(0.56, 0.88, 0.84, 0.10 * a))
		draw_dashed_line(Vector2(_gx(pre_max), TOP), Vector2(_gx(pre_max), BOTTOM), Color(1, 1, 1, 0.5 * a), 1.5, 8.0)
		var f := clampf((done_t - 1.0) / 1.6, 0.0, 1.0)
		f = 1.0 - pow(1.0 - f, 3.0)
		if f > 0.0 and not pts.is_empty():
			var x0 := _gx(float(pts[0][1]))
			var x1 := lerpf(x0, _gx(today), f)
			draw_line(Vector2(x0, TOP), Vector2(x1, TOP), Color("#ec8559"), 4.0)
			draw_circle(Vector2(x1, TOP), 8.0 + 2.0 * sin(_t * 5.0), Color("#ec8559"))
			if f >= 1.0:
				draw_string(font, Vector2(x1 - 30, TOP + 34), L.num(today, 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#ec8559"))
