extends Control
## Rámutatós bemutató: a képernyő elsötétül, egyszerre egy rész világít, mellette egy rövid
## mondat és a „Tovább” gomb. Bármikor átugorható (Esc). A lépéseket a főképernyő adja:
## [{"rect": Callable -> Rect2, "cim": String, "szoveg": String}, ...]

signal finished

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")

var steps: Array = []
var index := 0
var _rect := Rect2()
var _target := Rect2()
var _bubble: PanelContainer
var _pulse := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_parent_area_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	_show_step(true)


func _process(delta: float) -> void:
	_pulse += delta
	_rect = Rect2(_rect.position.lerp(_target.position, minf(1.0, delta * 9.0)),
		_rect.size.lerp(_target.size, minf(1.0, delta * 9.0)))
	queue_redraw()


func _draw() -> void:
	var full := get_rect().size
	var dark := Color(0.0, 0.0, 0.03, 0.80)
	var r := _rect
	draw_rect(Rect2(0, 0, full.x, r.position.y), dark)
	draw_rect(Rect2(0, r.end.y, full.x, full.y - r.end.y), dark)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dark)
	draw_rect(Rect2(r.end.x, r.position.y, full.x - r.end.x, r.size.y), dark)
	var glow := 0.65 + 0.35 * sin(_pulse * 3.0)
	draw_rect(r.grow(3), Color(UI.CYAN, glow), false, 3.0)
	draw_rect(r.grow(8), Color(UI.CYAN, glow * 0.25), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_end()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_RIGHT]:
			_next()
		elif event.keycode == KEY_LEFT and index > 0:
			index -= 1
			_show_step()
		accept_event()


func _next() -> void:
	index += 1
	if index >= steps.size():
		_end()
	else:
		_show_step()


func _end() -> void:
	finished.emit()
	queue_free()


func _show_step(first: bool = false) -> void:
	var st: Dictionary = steps[index]
	_target = (st["rect"] as Callable).call()
	_target = _target.grow(6).intersection(Rect2(Vector2(4, 4), get_rect().size - Vector2(8, 8)))
	if first:
		_rect = _target
	if _bubble != null:
		_bubble.queue_free()
	_bubble = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.CYAN
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 20
	sb.set_content_margin_all(22)
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.custom_minimum_size = Vector2(430, 0)
	var v := UI.vbox(12)
	_bubble.add_child(v)
	v.add_child(UI.label(L.t(st["cim"]), 24, UI.GOLD, true))
	v.add_child(UI.label(L.t(st["szoveg"]), 19, UI.TEXT))
	var row := UI.hbox(14)
	var dots := ""
	for i in steps.size():
		dots += "●" if i == index else "○"
	var d := UI.label(dots, 16, UI.MUTE, false, false)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(d)
	if index < steps.size() - 1:
		var skip := Button.new()
		skip.flat = true
		skip.text = L.t("Átugrom")
		skip.focus_mode = Control.FOCUS_NONE
		skip.add_theme_font_size_override("font_size", 16)
		skip.add_theme_color_override("font_color", UI.MUTE)
		skip.pressed.connect(_end)
		row.add_child(skip)
	var go := UI.button(L.t("Tovább →") if index < steps.size() - 1 else L.t("Kezdjük!"), true)
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(_next)
	row.add_child(go)
	v.add_child(row)
	add_child(_bubble)
	_place_bubble.call_deferred()


## A buborék oda kerül, ahol a kiemelt rész mellett a legtöbb hely van.
func _place_bubble() -> void:
	if _bubble == null:
		return
	var full := get_rect().size
	var s := _bubble.get_combined_minimum_size()
	_bubble.size = s
	var t := _target
	var gap := 22.0
	var pos := Vector2.ZERO
	var room := {"lent": full.y - t.end.y, "fent": t.position.y, "jobb": full.x - t.end.x, "bal": t.position.x}
	if room["jobb"] >= s.x + gap * 2:
		pos = Vector2(t.end.x + gap, t.get_center().y - s.y / 2)
	elif room["bal"] >= s.x + gap * 2:
		pos = Vector2(t.position.x - gap - s.x, t.get_center().y - s.y / 2)
	elif room["lent"] >= s.y + gap * 2:
		pos = Vector2(t.get_center().x - s.x / 2, t.end.y + gap)
	else:
		pos = Vector2(t.get_center().x - s.x / 2, t.position.y - gap - s.y)
	pos.x = clampf(pos.x, 12, full.x - s.x - 12)
	pos.y = clampf(pos.y, 12, full.y - s.y - 12)
	_bubble.position = pos
