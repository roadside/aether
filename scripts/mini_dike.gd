extends Control
## Minijáték: Gátőr. Egy tengerparti város gátját kell elég magasra emelni, miközben telnek az évek.
## 1900 és 2019 között a tengerszint valódi mérés (US EPA: CSIRO, NOAA); 2020-ban a játékos választ:
## alacsony vagy nagyon magas kibocsátás. Utána a görbe az IPCC AR6 valószínű tartományának közepéig nő.
## (adatok/tengerszint_gat.json, a forrás a fájlban)
## Játékszabály: a 2020 utáni görbe alakja, a viharok ideje és magassága, a gát magassága,
## az emelések száma és mérete kitalált.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const Y_START := 1900
const Y_END := 2100
const PAST_SPEED := 0.06      # játékszabály: másodperc / év 2020-ig
const FUTURE_SPEED := 0.3     # játékszabály: másodperc / év 2020 után
const DIKE0 := 105.0          # játékszabály: a gát kezdeti magassága (cm)
const RAISE := 8.0           # játékszabály: egy emelés (cm)
const RAISES := 4             # játékszabály
const PX_CM := 2.1            # a jelenet függőleges léptéke
const SEA0_Y := 720.0         # a 0 cm szint a jeleneten (az 1995–2014-es átlag)
const DIKE_X := 560.0
const PATHS := ["SSP1-2.6", "SSP5-8.5"]

var data_path := "res://adatok/tengerszint_gat.json"
var auto := false             # próbafutás: magától emel és választ
var auto_path := 1            # a próbafutás választása (0 = alacsony, 1 = nagyon magas)
var done_t := -1.0            # a befejezés óta eltelt idő; < 0 = még tart
var obs := {}                 # év -> cm
var ranges := {}              # pálya -> [alsó m, felső m] 2100-ra
var ipcc := {}
var source := ""
var source2 := ""
var year := float(Y_START)
var path := -1                # a választott pálya, -1 = még nincs
var dike := DIKE0
var raises := RAISES
var floods := 0
var storms: Array = []        # [év, hullám cm, megtörtént]
var _t := 0.0
var _wave_t := -10.0
var _wave_h := 0.0
var _flood_t := -10.0
var _s2019 := 0.0
var _info: Label
var _read: Label
var _raise_btn: Button
var _choice: HBoxContainer
var _end: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var y := 1906.0
	while y < Y_END:      # játékszabály: viharok 4–9 évente, 55–100 cm-es hullámmal
		storms.append([y, rng.randf_range(55.0, 100.0), false])
		y += rng.randf_range(4.0, 9.0)
	var title := UI.heading(L.t("Gátőr"), 34)
	title.position = Vector2(60, 28)
	add_child(title)
	_info = UI.label(L.t("Nézd, hogyan emelkedik a tenger! Ha egy vihar hulláma magasabb a gátnál, elönti a várost. Szóközzel vagy a gombbal emelheted a gátat."), 18, UI.SOFT)
	_info.position = Vector2(60, 84)
	_info.size = Vector2(960, 60)
	add_child(_info)
	_read = UI.label("", 20, UI.CYAN, true, false)
	_read.position = Vector2(1080, 86)
	add_child(_read)
	_raise_btn = UI.button(L.t("Gát emelése"), true)
	_raise_btn.position = Vector2(60, 160)
	_raise_btn.pressed.connect(_raise)
	add_child(_raise_btn)
	_choice = UI.hbox(16)
	_choice.position = Vector2(240, 380)
	_choice.visible = false
	var q := UI.label(L.t("2020 van. Hogyan folytatja a világ?"), 22, UI.GOLD, true, false)
	q.position = Vector2(240, 330)
	q.name = "Q"
	q.visible = false
	add_child(q)
	var b0 := UI.button(L.t("Gyorsan csökkentjük a kibocsátást"), true)
	b0.pressed.connect(func() -> void: _choose(0))
	var b1 := UI.button(L.t("Egyre több szenet, olajat és gázt égetünk"), false)
	b1.pressed.connect(func() -> void: _choose(1))
	_choice.add_child(b0)
	_choice.add_child(b1)
	add_child(_choice)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(60, 470)
	_end.size = Vector2(980, 380)
	_end.visible = false
	add_child(_end)
	_update_read()
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	var en := L.is_en()
	source = str(j.get("forras_en" if en else "forras", ""))
	for p in j.get("meres", []):
		obs[int(p[0])] = float(p[1])
	var ip: Variant = j.get("ipcc", {})
	if typeof(ip) == TYPE_DICTIONARY:
		ipcc = ip
		ranges = ip.get("m_2100", {})
		source2 = str(ip.get("forras_en" if en else "forras", ""))
	_s2019 = float(obs.get(2019, 0.0))


func ok() -> bool:
	return obs.size() > 100 and ranges.has("SSP1-2.6") and ranges.has("SSP5-8.5")


## A tengerszint (cm) egy adott évben: 2019-ig mérés, utána a választott pálya (alakja játékszabály).
func sea_at(y: float) -> float:
	if y <= 2019.0:
		var a := int(floor(y))
		var b := mini(a + 1, 2019)
		return lerpf(float(obs.get(a, 0.0)), float(obs.get(b, 0.0)), y - a)
	if path < 0:
		return _s2019
	var r: Array = ranges[PATHS[path]]
	var target := (float(r[0]) + float(r[1])) * 50.0      # a valószínű tartomány közepe, cm
	var f := clampf((y - 2019.0) / (Y_END - 2019.0), 0.0, 1.0)
	return _s2019 + (target - _s2019) * pow(f, 1.4)


func _update_read() -> void:
	_read.text = L.t("%d    Tenger: %s cm    Gát: %s cm    Emelés: %d") % [int(year), L.num(sea_at(year), 0), L.num(dike, 0), raises]


func _raise() -> void:
	if raises <= 0 or done_t >= 0.0:
		return
	raises -= 1
	dike += RAISE
	if raises <= 0:
		_raise_btn.disabled = true
	_update_read()


func _choose(i: int) -> void:
	if path >= 0:
		return
	path = i
	_choice.visible = false
	get_node("Q").visible = false
	grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			finished.emit(done_t >= 0.0)
		elif event.keycode in [KEY_SPACE, KEY_UP]:
			get_viewport().set_input_as_handled()
			_raise()


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
		queue_redraw()
		return
	if year >= 2020.0 and path < 0:      # döntés: a játék megáll, amíg a játékos választ
		_choice.visible = true
		get_node("Q").visible = true
		if auto:
			_choose(auto_path)
		queue_redraw()
		return
	var prev := year
	year = minf(year + delta / (PAST_SPEED if year < 2020.0 else FUTURE_SPEED), float(Y_END))
	if prev < 2020.0 and year >= 2020.0:
		year = 2020.0
	for s in storms:
		if not bool(s[2]) and float(s[0]) <= year:
			s[2] = true
			_wave_t = _t
			_wave_h = float(s[1])
			if sea_at(year) + _wave_h > dike:
				floods += 1
				_flood_t = _t
	if auto and raises > 0 and sea_at(year + 6.0) + 100.0 > dike:
		_raise()
	_update_read()
	if year >= Y_END:
		_finish()
	queue_redraw()


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_info.visible = false
	_raise_btn.visible = false
	_read.visible = false
	var r0: Array = ranges.get("SSP1-2.6", [0, 0])
	var r1: Array = ranges.get("SSP5-8.5", [0, 0])
	var rate: Dictionary = ipcc.get("utem_mm_ev", {})
	_end.visible = true
	_end.add_child(UI.label(L.t("Ennyiszer öntötte el a víz a városodat: %d") % floods if floods > 0 else L.t("A városod száraz maradt."), 22, UI.CYAN, true))
	_end.add_child(UI.label(L.t("A tenger 1901 és 2018 között kb. %s cm-t emelkedett, és egyre gyorsabban: 2006 és 2018 között évente kb. %s mm-t.") % [L.num(float(ipcc.get("emelkedes_1901_2018_m", 0.0)) * 100.0, 0), L.num(float(rate.get("2006-2018", 0.0)), 1)], 19, UI.TEXT))
	_end.add_child(UI.label(L.t("2100-ra: alacsony kibocsátással %s–%s cm, nagyon magassal %s–%s cm (az 1995–2014-es szinthez képest).") % [L.num(float(r0[0]) * 100.0, 0), L.num(float(r0[1]) * 100.0, 0), L.num(float(r1[0]) * 100.0, 0), L.num(float(r1[1]) * 100.0, 0)], 19, UI.TEXT, true))
	_end.add_child(UI.label(L.t("A régen százévente egyszer előforduló magas vízállás 2100-ra a mérőhelyek több mint felén legalább évente előfordul."), 19, UI.TEXT))
	_end.add_child(UI.label(L.t("A gát időt ad, de a tenger 2100 után is emelkedik. A kibocsátás csökkentése lassítja."), 19, UI.GOLD, true))
	_end.add_child(UI.label(L.t("Adat: %s; %s") % [source, source2], 13, UI.MUTE))
	var b := UI.button(L.t("Tovább") + " →", true)
	b.pressed.connect(func() -> void: finished.emit(true))
	b.position = Vector2(1390, 30)
	add_child(b)


func _cy(cm: float) -> float:
	return SEA0_Y - cm * PX_CM


func _draw() -> void:
	var font := get_theme_default_font()
	# --- ég ---
	for i in 40:
		var f := i / 39.0
		draw_rect(Rect2(0, f * H, 1040, H / 39.0 + 1.0), Color("#0d1a33").lerp(Color("#36557f"), f))
	draw_rect(Rect2(1040, 0, W - 1040, H), Color("#0b1324"))
	var sea := sea_at(year)
	var wave := 0.0
	var wa := _t - _wave_t
	if wa < 1.4:
		wave = _wave_h * sin(clampf(wa / 1.4, 0.0, 1.0) * PI)
	# --- tenger a gát előtt ---
	var top := _cy(sea)
	var pts := PackedVector2Array()
	for k in 41:
		var x := DIKE_X * k / 40.0
		var bump := wave * exp(-pow((x - DIKE_X + 60.0) / 140.0, 2.0))
		pts.append(Vector2(x, top - bump * PX_CM + sin(_t * 2.0 + x * 0.03) * 4.0))
	pts.append(Vector2(DIKE_X, H))
	pts.append(Vector2(0, H))
	draw_colored_polygon(pts, Color("#1f5f8b"))
	# --- part és város ---
	var land := PackedVector2Array([Vector2(DIKE_X, _cy(10.0)), Vector2(1040, _cy(10.0)), Vector2(1040, H), Vector2(DIKE_X, H)])
	draw_colored_polygon(land, Color("#4a5a3c"))
	for h in 6:
		var hx := 640.0 + h * 64.0
		var hh := 46.0 + (h % 3) * 14.0
		draw_rect(Rect2(hx, _cy(10.0) - hh, 44, hh), Color("#c9b79c"))
		draw_colored_polygon(PackedVector2Array([Vector2(hx - 4, _cy(10.0) - hh), Vector2(hx + 22, _cy(10.0) - hh - 22), Vector2(hx + 48, _cy(10.0) - hh)]), Color("#8a4b3a"))
		draw_rect(Rect2(hx + 14, _cy(10.0) - hh + 12, 14, 12), Color("#f1c873") if fmod(_t + h, 3.0) > 0.4 else Color("#6b5a40"))
	var fa := _t - _flood_t
	if fa < 2.2:      # áradás: víz a városban
		var lvl := 50.0 * sin(clampf(fa / 2.2, 0.0, 1.0) * PI)
		draw_rect(Rect2(DIKE_X, _cy(10.0) - lvl, 1040 - DIKE_X, lvl + 4.0), Color(0.2, 0.45, 0.7, 0.75))
		draw_string(font, Vector2(700, _cy(10.0) - 120.0), L.t("Elöntötte a víz!"), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UI.EMBER)
	# --- a gát ---
	var dy := _cy(dike)
	draw_colored_polygon(PackedVector2Array([Vector2(DIKE_X - 40.0, _cy(-40.0)), Vector2(DIKE_X - 8.0, dy), Vector2(DIKE_X + 14.0, dy), Vector2(DIKE_X + 40.0, _cy(10.0)), Vector2(DIKE_X + 40.0, H), Vector2(DIKE_X - 40.0, H)]), Color("#7c7466"))
	draw_line(Vector2(DIKE_X - 8.0, dy), Vector2(DIKE_X + 14.0, dy), UI.GOLD, 3.0)
	draw_string(font, Vector2(DIKE_X - 70.0, dy - 10.0), L.t("gát") + " " + L.num(dike, 0) + " cm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.GOLD)
	draw_string(font, Vector2(20, top - 12.0), L.t("tenger") + " " + L.num(sea, 0) + " cm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.TEXT)
	draw_string(font, Vector2(860, 210), str(int(year)), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(UI.TEXT, 0.9))
	if done_t >= 0.0:
		draw_rect(Rect2(40, 455, 1000, 290), Color(0.043, 0.063, 0.114, 0.9 * clampf(done_t / 0.8, 0.0, 1.0)))
	# --- grafikon: tengerszint 1900–2100 ---
	var gx0 := 1090.0
	var gx1 := 1560.0
	var gy0 := 520.0
	var gy1 := 160.0
	var cmin := -20.0
	var cmax := 110.0
	var gx := func(yy: float) -> float: return lerpf(gx0, gx1, (yy - Y_START) / float(Y_END - Y_START))
	var gy := func(cm: float) -> float: return lerpf(gy0, gy1, (cm - cmin) / (cmax - cmin))
	draw_string(font, Vector2(gx0, 140), L.t("Tengerszint (cm, az 1995–2014-es szinthez képest)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.SOFT)
	for c in [0.0, 50.0, 100.0]:
		draw_line(Vector2(gx0, gy.call(c)), Vector2(gx1, gy.call(c)), Color(UI.MUTE, 0.25), 1.0)
		draw_string(font, Vector2(gx0 - 40.0, gy.call(c) + 5.0), L.num(c, 0), HORIZONTAL_ALIGNMENT_RIGHT, 34, 12, UI.MUTE)
	for yy in [1900, 1950, 2000, 2050, 2100]:
		draw_string(font, Vector2(gx.call(float(yy)) - 20.0, gy0 + 20.0), str(yy), HORIZONTAL_ALIGNMENT_CENTER, 40, 12, UI.MUTE)
	if done_t >= 0.0 or path >= 0:      # a két pálya tartománya 2100-ban
		for i in 2:
			var r: Array = ranges[PATHS[i]]
			var col := UI.GREEN if i == 0 else UI.EMBER
			var a := 0.9 if i == path else 0.35
			var bx: float = gx.call(2100.0) - 10.0 + i * 12.0
			draw_line(Vector2(bx, gy.call(float(r[0]) * 100.0)), Vector2(bx, gy.call(float(r[1]) * 100.0)), Color(col, a), 6.0)
	var prev := Vector2.ZERO
	var yy2 := float(Y_START)
	while yy2 <= year:
		var p := Vector2(gx.call(yy2), gy.call(sea_at(yy2)))
		if yy2 > Y_START:
			draw_line(prev, p, UI.CYAN if yy2 <= 2019.0 else (UI.GREEN if path == 0 else UI.EMBER), 2.5)
		prev = p
		yy2 += 1.0
	draw_string(font, Vector2(gx0, gy0 + 44.0), L.t("kék: mérés, 1900–2019"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.CYAN)
	draw_string(font, Vector2(gx0, gy0 + 64.0), L.t("2100: az IPCC valószínű tartománya"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.SOFT)
