extends Control
## Egy országcsoport kibocsátásának útja mostantól 2100-ig (a mai szint = 100%):
## zöld = a mostani vállalásuk szerint, cián = ha azt vállalják, amit éppen kérsz.

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Y0 := 2026.0
const Y1 := 2100.0

var _now: Array = []       # [[év, arány]]
var _ask: Array = []
var legend_now := "a mostani útjuk"     # a zöld vonal felirata (a záró képernyőn: a világ útja)


func _init() -> void:
	custom_minimum_size = Vector2(380, 74)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_paths(now_rows: Array, ask_rows: Array) -> void:
	_now = now_rows
	_ask = ask_rows
	queue_redraw()


func _pt(y: float, f: float) -> Vector2:
	var w := size.x - 46.0
	return Vector2(40.0 + w * (y - Y0) / (Y1 - Y0), 16.0 + (size.y - 30.0) * (1.0 - clampf(f, 0.0, 1.0)))


func _line(rows: Array, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for r in rows:
		pts.append(_pt(float(r[0]), float(r[1])))
	if pts.size() >= 2:
		draw_polyline(pts, color, width, true)


func _draw() -> void:
	var f := UI.font_body
	draw_rect(Rect2(_pt(Y0, 1.0), _pt(Y1, 0.0) - _pt(Y0, 1.0)), Color(0.03, 0.05, 0.1, 0.6))
	draw_line(_pt(Y0, 0.0), _pt(Y1, 0.0), Color(1, 1, 1, 0.25), 1.0)
	draw_string(f, Vector2(0, _pt(Y0, 1.0).y + 9), "100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	draw_string(f, Vector2(14, _pt(Y0, 0.0).y + 4), "0%", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	draw_string(f, Vector2(40, size.y), "2026", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	draw_string(f, Vector2(size.x - 34.0, size.y), "2100", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	var lx := 40.0
	for row in [[L.t(legend_now), UI.GREEN, true], [L.t("ha ezt vállalják"), UI.CYAN, not _ask.is_empty()]]:
		if not row[2]:
			continue
		draw_rect(Rect2(lx, 3, 14, 3), row[1])
		draw_string(f, Vector2(lx + 19, 9), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.SOFT)
		lx += 32.0 + f.get_string_size(row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_line(_now, UI.GREEN, 2.0)
	_line(_ask, UI.CYAN, 2.5)
	if not _now.is_empty():
		draw_circle(_pt(float(_now[0][0]), float(_now[0][1])), 4.0, Color.WHITE)
