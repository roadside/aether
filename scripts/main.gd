extends Control
## AETHER – a főképernyő. A Föld a játéktábla: körülötte a hat országcsoport, alul a lépéseid.
## A szabályok a world.gd-ben vannak, a klímamodell a model.gd-ben, a kártyák a cards.gd-ben.

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Globe := preload("res://scripts/globe.gd")
const Intro := preload("res://scripts/intro.gd")
const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")
const M := preload("res://scripts/model.gd")
const Chart := preload("res://scripts/curve.gd")
const PathChart := preload("res://scripts/path_chart.gd")
const Icons := preload("res://scripts/icons.gd")
const Landscape := preload("res://scripts/landscape.gd")
const ThemeArt := preload("res://scripts/theme_art.gd")
const StoryLine := preload("res://scripts/story_line.gd")
const SAVE := "user://jatek.json"

## Az aggodalmak mondatai (játékszabály: a csoportok hangja, nem idézet).
const WORRY := {
	"aram": "Ha bezárjuk a szénerőműveket, miből lesz elég és megfizethető áram?",
	"munka": "A gyáraink, az autóink és a fűtésünk szénnel, olajjal, gázzal mennek. Mivel váltjuk ki?",
	"elelem": "Előbb az embereknek kell enniük. Nem kockáztathatjuk a termést.",
	"part": "A tenger már most emelkedik nálunk. Mit ér nekünk egy távoli ígéret?",
	"egeszseg": "A városainkban már most betegít a hőség és a füst. Segít ez rajtuk?",
	"ketseg": "Biztos, hogy az ember okozza? És számít, amit mi teszünk?",
	"olaj": "Az olaj és a gáz a bevételünk. Mit tehetünk úgy, hogy ne menjünk tönkre?",
	"erdo": "Az erdő és a föld ad megélhetést. Ki fizeti meg, ha érintetlenül hagyjuk?",
}
## Amit a csoport a megállapodáskor mond: arra az aggodalmára felel, amelyikre a kártyád válaszolt (játékszabály).
const REPLY := {
	"aram": "Ha a tiszta áram elég és megfizethető, belevágunk.",
	"munka": "Ha van mivel kiváltani, átállítjuk a gyárainkat és az autóinkat.",
	"elelem": "Ha a termés biztonságban van, veletek tartunk.",
	"part": "Ez nekünk nem távoli ígéret. Számíthattok ránk.",
	"egeszseg": "Ha ettől tisztább lesz a levegő a városainkban, benne vagyunk.",
	"ketseg": "A mérések meggyőztek. Számít, amit teszünk.",
	"olaj": "Ha az olaj után is lesz miből élnünk, belevágunk.",
	"erdo": "Ha az erdő megvédése megélhetést is ad, veletek tartunk.",
}
const DISASTER := {"hoseg": "Hőhullám", "aszaly": "Aszály", "arviz": "Áradás", "tuz": "Erdőtűz"}
const THREAT := {"hoseg": "Hőhullám fenyeget", "aszaly": "Aszály fenyeget", "arviz": "Áradás fenyeget", "tuz": "Erdőtűz fenyeget"}
const MYTH := {"napaktivitas": "A Nap okozza a melegedést, nem az ember.", "kozmikus": "A világűrből jövő sugárzás okozza a melegedést.",
	"tcre": "A levegőben túl kevés a CO2 ahhoz, hogy számítson.", "felhok": "A felhők majd megállítják a melegedést."}
const MYTH_COLOR := Color("#b9a2ff")
const LEVELS := ["", "Gyorsabban telik az idő.", "Érzékenyebb a Föld.", "Egy csoport makacsabb.", "A csoportok könnyebben elbizonytalanodnak.", "Eggyel kevesebb lépésed van."]
const CDR_NAME := {"erdo": "Erdősítés", "bioszen": "Bioszén", "kozet": "Kőzetmállasztás", "levegoszures": "CO2-szűrés a levegőből", "novenyi_energia": "Növényi energia CO2-tárolással"}

var world: World
var globe
var _bg_nodes: Array = []
var _intro: Control
var _overlay: Control
var _body: Control
var _dim: ColorRect
var _close_x: Button
var _stats: Dictionary = {}
var _dots: Label
var _group_cards: Dictionary = {}
var _curve: Control
var _mission_btn: Button
var _mission_seen := 0
var _mission_game := -1
var _btns: Dictionary = {}
var _menu: PanelContainer
var _menu_catch: Control
var _reset_btn: Button
var _offers: Dictionary = {}          # témakör -> a körben felkínált kérdések (hogy ne lehessen újrahúzni)
var _busy := false
var _test := false
var _dry := false                 # ellenőrző futás: nem ír beállítást, nem szól (a --bejaras --eles ezt kikapcsolja)
var _snd: AudioStreamPlayer


class Twinkle extends Control:
	var _stars: Array = []
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2026
		for i in 60:
			_stars.append([Vector2(rng.randf() * 1600.0, rng.randf() * 900.0).snapped(Vector2(2, 2)),
				rng.randf_range(0.6, 2.2), rng.randf() * TAU, 2.0 if rng.randf() < 0.15 else 1.0])

	var _met_at := 14.0          # mikor jön a következő hullócsillag (másodperc)
	var _met_from := Vector2.ZERO
	var _met_dir := Vector2.ZERO

	func _process(delta: float) -> void:
		_t += delta
		if _t > _met_at + 0.9:   # ritkán, 20–45 másodpercenként egy halvány hullócsillag
			_met_at = _t + randf_range(20.0, 45.0)
			_met_from = Vector2(randf_range(200.0, 1400.0), randf_range(20.0, 300.0))
			_met_dir = Vector2(1.0 if randf() < 0.5 else -1.0, randf_range(0.35, 0.6)).normalized()
		queue_redraw()

	func _draw() -> void:
		var k := (_t - _met_at) / 0.9
		if k > 0.0 and k < 1.0 and _met_dir != Vector2.ZERO:
			var head := _met_from + _met_dir * 260.0 * k
			var fade := sin(k * PI)
			for i in 14:
				var p := (head - _met_dir * float(i) * 4.0).snapped(Vector2(2, 2))
				draw_rect(Rect2(p, Vector2(2, 2)), Color(0.9, 0.95, 1.0, fade * 0.75 * (1.0 - float(i) / 14.0)))
		for s in _stars:
			var a: float = 0.12 + 0.50 * (0.5 + 0.5 * sin(_t * float(s[1]) + float(s[2])))
			var sz: float = float(s[3]) * 2.0
			draw_rect(Rect2(s[0], Vector2(sz, sz)), Color(0.85, 0.92, 1.0, a))


## Felvillanó pillanat a Földön: lüktető gyűrű, fogyó idővel. Rá kell kattintani, mielőtt eltűnik.
## Kis műhold kering a Föld körül (kódból rajzolt); a gömb mögött eltűnik.
class Satellite extends Control:
	var center := Vector2(800, 444)
	var radius := 344.0
	var phase := 1.2

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		phase = fmod(phase + delta * 0.11, TAU)
		queue_redraw()

	func _draw() -> void:
		var x := cos(phase) * radius * 1.16
		var y := sin(phase) * radius * 0.30
		var p := center + Vector2(x, y).rotated(-0.38)
		if sin(phase) < 0.0 and p.distance_to(center) < radius * 0.99:      # a gömb mögött jár
			return
		var u := 3.0
		p = p.snapped(Vector2(u, u))
		var far := 0.75 if sin(phase) < 0.0 else 1.0
		draw_rect(Rect2(p + Vector2(-1, -1) * u, Vector2(3, 3) * u), Color(0.82, 0.86, 0.92, far))
		draw_rect(Rect2(p, Vector2(u, u)), Color(1.0, 0.85, 0.4, far))
		for sx in [-1.0, 1.0]:
			draw_rect(Rect2(p + Vector2(sx * 3.0 - (1.0 if sx < 0.0 else -1.0), 0) * u, Vector2(2, 1) * u), Color(0.25, 0.5, 0.95, far))
			draw_rect(Rect2(p + Vector2(sx * 2.0, 0) * u, Vector2(u, u)), Color(0.5, 0.55, 0.62, far))
		if int(phase * 9.0) % 7 == 0:      # jelzőfény
			draw_rect(Rect2(p + Vector2(0, -2) * u, Vector2(u, u)), Color(1.0, 0.3, 0.3, far))


## Szálló színes szikrák a megállapodás ablakában (kódból rajzolt).
class Burst extends Control:
	var colors: Array = [Color.WHITE]
	var bits: Array = []
	var age := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 44:
			var a := randf_range(-PI, 0.0)
			bits.append({"p": Vector2.ZERO, "v": Vector2(cos(a), sin(a)) * randf_range(140.0, 520.0), "c": colors[i % colors.size()], "s": randf_range(4.0, 8.0)})

	func _process(delta: float) -> void:
		age += delta
		for b in bits:
			b["v"] = (b["v"] as Vector2) * (1.0 - 1.2 * delta) + Vector2(0, 520.0) * delta
			b["p"] = (b["p"] as Vector2) + (b["v"] as Vector2) * delta
		queue_redraw()
		if age > 2.2:
			queue_free()

	func _draw() -> void:
		for b in bits:
			var s: float = floorf(float(b["s"]))
			draw_rect(Rect2((b["p"] as Vector2).snapped(Vector2(4, 4)), Vector2(s, s)), Color(b["c"], clampf(2.2 - age, 0.0, 1.0)))


class Moment extends Control:
	signal picked
	var color := Color.WHITE
	var total := 12.0
	var left := 12.0
	var _t := 0.0

	func _init() -> void:
		size = Vector2(140, 140)
		pivot_offset = size * 0.5
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picked.emit()

	func _draw() -> void:
		var c := size * 0.5
		for i in 3:                                   # kifelé futó gyűrűk
			var k := fmod(_t * 0.9 + float(i) / 3.0, 1.0)
			draw_arc(c, 20.0 + 48.0 * k, 0.0, TAU, 48, Color(color, 0.8 * (1.0 - k)), 4.0)
		draw_circle(c, 21.0, Color(0.04, 0.06, 0.12, 0.88))
		draw_arc(c, 21.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(left / total, 0.0, 1.0), 40, color, 4.0)   # a hátralévő idő
		var pulse := 1.0 + 0.25 * sin(_t * 7.0)
		draw_rect(Rect2(c + Vector2(-3, -11) * pulse, Vector2(6, 14) * pulse), color)                  # felkiáltójel
		draw_rect(Rect2(c + Vector2(-3, 6) * pulse, Vector2(6, 6) * pulse), color)


const ROUND_SECONDS := 90.0          # ennyi ideig tart egy kör (öt év), ha az idő telik (játékszabály)
const MOMENT_SECONDS := 12.0
var _clock := 0.0
var _tick_left := 0


func _round_s() -> float:
	return World.CHALLENGE_SECONDS if world != null and world.challenge >= 1 else ROUND_SECONDS


func _quote(text: String) -> String:
	return ("“%s”" if L.is_en() else "„%s”") % text


func _myth_text() -> String:
	return _quote(L.t(MYTH.get(str(world.myth.get("kartya", "")), "")))


## Az előre látható baj fajtája, ha ezt a csoportot fenyegeti, és még nem készült fel rá.
func _threat_on(g: Dictionary) -> String:
	if world.over() or world.threat.is_empty() or str(world.threat.get("csoport", "")) != str(g["id"]) or g.get("felkeszult", false):
		return ""
	return str(world.threat.get("mi", ""))
var _clock_bar: ColorRect
var _clock_force := false            # az önteszt képeihez
var _clock_live := false             # próba: az óra ellenőrző futásban is jár, és magától lép a következő körre
var _moment: Dictionary = {}         # {"fajta": "figyelem" | "felfedezes", "csoport", "lat", "lon"}
var _moment_node: Moment
var _moment_lbl: Label
var _moment_times: Array = []        # a körön belül ekkor villan fel egy-egy pillanat (másodperc)


func _time_on() -> bool:
	return bool(L.get_setting("elo_ido", true))


# --- az első játék vezetése -----------------------------------------------------
## Az első játék első körében egy rövid sor mindig megmondja a következő mozdulatot (legfeljebb egy mondat).
## Ebben a körben az idő még nem telik, és nem villan fel pillanat: előbb a három alaplépést kell megtanulni.
var _tutor: Label
var _tutor_ctx := ""
var _ramp_game := -1            # az első játék: a lehetőségek körről körre nyílnak meg (ennek a játéknak az azonosítója)

## Az első játékban lépcsőzetesen nyílnak meg a lehetőségek: hányadik körtől él a megadott dolog.
func _ramp(from_round: int) -> bool:
	return _ramp_game != world.game_id or world.round_i >= from_round or world.over()

var _tutor_force := false

func _tutor_on() -> bool:
	if world == null or world.over() or world.round_i != 0:
		return false
	if _tutor_force or not bool(L.get_setting("tanulo_kesz", false)):
		_ramp_game = world.game_id
		return true
	return false


func _tutor_text() -> String:
	if _intro != null or world == null:
		return ""
	if not _tutor_on():
		if _overlay != null or world.over() or _ramp_game != world.game_id:
			return ""
		if world.round_i == 1 and _time_on():
			return "Mostantól telik az idő. Figyeld a sávot az évszám alatt!"
		if world.round_i == 2:
			return "Új: metáncsökkentést és felkészülést is kérhetsz."
		if world.round_i == 3:
			return "Új gomb: CO2-kivonás. Kártya kell hozzá."
		return ""
	if _overlay != null:
		return {"temak": "Válassz egy témakört!", "kerdesek": "Válassz egy kérdést!", "kartya": "Ez a bizonyítékod. Olvasd el, aztán csukd be az ablakot!",
			"csoport": "Jelölj be egy kártyát, aztán kattints: Ezzel érvelek."}.get(_tutor_ctx, "")
	if world.steps <= 0:
		return "Elfogytak a lépéseid. Kattints: Következő 5 év."
	if world.hand.is_empty():
		return "Kezdd kutatással! Kattints a Kutatás gombra."
	if world.groups.any(func(g: Dictionary) -> bool: return world.can_convince(g)):
		return "Van kártyád! Kattints a világító csoportra."
	return "Kutass tovább, amíg van lépésed!"


func _tutor_update(ctx: String = "") -> void:
	_tutor_ctx = ctx
	if _tutor == null:
		_tutor = UI.label("", 19, UI.GOLD, true, false)
		_tutor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tutor.add_theme_stylebox_override("normal", _flat(Color(0.03, 0.05, 0.11, 0.94), UI.GOLD, 2, 10))
		_tutor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tutor.z_index = 20
		add_child(_tutor)
	var txt := L.t(_tutor_text()) if _tutor_text() != "" else ""
	_tutor.visible = txt != ""
	if txt == "" or txt == _tutor.text:
		return
	_tutor.text = "➜  " + txt if not txt.begins_with("➜") else txt
	_tutor.reset_size()
	_tutor.position = Vector2(340.0, 764.0)
	if not _test:
		_tutor.pivot_offset = _tutor.get_minimum_size() * 0.5
		_tutor.scale = Vector2(1.12, 1.12)
		_tutor.create_tween().tween_property(_tutor, "scale", Vector2.ONE, 0.25)


func _clock_runs() -> bool:
	if _clock_force:
		return true
	if _tutor_on() and not _clock_live:
		return false
	if _clock_live:
		return not _busy and _overlay == null and not world.over()
	return _time_on() and not _test and not _busy and _overlay == null and _intro == null and not world.over() \
		and not _menu.visible and not globe.dragging


## Mikor villanjon fel pillanat ebben a körben. Az első körben hamar jön egy, hogy rögtön történjen valami.
func _plan_moments() -> void:
	_clear_moment()
	_moment_times = [randf_range(4.0, 6.0), randf_range(50.0, 65.0)] if world.round_i == 0 else [randf_range(20.0, 60.0)]


var _moment_home: Array = []


func _clear_moment() -> void:
	_moment = {}
	if not _moment_home.is_empty():              # a Föld visszafordul oda, ahol a pillanat előtt állt
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
		tw.tween_property(globe, "spin", float(_moment_home[0]), 0.9)
		tw.tween_property(globe, "tilt", float(_moment_home[1]), 0.9)
		_moment_home = []
	if _moment_node != null:
		_moment_node.queue_free()
		_moment_node = null
	if _moment_lbl != null:
		_moment_lbl.queue_free()
		_moment_lbl = null


func _spawn_moment(kind: String = "") -> void:
	var open_g: Array = world.groups.filter(func(g: Dictionary) -> bool: return not g["konnyebb"] and not world.targets_for(g).is_empty())
	if kind == "":
		kind = "figyelem" if (not open_g.is_empty() and world.round_i > 0 and randf() < 0.5) else "felfedezes"
	if kind == "figyelem" and open_g.is_empty():
		kind = "felfedezes"
	if kind == "figyelem":
		var g: Dictionary = open_g[randi() % open_g.size()]
		_moment = {"fajta": kind, "csoport": g["id"], "lat": g["lat"], "lon": g["lon"]}
	else:
		var tp: Dictionary = world.tips[randi() % world.tips.size()]
		_moment = {"fajta": kind, "lat": tp["lat"], "lon": tp["lon"]}
	_moment_home = [globe.spin, globe.tilt]
	globe.look_at_event(_moment)
	_moment_node = Moment.new()
	_moment_node.color = UI.GOLD if kind == "figyelem" else UI.CYAN
	_moment_node.total = MOMENT_SECONDS
	_moment_node.left = MOMENT_SECONDS
	_moment_node.picked.connect(_pick_moment)
	_moment_lbl = UI.label(L.t("Most figyelnek rád!") if kind == "figyelem" else L.t("Új felfedezés!"), 22, _moment_node.color, true, false)
	_moment_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_moment_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08))
	_moment_lbl.add_theme_constant_override("outline_size", 6)
	add_child(_moment_node)
	add_child(_moment_lbl)
	var after: Node = _group_cards[world.groups[0]["id"]]["gomb"]
	move_child(_moment_node, after.get_index())      # a kártyák és az ablakok alatt, a Föld fölött
	move_child(_moment_lbl, _moment_node.get_index() + 1)
	_place_moment()
	_sound("jo_hir")


func _place_moment() -> void:
	if _moment_node == null:
		return
	var p: Vector3 = globe.project(float(_moment["lat"]), float(_moment["lon"]))
	var at: Vector2 = globe.position + Vector2(p.x, p.y)
	_moment_node.visible = p.z > 0.5
	_moment_lbl.visible = p.z > 0.5
	_moment_node.position = at - _moment_node.size * 0.5
	_moment_lbl.position = at + Vector2(-_moment_lbl.size.x * 0.5, 64)


func _pick_moment() -> void:
	if _moment.is_empty() or _busy or _overlay != null:
		return
	var m := _moment
	_clear_moment()
	globe.flash(float(m["lat"]), float(m["lon"]), UI.GOLD if m["fajta"] == "figyelem" else UI.CYAN)
	if m["fajta"] == "figyelem":
		if world.moment_attention(str(m["csoport"])):
			_refresh()
			_open_group(world.group(str(m["csoport"])))
	else:
		world.moment_discovery()
		_sound("jo_hir")
		_refresh()
		_float_text(L.t("+1 lépés"), Vector2(960, 120), UI.CYAN)     # a lépések számlálója alatt


## Rövid, felszálló felirat (például „+1 lépés”).
func _float_text(text: String, at: Vector2, color: Color) -> void:
	var l := UI.label(text, 26, color, true, false)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08))
	l.add_theme_constant_override("outline_size", 8)
	l.position = at - Vector2(50, 20)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


func _process(delta: float) -> void:
	if _sat != null:
		_sat.visible = _intro == null
	if world == null or _clock_bar == null or _menu == null:
		return
	(_clock_bar.get_parent() as Control).visible = (_time_on() and not world.over() and not _test) or _clock_force
	if not _clock_runs():
		return
	_clock += delta
	var k := clampf(_clock / _round_s(), 0.0, 1.0)
	_clock_bar.size.x = 150.0 * (1.0 - k)
	_clock_bar.color = UI.EMBER if k > 0.85 else UI.CYAN
	var left := int(ceilf(_round_s() - _clock))
	if left <= 8 and left != _tick_left and left > 0:        # az utolsó másodpercekben ketyeg az óra
		_sound("ora")
		_clock_bar.get_parent().scale = Vector2(1.0, 2.2)
		_clock_bar.create_tween().tween_property(_clock_bar.get_parent(), "scale", Vector2.ONE, 0.3)
	_tick_left = left
	(_stats["ev"] as Label).text = str(world.year() + mini(World.ROUND_YEARS - 1, int(k * World.ROUND_YEARS)))
	if _moment.is_empty():
		if not _moment_times.is_empty() and _clock >= float(_moment_times[0]):
			_moment_times.pop_front()
			_spawn_moment()
	else:
		_moment_node.left -= delta
		_place_moment()
		if _moment_node.left <= 0.0:
			_clear_moment()
	if _clock >= _round_s() and not _clock_force:
		_advance()


func _ready() -> void:
	L.init()
	UI.load_fonts()
	Cards.load_all()
	theme = _make_theme()
	get_tree().node_added.connect(_on_node_added)
	var args := OS.get_cmdline_user_args()
	_test = "--onteszt" in args or "--bejaras" in args
	_dry = (_test and not ("--eles" in args)) or "--elojatek" in args or "--majom" in args
	L.dry = _dry
	if _test or "--intro-kepek" in args or "--elojatek" in args or "--majom" in args:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)   # az ellenőrző futások ablakban mennek
	var bg := TextureRect.new()
	bg.texture = load("res://assets/nebula_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(bg)
	var stars := Twinkle.new()
	stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stars)
	_bg_nodes = [bg, stars]

	world = World.new()
	var saved: Variant = null if _test else World.read_json(SAVE)
	if typeof(saved) != TYPE_DICTIONARY or not world.from_dict(saved):
		world.new_game(2026 if _test else -1)
		world.gentle = not _test and not bool(L.get_setting("tanulo_kesz", false))      # az első játék szelídebb

	globe = Globe.new()
	globe.position = Vector2(400, 44)
	globe.size = Vector2(800, 800)
	_sat = Satellite.new()
	_sat.set_anchors_preset(Control.PRESET_FULL_RECT)
	globe.fixed_sun = true
	globe.station_clicked.connect(func(s: Dictionary) -> void:
		if s.has("id") and _overlay == null:
			_open_group(world.group(s["id"])))
	add_child(globe)
	_sat.visible = false
	add_child(_sat)

	_build_top()
	_build_groups()
	_build_bottom()
	_build_menu()
	_refresh()
	if "--bejaras" in args:
		_walkthrough()
		return
	if "--elojatek" in args:
		_live_play()
		return
	if "--majom" in args:
		var ms := 1
		var secs := 150.0
		for a in args:
			if str(a).begins_with("--mag="):
				ms = int(str(a).trim_prefix("--mag="))
			if str(a).begins_with("--mp="):
				secs = float(str(a).trim_prefix("--mp="))
		_monkey(ms, secs)
		return
	if _test:
		_selftest()
		return
	globe.stations = [{"name": "", "lat": 47.5, "lon": 19.0, "color": UI.GOLD, "me": true}]   # a nyitány „hívás” képéhez
	_intro = Intro.new()
	_intro.main = self
	if "--intro-kepek" in args:
		_intro.shots_dir = OS.get_user_data_dir().path_join("aether_onteszt")
		DirAccess.make_dir_recursive_absolute(_intro.shots_dir)
	add_child(_intro)
	await _intro.finished
	_intro = null
	if "--intro-kepek" in args:
		get_tree().quit()
		return
	_refresh()
	_plan_moments()
	get_tree().create_timer(12.0).timeout.connect(_start_music)
	if not bool(L.get_setting("uj_sugo_latta", false)):
		_open_help()
		L.set_setting("uj_sugo_latta", true)
	elif not world.news.is_empty():
		pass


# --- a nyitány (intro.gd) ezeket kéri a főképernyőtől -------------------------
func intro_keep() -> Array:
	return _bg_nodes + [globe]


func load_anomaly_quietly() -> void:
	pass


func anomaly_ready() -> bool:
	return false


func warming_text() -> String:
	return "+%s °C" % L.num(float(world.st["T"]), 2)


var _click: AudioStreamPlayer

## Halk kattanás minden gombnyomásra (külön lejátszó, hogy ne vágja el a többi hangot).
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n is CheckBox):
		(n as BaseButton).pressed.connect(func() -> void:
			if _dry or not _sounds_on():
				return
			if _click == null:
				_click = AudioStreamPlayer.new()
				_click.volume_db = -14.0
				_click.stream = load("res://assets/hang/kattintas.wav")
				add_child(_click)
			_click.play())


func _sounds_on() -> bool:
	return bool(L.get_setting("hangok", true))


func _sound(name: String) -> void:
	if _dry or not _sounds_on():
		return
	if _snd == null:
		_snd = AudioStreamPlayer.new()
		_snd.volume_db = -8.0
		add_child(_snd)
	_snd.stream = load("res://assets/hang/%s.wav" % name)
	_snd.play()


# --- téma ---------------------------------------------------------------------
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UI.font_body
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", _frame("res://assets/ui/panel.png", 12, 18))
	var imgs := {"normal": "gomb", "disabled": "gomb", "hover": "gomb_folotte", "pressed": "gomb_lenyomva", "hover_pressed": "gomb_lenyomva"}
	for state in imgs:
		var b := _frame("res://assets/ui/%s.png" % imgs[state], 8, 10)
		b.content_margin_left = 16
		b.content_margin_right = 16
		t.set_stylebox(state, "Button", b)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_font("font", "Button", UI.font_bold)
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_disabled_color", "Button", Color(UI.MUTE, 0.55))
	t.set_color("font_color", "Label", UI.TEXT)
	return t


func _frame(path: String, margin: int, content: int) -> StyleBox:
	var tex: Texture2D = load(path)
	if tex == null:
		var f := StyleBoxFlat.new()
		f.bg_color = UI.PANEL_BG
		f.border_color = UI.EDGE
		f.set_border_width_all(2)
		f.set_content_margin_all(content)
		return f
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.set_texture_margin_all(margin)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.set_content_margin_all(content)
	return s


func _flat(bg: Color, border: Color, width: int = 2, margin: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(9)
	sb.set_content_margin_all(margin)
	return sb


# --- felület ------------------------------------------------------------------
func _stat(parent: Control, key: String, caption: String, color: Color, sub: bool = false, tip: String = "") -> void:
	var v := UI.vbox(-3)
	if tip != "":           # mihez képest értendő a szám: az egérrel fölé állva látszik
		v.tooltip_text = tip
		v.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(UI.label(caption, 14, UI.MUTE, false, false))
	var l := UI.label("", 21, color, true, false)
	v.add_child(l)
	_stats[key] = l
	if sub:
		var s := UI.label("", 14, UI.SOFT, false, false)
		v.add_child(s)
		_stats[key + "_al"] = s
	parent.add_child(v)


func _build_top() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(1600, 70)
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = 26
	bare.content_margin_right = 22
	bare.content_margin_top = 8
	p.add_theme_stylebox_override("panel", bare)
	add_child(p)
	var h := UI.hbox(36)
	p.add_child(h)
	var logo := UI.label("AETHER", 32, UI.CYAN, false, false)
	logo.add_theme_font_override("font", UI.font_pixel)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(logo)
	_stat(h, "ev", L.t("Év"), UI.TEXT, true)
	_stat(h, "meleg", L.t("Melegedés"), UI.EMBER, true, L.t("Az 1850–1900-as évek átlagához képest."))
	_stat(h, "tenger", L.t("Tenger 2100-ban"), Color("#6ab8ff"), false, L.t("Az 1995–2014-es évek átlagához képest (IPCC AR6)."))
	_stat(h, "kibocs", L.t("A világ CO2-kibocsátása"), UI.GREEN, false, L.t("A 2025-ös kibocsátáshoz képest; a kivont CO2-t levonjuk belőle."))
	_stat(h, "lepes", L.t("Lépéseid"), UI.CYAN)
	_dots = _stats["lepes"]
	var bar_bg := ColorRect.new()                 # a körből hátralévő idő sávja az évszám alatt
	bar_bg.color = Color(1, 1, 1, 0.10)
	bar_bg.position = Vector2(174, 68)
	bar_bg.size = Vector2(150, 4)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)
	_clock_bar = ColorRect.new()
	_clock_bar.color = UI.CYAN
	_clock_bar.size = Vector2(150, 4)
	_clock_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_clock_bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var mb := UI.button(L.t("Menü"))
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mb.focus_mode = Control.FOCUS_NONE
	mb.pressed.connect(func() -> void: _show_menu(not _menu.visible))
	h.add_child(mb)


var _land_frame := 0
var _pulse_n := 0


## Lüktető keret a csoport kártyáján (baj fenyeget: parázsszín; bizonytalan: arany).
func _pulse(gid: String, on: bool, color: Color = Color.WHITE) -> void:
	var entry: Dictionary = _group_cards[gid]
	var old: Variant = entry.get("lukt")
	if old != null and is_instance_valid(old):
		if on and (old as Panel).get_meta("szin") == color:
			return
		(old as Panel).queue_free()
	entry["lukt"] = null
	if not on:
		return
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _flat(Color(color, 0.07), color, 3))
	p.set_meta("szin", color)
	(entry["gomb"] as Button).add_child(p)
	entry["lukt"] = p
	var tw := p.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tw.tween_property(p, "modulate:a", 0.15, 0.7)
	tw.tween_property(p, "modulate:a", 1.0, 0.7)


## A csoport tájképe most: baj idején a bajt mutatja, cél után szélkerekeket, nulla kibocsátás után madarakat is.
func _land_tex(g: Dictionary) -> Texture2D:
	if str(g.get("baj", "")) != "":
		return Landscape.disaster(str(g["id"]), str(g["baj"]))
	return Landscape.texture(str(g["id"]), int(g["cel"]) > 0, _land_frame, int(g.get("nulla", 0)) > 0)


## A kártyák tájképei élnek: a szélkerekek forognak, az eső esik.
func _tick_landscapes() -> void:
	_land_frame = 1 - _land_frame
	_pulse_n += 1
	if _pulse_n % 5 == 0 and _overlay == null and not _busy and not world.over():     # a Földön is látszik, kire kell figyelni
		for g in world.groups:
			if _threat_on(g) != "":
				globe.flash(float(g["lat"]), float(g["lon"]), UI.EMBER)
			elif world.myth_on(g):
				globe.flash(float(g["lat"]), float(g["lon"]), MYTH_COLOR)
			elif g.get("inog", false):
				globe.flash(float(g["lat"]), float(g["lon"]), UI.GOLD)
	for gid in _group_cards:
		var g: Dictionary = world.group(gid)
		if not g.is_empty():
			(_group_cards[gid]["taj"] as TextureRect).texture = _land_tex(g)


func _build_groups() -> void:
	var lt := Timer.new()
	lt.wait_time = 0.6
	lt.autostart = true
	lt.timeout.connect(_tick_landscapes)
	add_child(lt)
	for i in world.groups.size():
		var g: Dictionary = world.groups[i]
		var b := Button.new()
		b.position = Vector2(18 if i < 3 else 1600 - 18 - 300, 100 + (i % 3) * 218)
		b.custom_minimum_size = Vector2(300, 202)
		b.size = Vector2(300, 202)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var col := Color(str(g["szin"]))
		b.add_theme_stylebox_override("normal", _flat(Color(0.04, 0.06, 0.12, 0.88), Color(col, 0.55)))
		b.add_theme_stylebox_override("hover", _flat(Color(0.07, 0.11, 0.2, 0.95), col, 3))
		b.add_theme_stylebox_override("pressed", _flat(Color(0.07, 0.11, 0.2, 0.95), col, 3))
		var gid := str(g["id"])
		b.pressed.connect(func() -> void: _open_group(world.group(gid)))
		b.mouse_entered.connect(func() -> void:
			globe.look_at_event({"lat": g["lat"], "lon": g["lon"]})
			_ghost_show(gid))
		b.mouse_exited.connect(func() -> void: _curve.set_ghost([]))
		var wash := TextureRect.new()             # halvány színmosás a csoport színével, felülről lefelé
		var grad := Gradient.new()
		grad.set_color(0, Color(col, 0.17))
		grad.set_color(1, Color(col, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 4
		gt.height = 64
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		wash.texture = gt
		wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wash.stretch_mode = TextureRect.STRETCH_SCALE
		wash.position = Vector2(4, 4)
		wash.size = Vector2(292, 120)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(wash)
		var land := Landscape.rect(gid, 70)
		land.position = Vector2(300 - 9 - 70, 8)
		b.add_child(land)
		var v := UI.vbox(4)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_top = 10
		v.offset_right = -14
		v.offset_bottom = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		add_child(b)
		_group_cards[gid] = {"gomb": b, "doboz": v, "taj": land}


var _best_target: Dictionary = {}     # csoport -> a most elérhető legjobb cél (a görbe előnézetéhez)


## Ha a kártyára mutatsz, a görbén szaggatott vonal mutatja, hová vinne a csoport legjobb elérhető megállapodása.
func _ghost_show(gid: String) -> void:
	var g := world.group(gid)
	if _overlay != null or _busy or world.over() or g.is_empty() or not _best_target.has(gid) or not world.can_convince(g):
		return
	if not (int(_best_target[gid]) in world.targets_for(g)):
		return
	_curve.set_ghost(world.preview_path(g, int(_best_target[gid])), Color(str(g["szin"])).lightened(0.25))


var _bar_shown: Dictionary = {}       # "játék/csoport" -> a kártyán utoljára mutatott kibocsátás-arány
var _bar_hold := false                # körváltás: a hírek ablaka mindjárt eltakarja a kártyákat
var _bar_pending := false             # van még le nem játszott sávcsökkenés


func _bars_play() -> void:
	if not _bar_pending or _overlay != null or _busy:
		return
	_bar_pending = false
	for g in world.groups:
		_fill_group(g)


func _fill_group(g: Dictionary) -> void:
	var v: VBoxContainer = _group_cards[g["id"]]["doboz"]
	UI.clear(v)
	var col := Color(str(g["szin"]))
	(_group_cards[g["id"]]["taj"] as TextureRect).texture = _land_tex(g)
	var name_l := UI.label(L.field(g, "nev"), 20, col, true, false)
	v.add_child(name_l)
	v.add_child(_lbl(L.t("A világ CO2-kibocsátásának %s%%-a") % L.num_short(float(g["co2_resz"]) * 100.0, 0), 13, UI.MUTE))
	# a mostani kibocsátásuk a maihoz képest
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = World.fraction(g, world.year() - 1)
	bar.custom_minimum_size = Vector2(0, 8)
	bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, 0))
	bar.add_theme_stylebox_override("fill", _flat(Color(col, 0.9), Color.TRANSPARENT, 0, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar_row := UI.hbox(8)
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(bar)
	bar_row.add_child(_lbl("%d%%" % roundi(bar.value * 100.0), 13, UI.SOFT))
	(bar_row.get_child(1) as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(bar_row)
	# körváltáskor a sáv és a szám láthatóan csökken az előző értékről (ugyanabban a játékban)
	var return_bar := false
	var key := "%d/%s" % [world.game_id, str(g["id"])]
	var shown: float = float(_bar_shown.get(key, bar.value))
	if not _test and absf(shown - bar.value) > 0.004 and (_overlay != null or _bar_hold):
		bar.value = shown              # ablak takarja: a régi érték marad, a csökkenés az ablak bezárása után látszik
		(bar_row.get_child(1) as Label).text = "%d%%" % roundi(shown * 100.0)
		_bar_pending = true
		return_bar = true
	elif not _test and absf(shown - bar.value) > 0.004:
		var target: float = bar.value
		var pct: Label = bar_row.get_child(1)
		bar.value = shown
		pct.text = "%d%%" % roundi(shown * 100.0)
		pct.add_theme_color_override("font_color", UI.GREEN if target < shown else UI.EMBER)
		var btw := bar.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		btw.tween_interval(0.3)
		btw.tween_method(func(x: float) -> void:
			bar.value = x
			pct.text = "%d%%" % roundi(x * 100.0), shown, target, 1.3)
		btw.tween_callback(func() -> void: pct.add_theme_color_override("font_color", UI.SOFT))
	if not return_bar:
		_bar_shown[key] = World.fraction(g, world.year() - 1)
	if int(g.get("nulla", 0)) > 0:
		v.add_child(_lbl("★ " + L.t("Nulla kibocsátás %d óta") % int(g["nulla"]), 16, UI.GREEN, true))
	elif int(g["cel"]) > 0:
		v.add_child(_lbl(L.rag(L.t("Nulla kibocsátás %d-re") % int(g["cel"])), 16, UI.GREEN, true))
	else:
		v.add_child(_lbl(L.t("Még nem vállalt semmit"), 16, UI.SOFT, true))
	var extras: Array = []
	if int(g["metan"]) > 0:
		extras.append(L.t("Metán: −30%"))
	if g.get("felkeszult", false):
		extras.append(L.t("Felkészült"))
	if not extras.is_empty():
		v.add_child(_lbl("✔ " + " · ✔ ".join(extras), 14, UI.GREEN))
	var n := world.usable(g).size()
	var shaky: bool = g.get("inog", false) and not world.over()
	var danger := _threat_on(g)
	if shaky:
		v.add_child(_lbl("⚠ " + L.t("Bizonytalan"), 15, UI.GOLD, true))
	if danger != "":
		v.add_child(_lbl("⚠ " + L.t(THREAT[danger]), 15, UI.EMBER, true))
	var mythy := world.myth_on(g) and not world.over()
	if mythy:
		v.add_child(_lbl("⚠ " + L.t("Tévhit terjed"), 15, MYTH_COLOR, true))
	_pulse(str(g["id"]), (danger != "" or shaky or mythy) and not world.over(), UI.EMBER if danger != "" else (MYTH_COLOR if mythy else UI.GOLD))
	var fears := HFlowContainer.new()
	fears.visible = int(shaky) + int(danger != "") + int(mythy) < 2
	fears.add_theme_constant_override("h_separation", 3)
	fears.add_theme_constant_override("v_separation", 4)
	fears.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for th in g["felelmek"]:
		var ch := _chip(_theme_name(th), _theme_color(th))
		ch.add_theme_font_size_override("font_size", 11)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fears.add_child(ch)
	v.add_child(fears)
	if fears.is_inside_tree():
		_fit_chips(fears)
	else:
		fears.ready.connect(_fit_chips.bind(fears))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	if danger != "" and world.steps > 0 and not world.prepare_cards(g).is_empty():
		v.add_child(_lbl(L.t("Készítsd fel őket") + " →", 15, UI.EMBER, true))
	elif mythy and world.steps > 0:
		v.add_child(_lbl((L.t("Cáfold meg") if str(world.myth["kartya"]) in world.hand else L.t("Kutasd ki a cáfolatot")) + " →", 15, MYTH_COLOR, true))
	elif shaky and n > 0 and world.steps > 0:
		v.add_child(_lbl(L.t("Erősítsd meg őket") + " →", 15, UI.GOLD, true))
	elif world.can_convince(g):
		var best := 0.0                # a most elérhető legjobb megállapodás hatása 2100-ra
		for t in world.targets_for(g):
			if n >= world.cards_needed(g, t):
				var pv := world.preview(g, t)
				if pv < best:
					best = pv
					_best_target[str(g["id"])] = int(t)
		var gain := ""
		if best < -0.004:
			var bs := "%.2f" % best
			gain = " · %s °C" % (bs if L.is_en() else bs.replace(".", ",")).replace("-", "−")
		v.add_child(_lbl(L.t("Meggyőzheted őket") + gain + " →", 15, UI.CYAN, true))
	elif world.targets_for(g).is_empty() and int(g["metan"]) > 0 and g.get("felkeszult", false):
		v.add_child(_lbl(L.t("Tőlük már nincs mit kérned."), 14, UI.GREEN))
	elif g["konnyebb"] and not world.targets_for(g).is_empty():
		v.add_child(_lbl(L.t("Most könnyebb meggyőzni"), 14, UI.GOLD))
	elif n > 0 or not world.hand.is_empty():     # üres kézzel nincs mit mondani
		v.add_child(_lbl(L.t("%d kártyád szól nekik") % n if n > 0 else L.t("Nincs hozzájuk illő kártyád"), 14, UI.SOFT if n > 0 else UI.MUTE))


func _lbl(text: String, size: int, color: Color, bold: bool = false) -> Label:
	var l := UI.label(text, size, color, bold, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_bottom() -> void:
	var h := UI.hbox(12)
	h.position = Vector2(26, 800)
	h.size = Vector2(1548, 86)
	add_child(h)
	for row in [["kutatas", L.t("Kutatás"), 150, _open_research], ["kartyak", L.t("Kártyáim"), 150, _open_hand],
			["kivonas", L.t("CO2-kivonás"), 160, _open_cdr], ["ido", L.t("Következő 5 év") + "  ▶", 210, _advance_click]]:
		var b := UI.button(row[1])
		b.custom_minimum_size = Vector2(row[2], 54)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(row[3])
		var col := UI.vbox(3)
		col.alignment = BoxContainer.ALIGNMENT_END
		var tag := UI.label(L.t("Következő lépés"), 13, UI.CYAN, false, false)
		tag.modulate.a = 0.0
		col.add_child(tag)
		col.add_child(b)
		b.set_meta("tag", tag)
		h.add_child(col)
		_btns[row[0]] = b
	var gap := UI.vbox(0)
	gap.alignment = BoxContainer.ALIGNMENT_END
	gap.custom_minimum_size = Vector2(190, 0)
	h.add_child(gap)
	var mb := UI.button(L.t("Küldetések"), false)
	mb.custom_minimum_size = Vector2(176, 44)
	mb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mb.focus_mode = Control.FOCUS_NONE
	mb.add_theme_font_size_override("font_size", 16)
	mb.pressed.connect(_open_missions)
	gap.add_child(mb)
	_mission_btn = mb
	_curve = Chart.new()
	_curve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_curve)


func _build_menu() -> void:
	_menu_catch = Control.new()
	_menu_catch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_catch.visible = false
	_menu_catch.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_show_menu(false))
	add_child(_menu_catch)
	_menu = PanelContainer.new()
	_menu.custom_minimum_size = Vector2(300, 0)
	_menu.position = Vector2(1600 - 18 - 300, 64)
	_menu.z_index = 8
	_menu.visible = false
	add_child(_menu)
	var v := UI.vbox(8)
	_menu.add_child(v)
	var help := UI.button(L.t("Hogyan játssz?"))
	help.pressed.connect(func() -> void:
		_show_menu(false)
		_open_help())
	v.add_child(help)
	var lang := UI.button("English" if not L.is_en() else "Magyar")
	lang.pressed.connect(func() -> void:
		L.set_lang("hu" if L.is_en() else "en")
		get_tree().reload_current_scene())
	v.add_child(lang)
	var story := UI.button(L.t("A te történeted"))
	story.pressed.connect(func() -> void:
		_show_menu(false)
		_open_story())
	v.add_child(story)
	var coll := UI.button(L.t("Gyűjtemény"))
	coll.pressed.connect(func() -> void:
		_show_menu(false)
		_open_collection())
	v.add_child(coll)
	var mus := UI.button(L.t("Zene: be") if _music_on() else L.t("Zene: ki"))
	mus.pressed.connect(_toggle_music.bind(mus))
	v.add_child(mus)
	var snd := UI.button(L.t("Hangok: be") if _sounds_on() else L.t("Hangok: ki"))
	snd.pressed.connect(func() -> void:
		L.set_setting("hangok", not _sounds_on())
		snd.text = L.t("Hangok: be") if _sounds_on() else L.t("Hangok: ki"))
	v.add_child(snd)
	var tim := UI.button(L.t("Telő idő: be") if _time_on() else L.t("Telő idő: ki"))
	tim.pressed.connect(func() -> void:
		L.set_setting("elo_ido", not _time_on())
		tim.text = L.t("Telő idő: be") if _time_on() else L.t("Telő idő: ki")
		_clear_moment()
		_refresh())
	v.add_child(tim)
	_reset_btn = UI.button(L.t("Új játék"))
	_reset_btn.pressed.connect(_reset_game)
	v.add_child(_reset_btn)
	var daily := UI.button(L.t("A mai Föld"))
	var day_best: Variant = L.get_setting("napi_legjobb", {})
	if typeof(day_best) == TYPE_DICTIONARY and day_best.has(str(_daily_code())):     # a mai legjobb eredményed
		daily.text += " · +%s °C" % L.num(float(day_best[str(_daily_code())]), 2)
	daily.tooltip_text = L.t("Ma mindenki ugyanezt a Földet kapja.")
	daily.pressed.connect(func() -> void:
		_show_menu(false)
		_pick_game(_daily_code()))
	v.add_child(daily)
	var code_row := UI.hbox(6)
	var code := LineEdit.new()
	code.placeholder_text = L.t("Föld-kód")
	code.max_length = 6
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.add_theme_font_size_override("font_size", 17)
	code_row.add_child(code)
	var code_go := UI.button("→")
	code_go.focus_mode = Control.FOCUS_NONE
	var play_code := func() -> void:
		if code.text.strip_edges().is_valid_int() and int(code.text) >= 0:
			var n := int(code.text)
			code.text = ""
			_show_menu(false)
			_pick_game(n)
	code_go.pressed.connect(play_code)
	code.text_submitted.connect(func(_t: String) -> void: play_code.call())
	code_row.add_child(code_go)
	v.add_child(code_row)
	var quit := UI.button(L.t("Kilépés a játékból"))
	quit.pressed.connect(func() -> void:
		_save()
		get_tree().quit())
	v.add_child(quit)
	for b in v.get_children():
		if b is Button:
			(b as Button).focus_mode = Control.FOCUS_NONE


## A mai nap Föld-kódja (ééhhnn): aznap mindenki ugyanazt a Földet kapja.
## Csillagok a 2100-as melegedés szerint (a jelvények határaival): +2 °C alatt egy, +1,7 alatt kettő, +1,6 alatt három.
static func _stars(t: float) -> String:
	var n := 3 if t < 1.6 else (2 if t < 1.7 else (1 if t < 2.0 else 0))
	return "★".repeat(n) + "☆".repeat(3 - n)


## Hány egymást követő napon játszottad végig „A mai Föld”-et (a mai vagy a tegnapi nappal bezárólag).
func _daily_streak() -> int:
	var ds: Variant = L.get_setting("napi_sorozat", {})
	if typeof(ds) != TYPE_DICTIONARY or not ds.has("nap"):
		return 0
	var today := int(Time.get_unix_time_from_system() / 86400.0)
	return int(ds.get("db", 0)) if today - int(ds["nap"]) <= 1 else 0


func _daily_code() -> int:
	var d := Time.get_date_dict_from_system()
	return (int(d["year"]) % 100) * 10000 + int(d["month"]) * 100 + int(d["day"])


func _show_menu(on: bool) -> void:
	_menu.visible = on
	_menu_catch.visible = on


func _reset_game() -> void:
	if _reset_btn.text != L.t("Biztos? Kattints még egyszer!"):
		_reset_btn.text = L.t("Biztos? Kattints még egyszer!")
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if is_instance_valid(_reset_btn):
				_reset_btn.text = L.t("Új játék"))
		return
	_reset_btn.text = L.t("Új játék")
	_show_menu(false)
	_pick_game()


## Új játék előtt: fokozat választása (játékszabály: körönként hány lépésed van).
var _level_force := -1         # az önteszt képeihez

## Kihívás-lépcső (játékszabály): ha +2 °C alatt végzel a legmagasabb elért szinten, megnyílik a következő.
func _level_max() -> int:
	return clampi(int(L.get_setting("lepcso", 0)) if _level_force < 0 else _level_force, 0, World.CHALLENGE_MAX)


func _pick_game(code: int = -1, level: int = -1) -> void:
	var top := _level_max()
	var lv := top if level < 0 else clampi(level, 0, top)
	var body := _open(L.t("Új játék"), UI.CYAN)
	if top > 0:
		var lrow := UI.hbox(8)
		var ll := UI.label(L.t("Kihívás:"), 18, UI.GOLD, true, false)
		ll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lrow.add_child(ll)
		for i in top + 1:
			var lb := UI.button(str(i), i == lv)
			lb.focus_mode = Control.FOCUS_NONE
			lb.custom_minimum_size = Vector2(52, 0)
			lb.pressed.connect(func() -> void: _pick_game(code, i))
			lrow.add_child(lb)
		body.add_child(lrow)
		for i in range(1, lv + 1):
			body.add_child(UI.label("%d. %s" % [i, L.t(LEVELS[i])], 16, UI.SOFT))
	for row in [["Könnyű", 5], ["Közepes", 4], ["Nehéz", 3]]:
		var n: int = row[1]
		body.add_child(_go("%s · %s" % [L.t(row[0]), L.t("%d lépés körönként") % n], func() -> void: _new_game(code, n, lv), n == 4))


func _new_game(code: int = -1, steps_n: int = World.STEPS, level: int = 0) -> void:
	_close()
	world.new_game(code, steps_n, level)
	world.gentle = not _test and not bool(L.get_setting("tanulo_kesz", false))      # az első játék szelídebb
	_offers = {}
	_clock = 0.0
	_plan_moments()
	globe.home()
	_refresh()


func _save() -> void:
	if _dry:
		return
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(world.to_dict()))


# --- frissítés ----------------------------------------------------------------
func _refresh() -> void:
	var y := world.year()
	_best_target.clear()
	if _curve != null:
		_curve.set_ghost([])
	if world.over():
		(_stats["ev"] as Label).text = "2100"
		(_stats["ev_al"] as Label).text = L.t("vége")
	else:
		(_stats["ev"] as Label).text = ("%d–%d" % [y, y + World.ROUND_YEARS - 1]) if not (_time_on() and not _test) \
			else str(y + mini(World.ROUND_YEARS - 1, int(_clock / _round_s() * World.ROUND_YEARS)))
		(_stats["ev_al"] as Label).text = L.t("%d. kör a 15-ből") % (world.round_i + 1)
	var t := float(world.st["T"])
	(_stats["meleg"] as Label).text = "+%s °C" % L.num(t, 2)
	var fc := world.forecast()
	if not world.over():
		(_stats["meleg_al"] as Label).text = L.t("2100-ban: +%s és +%s °C között") % [L.num(minf(float(fc["also"][-1][1]), float(fc["felso"][-1][1])), 1), L.num(maxf(float(fc["also"][-1][1]), float(fc["felso"][-1][1])), 1)]
	else:
		(_stats["meleg_al"] as Label).text = ""
	var ratio := world.net_ratio(y)
	(_stats["kibocs"] as Label).text = (L.t("a mai %d%%-a") % roundi(ratio * 100.0)) if ratio > 0.005 else L.t("nulla alatt")
	(_stats["kibocs"] as Label).add_theme_color_override("font_color", UI.GREEN if ratio < 0.995 else UI.SOFT)
	(_stats["tenger"] as Label).text = L.t("kb. +%s cm") % L.num_short(M.sea_2100(float(fc["kozep"][-1][1]) if not world.over() else t) * 100.0, 0)
	_dots.text = "●".repeat(world.steps) + "○".repeat(maxi(world.max_steps - world.steps, 0))
	for g in world.groups:
		_fill_group(g)
	_curve.set_data(world.history, world.base_history, fc)
	# a Föld képe: melegedés, pára és városfény a kibocsátás szerint, zöldülés a kivonással
	globe.heat = clampf((t - M.T_START) / 2.0, 0.0, 1.5)
	globe.set_plan_look({"smog": clampf(ratio, 0.0, 1.0), "clean": clampf(1.0 - ratio, 0.0, 1.0), "regrow": clampf(-ratio / 0.25, 0.0, 1.0)})
	globe.sea_rise = clampf((t - M.T_START) / 2.0, 0.0, 1.0)
	var marks: Array = []
	for g in world.groups:
		var shaky: bool = g.get("inog", false) and not world.over()
		var danger := _threat_on(g)
		var mythy := world.myth_on(g) and not world.over()
		marks.append({"id": g["id"], "name": L.field(g, "nev") if danger == "" else "%s\n%s" % [L.field(g, "nev"), L.t(THREAT[danger])],
			"label": ("⚠ " if shaky or danger != "" or mythy else "") + L.field(g, "nev"), "lat": g["lat"], "lon": g["lon"],
			"color": UI.EMBER if danger != "" else (MYTH_COLOR if mythy else (UI.GOLD if shaky else Color(str(g["szin"]))))})
	for tp in world.tips:
		var rng_txt := L.t("küszöb: %s–%s °C") % [L.num(float(tp["also"]), 1), L.num(float(tp["felso"]), 1)]
		if int(tp["ev"]) > 0:
			marks.append({"name": "%s\n%s %d · %s" % [L.field(tp, "nev"), L.t("küszöb átlépve:"), int(tp["ev"]), rng_txt], "lat": tp["lat"], "lon": tp["lon"], "color": UI.EMBER, "small": true})
		elif t >= float(tp["also"]):       # a melegedés már a küszöb sávjában jár: bármikor átléphetjük
			marks.append({"name": "%s\n%s · %s" % [L.field(tp, "nev"), L.t("veszélysávban"), rng_txt], "lat": tp["lat"], "lon": tp["lon"], "color": UI.GOLD, "small": true, "dim": true, "warn": true})
		else:
			marks.append({"name": "%s\n%s" % [L.field(tp, "nev"), rng_txt], "lat": tp["lat"], "lon": tp["lon"], "color": Color(0.75, 0.82, 0.92), "small": true, "dim": true})
	globe.stations = marks
	var storms: Array = []
	for g in world.groups:
		if _threat_on(g) != "":
			storms.append({"lat": g["lat"], "lon": g["lon"], "kind": _threat_on(g)})
	globe.storms = storms
	var allies: Array = world.groups.filter(func(g: Dictionary) -> bool: return int(g["cel"]) > 0)
	allies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["lon"]) < float(b["lon"]))
	var lines: Array = []
	for i in range(1, allies.size()):
		lines.append([allies[i - 1]["lat"], allies[i - 1]["lon"], allies[i]["lat"], allies[i]["lon"]])
	globe.links = lines
	_mark_next()
	_tutor_update(_tutor_ctx)
	_save()


## Mi a következő lépés? Ha nincs lépésed: telik az idő. Ha van meggyőzhető csoport: az ő kártyája lüktet. Különben kutatás.
func _mark_next() -> void:
	var next := "kutatas"
	var hot := ""
	if world.over():
		next = ""
	elif world.steps <= 0:
		next = "ido"
	else:
		for g in world.groups:       # legelőször az, akit baj fenyeget, és fel tudod készíteni
			if _threat_on(g) != "" and not world.prepare_cards(g).is_empty():
				hot = g["id"]
				break
		for g in world.groups:       # aztán a megcáfolható tévhit
			if hot == "" and world.myth_on(g) and str(world.myth["kartya"]) in world.hand:
				hot = g["id"]
		for g in world.groups:       # aztán az, aki elbizonytalanodott, és van neki szóló kártyád
			if hot != "":
				break
			if g.get("inog", false) and not world.usable(g).is_empty():
				hot = g["id"]
				break
		for g in world.groups:
			if hot == "" and world.can_convince(g):
				hot = g["id"]
		if hot != "":
			next = ""
	for k in _btns:
		var b: Button = _btns[k]
		var on: bool = k == next
		(b.get_meta("tag") as Label).modulate.a = 1.0 if on else 0.0
		if on:
			b.add_theme_stylebox_override("normal", _flat(Color("#2b6b5e"), UI.CYAN, 3))
			b.add_theme_stylebox_override("hover", _flat(Color("#38816f"), UI.CYAN, 3))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_stylebox_override("hover")
			b.remove_theme_color_override("font_color")
	_btns["kutatas"].disabled = world.steps <= 0 or world.over()
	_btns["kivonas"].disabled = world.steps <= 0 or world.over()
	(_btns["kivonas"].get_parent() as Control).modulate.a = 1.0 if _ramp(3) else 0.0
	_btns["kivonas"].mouse_filter = Control.MOUSE_FILTER_STOP if _ramp(3) else Control.MOUSE_FILTER_IGNORE
	_adv_reset()
	_btns["kartyak"].text = "%s (%d)" % [L.t("Kártyáim"), world.hand.size()]
	_mission_btn.visible = not world.missions.is_empty() and _ramp(1)
	var md := world.missions_done()
	_mission_btn.text = "%s %d/%d" % [L.t("Küldetések"), md, world.missions.size()]
	if _mission_game != world.game_id:
		_mission_game = world.game_id
	elif md > _mission_seen:
		_sound("jo_hir")
		_mission_btn.modulate = Color(1.6, 1.4, 0.6)
		create_tween().tween_property(_mission_btn, "modulate", Color.WHITE, 2.5)
	_mission_seen = md
	for gid in _group_cards:
		var gb: Button = _group_cards[gid]["gomb"]
		var col := Color(str(world.group(gid)["szin"]))
		gb.add_theme_stylebox_override("normal", _flat(Color(0.04, 0.06, 0.12, 0.88), UI.CYAN if gid == hot else Color(col, 0.55), 3 if gid == hot else 2))
		if _group_cards[gid].get("lukt") != null and is_instance_valid(_group_cards[gid]["lukt"]):
			gb.move_child(_group_cards[gid]["lukt"], -1)


# --- ablakok ------------------------------------------------------------------
## Az ablak alján mindig látszó gomb (hosszú, görgethető tartalomnál sem kell keresni).
func _sticky(body: VBoxContainer, node: Control) -> void:
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.get_parent().get_parent().get_parent().add_child(node)


func _open(title: String, accent: Color = UI.GOLD) -> VBoxContainer:
	var keep := _flash_ids       # a felvillanás az ablak valódi bezárásakor jön, nem ablakváltáskor
	var fresh := _overlay == null or _pop_next
	_pop_next = false
	_flash_ids = []
	_close()
	_flash_ids = keep
	_show_menu(false)
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.02, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.z_index = 10
	_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close())
	add_child(_dim)
	var p := PanelContainer.new()
	p.position = Vector2(340, 40)
	p.custom_minimum_size = Vector2(920, 720)
	p.size = Vector2(920, 720)
	p.z_index = 11
	add_child(p)
	_overlay = p
	_tutor_update()
	if fresh and not _test:        # az új ablak finoman előugrik
		p.pivot_offset = Vector2(460, 360)
		p.scale = Vector2(0.94, 0.94)
		p.modulate.a = 0.0
		_dim.modulate.a = 0.0
		var pop := p.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(p, "scale", Vector2.ONE, 0.22)
		pop.tween_property(p, "modulate:a", 1.0, 0.14)
		pop.tween_property(_dim, "modulate:a", 1.0, 0.14)
	var outer := UI.vbox(10)
	p.add_child(outer)
	var head := UI.heading(title, 28)
	head.add_theme_color_override("font_color", accent)
	outer.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := UI.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(UI.scroll_pad(body, 18))
	_close_x = Button.new()
	_close_x.text = "X"
	_close_x.focus_mode = Control.FOCUS_NONE
	_close_x.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed"]:
		var sb := _flat(Color("#8a2b2b") if st != "normal" else Color("#1a2238"), UI.CYAN, 3, 0)
		sb.set_corner_radius_all(22)
		_close_x.add_theme_stylebox_override(st, sb)
	_close_x.size = Vector2(44, 44)
	_close_x.position = p.position + Vector2(920 - 22, -22)
	_close_x.z_index = 12
	_close_x.pressed.connect(_close)
	add_child(_close_x)
	_body = body
	_fit.call_deferred()
	return body


## Az ablak magassága a tartalomhoz igazodik (legfeljebb 720), és függőlegesen középre kerül.
func _fit() -> void:
	await get_tree().process_frame
	if _overlay == null or not is_instance_valid(_overlay) or _body == null or not is_instance_valid(_body):
		return
	var p: Control = _overlay
	var body: Control = _body
	var extra := 0.0               # az ablak alján mindig látszó gombok helye
	var outer := body.get_parent().get_parent().get_parent()
	for i in range(2, outer.get_child_count()):
		extra += (outer.get_child(i) as Control).get_combined_minimum_size().y + 10.0
	var h := clampf(body.get_combined_minimum_size().y + 118.0 + extra, 240.0, 720.0)
	p.custom_minimum_size.y = h
	p.size.y = h
	p.position.y = maxf(40.0, (800.0 - h) * 0.5)
	if _close_x != null:
		_close_x.position = p.position + Vector2(920 - 22, -22)


var _sat: Satellite
var _pop_next := false         # a következő ablak akkor is előugrik, ha ablakból nyílik (új kártya, megállapodás)
var _bonus_float := false
var _flash_ids: Array = []        # akiknél az ablak bezárása után felvillanás jár (egyezség, megerősítés, csúcs)

func _close() -> void:
	for n in [_overlay, _dim, _close_x]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_overlay = null
	_dim = null
	_close_x = null
	_tutor_update()
	for gid in _flash_ids:
		var g := world.group(gid)
		if g.is_empty() or not _group_cards.has(gid):
			continue
		globe.flash(float(g["lat"]), float(g["lon"]), Color(str(g["szin"])).lightened(0.3))
		var card: Control = _group_cards[gid]["gomb"]
		card.modulate = Color(1.9, 1.9, 1.9)
		create_tween().tween_property(card, "modulate", Color.WHITE, 0.2 if _test else 1.2)
	_flash_ids = []
	if _bonus_float:
		_bonus_float = false
		_sound("lendulet")
		_float_text(L.t("+1 lépés"), _dots.global_position + Vector2(60, 40), UI.GOLD)
		_dots.modulate = Color(2.2, 1.9, 0.8)
		create_tween().tween_property(_dots, "modulate", Color.WHITE, 1.5)
	if _bar_pending:
		_bars_play.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _intro != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _overlay != null:
			_close()
		elif event.keycode == KEY_ESCAPE:
			_show_menu(not _menu.visible)
		elif event.keycode == KEY_SPACE and _overlay == null and not _menu.visible and world.steps <= 0:
			_advance()             # szóköz: ha elfogytak a lépések, jöhet a következő öt év
		elif event.keycode == KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _fit_chips(fears: Control) -> void:
	# ha a címkék nem férnek el egy sorban, kisebb betűvel írjuk, hogy a kártya alja ne csússzon ki
	for fs in [12, 11, 10, 9]:
		var w := 0.0
		for ch in fears.get_children():
			var l := ch as Label
			l.add_theme_font_size_override("font_size", fs)
			w += l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			w += l.get_theme_stylebox("normal").get_minimum_size().x + 4.0
		if w <= 270.0:
			break


func _chip(text: String, color: Color) -> Label:
	var l := UI.label(text, 14, color, true, false)
	l.add_theme_stylebox_override("normal", _flat(Color(color, 0.14), Color(color, 0.6), 1, 5))
	return l


func _go(text: String, fn: Callable, primary: bool = true) -> Button:
	var b := UI.button(text, primary)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	return b


func _theme_name(th: String) -> String:
	return L.t(Cards.THEMES[th][0])


func _theme_color(th: String) -> Color:
	return Color(str(Cards.THEMES[th][1])) if Cards.THEMES.has(th) else UI.SOFT


# --- gyűjtemény és rekordok (több játékon át megmaradnak) -----------------------
func _collection() -> Array:
	var c: Variant = L.get_setting("gyujtemeny", [])
	return c if typeof(c) == TYPE_ARRAY else []


func _collect(id: String) -> void:
	if _dry:
		return
	var c := _collection()
	if not (id in c):
		var before := _rank(c.size())
		c.append(id)
		L.set_setting("gyujtemeny", c)
		if _rank(c.size()) != before:
			_new_rank = _rank(c.size())


## Rang a több játékon át kikutatott kártyák száma szerint (játékszabály): [ennyi kártyától, név].
const RANKS := [[0, "Gyakornok"], [10, "Kutató"], [30, "Vezető kutató"], [60, "Professzor"], [90, "A Föld őre"]]
var _new_rank := ""

func _rank(n: int) -> String:
	var out := ""
	for r in RANKS:
		if n >= int(r[0]):
			out = r[1]
	return out


## Jelvények: [azonosító, név, mit kell hozzá]. Több játékon át gyűlnek.
const BADGES := [
	["elso", "Első Föld", "Játssz végig egy játékot."],
	["ketfok", "Két fok alatt", "Maradj 2100-ban +2 °C alatt."],
	["masfel", "Kiváló Föld", "Maradj 2100-ban +1,7 °C alatt."],
	["mindenki", "Mindenki vállalta", "A játék végére mind a hat csoport vállaljon nulla kibocsátást."],
	["metan", "Metánvadász", "Mind a hat csoport vállaljon metáncsökkentést."],
	["meresz", "Merész cél", "Érd el, hogy egy csoport tizenöt év alatt vállalja a nulla kibocsátást."],
	["kuszob", "Egy küszöb sem", "Játssz végig egy játékot úgy, hogy egy billenőpont küszöbét sem lépitek át."],
	["kivonas", "Tisztító", "Indíts el legalább három CO2-kivonást egy játékban."],
	["felkeszult", "Senki sem marad magára", "Segíts mind a hat csoportnak felkészülni a bajra."],
	["nehez", "Nehéz Föld", "Maradj +2 °C alatt egy átlagnál érzékenyebb Földön."],
	["mester", "Mester", "Maradj +2 °C alatt nehéz fokozaton."],
	["huvos", "Hűvös Föld", "Maradj 2100-ban +1,6 °C alatt."],
	["szilard", "Egy megingás sem", "Játssz végig egy játékot úgy, hogy egy csoport sem tolja későbbre a célját."],
	["gyors", "Gyors kezdés", "Érd el, hogy 2040 előtt mind a hat csoport vállaljon célt."],
	["napi", "Napi Föld", "Játssz végig egy játékot „A mai Föld” gombbal."],
	["gyujto", "Gyűjtő", "Kutass ki ötven különböző kártyát."],
	["tudos", "Mindenhez értesz", "Legyen kártyád mind a nyolc témakörből a gyűjteményben."],
	["ovatos", "Óvatos tudós", "Kutass ki három kockázatos ötletet."],
	["kuldetes", "Küldetésteljesítő", "Teljesítsd mind a három küldetést egy játékban."],
	["tevhit", "Tévhitvadász", "Cáfolj meg három tévhitet egy játékban."],
	["vedo", "Időben szóltál", "Készíts fel három csoportot, mielőtt lecsap rájuk a baj."],
	["lepcso", "A lépcső teteje", "Maradj +2 °C alatt az ötödik kihíváson."],
]
var _end_info: Dictionary = {}


func _badges() -> Array:
	var b: Variant = L.get_setting("jelvenyek", [])
	return b if typeof(b) == TYPE_ARRAY else []


## A játék végén egyszer: játékszám, legjobb eredmény, új jelvények.
func _finish_game(r: Dictionary) -> Dictionary:
	if _end_info.get("jatek", -1) == world.game_id:
		return _end_info
	_end_info = {"jatek": world.game_id, "rekord": false, "uj": []}
	if _dry or world.game_id == int(L.get_setting("utolso_jatek", -1)):
		return _end_info
	var t := float(r["T"])
	L.set_setting("utolso_jatek", world.game_id)
	L.set_setting("jatekok", int(L.get_setting("jatekok", 0)) + 1)
	L.set_setting("kuldetesek", int(L.get_setting("kuldetesek", 0)) + world.missions_done())
	if world.seed_v == _daily_code():
		var db: Variant = L.get_setting("napi_legjobb", {})
		if typeof(db) != TYPE_DICTIONARY:
			db = {}
		var key := str(world.seed_v)
		if not db.has(key) or t < float(db[key]):
			L.set_setting("napi_legjobb", {key: t})       # csak a mai napot őrizzük
		var today := int(Time.get_unix_time_from_system() / 86400.0)
		var ds: Variant = L.get_setting("napi_sorozat", {})
		if typeof(ds) != TYPE_DICTIONARY:
			ds = {}
		var last := int(ds.get("nap", -9))
		if last != today:
			L.set_setting("napi_sorozat", {"nap": today, "db": int(ds.get("db", 0)) + 1 if today - last == 1 else 1})
	var past: Variant = L.get_setting("foldek", [])
	if typeof(past) != TYPE_ARRAY:
		past = []
	var dd := Time.get_date_dict_from_system()
	past.push_front({"ev": int(dd["year"]), "ho": int(dd["month"]), "nap": int(dd["day"]), "T": t, "lepes": world.max_steps + (1 if world.challenge >= World.CHALLENGE_MAX else 0), "mag": world.seed_v})
	L.set_setting("foldek", past.slice(0, 12))
	if t < 2.0 and world.challenge >= _level_max() and world.challenge < World.CHALLENGE_MAX:
		L.set_setting("lepcso", world.challenge + 1)
		_end_info["lepcso"] = world.challenge + 1
	var best := float(L.get_setting("legjobb", 0.0))
	if best <= 0.0 or t < best - 0.004:
		L.set_setting("legjobb", t)
		_end_info["rekord"] = best > 0.0
	var c := _collection()
	var themes := {}
	for id in c:
		themes[Cards.theme_of(id)] = true
	var ok := {
		"elso": true, "ketfok": t < 2.0, "masfel": t < 1.7,
		"mindenki": world.groups.all(func(g: Dictionary) -> bool: return int(g["cel"]) > 0),
		"metan": world.groups.all(func(g: Dictionary) -> bool: return int(g["metan"]) > 0),
		"meresz": world.groups.any(func(g: Dictionary) -> bool: return int(g["fok"]) >= 4),
		"felkeszult": world.groups.all(func(g: Dictionary) -> bool: return g.get("felkeszult", false)),
		"kuszob": int(r["billenes"]) == 0, "kivonas": world.cdr.size() >= 3,
		"nehez": t < 2.0 and float(r["sens"]) >= 0.25,
		"mester": t < 2.0 and world.max_steps <= 3,
		"huvos": t < 1.6,
		"szilard": not world.naplo.any(func(e: Dictionary) -> bool: return e["fajta"] == "visszalepett"),
		"gyors": world.groups.all(func(g: Dictionary) -> bool:
			return world.naplo.any(func(e: Dictionary) -> bool: return e["fajta"] == "cel" and e.get("csoport", "") == g["id"] and int(e["ev"]) < 2040)),
		"napi": world.seed_v == _daily_code(),
		"ovatos": c.filter(func(id: String) -> bool: return Cards.theme_of(id) in Cards.NO_TALK).size() >= 3,
		"kuldetes": world.missions.size() >= 3 and world.missions_done() == world.missions.size(),
		"tevhit": world.naplo.filter(func(e: Dictionary) -> bool: return e["fajta"] == "cafolat").size() >= 3,
		"vedo": world.naplo.filter(func(e: Dictionary) -> bool: return e["fajta"] == "baj" and e.get("vedve", false)).size() >= 3,
		"lepcso": t < 2.0 and world.challenge >= World.CHALLENGE_MAX,
		"gyujto": c.size() >= 50, "tudos": Cards.talk_themes().all(func(th: String) -> bool: return themes.has(th)),
	}
	var have := _badges()
	for row in BADGES:
		if ok.get(row[0], false) and not (row[0] in have):
			have.append(row[0])
			_end_info["uj"].append(row[0])
	L.set_setting("jelvenyek", have)
	return _end_info


func _open_collection() -> void:
	var body := _open(L.t("Gyűjtemény"), UI.GOLD)
	var c := _collection()
	var all_n := 0
	for th in Cards.THEMES:
		all_n += Cards.TAGS[th].size()
	body.add_child(UI.label(L.t("Rangod: %s") % L.t(_rank(c.size())), 22, UI.GOLD, true))
	body.add_child(UI.label(L.t("Kikutatott kártyák: %d / %d") % [c.size(), all_n], 19, UI.TEXT, true))
	for r in RANKS:
		if int(r[0]) > c.size():
			body.add_child(UI.label(L.t("A következő rang: %s (%d kártyától)") % [L.t(r[1]), int(r[0])], 15, UI.SOFT))
			break
	var games := int(L.get_setting("jatekok", 0))
	if games > 0:
		body.add_child(UI.label(L.t("Befejezett játékok: %d · A legjobb Földed: +%s °C") % [games, L.num(float(L.get_setting("legjobb", 0.0)), 2)], 17, UI.GREEN))
	if _daily_streak() >= 2:
		body.add_child(UI.label(L.t("A mai Föld: %d napja játszod egymás után.") % _daily_streak(), 17, UI.GREEN))
	var mdone := int(L.get_setting("kuldetesek", 0))
	if mdone > 0:
		body.add_child(UI.label(L.t("Teljesített küldetések: %d") % mdone, 17, UI.GREEN))
	# jelvények: érmek egy sorban; alattuk az egér alatti (vagy a következő megszerezhető) jelvény neve és feltétele
	var have := _badges()
	body.add_child(UI.label(L.t("Jelvények: %d / %d") % [have.size(), BADGES.size()], 19, UI.GOLD, true, false))
	var medals := HFlowContainer.new()
	medals.add_theme_constant_override("h_separation", 4)
	medals.add_theme_constant_override("v_separation", 5)
	var medal_lbl := UI.label(" ", 16, UI.SOFT, false, false)
	var next_goal := " "
	for row in BADGES:
		if not (row[0] in have):
			next_goal = "☆ %s – %s" % [L.t(row[1]), L.t(row[2])]
			break
	medal_lbl.text = next_goal
	for row in BADGES:
		var got_b: bool = row[0] in have
		var m := Button.new()
		m.custom_minimum_size = Vector2(33, 36)
		m.focus_mode = Control.FOCUS_NONE
		m.text = "★" if got_b else "☆"
		m.add_theme_font_size_override("font_size", 20)
		for cn in ["font_color", "font_hover_color", "font_pressed_color"]:
			m.add_theme_color_override(cn, UI.GOLD if got_b else UI.MUTE)
		for st in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = (Color(0.2, 0.16, 0.06) if got_b else Color(0.05, 0.07, 0.12)).lightened(0.08 if st == "hover" else 0.0)
			sb.border_color = UI.GOLD if got_b else UI.EDGE
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(18)
			m.add_theme_stylebox_override(st, sb)
		var line := "%s %s – %s" % ["★" if got_b else "☆", L.t(row[1]), L.t(row[2])]
		var line_col := UI.GOLD if got_b else UI.SOFT
		m.mouse_entered.connect(func() -> void:
			medal_lbl.text = line
			medal_lbl.add_theme_color_override("font_color", line_col))
		m.mouse_exited.connect(func() -> void:
			medal_lbl.text = next_goal
			medal_lbl.add_theme_color_override("font_color", UI.SOFT))
		medals.add_child(m)
	body.add_child(medals)
	body.add_child(medal_lbl)
	for th in Cards.THEMES:
		var mine: Array = Cards.TAGS[th].filter(func(id: String) -> bool: return id in c)
		var head := UI.hbox(10)
		head.add_child(Icons.rect(th, _theme_color(th), 24))
		head.add_child(UI.label(_theme_name(th), 18, _theme_color(th), true, false))
		head.add_child(UI.label("%d / %d" % [mine.size(), Cards.TAGS[th].size()], 15, UI.SOFT, false, false))
		body.add_child(head)
		# album: minden kártya egy csempe; a megtaláltak színesek és újra elolvashatók, a többi még rejtély
		var ask := UI.label(" ", 16, UI.TEXT, false, false)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for id in Cards.TAGS[th]:
			var got: bool = id in c
			var tile := Button.new()
			tile.custom_minimum_size = Vector2(44, 44)
			tile.focus_mode = Control.FOCUS_NONE
			tile.disabled = not got
			var col := _theme_color(th)
			for st in ["normal", "hover", "pressed", "disabled"]:
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.05, 0.07, 0.12) if not got else (col.darkened(0.45) if st == "hover" else col.darkened(0.68))
				sb.border_color = col if got else UI.EDGE
				sb.set_border_width_all(3 if st == "hover" else 2)
				tile.add_theme_stylebox_override(st, sb)
			if got:
				var ic := Icons.rect(th, col, 26)
				ic.position = Vector2(9, 9)
				ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tile.add_child(ic)
				tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				tile.mouse_entered.connect(func() -> void: ask.text = Cards.text(id, "Kérdés", L.is_en()))
				tile.mouse_exited.connect(func() -> void: ask.text = " ")
				tile.pressed.connect(_open_card.bind(id, false))
			else:
				tile.text = "?"
				tile.add_theme_font_size_override("font_size", 18)
				tile.add_theme_color_override("font_disabled_color", UI.EDGE)
			flow.add_child(tile)
		body.add_child(flow)
		body.add_child(ask)
	var past: Variant = L.get_setting("foldek", [])
	if typeof(past) == TYPE_ARRAY and not past.is_empty():
		body.add_child(UI.label(L.t("Korábbi Földjeid"), 19, UI.GOLD, true, false))
		# két oszlop, az elsőben a legfrissebbek – így a jelvények is kiférnek alá
		var cols := UI.hbox(24)
		var half := ceili(past.size() / 2.0)
		var colv: Array = [UI.vbox(4), UI.vbox(4)]
		for cv in colv:
			(cv as Control).custom_minimum_size = Vector2(416, 0)
			cols.add_child(cv)
		body.add_child(cols)
		for i in past.size():
			var e: Dictionary = past[i]
			var date := ("%d-%02d-%02d" if L.is_en() else "%d. %02d. %02d.") % [int(e["ev"]), int(e["ho"]), int(e["nap"])]
			var level: String = L.t({3: "Nehéz", 4: "Közepes", 5: "Könnyű"}.get(int(e.get("lepes", 4)), "Közepes"))
			(colv[0 if i < half else 1] as Control).add_child(UI.label("%s  %s · +%s °C · %s · %s: %d" % [_stars(float(e["T"])), date, L.num(float(e["T"]), 2), level, L.t("Föld-kód"), int(e["mag"])], 15, UI.SOFT))


# --- zene játék közben ----------------------------------------------------------
var _music: AudioStreamPlayer

func _music_on() -> bool:
	return bool(L.get_setting("zene", true))


## Játék közben: a játékos saját zenéje (ha van), utána a két halk, kódból készült alapzene, és így tovább.
var _playlist: Array = []
var _track := 0

func _start_music() -> void:
	if _dry or not _music_on() or (_music != null and _music.playing):
		return
	if _music == null:
		for full in Intro.own_music_places():        # a játékos saját zenefájlja, ha van (nem része a játéknak)
			if FileAccess.file_exists(full):
				var own: AudioStream = AudioStreamWAV.load_from_file(full)
				if own != null:
					_playlist.append(own)
					break
		for name in ["alapzene", "alapzene2"]:      # a két kódból készült alapzene felváltva
			var amb: AudioStream = load("res://assets/hang/%s.wav" % name)
			if amb != null:
				_playlist.append(amb)
		if _playlist.is_empty():
			return
		_track = 1 if _playlist.size() > 2 else 0      # a nyitány után előbb az alapzene jön, a saját zene később tér vissza
		_music = AudioStreamPlayer.new()
		_music.finished.connect(func() -> void:
			if _music_on():
				_track = (_track + 1) % _playlist.size()
				_play_track(2.0))
		add_child(_music)
	_play_track(4.0)


## Egy szám lejátszása: lassan beúszik, és a vége előtt kiúszik, hogy a számok között ne legyen kattanás.
var _music_tw: Tween

func _play_track(fade_in: float) -> void:
	if _music_tw != null:
		_music_tw.kill()
	_music.stream = _playlist[_track]
	_music.volume_db = -40.0
	_music.play()
	var length: float = (_playlist[_track] as AudioStream).get_length()
	_music_tw = create_tween()
	_music_tw.tween_property(_music, "volume_db", -17.0, fade_in)
	if length > fade_in + 6.0:
		_music_tw.tween_interval(length - fade_in - 3.0)
		_music_tw.tween_property(_music, "volume_db", -50.0, 2.8)


func _toggle_music(btn: Button) -> void:
	L.set_setting("zene", not _music_on())
	btn.text = L.t("Zene: be") if _music_on() else L.t("Zene: ki")
	if _music_on():
		_start_music()
	elif _music != null:
		_music.stop()


# --- kutatás ------------------------------------------------------------------
func _open_research(theme: String = "") -> void:
	if world.steps <= 0 or world.over():
		return
	if theme != "":
		_research_theme(theme)
		return
	var body := _open(L.t("Miről kutatsz?"))
	_tutor_update("temak")
	body.add_child(UI.label(L.t("Válassz témakört. Három valódi kérdést kapsz, egyet kutathatsz ki: ebből lesz bizonyíték-kártyád."), 17, UI.SOFT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 9)
	body.add_child(grid)
	for th in Cards.THEMES:
		var n := Cards.open_in(th, world.max_era(), world.hand).size()
		if th in Cards.NO_TALK and world.max_era() < 4:
			n = 0                      # a kockázatos ötletek csak a játék második felében kerülnek elő
		var who: Array = []
		for g in world.groups:
			if th in g["felelmek"]:
				who.append(L.field(g, "nev"))
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 104)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = n == 0
		var col := _theme_color(th)
		b.add_theme_stylebox_override("normal", _flat(UI.CARD_BG, Color(col, 0.7)))
		b.add_theme_stylebox_override("hover", _flat(Color(0.12, 0.18, 0.3), col, 3))
		b.add_theme_stylebox_override("disabled", _flat(Color(0.06, 0.08, 0.13), Color(col, 0.2)))
		var v := UI.vbox(2)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_top = 10
		v.offset_right = -14
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_lbl(_theme_name(th), 20, col, true))
		if th in Cards.NO_TALK:
			v.add_child(_lbl(L.t("Tárgyalásra nem jó. Megtudod belőle, miért kockázatos mesterségesen hűteni a Földet."), 14, UI.SOFT))
		else:
			v.add_child(_lbl(L.t("Akit ez aggaszt: %s") % ", ".join(who) if not who.is_empty() else "", 14, UI.SOFT))
		var shaky_who: Array = []
		for g in world.groups:
			if g.get("inog", false) and th in g["felelmek"]:
				shaky_who.append(L.field(g, "nev"))
		if th == "ketseg" and not world.myth.is_empty() and not (str(world.myth["kartya"]) in world.hand):
			v.add_child(_lbl("⚠ " + L.t("Itt a terjedő tévhit cáfolata"), 13, UI.GOLD))
		elif not shaky_who.is_empty() and n > 0:
			v.add_child(_lbl("⚠ %s: %s" % [", ".join(shaky_who), L.t("Bizonytalan")], 13, UI.GOLD))
		elif not (th in Cards.NO_TALK):       # a kockázatos ötletek leírása három sor: oda már nem fér állapotsor
			v.add_child(_lbl(L.t("%d kérdés vár") % n if n > 0 else L.t("Itt most nincs új kérdés"), 13, UI.MUTE))
		b.add_child(v)
		v.offset_right = -150
		var art := ThemeArt.rect(th, 126)             # festett kép a témakörhöz
		art.position = Vector2(420 - 126 - 10, 10)
		art.modulate.a = 1.0 if n > 0 else 0.35
		b.add_child(art)
		var ic := Icons.rect(th, Color(col, 0.9 if n > 0 else 0.3), 24)
		ic.size = Vector2(24, 24)
		ic.position = Vector2(420 - 126 - 10, 74)
		b.add_child(ic)
		b.pressed.connect(_research_theme.bind(th))
		grid.add_child(b)


func _research_theme(th: String) -> void:
	if not _offers.has(th):
		_offers[th] = world.research_offers(th)
	var body := _open(_theme_name(th), _theme_color(th))
	_tutor_update("kerdesek")
	var offers: Array = _offers[th].filter(func(id: String) -> bool: return not (id in world.hand))
	if offers.is_empty():
		body.add_child(UI.label(L.t("Itt most nincs új kérdés"), 17, UI.SOFT))
	else:
		var head := UI.hbox(14)
		head.add_child(ThemeArt.rect(th, 168))
		var hl := UI.label(L.t("Melyik kérdést kutatod ki? Egy lépésbe kerül."), 17, UI.SOFT)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hl)
		body.add_child(head)
	for id in offers:
		var c := UI.card(_theme_color(th))
		if id == str(world.myth.get("kartya", "")):
			c.add_child(UI.label("⚠ " + L.t("Ez cáfolja a terjedő tévhitet."), 15, UI.GOLD, true))
		c.add_child(UI.label(Cards.text(id, "Kérdés", L.is_en()), 20, UI.TEXT, true))
		c.add_child(UI.label(Cards.text(id, "Röviden", L.is_en()), 16, UI.SOFT))
		c.add_child(_go(L.t("Ezt kutatom ki") + " →", _do_research.bind(id, th)))
		body.add_child(UI.card_root(c))
	body.add_child(_go("← " + L.t("Másik témakör"), _open_research.bind(""), false))


func _do_research(id: String, th: String) -> void:
	if world.research(id):
		_offers.erase(th)
		_collect(id)
		_refresh()
		_sound("kartya")
		_pop_next = true
		_open_card(id, true)


func _open_card(id: String, fresh: bool = false) -> void:
	var th := Cards.theme_of(id)
	var body := _open(L.t("Új bizonyíték-kártya") if fresh else L.t("Bizonyíték-kártya"), _theme_color(th) if th != "" else UI.GOLD)
	_tutor_update("kartya" if fresh else "")
	var en := L.is_en()
	if fresh and _new_rank != "":
		body.add_child(UI.label("★ " + L.t("Új rang: %s") % L.t(_new_rank), 20, UI.GOLD, true))
		_new_rank = ""
	var qrow := UI.hbox(16)
	if th != "":
		var qa := ThemeArt.rect(th, 210)
		qa.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		qrow.add_child(qa)
	var ql := UI.label(Cards.text(id, "Kérdés", en), 24, UI.TEXT, true)
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ql.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qrow.add_child(ql)
	body.add_child(qrow)
	var chips := UI.hbox(8)
	if th != "":
		chips.add_child(Icons.rect(th, _theme_color(th), 36))
		chips.add_child(_chip(_theme_name(th), _theme_color(th)))
	for g in world.groups:
		if th in g["felelmek"]:
			chips.add_child(_chip(L.field(g, "nev"), Color(str(g["szin"]))))
	body.add_child(chips)
	var kn := Cards.key_number(id)
	if not kn.is_empty():
		var kc := UI.card(UI.GOLD)
		kc.add_child(UI.label(str(kn["en"]) if en and str(kn.get("en", "")) != "" else str(kn["hu"]), 19, UI.GOLD, true))
		kc.add_child(UI.text_link(str(kn.get("forras_en", kn.get("forras", ""))) if en else str(kn.get("forras", "")), str(kn.get("link", "")), 14))
		body.add_child(UI.card_root(kc))
	for pair in [["Mire jó?", UI.GREEN], ["Mi a gond vele?", UI.EMBER], ["Mennyire bizonyított?", UI.CYAN]]:
		var txt := Cards.text(id, pair[0], en)
		if txt == "":
			continue
		body.add_child(UI.label(L.t("Miért jó?" if pair[0] == "Mire jó?" else pair[0]), 16, pair[1], true, false))   # a mező neve a témafájlban marad
		body.add_child(UI.label(txt, 17, UI.TEXT))
	body.add_child(UI.label(L.t("Források"), 16, UI.GOLD, true, false))
	for s in Cards.card(id).get("forrasok", []):
		body.add_child(UI.text_link(str(s["cim"]), str(s["link"]), 15))
	if World.CDR.has(id):
		body.add_child(UI.label(L.t("Ezzel a kártyával CO2-kivonást indíthatsz."), 16, UI.GREEN, true))
	_sticky(body, _go(L.t("Rendben"), _close))


func _open_hand() -> void:
	var body := _open(L.t("Kártyáim"))
	if world.hand.is_empty():
		body.add_child(UI.label(L.t("Még nincs kártyád. Kutass, hogy legyen mivel érvelned!"), 17, UI.SOFT))
	for th in Cards.THEMES:
		var mine: Array = world.hand.filter(func(id: String) -> bool: return Cards.theme_of(id) == th)
		if mine.is_empty():
			continue
		var th_row := UI.hbox(8)
		th_row.add_child(Icons.rect(th, _theme_color(th), 24))
		th_row.add_child(UI.label(_theme_name(th), 18, _theme_color(th), true, false))
		body.add_child(th_row)
		for id in mine:
			var b := UI.text_link(Cards.text(id, "Kérdés", L.is_en()), "", 17)
			for c in b.pressed.get_connections():
				b.pressed.disconnect(c["callable"])
			b.pressed.connect(_open_card.bind(id, false))
			var row := UI.hbox(8)
			row.add_child(b)
			for g in world.groups:      # kinek szólhat még ez a kártya (aki már hallotta, annak nem)
				if th in g["felelmek"] and not (id in g["hasznalt"]):
					var ch := _chip(L.field(g, "nev"), Color(str(g["szin"])))
					ch.add_theme_font_size_override("font_size", 12)
					ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					row.add_child(ch)
			body.add_child(row)


# --- tárgyalás ----------------------------------------------------------------
func _open_group(g: Dictionary) -> void:
	if g.is_empty() or _busy:
		return
	var col := Color(str(g["szin"]))
	var body := _open(L.field(g, "nev"), col)
	_tutor_update("csoport" if world.can_convince(g) else "")
	var top_row := UI.hbox(14)
	var big_land := Landscape.rect(str(g["id"]), 168, int(g["cel"]) > 0)
	big_land.texture = _land_tex(g)
	big_land.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(big_land)
	var top_l := UI.label(L.t("A világ CO2-kibocsátásának %s%%-a") % L.num_short(float(g["co2_resz"]) * 100.0, 0), 16, UI.SOFT)
	top_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(top_l)
	body.add_child(top_row)
	for f in g.get("tenyek", []):
		body.add_child(UI.text_link("%s (%s)" % [L.field(f, "szoveg"), L.field(f, "forras")], str(f.get("link", "")), 15))
	if int(g["cel"]) > 0:
		body.add_child(UI.label(L.rag(L.t("A játékban eddig: nulla kibocsátás %d-re.") % int(g["cel"])), 17, UI.GREEN, true))
	if world.over():
		return
	if world.steps <= 0:
		body.add_child(UI.label(L.t("Erre a körre elfogytak a lépéseid. Jöhet a következő öt év."), 17, UI.GOLD))
		return
	var targets := world.targets_for(g)
	var asks: Array = []
	var danger := _threat_on(g)
	if danger != "":
		var dr := UI.hbox(10)
		dr.add_child(Icons.rect(danger, UI.EMBER, 30))
		var dl := UI.label("%s. %s" % [L.t(THREAT[danger]), L.t("Készítsd fel őket a kör végéig, különben a mentés elvisz egy lépésedet.")], 17, UI.EMBER, true)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dr.add_child(dl)
		body.add_child(dr)
		asks.append({"fajta": "felkeszules", "kell": 1})
	if world.myth_on(g):
		var mc := UI.card(MYTH_COLOR)
		mc.add_child(UI.label("⚠ %s: %s" % [L.t("Tévhit terjed"), _myth_text()], 18, MYTH_COLOR, true))
		mc.add_child(UI.label(L.t("Amíg terjed, eggyel több kártya kell nekik, és a kör végén elbizonytalanodnak."), 15, UI.SOFT))
		var mid := str(world.myth["kartya"])
		if mid in world.hand:
			mc.add_child(_go("%s %s" % [L.t("Megcáfolom ezzel:"), Cards.text(mid, "Kérdés", L.is_en())], func() -> void:
				if world.refute(g):
					_refresh()
					_sound("egyezseg")
					_pop_next = true
					_refuted(g, mid)))
		else:
			var rl := UI.text_link(L.t("Kutasd ki a cáfolatát: %s") % _theme_name("ketseg") + " →", "", 16)
			for cn in rl.pressed.get_connections():
				rl.pressed.disconnect(cn["callable"])
			rl.pressed.connect(_open_research.bind("ketseg"))
			mc.add_child(rl)
		body.add_child(UI.card_root(mc))
	if g.get("makacs", false) and not targets.is_empty():
		body.add_child(UI.label(L.t("Makacs csoport: eggyel több kártya kell nekik."), 15, UI.GOLD))
	if g.get("inog", false):
		asks.append({"fajta": "megerosites", "kell": 1})
	for t in targets:
		asks.append({"fajta": "cel", "cel": t, "kell": world.cards_needed(g, t)})
	if int(g["metan"]) == 0 and _ramp(2):
		asks.append({"fajta": "metan", "kell": world.methane_needed(g)})
	if not g.get("felkeszult", false) and danger == "" and _ramp(2):
		asks.append({"fajta": "felkeszules", "kell": 1})
	if asks.is_empty():
		body.add_child(UI.label(L.t("Tőlük már nincs mit kérned."), 17, UI.SOFT))
		return
	var head_row := UI.hbox(16)
	var head_v := UI.vbox(4)
	head_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_v.size_flags_vertical = Control.SIZE_SHRINK_END
	head_v.add_child(UI.label(L.t("Mit kérsz tőlük?"), 19, UI.GOLD, true, false))
	head_v.add_child(UI.label(L.t("A szám azt mutatja, mennyivel lenne hűvösebb 2100-ban."), 14, UI.MUTE))
	head_row.add_child(head_v)
	var pc = PathChart.new()
	pc.set_paths(world.path(g), [])
	head_row.add_child(pc)
	body.add_child(head_row)
	var ask_row := HFlowContainer.new()
	ask_row.add_theme_constant_override("h_separation", 10)
	ask_row.add_theme_constant_override("v_separation", 10)
	body.add_child(ask_row)
	var area := UI.vbox(10)
	body.add_child(area)
	var bg := ButtonGroup.new()
	# a várható hűlés: két tizedes; ha így két cél egyformának látszana, három tizedes
	var cooling: Dictionary = {}
	var dec := 2
	var seen: Array = []
	for a in asks:
		if a["fajta"] in ["cel", "metan"]:
			var v := world.preview(g, int(a.get("cel", 0)), a["fajta"] == "metan")
			cooling[a] = v
			var short := "%.2f" % v
			if short in seen:
				dec = 3
			seen.append(short)
	for a in asks:
		var txt: String = (L.rag(L.t("Nulla kibocsátás %d-re") % int(a["cel"]))) if a["fajta"] == "cel" else (L.t("Metán: −30% tíz év alatt") if a["fajta"] == "metan" \
			else (L.t("Megerősítés") if a["fajta"] == "megerosites" else L.t("Felkészülés a bajra")))
		var b := UI.button("%s · %s" % [txt, L.t("%d kártya") % int(a["kell"])])
		if a["fajta"] in ["cel", "metan"]:
			var dts := ("%.3f" if dec == 3 else "%.2f") % float(cooling[a])
			b.text += " · %s °C" % (dts if L.is_en() else dts.replace(".", ",")).replace("-", "−")
		b.toggle_mode = true
		b.button_group = bg
		b.focus_mode = Control.FOCUS_NONE
		var sel := _flat(Color("#2b6b5e"), UI.CYAN, 2, 10)      # a kiválasztott kérés jól látszik
		sel.content_margin_left = 16
		sel.content_margin_right = 16
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("hover_pressed", sel)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				pc.set_paths(world.path(g), world.path(g, int(a["cel"])) if a["fajta"] == "cel" else [])
				_fill_ask(area, g, a))
		ask_row.add_child(b)
	(ask_row.get_child(0) as Button).button_pressed = true


func _fill_ask(area: VBoxContainer, g: Dictionary, ask: Dictionary) -> void:
	UI.clear(area)
	var need := int(ask["kell"])
	var picked: Array = []
	var status := UI.label("", 16, UI.SOFT, false, false)
	var ok := UI.button(L.t("Ezzel érvelek"), true)
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var update := func() -> void:
		status.text = L.t("Válassz %d kártyát (%d/%d)") % [need, picked.size(), need]
		ok.disabled = picked.size() != need
	var add_card := func(box: VBoxContainer, id: String) -> void:
		var cb := CheckBox.new()
		cb.text = Cards.text(id, "Kérdés", L.is_en())
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 17)
		cb.toggled.connect(func(on: bool) -> void:
			if on and picked.size() >= need:
				cb.set_pressed_no_signal(false)
				return
			if on:
				picked.append(id)
			else:
				picked.erase(id)
			update.call())
		box.add_child(cb)
	var top := UI.hbox(14)
	top.add_child(ok)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(status)
	# a gomb az ablak alján mindig látszik: a kártyák bejelölése után nem kell visszagörgetni
	if area.has_meta("alul") and is_instance_valid(area.get_meta("alul")):
		(area.get_meta("alul") as Node).free()
	area.set_meta("alul", top)
	_sticky(area.get_parent() as VBoxContainer, top)
	_fit.call_deferred()
	var any := false
	if ask["fajta"] == "felkeszules":
		var cp := UI.card(Color("#4aa0e0"))
		cp.add_child(UI.label(L.t("Segíts nekik felkészülni a hőségre, az áradásra és az aszályra! Aki felkészült, megbízik benned, és többé nem inog meg."), 16, UI.SOFT))
		for id in world.prepare_cards(g):
			add_card.call(cp, id)
			any = true
		if not any:
			cp.add_child(UI.label(L.t("Ehhez Tenger és part, Egészség vagy Élelem kártya kell."), 15, UI.MUTE))
		area.add_child(UI.card_root(cp))
	elif ask["fajta"] == "metan":
		var c := UI.card(UI.GREEN)
		c.add_child(UI.label(L.t("A metán rövid ideig marad a levegőben, de erősen melegít. Mutasd meg, hol lehet gyorsan csökkenteni!"), 16, UI.SOFT))
		if not bool(g.get("metan_valodi", true)):
			c.add_child(UI.text_link(L.t("A valóságban nem csatlakoztak a Globális Metánvállaláshoz, ezért nehezebb meggyőzni őket."), "https://www.globalmethanepledge.org/", 15))
		for id in world.methane_cards(g):
			add_card.call(c, id)
			any = true
		if not any:
			c.add_child(UI.label(L.t("Ehhez metánról szóló kártya kell (Olaj és gáz, Élelem, Áram)."), 15, UI.MUTE))
		area.add_child(UI.card_root(c))
	else:
		if ask["fajta"] == "megerosites":
			area.add_child(UI.label(L.t("Elbizonytalanodtak. Ha a kör végéig nem erősíted meg őket, meginognak, és későbbre tolják a céljukat."), 16, UI.GOLD))
		area.add_child(UI.label(L.t("Amitől tartanak:"), 17, UI.GOLD, true, false))
		var usable := world.usable(g)
		# előre az az aggodalom kerül, amelyikre van kártyád: a bejelölhető sor görgetés nélkül látszik
		var has_card := func(th: String) -> bool: return usable.any(func(id: String) -> bool: return Cards.theme_of(id) == th)
		var fears: Array = (g["felelmek"] as Array).filter(has_card) + (g["felelmek"] as Array).filter(func(th: String) -> bool: return not has_card.call(th))
		for th in fears:
			var c := UI.card(_theme_color(th))
			var wrow := UI.hbox(10)
			wrow.add_child(Icons.rect(th, _theme_color(th), 24))
			wrow.add_child(UI.label(("“%s”" if L.is_en() else "„%s”") % L.t(WORRY[th]), 17, UI.TEXT))
			c.add_child(wrow)
			var mine: Array = usable.filter(func(id: String) -> bool: return Cards.theme_of(id) == th)
			for id in mine:
				add_card.call(c, id)
				any = true
			if mine.is_empty():
				var row := UI.hbox(10)
				row.add_child(UI.label(L.t("Erre még nincs új kártyád."), 15, UI.MUTE, false, false))
				var rb := UI.text_link(L.t("Kutatás: %s") % _theme_name(th) + " →", "", 15)
				for cn in rb.pressed.get_connections():
					rb.pressed.disconnect(cn["callable"])
				rb.pressed.connect(_open_research.bind(th))
				row.add_child(rb)
				c.add_child(row)
			area.add_child(UI.card_root(c))
	update.call()
	ok.pressed.connect(func() -> void:
		var done := false
		var before := float(world.forecast()["kozep"][-1][1])
		if ask["fajta"] == "megerosites":
			ask["kartya"] = picked[0]
			done = world.reassure(g, picked[0])
		elif ask["fajta"] == "felkeszules":
			done = world.prepare(g, picked[0])
		elif ask["fajta"] == "metan":
			done = world.pledge_methane(g, picked)
		else:
			ask["tema"] = Cards.theme_of(picked[0]) if not picked.is_empty() else ""
			done = world.negotiate(g, int(ask["cel"]), picked)
		if done:
			_refresh()
			var game := world.game_id
			if not _test and ask["fajta"] in ["cel", "metan"]:
				await _persuade(g, picked)
			if world.game_id != game:       # a jelenet alatt új játék indult
				return
			_sound("egyezseg")
			_pop_next = true
			_agreed(g, ask, before))


func _refuted(g: Dictionary, card_id: String) -> void:
	_flash_ids = [g["id"]]
	var body := _open(L.t("Megcáfoltad!"), MYTH_COLOR)
	body.add_child(UI.label(_quote(L.t(MYTH.get(card_id, ""))), 20, UI.MUTE, true))
	var c := UI.card(UI.GREEN)
	c.add_child(UI.label(Cards.text(card_id, "Kérdés", L.is_en()), 19, UI.TEXT, true))
	c.add_child(UI.label(Cards.text(card_id, "Mennyire bizonyított?", L.is_en()), 17, UI.TEXT))
	body.add_child(UI.card_root(c))
	body.add_child(UI.label(L.t("%s most jobban bízik benned: eggyel kevesebb kártyával is meggyőzheted.") % L.field(g, "nev"), 17, UI.GREEN, true))
	_sticky(body, _go(L.t("Rendben"), _close))


## Rövid jelenet a megállapodás előtt: a bizonyítékaid egymás után érkeznek meg, és a csoport sávja megtelik.
func _persuade(g: Dictionary, picked: Array) -> void:
	_busy = true
	var col := Color(str(g["szin"]))
	var body := _open(L.field(g, "nev"), col)
	var pic := Landscape.rect(str(g["id"]), 252)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(pic)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(0, 18)
	bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, 0))
	bar.add_theme_stylebox_override("fill", _flat(col, Color.TRANSPARENT, 0, 0))
	body.add_child(bar)
	var n := maxi(picked.size(), 1)
	for i in picked.size():
		if not is_instance_valid(body) or not body.is_inside_tree():      # közben bezárták, vagy más ablak nyílt
			break
		var row := UI.label("✔  " + Cards.text(picked[i], "Kérdés", L.is_en()), 19, UI.TEXT, true)
		row.modulate.a = 0.0
		body.add_child(row)
		var tw := row.create_tween().set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, 0.2)
		tw.tween_property(bar, "value", float(i + 1) / float(n), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_sound("kartya")
		await get_tree().create_timer(0.55).timeout
		if _overlay == null:          # a játékos közben bezárta
			break
	if _overlay != null and is_instance_valid(body):
		await get_tree().create_timer(0.25).timeout
	_busy = false


func _agreed(g: Dictionary, ask: Dictionary, before: float = -1.0) -> void:
	_flash_ids = [g["id"]]
	if ask["fajta"] == "megerosites":
		var b2 := _open(L.field(g, "nev"), UI.GREEN)
		b2.add_child(UI.label(L.t("%s megingott, de kitartott.") % L.field(g, "nev"), 22, UI.GREEN, true))
		b2.add_child(UI.label(L.t("A bizonyítékod miatt kitartottak: %s") % Cards.text(ask["kartya"], "Kérdés", L.is_en()), 17, UI.SOFT))
		b2.add_child(_go(L.t("Rendben"), _close))
		return
	var body := _open(L.t("Megállapodtatok!"), UI.GREEN)
	if not _test:
		var burst := Burst.new()
		burst.colors = [Color(str(g["szin"])), UI.GOLD, UI.GREEN, UI.CYAN]
		burst.position = Vector2(800, 120)
		burst.z_index = 12
		add_child(burst)
	if ask["fajta"] == "felkeszules":
		body.add_child(UI.label(L.t("%s felkészült a bajra. Megbízik benned, és többé nem inog meg.") % L.field(g, "nev"), 22, UI.TEXT, true))
		_sticky(body, _go(L.t("Rendben"), _close))
		return
	var txt: String = (L.rag(L.t("%s vállalta: nulla kibocsátás %d-re.") % [L.field(g, "nev"), int(ask["cel"])])) if ask["fajta"] == "cel" \
		else (L.t("%s vállalta: 30%%-kal kevesebb metán tíz év alatt.") % L.field(g, "nev"))
	if ask["fajta"] == "cel":       # a tájban megjelennek a szélkerekek és a napelemek
		var pic := Landscape.rect(str(g["id"]), 252, true)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		body.add_child(pic)
	body.add_child(UI.label(txt, 22, UI.TEXT, true))
	if REPLY.has(str(ask.get("tema", ""))):
		body.add_child(UI.label(_quote(L.t(REPLY[ask["tema"]])), 18, Color(str(g["szin"])).lightened(0.25)))
	var fc := world.forecast()
	var after := float(fc["kozep"][-1][1])
	if before > 0.0:
		var fmt := L.t("Várható melegedés 2100-ban: +%s → +%s °C")
		var cl := UI.label(fmt % [L.num(before, 2), L.num(after, 2)], 22, UI.GREEN, true)
		body.add_child(cl)
		if not _test:             # a szám a szemed előtt pereg le az új értékre
			cl.text = fmt % [L.num(before, 2), L.num(before, 2)]
			var tw := cl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.35)
			tw.tween_method(func(x: float) -> void: cl.text = fmt % [L.num(before, 2), L.num(x, 2)], before, after, 1.1)
	if world.streak_bonus:
		body.add_child(UI.label("★ " + L.t("Lendület! Két megállapodás egy körben: +1 lépés."), 19, UI.GOLD, true))
		_bonus_float = true
	elif world.streak % 2 == 1 and world.steps > 0:
		body.add_child(UI.label(L.t("Még egy megállapodás ebben a körben, és kapsz egy lépést."), 16, UI.GOLD))
	body.add_child(UI.label(L.t("2100-ban: +%s és +%s °C között") % [L.num(minf(float(fc["also"][-1][1]), float(fc["felso"][-1][1])), 1), L.num(maxf(float(fc["also"][-1][1]), float(fc["felso"][-1][1])), 1)], 17, UI.SOFT))
	body.add_child(UI.label(L.t("A hőmérsékleti sáv azért ilyen széles, mert nem tudjuk pontosan, mennyire érzékeny a Föld."), 15, UI.MUTE))
	_sticky(body, _go(L.t("Rendben"), _close))


# --- CO2-kivonás --------------------------------------------------------------
func _open_cdr() -> void:
	var body := _open(L.t("CO2-kivonás"), UI.GREEN)
	body.add_child(UI.label(L.t("Ha megvan a hozzá tartozó kártya, elindíthatod. Húsz év alatt fut fel, és óvatosan, a fenntartható sáv aljával számolunk."), 17, UI.SOFT))
	for id in World.CDR:
		var c := UI.card(UI.GREEN)
		var rng: Array = World.CDR[id]
		c.add_child(UI.label(L.t(CDR_NAME[id]), 19, UI.TEXT, true))
		c.add_child(UI.label(L.t("Évi %s–%s milliárd tonna CO2 (Fuss és mtsai 2018)") % [L.num_short(rng[0], 1), L.num_short(rng[1], 1)], 15, UI.SOFT))
		var running: bool = world.cdr.any(func(x: Dictionary) -> bool: return x["id"] == id)
		if running:
			c.add_child(UI.label(L.t("Már fut."), 15, UI.GREEN, true))
		elif id in world.hand and world.steps > 0 and not world.over():
			c.add_child(_go(L.t("Elindítom") + " →", func() -> void:
				if world.start_cdr(id):
					_refresh()
					_open_cdr()))
		elif id in world.hand:
			c.add_child(UI.label(L.t("Erre a körre elfogytak a lépéseid. Jöhet a következő öt év."), 15, UI.GOLD))
		else:
			var th := Cards.theme_of(id)
			var need := L.t("Előbb kutasd ki: %s") % Cards.text(id, "Kérdés", L.is_en())
			if world.steps > 0 and not world.over() and id in Cards.open_in(th, world.max_era(), world.hand):
				# egy kattintás a kérdéshez: a témakör három kérdése közé ez biztosan bekerül
				var rb := UI.text_link(need + " →", "", 15)
				for cn in rb.pressed.get_connections():
					rb.pressed.disconnect(cn["callable"])
				rb.pressed.connect(func() -> void:
					var offers: Array = _offers[th] if _offers.has(th) else world.research_offers(th)
					if not (id in offers):
						if offers.size() >= 3:
							offers.pop_back()
						offers.push_front(id)
					_offers[th] = offers
					_research_theme(th))
				c.add_child(rb)
			else:
				c.add_child(UI.label(need, 15, UI.MUTE))
		body.add_child(UI.card_root(c))


# --- telik az idő -------------------------------------------------------------
## Nagy, áttetsző évszám a Föld fölött, amíg az évek peregnek.
func _year_label() -> Label:
	var big := UI.label("", 132, Color(1, 1, 1, 0.36), true, false)
	big.add_theme_font_override("font", UI.font_pixel)
	big.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.5))
	big.add_theme_constant_override("outline_size", 12)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.position = Vector2(500, 350)
	big.size = Vector2(600, 150)
	big.pivot_offset = Vector2(300, 75)
	add_child(big)
	return big


## A gomb első megnyomása nem lép tovább, ha még van lépésed: előbb szól, és csak a második kattintás vált kört
## (véletlen kattintás ne vigyen el egy egész kört). Az óra és a szóköz ezt nem használja.
var _adv_ask := 0

func _advance_click() -> void:
	if _busy or _overlay != null:
		return
	var now := Time.get_ticks_msec()
	if not _test and not world.over() and not world.summit_due and world.dilemma.is_empty() and world.steps > 0 and now > _adv_ask:
		_adv_ask = now + 4000
		var btn: Button = _btns["ido"]
		btn.text = L.t("Még %d lépésed van") % world.steps + "  ▶"
		btn.add_theme_color_override("font_color", UI.GOLD)
		btn.add_theme_color_override("font_hover_color", UI.GOLD)
		create_tween().tween_callback(func() -> void:
			if Time.get_ticks_msec() >= _adv_ask - 60:
				_adv_reset()).set_delay(4.0)
		return
	_adv_reset()
	_advance()


func _adv_reset() -> void:
	_adv_ask = 0
	var btn: Button = _btns["ido"]
	btn.remove_theme_color_override("font_color")
	btn.remove_theme_color_override("font_hover_color")
	btn.text = L.t("Végeredmény") if world.over() else L.t("Következő 5 év") + "  ▶"


func _advance() -> void:
	if _busy or _overlay != null:
		return
	if world.over():
		_open_end()
		return
	if world.summit_due:          # előbb a klímacsúcsról kell dönteni
		_open_summit()
		return
	if not world.dilemma.is_empty():     # függőben lévő döntés
		_open_dilemma()
		return
	_busy = true
	var t0 := float(world.st["T"])
	var y0 := world.year()
	var n0 := world.history.size()
	var heat0: float = globe.heat
	if _tutor_on():              # az első kör végén a vezetés véget ér
		if not _dry:
			L.set_setting("tanulo_kesz", true)
	world.advance()
	_offers = {}
	_clock = 0.0
	_plan_moments()
	var fc := world.forecast()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(globe, "spin", globe.spin + 1.0, 0.2 if _test else 2.6)
	# évről évre: az évszám, a hőmérséklet, a görbe és a Föld színe együtt lép
	var big := _year_label()
	var game := world.game_id        # ha közben új játék indul (menü), ez a körváltás csendben abbamarad
	for i in range(n0, world.history.size()):
		if world.game_id != game or i >= world.history.size():
			break
		var row: Array = world.history[i]
		big.text = str(int(row[0]))
		big.scale = Vector2(1.12, 1.12)
		big.create_tween().tween_property(big, "scale", Vector2.ONE, 0.3)
		(_stats["ev"] as Label).text = str(int(row[0]))
		(_stats["meleg"] as Label).text = "+%s °C" % L.num(float(row[1]), 2)
		_curve.set_data(world.history.slice(0, i + 1), world.base_history.slice(0, i + 1), fc)
		globe.heat = lerpf(heat0, clampf((float(world.st["T"]) - M.T_START) / 2.0, 0.0, 1.5), float(i - n0 + 1) / float(World.ROUND_YEARS))
		await get_tree().create_timer(0.03 if _test else 0.5).timeout
	if tw.is_running():
		await tw.finished
	var fade := big.create_tween()
	fade.tween_property(big, "modulate:a", 0.0, 0.4)
	fade.tween_callback(big.queue_free)
	if world.game_id != game:
		_busy = false
		_refresh()
		return
	# a baj lecsap: a Föld odafordul, és a jel felnagyítva lobog
	for n in world.news:
		if n["fajta"] == "katasztrofa" and not _test:
			var dg := world.group(n["csoport"])
			globe.look_at_event({"lat": dg["lat"], "lon": dg["lon"]})
			globe.storms = [{"lat": dg["lat"], "lon": dg["lon"], "kind": n["mi"], "strong": true}]
			_sound("katasztrofa")
			await get_tree().create_timer(0.7).timeout
			globe.flash(float(dg["lat"]), float(dg["lon"]), UI.EMBER)
			await get_tree().create_timer(1.3).timeout
			if world.game_id != game:
				break
	_busy = false
	_bar_hold = true
	_refresh()
	_bar_hold = false
	if world.game_id != game:
		return
	var kinds: Array = world.news.map(func(n: Dictionary) -> String: return str(n["fajta"]))
	_sound("zaro" if world.over() else ("billenes" if "billenes" in kinds else ("katasztrofa" if "katasztrofa" in kinds else ("veszely" if not world.threat.is_empty() else ("megingas" if ("visszalepett" in kinds or "inog" in kinds) else ("jo_hir" if ("nulla" in kinds or "vilag_nulla" in kinds) else "korvaltas"))))))
	_open_news(y0, t0)


func _open_news(y0: int, t0: float) -> void:
	var body := _open("%d–%d" % [y0, y0 + World.ROUND_YEARS - 1])
	var quiet := true
	var t1 := float(world.st["T"])
	body.add_child(UI.label(L.t("A Föld melegedése: +%s → +%s °C") % [L.num(t0, 2), L.num(t1, 2)], 22, UI.EMBER if t1 > t0 + 0.005 else UI.GREEN, true))
	var lost := false
	var bands: Array = []          # új veszélysáv: a küszöb rejtve van, de a sávja ismert
	for tp in world.tips:
		if int(tp["ev"]) == 0 and float(tp["also"]) > t0 and float(tp["also"]) <= t1:
			bands.append(L.field(tp, "nev"))
	if not bands.is_empty():
		var cw := UI.card(UI.GOLD)
		cw.add_child(UI.label("⚠ " + L.t("Veszélysávba értünk: %s") % ", ".join(bands), 18, UI.GOLD, true))
		cw.add_child(UI.label(L.t("A küszöb rejtve van: senki sem tudja, pontosan mikor lépjük át."), 16, UI.SOFT))
		body.add_child(UI.card_root(cw))
		quiet = false
	for n in world.news:
		match str(n["fajta"]):
			"billenes":
				var tp: Dictionary = world.tips.filter(func(x: Dictionary) -> bool: return x["id"] == n["id"])[0]
				var c := UI.card(UI.EMBER)
				c.add_child(UI.label(L.t("Átlépte a küszöbértéket: %s (%d)") % [L.field(tp, "nev"), int(n["ev"])], 19, UI.EMBER, true))
				c.add_child(UI.label(L.t("Ha a melegedés tartósan e fölött marad, a változás lassan, de megállíthatatlanul végbemegy. A küszöböt a tudomány csak sávként ismeri (%s és %s °C között); a játék ebből sorsolt egyet.") % [L.num(float(tp["also"]), 1), L.num(float(tp["felso"]), 1)], 16, UI.TEXT))
				body.add_child(UI.card_root(c))
			"visszalepett":
				var c2 := UI.card(UI.GOLD)
				c2.add_child(UI.label(L.rag(L.t("%s megingott: a célját %d-re tolta.") % [L.field(world.group(n["csoport"]), "nev"), int(n["cel"])]), 18, UI.GOLD, true))
				c2.add_child(UI.label(L.t("Nem erősítetted meg őket időben."), 16, UI.SOFT))
				body.add_child(UI.card_root(c2))
			"nulla":
				var c6 := UI.card(UI.GREEN)
				c6.add_child(UI.label("★ " + L.t("%s elérte a nulla kibocsátást (%d).") % [L.field(world.group(n["csoport"]), "nev"), int(n["ev"])], 18, UI.GREEN, true))
				body.add_child(UI.card_root(c6))
			"vilag_nulla":
				var c7 := UI.card(UI.GREEN)
				c7.add_child(UI.label("★ " + L.t("A világ már több CO2-t von ki, mint amennyit kibocsát (%d).") % int(n["ev"]), 18, UI.GREEN, true))
				body.add_child(UI.card_root(c7))
			"inog":
				var c5 := UI.card(UI.GOLD)
				c5.add_child(UI.label("⚠ " + L.t("%s elbizonytalanodott.") % L.field(world.group(n["csoport"]), "nev"), 18, UI.GOLD, true))
				c5.add_child(UI.label(L.t("Erősítsd meg őket egy hozzájuk illő kártyával, különben öt év múlva meginognak!"), 16, UI.SOFT))
				body.add_child(UI.card_root(c5))
			"kitartott":
				var c3 := UI.card(UI.GREEN)
				c3.add_child(UI.label(L.t("%s megingott, de kitartott.") % L.field(world.group(n["csoport"]), "nev"), 18, UI.GREEN, true))
				c3.add_child(UI.label(L.t("A bizonyítékod miatt kitartottak: %s") % Cards.text(n["kartya"], "Kérdés", L.is_en()), 16, UI.SOFT))
				body.add_child(UI.card_root(c3))
			"katasztrofa":
				var c4o := UI.card(UI.EMBER)
				var row4 := UI.hbox(14)
				c4o.add_child(row4)
				var pic4 := Landscape.disaster_rect(str(n["csoport"]), str(n["mi"]), 147)
				pic4.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row4.add_child(pic4)
				var c4 := UI.vbox(6)
				c4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row4.add_child(c4)
				var dh := UI.hbox(10)
				dh.add_child(Icons.rect(str(n["mi"]), UI.EMBER, 36))
				dh.add_child(UI.label("%s: %s" % [L.t(DISASTER[n["mi"]]), L.field(world.group(n["csoport"]), "nev")], 18, UI.EMBER, true))
				c4.add_child(dh)
				if world.group(n["csoport"]).get("felkeszult", false):
					c4.add_child(UI.label(L.t("Felkészültek rá, ezért kisebb volt a baj."), 16, UI.GREEN))
				elif n.get("lepes", false):
					c4.add_child(UI.label(L.t("Nem voltak felkészülve. A mentés miatt most eggyel kevesebb lépésed van."), 16, UI.EMBER, true))
					lost = true
				c4.add_child(UI.label(L.t("A baj után jobban figyelnek rád: most eggyel kevesebb kártyával is meggyőzheted őket."), 16, UI.SOFT))
				body.add_child(UI.card_root(c4o))
			"tevhit":
				var cm := UI.card(MYTH_COLOR)
				cm.add_child(UI.label("⚠ %s: %s" % [L.t("Tévhit terjed"), L.field(world.group(n["csoport"]), "nev")], 18, MYTH_COLOR, true))
				cm.add_child(UI.label(_quote(L.t(MYTH.get(str(n["kartya"]), ""))), 18, UI.TEXT, true))
				cm.add_child(UI.label(L.t("Kutasd ki az igazságot a „Honnan tudjuk?” témakörben, és cáfold meg! Amíg terjed, eggyel több kártya kell nekik."), 16, UI.SOFT))
				body.add_child(UI.card_root(cm))
			"segit":
				var c8 := UI.card(UI.GREEN)
				c8.add_child(UI.label(L.t("%s tiszta technikát ad át. %s most könnyebben meggyőzhető.") % [L.field(world.group(n["csoport"]), "nev"), L.field(world.group(n["kinek"]), "nev")], 18, UI.GREEN, true))
				body.add_child(UI.card_root(c8))
				_flash_ids = [n["csoport"], n["kinek"]]
	if not world.threat.is_empty() and not world.over():      # a következő baj már látszik: van idő felkészülni
		var tg := world.group(str(world.threat["csoport"]))
		var c9 := UI.card(UI.EMBER)
		var r9 := UI.hbox(10)
		r9.add_child(Icons.rect(str(world.threat["mi"]), UI.EMBER, 36))
		r9.add_child(UI.label("⚠ %s: %s" % [L.t(THREAT[world.threat["mi"]]), L.field(tg, "nev")], 18, UI.EMBER, true))
		c9.add_child(r9)
		c9.add_child(UI.label(L.t("Készítsd fel őket a kör végéig, különben a mentés elvisz egy lépésedet."), 16, UI.SOFT))
		body.add_child(UI.card_root(c9))
	if lost and not _test:        # megrázkódik az ablak, ha a baj felkészületlenül ért
		var ov := _overlay
		var x0 := ov.position.x
		var sh := ov.create_tween()
		for dx in [14.0, -12.0, 9.0, -6.0, 3.0, 0.0]:
			sh.tween_property(ov, "position:x", x0 + dx, 0.06)
	if world.news.is_empty() and world.threat.is_empty() and quiet:
		body.add_child(UI.label(L.t("Csendes öt év volt."), 17, UI.SOFT))
		var known: Array = world.hand.filter(func(id: String) -> bool: return not Cards.key_number(id).is_empty())
		if not known.is_empty():
			var kid: String = known[(world.round_i * 7 + world.seed_v) % known.size()]
			var k := Cards.key_number(kid)
			var kc := UI.card(_theme_color(Cards.theme_of(kid)))
			kc.add_child(UI.label(L.t("A kártyáidból tudod:"), 14, UI.SOFT))
			kc.add_child(UI.label(str(k["en"] if L.is_en() and str(k.get("en", "")) != "" else k["hu"]), 17, UI.GOLD, true))
			kc.add_child(UI.label(str(k["forras_en"] if L.is_en() and str(k.get("forras_en", "")) != "" else k["forras"]), 13, UI.CYAN))
			body.add_child(UI.card_root(kc))
	if world.over():
		body.add_child(_go(L.t("Lássuk, mi lett a Földdel") + " →", _open_end))
	elif world.summit_due:
		body.add_child(_go(L.t("Tovább") + " →", _open_summit))
	else:
		body.add_child(_go(L.t("Tovább") + (" →" if not world.dilemma.is_empty() else ""), _open_dilemma if not world.dilemma.is_empty() else _close))


# --- klímacsúcs ---------------------------------------------------------------
## Döntési helyzet a kör elején (játékszabály): két lehetőség, mindkettőnél látszik, mit ad.
func _open_dilemma() -> void:
	var d := world.dilemma
	if d.is_empty():
		_close()
		return
	var body := _open(L.t("Tudáspróba") if d["fajta"] == "kviz" else L.t("Döntés"), UI.GOLD)
	var opts: Array = []
	if d["fajta"] == "kviz":
		var k := Cards.key_number(str(d["id"]))
		body.add_child(UI.label(L.t("Melyik kártyádon áll ez? Ha eltalálod, ebben a körben eggyel több lépésed van."), 17, UI.SOFT))
		var kc := UI.card(UI.GOLD)
		kc.add_child(UI.label(str(k.get("en", "") if L.is_en() and str(k.get("en", "")) != "" else k.get("hu", "")), 19, UI.GOLD, true))
		body.add_child(UI.card_root(kc))
		for id in d["valasz"]:
			opts.append(Cards.text(str(id), "Kérdés", L.is_en()))
	elif d["fajta"] == "tamogatas":
		body.add_child(UI.label(L.t("Egy alapítvány támogatja a munkádat. Mire kéred?"), 18, UI.TEXT))
		opts = [L.t("Több kutató: ebben a körben eggyel több lépésed van."),
			L.t("Felkészítő program: %s azonnal felkészül a bajra.") % L.field(world.group(str(d["a"])), "nev")]
	else:
		body.add_child(UI.label(L.t("Két meghívást kaptál, de csak egy útra van időd. Akit meglátogatsz, azt most eggyel kevesebb kártyával is meggyőzheted."), 18, UI.TEXT))
		opts = [L.field(world.group(str(d["a"])), "nev"), L.field(world.group(str(d["b"])), "nev")]
	for i in opts.size():
		body.add_child(_go(str(opts[i]) + " →", _do_dilemma.bind(i), false))


func _do_dilemma(choice: int) -> void:
	var quiz: bool = world.dilemma.get("fajta", "") == "kviz"
	var right := str(world.dilemma.get("id", ""))
	var ok := world.resolve_dilemma(choice)
	_save()
	_refresh()
	if not quiz:
		_sound("kartya")
		_close()
		return
	_sound("jo_hir" if ok else "megingas")
	var body := _open(L.t("Tudáspróba"), UI.GREEN if ok else UI.EMBER)
	if ok:
		body.add_child(UI.label(L.t("Eltaláltad! Ebben a körben eggyel több lépésed van."), 20, UI.GREEN, true))
	else:
		body.add_child(UI.label(L.t("Nem ez volt. A helyes válasz:"), 18, UI.TEXT))
		body.add_child(UI.label(Cards.text(right, "Kérdés", L.is_en()), 20, UI.GOLD, true))
	_sticky(body, _go(L.t("Rendben"), _close))


func _open_summit() -> void:
	var body := _open("%s %d" % [L.t("Klímacsúcs"), world.year()], UI.GOLD)
	body.add_child(UI.label(L.t("Mutass meg egy kártyát az egész világnak! Aki már vállalt célt, és a kártya az ő aggodalmára felel, öt évvel előbbre hozza a vállalását. Nem kerül semmibe."), 17, UI.SOFT))
	var rows: Array = []
	for id in world.hand:
		var ls := world.summit_listeners(id)
		if not ls.is_empty():
			rows.append([id, ls])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1].size() > b[1].size())
	for r in rows.slice(0, 8):
		var id: String = r[0]
		var c := UI.card(_theme_color(Cards.theme_of(id)))
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		for g in r[1]:
			chips.add_child(_chip(L.field(g, "nev"), Color(str(g["szin"]))))
		c.add_child(chips)
		c.add_child(_go(Cards.text(id, "Kérdés", L.is_en()) + " →", _do_summit.bind(id), false))
		body.add_child(UI.card_root(c))
	if rows.is_empty():
		body.add_child(UI.label(L.t("Most nincs olyan kártyád, amire figyelnének."), 17, UI.GOLD))
	body.add_child(_go(L.t("Most nem mutatok semmit"), func() -> void:
		world.skip_summit()
		_save()
		_close(), rows.is_empty()))


func _do_summit(id: String) -> void:
	var before := float(world.forecast()["kozep"][-1][1])
	var who := world.summit(id)
	_flash_ids = who.duplicate()
	_refresh()
	_save()
	_sound("egyezseg")
	var body := _open(L.t("Klímacsúcs"), UI.GREEN)
	for gid in who:
		var g := world.group(gid)
		body.add_child(UI.label(L.rag(L.t("%s előbbre hozta a célját: nulla kibocsátás %d-re.") % [L.field(g, "nev"), int(g["cel"])]), 20, UI.TEXT, true))
	body.add_child(UI.label(L.t("Várható melegedés 2100-ban: +%s → +%s °C") % [L.num(before, 2), L.num(float(world.forecast()["kozep"][-1][1]), 2)], 20, UI.GREEN, true))
	_sticky(body, _go(L.t("Rendben"), _close))


var _cheer_force := false        # az élő próba így a szikraesőt is lefuttatja
var _end_opened := 0            # hányszor nyílt meg a záróképernyő (a véletlen próba képet ment róla)


func _open_end() -> void:
	_end_opened += 1
	var r := world.result()
	var body := _open(L.t("2100: a te Földed"), UI.CYAN)
	var row := UI.hbox(24)
	body.add_child(row)
	for side in [[L.t("A te Földed"), r["T"], r["tenger"], UI.GREEN, 1.0], [L.t("Ha semmi sem változik"), r["alap"], r["tenger_alap"], UI.EMBER, 0.0]]:
		var v := UI.vbox(4)
		v.custom_minimum_size = Vector2(410, 0)
		var gl = Globe.new()
		gl.custom_minimum_size = Vector2(264, 264)
		gl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		gl.heat = clampf((float(side[1]) - M.T_START) / 2.0, 0.0, 1.5)
		var ratio := world.net_ratio(2100) if side[4] > 0.5 else 1.0
		gl.set_plan_look({"smog": clampf(ratio, 0.0, 1.0), "clean": clampf(1.0 - ratio, 0.0, 1.0), "regrow": clampf(-ratio / 0.25, 0.0, 1.0)})
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gl.fixed_sun = true
		gl.pixels = 280.0
		gl.sea_rise = clampf((float(side[1]) - M.T_START) / 2.0, 0.0, 1.0)
		gl.spin = 0.05
		v.add_child(gl)
		var a := UI.label(str(side[0]) + ("   " + _stars(float(side[1])) if side[4] > 0.5 else ""), 20, side[3], true, false)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		var b := UI.label("+%s °C" % L.num(float(side[1]), 2), 34, side[3], true, false)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(b)
		if not _test:             # a két szám együtt indul a mai melegedésről; a „ha semmi sem változik” tovább kúszik
			var end_t := float(side[1])
			var dur := 0.9 * maxf(end_t - M.T_START, 0.2) / 0.5
			var cnt := b.create_tween()
			cnt.tween_method(func(x: float) -> void: b.text = "+%s °C" % L.num(x, 2), M.T_START, end_t, dur)
			# a két Föld a mai állapotból indul, és a számmal együtt változik 2100-ig; közben lassan forog
			var look := {"heat": gl.heat, "sea_rise": gl.sea_rise, "smog": gl.smog, "clean": gl.clean, "regrow": gl.regrow}
			gl.heat = 0.0
			gl.sea_rise = 0.0
			gl.set_plan_look({"smog": 1.0, "clean": 0.0, "regrow": 0.0})
			gl.spin_speed = 0.006
			var lapse := gl.create_tween().set_parallel(true)
			for key in look:
				lapse.tween_property(gl, key, float(look[key]), dur)
		var c := UI.label(L.t("A tenger kb. %s cm-rel magasabb") % L.num_short(float(side[2]) * 100.0, 0), 15, UI.SOFT, false, false)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(c)
		row.add_child(v)
	var tt := float(r["T"])
	if (tt < 2.0 or _cheer_force) and not _test:           # +2 °C alatt: három szikraeső a te Földed fölött
		var game := world.game_id
		for i in 3:
			create_tween().tween_callback(func() -> void:
				if _overlay == null or world.game_id != game or not world.over():
					return
				var burst := Burst.new()
				burst.colors = [UI.GREEN, UI.GOLD, UI.CYAN, Color.WHITE]
				burst.position = Vector2(560 + 60 * i, 250 - 30 * (i % 2))
				burst.z_index = 12
				add_child(burst)
				if i == 0:
					_sound("lendulet")).set_delay(1.0 + 0.5 * i)
	var verdict := "A Földed +1,7 °C alatt maradt. 2026-ból indulva ennél sokkal jobbat már alig lehet elérni." if tt < 1.7 \
		else ("A Földed +2 °C alatt maradt. A Párizsi Megállapodás ennél többet kér: jóval +2 °C alatt megállni, lehetőleg +1,5 °C-nál." if tt < 2.0 \
		else "A Földed +2 °C fölé melegedett. A következő játékban lépj hamarabb!")
	body.add_child(UI.label(L.t(verdict), 19, UI.GREEN if tt < 2.0 else UI.EMBER, true))
	var fin := _finish_game(r)
	if fin["rekord"]:
		body.add_child(UI.label(L.t("Új rekord! Ez az eddigi legjobb Földed."), 19, UI.GOLD, true))
	if int(fin.get("lepcso", 0)) > 0:
		body.add_child(UI.label("★ " + L.t("Új kihívás nyílt meg: %d. szint") % int(fin["lepcso"]), 19, UI.GOLD, true))
		body.add_child(UI.label(L.t(LEVELS[int(fin["lepcso"])]), 16, UI.SOFT))
	for bd in BADGES:
		if bd[0] in fin["uj"]:
			body.add_child(UI.label("★ " + L.t("Új jelvény: %s") % L.t(bd[1]), 17, UI.GOLD, true))
	if not world.naplo.is_empty():       # a játék története egy képen, rögtön az eredmény alatt
		_add_story(body)
	body.add_child(UI.label(L.t("A legmelegebb év: +%s °C. Küszöbét átlépő rendszer: %d a %d-ből.") % [L.num(float(r["csucs"]), 2), int(r["billenes"]), world.tips.size()], 17, UI.TEXT))
	var late := world.what_if(5)
	if late > tt + 0.005:
		body.add_child(UI.label(L.t("Ha minden öt évvel később történik, a Földed +%s °C-ra melegszik. Minden év számít!") % L.num(late, 2), 17, UI.GOLD))
	var s := float(r["sens"])
	var kind := L.t("átlagos") if absf(s) < 0.25 else (L.t("az átlagnál érzékenyebb") if s > 0 else L.t("az átlagnál kevésbé érzékeny"))
	body.add_child(UI.label(L.t("Ez a Föld %s volt. Ezt előre senki sem tudhatta, ahogy a valódi Földnél sem tudjuk pontosan.") % kind, 16, UI.SOFT))
	body.add_child(UI.label(L.t("A hőmérsékletet egyszerű klímamodell számolta. Irányt és nagyságrendet mutat, nem előrejelzés."), 14, UI.MUTE))
	body.add_child(UI.label(L.t("Föld-kód: %d. Ha egy barátod ezt írja be a menüben, ugyanezt a Földet kapja.") % world.seed_v, 14, UI.SOFT))
	var end_row := UI.hbox(12)
	end_row.add_child(_go(L.t("Új játék, új Föld") + " →", func() -> void: _pick_game()))
	var saved_lbl := UI.label("", 14, UI.SOFT)
	saved_lbl.custom_minimum_size = Vector2(430, 0)
	end_row.add_child(_go(L.t("Kép mentése"), func() -> void:
		var msg: String = await _save_picture()
		if is_instance_valid(saved_lbl):       # mentés közben bezárhatták az ablakot
			saved_lbl.text = msg, false))
	end_row.add_child(saved_lbl)
	_sticky(body, end_row)
	if world.hajto.size() >= M.END_YEAR - M.START_YEAR:
		var wp = PathChart.new()
		wp.custom_minimum_size = Vector2(560, 96)
		wp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		wp.legend_now = "A világ CO2-kibocsátása"
		var rows: Array = [[2026, 1.0]]
		for i in world.hajto.size():
			var hr: Array = world.hajto[i]
			rows.append([M.START_YEAR + 1 + i, (float(hr[0]) - float(hr[1])) / M.E_CO2_NOW])
		wp.set_paths(rows, [])
		body.add_child(wp)
	# ki mennyi CO2-t nem bocsátott ki (a modell szerint, a „ha semmi sem változik” úthoz képest)
	var saved: Array = world.groups.filter(func(g: Dictionary) -> bool: return float(g.get("megsporolt", 0.0)) >= 0.5)
	saved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["megsporolt"]) > float(b["megsporolt"]))
	if not saved.is_empty():
		body.add_child(UI.label(L.t("Ennyi CO2-t nem bocsátottak ki 2100-ig"), 19, UI.GOLD, true, false))
		var top_v := float(saved[0]["megsporolt"])
		for g in saved:
			var hb := UI.hbox(10)
			var gp := Landscape.rect(str(g["id"]), 63, int(g.get("nulla", 0)) > 0)
			gp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(gp)
			var nm := UI.label(L.field(g, "nev"), 15, Color(str(g["szin"])), true, false)
			nm.custom_minimum_size = Vector2(170, 0)
			hb.add_child(nm)
			var barc := ColorRect.new()
			barc.color = Color(str(g["szin"]))
			barc.custom_minimum_size = Vector2(maxf(4.0, 380.0 * float(g["megsporolt"]) / top_v), 12)
			barc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(barc)
			hb.add_child(UI.label(L.t("%s milliárd tonna") % L.num_short(float(g["megsporolt"]), 0), 15, UI.SOFT, false, false))
			body.add_child(hb)
		if world.cdr_total >= 0.5:
			body.add_child(UI.label("%s: %s" % [L.t("CO2-kivonás"), L.t("%s milliárd tonna") % L.num_short(world.cdr_total, 0)], 15, UI.GREEN, true))
	if not world.missions.is_empty():
		body.add_child(UI.label("%s: %d/%d" % [L.t("Küldetések"), world.missions_done(), world.missions.size()], 19, UI.GOLD, true, false))
		_add_missions(body)


const MISSION_TEXT := {
	"korai": "Győzd meg ezt a csoportot 2040 végéig: %s",
	"metan3": "2050 végéig legalább három csoport vállaljon metáncsökkentést.",
	"kivonas2": "Indíts el két CO2-kivonást.",
	"tema": "Kutass ki öt kártyát ebből a témakörből: %s",
	"felkeszul3": "Segíts három csoportnak felkészülni a bajra.",
	"nulla2065": "Legalább egy csoport érje el a nulla kibocsátást 2065-ig.",
	"csucs3": "Egy klímacsúcson legalább három csoport hozza előbbre a célját.",
	"kartya20": "Gyűjts húsz kártyát ebben a játékban.",
	"lendulet2": "Szerezz kétszer lendületet: két megállapodás egy körben.",
}


func _mission_text(m: Dictionary) -> String:
	var t: String = L.t(MISSION_TEXT.get(str(m["id"]), ""))
	if "%s" in t:
		var arg := str(m.get("arg", ""))
		t = t % (_theme_name(arg) if m["id"] == "tema" else L.field(world.group(arg), "nev"))
	return t


## A három küldetés sora pipával; a záró képernyőn és a Küldetések ablakban is ez látszik.
func _add_missions(body: VBoxContainer) -> void:
	for m in world.missions:
		var done := world.mission_done(m)
		body.add_child(UI.label(("✔ " if done else "○ ") + _mission_text(m), 17, UI.GREEN if done else UI.TEXT))


func _open_missions() -> void:
	var body := _open(L.t("Küldetések"), UI.GOLD)
	body.add_child(UI.label(L.t("Három cél erre a játékra. Nem kötelezőek, de jelvény jár értük."), 16, UI.SOFT))
	_add_missions(body)


## A képernyő képe a Képek mappába (ha nincs ilyen, a játék saját mappájába). Vissza: a kiírandó mondat.
func _save_picture() -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "" or not DirAccess.dir_exists_absolute(dir) or _dry:
		dir = OS.get_user_data_dir()
	var path := dir.path_join("AETHER_2100_%d.png" % world.seed_v)
	if _dry:
		return L.t("Elmentve: %s") % path
	return L.t("Elmentve: %s") % path if img.save_png(path) == OK else L.t("Nem sikerült elmenteni a képet.")


## A játék fontos pillanatai egy képen: megnyitáskor újrajátssza az éveket, utána az egér alatti jel szövege látszik.
func _add_story(body: VBoxContainer) -> void:
	var lines: Array = []
	for e in world.naplo:
		var line := ""
		var lc := UI.SOFT
		var lane := 0
		var mark := UI.CYAN
		if e.has("csoport"):
			mark = Color(str(world.group(e["csoport"])["szin"]))
		match str(e["fajta"]):
			"cel":
				line = L.rag(L.t("%s vállalta: nulla kibocsátás %d-re.") % [L.field(world.group(e["csoport"]), "nev"), int(e["cel"])])
			"metan":
				line = L.t("%s vállalta: 30%%-kal kevesebb metán tíz év alatt.") % L.field(world.group(e["csoport"]), "nev")
			"felkeszules":
				line = L.t("%s felkészült a bajra.") % L.field(world.group(e["csoport"]), "nev")
			"kivonas":
				line = "%s: %s" % [L.t("CO2-kivonás"), L.t(CDR_NAME[e["id"]])]
				mark = UI.GREEN
			"nulla":
				line = (L.t("%s elérte a nulla kibocsátást (%d).") % [L.field(world.group(e["csoport"]), "nev"), int(e["ev"])]).replace(" (%d)" % int(e["ev"]), "")
				lc = UI.GREEN
				lane = 1
			"vilag_nulla":
				line = (L.t("A világ már több CO2-t von ki, mint amennyit kibocsát (%d).") % int(e["ev"])).replace(" (%d)" % int(e["ev"]), "")
				lc = UI.GREEN
				lane = 1
				mark = UI.GOLD
			"csucs":
				line = L.t("Klímacsúcs: %d csoport hozta előbbre a célját.") % int(e.get("db", 0))
				mark = UI.GOLD
			"visszalepett":
				line = L.rag(L.t("%s megingott: a célját %d-re tolta.") % [L.field(world.group(e["csoport"]), "nev"), int(e["cel"])])
				lc = UI.GOLD
				lane = 2
				mark = UI.GOLD
			"cafolat":
				line = "%s %s" % [L.t("Megcáfoltad:"), _quote(L.t(MYTH.get(str(e.get("kartya", "")), "")))]
				lc = MYTH_COLOR
				mark = MYTH_COLOR
			"baj":
				line = "%s: %s" % [L.t(DISASTER[e["mi"]]), L.field(world.group(e["csoport"]), "nev")] + (" · " + L.t("Felkészült") if e.get("vedve", false) else "")
				lc = UI.GREEN if e.get("vedve", false) else UI.EMBER
				lane = 2
				mark = lc
			"billenes":
				var tp2: Array = world.tips.filter(func(x: Dictionary) -> bool: return x["id"] == e["id"])
				if not tp2.is_empty():
					line = L.t("küszöb átlépve:") + " " + L.field(tp2[0], "nev")
					lc = UI.EMBER
					lane = 2
					mark = Color("#ff6a4a")
		if line != "":
			lines.append({"ev": int(e["ev"]), "szoveg": line, "szin": lc, "jel": mark, "sav": lane})
	var sl := StoryLine.new()
	sl.hint = L.t("Vidd az egeret egy jel fölé.")
	sl.setup(lines, world.history, world.base_history, _test and not _story_live)
	body.add_child(sl)


var _story_live := false


func _open_story() -> void:
	var body := _open(L.t("A te történeted"), UI.GOLD)
	if world.naplo.is_empty():
		body.add_child(UI.label(L.t("Még nem vállalt semmit"), 17, UI.SOFT))
	else:
		_add_story(body)


func _open_help() -> void:
	var body := _open(L.t("Hogyan játssz?"), UI.CYAN)
	for row in [
			["1.", "Te vagy a világ klímatudósa. 2026-ból indulsz; egy kör öt év, így 2100-ig tizenöt köröd van."],
			["2.", L.t("Körönként %s lépésed van. Kutass: minden kutatás egy bizonyíték-kártyát ad valódi tudományos forrásokkal.") % L.t(str({2: "két", 3: "három", 4: "négy", 5: "öt"}.get(world.max_steps, str(world.max_steps))))],
			["3.", "Kattints egy országcsoportra, és győzd meg a kártyáiddal. Minden csoport mástól tart, ezért más kártyára van szüksége."],
			["4.", "Lépj korán: minden év késés számít. Akit egyszer meggyőztél, attól később merészebb célt is kérhetsz."],
			["5.", "A cél: 2100-ban jóval +2 °C alatt maradni, minél közelebb a +1,5 °C-hoz. Ez a Párizsi Megállapodás célja is."],
			["6.", "A Föld érzékenységét senki sem ismeri pontosan, és vannak rejtett billenőpontok. Ne várj sokáig!"],
			["7.", "Az évek maguktól telnek. Amíg olvasol, az idő áll. Ha a Földön felvillan valami, kattints rá gyorsan!"]]:
		var h := UI.hbox(12)
		h.add_child(UI.label(row[0], 22, UI.GOLD, true, false))
		h.add_child(UI.label(L.t(row[1]), 18, UI.TEXT))
		body.add_child(h)
	body.add_child(UI.label(L.t("Valódi: a klímamodell számai, a csoportok kibocsátása, a kártyák forrásai. Játékszabály: a tárgyalás, az aggodalmak mondatai, a jövő hírei."), 15, UI.MUTE))
	var hb := UI.hbox(12)
	hb.add_child(_go(L.t("Kezdjük!"), _close))
	hb.add_child(_go(L.t("Új játék vezetéssel"), func() -> void:       # az első kör lépésről lépésre, újra
		if not _dry:
			L.set_setting("tanulo_kesz", false)
		_pick_game(), false))
	body.add_child(hb)


# --- önteszt: végigjátszik pár kört, és minden ablakról képet ment --------------
func _shot(name: String) -> void:
	var dir := OS.get_user_data_dir().path_join("aether_onteszt")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name))


## Élő próbajáték (godot -- --elojatek): valós időben, a valódi gombokon át játssza le az első két kört új játékosként,
## hogy az animációk, az óra és az első kör vezetése is próbára kerüljön. Beállítást és mentést nem ír.
func _find_button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).text.begins_with(text) and not (c as Button).disabled:
			return c
		var r := _find_button(c, text)
		if r != null:
			return r
	return null


func _find_check(n: Node) -> CheckBox:
	for c in n.get_children():
		if c is CheckBox:
			return c
		var r := _find_check(c)
		if r != null:
			return r
	return null


## Véletlen próba (godot -- --majom --mag=3 --mp=150): valós időben, találomra nyomkodja azokat a gombokat,
## amelyeket a játékos is elérne (nyitott ablaknál csak az ablak gombjait), néha szóközt és Esc-et is üt.
## Rejtett hibák kiszűrésére: a futás végén a naplóban nem lehet SCRIPT ERROR.
func _monkey_buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		if c is BaseButton and not (c as BaseButton).disabled and (c as Control).is_visible_in_tree():
			var txt := str(c.get("text")) if c is Button else ""
			if txt != L.t("Kilépés a játékból") and not (c as Control).tooltip_text.begins_with("http") and not (_monkey_calm and txt in [L.t("Menü"), "English", "Magyar"]):
				out.append(c)
		_monkey_buttons(c, out)


var _monkey_calm := false       # páros magnál a próba nem nyúl a menühöz: így végig is ér egy játékon


func _monkey(seed_n: int, seconds: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	_monkey_calm = seed_n % 2 == 0
	world.new_game(2026 + seed_n, 3 + (seed_n / 12) % 3, (seed_n / 2) % 6)      # a mag a fokozatot és a kihívást is váltogatja
	if seed_n % 5 == 0:            # minden ötödik mag: első játék vezetéssel, szelíd kezdéssel
		world.gentle = true
		_tutor_force = true
		_ramp_game = world.game_id
	_refresh()
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var clicks := 0
	var games := 0
	var top_round := 0
	var was_over := false
	while Time.get_ticks_msec() < t_end:
		if not is_inside_tree():       # nyelvváltáskor a jelenet újratölt: ott új próba indul
			return
		await get_tree().create_timer(rng.randf_range(0.05, 0.3)).timeout
		if not is_inside_tree():
			return
		top_round = maxi(top_round, world.round_i)
		if _end_opened == 1:
			_end_opened = 2
			await get_tree().create_timer(0.6).timeout
			await _shot("m_vege_%d.png" % seed_n)
		if world.over() and not was_over:
			games += 1
		was_over = world.over()
		var r := rng.randf()
		if r < 0.06:
			for pressed in [true, false]:
				var ev := InputEventKey.new()
				ev.keycode = KEY_SPACE if r < 0.04 else KEY_ESCAPE
				ev.physical_keycode = ev.keycode
				ev.pressed = pressed
				Input.parse_input_event(ev)
			continue
		var pool: Array = []
		if _overlay != null and is_instance_valid(_overlay):
			_monkey_buttons(_overlay, pool)
			if _close_x != null and is_instance_valid(_close_x) and _close_x.visible:
				pool.append(_close_x)
		else:
			_monkey_buttons(self, pool)
			if r > 0.8 and not (_btns["ido"] as Button).disabled and (_btns["ido"] as Button).is_visible_in_tree():
				pool = [_btns["ido"]]
		if pool.is_empty():
			continue
		var b: BaseButton = pool[rng.randi() % pool.size()]
		if b.toggle_mode:
			b.button_pressed = not b.button_pressed
		else:
			b.pressed.emit()
		clicks += 1
	print("MAJOM kész mag=%d kattintás=%d legtovább=%d. kör befejezett=%d lépés=%d kihívás=%d" % [seed_n, clicks, top_round, games, world.max_steps, world.challenge])
	get_tree().quit()


func _live_play() -> void:
	_tutor_force = true
	world.new_game(2026)
	world.gentle = true
	_refresh()
	var wait := func(t: float) -> void: await get_tree().create_timer(t).timeout
	await wait.call(1.0)
	await _shot("e1_kezdes.png")
	print("ELO 1 vezetes=", _tutor.text, " ora=%.1f" % _clock)
	(_btns["kutatas"] as Button).pressed.emit()
	await wait.call(0.5)
	_research_theme("aram")
	await wait.call(0.4)
	(_find_button(_overlay, L.t("Ezt kutatom ki")) as Button).pressed.emit()
	await wait.call(0.6)
	await _shot("e2_kartya.png")
	print("ELO 2 vezetes=", _tutor.text, " kez=", world.hand.size())
	_close_x.pressed.emit()
	await wait.call(0.6)
	await _shot("e3_vilagit.png")
	print("ELO 3 vezetes=", _tutor.text)
	var hot: Dictionary = {}
	for g in world.groups:
		if world.can_convince(g):
			hot = g
			break
	(_group_cards[hot["id"]]["gomb"] as Button).pressed.emit()
	await wait.call(0.6)
	print("ELO 4 vezetes=", _tutor.text)
	_find_check(_overlay).button_pressed = true
	await wait.call(0.3)
	await _shot("e4_targyalas.png")
	(_find_button(_overlay, L.t("Ezzel érvelek")) as Button).pressed.emit()
	await wait.call(0.5)
	await _shot("e5_meggyozes.png")
	await wait.call(1.6)
	await _shot("e6_megallapodas.png")
	print("ELO 5 cel=", int(hot["cel"]), " lepes=", world.steps, " sorozat=", world.streak)
	(_find_button(_overlay, L.t("Rendben")) as Button).pressed.emit()
	await wait.call(0.8)
	await _shot("e7_utana.png")
	while world.steps > 0:
		(_btns["kutatas"] as Button).pressed.emit()
		await wait.call(0.3)
		_research_theme("munka")
		await wait.call(0.3)
		var rb := _find_button(_overlay, L.t("Ezt kutatom ki"))
		if rb == null:
			break
		rb.pressed.emit()
		await wait.call(0.4)
		_close()
		await wait.call(0.3)
	print("ELO 6 vezetes=", _tutor.text, " ora=%.1f (az első körben állnia kell)" % _clock)
	await _shot("e8_elfogyott.png")
	var sp := InputEventKey.new()
	sp.keycode = KEY_SPACE
	sp.pressed = true
	Input.parse_input_event(sp)
	await wait.call(1.2)
	await _shot("e9_evek.png")
	await wait.call(4.5)
	await _shot("e10_hirek.png")
	print("ELO 7 kor=", world.round_i, " ablak=", _overlay != null)
	var nb := _find_button(_overlay, L.t("Tovább"))
	if nb != null:
		nb.pressed.emit()
	await wait.call(0.5)
	_close()
	await wait.call(0.5)                # a kibocsátás-sávok most csökkennek: a kép a mozgás közepén készül
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir().path_join("aether_onteszt/e10b_savok.png"))
	print("ELO 7b sav_varakozik=", _bar_pending)
	await wait.call(2.4)
	await _shot("e11_masodik_kor.png")
	print("ELO 8 vezetes=", _tutor.text, " ora=%.1f (most járnia kell)" % _clock)
	_clock = _round_s() - 5.0
	await wait.call(3.0)
	await _shot("e12_ketyeg.png")
	await wait.call(9.0)
	print("ELO 9 kor=", world.round_i, " (az óra magától lépett: 2 kell legyen)")
	await _shot("e13_magatol.png")
	_close()
	while not world.over():            # a végére ugrik: a záróképernyő élő (nem gyorsított) változata is lefut
		world.advance()
	_busy = false
	_refresh()
	_cheer_force = true
	(_btns["ido"] as Button).pressed.emit()
	await wait.call(2.4)
	await _shot("e14_vege.png")
	print("ELO 10 vege ablak=", _overlay != null, " T=%.2f" % float(world.st["T"]))
	await wait.call(3.0)
	print("ELOJATEK kész")
	get_tree().quit()


func _selftest() -> void:
	_tutor_force = true
	_refresh()
	await _shot("1_fooldal.png")
	if "--idoproba" in OS.get_cmdline_user_args():      # az óra a kör végén magától lép tovább?
		_clock_live = true
		_clock = _round_s() - 3.0
		await get_tree().create_timer(6.0).timeout
		print("IDOPROBA kor=%d ablak=%s ora=%.1f" % [world.round_i, str(_overlay != null), _clock])
		await _shot("0_idoproba.png")
		get_tree().quit()
		return
	# élő idő: felvillanó pillanat a Földön, majd a rákattintás
	_clock_force = true
	_clock = 30.0
	_spawn_moment("felfedezes")
	await get_tree().create_timer(1.2).timeout
	await _shot("1b_pillanat.png")
	_pick_moment()
	await get_tree().create_timer(0.4).timeout
	await _shot("1c_pillanat_utan.png")
	world.steps -= 1
	_spawn_moment("figyelem")
	await get_tree().create_timer(1.2).timeout
	await _shot("1d_figyelnek.png")
	_clear_moment()
	_clock_force = false
	_clock = 0.0
	# előre látható baj: a kártyán, a Földön és a csoport ablakában
	world.threat = {"csoport": "europa", "mi": "arviz"}
	_refresh()
	await get_tree().create_timer(0.5).timeout
	await _shot("1e_veszely.png")
	_open_group(world.group("europa"))
	await _shot("1f_veszely_ablak.png")
	_close()
	var yl := _year_label()
	yl.text = "2031"
	var eu := world.group("europa")
	globe.storms = [{"lat": eu["lat"], "lon": eu["lon"], "kind": "arviz", "strong": true}, {"lat": 28.0, "lon": 15.0, "kind": "hoseg", "strong": true},
		{"lat": 5.0, "lon": 20.0, "kind": "tuz", "strong": true}, {"lat": 25.0, "lon": 45.0, "kind": "aszaly", "strong": true},
		{"lat": 50.0, "lon": 40.0, "kind": "tuz"}, {"lat": -15.0, "lon": 25.0, "kind": "aszaly"}, {"lat": 10.0, "lon": 0.0, "kind": "hoseg"}]
	await get_tree().create_timer(0.4).timeout
	await _shot("1h_baj_lecsap.png")
	yl.queue_free()
	world.threat = {}
	world.myth = {"csoport": "kina", "kartya": "felhok"}
	_refresh()
	_open_group(world.group("kina"))
	await _shot("1i_tevhit.png")
	world.hand.append("felhok")
	_open_group(world.group("kina"))
	await _shot("1j_tevhit_kartyaval.png")
	world.refute(world.group("kina"))
	_refuted(world.group("kina"), "felhok")
	await _shot("1k_megcafolva.png")
	_close()
	world.hand.erase("felhok")
	world.group("kina")["konnyebb"] = false
	world.steps = world.max_steps
	world.naplo.clear()
	_level_force = 3
	_pick_game(-1, 2)
	await _shot("1g_kihivas.png")
	_close()
	_level_force = -1
	_refresh()
	await get_tree().create_timer(1.6).timeout
	_open_help()
	await _shot("2_sugo.png")
	_open_research()
	await _shot("3_temakorok.png")
	_research_theme("aram")
	await _shot("4_kerdesek.png")
	_do_research(_offers["aram"][0], "aram")
	await _shot("5_kartya.png")
	for th in ["munka", "egeszseg"]:
		_research_theme(th)
		_do_research(_offers[th][0], th)
	_close()
	await _shot("6_lepesek_elfogytak.png")
	await _advance()
	await _shot("7_hirek.png")
	var real_news: Array = world.news          # a négy hír-képjel képe (a világ állapotát nem változtatja meg)
	world.news = []
	for i in 4:
		world.news.append({"fajta": "katasztrofa", "csoport": world.groups[i]["id"], "mi": ["hoseg", "aszaly", "arviz", "tuz"][i], "lepes": i == 0})
	world.news.append({"fajta": "segit", "csoport": world.groups[4]["id"], "kinek": world.groups[5]["id"]})
	world.news.append({"fajta": "tevhit", "csoport": world.groups[1]["id"], "kartya": "napaktivitas"})
	var real_threat: Dictionary = world.threat
	world.threat = {"csoport": world.groups[2]["id"], "mi": "tuz"}
	_open_news(2026, 1.41)
	await _shot("7b_hir_kepjelek.png")
	world.news = real_news
	world.threat = real_threat
	_close()
	_refresh()
	_ghost_show("kina")                 # a görbe előnézete, amikor az egér a kártya fölött van
	await _shot("7c_elonezet.png")
	_curve.set_ghost([])
	_open_group(world.group("kina"))
	await _shot("8_targyalas.png")
	var kina := world.group("kina")
	var kt: int = world.targets_for(kina)[0]
	world.negotiate(kina, kt, world.usable(kina).slice(0, 1))
	_refresh()
	_test = false
	_agreed(kina, {"fajta": "cel", "cel": kt, "tema": "aram"}, 2.8)
	await get_tree().create_timer(0.7).timeout
	_test = true
	await _shot("9_megegyezes.png")
	_close()
	await get_tree().create_timer(0.6).timeout
	await _shot("9b_felvillanas.png")
	# a valós idejű jelenetek próbája (ezek ellenőrző futásban különben kimaradnak): meggyőzés, lecsapó baj, ketyegő óra
	_test = false
	var eu2 := world.group("europa")
	await _persuade(eu2, world.hand.slice(0, 2))
	await _shot("9c_meggyozes.png")
	_close()
	_busy = false
	world.threat = {"csoport": "europa", "mi": "tuz"}
	world.summit_due = false
	world.dilemma = {}
	_advance()
	await get_tree().create_timer(5.2).timeout
	_test = true
	await _shot("9d_baj_lecsap.png")
	_test = false
	await get_tree().create_timer(2.6).timeout
	await _shot("9e_baj_hirek.png")
	_close()
	_clock_force = true
	_clock = _round_s() - 4.0
	await get_tree().create_timer(2.2).timeout
	_clock_force = false
	_clock = 0.0
	_test = true
	print("JELENETEK kör=%d lépés=%d/%d" % [world.round_i, world.steps, world.max_steps])
	_open_hand()
	await _shot("10_kartyaim.png")
	_open_cdr()
	await _shot("11_kivonas.png")
	var cdr_link := _find_button(_overlay, L.t("Előbb kutasd ki: %s").split("%")[0])      # a hiányzó kártya egy kattintással kikutatható
	if cdr_link != null:
		var rng_state: int = world.rng.state
		var offers_before := _offers.duplicate(true)
		cdr_link.pressed.emit()
		await _shot("11_kivonas_kerdes.png")
		print("KIVONAS kerdes=", _find_button(_overlay, L.t("Ezt kutatom ki")) != null, " felkinalva=", _offers.values().any(func(o: Array) -> bool: return o.any(func(id: String) -> bool: return World.CDR.has(id))))
		_offers = offers_before
		world.rng.state = rng_state
	_open_collection()
	await _shot("11b_gyujtemeny.png")
	_pick_game()
	await _shot("11c_uj_jatek.png")
	_open_missions()
	await _shot("11g_kuldetesek.png")
	_open_story()
	await _shot("11e_tortenet.png")
	_story_live = true                 # a visszajátszás közben is készül kép
	_open_story()
	await get_tree().create_timer(2.2).timeout
	await _shot("11e2_tortenet_lejatszas.png")
	_story_live = false
	_close()
	_show_menu(true)
	await _shot("11f_menu.png")
	_show_menu(false)
	Cards.show_unproofed = true
	_open_card("napelem")
	await _shot("11d_kulcsszam.png")
	Cards.show_unproofed = false
	_close()
	if world.hand.size() >= 2:        # a tudáspróba képe (a világ állapotát nem változtatja meg)
		world.dilemma = {"fajta": "kviz", "id": "napelem", "valasz": [world.hand[0], "napelem", world.hand[1]]}
		_open_dilemma()
		await _shot("11h_tudasproba.png")
		world.dilemma = {}
		_close()
	# a többi kör gyorsan: minden körben kutatás és ahol lehet, megegyezés
	var shaky_shot := false
	while not world.over():
		while world.steps > 0:
			var acted := false
			for g in world.groups:
				var ts := world.targets_for(g)
				if not ts.is_empty() and world.usable(g).size() >= world.cards_needed(g, ts[0]):
					acted = world.negotiate(g, ts[0], world.usable(g).slice(0, world.cards_needed(g, ts[0])))
					if acted:
						break
			if not acted:
				for id in world.cdr_available():
					acted = world.start_cdr(id)
					break
			if not acted:
				var ths: Array = Cards.talk_themes()
				var of := world.research_offers(ths[world.rng.randi_range(0, ths.size() - 1)])
				if of.is_empty():
					break
				world.research(of[0])
		if world.round_i == 7:
			_refresh()
			await _shot("12_felido.png")
		await _advance()
		if world.round_i == 8 or world.over():
			await _shot("13_hirek_%d.png" % world.round_i)
		_close()
		if not world.dilemma.is_empty():
			_open_dilemma()
			await _shot("13d_dontes_%s.png" % str(world.dilemma["fajta"]))
			_do_dilemma(world.round_i % 2)
			await _shot("13e_dontes_utan.png")
			_close()
		if world.summit_due:
			_open_summit()
			await _shot("13b_csucs_%d.png" % world.round_i)
			var best := ""
			for id in world.hand:
				if best == "" or world.summit_listeners(id).size() > world.summit_listeners(best).size():
					best = id
			if best != "" and not world.summit_listeners(best).is_empty():
				_do_summit(best)
				await _shot("13c_csucs_utan_%d.png" % world.round_i)
			else:
				world.skip_summit()
			_close()
		var sh: Array = world.groups.filter(func(x: Dictionary) -> bool: return x.get("inog", false))
		if not sh.is_empty() and not shaky_shot and not world.over():
			shaky_shot = true
			_refresh()
			await _shot("12b_bizonytalan.png")
			_open_group(sh[0])
			await _shot("12c_megerosites.png")
			if not world.usable(sh[0]).is_empty() and world.steps <= 0:
				world.steps = 1
			if not world.usable(sh[0]).is_empty():
				var cid: String = world.usable(sh[0])[0]
				if world.reassure(sh[0], cid):
					_refresh()
					_agreed(sh[0], {"fajta": "megerosites", "kartya": cid})
					await _shot("12d_kitartott.png")
			_close()
			for g2 in world.groups:
				if not g2.get("felkeszult", false) and not world.prepare_cards(g2).is_empty():
					world.steps = maxi(world.steps, 1)
					if world.prepare(g2, world.prepare_cards(g2)[0]):
						_refresh()
						_agreed(g2, {"fajta": "felkeszules"})
						await _shot("12e_felkeszult.png")
						_close()
					break
			_open_collection()
			_close()
	_test = false
	_open_end()
	await get_tree().create_timer(0.8).timeout
	await _shot("14a_vege_szamlal.png")
	await get_tree().create_timer(3.0).timeout
	_test = true
	_open_end()
	await _shot("14_vege.png")
	print("KEP ", await _save_picture())
	var nd: Node = _body
	while nd != null and not (nd is ScrollContainer):
		nd = nd.get_parent()
	if nd != null:
		(nd as ScrollContainer).scroll_vertical = 100000
		await _shot("14b_tortenet.png")
	print("ONTESZT kész: T2100=%.2f alap=%.2f" % [world.result()["T"], world.result()["alap"]])
	get_tree().quit()


## Bejárás (hibakereső futás, kép nélkül): több Földön, mindhárom fokozaton végigjátssza a játékot a felület
## saját függvényein át, minden körben megnyitva minden ablakot és minden kérést.   godot -- --bejaras
func _press_toggles(n: Node) -> void:
	for c in n.get_children():
		if c is Button and (c as Button).toggle_mode and not (c is CheckBox):
			(c as Button).button_pressed = true
		_press_toggles(c)


func _walkthrough() -> void:
	var games := 0
	for seed_v in [11, 222, 3333, 44444, 5, 60606]:
		_new_game(seed_v, 3 + games % 3, games % 6)
		while not world.over():
			if not world.dilemma.is_empty():
				_open_dilemma()
				await get_tree().process_frame
				_do_dilemma(world.round_i % 2)
				_close()
			if world.summit_due:
				_open_summit()
				var best := ""
				for id in world.hand:
					if best == "" or world.summit_listeners(id).size() > world.summit_listeners(best).size():
						best = id
				if best != "" and not world.summit_listeners(best).is_empty() and world.round_i % 2 == 1:
					_do_summit(best)
				else:
					world.skip_summit()
				_close()
			var guard := 0
			while world.steps > 0 and guard < 12:
				guard += 1
				var acted := false
				for g in world.groups:
					_open_group(g)
					if _body != null:
						_press_toggles(_body)
					_close()
					var u := world.usable(g)
					if world.myth_on(g):            # tévhit: a cáfolat kikutatása, majd a cáfolat
						var mid := str(world.myth["kartya"])
						if mid in world.hand:
							acted = world.refute(g)
							if acted:
								_refuted(g, mid)
						else:
							_research_theme("ketseg")
							_do_research(mid, "ketseg")
							acted = mid in world.hand
						_close()
						if acted:
							break
					if g.get("inog", false) and not u.is_empty():
						acted = world.reassure(g, u[0])
						if acted:
							_agreed(g, {"fajta": "megerosites", "kartya": u[0]})
					var ts := world.targets_for(g)
					if not acted and not ts.is_empty():
						var t: int = ts[world.rng.randi_range(0, ts.size() - 1)]
						if u.size() >= world.cards_needed(g, t):
							var before := float(world.forecast()["kozep"][-1][1])
							acted = world.negotiate(g, t, u.slice(0, world.cards_needed(g, t)))
							if acted:
								_agreed(g, {"fajta": "cel", "cel": t}, before)
					if not acted and int(g["metan"]) == 0 and world.methane_cards(g).size() >= world.methane_needed(g):
						acted = world.pledge_methane(g, world.methane_cards(g).slice(0, world.methane_needed(g)))
						if acted:
							_agreed(g, {"fajta": "metan"}, 2.0)
					if not acted and not g.get("felkeszult", false) and not world.prepare_cards(g).is_empty() and world.rng.randf() < 0.3:
						acted = world.prepare(g, world.prepare_cards(g)[0])
						if acted:
							_agreed(g, {"fajta": "felkeszules"})
					_close()
					if acted:
						break
				if not acted:
					_open_cdr()
					for id in world.cdr_available():
						acted = world.start_cdr(id)
						break
					_close()
				if not acted:
					_open_research()
					var ths: Array = Cards.talk_themes()
					var th: String = ths[world.rng.randi_range(0, ths.size() - 1)]
					_research_theme(th)
					if _offers.has(th) and not _offers[th].is_empty():
						_do_research(_offers[th][0], th)
					else:
						world.steps -= 1
					_close()
				_refresh()
			if not _dry:      # éles bejárás: mentés és visszatöltés minden körben, hangok, zene
				_save()
				var rt: Variant = World.read_json(SAVE)
				if typeof(rt) != TYPE_DICTIONARY or not world.from_dict(rt):
					print("BEJARAS HIBA: a mentés nem tölthető vissza (kör %d)" % world.round_i)
				_refresh()
				_start_music()
				(_btns["kartyak"] as Button).pressed.emit()
				_close()
			_open_story()
			_open_hand()
			for id in world.hand.slice(0, 3):
				_open_card(id)
			_open_collection()
			_open_help()
			_close()
			await _advance()
			_close()
		_open_end()
		print("KEP ", await _save_picture())
		_open_missions()
		await get_tree().process_frame
		_open_end()
		await get_tree().process_frame
		_close()
		games += 1
		print("BEJARAS mag=%d lepes=%d T2100=%.2f naplo=%d" % [seed_v, world.max_steps, world.result()["T"], world.naplo.size()])
	print("BEJARAS kész: %d játék" % games)
	get_tree().quit()
