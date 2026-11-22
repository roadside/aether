extends Control
## Hőmérséklet-görbe: alapeset (narancs) és a játékos terve (türkiz),
## mindkettő bizonytalansági sávval. Kattintással / húzással évet választ.

signal year_changed(year: int)

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")

var data: Dictionary = {}
var year := 2050
var now_year := 0              # a játék aktuális éve (0 = nincs jelölve)
var _t_min := 1.0
var _t_max := 3.5
const PAD_L := 54.0
const PAD_R := 16.0
const PAD_T := 14.0
const PAD_B := 30.0


func _ready() -> void:
	UI.load_fonts()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 230)


func set_data(d: Dictionary) -> void:
	data = d
	var lo := 99.0
	var hi := -99.0
	for key in ["terv", "alapeset"]:
		for e in ["alacsony", "kozep", "magas"]:
			var arr: Array = d[key][e]["homerseklet"]
			for t in arr:
				lo = min(lo, float(t))
				hi = max(hi, float(t))
	_t_min = floor(min(lo, 1.0) * 2.0) / 2.0
	_t_max = ceil(max(hi, 2.0) * 2.0) / 2.0
	queue_redraw()


func _years() -> Array:
	# A JSON számok float-ként jönnek; int-re alakítva működik a find(év).
	var out: Array = []
	for y in data.get("evek", []):
		out.append(int(y))
	return out


func _pt(i: int, t: float) -> Vector2:
	var n: int = max(1, _years().size() - 1)
	var w := size.x - PAD_L - PAD_R
	var h := size.y - PAD_T - PAD_B
	return Vector2(PAD_L + w * i / float(n), PAD_T + h * (1.0 - (t - _t_min) / (_t_max - _t_min)))


func _band(key: String, col: Color) -> void:
	var lo: Array = data[key]["alacsony"]["homerseklet"]
	var hi: Array = data[key]["magas"]["homerseklet"]
	var mid: Array = data[key]["kozep"]["homerseklet"]
	var poly := PackedVector2Array()
	for i in hi.size():
		poly.append(_pt(i, float(hi[i])))
	for i in range(lo.size() - 1, -1, -1):
		poly.append(_pt(i, float(lo[i])))
	draw_colored_polygon(poly, Color(col, 0.18))
	var line := PackedVector2Array()
	for i in mid.size():
		line.append(_pt(i, float(mid[i])))
	draw_polyline(line, col, 3.0, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.09, 0.9))
	if data.is_empty():
		return
	var f: Font = UI.font_body
	# rácsvonalak fokonként
	var t := _t_min
	while t <= _t_max + 0.001:
		var y := _pt(0, t).y
		var special := is_equal_approx(t, 1.5) or is_equal_approx(t, 2.0)
		draw_line(Vector2(PAD_L, y), Vector2(size.x - PAD_R, y), Color(1, 1, 1, 0.22 if special else 0.07), 1.0)
		draw_string(f, Vector2(4, y + 5), UI.hu(t, 1) + " °C", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.MUTE)
		t += 0.5
	var ys := _years()
	for yr in [2025, 2050, 2075, 2100]:
		var i := ys.find(yr)
		if i >= 0:
			var p := _pt(i, _t_min)
			draw_string(f, Vector2(p.x - 16, size.y - 8), str(yr), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.MUTE)
	_band("alapeset", UI.EMBER)
	_band("terv", UI.CYAN)
	# a játék jelenlegi éve: előtte a múlt (már nem változtatható)
	var ni := ys.find(now_year)
	if ni >= 0:
		var nx := _pt(ni, _t_min).x
		draw_rect(Rect2(PAD_L, PAD_T, nx - PAD_L, size.y - PAD_T - PAD_B), Color(1, 1, 1, 0.05))
		draw_line(Vector2(nx, PAD_T), Vector2(nx, size.y - PAD_B), Color(UI.TEXT, 0.6), 1.0)
		draw_string(f, Vector2(nx + 4, size.y - PAD_B - 6), L.t("most"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.SOFT)
	# kiválasztott év
	var yi := ys.find(year)
	if yi >= 0:
		var x := _pt(yi, _t_min).x
		draw_line(Vector2(x, PAD_T), Vector2(x, size.y - PAD_B), Color(UI.GOLD, 0.9), 2.0)
		var tv: float = data["terv"]["kozep"]["homerseklet"][yi]
		draw_circle(_pt(yi, tv), 5.0, UI.GOLD)
	# jelmagyarázat
	draw_rect(Rect2(PAD_L + 10, PAD_T + 4, 14, 4), UI.EMBER)
	draw_string(f, Vector2(PAD_L + 30, PAD_T + 11), L.t("Ha semmi sem változik"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)
	draw_rect(Rect2(PAD_L + 10, PAD_T + 22, 14, 4), UI.CYAN)
	draw_string(f, Vector2(PAD_L + 30, PAD_T + 29), L.t("A te terved (a sáv: ennyivel tévedhet a modell)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var drag: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if (pressed or drag) and not data.is_empty():
		var ys := _years()
		var w := size.x - PAD_L - PAD_R
		var u := clampf((event.position.x - PAD_L) / w, 0.0, 1.0)
		var i := int(round(u * (ys.size() - 1)))
		set_year(int(ys[i]))
		year_changed.emit(year)


func set_year(y: int) -> void:
	year = y
	queue_redraw()


## A terv középső becslése egy adott évre (°C).
func temp_at(y: int) -> float:
	var i := _years().find(y)
	if i < 0:
		return 0.0
	return float(data["terv"]["kozep"]["homerseklet"][i])
