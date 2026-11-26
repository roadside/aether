extends Button
## Kis zászló gomb a nyelvváltáshoz: kódból rajzolva (nincs képfájl). "hu" = magyar, "en" = brit zászló.

var code := "hu"
var active := false


func _init() -> void:
	custom_minimum_size = Vector2(60, 42)
	flat = true
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var w := 48.0
	var h := 30.0
	var o := ((size - Vector2(w, h)) / 2.0).round()
	var dim := 1.0 if active or is_hovered() else 0.5
	var red := Color("#ce2939") if code == "hu" else Color("#c8102e")
	var white := Color.WHITE
	if code == "hu":
		draw_rect(Rect2(o, Vector2(w, h / 3.0)), red * Color(dim, dim, dim))
		draw_rect(Rect2(o + Vector2(0, h / 3.0), Vector2(w, h / 3.0)), white * Color(dim, dim, dim))
		draw_rect(Rect2(o + Vector2(0, 2.0 * h / 3.0), Vector2(w, h / 3.0)), Color("#477050") * Color(dim, dim, dim))
	else:
		var d := Color(dim, dim, dim)
		draw_rect(Rect2(o, Vector2(w, h)), Color("#012169") * d)
		_diagonals(o, w, h, 3.0, white * d)
		_diagonals(o, w, h, 1.0, red * d)
		draw_rect(Rect2(o + Vector2(w / 2.0 - 5.0, 0), Vector2(10, h)), white * d)
		draw_rect(Rect2(o + Vector2(0, h / 2.0 - 5.0), Vector2(w, 10)), white * d)
		draw_rect(Rect2(o + Vector2(w / 2.0 - 3.0, 0), Vector2(6, h)), red * d)
		draw_rect(Rect2(o + Vector2(0, h / 2.0 - 3.0), Vector2(w, 6)), red * d)
	if active:
		draw_rect(Rect2(o - Vector2(3, 3), Vector2(w + 6, h + 6)), Color("#f4c85a"), false, 2.0)


## A két átló, a zászló téglalapjára vágva (t = a csík fél vastagsága).
func _diagonals(o: Vector2, w: float, h: float, t: float, c: Color) -> void:
	var len := sqrt(w * w + h * h)
	var a := t * len / h
	var b := t * len / w
	draw_colored_polygon(PackedVector2Array([o, o + Vector2(a, 0), o + Vector2(w, h - b), o + Vector2(w, h), o + Vector2(w - a, h), o + Vector2(0, b)]), c)
	draw_colored_polygon(PackedVector2Array([o + Vector2(w, 0), o + Vector2(w, b), o + Vector2(a, h), o + Vector2(0, h), o + Vector2(0, h - b), o + Vector2(w - a, 0)]), c)
