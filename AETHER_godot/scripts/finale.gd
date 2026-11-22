extends Control
## Záró jelenet 2100-ban: két Föld egymás mellett. Balra az, ami terv nélkül lett volna,
## jobbra a te Földed. Közben az évszámláló 2026-tól 2100-ig fut, és kirajzolódik a két út.
## Minden szám a klímamodellből jön; a földgömb színezése csak szemléltetés.
## Esc vagy kattintás: átugrás. A végén a `finished` jelre a játék megnyitja az összegzést.

signal finished

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Globe := preload("res://scripts/globe.gd")
const Milestones := preload("res://scripts/milestones.gd")
const PathStrip := preload("res://scripts/path_strip.gd")

const T_FADE := 2.0           # elsötétül
const T_TITLE := 5.0          # „2100.”
const T_COUNT := 16.0         # eddig fut a számláló (11 mp)
const T_VERDICT := 18.0       # megjelenik az ítélet
const T_END := 30.0
const Y0 := 2026
const Y1 := 2100
var campaign
var _t := 0.0
var _done := false
var _g_base: Control
var _g_plan: Control
var _music: AudioStreamPlayer
var _btn: Button
var _years: Array = []
var _plan: Array = []
var _base: Array = []
var _i0 := 0
var _has_plan := false


func _ready() -> void:
	# a szülő (főképernyő) mérete 0 lehet: kifejezetten a teljes képre feszül, hogy a kattintás is ide jusson
	position = Vector2.ZERO
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	var m: Dictionary = campaign.model
	_years = m.get("evek", [])
	# ami ebben a játékban tényleg történt: a Föld rejtett érzékenysége szerinti két pálya
	_plan = []
	_base = []
	for y in _years:
		var tp: float = campaign.world_value("terv", "homerseklet", int(y))
		var tb: float = campaign.world_value("alapeset", "homerseklet", int(y))
		_plan.append(tp)
		_base.append(tp if is_nan(tb) else tb)
	_has_plan = not campaign.timeline.is_empty()
	for i in _years.size():
		if int(_years[i]) == Y0:
			_i0 = i
	_g_base = _make_globe(Vector2(170, 170))
	_g_plan = _make_globe(Vector2(1010, 170))
	_btn = UI.button(L.t("Tovább"), true)
	_btn.position = Vector2(730, 822)
	_btn.custom_minimum_size = Vector2(140, 44)
	_btn.modulate.a = 0.0
	_btn.pressed.connect(_finish)
	add_child(_btn)
	_music = AudioStreamPlayer.new()
	_music.stream = Milestones.load_sound("zaro")
	_music.volume_db = -5.0
	add_child(_music)
	if _music.stream != null:
		_music.play()


func _make_globe(pos: Vector2) -> Control:
	var g = Globe.new()
	g.position = pos
	g.size = Vector2(420, 420)
	g.pixels = 320.0
	g.real_sun = false            # itt mindig nappal van, hogy a két Föld jól látsszon
	g.tilt = 0.80                 # kicsit északról nézzük: látszik a sarki jég
	g.spin = 0.02
	g.spin_speed = 0.010          # lassan forog, hogy az egész Föld látszódjon
	g.modulate.a = 0.0
	add_child(g)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _finish() -> void:
	if _done:
		return
	_done = true
	if _music != null and _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -45.0, 1.2)
	var tw2 := create_tween()
	tw2.tween_property(self, "modulate:a", 0.0, 0.6)
	tw2.tween_callback(func() -> void:
		finished.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _t > T_VERDICT:
		_finish()


static func _ss(a: float, b: float, x: float) -> float:
	var k := clampf((x - a) / (b - a), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


func _temp(series: Array, yf: float) -> float:
	if series.is_empty():
		return 0.0
	var f := clampf(yf - Y0, 0.0, float(Y1 - Y0))
	var a := mini(_i0 + int(floor(f)), series.size() - 1)
	var b := mini(a + 1, series.size() - 1)
	return lerpf(float(series[a]), float(series[b]), f - floor(f))


## Tengerszint (m, az 1995–2014-es átlaghoz képest) az adott évben, ha a modell eredményében van.
func _sea(group: String, yf: float) -> float:
	var sl: Variant = campaign.model.get("tengerszint", {})
	if typeof(sl) != TYPE_DICTIONARY or not sl.has(group):
		return NAN
	var series: Array = sl[group].get("kozep", [])
	return NAN if series.is_empty() else _temp(series, yf)


func _year_f() -> float:
	return lerpf(Y0, Y1, _ss(T_TITLE, T_COUNT, _t))


func _process(delta: float) -> void:
	_t += delta
	var show := _ss(T_TITLE - 0.6, T_TITLE + 1.2, _t)
	var yf := _year_f()
	var now := _temp(_plan, Y0)
	for pair in [[_g_base, _base], [_g_plan, _plan]]:
		var g = pair[0]
		g.modulate.a = show
		# csak szemléltetés: a mához képest +2 °C = teljes „hő” színezés (ugyanúgy, mint a főképernyőn)
		g.heat = clampf((_temp(pair[1], yf) - now) / 2.0, 0.0, 1.0)
		var grp := "alapeset" if g == _g_base else "terv"
		g.sea_rise = Globe.sea_rise_of(_sea(grp, Y0), _sea(grp, yf))   # veszélyeztetett partok
		# a terved hatása: a terv nélküli Földön marad a pára és a meleg városfény
		if g == _g_plan and _has_plan:
			g.set_plan_look(Globe.clean_of(campaign.model, int(yf)))
		else:
			g.set_plan_look({"smog": 1.0, "clean": 0.0, "regrow": 0.0})
		g._mat.set_shader_parameter("atmosphere", Vector3(0.39, 0.95, 0.89).lerp(Vector3(1.0, 0.50, 0.28), g.heat))
	_btn.modulate.a = _ss(T_VERDICT + 1.5, T_VERDICT + 2.5, _t)
	_btn.disabled = _t < T_VERDICT + 1.5
	if _t >= T_END + 30.0:
		_finish()
	queue_redraw()


func _verdict(t: float) -> String:
	if not _has_plan:
		return L.t("Nem volt terved. A Föld tovább melegedett.")
	if t < 1.5:
		return L.t("Másfél fok alatt maradt. Kiváló!")
	if t < 2.0:
		return L.t("Két fok alatt maradt.")
	return L.t("Két fok fölé ment.")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1600, 900)), Color(0.01, 0.015, 0.035, _ss(0.0, T_FADE, _t)))   # teljesen fedi a főképernyőt
	# „2100.”
	var ta := _ss(T_FADE, T_FADE + 0.8, _t) * (1.0 - _ss(T_TITLE - 1.0, T_TITLE - 0.2, _t))
	if ta > 0.0:
		draw_string(UI.font_bold, Vector2(0, 470), "2100.", HORIZONTAL_ALIGNMENT_CENTER, 1600, 120, Color(UI.TEXT, ta))
	var show := _ss(T_TITLE - 0.2, T_TITLE + 1.2, _t)
	if show <= 0.0:
		return
	var yf := _year_f()
	var tb := _temp(_base, yf)
	var tp := _temp(_plan, yf)
	# évszámláló középen
	draw_string(UI.font_bold, Vector2(0, 120), str(int(round(yf))), HORIZONTAL_ALIGNMENT_CENTER, 1600, 84, Color(UI.TEXT, show))
	# a két Föld felirata és hőmérséklete
	var cols := [PathStrip.temp_color(tb), PathStrip.temp_color(tp)]
	var names := [L.t("Terv nélkül"), L.t("A te Földed")]
	var temps := [tb, tp]
	var xs := [170.0, 1010.0]
	for i in 2:
		draw_string(UI.font_pixel, Vector2(xs[i], 150), names[i], HORIZONTAL_ALIGNMENT_CENTER, 420, 34,
			Color(UI.SOFT if i == 0 else UI.GOLD, show))
		draw_string(UI.font_bold, Vector2(xs[i], 660), "+%s °C" % UI.hu(temps[i], 1), HORIZONTAL_ALIGNMENT_CENTER, 420, 64, Color(cols[i], show))
		var sea := _sea("alapeset" if i == 0 else "terv", yf)
		if not is_nan(sea):   # IPCC AR6, 9.9 táblázat, a 2100-as melegedés szerint
			draw_string(UI.font_body, Vector2(xs[i], 694), L.t("a tenger %d cm-rel magasabb") % int(round(sea * 100.0)),
				HORIZONTAL_ALIGNMENT_CENTER, 420, 20, Color(Color("#7fc8f0"), show))
	# a két út középen, ahogy az évek telnek
	var gx0 := 640.0
	var gx1 := 960.0
	var gy0 := 560.0
	var gy1 := 250.0
	var tmax := 3.0
	for v in _base:
		tmax = maxf(tmax, float(v) + 0.1)
	var px := func(y: float) -> float:
		return gx0 + (y - Y0) / float(Y1 - Y0) * (gx1 - gx0)
	var py := func(t: float) -> float:
		return gy0 + (t - 1.2) / (tmax - 1.2) * (gy1 - gy0)
	for lim in [1.5, 2.0]:
		var ly: float = py.call(lim)
		draw_line(Vector2(gx0, ly), Vector2(gx1, ly), Color(1, 1, 1, 0.16 * show), 1.0)
		# a felirat a vonal jobb vége mögé kerül, hogy ne fusson rá a görbék elejére
		draw_string(UI.font_body, Vector2(gx1 + 8, ly + 5), "%s °C" % UI.hu(lim, 1 if lim < 2.0 else 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5 * show))
	var pb := PackedVector2Array()
	var pp := PackedVector2Array()
	var y := float(Y0)
	while y < yf:
		pb.append(Vector2(px.call(y), py.call(_temp(_base, y))))
		pp.append(Vector2(px.call(y), py.call(_temp(_plan, y))))
		y += 1.0
	pb.append(Vector2(px.call(yf), py.call(tb)))
	pp.append(Vector2(px.call(yf), py.call(tp)))
	if pb.size() > 1:
		draw_polyline(pb, Color(UI.EMBER, 0.9 * show), 3.0, true)
		draw_polyline(pp, Color(cols[1], show), 4.0, true)
		draw_circle(pb[-1], 5.0, Color(UI.EMBER, show))
		draw_circle(pp[-1], 6.0, Color(cols[1], show))
	draw_string(UI.font_body, Vector2(0, 596), L.t("a klímamodell szerint"), HORIZONTAL_ALIGNMENT_CENTER, 1600, 14, Color(UI.MUTE, show))
	# az ítélet
	var va := _ss(T_VERDICT, T_VERDICT + 1.5, _t)
	if va > 0.0:
		var t2100 := _temp(_plan, Y1)
		var saved := _temp(_base, Y1) - t2100
		draw_string(UI.font_pixel, Vector2(0, 740), _verdict(t2100), HORIZONTAL_ALIGNMENT_CENTER, 1600, 44,
			Color(PathStrip.temp_color(t2100) if _has_plan else UI.EMBER, va))
		if _has_plan and saved >= 0.05:
			draw_string(UI.font_body, Vector2(0, 786), L.t("A terved %s fokkal hűvösebb Földet hagyott az unokáidra.") % UI.hu(saved, 1),
				HORIZONTAL_ALIGNMENT_CENTER, 1600, 22, Color(UI.TEXT, va))
