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
const DISASTER := {"hoseg": "Hőhullám", "aszaly": "Aszály", "arviz": "Áradás", "tuz": "Erdőtűz"}
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
		for i in 140:
			_stars.append([Vector2(rng.randf() * 1600.0, rng.randf() * 900.0).snapped(Vector2(2, 2)),
				rng.randf_range(0.6, 2.2), rng.randf() * TAU, 2.0 if rng.randf() < 0.15 else 1.0])

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for s in _stars:
			var a: float = 0.25 + 0.55 * (0.5 + 0.5 * sin(_t * float(s[1]) + float(s[2])))
			var sz: float = float(s[3]) * 2.0
			draw_rect(Rect2(s[0], Vector2(sz, sz)), Color(0.85, 0.92, 1.0, a))


func _ready() -> void:
	L.init()
	UI.load_fonts()
	Cards.load_all()
	theme = _make_theme()
	get_tree().node_added.connect(_on_node_added)
	var args := OS.get_cmdline_user_args()
	_test = "--onteszt" in args or "--bejaras" in args
	_dry = _test and not ("--eles" in args)
	if _test or "--intro-kepek" in args:
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

	globe = Globe.new()
	globe.position = Vector2(400, 44)
	globe.size = Vector2(800, 800)
	globe.fixed_sun = true
	globe.station_clicked.connect(func(s: Dictionary) -> void:
		if s.has("id") and _overlay == null:
			_open_group(world.group(s["id"])))
	add_child(globe)

	_build_top()
	_build_groups()
	_build_bottom()
	_build_menu()
	_refresh()
	if "--bejaras" in args:
		_walkthrough()
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
	sb.set_corner_radius_all(6)
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
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var mb := UI.button(L.t("Menü"))
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mb.focus_mode = Control.FOCUS_NONE
	mb.pressed.connect(func() -> void: _show_menu(not _menu.visible))
	h.add_child(mb)


func _build_groups() -> void:
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
		b.mouse_entered.connect(func() -> void: globe.look_at_event({"lat": g["lat"], "lon": g["lon"]}))
		var v := UI.vbox(4)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14
		v.offset_top = 10
		v.offset_right = -14
		v.offset_bottom = -10
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		add_child(b)
		_group_cards[gid] = {"gomb": b, "doboz": v}


func _fill_group(g: Dictionary) -> void:
	var v: VBoxContainer = _group_cards[g["id"]]["doboz"]
	UI.clear(v)
	var col := Color(str(g["szin"]))
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
	var shaky: bool = g.get("inog", false)
	if shaky:
		v.add_child(_lbl("⚠ " + L.t("Bizonytalan"), 15, UI.GOLD, true))
	var fears := HFlowContainer.new()
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
	if shaky and n > 0 and world.steps > 0:
		v.add_child(_lbl(L.t("Erősítsd meg őket") + " →", 15, UI.GOLD, true))
	elif world.can_convince(g):
		v.add_child(_lbl(L.t("Meggyőzheted őket") + " →", 15, UI.CYAN, true))
	elif world.targets_for(g).is_empty() and int(g["metan"]) > 0 and g.get("felkeszult", false):
		v.add_child(_lbl(L.t("Tőlük már nincs mit kérned."), 14, UI.GREEN))
	elif g["konnyebb"] and not world.targets_for(g).is_empty():
		v.add_child(_lbl(L.t("Most könnyebb meggyőzni"), 14, UI.GOLD))
	else:
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
			["kivonas", L.t("CO2-kivonás"), 160, _open_cdr], ["ido", L.t("Következő 5 év") + "  ▶", 210, _advance]]:
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
func _pick_game(code: int = -1) -> void:
	var body := _open(L.t("Új játék"), UI.CYAN)
	for row in [["Könnyű", 5], ["Közepes", 4], ["Nehéz", 3]]:
		var n: int = row[1]
		body.add_child(_go("%s · %s" % [L.t(row[0]), L.t("%d lépés körönként") % n], func() -> void: _new_game(code, n), n == 4))


func _new_game(code: int = -1, steps_n: int = World.STEPS) -> void:
	_close()
	world.new_game(code, steps_n)
	_offers = {}
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
	if world.over():
		(_stats["ev"] as Label).text = "2100"
		(_stats["ev_al"] as Label).text = L.t("vége")
	else:
		(_stats["ev"] as Label).text = "%d–%d" % [y, y + World.ROUND_YEARS - 1]
		(_stats["ev_al"] as Label).text = L.t("%d. kör a 15-ből") % (world.round_i + 1)
	var t := float(world.st["T"])
	(_stats["meleg"] as Label).text = "+%s °C" % L.num(t, 2)
	var fc := world.forecast()
	if not world.over():
		(_stats["meleg_al"] as Label).text = L.t("2100-ban: +%s és +%s °C között") % [L.num(float(fc["also"][-1][1]), 1), L.num(float(fc["felso"][-1][1]), 1)]
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
		var shaky: bool = g.get("inog", false)
		marks.append({"id": g["id"], "name": L.field(g, "nev"), "label": ("⚠ " if shaky else "") + L.field(g, "nev"), "lat": g["lat"], "lon": g["lon"],
			"color": UI.GOLD if shaky else Color(str(g["szin"]))})
	for tp in world.tips:
		var rng_txt := L.t("küszöb: %s–%s °C") % [L.num(float(tp["also"]), 1), L.num(float(tp["felso"]), 1)]
		if int(tp["ev"]) > 0:
			marks.append({"name": "%s\n%s %d · %s" % [L.field(tp, "nev"), L.t("küszöb átlépve:"), int(tp["ev"]), rng_txt], "lat": tp["lat"], "lon": tp["lon"], "color": UI.EMBER, "small": true})
		else:
			marks.append({"name": "%s\n%s" % [L.field(tp, "nev"), rng_txt], "lat": tp["lat"], "lon": tp["lon"], "color": Color(0.75, 0.82, 0.92), "small": true, "dim": true})
	globe.stations = marks
	var allies: Array = world.groups.filter(func(g: Dictionary) -> bool: return int(g["cel"]) > 0)
	allies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["lon"]) < float(b["lon"]))
	var lines: Array = []
	for i in range(1, allies.size()):
		lines.append([allies[i - 1]["lat"], allies[i - 1]["lon"], allies[i]["lat"], allies[i]["lon"]])
	globe.links = lines
	_mark_next()
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
		for g in world.groups:       # először az, aki elbizonytalanodott, és van neki szóló kártyád
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
			b.add_theme_stylebox_override("normal", _flat(Color("#1f6f66"), UI.CYAN, 3))
			b.add_theme_stylebox_override("hover", _flat(Color("#2a8a7f"), UI.CYAN, 3))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_stylebox_override("hover")
			b.remove_theme_color_override("font_color")
	_btns["kutatas"].disabled = world.steps <= 0 or world.over()
	_btns["kivonas"].disabled = world.steps <= 0 or world.over()
	_btns["ido"].text = L.t("Végeredmény") if world.over() else L.t("Következő 5 év") + "  ▶"
	_btns["kartyak"].text = "%s (%d)" % [L.t("Kártyáim"), world.hand.size()]
	_mission_btn.visible = not world.missions.is_empty()
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


# --- ablakok ------------------------------------------------------------------
func _open(title: String, accent: Color = UI.GOLD) -> VBoxContainer:
	var keep := _flash_ids       # a felvillanás az ablak valódi bezárásakor jön, nem ablakváltáskor
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
	var h := clampf(body.get_combined_minimum_size().y + 118.0, 240.0, 720.0)
	p.custom_minimum_size.y = h
	p.size.y = h
	p.position.y = maxf(40.0, (800.0 - h) * 0.5)
	if _close_x != null:
		_close_x.position = p.position + Vector2(920 - 22, -22)


var _flash_ids: Array = []        # akiknél az ablak bezárása után felvillanás jár (egyezség, megerősítés, csúcs)

func _close() -> void:
	for n in [_overlay, _dim, _close_x]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_overlay = null
	_dim = null
	_close_x = null
	for gid in _flash_ids:
		var g := world.group(gid)
		if g.is_empty() or not _group_cards.has(gid):
			continue
		globe.flash(float(g["lat"]), float(g["lon"]), Color(str(g["szin"])).lightened(0.3))
		var card: Control = _group_cards[gid]["gomb"]
		card.modulate = Color(1.9, 1.9, 1.9)
		create_tween().tween_property(card, "modulate", Color.WHITE, 0.2 if _test else 1.2)
	_flash_ids = []


func _unhandled_input(event: InputEvent) -> void:
	if _intro != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _overlay != null:
			_close()
		elif event.keycode == KEY_ESCAPE:
			_show_menu(not _menu.visible)
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
	var past: Variant = L.get_setting("foldek", [])
	if typeof(past) != TYPE_ARRAY:
		past = []
	var dd := Time.get_date_dict_from_system()
	past.push_front({"ev": int(dd["year"]), "ho": int(dd["month"]), "nap": int(dd["day"]), "T": t, "lepes": world.max_steps, "mag": world.seed_v})
	L.set_setting("foldek", past.slice(0, 12))
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
	var mdone := int(L.get_setting("kuldetesek", 0))
	if mdone > 0:
		body.add_child(UI.label(L.t("Teljesített küldetések: %d") % mdone, 17, UI.GREEN))
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
			(colv[0 if i < half else 1] as Control).add_child(UI.label("%s · +%s °C · %s · %s: %d" % [date, L.num(float(e["T"]), 2), level, L.t("Föld-kód"), int(e["mag"])], 15, UI.SOFT))
	var have := _badges()
	body.add_child(UI.label(L.t("Jelvények: %d / %d") % [have.size(), BADGES.size()], 19, UI.GOLD, true, false))
	var bg := GridContainer.new()
	bg.columns = 2
	bg.add_theme_constant_override("h_separation", 12)
	bg.add_theme_constant_override("v_separation", 8)
	body.add_child(bg)
	for row in BADGES:
		var got: bool = row[0] in have
		var cell := UI.vbox(0)
		cell.custom_minimum_size = Vector2(428, 0)
		cell.add_child(UI.label(("★ " if got else "☆ ") + L.t(row[1]), 17, UI.GOLD if got else UI.MUTE, true, false))
		cell.add_child(UI.label(L.t(row[2]), 14, UI.SOFT if got else UI.MUTE))
		bg.add_child(cell)
	for th in Cards.THEMES:
		var mine: Array = Cards.TAGS[th].filter(func(id: String) -> bool: return id in c)
		var head := UI.hbox(10)
		head.add_child(Icons.rect(th, _theme_color(th), 24))
		head.add_child(UI.label(_theme_name(th), 18, _theme_color(th), true, false))
		head.add_child(UI.label("%d / %d" % [mine.size(), Cards.TAGS[th].size()], 15, UI.SOFT, false, false))
		body.add_child(head)
		for id in mine:
			var b := UI.text_link(Cards.text(id, "Kérdés", L.is_en()), "", 16)
			for cn in b.pressed.get_connections():
				b.pressed.disconnect(cn["callable"])
			b.pressed.connect(_open_card.bind(id, false))
			body.add_child(b)


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
		for path in Intro.OWN_MUSIC:        # a játékos saját zenefájlja, ha van (nem része a játéknak)
			var full := ProjectSettings.globalize_path(path)
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
	body.add_child(UI.label(L.t("Válassz témakört. Három valódi kérdést kapsz, egyet kutathatsz ki: ebből lesz bizonyíték-kártyád."), 17, UI.SOFT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
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
		if not shaky_who.is_empty() and n > 0:
			v.add_child(_lbl("⚠ %s: %s" % [", ".join(shaky_who), L.t("Bizonytalan")], 13, UI.GOLD))
		else:
			v.add_child(_lbl(L.t("%d kérdés vár") % n if n > 0 else L.t("Itt most nincs új kérdés"), 13, UI.MUTE))
		b.add_child(v)
		var ic := Icons.rect(th, Color(col, 0.9 if n > 0 else 0.3), 30)
		ic.size = Vector2(30, 30)
		ic.position = Vector2(420 - 30 - 12, 8)
		b.add_child(ic)
		b.pressed.connect(_research_theme.bind(th))
		grid.add_child(b)


func _research_theme(th: String) -> void:
	if not _offers.has(th):
		_offers[th] = world.research_offers(th)
	var body := _open(_theme_name(th), _theme_color(th))
	var offers: Array = _offers[th].filter(func(id: String) -> bool: return not (id in world.hand))
	if offers.is_empty():
		body.add_child(UI.label(L.t("Itt most nincs új kérdés"), 17, UI.SOFT))
	else:
		body.add_child(UI.label(L.t("Melyik kérdést kutatod ki? Egy lépésbe kerül."), 17, UI.SOFT))
	for id in offers:
		var c := UI.card(_theme_color(th))
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
		_open_card(id, true)


func _open_card(id: String, fresh: bool = false) -> void:
	var th := Cards.theme_of(id)
	var body := _open(L.t("Új bizonyíték-kártya") if fresh else L.t("Bizonyíték-kártya"), _theme_color(th) if th != "" else UI.GOLD)
	var en := L.is_en()
	if fresh and _new_rank != "":
		body.add_child(UI.label("★ " + L.t("Új rang: %s") % L.t(_new_rank), 20, UI.GOLD, true))
		_new_rank = ""
	body.add_child(UI.label(Cards.text(id, "Kérdés", en), 24, UI.TEXT, true))
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
		body.add_child(UI.label(L.t(pair[0]), 16, pair[1], true, false))
		body.add_child(UI.label(txt, 17, UI.TEXT))
	body.add_child(UI.label(L.t("Források"), 16, UI.GOLD, true, false))
	for s in Cards.card(id).get("forrasok", []):
		body.add_child(UI.text_link(str(s["cim"]), str(s["link"]), 15))
	if World.CDR.has(id):
		body.add_child(UI.label(L.t("Ezzel a kártyával CO2-kivonást indíthatsz."), 16, UI.GREEN, true))
	body.add_child(_go(L.t("Rendben"), _close))


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
	body.add_child(UI.label(L.t("A világ CO2-kibocsátásának %s%%-a") % L.num_short(float(g["co2_resz"]) * 100.0, 0), 16, UI.SOFT))
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
	if g.get("inog", false):
		asks.append({"fajta": "megerosites", "kell": 1})
	for t in targets:
		asks.append({"fajta": "cel", "cel": t, "kell": world.cards_needed(g, t)})
	if int(g["metan"]) == 0:
		asks.append({"fajta": "metan", "kell": world.methane_needed(g)})
	if not g.get("felkeszult", false):
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
	for a in asks:
		var txt: String = (L.rag(L.t("Nulla kibocsátás %d-re") % int(a["cel"]))) if a["fajta"] == "cel" else (L.t("Metán: −30% tíz év alatt") if a["fajta"] == "metan" \
			else (L.t("Megerősítés") if a["fajta"] == "megerosites" else L.t("Felkészülés a bajra")))
		var b := UI.button("%s · %s" % [txt, L.t("%d kártya") % int(a["kell"])])
		if a["fajta"] in ["cel", "metan"]:
			var dt := world.preview(g, int(a.get("cel", 0)), a["fajta"] == "metan")
			b.text += " · %s °C" % L.num(dt, 2).replace("-", "−")
		b.toggle_mode = true
		b.button_group = bg
		b.focus_mode = Control.FOCUS_NONE
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
	var status := UI.label("", 16, UI.SOFT)
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
	area.add_child(top)
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
			area.add_child(UI.label(L.t("Elbizonytalanodtak. Ha a kör végéig nem erősíted meg őket, megingnak, és későbbre tolják a céljukat."), 16, UI.GOLD))
		area.add_child(UI.label(L.t("Amitől tartanak:"), 17, UI.GOLD, true, false))
		var usable := world.usable(g)
		for th in g["felelmek"]:
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
			done = world.negotiate(g, int(ask["cel"]), picked)
		if done:
			_refresh()
			_sound("egyezseg")
			_agreed(g, ask, before))


func _agreed(g: Dictionary, ask: Dictionary, before: float = -1.0) -> void:
	_flash_ids = [g["id"]]
	if ask["fajta"] == "megerosites":
		var b2 := _open(L.field(g, "nev"), UI.GREEN)
		b2.add_child(UI.label(L.t("%s megingott, de kitartott.") % L.field(g, "nev"), 22, UI.GREEN, true))
		b2.add_child(UI.label(L.t("A bizonyítékod miatt kitartottak: %s") % Cards.text(ask["kartya"], "Kérdés", L.is_en()), 17, UI.SOFT))
		b2.add_child(_go(L.t("Rendben"), _close))
		return
	var body := _open(L.t("Egyezség kötve!"), UI.GREEN)
	if ask["fajta"] == "felkeszules":
		body.add_child(UI.label(L.t("%s felkészült a bajra. Megbízik benned, és többé nem inog meg.") % L.field(g, "nev"), 22, UI.TEXT, true))
		body.add_child(_go(L.t("Rendben"), _close))
		return
	var txt: String = (L.rag(L.t("%s vállalta: nulla kibocsátás %d-re.") % [L.field(g, "nev"), int(ask["cel"])])) if ask["fajta"] == "cel" \
		else (L.t("%s vállalta: 30%%-kal kevesebb metán tíz év alatt.") % L.field(g, "nev"))
	body.add_child(UI.label(txt, 22, UI.TEXT, true))
	var fc := world.forecast()
	var after := float(fc["kozep"][-1][1])
	if before > 0.0:
		body.add_child(UI.label(L.t("Várható melegedés 2100-ban: +%s → +%s °C") % [L.num(before, 2), L.num(after, 2)], 22, UI.GREEN, true))
	body.add_child(UI.label(L.t("2100-ban: +%s és +%s °C között") % [L.num(float(fc["also"][-1][1]), 1), L.num(float(fc["felso"][-1][1]), 1)], 17, UI.SOFT))
	body.add_child(UI.label(L.t("A sáv azért széles, mert nem tudjuk pontosan, mennyire érzékeny a Föld."), 15, UI.MUTE))
	body.add_child(_go(L.t("Rendben"), _close))


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
			c.add_child(UI.label(L.t("Előbb kutasd ki: %s") % Cards.text(id, "Kérdés", L.is_en()), 15, UI.MUTE))
		body.add_child(UI.card_root(c))


# --- telik az idő -------------------------------------------------------------
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
	world.advance()
	_offers = {}
	var fc := world.forecast()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(globe, "spin", globe.spin + 1.0, 0.2 if _test else 2.6)
	# évről évre: az évszám, a hőmérséklet, a görbe és a Föld színe együtt lép
	for i in range(n0, world.history.size()):
		var row: Array = world.history[i]
		(_stats["ev"] as Label).text = str(int(row[0]))
		(_stats["meleg"] as Label).text = "+%s °C" % L.num(float(row[1]), 2)
		_curve.set_data(world.history.slice(0, i + 1), world.base_history.slice(0, i + 1), fc)
		globe.heat = lerpf(heat0, clampf((float(world.st["T"]) - M.T_START) / 2.0, 0.0, 1.5), float(i - n0 + 1) / float(World.ROUND_YEARS))
		await get_tree().create_timer(0.03 if _test else 0.5).timeout
	if tw.is_running():
		await tw.finished
	_busy = false
	_refresh()
	var kinds: Array = world.news.map(func(n: Dictionary) -> String: return str(n["fajta"]))
	_sound("zaro" if world.over() else ("billenes" if "billenes" in kinds else ("katasztrofa" if "katasztrofa" in kinds else ("megingas" if ("visszalepett" in kinds or "inog" in kinds) else ("jo_hir" if ("nulla" in kinds or "vilag_nulla" in kinds) else "korvaltas")))))
	_open_news(y0, t0)


func _open_news(y0: int, t0: float) -> void:
	var body := _open("%d–%d" % [y0, y0 + World.ROUND_YEARS - 1])
	var t1 := float(world.st["T"])
	body.add_child(UI.label(L.t("A Föld melegedése: +%s → +%s °C") % [L.num(t0, 2), L.num(t1, 2)], 22, UI.EMBER if t1 > t0 + 0.005 else UI.GREEN, true))
	for n in world.news:
		match str(n["fajta"]):
			"billenes":
				var tp: Dictionary = world.tips.filter(func(x: Dictionary) -> bool: return x["id"] == n["id"])[0]
				var c := UI.card(UI.EMBER)
				c.add_child(UI.label(L.t("Átlépte a küszöbét: %s (%d)") % [L.field(tp, "nev"), int(n["ev"])], 19, UI.EMBER, true))
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
				c5.add_child(UI.label(L.t("Erősítsd meg őket egy hozzájuk illő kártyával, különben öt év múlva megingnak!"), 16, UI.SOFT))
				body.add_child(UI.card_root(c5))
			"kitartott":
				var c3 := UI.card(UI.GREEN)
				c3.add_child(UI.label(L.t("%s megingott, de kitartott.") % L.field(world.group(n["csoport"]), "nev"), 18, UI.GREEN, true))
				c3.add_child(UI.label(L.t("A bizonyítékod miatt kitartottak: %s") % Cards.text(n["kartya"], "Kérdés", L.is_en()), 16, UI.SOFT))
				body.add_child(UI.card_root(c3))
			"katasztrofa":
				var c4 := UI.card(UI.EMBER)
				c4.add_child(UI.label("%s: %s" % [L.t(DISASTER[n["mi"]]), L.field(world.group(n["csoport"]), "nev")], 18, UI.EMBER, true))
				if world.group(n["csoport"]).get("felkeszult", false):
					c4.add_child(UI.label(L.t("Felkészültek rá, ezért kisebb volt a baj."), 16, UI.GREEN))
				c4.add_child(UI.label(L.t("A baj után jobban figyelnek rád: most eggyel kevesebb kártyával is meggyőzheted őket."), 16, UI.SOFT))
				body.add_child(UI.card_root(c4))
	if world.news.is_empty():
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
	body.add_child(UI.label(L.t("A jövő hírei a játék részei, nem valódi események."), 13, UI.MUTE))
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
	var body := _open(L.t("Döntés"), UI.GOLD)
	var opts: Array = []
	if d["fajta"] == "tamogatas":
		body.add_child(UI.label(L.t("Egy alapítvány támogatja a munkádat. Mire kéred?"), 18, UI.TEXT))
		opts = [L.t("Több kutató: ebben a körben eggyel több lépésed van."),
			L.t("Felkészítő program: %s azonnal felkészül a bajra.") % L.field(world.group(str(d["a"])), "nev")]
	else:
		body.add_child(UI.label(L.t("Két meghívást kaptál, de csak egy útra van időd. Akit meglátogatsz, azt most eggyel kevesebb kártyával is meggyőzheted."), 18, UI.TEXT))
		opts = [L.field(world.group(str(d["a"])), "nev"), L.field(world.group(str(d["b"])), "nev")]
	for i in opts.size():
		body.add_child(_go(str(opts[i]) + " →", _do_dilemma.bind(i), false))
	body.add_child(UI.label(L.t("A jövő hírei a játék részei, nem valódi események."), 13, UI.MUTE))


func _do_dilemma(choice: int) -> void:
	world.resolve_dilemma(choice)
	_sound("kartya")
	_save()
	_refresh()
	_close()


func _open_summit() -> void:
	var body := _open("%s %d" % [L.t("Klímacsúcs"), world.year()], UI.GOLD)
	body.add_child(UI.label(L.t("Mutass meg egy kártyát az egész világnak! Aki már vállalt célt, és a kártya az ő aggodalmára felel, öt évvel előbbre hozza. Ez nem kerül lépésbe."), 17, UI.SOFT))
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
	body.add_child(_go(L.t("Rendben"), _close))


func _open_end() -> void:
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
		var a := UI.label(side[0], 20, side[3], true, false)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		var b := UI.label("+%s °C" % L.num(float(side[1]), 2), 34, side[3], true, false)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(b)
		var c := UI.label(L.t("A tenger kb. %s cm-rel magasabb") % L.num_short(float(side[2]) * 100.0, 0), 15, UI.SOFT, false, false)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(c)
		row.add_child(v)
	var tt := float(r["T"])
	var verdict := "A Földed +1,7 °C alatt maradt. 2026-ból indulva ennél sokkal jobbat már alig lehet elérni." if tt < 1.7 \
		else ("A Földed +2 °C alatt maradt. A Párizsi Megállapodás ennél többet kér: jóval +2 °C alatt megállni, lehetőleg +1,5 °C-nál." if tt < 2.0 \
		else "A Földed +2 °C fölé melegedett. A következő játékban lépj hamarabb!")
	body.add_child(UI.label(L.t(verdict), 19, UI.GREEN if tt < 2.0 else UI.EMBER, true))
	var fin := _finish_game(r)
	if fin["rekord"]:
		body.add_child(UI.label(L.t("Új rekord! Ez az eddigi legjobb Földed."), 19, UI.GOLD, true))
	for bd in BADGES:
		if bd[0] in fin["uj"]:
			body.add_child(UI.label("★ " + L.t("Új jelvény: %s") % L.t(bd[1]), 17, UI.GOLD, true))
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
	end_row.add_child(_go(L.t("Kép mentése"), func() -> void: saved_lbl.text = await _save_picture(), false))
	end_row.add_child(saved_lbl)
	body.add_child(end_row)
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
	if not world.naplo.is_empty():
		body.add_child(UI.label(L.t("A te történeted"), 19, UI.GOLD, true, false))
		_add_story(body)


const MISSION_TEXT := {
	"korai": "Győzd meg ezt a csoportot 2040 végéig: %s",
	"metan3": "2050 végéig legalább három csoport vállaljon metáncsökkentést.",
	"kivonas2": "Indíts el két CO2-kivonást.",
	"tema": "Kutass ki öt kártyát ebből a témakörből: %s",
	"felkeszul3": "Segíts három csoportnak felkészülni a bajra.",
	"nulla2065": "Legalább egy csoport érje el a nulla kibocsátást 2065-ig.",
	"csucs3": "Egy klímacsúcson legalább három csoport hozza előbbre a célját.",
	"kartya20": "Gyűjts húsz kártyát ebben a játékban.",
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
	body.add_child(UI.label(L.t("Három cél erre a játékra. Nem kötelezők, de jelvény jár értük."), 16, UI.SOFT))
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


## A játék fontos pillanatai évről évre, két oszlopban.
func _add_story(body: VBoxContainer) -> void:
	var grid := UI.hbox(24)
	var cols: Array = [UI.vbox(3), UI.vbox(3)]
	grid.add_child(cols[0])
	grid.add_child(cols[1])
	var lines: Array = []
	for e in world.naplo:
		var line := ""
		var lc := UI.SOFT
		match str(e["fajta"]):
			"cel":
				line = L.rag(L.t("%s vállalta: nulla kibocsátás %d-re.") % [L.field(world.group(e["csoport"]), "nev"), int(e["cel"])])
			"metan":
				line = L.t("%s vállalta: 30%%-kal kevesebb metán tíz év alatt.") % L.field(world.group(e["csoport"]), "nev")
			"felkeszules":
				line = L.t("%s felkészült a bajra.") % L.field(world.group(e["csoport"]), "nev")
			"kivonas":
				line = "%s: %s" % [L.t("CO2-kivonás"), L.t(CDR_NAME[e["id"]])]
			"nulla":
				line = (L.t("%s elérte a nulla kibocsátást (%d).") % [L.field(world.group(e["csoport"]), "nev"), int(e["ev"])]).replace(" (%d)" % int(e["ev"]), "")
				lc = UI.GREEN
			"vilag_nulla":
				line = (L.t("A világ már több CO2-t von ki, mint amennyit kibocsát (%d).") % int(e["ev"])).replace(" (%d)" % int(e["ev"]), "")
				lc = UI.GREEN
			"csucs":
				line = L.t("Klímacsúcs: %d csoport hozta előbbre a célját.") % int(e.get("db", 0))
			"visszalepett":
				line = L.rag(L.t("%s megingott: a célját %d-re tolta.") % [L.field(world.group(e["csoport"]), "nev"), int(e["cel"])])
				lc = UI.GOLD
			"billenes":
				var tp2: Array = world.tips.filter(func(x: Dictionary) -> bool: return x["id"] == e["id"])
				if not tp2.is_empty():
					line = L.t("küszöb átlépve:") + " " + L.field(tp2[0], "nev")
					lc = UI.EMBER
		if line != "":
			var ll := UI.label("%d · %s" % [int(e["ev"]), line], 14, lc)
			ll.custom_minimum_size = Vector2(400, 0)
			lines.append(ll)
	for i in lines.size():
		cols[0 if i < (lines.size() + 1) / 2 else 1].add_child(lines[i])
	body.add_child(grid)


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
			["2.", L.t("Körönként %s lépésed van. Kutass: minden kutatás egy bizonyíték-kártyát ad valódi tudományos forrásokkal.") % L.t({3: "három", 4: "négy", 5: "öt"}[world.max_steps])],
			["3.", "Kattints egy országcsoportra, és győzd meg a kártyáiddal. Minden csoport mástól tart, ezért más kártyára van szüksége."],
			["4.", "Lépj korán: minden év késés számít. Akit egyszer meggyőztél, attól később merészebb célt is kérhetsz."],
			["5.", "A cél: 2100-ban jóval +2 °C alatt maradni, minél közelebb a +1,5 °C-hoz. Ez a Párizsi Megállapodás célja is."],
			["6.", "A Föld érzékenységét senki sem ismeri pontosan, és vannak rejtett billenőpontok. Ne várj sokáig!"]]:
		var h := UI.hbox(12)
		h.add_child(UI.label(row[0], 22, UI.GOLD, true, false))
		h.add_child(UI.label(L.t(row[1]), 18, UI.TEXT))
		body.add_child(h)
	body.add_child(UI.label(L.t("Valódi: a klímamodell számai, a csoportok kibocsátása, a kártyák forrásai. Játékszabály: a tárgyalás, az aggodalmak mondatai, a jövő hírei."), 15, UI.MUTE))
	body.add_child(_go(L.t("Kezdjük!"), _close))


# --- önteszt: végigjátszik pár kört, és minden ablakról képet ment --------------
func _shot(name: String) -> void:
	var dir := OS.get_user_data_dir().path_join("aether_onteszt")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name))


func _selftest() -> void:
	await _shot("1_fooldal.png")
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
	_close()
	_open_group(world.group("kina"))
	await _shot("8_targyalas.png")
	var kina := world.group("kina")
	var kt: int = world.targets_for(kina)[0]
	world.negotiate(kina, kt, world.usable(kina).slice(0, 1))
	_refresh()
	_agreed(kina, {"fajta": "cel", "cel": kt}, 2.8)
	await _shot("9_megegyezes.png")
	_close()
	await get_tree().create_timer(0.6).timeout
	await _shot("9b_felvillanas.png")
	_open_hand()
	await _shot("10_kartyaim.png")
	_open_cdr()
	await _shot("11_kivonas.png")
	_open_collection()
	await _shot("11b_gyujtemeny.png")
	_pick_game()
	await _shot("11c_uj_jatek.png")
	_open_missions()
	await _shot("11g_kuldetesek.png")
	_open_story()
	await _shot("11e_tortenet.png")
	_close()
	_show_menu(true)
	await _shot("11f_menu.png")
	_show_menu(false)
	Cards.show_unproofed = true
	_open_card("napelem")
	await _shot("11d_kulcsszam.png")
	Cards.show_unproofed = false
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
		_new_game(seed_v, 3 + games % 3)
		while not world.over():
			if not world.dilemma.is_empty():
				_open_dilemma()
				await get_tree().process_frame
				_do_dilemma(world.round_i % 2)
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
