extends Control
## Minijáték: Melegrekord a tengeren. Az óceán felszínének valódi évi hőmérséklete rajzolódik ki
## 1900-tól 2024-ig (adatok/tengerfelszin_ho.json: NOAA NCEI, a forrás a fájlban). A játékos kétszer tippel:
## hány új melegrekord született egy időszakban; utána a görbe kirajzolja, mi történt valójában.
## Játékszabály: a két időszak határa, a választható tippek és a kirajzolás sebessége.
## A zátony rajza jelkép: a korallok fakulása a görbét követi, nem egy mért zátonyt mutat.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const YEAR_SECONDS := 0.14        # játékszabály: ennyi ideig tart egy év a kirajzoláskor
const SPLITS := [1950, 1980, 2024]                 # játékszabály: a két tipp időszakai
const OPTIONS := [[0, 4, 9], [2, 6, 11]]           # játékszabály: a választható tippek
const QUESTIONS := [
	"A görbe az óceán felszínének hőmérséklete. A sárga pöttyök melegrekordok. Szerinted hány új rekord született %d és %d között?",
	"És %d után, egészen %d-ig? Tippelj!"]
const CX0 := 150.0
const CX1 := 1500.0
const CY0 := 175.0
const CY1 := 470.0
const SEA_Y := 520.0
const STUDY := "Longer and more frequent marine heatwaves over the past century (2018)"

var data_path := "res://adatok/tengerfelszin_ho.json"
var auto := false                 # próbafutás: magától elkapja a rekordokat
var done_t := -1.0                # a befejezés óta eltelt idő; < 0 = még tart
var years: Array = []
var vals: Array = []
var records: Array = []           # [{k, caught}] az első év utáni rekordok
var source := ""
var hits := 0
var round_i := 0
var _guess := -1
var _target := 0.0
var _wait := 0.0
var _gap := 0                    # ennyi évig állt a leghosszabb ideig álló rekord
var _btns: HBoxContainer
var _say: Label
var _next_btn: Button
var _pos := 0.0                   # hol tart a görbe (évindex, törttel)
var _t := 0.0
var _flash := -9.0
var _miss := -9.0
var _lo := 0.0
var _hi := 1.0
var _corals: Array = []
var _fish: Array = []
var _bubbles: Array = []
var _info: Label
var _read: Label
var _end: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	_make_reef()
	var title := UI.heading(L.t("Melegrekord a tengeren"), 34)
	title.position = Vector2(60, 28)
	add_child(title)
	_info = UI.label("", 18, UI.SOFT)
	_info.position = Vector2(60, 80)
	_info.size = Vector2(1000, 50)
	add_child(_info)
	_say = UI.label("", 20, UI.TEXT, true)
	_say.position = Vector2(60, 84)
	_say.size = Vector2(1000, 50)
	_say.visible = false
	add_child(_say)
	_btns = UI.hbox(14)
	_btns.position = Vector2(1080, 88)
	add_child(_btns)
	for i in 3:
		var ob := UI.button("0", true)
		ob.custom_minimum_size = Vector2(70, 0)
		ob.pressed.connect(_choose.bind(i))
		_btns.add_child(ob)
	_next_btn = UI.button(L.t("Tovább") + " →", true)
	_next_btn.position = Vector2(1390, 30)
	_next_btn.visible = false
	_next_btn.pressed.connect(_next)
	add_child(_next_btn)
	_read = UI.label("", 20, UI.CYAN, true, false)
	_read.position = Vector2(1120, 40)
	add_child(_read)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(150, 545)
	_end.size = Vector2(1300, 300)
	_end.visible = false
	add_child(_end)
	_pos = float(years.find(int(SPLITS[0])))
	_target = _pos
	var prev_y := int(years[0])
	for r in records:      # a leghosszabb szünet két rekord között
		var ry := int(years[int(r["k"])])
		_gap = maxi(_gap, ry - prev_y)
		prev_y = ry
	_ask()
	_update_read()
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	source = str(j.get("forras_en" if L.is_en() else "forras", ""))
	var best := -INF
	for row in j.get("adatok", []):
		var v := float(row[1])
		if v > best:
			if not years.is_empty():      # az első év nem rekord, csak a kiindulás
				records.append({"k": years.size(), "caught": false})
			best = v
		years.append(int(row[0]))
		vals.append(v)
	if vals.is_empty():
		return
	_lo = float(vals.min()) - 0.08
	_hi = float(vals.max()) + 0.1


func ok() -> bool:
	return years.size() > 100 and records.size() >= 5


func _make_reef() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var hues := [Color("#e8567c"), Color("#f08a4b"), Color("#b667d6"), Color("#f2c14e"), Color("#4fc3a1"), Color("#ef6f6c")]
	var x := 40.0
	while x < W - 40.0:
		var kind := rng.randi_range(0, 2)
		var branches: Array = []
		if kind == 0:      # ágas korall
			_branch(rng, branches, Vector2.ZERO, -PI / 2.0, rng.randf_range(34.0, 58.0), 4)
		_corals.append({"x": x, "y": H - rng.randf_range(34.0, 70.0), "kind": kind, "col": hues[rng.randi_range(0, hues.size() - 1)],
			"s": rng.randf_range(0.8, 1.35), "br": branches, "late": rng.randf_range(0.0, 0.35)})
		x += rng.randf_range(62.0, 120.0)
	for i in 14:
		_fish.append([rng.randf_range(0.0, W), rng.randf_range(SEA_Y + 60.0, H - 150.0), rng.randf_range(24.0, 60.0) * (1.0 if rng.randf() < 0.5 else -1.0),
			[Color("#f2c14e"), Color("#8fe0d6"), Color("#f08a4b")][rng.randi_range(0, 2)], rng.randf_range(0.7, 1.3)])
	for i in 26:
		_bubbles.append([rng.randf_range(0.0, W), rng.randf_range(0.0, 1.0), rng.randf_range(1.5, 4.0), rng.randf_range(18.0, 40.0)])


func _branch(rng: RandomNumberGenerator, out: Array, p: Vector2, ang: float, length: float, depth: int) -> void:
	var e := p + Vector2(cos(ang), sin(ang)) * length
	out.append([p, e, depth])
	if depth <= 1:
		return
	for s in [-1.0, 1.0]:
		_branch(rng, out, e, ang + s * rng.randf_range(0.3, 0.6), length * rng.randf_range(0.62, 0.78), depth - 1)


func _now() -> float:      # a görbe mostani értéke
	var k := int(floor(_pos))
	if k >= vals.size() - 1:
		return float(vals[-1])
	return lerpf(float(vals[k]), float(vals[k + 1]), _pos - k)


func _record_before(k: int) -> float:
	var m := -INF
	for i in mini(k, vals.size()):
		m = maxf(m, float(vals[i]))
	return m


func _update_read() -> void:
	var k := clampi(int(floor(_pos)), 0, years.size() - 1)
	_read.text = "%d    %s °C" % [years[k], ("+" if float(vals[k]) >= 0.0 else "") + L.num(float(vals[k]), 2)]


## Hány új rekord született a két évszám között (a második is beleszámít)?
func _records_between(y0: int, y1: int) -> int:
	var n := 0
	for r in records:
		var y := int(years[int(r["k"])])
		if y > y0 and y <= y1:
			n += 1
	return n


func _answer() -> int:
	return _records_between(int(SPLITS[round_i]), int(SPLITS[round_i + 1]))


func _ask() -> void:
	_info.text = L.t(QUESTIONS[round_i]) % [int(SPLITS[round_i]), int(SPLITS[round_i + 1])]
	_info.visible = true
	var opts: Array = OPTIONS[round_i]
	for i in 3:
		(_btns.get_child(i) as Button).text = str(opts[i])
	_btns.visible = true
	_say.visible = false
	_next_btn.visible = false
	_guess = -1


func _choose(i: int) -> void:
	if done_t >= 0.0 or _guess >= 0 or round_i >= 2:
		return
	_guess = int(OPTIONS[round_i][i])
	_btns.visible = false
	_target = float(years.find(int(SPLITS[round_i + 1])))


func _next() -> void:
	if done_t >= 0.0:
		finished.emit(true)
		return
	if _guess < 0 or _pos < _target:
		return
	round_i += 1
	if round_i >= 2:
		_finish()
	else:
		_ask()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		finished.emit(done_t >= 0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
		queue_redraw()
		return
	if _guess < 0:
		if auto:
			_wait += delta
			if _wait > 2.0:
				_wait = 0.0
				_choose((OPTIONS[round_i] as Array).find(_answer()) if (OPTIONS[round_i] as Array).has(_answer()) else 0)
	elif _pos < _target:
		var before := int(floor(_pos))
		_pos = minf(_target, _pos + delta / YEAR_SECONDS)
		for r in records:      # új rekord: felvillan a felirat
			if int(r["k"]) > before and int(r["k"]) <= int(floor(_pos)):
				_flash = _t
		if _pos >= _target:
			var real := _answer()
			var hit := real == _guess
			if hit:
				hits += 1
			var line := L.t("Nem született új rekord: a régi csúcs %d évig tartott.") % _gap if real == 0 else L.t("%d új melegrekord született.") % real
			_say.text = (L.t("Eltaláltad!") if hit else L.t("Nem ennyi volt.")) + " " + line
			_say.add_theme_color_override("font_color", UI.GREEN if hit else UI.TEXT)
			_say.visible = true
			_info.visible = false
			_next_btn.visible = true
			_wait = 0.0
	elif auto:
		_wait += delta
		if _wait > 2.5:
			_wait = 0.0
			_next()
	_update_read()
	queue_redraw()


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_pos = float(years.size() - 1)
	_info.visible = false
	_say.visible = false
	_btns.visible = false
	var late := 0
	for r in records:
		if int(years[int(r["k"])]) >= 1980:
			late += 1
	_end.visible = true
	_end.add_child(UI.label(L.t("%d óta %d új melegrekord született, ebből %d 1980 után.") % [years[0], records.size(), late], 22, UI.CYAN, true))
	_end.add_child(UI.label(L.t("Minél melegebb az alaphőmérséklet, annál könnyebben jön létre tengeri hőhullám."), 19, UI.TEXT))
	_end.add_child(UI.label(L.t("Mérések szerint 1925 és 2016 között a tengeri hőhullámok 34%-kal gyakoribbak és 17%-kal hosszabbak lettek, így évente 54%-kal több a tengeri hőhullámos nap. Ezt főleg a tenger átlagos melegedése okozza, ami az élővilág pusztulását vetíti előre."), 19, UI.TEXT))
	_end.add_child(UI.label(L.t("Forrás: %s") % (source + "; " + STUDY), 13, UI.MUTE))
	_next_btn.visible = true


func _px(k: float) -> float:
	return lerpf(CX0, CX1, k / float(years.size() - 1))


func _py(v: float) -> float:
	return lerpf(CY1, CY0, (v - _lo) / (_hi - _lo))


func _draw_sea(heat: float) -> void:
	# víz: a mélység felé sötétedik; a melegedéssel a színe zöldesebb, fakóbb lesz (jelkép)
	var top := Color("#1d6fa8").lerp(Color("#3f9a94"), heat * 0.7)
	var deep := Color("#07213f").lerp(Color("#12313a"), heat * 0.6)
	for i in 30:
		var f := i / 30.0
		draw_rect(Rect2(0, SEA_Y + f * (H - SEA_Y), W, (H - SEA_Y) / 30.0 + 1.0), top.lerp(deep, pow(f, 0.8)))
	for i in 7:      # fénysugarak
		var x := 120.0 + i * 230.0 + sin(_t * 0.4 + i) * 30.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, SEA_Y), Vector2(x + 60.0, SEA_Y), Vector2(x - 60.0, H), Vector2(x - 200.0, H)]), Color(1, 1, 1, 0.035))
	var wave := PackedVector2Array()      # vízfelszín
	for i in 81:
		var x := i * 20.0
		wave.append(Vector2(x, SEA_Y + sin(x * 0.02 + _t * 1.6) * 4.0))
	draw_polyline(wave, Color(1, 1, 1, 0.35), 2.0, true)
	for b in _bubbles:
		var f := fmod(float(b[1]) + _t / float(b[3]), 1.0)
		draw_arc(Vector2(float(b[0]) + sin(_t + float(b[0])) * 5.0, lerpf(H - 40.0, SEA_Y + 10.0, f)), float(b[2]), 0.0, TAU, 10, Color(1, 1, 1, 0.25), 1.0)
	# homok
	var sand := PackedVector2Array([Vector2(0, H)])
	for i in 41:
		sand.append(Vector2(i * 40.0, H - 40.0 - 10.0 * sin(i * 0.5) - 6.0 * sin(i * 1.7)))
	sand.append(Vector2(W, H))
	draw_colored_polygon(sand, Color("#b9a27a").lerp(Color("#0b2a45"), 0.45))
	# halak
	for fsh in _fish:
		var sp := float(fsh[2])
		var x := fmod(float(fsh[0]) + _t * sp + W * 20.0, W + 120.0) - 60.0
		var p := Vector2(x, float(fsh[1]) + sin(_t * 1.5 + float(fsh[0])) * 8.0)
		var d := signf(sp)
		var s := float(fsh[4])
		var c: Color = fsh[3]
		draw_colored_polygon(PackedVector2Array([p + Vector2(14 * d, 0) * s, p + Vector2(0, -6) * s, p + Vector2(-10 * d, 0) * s, p + Vector2(0, 6) * s]), Color(c, 0.9))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-9 * d, 0) * s, p + Vector2(-18 * d, -6) * s, p + Vector2(-18 * d, 6) * s]), Color(c, 0.75))
	# korallok: a melegedéssel kifakulnak
	var bone := Color("#e9e4d8")
	for c in _corals:
		var bl := clampf((heat - float(c["late"])) / 0.6, 0.0, 1.0)
		var col: Color = (c["col"] as Color).lerp(bone, bl)
		var p := Vector2(float(c["x"]), float(c["y"]))
		var s := float(c["s"])
		match int(c["kind"]):
			0:
				for br in c["br"]:
					draw_line(p + (br[0] as Vector2) * s, p + (br[1] as Vector2) * s, col, 2.0 + float(br[2]) * 1.6)
					if int(br[2]) == 1:
						draw_circle(p + (br[1] as Vector2) * s, 3.5, col.lightened(0.15))
			1:      # agykorall
				draw_circle(p + Vector2(0, -16) * s, 26.0 * s, col.darkened(0.15))
				for a in 5:
					draw_arc(p + Vector2(0, -16) * s, (6.0 + a * 4.5) * s, PI, TAU, 14, col.lightened(0.2), 1.5)
			_:      # legyezőkorall
				for a in 7:
					var ang := -PI / 2.0 + (a - 3) * 0.24
					var e := p + Vector2(cos(ang), sin(ang)) * 62.0 * s
					draw_line(p, e, col, 3.0)
					draw_circle(e, 4.0, col.lightened(0.15))
				draw_arc(p, 40.0 * s, -PI / 2.0 - 0.72, -PI / 2.0 + 0.72, 12, col.darkened(0.1), 2.0)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, W, SEA_Y), Color("#0b1324"))
	if vals.is_empty():
		return
	var heat := clampf((_now() - 0.25) / 0.7, 0.0, 1.0)      # jelkép: 0 = a régi tenger, 1 = a 2024-es
	_draw_sea(heat)
	# --- grafikon ---
	draw_rect(Rect2(CX0 - 70.0, CY0 - 20.0, CX1 - CX0 + 110.0, CY1 - CY0 + 60.0), Color(0.09, 0.13, 0.22, 1.0))
	draw_string(font, Vector2(CX0 - 60.0, CY0 - 28.0), L.t("Az óceán felszíne: eltérés a 20. századi átlagtól (°C)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.SOFT)
	for g in [-0.4, 0.0, 0.4, 0.8]:
		var gy := _py(g)
		draw_line(Vector2(CX0, gy), Vector2(CX1, gy), Color(1, 1, 1, 0.14 if g == 0.0 else 0.06), 1.0)
		draw_string(font, Vector2(CX0 - 66.0, gy + 5.0), ("+" if g > 0.0 else "") + L.num(g, 1), HORIZONTAL_ALIGNMENT_RIGHT, 56, 13, UI.MUTE)
	for yv in [1900, 1920, 1940, 1960, 1980, 2000, 2020]:
		var k := years.find(yv)
		if k >= 0:
			draw_string(font, Vector2(_px(float(k)) - 30.0, CY1 + 26.0), str(yv), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, UI.MUTE)
	var last := minf(_pos, float(years.size() - 1))
	var whole := int(floor(last))
	# az eddigi rekord szaggatott vonala
	if done_t < 0.0:
		var rec := _record_before(whole + 1)
		var ry := _py(rec)
		draw_dashed_line(Vector2(CX0, ry), Vector2(CX1, ry), Color(UI.GOLD, 0.7), 2.0, 10.0)
		draw_string(font, Vector2(CX1 - 200.0, ry - 8.0), L.t("eddigi rekord"), HORIZONTAL_ALIGNMENT_RIGHT, 200, 14, UI.GOLD)
	# a görbe: a hidegebb évek kékek, a melegebbek narancsok
	for k in whole:
		var c := Color("#6fb6ea").lerp(UI.EMBER, clampf((float(vals[k + 1]) + 0.2) / 0.9, 0.0, 1.0))
		draw_line(Vector2(_px(float(k)), _py(float(vals[k]))), Vector2(_px(float(k + 1)), _py(float(vals[k + 1]))), c, 3.0, true)
	var tip := Vector2(_px(last), _py(_now() if done_t < 0.0 else float(vals[-1])))
	if whole < years.size() - 1:
		draw_line(Vector2(_px(float(whole)), _py(float(vals[whole]))), tip, UI.EMBER, 3.0, true)
	draw_circle(tip, 5.0, UI.TEXT)
	# rekordok jelei
	for r in records:
		var k := int(r["k"])
		if k > last:
			continue
		var p := Vector2(_px(float(k)), _py(float(vals[k])))
		draw_circle(p, 8.0, UI.GOLD)
	if _t - _flash < 0.8:
		draw_string(font, tip + Vector2(-130.0, -22.0), L.t("Új rekord!"), HORIZONTAL_ALIGNMENT_CENTER, 260, 20, Color(UI.GOLD, 1.0 - (_t - _flash) / 0.8))
	if done_t >= 0.0:
		draw_rect(Rect2(120, 530, 1360, 200), Color(0.043, 0.063, 0.114, 0.9 * clampf(done_t / 0.8, 0.0, 1.0)))
	else:
		draw_string(font, Vector2(60, 880), L.t("A korallok fakulása jelkép: a görbét követi."), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
