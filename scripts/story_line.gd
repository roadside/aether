extends Control
## A játék története egyetlen képen: a hőmérséklet útja 2026-tól 2100-ig, alatta jelek a fontos
## pillanatokról (pont = vállalás, védelem, kivonás; csillag = elért nulla; háromszög = baj, megingás, küszöb).
## Megnyitáskor újrajátssza az éveket; utána az egér alatti jel szövege látszik.

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Y0 := 2026.0
const Y1 := 2100.0
const X0 := 46.0
const TOP := 14.0
const CHART_H := 132.0
const LANE_Y := [172.0, 216.0, 246.0]     # jó lépések, elért nulla, bajok
const STEP := 12.5
const PER_ROW := 4
const REPLAY_S := 6.0

var _events: Array = []       # [{"ev", "szoveg", "szin", "jel", "sav"}] + számolt "pos"
var _own: Array = []          # [[év, T]]
var _base: Array = []
var _lo := 1.2
var _hi := 3.0
var _t := 0.0
var _done := false
var _hover := -1
var _end := Y1          # eddig tart a történet (játék közben a mostani év)
var _dur := REPLAY_S
var hint := ""


func _init() -> void:
	custom_minimum_size = Vector2(840, 312)
	mouse_filter = Control.MOUSE_FILTER_PASS


## events: [{"ev": év, "szoveg": sor, "szin": Color, "jel": Color, "sav": 0 | 1 | 2}]
func setup(events: Array, own: Array, base: Array, instant: bool) -> void:
	_events = events.duplicate(true)
	_own = own
	_base = base
	_hi = 1.6
	for r in own + base:
		_hi = maxf(_hi, float(r[1]) + 0.12)
		_lo = minf(_lo, float(r[1]) - 0.08)
	_end = clampf(float(own[-1][0]) if not own.is_empty() else Y1, Y0 + 5.0, Y1)
	_dur = maxf(1.5, REPLAY_S * (_end - Y0) / (Y1 - Y0))
	_done = instant
	_t = _dur if instant else 0.0
	set_process(not instant)
	_place()
	queue_redraw()


func _ready() -> void:
	resized.connect(func() -> void:
		_place()
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw())


func _w() -> float:
	return maxf(200.0, size.x - X0 - 56.0)


func _x(y: float) -> float:
	return X0 + _w() * (y - Y0) / (Y1 - Y0)


func _pt(y: float, t: float) -> Vector2:
	return Vector2(_x(maxf(y, Y0)), TOP + CHART_H * (1.0 - (t - _lo) / (_hi - _lo)))


## A jelek helye: egy körön (öt éven) belül egymás mellé, ha sok van, új sorba kerülnek.
func _place() -> void:
	var count := {}
	for e in _events:
		var slot := int((float(e["ev"]) - Y0) / 5.0)
		var key := "%d/%d" % [int(e["sav"]), slot]
		var k := int(count.get(key, 0))
		count[key] = k + 1
		e["pos"] = Vector2(_x(Y0 + slot * 5.0) + 7.0 + (k % PER_ROW) * STEP, float(LANE_Y[int(e["sav"])]) + (k / PER_ROW) * STEP)


func _year_now() -> float:
	return Y0 + (_end - Y0) * clampf(_t / _dur, 0.0, 1.0)


## Csak akkor indul a visszajátszás, amikor a kép már látszik (hosszú ablakban le kell hozzá görgetni).
func _seen() -> bool:
	var p := get_parent()
	while p != null:
		if p is ScrollContainer:
			return global_position.y + 100.0 < (p as Control).global_position.y + (p as Control).size.y
		p = p.get_parent()
	return true


func _process(delta: float) -> void:
	if _t <= 0.0 and not _seen():
		return
	_t += delta
	if _t >= _dur + 0.3:
		_done = true
		set_process(false)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and not _done:      # kattintásra a visszajátszás a végére ugrik
		_t = _dur + 0.3
		_done = true
		set_process(false)
		queue_redraw()
	if ev is InputEventMouseMotion and _done:
		var best := -1
		var bd := 9.0
		for i in _events.size():
			var d: float = (_events[i]["pos"] as Vector2).distance_to(ev.position)
			if d < bd:
				bd = d
				best = i
		if best != _hover:
			_hover = best
			queue_redraw()


func _curve(rows: Array, until: float, color: Color, width: float) -> Vector2:
	var pts := PackedVector2Array()
	var last := Vector2.ZERO
	for i in rows.size():
		var y := float(rows[i][0])
		if y <= until:
			last = _pt(y, float(rows[i][1]))
			pts.append(last)
		elif i > 0:
			var y_prev := float(rows[i - 1][0])
			var f := (until - y_prev) / maxf(0.001, y - y_prev)
			last = _pt(until, lerpf(float(rows[i - 1][1]), float(rows[i][1]), f))
			pts.append(last)
			break
	if pts.size() >= 2:
		draw_polyline(pts, color, width, true)
	return last


func _mark(e: Dictionary, s: float, hot: bool) -> void:
	var c: Vector2 = e["pos"]
	var col: Color = e["jel"]
	match int(e["sav"]):
		1:
			var star := PackedVector2Array()
			for i in 10:
				var r := (6.5 if i % 2 == 0 else 2.8) * s
				star.append(c + Vector2(sin(i * PI / 5.0), -cos(i * PI / 5.0)) * r)
			draw_colored_polygon(star, col)
		2:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5.5) * s, c + Vector2(5.5, 4.5) * s, c + Vector2(-5.5, 4.5) * s]), col)
		_:
			draw_circle(c, 5.0 * s, col)
	if hot:
		draw_arc(c, 8.5, 0.0, TAU, 20, Color.WHITE, 1.5, true)


func _draw() -> void:
	var f := UI.font_body
	var now := _year_now()
	draw_rect(Rect2(X0, TOP, _w(), CHART_H), Color(0.09, 0.13, 0.22, 0.7))
	for yy in [2026, 2050, 2075, 2100]:
		var x := _x(float(yy))
		draw_line(Vector2(x, TOP), Vector2(x, 284.0), Color(1, 1, 1, 0.08), 1.0)
		draw_string(f, Vector2(x - 15.0, TOP + CHART_H + 15.0), str(yy), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	for tt in [1.5, 2.0, 2.5, 3.0]:
		if tt > _lo and tt < _hi:
			var yl := _pt(Y0, tt).y
			draw_line(Vector2(X0, yl), Vector2(X0 + _w(), yl), Color(1, 1, 1, 0.1), 1.0)
			draw_string(f, Vector2(4, yl + 4.0), "+" + L.num_short(tt, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTE)
	var end_b := _curve(_base, now, UI.EMBER, 1.5)
	var end_o := _curve(_own, now, UI.GREEN, 2.5)
	if not _own.is_empty():
		draw_circle(end_o, 4.0, Color.WHITE)
	if _done and not _own.is_empty() and not _base.is_empty():
		var yo := end_o.y + 5.0
		var yb := end_b.y + 5.0
		if absf(yo - yb) < 14.0:
			yb = yo - 14.0
		draw_string(f, Vector2(end_o.x + 8.0, yo), "+" + L.num(float(_own[-1][1]), 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.GREEN)
		draw_string(f, Vector2(end_b.x + 8.0, yb), "+" + L.num(float(_base[-1][1]), 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.EMBER)
	if not _done:
		draw_line(Vector2(_x(now), TOP), Vector2(_x(now), 284.0), Color(1, 1, 1, 0.35), 1.0)
	var per_year := _dur / (_end - Y0)
	var latest := -1
	for i in _events.size():
		var e: Dictionary = _events[i]
		var age := (now - float(e["ev"])) * per_year
		if age < 0.0 and not _done:
			continue
		latest = i
		var s := 1.0 if _done or age > 0.3 else 1.0 + 0.9 * (1.0 - age / 0.3)
		_mark(e, s, i == _hover)
	var show := _hover if _done else latest
	if show >= 0:
		var e2: Dictionary = _events[show]
		draw_string(f, Vector2(X0, 306.0), "%d · %s" % [int(e2["ev"]), str(e2["szoveg"])], HORIZONTAL_ALIGNMENT_LEFT, size.x - X0, 16, e2["szin"])
	elif _done and hint != "":
		draw_string(f, Vector2(X0, 306.0), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - X0, 15, UI.MUTE)
