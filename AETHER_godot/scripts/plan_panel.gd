extends PanelContainer
## A játékos terve: néhány egyszerű csúszka, hétköznapi kérdésekkel.
## A CO2 és a metán a kezdetektől állítható (IPCC / UNEP célok alapján),
## a többi kar csak kutatás és jóváhagyás után nyílik meg, és csak
## az ellenőrzött értékig húzható.

signal model_ready(result: Dictionary)
signal closed

const UI := preload("res://scripts/ui.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")
const Chart := preload("res://scripts/chart.gd")

const NEVER := 2105          # a csúszka "Soha" állása

var bridge
var levers: Dictionary = {}  # kar -> javaslat (a jóváhagyott kutatásokból)
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
	sb.set_border_width_all(2)
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
		c.add_child(UI.label("Forrás: " + source, 13, UI.MUTE))
	_body.add_child(UI.card_root(c))
	return s


func rebuild() -> void:
	UI.clear(_body)
	_lever_sliders.clear()
	var h := UI.hbox(12)
	h.add_child(UI.heading("A terved"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var x := UI.button("Bezárás")
	var close_fn := func() -> void: closed.emit()
	x.pressed.connect(close_fn)
	h.add_child(x)
	_body.add_child(h)
	_body.add_child(UI.label("Állítsd be, mit tegyen a világ. Utána megnézzük, mi lesz a Föld hőmérsékletével 2100-ig.", 17, UI.SOFT))

	var year_fmt := func(y: float) -> String: return "Soha" if int(y) >= NEVER else str(int(y))
	var pct_fmt := func(p: float) -> String: return "%d%%" % int(p)
	var gt_fmt := func(v: float) -> String: return UI.hu(v, 2) + " mrd t"
	_co2 = _slider_row("Mikorra csökkenjen nullára a CO2-kibocsátás?",
		"A CO2 a fő oka a melegedésnek. Minél hamarabb nullázzuk, annál kevésbé melegszik a Föld.",
		2035, NEVER, 5, 2050, year_fmt,
		"IPCC AR6: a melegedés a kibocsátott CO2 összmennyiségével arányos")
	_ch4 = _slider_row("Mennyivel csökkentsük a metánt 2030-ig?",
		"A metán gyorsan hat: ha csökken, pár évtized alatt érezhetően lassul a melegedés.",
		0, 45, 5, 0, pct_fmt,
		"UNEP/CCAC Global Methane Assessment (2021): 45% elérhető 2030-ig")

	var keys := levers.keys()
	keys.sort()
	for k in keys:
		var j: Dictionary = levers[k]
		var mx := float(j["kar_ertek"])
		if str(k).begins_with("cdr:"):
			_lever_sliders[k] = _slider_row("%s: évente mennyi CO2-t vonjon ki 2050-re?" % j["kar_nev"],
				"A kutatásod szerint legfeljebb ennyi lehetséges. " + str(j["bizonyossag_szoveg"]),
				0, mx, mx / 20.0, mx, gt_fmt,
				"saját kutatásod, " + str(j["publikacio"]))
		elif k == "alkalmazkodas":
			_lever_sliders[k] = _slider_row("Aszálytűrő fajták: mekkora részét védjék a termésnek?",
				"Ez nem hűti a Földet, de csökkenti a termésveszteséget. " + str(j["bizonyossag_szoveg"]),
				0, mx, 1, mx, pct_fmt,
				"saját kutatásod, " + str(j["publikacio"]))
	if levers.is_empty():
		var c := UI.card(UI.EDGE)
		c.add_child(UI.label("Zárolva: CO2-kivonás és alkalmazkodás", 17, UI.MUTE, true))
		c.add_child(UI.label("Ezeket előbb ki kell kutatnod. Csak olyan szám kerülhet a tervbe, amit valódi cikkekben ellenőriztünk.", 15, UI.MUTE))
		_body.add_child(UI.card_root(c))

	_run_btn = UI.button("Mi lesz a Földdel? (modell futtatása)", true)
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
	if bridge.run("modell", ["godot-modell", inp, "--ki", _out_path]):
		_run_btn.disabled = true
		_run_btn.text = "Számolok…"
	else:
		_run_btn.text = "Még dolgozom egy másik feladaton, nyomd meg újra pár másodperc múlva"


func _on_bridge_finished(tag: String, code: int, output: String) -> void:
	if tag != "modell":
		return
	_run_btn.disabled = false
	_run_btn.text = "Újraszámolás"
	UI.clear(_result_box)
	var r: Variant = Bridge.read_json(_out_path)
	if code != 0 or typeof(r) != TYPE_DICTIONARY or r.has("hiba"):
		_result_box.add_child(UI.label("A modell nem futott le. Telepítve van a Python 3.10+?", 17, UI.EMBER))
		print(output)
		return
	var res: Dictionary = r
	_result_box.add_child(UI.label(str(res["jelentes"]), 19, UI.TEXT, true))
	_chart = Chart.new()
	_result_box.add_child(_chart)
	_chart.set_data(res)
	_result_box.add_child(UI.label("Ez egy egyszerű oktatási modell: az irányt és a nagyságrendet mutatja, nem pontos jövendölést.", 14, UI.MUTE))
	var see := UI.button("Megnézem a földgömbön", true)
	var see_fn := func() -> void: model_ready.emit(res)
	see.pressed.connect(see_fn)
	_result_box.add_child(see)
