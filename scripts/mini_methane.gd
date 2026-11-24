extends Control
## Minijáték: Metánvadász. Egy műhold újra és újra végigpásztázza az olaj- és gázmezőt; a nagy
## szivárgások felhője ilyenkor láthatóvá válik. A játékos rákattint, és javítócsapatot küld oda.
## A tanulság számai valódiak (Lauvaux és mtsai 2022, Alvarez és mtsai 2018; adatok/metan_szivargas.json).
## Játékszabály: a kutak helye, a szivárgások mérete (néhány nagy, sok kicsi), a műhold áthaladása,
## a csapatok száma és az idő kitalált.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const MAP := Rect2(60, 170, 1480, 640)
const SITES := 60             # játékszabály
const CREWS := 6              # játékszabály: ennyi javítócsapat
const TIME := 40.0            # játékszabály: másodperc
const PASS_SECONDS := 5.0     # játékszabály: egy műholdas áthaladás ideje
const SEEN_SHARE := 0.15      # játékszabály: a műhold a kutak legnagyobb 15%-ának szivárgását látja

var data_path := "res://adatok/metan_szivargas.json"
var auto := false             # próbafutás: mindig a legnagyobb látható felhőt javítja
var done_t := -1.0            # a befejezés óta eltelt idő; < 0 = még tart
var sites: Array = []         # [{pos, e, seen, fixed, fix_t}]
var total := 0.0
var fixed_e := 0.0
var fixed_n := 0
var wasted := 0
var crews := CREWS
var facts := {}
var source := ""
var _cut := 0.0               # ennél nagyobb szivárgást lát a műhold
var _t := 0.0
var _play_t := 0.0
var _auto_t := 0.0
var _pipes: Array = []
var _info: Label
var _read: Label
var _end: VBoxContainer
var _msg := ""
var _msg_t := 0.0
var _msg_pos := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	_make_field()
	var title := UI.heading(L.t("Metánvadász"), 34)
	title.position = Vector2(60, 28)
	add_child(title)
	_info = UI.label(L.t("A műhold végigpásztázza a gázmezőt. Ahol felhő jelenik meg, ott nagy a szivárgás: kattints rá, és küldj oda javítócsapatot!"), 18, UI.SOFT)
	_info.position = Vector2(60, 84)
	_info.size = Vector2(980, 60)
	add_child(_info)
	_read = UI.label("", 20, UI.CYAN, true, false)
	_read.position = Vector2(1100, 40)
	add_child(_read)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(140, 300)
	_end.size = Vector2(1320, 400)
	_end.visible = false
	add_child(_end)
	_update_read()
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	facts = j
	source = str(j.get("forras_en" if L.is_en() else "forras", ""))


## Játékszabály: a szivárgások mérete erősen egyenlőtlen (néhány nagy, sok kicsi), mert a mérések is ezt mutatják.
func _make_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var emax := 0.0
	for i in SITES:
		var p := Vector2(rng.randf_range(MAP.position.x + 30.0, MAP.end.x - 30.0), rng.randf_range(MAP.position.y + 30.0, MAP.end.y - 30.0))
		var e := pow(rng.randf_range(0.02, 1.0), -1.1)      # hosszú farkú eloszlás
		sites.append({"pos": p, "e": e, "seen": false, "fixed": false, "fix_t": 0.0})
		emax = maxf(emax, e)
		total += e
	var es: Array = []
	for s in sites:
		s["rel"] = float(s["e"]) / emax
		es.append(float(s["e"]))
	es.sort()
	_cut = float(es[int(es.size() * (1.0 - SEEN_SHARE))])
	for i in sites.size():      # vezetékek: minden kút a legközelebbi korábbihoz
		var best := -1
		var bd := INF
		for k in i:
			var d: float = (sites[i]["pos"] as Vector2).distance_to(sites[k]["pos"])
			if d < bd:
				bd = d
				best = k
		if best >= 0:
			_pipes.append([sites[i]["pos"], sites[best]["pos"]])


func ok() -> bool:
	return sites.size() == SITES and total > 0.0 and facts.has("muhold")


func _scan_x() -> float:
	return MAP.position.x + MAP.size.x * fmod(_play_t / PASS_SECONDS, 1.0)


func _update_read() -> void:
	_read.text = L.t("Csapat: %d    Idő: %d mp") % [crews, int(ceil(maxf(TIME - _play_t, 0.0)))]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		finished.emit(done_t >= 0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if done_t < 0.0:
			_click(event.position)


func _click(p: Vector2) -> void:
	var best := -1
	var bd := 40.0
	for i in sites.size():
		var d := p.distance_to(sites[i]["pos"])
		if d < bd and not bool(sites[i]["fixed"]):
			bd = d
			best = i
	if best < 0 or crews <= 0:
		return
	_fix(best)


func _fix(i: int) -> void:
	var s: Dictionary = sites[i]
	crews -= 1
	s["fixed"] = true
	s["fix_t"] = _t
	fixed_e += float(s["e"])
	fixed_n += 1
	if not bool(s["seen"]):
		wasted += 1
	_msg = L.t("Kicsi szivárgás") if float(s["rel"]) < 0.2 else L.t("Nagy szivárgás elzárva!")
	_msg_t = _t
	_msg_pos = s["pos"]
	_update_read()
	if crews <= 0:
		_finish()


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
		queue_redraw()
		return
	var px := _scan_x()
	_play_t += delta
	var nx := _scan_x()
	for s in sites:      # a műhold sávja alatt a nagy szivárgás láthatóvá válik
		var x: float = (s["pos"] as Vector2).x
		var crossed := (x >= px and x < nx) or (nx < px and (x >= px or x < nx))
		if crossed and float(s["e"]) >= _cut:
			s["seen"] = true
	if auto:
		_auto_t += delta
		if _auto_t >= 2.6:
			_auto_t = 0.0
			var best := -1
			var be := 0.0
			for i in sites.size():
				if bool(sites[i]["seen"]) and not bool(sites[i]["fixed"]) and float(sites[i]["e"]) > be:
					be = float(sites[i]["e"])
					best = i
			if best >= 0:
				_fix(best)
	_update_read()
	if _play_t >= TIME and done_t < 0.0:
		_finish()
	queue_redraw()


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_info.visible = false
	_read.visible = false
	var m: Dictionary = facts.get("muhold", {})
	var u: Dictionary = facts.get("usa_2015", {})
	_end.visible = true
	_end.add_child(UI.label(L.t("A kutak %s%%-át javítottad, és ezzel a szivárgás %s%%-át állítottad meg.") % [L.num(100.0 * fixed_n / SITES, 0), L.num(100.0 * fixed_e / maxf(total, 0.001), 0)], 22, UI.CYAN, true))
	_end.add_child(UI.label(L.t("Kevés nagy szivárgás adja a metán nagy részét. Ezeket érdemes először megtalálni."), 19, UI.TEXT))
	_end.add_child(UI.label(L.t("A valóságban: műholdas mérések szerint (%s) néhány száz óriási szivárgás adta az olaj- és gázipari metán %s–%s%%-át, évi kb. %s millió tonnát. A javításuk nagyrészt olcsó.") % [str(m.get("evek", "")), L.num(float(m.get("oriasi_szivargasok_aranya_min", 0)), 0), L.num(float(m.get("oriasi_szivargasok_aranya_max", 0)), 0), L.num(float(m.get("oriasi_szivargasok_millio_tonna_ev", 0)), 0)], 19, UI.TEXT, true))
	_end.add_child(UI.label(L.t("Az USA-ban 2015-ben az olaj- és gázágazat kb. %s%%-kal több metánt engedett ki, mint a hivatalos becslés.") % L.num(float(u.get("tobblet_szazalek", 0)), 0), 19, UI.TEXT))
	_end.add_child(UI.label(L.t("Adat: %s") % source, 13, UI.MUTE))
	var b := UI.button(L.t("Tovább") + " →", true)
	b.pressed.connect(func() -> void: finished.emit(true))
	b.position = Vector2(1390, 30)
	add_child(b)


func _draw_site(p: Vector2, fixed: bool) -> void:
	var c := Color("#c9d1de") if not fixed else UI.GREEN
	draw_line(p + Vector2(-8, 8), p + Vector2(0, -12), c, 2.0)
	draw_line(p + Vector2(8, 8), p + Vector2(0, -12), c, 2.0)
	draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), c, 1.5)
	draw_rect(Rect2(p + Vector2(-10, 8), Vector2(20, 4)), Color(c, 0.8))


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, W, H), Color("#0b1324"))
	# --- a mező: száraz, sötét síkság ---
	for i in 30:
		var f := i / 30.0
		draw_rect(Rect2(MAP.position.x, MAP.position.y + f * MAP.size.y, MAP.size.x, MAP.size.y / 30.0), Color("#3a2f24").lerp(Color("#251d17"), f))
	draw_rect(MAP, Color(UI.MUTE, 0.3), false, 1.0)
	for pp in _pipes:
		draw_line(pp[0], pp[1], Color(0.55, 0.5, 0.42, 0.35), 2.0)
	# --- szivárgások: a látható felhő mérete a szivárgással nő ---
	for s in sites:
		var p: Vector2 = s["pos"]
		var rel: float = s["rel"]
		if bool(s["seen"]):
			var fade := 1.0
			if bool(s["fixed"]):
				fade = clampf(1.0 - (_t - float(s["fix_t"])) / 1.5, 0.0, 1.0)
			if fade > 0.0:
				var r := 18.0 + sqrt(rel) * 70.0
				for k in 5:
					var o := Vector2(sin(_t * 0.8 + k * 1.7) * r * 0.25 + k * r * 0.18, cos(_t * 0.6 + k) * r * 0.15 - k * 6.0)
					draw_circle(p + o, r * (1.0 - k * 0.12), Color(0.93, 0.52, 0.35, 0.10 * fade))
				draw_circle(p, r * 0.35, Color(0.93, 0.52, 0.35, 0.22 * fade))
		_draw_site(p, bool(s["fixed"]))
	if done_t < 0.0:
		# --- a műhold sávja és maga a műhold ---
		var x := _scan_x()
		draw_rect(Rect2(x - 30.0, MAP.position.y, 60.0, MAP.size.y), Color(UI.CYAN, 0.10))
		draw_line(Vector2(x, MAP.position.y), Vector2(x, MAP.end.y), Color(UI.CYAN, 0.5), 1.5)
		var sp := Vector2(x, MAP.position.y - 18.0)
		draw_rect(Rect2(sp - Vector2(8, 6), Vector2(16, 12)), Color("#c9d1de"))
		draw_rect(Rect2(sp - Vector2(34, 3), Vector2(22, 6)), Color(UI.CYAN, 0.8))
		draw_rect(Rect2(sp + Vector2(12, -3), Vector2(22, 6)), Color(UI.CYAN, 0.8))
		if _t - _msg_t < 1.2 and _msg != "":
			draw_string(font, _msg_pos + Vector2(-120, -40), _msg, HORIZONTAL_ALIGNMENT_CENTER, 240, 17, UI.GOLD)
		draw_string(font, Vector2(60, 850), L.t("A felhők mérete jelkép. A kis szivárgásokat a műhold nem látja."), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.MUTE)
	else:
		draw_rect(Rect2(110, 270, 1380, 440), Color(0.043, 0.063, 0.114, 0.9 * clampf(done_t / 0.8, 0.0, 1.0)))
