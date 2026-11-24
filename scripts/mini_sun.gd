extends Control
## Minijáték: Nap vagy CO₂? Három valódi mérési sor (a Nap ereje, a felszín és a sztratoszféra
## hőmérséklete, 1980–2023; adatok/nap_vagy_co2.json, a források a fájlban). A játékos az első
## évek alapján megtippeli, merre megy tovább a görbe, aztán megjelenik, amit valóban mértek.
## Játékszabály: a tippelés és a három kör. A bal oldali légkör-rajz jelkép (a színek a mért irányt
## mutatják, nem a mértékét).

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const SHOWN := 16                 # játékszabály: ennyi év látszik a tipp előtt (1980–1995)
const REVEAL_SECONDS := 2.6
const CX0 := 640.0                # a grafikonok bal széle
const CX1 := 1540.0
const CY0 := 250.0
const CH := 150.0                 # egy grafikon magassága
const CGAP := 52.0
const FLAT := 0.05                # ennél kisebb évtizedes trend: „nem változik”
const QUESTIONS := [
	"Ha a Nap melegítené a Földet, akkor a levegő minden rétege melegedne. Mit mértek 1995 után? Csökkent, nőtt vagy nem változott a Nap ereje? Tippelj!",
	"És a felszín hőmérséklete? Csökkent, nőtt vagy nem változott 1995 után? Tippelj!",
	"És fent, a sztratoszférában? Ott csökkent, nőtt vagy nem változott a hőmérséklet 1995 után? Tippelj!"]
const WARM := Color("#ec8559")
const COOL := Color("#6fb6ea")

var data_path := "res://adatok/nap_vagy_co2.json"
var auto := false                 # próbafutás: magától tippel
var done_t := -1.0                # a befejezés óta eltelt idő; < 0 = még tart
var years: Array = []
var series: Array = []            # [{name, unit, vals, trend, answer, say, col}]
var source := ""
var round_i := 0
var hits := 0
var _guess: Array = [-9, -9, -9]
var _rev: Array = [0.0, 0.0, 0.0]   # 0..1: mennyi látszik a rejtett részből
var _wait := 0.0
var _t := 0.0
var _info: Label
var _say: Label
var _btns: HBoxContainer
var _next_btn: Button
var _end: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	var title := UI.heading(L.t("Nap vagy CO₂?"), 34)
	title.position = Vector2(60, 28)
	add_child(title)
	_info = UI.label(L.t(QUESTIONS[0]), 18, UI.SOFT)
	_info.position = Vector2(60, 84)
	_info.size = Vector2(1000, 50)
	add_child(_info)
	_btns = UI.hbox(14)
	_btns.position = Vector2(CX0, 150)
	add_child(_btns)
	var names := ["↘ " + L.t("csökken"), "→ " + L.t("nem változik"), "↗ " + L.t("nő")]
	for i in 3:
		var b := UI.button(names[i], i == 1)
		b.pressed.connect(_choose.bind(i - 1))
		_btns.add_child(b)
	_say = UI.label("", 19, UI.TEXT, true)
	_say.position = Vector2(CX0, 140)
	_say.size = Vector2(CX1 - CX0, 80)
	_say.visible = false
	add_child(_say)
	_next_btn = UI.button(L.t("Tovább") + " →", true)
	_next_btn.position = Vector2(1390, 30)
	_next_btn.visible = false
	_next_btn.pressed.connect(_next)
	add_child(_next_btn)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(CX0, 130)
	_end.size = Vector2(CX1 - CX0, 100)
	_end.visible = false
	add_child(_end)
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	source = str(j.get("forras_en" if L.is_en() else "forras", ""))
	var tr: Dictionary = j.get("trend_evtizedenkent_1980_2023", {})
	var cols := [[], [], []]
	for row in j.get("adatok", []):
		years.append(int(row[0]))
		cols[0].append(float(row[1]))
		cols[1].append(float(row[2]))
		cols[2].append(float(row[4]))
	var defs := [
		["A Nap ereje", "W/m²", "tsi_W_m2", "A Nap ereje 1980 óta nem nőtt: 11 évente hullámzik, kb. 1 W/m²-t.", UI.GOLD],
		["A felszín hőmérséklete", "°C", "felszin_C", "A felszín közben évtizedenként kb. 0,2 °C-kal melegedett.", WARM],
		["A sztratoszféra hőmérséklete", "°C", "sztratoszfera_C", "A magasban, a sztratoszférában viszont hűlt a levegő. Ezt a CO2 okozza: lent csapdába ejti a hőt, fent több hőt sugároz ki a világűrbe.", COOL]]
	for i in 3:
		var t := float(tr.get(defs[i][2], 0.0))
		series.append({"name": L.t(defs[i][0]), "unit": defs[i][1], "vals": cols[i], "trend": t,
			"answer": 0 if absf(t) < FLAT else signi(int(signf(t))), "say": L.t(defs[i][3]), "col": defs[i][4]})


func ok() -> bool:
	return years.size() > SHOWN + 10 and series.size() == 3


func _choose(g: int) -> void:
	if done_t >= 0.0 or round_i >= 3 or int(_guess[round_i]) != -9:
		return
	_guess[round_i] = g
	_btns.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		finished.emit(done_t >= 0.0)


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
		queue_redraw()
		return
	if round_i < 3:
		if int(_guess[round_i]) == -9:
			if auto and _t > 1.5 + round_i * 0.2:
				_wait += delta
				if _wait > 1.2:
					_wait = 0.0
					_choose(int(series[round_i]["answer"]))
		elif float(_rev[round_i]) < 1.0:
			_rev[round_i] = minf(1.0, float(_rev[round_i]) + delta / REVEAL_SECONDS)
			if float(_rev[round_i]) >= 1.0:
				var good := int(_guess[round_i]) == int(series[round_i]["answer"])
				if good:
					hits += 1
				_say.text = (L.t("Eltaláltad!") if good else L.t("Nem ezt mérték.")) + " " + str(series[round_i]["say"])
				_say.add_theme_color_override("font_color", UI.GREEN if good else UI.TEXT)
				_say.visible = true
				_next_btn.visible = true
				_wait = 0.0
		elif auto:      # a játékos a Tovább gombbal lép, amikor elolvasta; csak a próbafutás lép magától
			_wait += delta
			if _wait > 2.4:
				_next()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()


func _next() -> void:
	if done_t >= 0.0:
		finished.emit(true)
		return
	if round_i >= 3 or float(_rev[round_i]) < 1.0:
		return
	_wait = 0.0
	_say.visible = false
	_next_btn.visible = false
	round_i += 1
	if round_i >= 3:
		_finish()
	else:
		_info.text = L.t(QUESTIONS[round_i])
		_info.visible = true
		_btns.visible = true


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_btns.visible = false
	_info.visible = false
	_end.visible = true
	_end.add_child(UI.label(L.t("Tanulság: a jelenlegi felmelegedést a CO₂ okozza, nem a Nap."), 22, UI.GOLD, true))
	_end.add_child(UI.label(L.t("Forrás: %s") % source, 13, UI.MUTE))
	_next_btn.visible = true


func _chart_y(i: int) -> float:
	return CY0 + i * (CH + CGAP)


func _draw_scene(font: Font) -> void:
	# --- bal oldal: a légkör rétegei (jelkép) ---
	var x0 := 60.0
	var x1 := 560.0
	var top := 190.0
	var bot := 850.0
	var strat_cool := float(_rev[2])
	var surf_warm := float(_rev[1])
	# világűr
	draw_rect(Rect2(x0, top, x1 - x0, bot - top), Color("#070b18"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var p := Vector2(rng.randf_range(x0 + 6.0, x1 - 6.0), rng.randf_range(top + 4.0, top + 190.0))
		draw_circle(p, rng.randf_range(0.6, 1.5), Color(1, 1, 1, 0.25 + 0.2 * sin(_t * 1.3 + i)))
	# sztratoszféra: hűlés esetén kékül
	var sy0 := top + 200.0
	var sy1 := top + 400.0
	var scol := Color("#39486e").lerp(Color("#2f7fd1"), strat_cool)
	for k in 20:
		var f := k / 19.0
		draw_rect(Rect2(x0, lerpf(sy0, sy1, f), x1 - x0, (sy1 - sy0) / 19.0 + 1.0), Color("#0d1530").lerp(scol, 0.35 + 0.65 * f))
	# troposzféra és felszín: melegedés esetén vörösödik
	var ty1 := bot - 70.0
	var tcol := Color("#5f8fc4").lerp(Color("#d98a63"), surf_warm * 0.8)
	for k in 20:
		var f := k / 19.0
		draw_rect(Rect2(x0, lerpf(sy1, ty1 + 30.0, f), x1 - x0, (ty1 + 30.0 - sy1) / 19.0 + 1.0), scol.lerp(tcol, f))
	for i in 5:      # felhők
		var cx := fmod(x0 + 60.0 + i * 110.0 + _t * (6.0 + i), x1 - x0 - 80.0) + x0 + 40.0
		var cy := sy1 + 80.0 + (i % 3) * 46.0
		for d in 4:
			draw_circle(Vector2(cx + d * 16.0 - 24.0, cy + (d % 2) * 6.0), 15.0 + (d % 2) * 5.0, Color(1, 1, 1, 0.16))
	# föld: dombok
	var ground := PackedVector2Array([Vector2(x0, bot)])
	for k in 26:
		var gx := lerpf(x0, x1, k / 25.0)
		ground.append(Vector2(gx, ty1 + 14.0 * sin(k * 0.55) + 8.0 * sin(k * 1.3 + 1.0)))
	ground.append(Vector2(x1, bot))
	draw_colored_polygon(ground, Color("#2f5d46").lerp(Color("#7a5b3a"), surf_warm * 0.5))
	# a Nap: a mért ereje szerint lüktet (a hullámzás erősen felnagyítva)
	var sun := Vector2(x0 + 90.0, top + 80.0)
	var pulse := 0.5
	if not series.is_empty():
		var vals: Array = series[0]["vals"]
		var n := vals.size()
		var idx := int(clampf((SHOWN + float(_rev[0]) * (n - SHOWN)) - 1.0, 0.0, n - 1.0))
		var lo: float = vals.min()
		var hi: float = vals.max()
		pulse = (float(vals[idx]) - lo) / maxf(hi - lo, 0.001)
	for r in 6:
		draw_circle(sun, 40.0 + pulse * 10.0 + r * 9.0, Color(UI.GOLD, 0.05))
	draw_circle(sun, 38.0 + pulse * 8.0, Color("#ffd98a"))
	for i in 5:      # napsugarak lefelé
		var a := 0.5 + i * 0.16
		var dir := Vector2(cos(a), sin(a))
		draw_line(sun + dir * 70.0, sun + dir * minf(560.0, (x1 - 8.0 - sun.x) / dir.x), Color(UI.GOLD, 0.07), 6.0)
	# feliratok és nyilak
	draw_string(font, Vector2(x1 - 200.0, (sy0 + sy1) * 0.5 + 6.0), L.t("sztratoszféra"), HORIZONTAL_ALIGNMENT_RIGHT, 190, 17, UI.TEXT)
	draw_string(font, Vector2(x1 - 200.0, ty1 - 20.0), L.t("felszín"), HORIZONTAL_ALIGNMENT_RIGHT, 190, 17, UI.TEXT)
	if strat_cool >= 1.0:
		_arrow(Vector2(x0 + 330.0, (sy0 + sy1) * 0.5 - 30.0), 60.0, COOL)
	if surf_warm >= 1.0:
		_arrow(Vector2(x0 + 330.0, ty1 - 30.0), -60.0, WARM)
	draw_rect(Rect2(x0, top, x1 - x0, bot - top), UI.EDGE, false, 2.0)


func _arrow(p: Vector2, dy: float, col: Color) -> void:
	var e := p + Vector2(0, dy)
	draw_line(p, e, col, 5.0)
	var s := signf(dy)
	draw_colored_polygon(PackedVector2Array([e + Vector2(0, 14.0 * s), e + Vector2(-12, -4.0 * s), e + Vector2(12, -4.0 * s)]), col)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, W, H), UI.PANEL_BG)
	_draw_scene(font)
	if years.is_empty():
		return
	var n := years.size()
	for i in 3:
		var s: Dictionary = series[i]
		var vals: Array = s["vals"]
		var y0 := _chart_y(i)
		var active := done_t < 0.0 and i == round_i
		var seen := done_t >= 0.0
		draw_rect(Rect2(CX0, y0, CX1 - CX0, CH), Color(0.09, 0.13, 0.22, 1.0 if active or seen else 0.35))
		draw_rect(Rect2(CX0, y0, CX1 - CX0, CH), Color(s["col"], 0.9) if active else UI.EDGE, false, 2.0 if active else 1.0)
		var dim := 1.0 if active or seen else 0.28
		draw_string(font, Vector2(CX0 + 4.0, y0 - 10.0), "%s (%s)" % [s["name"], s["unit"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(s["col"], dim))
		var lo: float = vals.min()
		var hi: float = vals.max()
		var pad := (hi - lo) * 0.12
		lo -= pad
		hi += pad
		var px := func(k: float) -> float: return lerpf(CX0 + 70.0, CX1 - 20.0, k / float(n - 1))
		var py := func(v: float) -> float: return lerpf(y0 + CH - 8.0, y0 + 8.0, (v - lo) / (hi - lo))
		for g in 3:      # tengely: három érték
			var gv := lerpf(vals.min(), vals.max(), g / 2.0)
			var gy: float = py.call(gv)
			draw_line(Vector2(CX0 + 64.0, gy), Vector2(CX1 - 20.0, gy), Color(1, 1, 1, 0.06), 1.0)
			draw_string(font, Vector2(CX0 + 2.0, gy + 5.0), L.num(gv, 1), HORIZONTAL_ALIGNMENT_RIGHT, 58, 13, Color(UI.MUTE, dim))
		var last := float(SHOWN - 1)
		if i < round_i or done_t >= 0.0:
			last = float(n - 1)
		elif i == round_i:
			last = SHOWN - 1 + float(_rev[i]) * (n - SHOWN)
		# a még rejtett rész
		if last < n - 1:
			var hx: float = px.call(last)
			draw_rect(Rect2(hx + 4.0, y0 + 2.0, CX1 - hx - 6.0, CH - 4.0), Color(0, 0, 0, 0.28))
			if int(_guess[i]) == -9:
				draw_string(font, Vector2(hx, y0 + CH * 0.5 + 16.0), "?", HORIZONTAL_ALIGNMENT_CENTER, CX1 - hx, 44, Color(1, 1, 1, 0.25 * dim + (0.15 * sin(_t * 3.0) if active else 0.0)))
		# a játékos tippje: szaggatott vonal a látható rész végétől
		if int(_guess[i]) != -9:
			var a := Vector2(px.call(float(SHOWN - 1)), py.call(float(vals[SHOWN - 1])))
			var b := Vector2(CX1 - 20.0, clampf(a.y - int(_guess[i]) * CH * 0.38, y0 + 8.0, y0 + CH - 8.0))
			draw_dashed_line(a, b, Color(1, 1, 1, 0.35), 2.0, 8.0)
		# a mért görbe
		var pts := PackedVector2Array()
		var whole := int(floor(last))
		for k in whole + 1:
			pts.append(Vector2(px.call(float(k)), py.call(float(vals[k]))))
		if whole < n - 1 and last > whole:
			var f := last - whole
			pts.append(Vector2(px.call(last), py.call(lerpf(float(vals[whole]), float(vals[whole + 1]), f))))
		if pts.size() >= 2:
			draw_polyline(pts, Color(s["col"], dim), 3.0, true)
		draw_circle(pts[-1], 4.5, Color(s["col"], dim))
		# évszámok
		for yv in [1980, 1995, 2010, 2023]:
			var k := years.find(yv)
			if k >= 0 and i == 2:
				draw_string(font, Vector2(px.call(float(k)) - 30.0, y0 + CH + 20.0), str(yv), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, UI.MUTE)
		draw_line(Vector2(px.call(float(SHOWN - 1)), y0 + 2.0), Vector2(px.call(float(SHOWN - 1)), y0 + CH - 2.0), Color(1, 1, 1, 0.12), 1.0)
