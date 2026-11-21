extends Control
## AETHER – főképernyő, 1. mérföldkő: egy teljes kutatási kör.
##   valós mai Föld -> kutatás -> jóváhagyás -> terv -> modell -> hatás a földgömbön
## A felületet kódból építi fel, hogy a jelenet-fájl egyszerű maradjon.

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")
const Globe := preload("res://scripts/globe.gd")
const ResearchFlow := preload("res://scripts/research_flow.gd")
const PlanPanel := preload("res://scripts/plan_panel.gd")
const EventPanel := preload("res://scripts/event_panel.gd")

const MISSION := [
	["Nézd meg a mai Földet", "A bal oldali lista és a földgömb pöttyei valódi, friss jelentések. Kattints egyre!"],
	["Kutass!", "Nyomd meg lent a „Kutatás” gombot, és válassz egy kérdést."],
	["Nézd meg, mit találtál", "A játék csak azt fogadja el, ami szó szerint benne van a cikkekben."],
	["Készítsd el a terved", "Nyomd meg „A terved” gombot, állítsd be a csúszkákat, és nézd meg, mi lesz 2100-ban."],
]

var globe                     # globe.gd példány
var bridge                    # lab_bridge.gd példány
var world: Dictionary = {}
var model: Dictionary = {}
var mission_step := 0

var _events_box: VBoxContainer
var _world_note: Label
var _refresh_btn: Button
var _mission_box: VBoxContainer
var _stats: Dictionary = {}   # név -> érték-címke
var _info: Label
var _info_link: LinkButton
var _info_url := ""
var _year_row: HBoxContainer
var _year_slider: HSlider
var _year_label: Label
var _overlay: Control
var _dim: ColorRect
var _plan                     # plan_panel.gd példány (megmarad a jóváhagyott karokkal)


func _ready() -> void:
	L.init()
	UI.load_fonts()
	theme = _make_theme()
	var bg := TextureRect.new()
	bg.texture = load("res://assets/nebula_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(bg)

	bridge = Bridge.new()
	add_child(bridge)
	bridge.finished.connect(_on_bridge_finished)

	globe = Globe.new()
	globe.position = Vector2(440, 74)
	globe.size = Vector2(720, 720)
	globe.stations = [{"name": L.t("Te · Budapest"), "lat": 47.5, "lon": 19.0, "color": UI.GOLD, "me": true}]
	globe.station_clicked.connect(_on_station)
	globe.event_clicked.connect(_show_event)
	add_child(globe)

	_build_top_bar()
	_build_left_panel()
	_build_right_panel()
	_build_bottom_bar()

	_plan = PlanPanel.new()
	_plan.bridge = bridge
	_plan.closed.connect(_close_overlay)
	_plan.model_ready.connect(_on_model)

	_load_world_cache()
	if "--onteszt" in OS.get_cmdline_user_args():
		_selftest()
	elif world.is_empty():
		_refresh_world()


# ---------------------------------------------------------------------------
# Téma
# ---------------------------------------------------------------------------
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UI.font_body
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = UI.PANEL_BG
	panel.border_color = UI.EDGE
	panel.set_border_width_all(2)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = Color("#1c2944") if state != "hover" else Color("#26385c")
		b.border_color = Color("#4a6391") if state != "focus" else UI.GOLD
		b.set_border_width_all(2)
		b.set_content_margin_all(10)
		b.content_margin_left = 16
		b.content_margin_right = 16
		t.set_stylebox(state, "Button", b)
	t.set_font("font", "Button", UI.font_bold)
	t.set_font_size("font_size", "Button", 17)
	t.set_font("font", "CheckBox", UI.font_body)
	t.set_color("font_color", "Label", UI.TEXT)
	return t


func _panel(pos: Vector2, width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size = Vector2(width, 0)
	add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	return v


func _stat(parent: Control, key: String, caption: String, value: String, color: Color, link: String = "") -> void:
	var v := UI.vbox(0)
	v.add_child(UI.label(caption, 14, UI.MUTE, false, false))
	var l := UI.label(value, 21, color, true, false)
	v.add_child(l)
	if link != "":
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		l.tooltip_text = L.t("Forrás: Forster és mtsai 2025 (kattints a megnyitáshoz)")
		var open_fn := func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				OS.shell_open(link)
		l.gui_input.connect(open_fn)
	_stats[key] = l
	parent.add_child(v)


## F11: teljes képernyő be/ki. (A felület 1600×900-as tervből bármekkora
## kijelzőre élesen felnagyul, a betűk a valódi felbontáson rajzolódnak.)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------------------
# Felület
# ---------------------------------------------------------------------------
func _build_top_bar() -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(1600, 70)
	add_child(p)
	var h := UI.hbox(34)
	p.add_child(h)
	var logo := UI.label("AETHER", 32, UI.CYAN, false, false)
	logo.add_theme_font_override("font", UI.font_pixel)
	h.add_child(logo)
	var d := Time.get_date_dict_from_system()
	_stat(h, "ma", L.t("Ma"), ("%d-%02d-%02d" if L.is_en() else "%d. %02d. %02d.") % [d["year"], d["month"], d["day"]], UI.TEXT)
	_stat(h, "melegedes", L.t("Ember okozta melegedés (2024)"), "+%s °C" % L.num(1.36, 2), UI.EMBER, "https://doi.org/10.5194/essd-17-2641-2025")
	_stat(h, "co2", L.t("CO2 a levegőben"), L.t("letöltés…"), UI.GOLD)
	_stat(h, "jeg", L.t("Északi-sarki tengeri jég"), L.t("letöltés…"), Color("#a9dcea"))
	_stat(h, "jovo", L.t("A terved szerint"), L.t("még nincs terv"), UI.CYAN)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	# Nyelvváltó: a másik nyelvre vált, elmenti, és újraépíti a képernyőt.
	var lang_btn := UI.button("EN" if not L.is_en() else "HU")
	lang_btn.tooltip_text = "Switch to English" if not L.is_en() else "Váltás magyarra"
	lang_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lang_fn := func() -> void:
		L.set_lang("hu" if L.is_en() else "en")
		get_tree().reload_current_scene()
	lang_btn.pressed.connect(lang_fn)
	h.add_child(lang_btn)


func _build_left_panel() -> void:
	var v := _panel(Vector2(18, 90), 400)
	v.add_child(UI.heading(L.t("Mi történik most?"), 24))
	_world_note = UI.label(L.t("Valós jelentések betöltése…"), 14, UI.MUTE)
	v.add_child(_world_note)
	# A kártyák görgethető, rögzített magasságú dobozban vannak, így a frissítés
	# gomb mindig a képernyőn marad (az alsó sáv fölött).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_events_box = UI.vbox(8)
	_events_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_events_box)
	_refresh_btn = UI.button(L.t("Frissítés valós adatokkal"))
	_refresh_btn.pressed.connect(_refresh_world)
	v.add_child(_refresh_btn)


func _build_right_panel() -> void:
	var v := _panel(Vector2(1212, 90), 370)
	v.add_child(UI.heading(L.t("Első küldetés"), 24))
	_mission_box = UI.vbox(8)
	v.add_child(_mission_box)
	_render_mission()


func _build_bottom_bar() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(18, 772)
	p.custom_minimum_size = Vector2(1564, 112)
	add_child(p)
	var h := UI.hbox(16)
	p.add_child(h)
	var research := UI.button(L.t("Kutatás"), true)
	research.custom_minimum_size = Vector2(150, 0)
	research.pressed.connect(_open_research)
	h.add_child(research)
	var plan := UI.button(L.t("A terved"))
	plan.custom_minimum_size = Vector2(150, 0)
	plan.pressed.connect(_open_plan)
	h.add_child(plan)
	var info_box := UI.vbox(2)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info = UI.label(L.t("Üdv az AETHER-ben! Kezdd a jobb oldali küldetéssel."), 16, UI.SOFT)
	info_box.add_child(_info)
	_info_link = LinkButton.new()
	_info_link.text = L.t("Forrás megnyitása")
	_info_link.add_theme_color_override("font_color", UI.CYAN)
	_info_link.visible = false
	_info_link.pressed.connect(_open_info_link)
	info_box.add_child(_info_link)
	_year_row = UI.hbox(12)
	_year_row.visible = false
	_year_row.add_child(UI.label(L.t("Év:"), 16, UI.MUTE, false, false))
	_year_slider = HSlider.new()
	_year_slider.min_value = 2025
	_year_slider.max_value = 2100
	_year_slider.step = 1
	_year_slider.value = 2026
	_year_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_year_slider.value_changed.connect(_on_year)
	_year_row.add_child(_year_slider)
	_year_label = UI.label("", 17, UI.GOLD, true, false)
	_year_label.custom_minimum_size = Vector2(150, 0)
	_year_row.add_child(_year_label)
	info_box.add_child(_year_row)
	h.add_child(info_box)


func _show_info(text: String, link: String) -> void:
	_info.text = text
	_info_url = link
	_info_link.visible = link != ""


func _open_info_link() -> void:
	if _info_url != "":
		OS.shell_open(_info_url)


func _on_station(s: Dictionary) -> void:
	_show_info(L.t("A te kutatóállomásod: ") + str(s["name"]), "")


# ---------------------------------------------------------------------------
# Küldetés
# ---------------------------------------------------------------------------
func _render_mission() -> void:
	UI.clear(_mission_box)
	for i in MISSION.size():
		var done := i < mission_step
		var current := i == mission_step
		var mark := "✓" if done else ("●" if current else "○")
		var col: Color = UI.GREEN if done else (UI.GOLD if current else UI.MUTE)
		_mission_box.add_child(UI.label("%s  %d. %s" % [mark, i + 1, L.t(MISSION[i][0])], 18, col, current))
		if current:
			_mission_box.add_child(UI.label(L.t(MISSION[i][1]), 15, UI.SOFT))
	if mission_step >= MISSION.size():
		_mission_box.add_child(UI.label(L.t("Kész! Húzd az év-csúszkát lent, és nézd, hogyan változik a Föld. Próbálj ki egy új kutatást vagy egy másik tervet!"), 15, UI.GREEN))


func _advance(to_step: int) -> void:
	if to_step > mission_step:
		mission_step = to_step
		_render_mission()


# ---------------------------------------------------------------------------
# Valós mai Föld (world_state.py)
# ---------------------------------------------------------------------------
func _world_path() -> String:
	return str(bridge.work_dir("aether_vilag")).path_join("vilag.json")


func _load_world_cache() -> void:
	var w: Variant = Bridge.read_json(_world_path())
	if typeof(w) == TYPE_DICTIONARY:
		world = w
		_render_world()


func _refresh_world() -> void:
	if bridge.run("vilag", ["vilag", "--ki", _world_path()]):
		_refresh_btn.disabled = true
		_refresh_btn.text = L.t("Letöltés folyamatban…")
		_world_note.text = L.t("Valós jelentések letöltése (GDACS, ReliefWeb, NASA, NOAA, NSIDC)…")


func _render_world() -> void:
	UI.clear(_events_box)
	var events: Array = world.get("esemenyek", [])
	globe.events = events
	var srcs: Dictionary = world.get("forrasok", {})
	var ok := 0
	for k in srcs:
		if srcs[k].get("ok", false):
			ok += 1
	var when := str(world.get("letoltve", "")).replace("T", " ").left(16)
	_world_note.text = L.t("Valós jelentések, letöltve: %s (UTC). %d/%d forrás elérhető.") % [when, ok, srcs.size()]
	if events.is_empty():
		_events_box.add_child(UI.label(L.t("Most nem sikerült valós jelentést letölteni. Van internet? A játék nem pótolja kitalált adattal."), 16, UI.SOFT))
	for e in _pick_events(events, 4):
		_events_box.add_child(_event_card(e))
	for m in world.get("meresek", []):
		var key := ""
		var txt := ""
		if m.get("azonosito") == "co2_ppm":
			key = "co2"
			txt = "%s ppm" % UI.hu(float(m["ertek"]), 1)
		elif m.get("azonosito") == "arktisz_jeg":
			key = "jeg"
			txt = L.t("%s millió km²") % UI.hu(float(m["ertek"]), 2)
			if m.get("elteres_pct") != null:
				txt += " (%s%%)" % UI.hu(float(m["elteres_pct"]), 0)
		elif m.get("azonosito") == "levego_varosok":
			var air_title := L.field(m, "magyarazat")
			if m.get("ertek") != null and m.get("legrosszabb") != null and m.get("legrosszabb_pm2_5") != null:
				var total := str(m.get("egyseg", "")).replace("/", "").replace("város", "").strip_edges()
				air_title = L.t("%d/%s városban túl sok a finom por (WHO-határ felett). Legrosszabb: %s, %s µg/m³") % [
					int(m["ertek"]), total, L.field(m, "legrosszabb"), UI.hu(float(m["legrosszabb_pm2_5"]), 1)]
			_events_box.add_child(_event_card({"kategoria": "levego",
				"cim": air_title, "datum": str(m.get("datum", "")).left(10),
				"forras": str(m.get("forras", "")), "link": str(m.get("link", "")), "orszag": ""}))
		if key != "":
			var l: Label = _stats[key]
			l.text = txt
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			l.tooltip_text = "%s, %s. %s" % [str(m.get("forras", "")), str(m.get("datum", "")), L.field(m, "magyarazat")]
	for key in ["co2", "jeg"]:
		var l: Label = _stats[key]
		if l.text == L.t("letöltés…"):
			l.text = L.t("nem elérhető")


## Változatos válogatás a listához: előbb országhoz kötött, különböző típusú
## jelentések, aztán más típusok, végül a legfrissebbek.
func _pick_events(events: Array, n: int) -> Array:
	var picked: Array = []
	var cats := {}
	for pass_i in 3:
		for e in events:
			if picked.size() >= n:
				return picked
			if picked.has(e):
				continue
			var cat := str(e.get("kategoria", ""))
			if pass_i == 0 and (str(e.get("orszag", "")) == "" or cats.has(cat)):
				continue
			if pass_i == 1 and cats.has(cat):
				continue
			cats[cat] = true
			picked.append(e)
	return picked


func _event_card(e: Dictionary) -> Control:
	var accent: Color = Globe.EVENT_COLORS.get(str(e.get("kategoria", "")), UI.EDGE)
	var row := UI.card(accent)
	var place := EventPanel.short_place(e)
	row.add_child(UI.label(L.category(str(e.get("kategoria", ""))) + (" · " + place if place != "" else ""), 14, UI.MUTE, false))
	var t := UI.label(EventPanel.display_title(e), 16, UI.TEXT, true)
	t.max_lines_visible = 3
	row.add_child(t)
	row.add_child(UI.label("%s · %s" % [str(e.get("datum", "")), L.field(e, "forras")], 13, UI.MUTE, false))
	var root := UI.card_root(row)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var click_fn := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_event(e)
	root.gui_input.connect(click_fn)
	return root


func _show_event(e: Dictionary) -> void:
	# Röviden lent, részletesen (összefoglaló, ábrák, forráslink) külön ablakban.
	var place := EventPanel.short_place(e)
	_show_info("%s%s (%s). %s" % [EventPanel.display_title(e), (" · " + place) if place != "" else "",
		str(e.get("datum", "")), L.t("A részletek a megnyílt ablakban.")], "")
	var p = EventPanel.new()
	p.bridge = bridge
	p.event = e
	p.closed.connect(_close_overlay)
	_place_overlay(p)
	_advance(1)


# ---------------------------------------------------------------------------
# Kutatás és terv
# ---------------------------------------------------------------------------
func _close_overlay() -> void:
	if _overlay != null:
		remove_child(_overlay)
		if _overlay != _plan:
			_overlay.queue_free()
		_overlay = null
	if _dim != null:
		_dim.queue_free()
		_dim = null


## A megnyitott ablak mögött elsötétített háttér: így az ablak jól kiemelkedik.
## A sötét részre kattintva az ablak bezárul.
func _place_overlay(c: Control) -> void:
	_close_overlay()
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.02, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.z_index = 10
	var dim_fn := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_overlay()
	_dim.gui_input.connect(dim_fn)
	add_child(_dim)
	c.position = Vector2(340, 84)
	c.custom_minimum_size = Vector2(920, 680)
	c.size = Vector2(920, 680)
	c.z_index = 11
	_overlay = c
	add_child(c)


func _open_research() -> void:
	var r = ResearchFlow.new()
	r.bridge = bridge
	r.closed.connect(_close_overlay)
	r.results_shown.connect(_on_results_shown)
	r.approved.connect(_on_approved)
	_place_overlay(r)
	_advance(1)


func _on_results_shown(_has_levers: bool) -> void:
	_advance(3)


func _on_approved(levers: Array) -> void:
	_plan.add_levers(levers)
	_show_info(L.t("%d kutatási eredményt beépítettél a tervedbe. Nyomd meg „A terved” gombot!") % levers.size(), "")
	_close_overlay()
	_advance(3)


func _open_plan() -> void:
	_place_overlay(_plan)


func _on_model(res: Dictionary) -> void:
	model = res
	_close_overlay()
	_year_row.visible = true
	_year_slider.value = 2050
	_on_year(2050)
	var k: Dictionary = res["osszegzes"]["kozep"]
	var l: Label = _stats["jovo"]
	l.text = "2100: +%s °C" % UI.hu(float(k["T2100"]), 1)
	_show_info(str(res["jelentes"]), "")
	_advance(4)


func _temp_at(year: int) -> float:
	var ys: Array = model.get("evek", [])
	# A JSON számok float-ként jönnek (2100.0), ezért int-ként hasonlítunk.
	for i in ys.size():
		if int(ys[i]) == year:
			return float(model["terv"]["kozep"]["homerseklet"][i])
	return 0.0


func _on_year(v: float) -> void:
	if model.is_empty():
		return
	var y := int(v)
	var t := _temp_at(y)
	var now := _temp_at(2026)
	_year_label.text = "%d: +%s °C" % [y, UI.hu(t, 1)]
	# csak szemléltetés: a mához képest +2 °C = teljes "hő" színezés
	globe.heat = clampf((t - now) / 2.0, 0.0, 1.0)


func _on_bridge_finished(tag: String, code: int, output: String) -> void:
	if tag != "vilag":
		return
	_refresh_btn.disabled = false
	_refresh_btn.text = L.t("Frissítés valós adatokkal")
	var w: Variant = Bridge.read_json(_world_path())
	if code == 0 and typeof(w) == TYPE_DICTIONARY:
		world = w
		_render_world()
	else:
		_world_note.text = L.t("A valós adatok letöltése nem sikerült. Telepítve van a Python 3.10+, és van internet?")
		print(output)


# ---------------------------------------------------------------------------
# Önteszt: végigjátssza a kört gépiesen, és képernyőképeket ment.
# Indítás: Godot --path <projekt> -- --onteszt
# (AI nélküli kutatással: valódi cikkeket keres, számot nem emel ki.)
# ---------------------------------------------------------------------------
func _wait_tag(tag: String) -> Array:
	while true:
		var args: Array = await bridge.finished
		if args[0] == tag:
			return args
	return []


func _shot(dir: String, name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name))
	print("ONTESZT kép: ", dir.path_join(name))


func _selftest() -> void:
	var dir: String = bridge.work_dir("aether_onteszt")
	print("ONTESZT indul, képek: ", dir)
	_refresh_world()
	var w := await _wait_tag("vilag")
	print("ONTESZT világ: kód=", w[1], " események=", world.get("esemenyek", []).size(), " források=", world.get("forrasok", {}))
	await _shot(dir, "1_mai_fold.png")
	if not world.get("esemenyek", []).is_empty():
		_show_event(world["esemenyek"][0])
	_open_research()
	var r = _overlay
	r._pick_question(ResearchFlow.QUESTIONS[0])
	await _wait_tag("ai")
	print("ONTESZT AI-állapot: ", r._ai_status)
	await _shot(dir, "2_ki_kutasson.png")
	r._ai = "none"
	r._start_research()
	var k := await _wait_tag("kutat")
	print("ONTESZT kutatás: kód=", k[1])
	await _shot(dir, "3_eredmeny.png")
	_close_overlay()
	_open_plan()
	_plan._run_model()
	var m := await _wait_tag("modell")
	print("ONTESZT modell: kód=", m[1])
	await _shot(dir, "4_terv.png")
	var res: Variant = Bridge.read_json(_plan._out_path)
	if typeof(res) == TYPE_DICTIONARY and not res.has("hiba"):
		_on_model(res)
		_year_slider.value = 2100
		await _shot(dir, "5_fold_2100.png")
	print("ONTESZT kész")
	get_tree().quit()
