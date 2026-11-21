extends PanelContainer
## A játékos terve: néhány egyszerű csúszka, hétköznapi kérdésekkel.
## A CO2 és a metán a kezdetektől állítható (IPCC / UNEP célok alapján),
## a többi kar csak kutatás és jóváhagyás után nyílik meg, és csak
## az ellenőrzött értékig húzható.

signal model_ready(result: Dictionary)
signal closed

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")
const Chart := preload("res://scripts/chart.gd")

const NEVER := 2105          # a csúszka L.t("Soha") állása

var bridge
var levers: Dictionary = {}  # kar -> javaslat (a jóváhagyott kutatásokból)
var mission: Dictionary = {}  # az aktuális küldetés (missions.gd); co2_ev esetén a CO2-év rögzített
var _body: VBoxContainer
var _co2: HSlider
var _ch4: HSlider
var _lever_sliders: Dictionary = {}   # kar -> HSlider
var _result_box: VBoxContainer
var _chart                 # chart.gd példány
var _run_btn: Button
var _out_path := ""


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.GOLD
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 28
	sb.set_content_margin_all(24)
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = UI.vbox(14)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	bridge.finished.connect(_on_bridge_finished)
	rebuild()


func add_levers(new_levers: Array) -> void:
	for j in new_levers:
		levers[str(j["kar"])] = j
	if is_inside_tree():
		rebuild()


func set_mission(m: Dictionary) -> void:
	mission = m
	if is_inside_tree():
		rebuild()


func _slider_row(question: String, help: String, mn: float, mx: float, step: float, value: float,
		fmt: Callable, source: String = "") -> HSlider:
	var c := UI.card(UI.GOLD)
	c.add_child(UI.label(question, 18, UI.TEXT, true))
	c.add_child(UI.label(help, 15, UI.SOFT))
	var row := UI.hbox(14)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 28)
	var v := UI.label(fmt.call(value), 20, UI.GOLD, true, false)
	v.custom_minimum_size = Vector2(150, 0)
	var upd := func(x: float) -> void: v.text = fmt.call(x)
	s.value_changed.connect(upd)
	row.add_child(s)
	row.add_child(v)
	c.add_child(row)
	if source != "":
		c.add_child(UI.label(L.t("Forrás: ") + source, 13, UI.MUTE))
	_body.add_child(UI.card_root(c))
	return s


func rebuild() -> void:
	UI.clear(_body)
	_lever_sliders.clear()
	var h := UI.hbox(12)
	h.add_child(UI.heading(L.t("A terved")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var x := UI.button(L.t("Bezárás"))
	var close_fn := func() -> void: closed.emit()
	x.pressed.connect(close_fn)
	h.add_child(x)
	_body.add_child(h)
	if mission.is_empty():
		_body.add_child(UI.label(L.t("Állítsd be, mit tegyen a világ, és nézd meg, mi lesz 2100-ig."), 17, UI.SOFT))
	else:
		_body.add_child(UI.label(L.t("Küldetés: ") + L.t(mission["cel"]), 17, UI.GOLD, true))

	var year_fmt := func(y: float) -> String: return L.t("Soha") if int(y) >= NEVER else str(int(y))
	var pct_fmt := func(p: float) -> String: return "%d%%" % int(p)
	var gt_fmt := func(v: float) -> String: return UI.hu(v, 2) + L.t(" mrd t")
	_co2 = _slider_row(L.t("Mikorra csökkenjen nullára a CO2-kibocsátás?"),
		L.t("A melegedés fő oka. Minél hamarabb nulla, annál jobb."),
		2035, NEVER, 5, 2050, year_fmt,
		L.t("IPCC AR6: a melegedés a kibocsátott CO2 összmennyiségével arányos"))
	if mission.has("co2_ev"):   # ebben a küldetésben a világ nem tud gyorsabban
		_co2.value = int(mission["co2_ev"])
		_co2.editable = false
		_co2.tooltip_text = L.t("Ebben a küldetésben rögzített.")
	_ch4 = _slider_row(L.t("Mennyivel csökkentsük a metánt 2030-ig?"),
		L.t("Gyorsan hat: csökkentése pár évtized alatt lassítja a melegedést."),
		0, 45, 5, 0, pct_fmt,
		L.t("UNEP/CCAC Global Methane Assessment (2021): 45% elérhető 2030-ig"))

	var keys := levers.keys()
	keys.sort()
	for k in keys:
		var j: Dictionary = levers[k]
		var mx := float(j["kar_ertek"])
		if str(k).begins_with("cdr:"):
			_lever_sliders[k] = _slider_row(L.t("%s: évente mennyi CO2-t vonjon ki 2050-re?") % j["kar_nev"],
				L.t("A kutatásod szerint legfeljebb ennyi lehetséges. ") + str(j["bizonyossag_szoveg"]),
				0, mx, mx / 20.0, mx, gt_fmt,
				L.t("saját kutatásod, ") + str(j["publikacio"]))
		elif k == "alkalmazkodas":
			_lever_sliders[k] = _slider_row(L.t("Aszálytűrő fajták: mekkora részét védjék a termésnek?"),
				L.t("Ez nem hűti a Földet, de csökkenti a termésveszteséget. ") + str(j["bizonyossag_szoveg"]),
				0, mx, 1, mx, pct_fmt,
				L.t("saját kutatásod, ") + str(j["publikacio"]))
	if levers.is_empty():
		var c := UI.card(UI.EDGE)
		c.add_child(UI.label(L.t("Zárolva: CO2-kivonás és alkalmazkodás"), 17, UI.MUTE, true))
		c.add_child(UI.label(L.t("Ezeket előbb ki kell kutatnod."), 15, UI.MUTE))
		_body.add_child(UI.card_root(c))

	_run_btn = UI.button(L.t("Mi lesz a Földdel? (modell futtatása)"), true)
	_run_btn.pressed.connect(_run_model)
	_body.add_child(_run_btn)
	_result_box = UI.vbox(10)
	_body.add_child(_result_box)


func _scenario() -> Dictionary:
	var sc := {"nev": "A te terved", "leiras": "AETHER játékos terve"}
	if int(_co2.value) < NEVER:
		sc["co2_cel_ev"] = int(_co2.value)
		sc["co2_cel_ertek"] = 0.0
	sc["metan_csokkentes_pct"] = _ch4.value
	sc["metan_cel_ev"] = 2030
	var cdr := {}
	for k in _lever_sliders:
		var s: HSlider = _lever_sliders[k]
		if str(k).begins_with("cdr:"):
			cdr[str(k).substr(4)] = s.value
		elif k == "alkalmazkodas":
			sc["alkalmazkodas_hozam_kompenzacio_pct"] = s.value
			sc["alkalmazkodas_forras"] = str(levers[k]["publikacio"])
	sc["cdr"] = cdr
	return sc


func _run_model() -> void:
	var dir: String = bridge.work_dir("aether_modell")
	var inp := dir.path_join("terv.json")
	_out_path = dir.path_join("eredmeny.json")
	Bridge.write_json(inp, _scenario())
	if bridge.run("modell", ["godot-modell", inp, "--ki", _out_path, "--nyelv", L.lang]):
		_run_btn.disabled = true
		_run_btn.text = L.t("Számolok…")
	else:
		_run_btn.text = L.t("Egy pillanat, próbáld újra")


func _on_bridge_finished(tag: String, code: int, output: String) -> void:
	if tag != "modell":
		return
	_run_btn.disabled = false
	_run_btn.text = L.t("Újraszámolás")
	UI.clear(_result_box)
	var r: Variant = Bridge.read_json(_out_path)
	if code != 0 or typeof(r) != TYPE_DICTIONARY or r.has("hiba"):
		_result_box.add_child(UI.label(L.t("A modell nem futott le. Telepítve van a Python 3.10+?"), 17, UI.EMBER))
		print(output)
		return
	var res: Dictionary = r
	_result_box.add_child(UI.label(str(res["jelentes"]), 19, UI.TEXT, true))
	_chart = Chart.new()
	_result_box.add_child(_chart)
	_chart.set_data(res)
	_result_box.add_child(UI.label(L.t("Egyszerű oktatási modell: irányt mutat, nem jósol."), 14, UI.MUTE))
	var see := UI.button(L.t("Megnézem a földgömbön"), true)
	res["_terv"] = _scenario()   # a küldetés értékeléséhez
	var see_fn := func() -> void: model_ready.emit(res)
	see.pressed.connect(see_fn)
	_result_box.add_child(see)
