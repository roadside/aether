extends Control
## A melegedés görbéje 2100-ig: a múlt (fehér), a te jövőd sávja (zöld) és „ha semmi sem változik” (narancs).

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Y0 := 2024.0
const Y1 := 2100.0
const T0 := 1.0
const T1 := 3.6

var _hist: Array = []
var _base: Array = []
var _fc: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(300, 86)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(history: Array, base_history: Array, forecast: Dictionary) -> void:
	_hist = history
	_base = base_history
	_fc = forecast
	queue_redraw()


func _pt(y: float, t: float) -> Vector2:
	var w := size.x - 96.0
	return Vector2(40.0 + w * (y - Y0) / (Y1 - Y0), size.y - 4.0 - (size.y - 10.0) * (clampf(t, T0, T1) - T0) / (T1 - T0))


func _line(rows: Array, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for r in rows:
		pts.append(_pt(float(r[0]), float(r[1])))
	if pts.size() >= 2:
		draw_polyline(pts, color, width, true)


func _draw() -> void:
	var f := UI.font_body
	draw_rect(Rect2(Vector2(40, 0), Vector2(size.x - 96.0, size.y)), Color(0.03, 0.05, 0.1, 0.6))
	for t in [1.5, 2.0, 3.0]:
		var a := _pt(Y0, t)
		draw_line(a, _pt(Y1, t), Color(1, 1, 1, 0.14), 1.0)
		draw_string(f, Vector2(0, a.y + 5), "+" + L.num_short(t, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	if _hist.is_empty():
		return
	# „ha semmi sem változik”: a már eltelt rész és a folytatása
	var base_rows: Array = _base.duplicate()
	base_rows.append_array(_fc.get("alap", []))
	_line(base_rows, Color(UI.EMBER, 0.75), 2.0)
	# a te jövőd sávja
	var lo: Array = _fc.get("also", [])
	var hi: Array = _fc.get("felso", [])
	if lo.size() >= 2 and hi.size() == lo.size():
		for i in lo.size() - 1:
			var q := PackedVector2Array([_pt(float(lo[i][0]), float(lo[i][1])), _pt(float(lo[i + 1][0]), float(lo[i + 1][1])),
				_pt(float(hi[i + 1][0]), float(hi[i + 1][1])), _pt(float(hi[i][0]), float(hi[i][1]))])
			if absf(q[0].y - q[3].y) + absf(q[1].y - q[2].y) > 0.6:
				draw_colored_polygon(q, Color(UI.GREEN, 0.22))
	_line(_fc.get("kozep", []), UI.GREEN, 2.0)
	_line(_hist, Color.WHITE, 3.0)
	var now: Array = _hist[-1]
	draw_circle(_pt(float(now[0]), float(now[1])), 4.5, Color.WHITE)
	var x := size.x - 52.0
	if not lo.is_empty():
		var mid: Array = _fc.get("kozep", lo)
		draw_string(UI.font_bold, Vector2(x, _pt(Y1, float(mid[-1][1])).y + 5), "+" + L.num(float(mid[-1][1]), 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.GREEN)
	if not base_rows.is_empty():
		var by := _pt(Y1, float(base_rows[-1][1])).y + 5
		draw_string(UI.font_bold, Vector2(x, by), "+" + L.num(float(base_rows[-1][1]), 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.EMBER)
	draw_string(f, Vector2(40, size.y + 13), "2026", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	draw_string(f, Vector2(size.x - 86.0, size.y + 13), "2100", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
