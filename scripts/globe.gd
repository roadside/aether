extends Control
## A földgömb: shaderes gömb + a kutatóállomások és szövetségi vonalak rajzolása.
## A shader és ez a script ugyanazt a vetítést használja, így a jelölők a helyükön maradnak.
## A Nap a VALÓDI helyén van: a gép órájából (UTC) számoljuk, hol delel éppen
## (napfordulópont alatti pont), így a nappal és az éjszaka határa, valamint az
## évszak (sarki éjszaka) a valóságot mutatja, és valós időben halad.

signal station_clicked(station: Dictionary)
signal event_clicked(event: Dictionary)

const SHADER := preload("res://shaders/globe.gdshader")
const FX_SHADER := preload("res://shaders/fx.gdshader")

@export var pixels := 540.0          # a gömb "játékpixel"-felbontása (nagyobb = élesebb)
@export var radius_ratio := 0.86     # egyezzen a shader `radius` értékével
@export var tilt := 0.35             # a nézet szélessége (radián): + észak felé, - dél felé
const TILT_MAX := 1.45               # kb. 83 fok: a sarkok is jól láthatók
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
var zoom := 1.0                      # görgővel nagyítható ("nagyító" kör a gömb helyén)
@export var spin_speed := 0.0        # magától nem forog (egérrel forgatható); díszforgáshoz pl. 0.006
var fixed_sun := false               # a Nap mindig a néző felől süt (játéktábla-nézet)
@export var real_sun := true         # a Nap valódi helyzete a pontos idő alapján
@export var cloud_speed := 0.0035

var spin := 0.12
## Élő Föld: lassú ringás (a spin értékét nem írja át, csak a képet), repülők a csoportok között.
var alive := true
const SWAY := 0.018                  # fordulat (kb. 6,5 fok) jobbra-balra
var _sway_k := 1.0                   # forgatás közben elhal, utána lassan visszatér


func _spin_now() -> float:
	return spin + (sin(time * 0.21) * SWAY * _sway_k if alive else 0.0)

var cloud_drift := 0.0
var time := 0.0
var flashes: Array = []             # felvillanó gyűrűk: [{"lat", "lon", "color", "t0"}] (egyezségnél)
var storms: Array = []              # fenyegető vagy lecsapó baj: [{"lat", "lon", "kind", "strong"}] – kódból rajzolt, mozgó jel
var stations: Array = []             # [{name, lat, lon, color, me, locked}]
var links: Array = []                # [[lat1, lon1, lat2, lon2], ...]
var events: Array = []               # valós események (world_state.py): {cim, kategoria, lat, lon, link, ...}
## Tengerszint-emelkedés (0–1): a veszélyeztetett alacsony partvidékek (a mai tengerszint fölött
## legfeljebb 10 m, NOAA ETOPO1) figyelmeztető csíkozást kapnak, ami ezzel erősödik. Nem víz alá kerülést
## jelent, hanem: „alacsony part, itt a legnagyobb a veszély”. Lásd a shadert.
var sea_rise := 0.0
## A kiemelés léptéke: ennyi méter emelkedés (a mához képest) = teljes erősségű figyelmeztetés.
const SEA_FULL_M := 0.8


## A modell tengerszint-sorából (méter) a sea_rise érték: a mához képesti emelkedés / SEA_FULL_M.
static func sea_rise_of(meters_now: float, meters_then: float) -> float:
	if is_nan(meters_now) or is_nan(meters_then):
		return 0.0
	return clampf((meters_then - meters_now) / SEA_FULL_M, 0.0, 1.0)


## A terved hatása a gömbön (csak szemléltetés, a modell nettó CO2-sorából):
## smog: pára a lakott vidékek fölött, a mai kibocsátáshoz mérten (1 = mai szint, 0 = nulla);
## clean: a városfény a narancsos mai energiától a tiszta, hideg fényig (0 = ma, 1 = nulla kibocsátás);
## regrow: nettó CO2-kivonásnál (negatív kibocsátás) a növényzet visszazöldül (0–1).
var smog := 0.0
var ash := 0.0                       # vulkáni fátyol célértéke (0–1); a kép lassan közelít hozzá
var _ash_shown := 0.0
var clean := 0.0
var regrow := 0.0
## A nettó kivonás léptéke: ha a világ a mai kibocsátás ennyiszeresét vonja ki évente, teljes a zöldülés.
const REGROW_FULL := 0.25


## {"smog", "clean", "regrow"} az adott évre a modell eredményéből (model["terv"]["kozep"]["netto_co2"]).
## Ha nincs terv-sor (pl. terv nélküli alapeset), a mai állapot: pára van, a fény meleg.
static func clean_of(model: Dictionary, year: int) -> Dictionary:
	var out := {"smog": 1.0, "clean": 0.0, "regrow": 0.0}
	var ys: Array = model.get("evek", [])
	var t: Variant = model.get("terv", {})
	if typeof(t) != TYPE_DICTIONARY or not t.has("kozep"):
		return out
	var co2: Array = Dictionary(t["kozep"]).get("netto_co2", [])
	if co2.is_empty() or ys.is_empty():
		return out
	var base := float(co2[0])
	if base <= 0.0:
		return out
	var v := base
	for i in mini(ys.size(), co2.size()):
		if int(ys[i]) <= year:
			v = float(co2[i])
	var ratio := v / base
	out["smog"] = clampf(ratio, 0.0, 1.0)
	out["clean"] = clampf(1.0 - ratio, 0.0, 1.0)
	out["regrow"] = clampf(-ratio / REGROW_FULL, 0.0, 1.0)
	return out


## Egy lépésben beállítja a három értéket (clean_of eredményéből).
func set_plan_look(d: Dictionary) -> void:
	smog = float(d.get("smog", 0.0))
	clean = float(d.get("clean", 0.0))
	regrow = float(d.get("regrow", 0.0))
var heat := 0.0                      # 0 = ma; 1 = kb. +2 °C a mához képest (csak szemléltetés)
var highlight: Dictionary = {}       # a listában éppen rámutatott esemény: gyűrű jelöli
var anomaly_mix := 0.0               # 0..1: a mai hőmérséklet-eltérés térkép áttűnése


## A Copernicus Climate Pulse napi eltérés-térképe (egyenközű, -180..180) a gömbre.
func set_anomaly_texture(tex: Texture2D) -> void:
	_mat.set_shader_parameter("anomaly_map", tex)


func show_anomaly(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(self, "anomaly_mix", 1.0 if on else 0.0, 0.6)
var _look_tw: Tween
var sun_lat := 0.0                   # ahol a Nap éppen merőlegesen süt (fok)
var sun_lon := 0.0
var _sun_timer := 0.0

const EVENT_COLORS := {
	"aszaly": Color("#e0a24a"), "ehezes": Color("#f07a4a"), "arviz": Color("#4aa0e0"), "vihar": Color("#9ab8ff"),
	"tuz": Color("#ff5a3a"), "jeg": Color("#cfefff"), "hoseg": Color("#ff8a3a"), "tenger": Color("#3fa8d8"), "szennyezes": Color("#b48cff"),
	"levego": Color("#c8b49a"), "uv": Color("#e8f060"), "jarvany": Color("#ff6fa0"), "vulkan": Color("#d0503a"), "foldrenges": Color("#c0a070"), "viz": Color("#4ac0d0"),
}
var dragging := false

var _rect: ColorRect
var _mat: ShaderMaterial
var _fx_rect: ColorRect
var _fx_mat: ShaderMaterial


static var _low_tex: Texture2D


## Az alacsony partok maszkja (tools/alacsony_partok.py). Ha a Godot még nem importálta, közvetlenül
## a fájlból töltjük be; minden földgömb ugyanazt a textúrát használja.
static func _low_map() -> Texture2D:
	if _low_tex == null:
		var path := "res://assets/earth_low.png"
		if ResourceLoader.exists(path):
			_low_tex = load(path)
		else:
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				_low_tex = ImageTexture.create_from_image(img)
	return _low_tex


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
	_mat.set_shader_parameter("low_map", _low_map())
	_mat.set_shader_parameter("pixels", pixels)
	_mat.set_shader_parameter("radius", radius_ratio)
	_mat.set_shader_parameter("tilt", tilt)
	_rect.material = _mat
	add_child(_rect)
	# a jelölők a gömb fölé rajzolódnak
	_rect.show_behind_parent = true
	_fx_setup()
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
	var o := deg_to_rad(sun_lon) - _spin_now() * TAU
	var x := cos(lat) * sin(o)
	var y2 := -sin(lat)
	var z2 := cos(lat) * cos(o)
	return Vector3(x, y2 * cos(tilt) + z2 * sin(tilt), -y2 * sin(tilt) + z2 * cos(tilt))


func _process(delta: float) -> void:
	time += delta
	if not dragging:
		spin += spin_speed * delta
	cloud_drift += cloud_speed * delta
	_sway_k = move_toward(_sway_k, 0.0 if (dragging or effect_running()) else 1.0, delta * (4.0 if dragging else 0.5))
	_mat.set_shader_parameter("spin", _spin_now())
	_mat.set_shader_parameter("tilt", tilt)
	_mat.set_shader_parameter("zoom", zoom)
	if fixed_sun:
		_mat.set_shader_parameter("sun_dir", Vector3(-0.42, -0.3, 0.86).normalized())
	elif real_sun:
		_sun_timer -= delta
		if _sun_timer <= 0.0:
			_sun_timer = 10.0
			_update_sun()
		_mat.set_shader_parameter("sun_dir", _sun_dir())
	_mat.set_shader_parameter("cloud_drift", cloud_drift)
	_mat.set_shader_parameter("heat", heat)
	_mat.set_shader_parameter("sea_rise", sea_rise)
	_mat.set_shader_parameter("smog", smog)
	_ash_shown = move_toward(_ash_shown, ash, delta * 0.6)
	_mat.set_shader_parameter("ash", _ash_shown)
	_mat.set_shader_parameter("clean", clean)
	_mat.set_shader_parameter("regrow", regrow)
	_mat.set_shader_parameter("anomaly_mix", anomaly_mix)
	_fx_update()
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
		var hs := _station_at(event.position)
		_hover_name = str(hs.get("name", "")) if not hs.is_empty() else ""
		var over := not _event_at(event.position).is_empty() or not hs.is_empty()
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


var _hover_name := ""


## A pont fényképe (ha van): res://assets/kepek/<kep>.jpg. Csak valódi, forrással jegyzett fotó kerülhet ide
## (assets/FORRASOK.md).
static func photo_of(key: String) -> Texture2D:
	if key == "":
		return null
	for ext in ["jpg", "png", "webp"]:
		var path := "res://assets/kepek/%s.%s" % [key, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## Rámutatáskor a név mellé a hely valódi fényképe is megjelenik (ha van hozzá kép).
func _make_custom_tooltip(for_text: String) -> Object:
	var s := _station_at(get_local_mouse_position())
	var tex: Texture2D = photo_of(str(s.get("kep", ""))) if not s.is_empty() else null
	if tex == null:
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(420, 260)
	box.add_child(pic)
	var lab := Label.new()
	lab.text = for_text
	lab.add_theme_font_size_override("font_size", 18)
	box.add_child(lab)
	return box


## Földrajzi pont -> képernyőpont. Visszaad: Vector3(x, y, látható? 1 : 0)
func project(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var o := deg_to_rad(lon_deg) - _spin_now() * TAU
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
	_draw_planes(px)
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
	# felvillanás (egyezség): három, egymás után táguló gyűrű
	for fl in flashes:
		var pf := project(float(fl["lat"]), float(fl["lon"]))
		if pf.z < 0.5:
			continue
		for ring in 3:
			var age: float = time - float(fl["t0"]) - ring * 0.35
			if age > 0.0 and age < 1.6:
				var k := age / 1.6
				draw_arc(Vector2(pf.x, pf.y), 10.0 + 90.0 * k, 0.0, TAU, 48, Color(fl["color"], (1.0 - k) * 0.9), 3.0)
	# fenyegető baj: kis mozgó jel a csoport fölött (láng, eső, hőség, kiszáradt föld)
	var fx_on := effect_running()             # a nagy animáció alatt a jelek és a feliratok nem takarnak
	for st in storms:
		var ps := project(float(st["lat"]), float(st["lon"]))
		if ps.z < 0.5 or fx_on:
			continue
		var k := 2.4 if st.get("strong", false) else 1.4
		var u := px * k
		var base := Vector2(ps.x, ps.y) + Vector2(0, -16.0 * px)
		draw_circle(base + Vector2(0, -3.0 * u), 9.5 * u, Color(0, 0, 0, 0.42))
		match str(st.get("kind", "")):
			"tuz":
				for i in 9:
					var h := 2 + int(4.0 * absf(sin(time * 7.0 + i * 1.7))) - int(absf(i - 4) * 0.6)
					for j in maxi(h, 1):
						var heat_c := Color(1.0, 0.86, 0.3).lerp(Color(0.95, 0.3, 0.12), float(j) / 5.0)
						draw_rect(Rect2(base + Vector2(i - 4, -j) * u, Vector2(u, u)), heat_c)
				for i in 3:
					var sy := fmod(time * 9.0 + i * 4.1, 9.0)
					draw_rect(Rect2(base + Vector2(sin(time * 2.0 + i * 2.1) * 4.0, -6.0 - sy) * u, Vector2(u, u)), Color(1.0, 0.7, 0.3, 1.0 - sy / 9.0))
			"arviz":
				for i in 7:
					var ry := fmod(time * 16.0 + i * 3.7, 9.0)
					draw_rect(Rect2(base + Vector2(i * 2 - 6, -9.0 + ry) * u, Vector2(u, 2.0 * u)), Color(0.55, 0.8, 1.0, 0.95))
				for i in 13:
					var wy := roundf(sin(time * 4.0 + i * 0.9))
					draw_rect(Rect2(base + Vector2(i - 6, 1.0 + wy) * u, Vector2(u, u)), Color(0.3, 0.6, 1.0))
			"hoseg":
				var ray := 5.0 + 2.0 * sin(time * 5.0)
				for i in 8:
					var a := TAU * i / 8.0 + time * 0.6
					for j in range(4, int(ray) + 3):
						draw_rect(Rect2((base + Vector2(0, -4) * u + Vector2(cos(a), sin(a)) * j * u).snapped(Vector2(u, u)), Vector2(u, u)), Color(1.0, 0.6, 0.2, 0.9))
				draw_circle(base + Vector2(0, -4) * u + Vector2(u, u) * 0.5, 3.2 * u, Color(1.0, 0.85, 0.35))
			_:
				draw_circle(base + Vector2(3, -7) * u, 2.4 * u, Color(1.0, 0.8, 0.4))
				for i in 13:
					var zy := float((i * 7) % 3) - 1.0
					draw_rect(Rect2(base + Vector2(i - 6, zy) * u, Vector2(u, u)), Color(0.72, 0.5, 0.28))
				for i in 4:
					var dx := fmod(time * 6.0 + i * 5.3, 16.0) - 8.0
					draw_rect(Rect2(base + Vector2(dx, -2.0 - float(i % 2) * 2.0) * u, Vector2(u, u)), Color(0.85, 0.7, 0.45, 0.8))
	# állomások: fényoszlop + gyémánt
	for s in stations:
		var p := project(s.lat, s.lon)
		if p.z < 0.5 or fx_on:
			continue
		var col: Color = s.color
		var pos := Vector2(p.x, p.y)
		if s.get("small", false):
			# billenőpont: kis gyűrű (halvány, amíg a küszöb alatt vagyunk; lüktet, ha átléptük)
			var dim: bool = s.get("dim", false)
			var a := (0.55 + 0.35 * sin(time * 2.0) if s.get("warn", false) else 0.7) if dim else 0.75 + 0.25 * sin(time * 4.0)
			var r := 6.0 if dim else 8.0
			draw_arc(pos, r, 0.0, TAU, 20, Color(0, 0, 0, 0.55), 4.0)
			draw_arc(pos, r, 0.0, TAU, 20, Color(col, a), 2.0)
			if not dim:
				draw_circle(pos, 3.0, Color(col, a))
			if _hover_name != "" and _hover_name == str(s.get("name", "")):
				draw_arc(pos, r + 5.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
			continue
		var beam := 22 if s.get("me", false) else 12
		for j in beam:
			draw_rect(Rect2(pos + Vector2(0, -j * px), Vector2(px, px)), Color(col, 0.55 * (1.0 - float(j) / beam)))
		for off in [Vector2(0, -3), Vector2(-1, -2), Vector2(0, -2), Vector2(1, -2), Vector2(-2, -1), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(2, -1),
				Vector2(-3, 0), Vector2(-2, 0), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0),
				Vector2(-2, 1), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(-1, 2), Vector2(0, 2), Vector2(1, 2), Vector2(0, 3)]:
			var edge: bool = abs(off.x) + abs(off.y) == 3
			var cc := Color.WHITE if off == Vector2.ZERO else (col.darkened(0.4) if edge else col)
			draw_rect(Rect2(pos + off * px, Vector2(px, px)), cc)
		if str(s.get("label", "")) != "":
			var f: Font = ThemeDB.fallback_font if get_theme_default_font() == null else get_theme_default_font()
			var w := f.get_string_size(s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string_outline(f, pos + Vector2(-w * 0.5, 22), s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.8))
			draw_string(f, pos + Vector2(-w * 0.5, 22), s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col.lightened(0.35))
		if s.get("locked", false):
			draw_rect(Rect2(pos + Vector2(-2, -8) * px, Vector2(5, 3) * px), Color(0.67, 0.67, 0.67))
	_draw_fx()


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


## Felvillanó gyűrűk egy helyen (pl. amikor egy országcsoport vállal valamit).
func flash(lat: float, lon: float, color: Color) -> void:
	flashes = flashes.filter(func(f: Dictionary) -> bool: return time - float(f["t0"]) < 3.0)
	flashes.append({"lat": lat, "lon": lon, "color": color, "t0": time})
	queue_redraw()


# ---------------------------------------------------------------------------------------------
# A váratlan események nagy, jól látható képe a gömbön (csak szemléltetés, kódból rajzolva).
# ---------------------------------------------------------------------------------------------
var fx: Dictionary = {}              # {"kind", "t0", "dur", "lat", "lon", "points"}
var _fx_tw: Tween
const FX_DUR := {"vulkan": 9.5, "jarvany": 9.0, "attores": 9.0}


## Elindít egy nagy animációt. kind: "vulkan" (lat, lon a kitörés helye), "jarvany", "attores"
## (points: [{"lat", "lon"}] – a csoportok helye). Visszaadja, hány másodpercig tart.
func play_effect(kind: String, lat: float = 0.0, lon: float = 0.0, points: Array = []) -> float:
	var dur: float = FX_DUR.get(kind, 6.0)
	fx = {"kind": kind, "t0": time, "dur": dur, "lat": lat, "lon": lon, "points": points}
	if _look_tw != null and _look_tw.is_valid():
		_look_tw.kill()
	if _fx_tw != null and _fx_tw.is_valid():
		_fx_tw.kill()
	_fx_tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tw.set_parallel(true)
	if kind == "vulkan":
		# a tűzhányó a kép alsó felére kerül, hogy a hamuoszlopnak legyen helye fölfelé
		var ts := spin + wrapf(lon / 360.0 - spin, -0.5, 0.5)
		_fx_tw.tween_property(self, "spin", ts, 0.8)
		_fx_tw.tween_property(self, "tilt", clampf(deg_to_rad(lat + 30.0), -TILT_MAX, TILT_MAX), 0.8)
		_fx_tw.tween_property(self, "zoom", 1.0, 0.8)
	else:
		# a Föld közben egyszer körbefordul, hogy minden csoport látsszon
		_fx_tw.tween_property(self, "spin", spin + 1.0, dur - 0.5)
		_fx_tw.tween_property(self, "tilt", 0.3, 0.8)
		_fx_tw.tween_property(self, "zoom", 1.0, 0.8)
	return dur


func effect_running() -> bool:
	return not fx.is_empty() and time - float(fx["t0"]) < float(fx["dur"])


static func _h(i: float) -> float:
	return fposmod(sin(i * 127.1 + 31.7) * 43758.5453, 1.0)


func _fx_setup() -> void:
	_fx_rect = ColorRect.new()
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = FX_SHADER
	_fx_rect.material = _fx_mat
	_fx_rect.show_behind_parent = true        # a gömb fölött, de a kézzel rajzolt jelek alatt
	_fx_rect.visible = false
	add_child(_fx_rect)


## A csoportok jelének kora (mp) az adott animációban; <= 0: még nem látszik.
func _fx_point_age(kind: String, k: int, a: float) -> float:
	if kind == "jarvany":
		return a - 0.3 if k == 0 else a - 0.5 - (k - 1) * 0.7 - 0.7
	return a - 0.3 - k * 0.3


## Képkockánként: a shader adatai (a vetítés ugyanaz, mint a jelölőknél).
func _fx_update() -> void:
	if fx.is_empty() or time - float(fx["t0"]) >= float(fx["dur"]):
		fx = {}
		_fx_rect.visible = false
		return
	var a := time - float(fx["t0"])
	var kind := str(fx["kind"])
	_fx_rect.visible = true
	_fx_mat.set_shader_parameter("kind", {"vulkan": 1, "jarvany": 2, "attores": 3}.get(kind, 0))
	_fx_mat.set_shader_parameter("age", a)
	_fx_mat.set_shader_parameter("fade", clampf((float(fx["dur"]) - a) / 1.4, 0.0, 1.0))
	_fx_mat.set_shader_parameter("pixels", pixels)
	_fx_mat.set_shader_parameter("rad", 0.5 * radius_ratio * zoom)
	if kind == "vulkan":                      # a tűzhányót kézzel rajzoljuk (_draw_volcano)
		_fx_rect.visible = false
		return
	var arr := PackedVector3Array()
	var pts: Array = fx["points"]
	for k in mini(pts.size(), 8):
		var p := project(float(pts[k]["lat"]), float(pts[k]["lon"]))
		var pa := _fx_point_age(kind, k, a) if p.z > 0.5 else 0.0
		arr.append(Vector3(p.x / size.x, p.y / size.y, maxf(pa, 0.0)))
	var n := arr.size()
	while arr.size() < 8:
		arr.append(Vector3.ZERO)
	_fx_mat.set_shader_parameter("pts", arr)
	_fx_mat.set_shader_parameter("npts", n)


func _draw_fx() -> void:
	if fx.is_empty():
		return
	var a := time - float(fx["t0"])
	var dur := float(fx["dur"])
	if a >= dur:
		return
	var fade := clampf((dur - a) / 1.4, 0.0, 1.0)
	var R := size.x * 0.5 * radius_ratio * zoom
	match str(fx["kind"]):
		"vulkan":
			var p := project(float(fx["lat"]), float(fx["lon"]))
			if p.z > 0.5:
				_draw_volcano(Vector2(p.x, p.y), R, a, fade)
		"jarvany":
			_draw_pandemic(R, a, fade)
		"attores":
			_draw_breakthrough(R, a, fade)


func _draw_volcano(c: Vector2, R: float, a: float, fade: float) -> void:
	var w := R * 0.30
	var h := R * 0.25
	var grow := clampf(a / 0.9, 0.0, 1.0)
	grow = 1.0 - (1.0 - grow) * (1.0 - grow)
	c += Vector2(sin(a * 61.0), cos(a * 47.0)) * R * (0.007 if a < 3.0 else 0.002)
	var top := c + Vector2(0, -h * grow)
	var cr := w * 0.2
	var er := clampf((a - 0.9) / 0.5, 0.0, 1.0)          # a kitörés ereje
	# megperzselt föld és árnyék a hegy alatt: ettől ül a földön
	_ellipse(c + Vector2(w * 0.25, R * 0.02), Vector2(w * 1.75, w * 0.30) * grow, Color(0, 0, 0, 0.30 * fade))
	_ellipse(c + Vector2(0, R * 0.008), Vector2(w * 1.45, w * 0.24) * grow, Color(0.05, 0.035, 0.03, 0.55 * fade))
	_ellipse(c, Vector2(w * 1.2, w * 0.17) * grow, Color(0.10, 0.075, 0.065, 0.9 * fade))
	# izzás a kráter mögött
	for i in 7:
		draw_circle(top, R * (0.06 + 0.06 * i) * er * (1.0 + 0.07 * sin(a * 9.0 + i)), Color(1.0, 0.42, 0.08, 0.085 * fade))
	# lökéshullám a kitörés pillanatában
	var sh := (a - 0.9) / 1.4
	if sh > 0.0 and sh < 1.0:
		draw_arc(top, R * 0.9 * sh, 0.0, TAU, 72, Color(1.0, 0.85, 0.6, (1.0 - sh) * 0.7 * fade), 5.0)
	# hamuoszlop: sok gomolygó felhő, a régebbiek magasabban és szélesebben
	for i in 64:
		var pa := a - 0.95 - i * 0.105
		if pa <= 0.0:
			continue
		var rise := R * 0.80 * (1.0 - exp(-pa * 0.6))
		var kh := rise / (R * 0.80)
		var drift := R * 0.55 * kh * kh * (0.35 + _h(i)) + R * 0.03 * sin(pa * 1.7 + i)
		var side := (_h(i + 20.0) - 0.5) * R * 0.16 * (0.3 + kh * 1.6)
		var pr := R * (0.035 + 0.115 * (1.0 - exp(-pa * 0.55))) * (0.75 + 0.5 * _h(i + 7.0))
		var pos := top + Vector2(drift + side, -rise)
		var g := 0.20 + 0.26 * _h(i + 3.0)
		var hot := clampf(1.0 - pa / 0.9, 0.0, 1.0)      # a kráter fölött még izzik
		var col := Color(g + 0.5 * hot, g * 0.95 + 0.18 * hot, g * 0.92, 0.9 * fade)
		draw_circle(pos, pr, col)
		draw_circle(pos + Vector2(-pr * 0.28, -pr * 0.3), pr * 0.6, Color(col.r + 0.13, col.g + 0.12, col.b + 0.11, 0.55 * fade))
		draw_circle(pos + Vector2(pr * 0.3, pr * 0.32), pr * 0.55, Color(col.r * 0.6, col.g * 0.6, col.b * 0.62, 0.4 * fade))
	# villám a hamufelhőben
	var lt := fposmod(a, 1.37)
	if a > 2.6 and lt < 0.13:
		var seed_i := floorf(a / 1.37) * 13.0
		var q := top + Vector2(R * 0.12 * (_h(seed_i) - 0.3), -R * (0.42 + 0.2 * _h(seed_i + 1.0)))
		var pts := PackedVector2Array([q])
		for k in 6:
			q += Vector2((_h(seed_i + k * 3.0 + 2.0) - 0.5) * R * 0.11, R * 0.055)
			pts.append(q)
		draw_polyline(pts, Color(0.75, 0.8, 1.0, 0.5 * fade), 7.0)
		draw_polyline(pts, Color(1, 1, 1, fade), 2.5)
	# a hegy
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w, 0), top + Vector2(-cr, 0), top + Vector2(cr, 0), c + Vector2(w, 0)]), Color(0.13, 0.10, 0.10, fade))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w, 0), top + Vector2(-cr, 0), top + Vector2(cr * 0.1, 0), c + Vector2(-w * 0.1, 0)]), Color(0.23, 0.17, 0.15, fade))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w * 0.55, 0), top + Vector2(-cr * 0.9, 0), top + Vector2(-cr * 0.4, 0), c + Vector2(-w * 0.42, 0)]), Color(0.30, 0.23, 0.20, 0.7 * fade))
	# a hegy lába: ívelt talp és törmelék, hogy ne egyenes vonalban érjen véget
	_ellipse(c, Vector2(w, w * 0.11) * grow, Color(0.13, 0.10, 0.10, fade))
	_ellipse(c + Vector2(-w * 0.45, 0), Vector2(w * 0.55, w * 0.10) * grow, Color(0.23, 0.17, 0.15, fade))
	for i in 9:
		var rx := (_h(i + 70.0) - 0.5) * 2.3 * w
		draw_circle(c + Vector2(rx, w * 0.10 * (0.5 + _h(i + 80.0))) , R * (0.008 + 0.012 * _h(i + 90.0)) * grow, Color(0.17, 0.13, 0.12, fade))
	# lávafolyamok a hegyoldalon
	for s in 5:
		var prog := clampf((a - 1.3 - s * 0.45) / 3.2, 0.0, 1.0)
		if prog <= 0.0:
			continue
		var dir := (float(s) - 2.0) / 2.0                 # -1 .. 1: melyik oldalon folyik
		var pts := PackedVector2Array()
		var n := 14
		for k in n + 1:
			var u := float(k) / n * prog
			var x := dir * (cr * 0.7 + (w * 0.86 - cr * 0.7) * u) + sin(u * 9.0 + s * 2.3) * w * 0.035
			pts.append(top + Vector2(x, h * grow * u))
		var flick := 0.85 + 0.15 * sin(a * 7.0 + s)
		draw_polyline(pts, Color(0.75, 0.12, 0.03, 0.9 * fade), R * 0.030)
		draw_polyline(pts, Color(1.0, 0.45, 0.08, fade * flick), R * 0.018)
		draw_polyline(pts, Color(1.0, 0.86, 0.4, fade * flick), R * 0.007)
	# izzó kráter
	_ellipse(top, Vector2(cr * 1.15, cr * 0.32), Color(1.0, 0.5, 0.1, er * fade))
	_ellipse(top, Vector2(cr * 0.8, cr * 0.2), Color(1.0, 0.92, 0.55, er * fade))
	# lávaszökőkút
	if a > 0.9:
		for i in 90:
			var per := 1.0 + _h(i) * 0.9
			var t := fposmod(a - 0.9 - _h(i + 50.0) * per, per)
			var ang := -PI * 0.5 + (_h(i + 9.0) - 0.5) * 1.5
			var sp := R * (0.55 + 0.75 * _h(i + 3.0))
			var pos := top + Vector2(cos(ang), sin(ang)) * sp * t + Vector2(0, R * 1.0 * t * t)
			var k := t / per
			var col := Color(1.0, 0.95, 0.55).lerp(Color(0.9, 0.18, 0.04), k)
			var pr := R * 0.013 * (1.25 - k) * (0.6 + 0.8 * _h(i + 5.0))
			draw_circle(pos, pr * 2.2, Color(1.0, 0.4, 0.05, 0.18 * (1.0 - k) * fade))
			draw_circle(pos, pr, Color(col, (1.0 - k * 0.7) * fade))


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 28:
		var an := TAU * k / 28.0
		pts.append(c + Vector2(cos(an) * r.x, sin(an) * r.y))
	if r.x > 0.5 and r.y > 0.5:
		draw_colored_polygon(pts, col)


## Ív két földrajzi pont között (a gömb fölé emelve), 0..prog részig.
func _arc_pts(p0: Dictionary, p1: Dictionary, prog: float) -> PackedVector2Array:
	var va := _vec(float(p0["lat"]), float(p0["lon"]))
	var vb := _vec(float(p1["lat"]), float(p1["lon"]))
	var pts := PackedVector2Array()
	var c := size * 0.5
	var n := 48
	for i in int(n * prog) + 1:
		var u := float(i) / n
		var v := va.lerp(vb, u).normalized()
		var p := project(rad_to_deg(asin(v.y)), rad_to_deg(atan2(v.z, v.x)))
		if p.z < 0.5:
			if pts.size() > 1:
				break
			pts.clear()
			continue
		var q := c + (Vector2(p.x, p.y) - c) * (1.0 + sin(u * PI) * 0.16)
		if q.distance_to(c) > size.x * 0.5 * radius_ratio * zoom * 0.97:      # a gömb peremén túl nem rajzolunk
			if pts.size() > 1:
				break
			pts.clear()
			continue
		pts.append(q)
	return pts


## Izzó vonal: több, egyre keskenyebb és világosabb réteg.
func _glow_line(pts: PackedVector2Array, col: Color, w: float, alpha: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(col, 0.10 * alpha), w * 5.0, true)
	draw_polyline(pts, Color(col, 0.22 * alpha), w * 2.6, true)
	draw_polyline(pts, Color(col.lightened(0.3), 0.9 * alpha), w, true)
	draw_polyline(pts, Color(1, 1, 1, 0.85 * alpha), w * 0.35, true)


## Járvány: a fertőzés útja ívekben csoporttól csoportig (a vírust a shader rajzolja).
func _draw_pandemic(R: float, a: float, fade: float) -> void:
	var pts: Array = fx["points"]
	var pink := Color("#ff5a94")
	for k in range(1, pts.size()):
		var prog := clampf((a - 0.5 - (k - 1) * 0.7) / 0.7, 0.0, 1.0)
		if prog <= 0.0:
			continue
		var line := _arc_pts(pts[k - 1], pts[k], prog)
		if line.size() > 1:
			var dim := clampf(1.0 - (a - 5.2) / 1.5, 0.0, 1.0)       # a lezárásnál kihunynak az utak
			_glow_line(line, pink, 3.0, fade * dim)
			if prog < 1.0:
				var hp := line[line.size() - 1]
				draw_circle(hp, R * 0.03, Color(pink, 0.25 * fade))
				draw_circle(hp, R * 0.014, Color(1, 0.9, 0.95, fade))


## Áttörés: szélkerekek és napelemek nőnek ki minden csoportnál (a napot és a fényt a shader rajzolja).
func _draw_breakthrough(R: float, a: float, fade: float) -> void:
	var pts: Array = fx["points"]
	var c := size * 0.5
	# izzó hálózat köti össze a csoportokat
	for k in range(1, pts.size()):
		var prog := clampf((a - 2.2 - k * 0.3) / 0.9, 0.0, 1.0)
		if prog > 0.0:
			_glow_line(_arc_pts(pts[k - 1], pts[k], prog), Color("#7dffb0"), 2.2, fade * 0.9)
	for k in pts.size():
		var age := _fx_point_age("attores", k, a)
		if age <= 0.0:
			continue
		var p := project(float(pts[k]["lat"]), float(pts[k]["lon"]))
		if p.z < 0.5:
			continue
		var base := Vector2(p.x, p.y)
		if base.distance_to(c) > R * 0.9:
			continue
		# zöld domb
		var s0 := clampf(age / 0.5, 0.0, 1.0)
		_ellipse(base + Vector2(0, R * 0.012), Vector2(R * 0.19, R * 0.03) * s0, Color(0, 0, 0, 0.4 * fade))
		_ellipse(base, Vector2(R * 0.17, R * 0.026) * s0, Color(0.16, 0.42, 0.2, fade))
		_ellipse(base + Vector2(-R * 0.02, -R * 0.004), Vector2(R * 0.12, R * 0.014) * s0, Color(0.3, 0.6, 0.28, fade))
		# napelemsor a domb jobb oldalán
		for j in 3:
			var sp := clampf((age - 0.5 - j * 0.18) / 0.4, 0.0, 1.0)
			if sp > 0.0:
				_solar(base + Vector2(R * (0.035 + 0.047 * j), -R * 0.004 + R * 0.006 * j), R * 0.04 * sp, a + j * 0.3 + k, fade)
		# három szélkerék: egy nagy elöl, két kisebb hátrébb
		for j in [1, 2, 0]:
			var st := clampf((age - 0.15 - j * 0.3) / 0.7, 0.0, 1.0)
			st = 1.0 - (1.0 - st) * (1.0 - st)
			if st <= 0.0:
				continue
			var off := [Vector2(0, 0), Vector2(-0.085, -0.012), Vector2(-0.045, -0.02)][j] as Vector2
			var hgt := [0.23, 0.15, 0.12][j] as float
			_turbine(base + off * R, R * hgt * st, a * (3.0 + 0.5 * j) + k + j * 1.3, fade, 1.0 if j == 0 else 0.82)


func _solar(b: Vector2, w: float, t: float, fade: float) -> void:
	if w < 1.0:
		return
	var h := w * 0.62
	var sk := w * 0.32
	var quad := PackedVector2Array([b, b + Vector2(w, 0), b + Vector2(w + sk, -h), b + Vector2(sk, -h)])
	draw_line(b + Vector2(w * 0.3 + sk * 0.5, -h * 0.5), b + Vector2(w * 0.3 + sk * 0.5, h * 0.25), Color(0.2, 0.22, 0.25, fade), 2.0)
	draw_line(b + Vector2(w * 0.8 + sk * 0.5, -h * 0.5), b + Vector2(w * 0.8 + sk * 0.5, h * 0.25), Color(0.2, 0.22, 0.25, fade), 2.0)
	draw_colored_polygon(quad, Color(0.05, 0.12, 0.36, fade))
	draw_colored_polygon(PackedVector2Array([quad[3], quad[2], quad[2].lerp(quad[1], 0.45), quad[3].lerp(quad[0], 0.45)]), Color(0.12, 0.3, 0.62, 0.9 * fade))
	for i in range(1, 4):
		var u := float(i) / 4.0
		draw_line(quad[0].lerp(quad[1], u), quad[3].lerp(quad[2], u), Color(0.6, 0.78, 1.0, 0.75 * fade), 1.0)
	for i in range(1, 3):
		var u := float(i) / 3.0
		draw_line(quad[0].lerp(quad[3], u), quad[1].lerp(quad[2], u), Color(0.6, 0.78, 1.0, 0.75 * fade), 1.0)
	draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), Color(0.85, 0.92, 1.0, fade), 1.5)
	var gl := fposmod(t * 0.45, 1.6)
	if gl < 1.0:                                           # végigfutó csillanás
		draw_line(quad[0].lerp(quad[1], gl), quad[3].lerp(quad[2], gl), Color(1, 1, 1, 0.85 * fade * sin(gl * PI)), 2.5)


func _turbine(b: Vector2, h: float, rot: float, fade: float, tone: float) -> void:
	if h < 2.0:
		return
	var w0 := maxf(h * 0.045, 2.0)
	var w1 := maxf(h * 0.022, 1.2)
	var hub := b + Vector2(0, -h)
	# torony: lent szélesebb, bal oldala világos, jobb oldala árnyékos
	draw_colored_polygon(PackedVector2Array([b + Vector2(-w0 - 1.5, 0), hub + Vector2(-w1 - 1.5, 0), hub + Vector2(w1 + 1.5, 0), b + Vector2(w0 + 1.5, 0)]), Color(0, 0, 0, 0.55 * fade))
	draw_colored_polygon(PackedVector2Array([b + Vector2(-w0, 0), hub + Vector2(-w1, 0), hub + Vector2(w1, 0), b + Vector2(w0, 0)]), Color(0.72 * tone, 0.76 * tone, 0.82 * tone, fade))
	draw_colored_polygon(PackedVector2Array([b + Vector2(-w0, 0), hub + Vector2(-w1, 0), hub + Vector2(0, 0), b + Vector2(-w0 * 0.1, 0)]), Color(0.96 * tone, 0.97 * tone, 1.0 * tone, fade))
	# gépház
	var nw := h * 0.075
	draw_rect(Rect2(hub + Vector2(-nw * 0.45, -nw * 0.3), Vector2(nw, nw * 0.6)), Color(0, 0, 0, 0.55 * fade))
	draw_rect(Rect2(hub + Vector2(-nw * 0.45 + 1, -nw * 0.3 + 1), Vector2(nw - 2, nw * 0.6 - 2)), Color(0.86 * tone, 0.89 * tone, 0.93 * tone, fade))
	# három lapát: a tövénél széles, a hegyénél keskeny, két tónussal
	var bl := h * 0.52
	for i in 3:
		var an := TAU * i / 3.0 + rot
		var d := Vector2(cos(an), sin(an))
		var n := Vector2(-d.y, d.x)
		var blade := PackedVector2Array([hub + n * bl * 0.02, hub + d * bl * 0.22 + n * bl * 0.085, hub + d * bl * 0.6 + n * bl * 0.05, hub + d * bl, hub + d * bl * 0.5 - n * bl * 0.012, hub - n * bl * 0.02])
		var outline := PackedVector2Array(blade)
		outline.append(blade[0])
		draw_polyline(outline, Color(0, 0, 0, 0.55 * fade), 3.0, true)
		draw_colored_polygon(blade, Color(0.97 * tone, 0.98 * tone, 1.0 * tone, fade))
		draw_colored_polygon(PackedVector2Array([blade[0], blade[3], blade[4], blade[5]]), Color(0.74 * tone, 0.79 * tone, 0.86 * tone, fade))
	draw_circle(hub, maxf(h * 0.032, 2.5), Color(0.25, 0.3, 0.36, fade))
	draw_circle(hub + Vector2(-0.5, -0.5), maxf(h * 0.018, 1.4), Color(1, 1, 1, fade))


## Repülők a csoportok között (szemléltetés): apró fehér pont halvány csíkkal, a gömb fölé emelt íven.
## A csík színe a kibocsátással változik: ma szürkésbarna, nulla kibocsátásnál tiszta, világos.
func _draw_planes(px: float) -> void:
	if not alive or effect_running():
		return
	var g: Array = stations.filter(func(s: Dictionary) -> bool: return s.has("id"))
	if g.size() < 2:
		return
	var c := size * 0.5
	var trail := Color(0.72, 0.62, 0.5).lerp(Color(0.8, 0.97, 1.0), clampf(clean, 0.0, 1.0))
	var n := 0
	for i in g.size():
		for j in range(i + 1, g.size()):
			n += 1
			var va := _vec(float(g[i]["lat"]), float(g[i]["lon"]))
			var vb := _vec(float(g[j]["lat"]), float(g[j]["lon"]))
			var per := 26.0 + 14.0 * _h(n)
			var u := fposmod(time / per + _h(n + 40.0), 1.0)
			if n % 2 == 0:
				u = 1.0 - u
			var dir := -1.0 if n % 2 == 0 else 1.0
			for k in 9:                                   # k = 0: a gép, utána a csík
				var uk := u - dir * k * 0.012
				if uk < 0.0 or uk > 1.0:
					continue
				var v := va.lerp(vb, uk).normalized()
				var p := project(rad_to_deg(asin(v.y)), rad_to_deg(atan2(v.z, v.x)))
				if p.z < 0.5:
					continue
				var q := (c + (Vector2(p.x, p.y) - c) * (1.0 + sin(uk * PI) * 0.07)).snapped(Vector2(px, px))
				var edge := sin(uk * PI)                   # fel- és leszálláskor halvány
				if k == 0:
					draw_rect(Rect2(q - Vector2(px, px), Vector2(px, px) * 3.0), Color(0, 0, 0, 0.35 * edge))
					draw_rect(Rect2(q, Vector2(px, px) * 1.0), Color(1, 1, 1, edge))
					draw_rect(Rect2(q + Vector2(px, 0), Vector2(px, px)), Color(1, 1, 1, 0.8 * edge))
				else:
					draw_rect(Rect2(q, Vector2(px, px)), Color(trail, 0.6 * edge * (1.0 - k / 9.0)))
