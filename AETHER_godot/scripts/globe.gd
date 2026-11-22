extends Control
## A földgömb: shaderes gömb + a kutatóállomások és szövetségi vonalak rajzolása.
## A shader és ez a script ugyanazt a vetítést használja, így a jelölők a helyükön maradnak.
## A Nap a VALÓDI helyén van: a gép órájából (UTC) számoljuk, hol delel éppen
## (napfordulópont alatti pont), így a nappal és az éjszaka határa, valamint az
## évszak (sarki éjszaka) a valóságot mutatja, és valós időben halad.

signal station_clicked(station: Dictionary)
signal event_clicked(event: Dictionary)

const SHADER := preload("res://shaders/globe.gdshader")

@export var pixels := 540.0          # a gömb "játékpixel"-felbontása (nagyobb = élesebb)
@export var radius_ratio := 0.86     # egyezzen a shader `radius` értékével
@export var tilt := 0.35             # a nézet szélessége (radián): + észak felé, - dél felé
const TILT_MAX := 1.45               # kb. 83 fok: a sarkok is jól láthatók
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
var zoom := 1.0                      # görgővel nagyítható ("nagyító" kör a gömb helyén)
@export var spin_speed := 0.0        # magától nem forog (egérrel forgatható); díszforgáshoz pl. 0.006
@export var real_sun := true         # a Nap valódi helyzete a pontos idő alapján
@export var cloud_speed := 0.0015

var spin := 0.12
var cloud_drift := 0.0
var time := 0.0
var stations: Array = []             # [{name, lat, lon, color, me, locked}]
var links: Array = []                # [[lat1, lon1, lat2, lon2], ...]
var events: Array = []               # valós események (world_state.py): {cim, kategoria, lat, lon, link, ...}
var heat := 0.0                      # 0 = ma; 1 = kb. +2 °C a mához képest (csak szemléltetés)
var highlight: Dictionary = {}       # a listában éppen rámutatott esemény: gyűrű jelöli
var _look_tw: Tween
var sun_lat := 0.0                   # ahol a Nap éppen merőlegesen süt (fok)
var sun_lon := 0.0
var _sun_timer := 0.0

const EVENT_COLORS := {
	"aszaly": Color("#e0a24a"), "ehezes": Color("#f07a4a"), "arviz": Color("#4aa0e0"), "vihar": Color("#9ab8ff"),
	"tuz": Color("#ff5a3a"), "jeg": Color("#cfefff"), "hoseg": Color("#ff8a3a"), "tenger": Color("#3fa8d8"), "szennyezes": Color("#b48cff"),
	"levego": Color("#c8b49a"), "uv": Color("#e8f060"), "jarvany": Color("#ff6fa0"), "vulkan": Color("#d0503a"), "foldrenges": Color("#c0a070"),
}
var dragging := false

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("albedo_map", load("res://assets/earth_albedo.png"))
	_mat.set_shader_parameter("data_map", load("res://assets/earth_data.png"))
	_mat.set_shader_parameter("night_map", load("res://assets/earth_night.png"))
	_mat.set_shader_parameter("cloud_map", load("res://assets/earth_clouds.png"))
	_mat.set_shader_parameter("pixels", pixels)
	_mat.set_shader_parameter("radius", radius_ratio)
	_mat.set_shader_parameter("tilt", tilt)
	_rect.material = _mat
	add_child(_rect)
	# a jelölők a gömb fölé rajzolódnak
	_rect.show_behind_parent = true
	# induláskor a játékos helye legyen középen
	for s in stations:
		if s.get("me", false):
			spin = float(s["lon"]) / 360.0
	_update_sun()


## Hol delel most a Nap? Egyszerűsített csillagászati képlet (Astronomical
## Almanac, alacsony pontosságú napkoordináták; hiba < 0,1 fok, bőven elég).
static func subsolar_point(unix_utc: float) -> Vector2:
	var n := unix_utc / 86400.0 - 10957.5           # napok 2000-01-01 12:00 UTC óta
	var lmean := deg_to_rad(fposmod(280.460 + 0.9856474 * n, 360.0))
	var g := deg_to_rad(fposmod(357.528 + 0.9856003 * n, 360.0))
	var lam := lmean + deg_to_rad(1.915) * sin(g) + deg_to_rad(0.020) * sin(2.0 * g)
	var eps := deg_to_rad(23.439 - 0.0000004 * n)
	var decl := asin(sin(eps) * sin(lam))
	var ra := atan2(cos(eps) * sin(lam), cos(lam))
	var gmst_deg := fposmod(280.46061837 + 360.98564736629 * n, 360.0)
	var lon := fposmod(rad_to_deg(ra) - gmst_deg + 180.0, 360.0) - 180.0
	return Vector2(rad_to_deg(decl), lon)


func _update_sun() -> void:
	if not real_sun:
		return
	var p := subsolar_point(Time.get_unix_time_from_system())
	sun_lat = p.x
	sun_lon = p.y


## A Nap iránya a képernyő terében (ugyanaz a vetítés, mint a jelölőknél).
func _sun_dir() -> Vector3:
	var lat := deg_to_rad(sun_lat)
	var o := deg_to_rad(sun_lon) - spin * TAU
	var x := cos(lat) * sin(o)
	var y2 := -sin(lat)
	var z2 := cos(lat) * cos(o)
	return Vector3(x, y2 * cos(tilt) + z2 * sin(tilt), -y2 * sin(tilt) + z2 * cos(tilt))


func _process(delta: float) -> void:
	time += delta
	if not dragging:
		spin += spin_speed * delta
	cloud_drift += cloud_speed * delta
	_mat.set_shader_parameter("spin", spin)
	_mat.set_shader_parameter("tilt", tilt)
	_mat.set_shader_parameter("zoom", zoom)
	if real_sun:
		_sun_timer -= delta
		if _sun_timer <= 0.0:
			_sun_timer = 10.0
			_update_sun()
		_mat.set_shader_parameter("sun_dir", _sun_dir())
	_mat.set_shader_parameter("cloud_drift", cloud_drift)
	_mat.set_shader_parameter("heat", heat)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# egérrel forgatható
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		home()   # dupla kattintás: vissza a saját helyedre, nagyítás nélkül
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if event.pressed:
			var hit := _station_at(event.position)
			if not hit.is_empty():
				station_clicked.emit(hit)
			else:
				var ev := _event_at(event.position)
				if not ev.is_empty():
					event_clicked.emit(ev)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var f := 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
		zoom = clampf(zoom * f, ZOOM_MIN, ZOOM_MAX)
		accept_event()
	elif event is InputEventMouseMotion and not dragging:
		# rámutatáskor kéz-kurzor az eseményeken és az állomáson (kattintható)
		var over := not _event_at(event.position).is_empty() or not _station_at(event.position).is_empty()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
	elif event is InputEventMouseMotion and dragging:
		# vízszintesen: forgatás a tengely körül; függőlegesen: észak-dél billentés.
		# Nagyításkor lassabban mozog, hogy pontosan lehessen célozni.
		var k := PI * zoom
		spin -= event.relative.x / (size.x * k)
		tilt = clampf(tilt + event.relative.y / (size.y * k) * PI, -TILT_MAX, TILT_MAX)


## Vissza a kiinduló nézetbe: a játékos helye középen, nagyítás nélkül (finom átmenettel).
func home() -> void:
	var target_spin := spin
	for s in stations:
		if s.get("me", false):
			target_spin = float(s["lon"]) / 360.0
	# a legrövidebb úton forduljon
	target_spin = spin + wrapf(target_spin - spin, -0.5, 0.5)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(true)
	tw.tween_property(self, "spin", target_spin, 0.6)
	tw.tween_property(self, "tilt", 0.35, 0.6)
	tw.tween_property(self, "zoom", 1.0, 0.6)


## Lassan odafordul, hogy az esemény a gömb közepe felé kerüljön (a nagyítás marad).
func look_at_event(e: Dictionary) -> void:
	if e.get("lat") == null or e.get("lon") == null or dragging:
		return
	var target_spin := spin + wrapf(float(e["lon"]) / 360.0 - spin, -0.5, 0.5)
	var target_tilt := clampf(deg_to_rad(float(e["lat"])) * 0.8, -TILT_MAX, TILT_MAX)
	if _look_tw != null and _look_tw.is_valid():
		_look_tw.kill()
	_look_tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tw.set_parallel(true)
	_look_tw.tween_property(self, "spin", target_spin, 0.7)
	_look_tw.tween_property(self, "tilt", target_tilt, 0.7)


## Rámutatáskor kis felirat: mi ez az esemény (vagy az állomás neve).
func _get_tooltip(at_position: Vector2) -> String:
	var s := _station_at(at_position)
	if not s.is_empty():
		return str(s.get("name", ""))
	var e := _event_at(at_position)
	if e.is_empty():
		return ""
	var t := str(e.get("cim", ""))
	var place := str(e.get("orszag_hu", e.get("orszag", "")))
	return t + ("\n" + place if place != "" and not t.contains(place) else "")


## Földrajzi pont -> képernyőpont. Visszaad: Vector3(x, y, látható? 1 : 0)
func project(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var o := deg_to_rad(lon_deg) - spin * TAU
	var x := cos(lat) * sin(o)
	var y2 := -sin(lat)
	var z2 := cos(lat) * cos(o)
	var ct := cos(tilt)
	var st := sin(tilt)
	var ny := y2 * ct + z2 * st
	var nz := -y2 * st + z2 * ct
	var r := size.x * 0.5 * radius_ratio * zoom
	var px := size.x / pixels                      # egy játékpixel mérete
	var c := size * 0.5
	var sx := snappedf(c.x + x * r, px)
	var sy := snappedf(c.y + ny * r, px)
	# nagyításkor csak a "nagyító" körén belüli pont látszik
	var in_lens := zoom <= 1.0 or Vector2(sx, sy).distance_to(c) < size.x * 0.5 * 0.985
	return Vector3(sx, sy, 1.0 if nz > 0.04 and in_lens else 0.0)


func _draw() -> void:
	var px := size.x / pixels
	# szövetségi vonalak: pontozott, futó fénnyel
	for l in links:
		var a := _vec(l[0], l[1])
		var b := _vec(l[2], l[3])
		for i in 121:
			var u := i / 120.0
			var v := a.lerp(b, u).normalized()
			var lat := rad_to_deg(asin(v.y))
			var lon := rad_to_deg(atan2(v.z, v.x))
			var p := project(lat, lon)
			if p.z < 0.5:
				continue
			var lift := 1.0 + sin(u * PI) * 0.14
			var c := size * 0.5
			var q := c + (Vector2(p.x, p.y) - c) * lift
			var on := (i + int(time * 6.0)) % 6 < 3
			draw_rect(Rect2(q.snapped(Vector2(px, px)), Vector2(px, px)), Color(0.39, 0.95, 0.89, 0.95 if on else 0.25))
	# valós események: kis, pulzáló pixel-jelölők
	var pulse := 0.6 + 0.4 * sin(time * 3.0)
	for e in events:
		if e.get("lat") == null or e.get("lon") == null:
			continue
		var pe := project(float(e["lat"]), float(e["lon"]))
		if pe.z < 0.5:
			continue
		var ec: Color = EVENT_COLORS.get(str(e.get("kategoria", "")), Color("#d8d8d8"))
		var big := 2 if str(e.get("szint", "")) in ["orange", "red"] else 1
		var center := Vector2(pe.x, pe.y)
		draw_rect(Rect2(center - Vector2(big + 1, big + 1) * px, Vector2(2 * big + 3, 2 * big + 3) * px), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(center - Vector2(big, big) * px, Vector2(2 * big + 1, 2 * big + 1) * px), Color(ec, pulse))
	# a listában kijelölt esemény: pixeles, lüktető gyűrű
	if not highlight.is_empty() and highlight.get("lat") != null and highlight.get("lon") != null:
		var ph := project(float(highlight["lat"]), float(highlight["lon"]))
		if ph.z > 0.5:
			var hc := Vector2(ph.x, ph.y)
			var rad := (10.0 + 2.5 * sin(time * 5.0)) * px
			for k in 36:
				var a := TAU * k / 36.0
				var q := (hc + Vector2(cos(a), sin(a)) * rad).snapped(Vector2(px, px))
				draw_rect(Rect2(q, Vector2(px, px)), Color(1.0, 0.85, 0.35, 0.95))
	# állomások: fényoszlop + gyémánt
	for s in stations:
		var p := project(s.lat, s.lon)
		if p.z < 0.5:
			continue
		var col: Color = s.color
		var pos := Vector2(p.x, p.y)
		var beam := 22 if s.get("me", false) else 12
		for j in beam:
			draw_rect(Rect2(pos + Vector2(0, -j * px), Vector2(px, px)), Color(col, 0.55 * (1.0 - float(j) / beam)))
		for off in [Vector2(0, -3), Vector2(-1, -2), Vector2(0, -2), Vector2(1, -2), Vector2(-2, -1), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(2, -1),
				Vector2(-3, 0), Vector2(-2, 0), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0),
				Vector2(-2, 1), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(-1, 2), Vector2(0, 2), Vector2(1, 2), Vector2(0, 3)]:
			var edge: bool = abs(off.x) + abs(off.y) == 3
			var cc := Color.WHITE if off == Vector2.ZERO else (col.darkened(0.4) if edge else col)
			draw_rect(Rect2(pos + off * px, Vector2(px, px)), cc)
		if s.get("locked", false):
			draw_rect(Rect2(pos + Vector2(-2, -8) * px, Vector2(5, 3) * px), Color(0.67, 0.67, 0.67))


func _vec(lat_deg: float, lon_deg: float) -> Vector3:
	var a := deg_to_rad(lat_deg)
	var o := deg_to_rad(lon_deg)
	return Vector3(cos(a) * cos(o), sin(a), cos(a) * sin(o))


func _event_at(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 12.0
	for e in events:
		if e.get("lat") == null or e.get("lon") == null:
			continue
		var p := project(float(e["lat"]), float(e["lon"]))
		var d := pos.distance_to(Vector2(p.x, p.y))
		if p.z > 0.5 and d < best_d:
			best_d = d
			best = e
	return best


func _station_at(pos: Vector2) -> Dictionary:
	for s in stations:
		var p := project(s.lat, s.lon)
		if p.z > 0.5 and pos.distance_to(Vector2(p.x, p.y)) < 14.0:
			return s
	return {}
