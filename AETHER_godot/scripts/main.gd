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
const Missions := preload("res://scripts/missions.gd")
const Campaign := preload("res://scripts/campaign.gd")
const Knowledge := preload("res://scripts/knowledge.gd")
const StationPanel := preload("res://scripts/station_panel.gd")
const NalunkPanel := preload("res://scripts/nalunk_panel.gd")

const MISSION := [
	["Nézd meg a mai Földet", "A bal oldali lista és a földgömb pöttyei valódi, friss jelentések. Kattints egyre!"],
	["Kutass!", "Nyomd meg lent a „Kutatás” gombot, és válassz egy kérdést."],
	["Nézd meg, mit találtál", "A játék csak azt fogadja el, ami szó szerint benne van a cikkekben."],
	["Készítsd el a terved", "Nyomd meg „A terved” gombot, állítsd be a csúszkákat, és nézd meg, mi lesz 2100-ban."],
]

## Halkan pislákoló pixel-csillagok a háttér fölött (csak díszítés, nem takar semmit).
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


var globe                     # globe.gd példány
var bridge                    # lab_bridge.gd példány
var world: Dictionary = {}
var model: Dictionary = {}
var mission_step := 0          # a bevezető (első küldetés) lépése; 4 = kész
var mission_idx := 0           # az aktuális küldetés a Missions.LIST-ben
var _mission_note := ""        # az utolsó értékelés rövid szövege
var _mission_title: Label

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
var _close_x: Button                 # kerek X a megnyitott ablak sarkán
var _plan                     # plan_panel.gd példány (megmarad a jóváhagyott karokkal)
var campaign                  # campaign.gd: telő idő, pénz, bizalom
var _play_btn: Button
var _reset_btn: Button
var _base_retry: Timer
var _toasts := 0                      # egyszerre látható értesítések (egymás alá kerülnek)
var _year_bar: ProgressBar             # az év telése a felső sávban
var _month_label: Label
const MONTHS := ["jan.", "febr.", "márc.", "ápr.", "máj.", "jún.", "júl.", "aug.", "szept.", "okt.", "nov.", "dec."]
const MONTHS_EN := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


func _process(_delta: float) -> void:
	if _year_bar == null or campaign == null:
		return
	var per: float = Campaign.SECONDS_PER_YEAR[1 if campaign.fast else 0]
	var f: float = clampf(campaign._acc / per, 0.0, 1.0) if campaign.running else 0.0
	_year_bar.value = f
	_year_bar.modulate.a = 1.0 if campaign.running and not campaign.blocked else 0.35
	if campaign.running:
		var m := int(f * 12.0) % 12
		_month_label.text = (MONTHS_EN if L.is_en() else MONTHS)[m] + ("" if not campaign.blocked else "  ⏸")
	else:
		_month_label.text = ""


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
	var stars := Twinkle.new()
	stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stars)

	bridge = Bridge.new()
	add_child(bridge)
	bridge.finished.connect(_on_bridge_finished)
	campaign = Campaign.new()
	add_child(campaign)
	if "--onteszt" in OS.get_cmdline_user_args():   # az önteszt nem nyúl a játékos mentéséhez
		campaign.save_file = "aether_jatek_onteszt.json"
		campaign.new_game()
	campaign.load_game()
	campaign.year_passed.connect(_on_year_passed)
	campaign.changed.connect(_update_stats)
	campaign.game_over.connect(_on_game_over)
	campaign.era_reached.connect(_on_era_reached)

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
	_plan.campaign = campaign
	_plan.closed.connect(_close_overlay)
	_plan.model_ready.connect(_on_model)
	if bool(L.get_setting("bevezeto_kesz", false)):
		mission_step = MISSION.size()
		mission_idx = Missions.first_open()
		_plan.set_mission(Missions.LIST[mission_idx])
		_render_mission()

	_base_retry = Timer.new()
	_base_retry.wait_time = 2.0
	_base_retry.one_shot = true
	_base_retry.timeout.connect(_ensure_model)
	add_child(_base_retry)
	if not campaign.model.is_empty():
		model = campaign.model
		_year_row.visible = false
		_year_slider.value = campaign.year
	_update_stats()

	_load_world_cache()
	_ensure_model()
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
	# festett pixeles keretek (tools/festett_felulet.py), csempézve, hogy élesek maradjanak
	var panel := _frame("res://assets/ui/panel.png", 12, 18)
	t.set_stylebox("panel", "PanelContainer", panel)
	var imgs := {"normal": "gomb", "disabled": "gomb", "hover": "gomb_folotte", "pressed": "gomb_lenyomva"}
	for state in imgs:
		var b := _frame("res://assets/ui/%s.png" % imgs[state], 8, 10)
		b.content_margin_left = 16
		b.content_margin_right = 16
		t.set_stylebox(state, "Button", b)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = UI.GOLD
	focus.set_border_width_all(2)
	t.set_stylebox("focus", "Button", focus)
	t.set_font("font", "Button", UI.font_bold)
	t.set_font_size("font_size", "Button", 17)
	t.set_font("font", "CheckBox", UI.font_body)
	# A jelölőnégyzet és a kapcsológomb minden állapota ugyanazt a keretet és belső margót kapja,
	# különben egér alatt (bejelölve) a szöveg a négyzet alá csúszik.
	var cb_imgs := {"normal": "gomb", "pressed": "gomb", "disabled": "gomb", "hover": "gomb_folotte",
		"hover_pressed": "gomb_folotte"}
	for state in cb_imgs:
		var cbs := _frame("res://assets/ui/%s.png" % cb_imgs[state], 8, 10)
		cbs.content_margin_left = 16
		cbs.content_margin_right = 16
		t.set_stylebox(state, "CheckBox", cbs)
	t.set_stylebox("focus", "CheckBox", focus)
	t.set_constant("h_separation", "CheckBox", 10)
	var hp := _frame("res://assets/ui/gomb_lenyomva.png", 8, 10)
	hp.content_margin_left = 16
	hp.content_margin_right = 16
	t.set_stylebox("hover_pressed", "Button", hp)
	t.set_color("font_color", "Label", UI.TEXT)
	return t


func _frame(path: String, margin: int, content: int) -> StyleBox:
	var tex: Texture2D = load(path)
	if tex == null:   # ha a kép hiányzik, egyszerű keret
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _overlay != null:
		_request_close()
		return
	# Gyorsbillentyűk (csak ha nincs nyitott ablak, és nem egy szövegmezőbe gépelünk):
	# K kutatás, T terv, A állomás, N nálunk, szóköz idő indítása/szünet,
	# H a földgömb vissza a saját helyedre.
	if event is InputEventKey and event.pressed and not event.echo and _overlay == null \
			and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var handled := true
		match event.keycode:
			KEY_K: _open_research()
			KEY_T: _open_plan()
			KEY_A: _open_station()
			KEY_N: _open_nalunk()
			KEY_SPACE: _toggle_time()
			KEY_H: globe.home()
			KEY_F1: _open_help()
			_: handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
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
	var h := UI.hbox(26)
	p.add_child(h)
	var logo := UI.label("AETHER", 32, UI.CYAN, false, false)
	logo.add_theme_font_override("font", UI.font_pixel)
	h.add_child(logo)
	_stat(h, "ev", L.t("Év"), str(campaign.year), UI.TEXT)
	# telő idő: az év alatt egy vékony sáv töltődik, mellette a hónap – így látszik, hogy halad
	var ev_box: VBoxContainer = (_stats["ev"] as Label).get_parent()
	_year_bar = ProgressBar.new()
	_year_bar.show_percentage = false
	_year_bar.custom_minimum_size = Vector2(70, 5)
	_year_bar.max_value = 1.0
	_year_bar.step = 0.001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	var fg := StyleBoxFlat.new()
	fg.bg_color = UI.CYAN
	_year_bar.add_theme_stylebox_override("background", bg)
	_year_bar.add_theme_stylebox_override("fill", fg)
	_year_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var yrow := UI.hbox(6)
	yrow.add_child(_year_bar)
	_month_label = UI.label("", 11, UI.CYAN, false, false)
	_month_label.custom_minimum_size = Vector2(38, 0)
	yrow.add_child(_month_label)
	yrow.custom_minimum_size = Vector2(0, 0)
	ev_box.add_child(yrow)
	# az évszám és a sáv közötti hely ne nyújtsa meg a felső sávot
	ev_box.add_theme_constant_override("separation", -2)
	_stat(h, "korszak", L.t("Korszak"), Knowledge.era_name(campaign.era), UI.GOLD)
	(_stats["korszak"] as Label).mouse_filter = Control.MOUSE_FILTER_PASS
	(_stats["korszak"] as Label).tooltip_text = L.t("Tudásfa (játékszabály): a kutatott témák új korszakot, új témákat és új tervlehetőségeket nyitnak. Kutatás gomb.")
	_stat(h, "penz", L.t("Pénz"), str(campaign.money), UI.GOLD)
	_stat(h, "bizalom", L.t("Bizalom"), "%d%%" % campaign.trust, UI.GREEN)
	for k in ["penz", "bizalom"]:
		var sl: Label = _stats[k]
		sl.mouse_filter = Control.MOUSE_FILTER_PASS
		sl.tooltip_text = L.t("Játékszabály, nem valós adat. Pénz: kutatás és tervek bevezetése; évente kapsz. Bizalom: a gyors tervekhez kell; ellenőrzött kutatással és csökkenő kibocsátással nő.")
	_stat(h, "melegedes", L.t("Melegedés (modell)"), "+%s °C" % L.num(1.36, 2), UI.EMBER, "https://doi.org/10.5194/essd-17-2641-2025")
	_stat(h, "co2", L.t("CO2 a levegőben"), L.t("letöltés…"), UI.GOLD)
	_stat(h, "jeg", L.t("Északi-sarki tengeri jég"), L.t("letöltés…"), Color("#a9dcea"))
	_stat(h, "jovo", L.t("A terved szerint"), L.t("még nincs terv"), UI.CYAN)
	# egy kattintás: a korszakról a kutatáshoz (tudásfa), a tervről a tervhez
	_click_stat("korszak", _open_research)
	_click_stat("jovo", _open_plan)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	# Súgó: egy rövid lap a négy lépésről és a gyorsbillentyűkről (F1 is).
	var help_btn := UI.button("?")
	help_btn.tooltip_text = L.t("Hogyan játssz? (F1)")
	help_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.pressed.connect(_open_help)
	h.add_child(help_btn)
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
	scroll.add_child(UI.scroll_pad(_events_box, 16))
	_refresh_btn = UI.button(L.t("Frissítés valós adatokkal"))
	_refresh_btn.pressed.connect(_refresh_world)
	v.add_child(_refresh_btn)


func _build_right_panel() -> void:
	var v := _panel(Vector2(1212, 90), 370)
	_mission_title = UI.heading(L.t("Első küldetés"), 24)
	v.add_child(_mission_title)
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
	research.tooltip_text = L.t("Válassz kérdést, a válasz valódi cikkekből jön. Gyorsbillentyű: K")
	research.pressed.connect(_open_research)
	h.add_child(research)
	var plan := UI.button(L.t("A terved"))
	plan.custom_minimum_size = Vector2(150, 0)
	plan.tooltip_text = L.t("Állítsd be, mit tegyen a világ, és nézd meg, mi lesz 2100-ig. Gyorsbillentyű: T")
	plan.pressed.connect(_open_plan)
	h.add_child(plan)
	var station := UI.button(L.t("Állomás"))
	station.custom_minimum_size = Vector2(130, 0)
	station.tooltip_text = L.t("A kutatóállomásod: modulok építése és fejlesztése. Gyorsbillentyű: A")
	station.pressed.connect(_open_station)
	h.add_child(station)
	var home := UI.button(L.t("Nálunk"))
	home.custom_minimum_size = Vector2(120, 0)
	home.tooltip_text = L.t("Mit jelent a melegedés nálunk: forró napok és nyári eső, mért adatokból és a terved szerint. Gyorsbillentyű: N")
	home.pressed.connect(_open_nalunk)
	h.add_child(home)
	var tbox := UI.vbox(6)
	var trow := UI.hbox(6)
	_play_btn = UI.button(L.t("Idő indítása"))
	_play_btn.custom_minimum_size = Vector2(150, 0)
	_play_btn.tooltip_text = L.t("Az évek telnek. Ha egy ablak nyitva van, az idő áll. Gyorsbillentyű: szóköz")
	_play_btn.pressed.connect(_toggle_time)
	trow.add_child(_play_btn)
	tbox.add_child(trow)
	# Az idő csak indítható és megállítható (nincs gyorsítás és évugrás).
	campaign.fast = false
	var trow2 := UI.hbox(6)
	_reset_btn = UI.button(L.t("Új játék"))
	_reset_btn.custom_minimum_size = Vector2(150, 0)
	_reset_btn.tooltip_text = L.t("Elölről kezdi 2026-tól. A küldetések csillagai megmaradnak.")
	_reset_btn.pressed.connect(_reset_game)
	trow2.add_child(_reset_btn)
	tbox.add_child(trow2)
	h.add_child(tbox)
	# A gombok ne tartsák meg a fókuszt: így a szóköz az időt indítja, nem az utoljára nyomott gombot.
	for b in [research, plan, station, home, _play_btn, _reset_btn]:
		(b as Button).focus_mode = Control.FOCUS_NONE
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
	# Az évcsúszka nem kerül a képernyőre (összezavart): csak belül követi az évet, hogy a
	# földgömb melegedés-színezése a mostani évhez igazodjon. Az évet a felső sáv mutatja.
	add_child(_year_row)
	_year_row.visible = false
	h.add_child(info_box)


func _show_info(text: String, link: String) -> void:
	_info.text = text
	_info_url = link
	_info_link.visible = link != ""


func _open_info_link() -> void:
	if _info_url != "":
		OS.shell_open(_info_url)


func _on_station(s: Dictionary) -> void:
	if bool(s.get("me", false)):
		_open_station()
	else:
		_show_info(L.t("Kutatóállomás: ") + str(s["name"]), "")


## Rövid súgó: mit csinálj (4 lépés), és mely billentyűkkel megy gyorsan. Kevés szöveg.
func _open_help() -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.CYAN
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 28
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(UI.scroll_pad(v))
	v.add_child(UI.heading(L.t("Hogyan játssz?")))
	var steps := [
		[L.t("1. Nézz körül"), L.t("A bal oldali lista és a földgömb pöttyei valódi, mai jelentések.")],
		[L.t("2. Kutass"), L.t("Válassz kérdést: a válasz valódi tudományos cikkekből jön.")],
		[L.t("3. Tervezz"), L.t("A kutatott megoldásokat tedd a tervedbe, és nézd meg, mi lesz 2100-ig.")],
		[L.t("4. Indítsd az időt"), L.t("Telnek az évek, nő a pénz és a bizalom. Fejleszd az állomásod.")],
	]
	for st in steps:
		var c := UI.card(UI.GOLD)
		c.add_child(UI.label(st[0], 18, UI.TEXT, true))
		c.add_child(UI.label(st[1], 15, UI.SOFT))
		v.add_child(UI.card_root(c))
	v.add_child(UI.label(L.t("Gyorsbillentyűk"), 18, UI.CYAN, true))
	var keys := [["K", L.t("Kutatás")], ["T", L.t("A terved")], ["A", L.t("Állomás")], ["N", L.t("Nálunk")],
		[L.t("Szóköz"), L.t("idő indítása / szünet")], ["H", L.t("földgömb: vissza a helyedre")],
		["Esc", L.t("ablak bezárása")], ["F11", L.t("teljes képernyő")]]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for k in keys:
		grid.add_child(UI.label(k[0], 16, UI.GOLD, true, false))
		grid.add_child(UI.label(k[1], 16, UI.TEXT, false, false))
	v.add_child(grid)
	v.add_child(UI.label(L.t("A földgömb egérrel forgatható, görgővel nagyítható; dupla kattintás: vissza a helyedre."), 14, UI.MUTE))
	_place_overlay(p)


func _open_nalunk() -> void:
	var n = NalunkPanel.new()
	n.bridge = bridge
	n.campaign = campaign
	n.closed.connect(_close_overlay)
	_place_overlay(n)


func _open_station() -> void:
	var st = StationPanel.new()
	st.campaign = campaign
	st.closed.connect(_close_overlay)
	var built_fn := func(note: String) -> void:
		_show_info(note, "")
		_toast(note, UI.CYAN)
	st.built.connect(built_fn)
	_place_overlay(st)


# ---------------------------------------------------------------------------
# Küldetés
# ---------------------------------------------------------------------------
func _render_mission() -> void:
	UI.clear(_mission_box)
	if mission_step >= MISSION.size():
		_render_missions()
		return
	for i in MISSION.size():
		var done := i < mission_step
		var current := i == mission_step
		var mark := "✓" if done else ("●" if current else "○")
		var col: Color = UI.GREEN if done else (UI.GOLD if current else UI.MUTE)
		_mission_box.add_child(UI.label("%s  %d. %s" % [mark, i + 1, L.t(MISSION[i][0])], 18, col, current))
		if current:
			_mission_box.add_child(UI.label(L.t(MISSION[i][1]), 15, UI.SOFT))
			# egy kattintással oda, ahol a lépést el kell végezni
			if i == 1:
				_mission_box.add_child(_go_button(L.t("Kutatás →"), _open_research))
			elif i == 3:
				_mission_box.add_child(_go_button(L.t("A terved →"), _open_plan))


## A bevezető után: küldetéslista csillagokkal; az aktuálisnál a cél és az utolsó eredmény.
func _render_missions() -> void:
	_mission_title.text = L.t("Küldetések")
	for i in Missions.LIST.size():
		var m: Dictionary = Missions.LIST[i]
		var st := Missions.stars_of(m["id"])
		var of := 1 if m["id"] == "alkalmazkodas" else 3
		var current := i == mission_idx
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s  %s" % [Missions.star_text(st, of), L.t(m["cim"])]
		b.add_theme_font_size_override("font_size", 17)
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(s, UI.GOLD if current else (UI.GREEN if st > 0 else UI.SOFT))
		b.pressed.connect(_select_mission.bind(i))
		_mission_box.add_child(b)
		if current:
			_mission_box.add_child(UI.label(L.t(m["cel"]), 15, UI.TEXT))
			if _mission_note != "":
				_mission_box.add_child(UI.label(_mission_note, 15, UI.CYAN))
			# az aszálytűrő kukoricához előbb kutatni kell; a többi küldetés a tervben dől el
			# a mentett játék karjai a campaign-ben vannak (a tervablak csak megnyitáskor tölti be őket)
			var has_lever: bool = campaign.levers.has("alkalmazkodas") or (_plan != null and _plan.levers.has("alkalmazkodas"))
			var need_research: bool = m["id"] == "alkalmazkodas" and not has_lever
			if need_research:
				_mission_box.add_child(_go_button(L.t("Kutatás →"), _open_research))
			else:
				_mission_box.add_child(_go_button(L.t("A terved →"), _open_plan))


## Kis „ugrás” gomb a küldetés alatt: egy kattintással a következő teendőhöz visz.
func _go_button(text: String, fn: Callable) -> Button:
	var b := UI.button(text, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	_pulse(b)
	return b


## Finom, ismétlődő felvillanás: ez a következő teendő. Magától leáll, ha az elem eltűnik.
func _pulse(c: CanvasItem) -> void:
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "modulate", Color(1.35, 1.35, 1.35), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)


func _select_mission(i: int) -> void:
	mission_idx = i
	_mission_note = ""
	_plan.set_mission(Missions.LIST[i])
	_render_mission()


func _advance(to_step: int) -> void:
	if to_step > mission_step:
		mission_step = to_step
		_render_mission()


## A bevezető vége: a következő modellfuttatástól a küldetések számítanak.
func _start_missions() -> void:
	L.set_setting("bevezeto_kesz", true)
	_mission_note = L.t("Első küldetés kész! Jöhet a következő.")
	mission_idx = Missions.first_open()
	_plan.set_mission(Missions.LIST[mission_idx])
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
		_world_note.text = L.t("Valós jelentések letöltése…")
	else:   # épp más fut (pl. a modell): kicsit később újra
		get_tree().create_timer(2.0).timeout.connect(_refresh_world)


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
	# röviden; a részletek rámutatásra
	_world_note.text = L.t("Friss: %s · %d/%d forrás") % [when, ok, srcs.size()]
	_world_note.mouse_filter = Control.MOUSE_FILTER_PASS
	_world_note.tooltip_text = L.t("Valós jelentések, letöltve: %s (UTC). %d/%d forrás elérhető.") % [when, ok, srcs.size()]
	if events.is_empty():
		_events_box.add_child(UI.label(L.t("Nem sikerült jelentést letölteni. Van internet?"), 16, UI.SOFT))
	for e in _pick_events(events, 4):
		_events_box.add_child(_event_card(e))
	# az első lépésnél az első kártya finoman lüktet: ide kell kattintani
	if mission_step == 0 and _events_box.get_child_count() > 0:
		_pulse(_events_box.get_child(0))
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
	# rámutatáskor a földgömb megmutatja, hol történt (és odafordul)
	var enter_fn := func() -> void:
		globe.highlight = e
		globe.look_at_event(e)
	var exit_fn := func() -> void:
		if globe.highlight == e:
			globe.highlight = {}
	root.mouse_entered.connect(enter_fn)
	root.mouse_exited.connect(exit_fn)
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
	if campaign != null:
		campaign.blocked = false
	if _close_x != null:
		_close_x.queue_free()
		_close_x = null
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
	campaign.blocked = true
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
	# Kerek X a keret jobb felső sarkán: görgetéstől függetlenül mindig látszik.
	_close_x = Button.new()
	_close_x.text = "X"
	_close_x.tooltip_text = L.t("Bezárás")
	_close_x.focus_mode = Control.FOCUS_NONE
	_close_x.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_x.add_theme_font_override("font", UI.font_bold)
	_close_x.add_theme_font_size_override("font_size", 22)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		_close_x.add_theme_color_override(st, Color.WHITE)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#8a2b2b") if st.begins_with("hover") or st == "pressed" else Color("#1a2238")
		sb.border_color = UI.CYAN
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(22)
		_close_x.add_theme_stylebox_override(st, sb)
	_close_x.size = Vector2(44, 44)
	_close_x.custom_minimum_size = Vector2(44, 44)
	_close_x.position = c.position + Vector2(c.size.x - 22, -22)
	_close_x.z_index = 12
	_close_x.pressed.connect(_request_close)
	add_child(_close_x)
	# Ha az ablak a saját méretét állítja (pl. az állomás szélesebb), az X kövesse a sarkot.
	c.resized.connect(_place_close_x)
	_place_close_x.call_deferred()


func _place_close_x() -> void:
	if _close_x != null and _overlay != null:
		_close_x.position = _overlay.position + Vector2(_overlay.size.x - 22, -22)


## Rövid, magától eltűnő értesítés a felső sáv alatt (pl. új korszak, kész modul, csillag).
func _toast(text: String, color: Color = UI.GOLD) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#101a2c")
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 12
	p.add_theme_stylebox_override("panel", sb)
	var l := UI.label(text, 19, color, true, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.z_index = 30
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	# nyitott ablaknál a (sötétített) felső sávba kerül, hogy ne takarja az ablak címét
	var top := 84.0 if _overlay == null else 8.0
	p.position = Vector2((1600 - p.size.x) / 2.0, top + 58 * _toasts)
	_toasts += 1
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
	tw.tween_callback(func() -> void: _toasts = maxi(0, _toasts - 1))


## Az X és az Esc: az ablak saját bezárását hívja (pl. a kutatás leállítja a figyelést).
func _request_close() -> void:
	if _overlay == null:
		return
	if _overlay.has_method("_close"):
		_overlay._close()
	elif _overlay.has_signal("closed"):
		_overlay.emit_signal("closed")
	else:
		_close_overlay()


func _open_research() -> void:
	var r = ResearchFlow.new()
	r.bridge = bridge
	r.campaign = campaign
	r.closed.connect(_close_overlay)
	r.results_shown.connect(_on_results_shown)
	r.approved.connect(_on_approved)
	_place_overlay(r)
	_advance(1)


func _on_results_shown(_has_levers: bool) -> void:
	_advance(3)


func _on_approved(levers: Array) -> void:
	_plan.add_levers(levers)
	campaign.reward_results(levers.size())
	if levers.size() > 0:
		_toast(L.t("Új lehetőség a tervedben: %d") % levers.size(), UI.GREEN)
	_show_info(L.t("%d eredmény a tervedben, bizalom +%d%%. Nyomd meg „A terved” gombot!") % [
		levers.size(), levers.size() * Campaign.TRUST_PER_RESULT], "")
	_close_overlay()
	_advance(3)
	_mission_note = ""   # a régi „még nincs a tervedben” figyelmeztetés már nem igaz
	_render_mission()   # a küldetés ugrógombja: kutatás után már „A terved →”


func _open_plan() -> void:
	_place_overlay(_plan)
	_plan.rebuild()   # az eltelt idő miatt változhatott a legkorábbi céldátum


func _on_model(res: Dictionary) -> void:
	model = res
	_close_overlay()
	_year_row.visible = false
	_year_slider.value = campaign.year
	_on_year(campaign.year)
	_update_stats()
	_show_info((str(res.get("_bevezetes", "")) + " " if res.has("_bevezetes") else "") + str(res["jelentes"]), "")
	if mission_step >= MISSION.size() and not _plan.mission.is_empty():
		var m: Dictionary = Missions.LIST[mission_idx]
		var ev := Missions.evaluate(m, res)
		_mission_note = str(ev["szoveg"])
		if int(ev["csillag"]) > 0:
			Missions.save_stars(m["id"], int(ev["csillag"]))
			_toast("%s  %s" % [Missions.star_text(int(ev["csillag"]), 1 if m["id"] == "alkalmazkodas" else 3), L.t(m["cim"])], UI.GOLD)
			_mission_note += "\n" + L.t(m["tanulsag"])
		_render_mission()
	elif mission_step < MISSION.size():
		_advance(4)
		_start_missions()


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


# ---------------------------------------------------------------------------
# Telő idő és erőforrások
# ---------------------------------------------------------------------------
func _ensure_model() -> void:
	if not campaign.model.is_empty():
		return
	# új játék: az alapeset (semmi sem változik) a modellből, hogy legyen mihez mérni
	var dir: String = bridge.work_dir("aether_modell")
	Bridge.write_json(dir.path_join("jatek_alap.json"), {"idovonal": [{"ev": 2025, "terv": {"nev": "Alapeset"}}]})
	if not bridge.run("jatekmodell", ["godot-modell", dir.path_join("jatek_alap.json"), "--ki",
			dir.path_join("jatek_alap_ki.json"), "--nyelv", L.lang]):
		_base_retry.start()


func _update_stats() -> void:
	if _stats.is_empty():
		return
	_set_stat("ev", str(campaign.year))
	_set_stat("korszak", Knowledge.era_name(campaign.era))
	_set_stat("penz", str(campaign.money))
	_set_stat("bizalom", "%d%%" % campaign.trust)
	var t: float = campaign.temp_now()
	if not is_nan(t):
		var ml: Label = _stats["melegedes"]
		ml.text = "+%s °C" % UI.hu(t, 2)
		ml.tooltip_text = L.t("A klímamodell becslése erre az évre: %d. (2024-ben mért érték: +1,36 °C, Forster és mtsai 2025.)") % campaign.year
	if not model.is_empty():
		var k: Dictionary = model["osszegzes"]["kozep"]
		(_stats["jovo"] as Label).text = "2100: +%s °C" % UI.hu(float(k["T2100"]), 1)
	if _play_btn != null:
		_play_btn.text = L.t("Szünet") if campaign.running else L.t("Idő indítása")
		_play_btn.disabled = campaign.year >= Campaign.END_YEAR


func _click_stat(key: String, fn: Callable) -> void:
	var l: Label = _stats[key]
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var f := func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _overlay == null:
			fn.call()
	l.gui_input.connect(f)


## A felső sáv értéke; ha változott, röviden felvillan (így látszik, mi történt).
func _set_stat(key: String, value: String) -> void:
	var l: Label = _stats[key]
	if l.text == value:
		return
	var first := l.text == ""
	l.text = value
	if first or not is_inside_tree():
		return
	l.pivot_offset = l.size * 0.5
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.18, 1.18), 0.12)
	tw.parallel().tween_property(l, "modulate", Color(1.6, 1.6, 1.6), 0.12)
	tw.tween_property(l, "scale", Vector2.ONE, 0.25)
	tw.parallel().tween_property(l, "modulate", Color.WHITE, 0.35)


func _toggle_time() -> void:
	campaign.running = not campaign.running and campaign.year < Campaign.END_YEAR
	_update_stats()
	if campaign.running and campaign.timeline.is_empty():
		_show_info(L.t("Telik az idő, de még nincs terved: a kibocsátás nem csökken. Nyisd meg „A terved” ablakot!"), "")


func _on_year_passed(y: int, note: String) -> void:
	_year_slider.value = y   # rejtett: a földgömb színezését követi az év
	_show_info(note, "")


func _on_era_reached(e: int) -> void:
	_update_stats()
	_show_info(L.t("Új korszak: %s! %s") % [Knowledge.era_name(e), L.t(Knowledge.ERAS[e - 1]["tema"])], "")
	_toast(L.t("Új korszak: %s") % Knowledge.era_name(e), UI.GOLD)
	if is_instance_valid(_plan) and _plan.is_inside_tree():
		_plan.rebuild()


func _on_game_over() -> void:
	_update_stats()
	var k: Dictionary = model.get("osszegzes", {}).get("kozep", {})
	if k.is_empty():
		return
	_show_info(L.t("2100: vége a játéknak. A Föld +%s °C-kal melegebb, a csúcs +%s °C volt. „Új játék”: próbáld meg jobban!") % [
		UI.hu(float(k["T2100"]), 1), UI.hu(float(k["csucs"]), 1)], "")
	_open_summary(k)


## A játék vége: néhány nagy szám egy lapon, és egy gomb az új játékhoz.
func _open_summary(k: Dictionary) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.GOLD
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 28
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(18)
	p.add_child(v)
	v.add_child(UI.heading(L.t("2100 – így alakult")))
	var t2100 := float(k.get("T2100", 0.0))
	var verdict := L.t("Másfél fok alatt maradt. Kiváló!") if t2100 < 1.5 else (
		L.t("Két fok alatt maradt.") if t2100 < 2.0 else L.t("Két fok fölé ment. Próbáld korábbi CO2-nullával!"))
	v.add_child(UI.label(verdict, 22, UI.GREEN if t2100 < 2.0 else UI.EMBER, true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 14)
	var items := [
		[L.t("Melegedés 2100-ban"), "+%s °C" % UI.hu(t2100, 1), UI.EMBER],
		[L.t("Csúcs"), "+%s °C" % UI.hu(float(k.get("csucs", 0.0)), 1), UI.GOLD],
		[L.t("Kutatott témák"), str(campaign.done.size()), UI.CYAN],
		[L.t("Korszak"), Knowledge.era_name(campaign.era), UI.GOLD],
		[L.t("Bizalom"), "%d%%" % campaign.trust, UI.GREEN],
		[L.t("Pénz"), str(campaign.money), UI.GOLD],
	]
	for it in items:
		var c := UI.vbox(2)
		c.add_child(UI.label(it[0], 15, UI.MUTE, false, false))
		c.add_child(UI.label(it[1], 30, it[2], true, false))
		grid.add_child(c)
	v.add_child(grid)
	var again := UI.button(L.t("Új játék"), true)
	again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var again_fn := func() -> void:
		_close_overlay()
		_reset_btn.text = L.t("Biztos? Kattints újra")   # egyből indul, nem kér megerősítést
		_reset_game()
	again.pressed.connect(again_fn)
	# a küldetések csillagai összesen
	var got := 0
	var all := 0
	for m in Missions.LIST:
		got += Missions.stars_of(m["id"])
		all += 1 if m["id"] == "alkalmazkodas" else 3
	v.add_child(UI.label(L.t("Küldetések: %s  (%d/%d csillag)") % [Missions.star_text(got, all), got, all], 18, UI.GOLD, true))
	v.add_child(again)
	_place_overlay(p)
	# csak akkora legyen, amekkora a tartalom (az X a sarokkal együtt mozog)
	p.custom_minimum_size = Vector2(920, 0)
	p.position.y = 200
	var fit := func() -> void:
		if is_instance_valid(p):
			p.size = Vector2(920, 0)   # a tartalom legkisebb magasságára zsugorodik
	fit.call_deferred()


func _reset_game() -> void:
	if _reset_btn.text != L.t("Biztos? Kattints újra"):
		_reset_btn.text = L.t("Biztos? Kattints újra")
		var back := func() -> void:
			if is_instance_valid(_reset_btn):
				_reset_btn.text = L.t("Új játék")
		get_tree().create_timer(3.0).timeout.connect(back)
		return
	_reset_btn.text = L.t("Új játék")
	campaign.new_game()
	model = {}
	_year_row.visible = false
	globe.heat = 0.0
	globe.home()
	_ensure_model()
	_show_info(L.t("Új játék 2026-tól. Kutass, készíts tervet, és indítsd el az időt!"), "")


func _on_bridge_finished(tag: String, code: int, output: String) -> void:
	if tag == "jatekmodell":
		var r: Variant = Bridge.read_json(bridge.work_dir("aether_modell").path_join("jatek_alap_ki.json"))
		if code == 0 and typeof(r) == TYPE_DICTIONARY and not r.has("hiba") and campaign.model.is_empty():
			campaign.model = r
			campaign.save()
			model = r
			_year_row.visible = false
			_year_slider.value = campaign.year
			_update_stats()
		elif code != 0:
			print(output)
		return
	if tag != "vilag":
		return
	_refresh_btn.disabled = false
	_refresh_btn.text = L.t("Frissítés valós adatokkal")
	var w: Variant = Bridge.read_json(_world_path())
	if code == 0 and typeof(w) == TYPE_DICTIONARY:
		world = w
		_render_world()
	else:
		_world_note.text = L.t("Az adatletöltés nem sikerült. Van Python 3.10+ és internet?")
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
	# 1b: egy esemény kijelölése a listából (gyűrű a gömbön, odafordulás); 1c súgó; 1d játék vége
	var evs: Array = world.get("esemenyek", [])
	if not evs.is_empty():
		globe.highlight = evs[0]
		globe.look_at_event(evs[0])
		await get_tree().create_timer(1.0).timeout
		await _shot(dir, "1b_kiemeles.png")
		_open_help()
		await _shot(dir, "1c_sugo.png")
		_close_overlay()
		_open_summary({"T2100": 1.62, "csucs": 1.66})
		await _shot(dir, "1d_osszegzes.png")
		_close_overlay()
		# 1e: telő idő (évsáv és hónap a felső sávban), utána megáll
		campaign.running = true
		_update_stats()
		await get_tree().create_timer(5.0).timeout
		await _shot(dir, "1e_ido.png")
		campaign.running = false
		_update_stats()
		globe.highlight = {}
		globe.home()
		await get_tree().create_timer(0.8).timeout
	if not world.get("esemenyek", []).is_empty():
		_show_event(world["esemenyek"][0])
		for i in 120:   # az esemény összefoglalója a hídon fut: megvárjuk
			if not bridge.is_busy():
				break
			await get_tree().create_timer(0.5).timeout
	_open_research()
	var r = _overlay
	r._pick_question(Knowledge.topics()[0])
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
		res["_bevezetes"] = campaign.adopt(_plan._scenario(), res)
		print("ONTESZT bevezetés: ", res["_bevezetes"], " pénz=", campaign.money, " bizalom=", campaign.trust)
		_on_model(res)
		for i in 10:
			campaign.advance()
		print("ONTESZT idő: év=", campaign.year, " pénz=", campaign.money, " bizalom=", campaign.trust,
			" T=", campaign.temp_now())
		await _shot(dir, "5_ido_10_ev.png")
		_year_slider.value = 2100
		await _shot(dir, "5b_fold_2100.png")
		_year_slider.value = campaign.year
		print("ONTESZT építés: ", campaign.build("ai_mag"))
		campaign.advance()
		print("ONTESZT állomás: ", campaign.station, " cikk/kutatás=", campaign.papers_per_research())
		print("ONTESZT építés 2: ", campaign.build("uveghaz"))
		_open_station()
		await _shot(dir, "7_allomas.png")
		_close_overlay()
		# tudásfa: két I. korszakos téma után a II. korszak nyílik meg
		campaign.mark_researched("tcre")
		campaign.mark_researched("termes", 3)
		print("ONTESZT tudásfa: témák=", Knowledge.topics().size(), " korszak=", campaign.era,
			" kutatott=", campaign.done, " csillagok=", campaign.stars, " III. feltételei=", campaign.era_conditions(3))
		_open_research()
		var rp = _overlay
		rp._open_fields["1:fizika"] = true
		rp._open_fields["1:mezogazdasag"] = true
		rp._fill_questions()
		await _shot(dir, "8_tudasfa.png")
		rp._filter = "jég"
		rp.show_questions()
		await _shot(dir, "8b_kereses.png")
		rp._filter = ""
		_close_overlay()
		_open_nalunk()
		for i in 60:   # a mért adatok letöltése
			await get_tree().create_timer(1.0).timeout
			if not bridge.is_busy():
				break
		await get_tree().create_timer(1.0).timeout
		await _shot(dir, "9_nalunk.png")
		_close_overlay()
	_close_overlay()
	for e in world.get("esemenyek", []):
		if str(e.get("kategoria", "")) == "levego":
			_show_event(e)
			var ep = _overlay
			for i in 60:
				await get_tree().create_timer(1.0).timeout
				if ep._out != "" and FileAccess.file_exists(ep._out):
					break
			await get_tree().create_timer(1.0).timeout
			await _shot(dir, "6_esemeny_levego.png")
			_close_overlay()
			break
	print("ONTESZT kész")
	get_tree().quit()
