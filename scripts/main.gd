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
var _dim: ColorRect
var _close_x: Button
var _stats: Dictionary = {}
var _dots: Label
var _group_cards: Dictionary = {}
var _curve: Control
var _btns: Dictionary = {}
var _menu: PanelContainer
var _menu_catch: Control
var _reset_btn: Button
var _offers: Dictionary = {}          # témakör -> a körben felkínált kérdések (hogy ne lehessen újrahúzni)
var _busy := false
var _test := false
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
	var args := OS.get_cmdline_user_args()
	_test = "--onteszt" in args
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


func _sound(name: String) -> void:
	if _test:
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
func _stat(parent: Control, key: String, caption: String, color: Color, sub: bool = false) -> void:
	var v := UI.vbox(-3)
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
	var h := UI.hbox(44)
	p.add_child(h)
	var logo := UI.label("AETHER", 32, UI.CYAN, false, false)
	logo.add_theme_font_override("font", UI.font_pixel)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(logo)
	_stat(h, "ev", L.t("Év"), UI.TEXT, true)
	_stat(h, "meleg", L.t("Melegedés"), UI.EMBER, true)
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
	v.add_child(bar)
	if int(g["cel"]) > 0:
		v.add_child(_lbl(L.t("Nulla kibocsátás %d-re") % int(g["cel"]), 16, UI.GREEN, true))
	else:
		v.add_child(_lbl(L.t("Még nem vállalt semmit"), 16, UI.SOFT, true))
	if int(g["metan"]) > 0:
		v.add_child(_lbl(L.t("Metán: −30% tíz év alatt"), 14, UI.GREEN))
	if g["konnyebb"]:
		v.add_child(_lbl(L.t("Most könnyebb meggyőzni"), 14, UI.GOLD))
	var n := world.usable(g).size()
	var fears := HFlowContainer.new()
	fears.add_theme_constant_override("h_separation", 5)
	fears.add_theme_constant_override("v_separation", 4)
	fears.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for th in g["felelmek"]:
		var ch := _chip(_theme_name(th), _theme_color(th))
		ch.add_theme_font_size_override("font_size", 12)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fears.add_child(ch)
	v.add_child(fears)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	if world.can_convince(g):
		v.add_child(_lbl(L.t("Meggyőzheted őket") + " →", 15, UI.CYAN, true))
	else:
		v.add_child(_lbl(L.t("%d kártyád szól nekik") % n if n > 0 else L.t("Nincs nekik szóló kártyád"), 14, UI.SOFT if n > 0 else UI.MUTE))


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
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(190, 0)
	h.add_child(gap)
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
	_reset_btn = UI.button(L.t("Új játék"))
	_reset_btn.pressed.connect(_reset_game)
	v.add_child(_reset_btn)
	var quit := UI.button(L.t("Kilépés a játékból"))
	quit.pressed.connect(func() -> void:
		_save()
		get_tree().quit())
	v.add_child(quit)
	for b in v.get_children():
		(b as Button).focus_mode = Control.FOCUS_NONE


func _show_menu(on: bool) -> void:
	_menu.visible = on
	_menu_catch.visible = on


func _reset_game() -> void:
	if _reset_btn.text != L.t("Biztos? Kattints újra"):
		_reset_btn.text = L.t("Biztos? Kattints újra")
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if is_instance_valid(_reset_btn):
				_reset_btn.text = L.t("Új játék"))
		return
	_reset_btn.text = L.t("Új játék")
	_show_menu(false)
	_new_game()


func _new_game() -> void:
	_close()
	world.new_game()
	_offers = {}
	globe.home()
	_refresh()


func _save() -> void:
	if _test:
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
	_dots.text = "●".repeat(world.steps) + "○".repeat(World.STEPS - world.steps)
	for g in world.groups:
		_fill_group(g)
	_curve.set_data(world.history, world.base_history, fc)
	# a Föld képe: melegedés, pára és városfény a kibocsátás szerint, zöldülés a kivonással
	globe.heat = clampf((t - M.T_START) / 2.0, 0.0, 1.5)
	var ratio := world.net_ratio(y)
	globe.set_plan_look({"smog": clampf(ratio, 0.0, 1.0), "clean": clampf(1.0 - ratio, 0.0, 1.0), "regrow": clampf(-ratio / 0.25, 0.0, 1.0)})
	globe.sea_rise = clampf((t - M.T_START) / 2.0, 0.0, 1.0)
	var marks: Array = []
	for g in world.groups:
		marks.append({"id": g["id"], "name": L.field(g, "nev"), "label": L.field(g, "nev"), "lat": g["lat"], "lon": g["lon"], "color": Color(str(g["szin"]))})
	for tp in world.tips:
		if int(tp["ev"]) > 0:
			marks.append({"name": "%s · %s %d" % [L.field(tp, "nev"), L.t("küszöb átlépve:"), int(tp["ev"])], "lat": tp["lat"], "lon": tp["lon"], "color": UI.EMBER})
	globe.stations = marks
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
		for g in world.groups:
			if world.can_convince(g):
				hot = g["id"]
				break
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
	_btns["ido"].disabled = world.over()
	_btns["kartyak"].text = "%s (%d)" % [L.t("Kártyáim"), world.hand.size()]
	for gid in _group_cards:
		var gb: Button = _group_cards[gid]["gomb"]
		var col := Color(str(world.group(gid)["szin"]))
		gb.add_theme_stylebox_override("normal", _flat(Color(0.04, 0.06, 0.12, 0.88), UI.CYAN if gid == hot else Color(col, 0.55), 3 if gid == hot else 2))


# --- ablakok ------------------------------------------------------------------
func _open(title: String, accent: Color = UI.GOLD) -> VBoxContainer:
	_close()
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
	return body


func _close() -> void:
	for n in [_overlay, _dim, _close_x]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_overlay = null
	_dim = null
	_close_x = null


func _unhandled_input(event: InputEvent) -> void:
	if _intro != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _overlay != null:
			_close()
		elif event.keycode == KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


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
		var who: Array = []
		for g in world.groups:
			if th in g["felelmek"]:
				who.append(L.field(g, "nev"))
		var b := Button.new()
		b.custom_minimum_size = Vector2(420, 96)
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
		v.add_child(_lbl(L.t("Akit ez aggaszt: %s") % ", ".join(who) if not who.is_empty() else "", 14, UI.SOFT))
		v.add_child(_lbl(L.t("%d kérdés vár") % n if n > 0 else L.t("Itt most nincs új kérdés"), 13, UI.MUTE))
		b.add_child(v)
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
		_refresh()
		_sound("jel_jo")
		_open_card(id, true)


func _open_card(id: String, fresh: bool = false) -> void:
	var th := Cards.theme_of(id)
	var body := _open(L.t("Új bizonyíték-kártya") if fresh else L.t("Bizonyíték-kártya"), _theme_color(th) if th != "" else UI.GOLD)
	var en := L.is_en()
	body.add_child(UI.label(Cards.text(id, "Kérdés", en), 24, UI.TEXT, true))
	var chips := UI.hbox(8)
	if th != "":
		chips.add_child(_chip(_theme_name(th), _theme_color(th)))
	for g in world.groups:
		if th in g["felelmek"]:
			chips.add_child(_chip(L.field(g, "nev"), Color(str(g["szin"]))))
	body.add_child(chips)
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
		body.add_child(UI.label(_theme_name(th), 18, _theme_color(th), true, false))
		for id in mine:
			var b := UI.text_link(Cards.text(id, "Kérdés", L.is_en()), "", 17)
			for c in b.pressed.get_connections():
				b.pressed.disconnect(c["callable"])
			b.pressed.connect(_open_card.bind(id, false))
			body.add_child(b)


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
		body.add_child(UI.label(L.t("A játékban eddig: nulla kibocsátás %d-re.") % int(g["cel"]), 17, UI.GREEN, true))
	if world.over():
		return
	if world.steps <= 0:
		body.add_child(UI.label(L.t("Erre a körre elfogytak a lépéseid. Jöhet a következő öt év."), 17, UI.GOLD))
		return
	var targets := world.targets_for(g)
	var asks: Array = []
	for t in targets:
		asks.append({"fajta": "cel", "cel": t, "kell": world.cards_needed(g, t)})
	if int(g["metan"]) == 0:
		asks.append({"fajta": "metan", "kell": 1})
	if asks.is_empty():
		body.add_child(UI.label(L.t("Tőlük már nincs mit kérned."), 17, UI.SOFT))
		return
	body.add_child(UI.label(L.t("Mit kérsz tőlük?"), 19, UI.GOLD, true, false))
	var ask_row := HFlowContainer.new()
	ask_row.add_theme_constant_override("h_separation", 10)
	ask_row.add_theme_constant_override("v_separation", 10)
	body.add_child(ask_row)
	var area := UI.vbox(10)
	body.add_child(area)
	var bg := ButtonGroup.new()
	for a in asks:
		var txt: String = (L.t("Nulla kibocsátás %d-re") % int(a["cel"])) if a["fajta"] == "cel" else L.t("Metán: −30% tíz év alatt")
		var b := UI.button("%s · %s" % [txt, L.t("%d kártya") % int(a["kell"])])
		b.toggle_mode = true
		b.button_group = bg
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(func(on: bool) -> void:
			if on:
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
	var any := false
	if ask["fajta"] == "metan":
		var c := UI.card(UI.GREEN)
		c.add_child(UI.label(L.t("A metán rövid ideig marad a levegőben, de erősen melegít. Mutasd meg, hol lehet gyorsan csökkenteni!"), 16, UI.SOFT))
		for id in world.methane_cards(g):
			add_card.call(c, id)
			any = true
		if not any:
			c.add_child(UI.label(L.t("Ehhez metánról szóló kártya kell (Olaj és gáz, Élelem, Áram)."), 15, UI.MUTE))
		area.add_child(UI.card_root(c))
	else:
		area.add_child(UI.label(L.t("Amitől tartanak:"), 17, UI.GOLD, true, false))
		var usable := world.usable(g)
		for th in g["felelmek"]:
			var c := UI.card(_theme_color(th))
			c.add_child(UI.label(("“%s”" if L.is_en() else "„%s”") % L.t(WORRY[th]), 17, UI.TEXT))
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
		if ask["fajta"] == "metan":
			done = world.pledge_methane(g, picked[0])
		else:
			done = world.negotiate(g, int(ask["cel"]), picked)
		if done:
			_refresh()
			_sound("jel_jo")
			_agreed(g, ask))


func _agreed(g: Dictionary, ask: Dictionary) -> void:
	var body := _open(L.t("Megegyeztetek!"), UI.GREEN)
	var txt: String = (L.t("%s vállalta: nulla kibocsátás %d-re.") % [L.field(g, "nev"), int(ask["cel"])]) if ask["fajta"] == "cel" \
		else (L.t("%s vállalta: 30%%-kal kevesebb metán tíz év alatt.") % L.field(g, "nev"))
	body.add_child(UI.label(txt, 22, UI.TEXT, true))
	var fc := world.forecast()
	body.add_child(UI.label(L.t("2100-ban: +%s és +%s °C között") % [L.num(float(fc["also"][-1][1]), 1), L.num(float(fc["felso"][-1][1]), 1)], 19, UI.EMBER))
	body.add_child(UI.label(L.t("A sáv azért széles, mert nem tudjuk pontosan, mennyire érzékeny a Föld."), 15, UI.MUTE))
	body.add_child(_go(L.t("Rendben"), _close))


# --- CO2-kivonás --------------------------------------------------------------
func _open_cdr() -> void:
	var body := _open(L.t("CO2-kivonás"), UI.GREEN)
	body.add_child(UI.label(L.t("Ha megvan a kártyája, elindíthatod. Húsz év alatt fut fel, és óvatosan, a fenntartható sáv aljával számolunk."), 17, UI.SOFT))
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
	if _busy or _overlay != null or world.over():
		return
	_busy = true
	var t0 := float(world.st["T"])
	var y0 := world.year()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(globe, "spin", globe.spin + 1.0, 0.2 if _test else 1.6)
	await tw.finished
	world.advance()
	_offers = {}
	_busy = false
	_refresh()
	var bad: bool = world.news.any(func(n: Dictionary) -> bool: return n["fajta"] in ["billenes", "visszalepett"])
	_sound("zaro" if world.over() else ("jel_rossz" if bad else "jel_evtized"))
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
				c2.add_child(UI.label(L.t("%s megingott: a célját %d-re tolta.") % [L.field(world.group(n["csoport"]), "nev"), int(n["cel"])], 18, UI.GOLD, true))
				c2.add_child(UI.label(L.t("Nem volt a kezedben új bizonyíték, ami megtartotta volna őket."), 16, UI.SOFT))
				body.add_child(UI.card_root(c2))
			"kitartott":
				var c3 := UI.card(UI.GREEN)
				c3.add_child(UI.label(L.t("%s megingott, de kitartott.") % L.field(world.group(n["csoport"]), "nev"), 18, UI.GREEN, true))
				c3.add_child(UI.label(L.t("A bizonyítékod tartotta meg őket: %s") % Cards.text(n["kartya"], "Kérdés", L.is_en()), 16, UI.SOFT))
				body.add_child(UI.card_root(c3))
			"katasztrofa":
				var c4 := UI.card(UI.EMBER)
				c4.add_child(UI.label("%s: %s" % [L.t(DISASTER[n["mi"]]), L.field(world.group(n["csoport"]), "nev")], 18, UI.EMBER, true))
				c4.add_child(UI.label(L.t("A baj után jobban figyelnek rád: most eggyel kevesebb kártya kell náluk."), 16, UI.SOFT))
				body.add_child(UI.card_root(c4))
	if world.news.is_empty():
		body.add_child(UI.label(L.t("Csendes öt év volt."), 17, UI.SOFT))
	body.add_child(UI.label(L.t("A jövő hírei a játék részei, nem valódi események."), 13, UI.MUTE))
	if world.over():
		body.add_child(_go(L.t("Lássuk, mi lett a Földdel") + " →", _open_end))
	else:
		body.add_child(_go(L.t("Tovább"), _close))


func _open_end() -> void:
	var r := world.result()
	var body := _open(L.t("2100: a te Földed"), UI.CYAN)
	var row := UI.hbox(24)
	body.add_child(row)
	for side in [[L.t("A te Földed"), r["T"], r["tenger"], UI.GREEN, 1.0], [L.t("Ha semmi sem változik"), r["alap"], r["tenger_alap"], UI.EMBER, 0.0]]:
		var v := UI.vbox(4)
		v.custom_minimum_size = Vector2(410, 0)
		var gl = Globe.new()
		gl.custom_minimum_size = Vector2(330, 330)
		gl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		gl.heat = clampf((float(side[1]) - M.T_START) / 2.0, 0.0, 1.5)
		var ratio := world.net_ratio(2100) if side[4] > 0.5 else 1.0
		gl.set_plan_look({"smog": clampf(ratio, 0.0, 1.0), "clean": clampf(1.0 - ratio, 0.0, 1.0), "regrow": clampf(-ratio / 0.25, 0.0, 1.0)})
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gl.fixed_sun = true
		gl.pixels = 240.0
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
	var verdict := "A Földed a +1,5 °C közelében maradt. Ennél jobbat a mai tudásunk szerint alig lehet elérni." if tt < 1.6 \
		else ("A Földed +2 °C alatt maradt: ez a Párizsi Megállapodás fő célja." if tt < 2.0 \
		else "A Földed +2 °C fölé melegedett. A következő játékban lépj hamarabb!")
	body.add_child(UI.label(L.t(verdict), 19, UI.GREEN if tt < 2.0 else UI.EMBER, true))
	body.add_child(UI.label(L.t("A legmelegebb év: +%s °C. Küszöbét átlépő rendszer: %d a %d-ből.") % [L.num(float(r["csucs"]), 2), int(r["billenes"]), world.tips.size()], 17, UI.TEXT))
	var s := float(r["sens"])
	var kind := L.t("átlagos") if absf(s) < 0.25 else (L.t("az átlagnál érzékenyebb") if s > 0 else L.t("az átlagnál kevésbé érzékeny"))
	body.add_child(UI.label(L.t("Ez a Föld %s volt. Ezt előre senki sem tudhatta, ahogy a valódi Földnél sem tudjuk pontosan.") % kind, 16, UI.SOFT))
	body.add_child(UI.label(L.t("A hőmérsékletet egyszerű klímamodell számolta. Irányt és nagyságrendet mutat, nem előrejelzés."), 14, UI.MUTE))
	body.add_child(_go(L.t("Új játék, új Föld") + " →", _new_game))


func _open_help() -> void:
	var body := _open(L.t("Hogyan játssz?"), UI.CYAN)
	for row in [
			["1.", "Te vagy a világ klímatudósa. 2026-ból indulsz, egy kör öt év, 2100-ig tizenöt köröd van."],
			["2.", "Körönként három lépésed van. Kutass: minden kutatás egy bizonyíték-kártyát ad valódi tudományos forrásokkal."],
			["3.", "Kattints egy országcsoportra, és győzd meg a kártyáiddal. Mindenki mástól tart, ezért más kártya kell neki."],
			["4.", "Ha elfogytak a lépéseid, jön a következő öt év. A Föld és a görbe megmutatja, mit értél el."],
			["5.", "A cél: 2100-ban +2 °C alatt maradni, és minél közelebb a +1,5 °C-hoz. Ez a Párizsi Megállapodás célja is."],
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
	world.negotiate(kina, 2070, world.usable(kina).slice(0, 1))
	_refresh()
	_agreed(kina, {"fajta": "cel", "cel": 2070})
	await _shot("9_megegyezes.png")
	_open_hand()
	await _shot("10_kartyaim.png")
	_open_cdr()
	await _shot("11_kivonas.png")
	_close()
	# a többi kör gyorsan: minden körben kutatás és ahol lehet, megegyezés
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
				var ths: Array = Cards.THEMES.keys()
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
	_open_end()
	await _shot("14_vege.png")
	print("ONTESZT kész: T2100=%.2f alap=%.2f" % [world.result()["T"], world.result()["alap"]])
	get_tree().quit()
