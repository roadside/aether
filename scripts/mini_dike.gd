extends Control
## Minijáték: Gátőr. Egy tengerparti város hat házát kell megvédeni 2100-ig. A tengerszint 1900 és 2019
## között valódi mérés (US EPA: CSIRO, NOAA); 2020-ban a játékos választ: alacsony vagy nagyon magas
## kibocsátás, utána a görbe az IPCC AR6 valószínű tartományának közepéig nő (adatok/tengerszint_gat.json).
## A viharok látható módon közelednek; a játékos érméből emelheti a gátat (tartósan) vagy rakhat
## homokzsákot (csak az aktuális viharra). Végül kipróbálhatja a másik utat is.
## Játékszabály: a 2020 utáni görbe alakja, a viharok ideje és magassága, a gát, az érmék, az emelés
## és a homokzsák mérete, a házak száma.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const Y_START := 1900
const Y_END := 2100
const PAST_SECONDS := 4.5     # játékszabály: a múlt (1900–2019) ennyi idő alatt fut le
const FUTURE_SPEED := 0.3     # játékszabály: másodperc / év 2020 után
const WARN := 2.2             # játékszabály: ennyi idő alatt ér oda a hullám, ha a gát elég magas (mp; közben áll az idő)
const WARN_RISK := 7.0        # játékszabály: ennyi, ha a víz átcsapna: van idő olvasni és dönteni
const DIKE0 := 105.0          # játékszabály: a gát kezdeti magassága (cm)
const RAISE := 10.0           # játékszabály: egy tartós emelés (cm)
const RAISE_COST := 3         # játékszabály: érme
const BAG := 25.0             # játékszabály: homokzsák egy viharra (cm)
const BAG_COST := 1
const COIN_YEARS := 5         # játékszabály: ötévente egy érme 2020-tól
const HOUSES := 6
const PX_CM := 2.1
const SEA0_Y := 720.0         # a 0 cm szint a jeleneten (az 1995–2014-es átlag)
const DIKE_X := 560.0
const PATHS := ["SSP1-2.6", "SSP5-8.5"]

var data_path := "res://adatok/tengerszint_gat.json"
var auto := false             # próbafutás: magától emel, homokzsákol és választ
var auto_path := 1
var done_t := -1.0            # a befejezés óta eltelt idő; < 0 = még tart
var obs := {}
var ranges := {}
var ipcc := {}
var source := ""
var source2 := ""
var year := float(Y_START)
var path := -1
var dike := DIKE0
var coins := 0
var houses := HOUSES
var floods := 0
var storms: Array = []        # [év, hullám cm, megtörtént]
var results := {}             # pálya -> megmaradt házak (a „másik út” összevetéshez)
var _past_t := 0.0
var _storm := -1              # a közeledő vihar indexe
var _storm_t := 0.0           # a közeledő hullám útja, 0–1
var _bag := false             # homokzsák a mostani viharra
var _hit_t := -10.0
var _hit_flood := false
var _hit_h := 0.0
var _last_coin_year := 0
var _t := 0.0
var _info: Label
var _read: Label
var _warn: Label
var _raise_btn: Button
var _bag_btn: Button
var _choice: VBoxContainer
var _end: VBoxContainer
var _other_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var y := 2022.0
	while y < Y_END:      # játékszabály: viharok 2020 után, 4–8 évente, 55–100 cm-es hullámmal
		storms.append([y, rng.randf_range(55.0, 100.0), false])
		y += rng.randf_range(4.0, 8.0)
	var title := UI.heading(L.t("Gátőr"), 34)
	title.position = Vector2(60, 24)
	add_child(title)
	_info = UI.label(L.t("Először nézd, hogyan emelkedett a tenger 1900 óta! 2020-tól jönnek a viharok: védd meg a város hat házát."), 18, UI.SOFT)
	_info.position = Vector2(60, 76)
	_info.size = Vector2(960, 56)
	add_child(_info)
	_read = UI.label("", 16, UI.CYAN, true, false)
	_read.position = Vector2(1066, 34)
	add_child(_read)
	_warn = UI.label("", 22, UI.EMBER, true, false)
	_warn.position = Vector2(60, 214)
	add_child(_warn)
	_raise_btn = UI.button(L.t("Gát emelése: +%d cm (%d érme)") % [int(RAISE), RAISE_COST], true)
	_raise_btn.position = Vector2(60, 150)
	_raise_btn.pressed.connect(_raise)
	add_child(_raise_btn)
	_bag_btn = UI.button(L.t("Homokzsák erre a viharra: +%d cm (%d érme)") % [int(BAG), BAG_COST], false)
	_bag_btn.position = Vector2(420, 150)
	_bag_btn.pressed.connect(_sandbag)
	add_child(_bag_btn)
	_choice = UI.vbox(12)
	_choice.position = Vector2(200, 300)
	_choice.visible = false
	_choice.add_child(UI.label(L.t("2020 van. Hogyan folytatta szerinted a világ?"), 22, UI.GOLD, true, false))
	var b0 := UI.button(L.t("Gyorsan csökkentjük a kibocsátást"), true)
	b0.pressed.connect(func() -> void: _choose(0))
	var b1 := UI.button(L.t("Egyre több szenet, olajat és gázt égetünk"), true)
	b1.pressed.connect(func() -> void: _choose(1))
	_choice.add_child(b0)
	_choice.add_child(b1)
	add_child(_choice)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(60, 138)
	_end.size = Vector2(980, 400)
	_end.visible = false
	add_child(_end)
	_update_ui()
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


func ok() -> bool:
	return obs.size() > 100 and ranges.has("SSP1-2.6") and ranges.has("SSP5-8.5") and storms.size() > 8


## A tengerszint (cm): 2019-ig mérés, utána a választott pálya (a görbe alakja játékszabály).
func sea_at(y: float) -> float:
	var s2019 := float(obs.get(2019, 0.0))
	if y <= 2019.0:
		var a := int(floor(y))
		var b := mini(a + 1, 2019)
		return lerpf(float(obs.get(a, 0.0)), float(obs.get(b, 0.0)), y - a)
	if path < 0:
		return s2019
	var r: Array = ranges[PATHS[path]]
	var target := (float(r[0]) + float(r[1])) * 50.0      # a valószínű tartomány közepe, cm
	var f := clampf((y - 2019.0) / (Y_END - 2019.0), 0.0, 1.0)
	return s2019 + (target - s2019) * pow(f, 1.4)


func _update_ui() -> void:
	_read.text = L.t("%d    Tenger: %s cm    Gát: %s cm    Érme: %d    Ház: %d") % [int(year), L.num(sea_at(year), 0), L.num(dike, 0), coins, houses]
	var future := year >= 2020.0 and path >= 0 and done_t < 0.0
	_raise_btn.visible = future
	_bag_btn.visible = future
	_raise_btn.disabled = coins < RAISE_COST
	_bag_btn.disabled = coins < BAG_COST or _storm < 0 or _bag
	if _storm >= 0:
		var s: Array = storms[_storm]
		var water := sea_at(year) + float(s[1])
		var wall := dike + (BAG if _bag else 0.0)
		_warn.text = L.t("Vihar közeleg! Hullám: +%s cm. A víz eléri: %s cm, a gát: %s cm.") % [L.num(float(s[1]), 0), L.num(water, 0), L.num(wall, 0)]
		_warn.add_theme_color_override("font_color", UI.EMBER if _over(water, wall) else UI.GREEN)
	else:
		_warn.text = ""


func _raise() -> void:
	if coins < RAISE_COST or done_t >= 0.0 or path < 0:
		return
	coins -= RAISE_COST
	dike += RAISE
	_update_ui()


func _sandbag() -> void:
	if coins < BAG_COST or _storm < 0 or _bag or done_t >= 0.0:
		return
	coins -= BAG_COST
	_bag = true
	_update_ui()


func _choose(i: int) -> void:
	if path >= 0:
		return
	path = i
	_choice.visible = false
	_info.text = L.t("Ötévente kapsz egy érmét. A gátemelés tartós, de drága; a homokzsák olcsó, de csak egy viharra jó. Figyeld, mekkora a közeledő hullám!")
	coins = 1
	_last_coin_year = 2020
	_update_ui()
	grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			finished.emit(done_t >= 0.0)
		elif event.keycode in [KEY_UP, KEY_E]:
			get_viewport().set_input_as_handled()
			_raise()
		elif event.keycode in [KEY_SPACE, KEY_H]:
			get_viewport().set_input_as_handled()
			_sandbag()


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
		queue_redraw()
		return
	if path < 0:
		if year < 2020.0:      # a múlt gyorsan lefut, közben nincs teendő
			_past_t += delta
			year = lerpf(float(Y_START), 2020.0, clampf(_past_t / PAST_SECONDS, 0.0, 1.0))
		else:
			_choice.visible = true
			if auto:
				_choose(auto_path)
		_update_ui()
		queue_redraw()
		return
	if _storm >= 0:      # közeledő vihar: az idő áll, amíg a hullám odaér
		if auto:
			_auto_decide()
		var w := sea_at(year) + float(storms[_storm][1])
		_storm_t += delta / (WARN_RISK if _over(w, dike + (BAG if _bag else 0.0)) and not auto else WARN)
		if _storm_t >= 1.0:
			_hit()
		_update_ui()
		queue_redraw()
		return
	year = minf(year + delta / FUTURE_SPEED, float(Y_END))
	while int(year) >= _last_coin_year + COIN_YEARS:
		_last_coin_year += COIN_YEARS
		coins += 1
	for i in storms.size():
		if not bool(storms[i][2]) and float(storms[i][0]) <= year:
			_storm = i
			_storm_t = 0.0
			_bag = false
			break
	if auto and _storm < 0 and coins >= RAISE_COST and sea_at(year + 12.0) + 95.0 > dike:
		_raise()
	_update_ui()
	if year >= Y_END and _storm < 0:
		_finish()
	queue_redraw()


## A próbafutás döntése a közeledő viharnál.
func _auto_decide() -> void:
	var water := sea_at(year) + float(storms[_storm][1])
	if _over(water, dike) and not _bag and not _over(water, dike + BAG):
		_sandbag()


func _hit() -> void:
	var s: Array = storms[_storm]
	s[2] = true
	var water := sea_at(year) + float(s[1])
	_hit_flood = _over(water, dike + (BAG if _bag else 0.0))
	_hit_t = _t
	_hit_h = float(s[1])
	if _hit_flood:
		floods += 1
		houses = maxi(houses - 1, 0)
	_storm = -1
	_bag = false


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	results[PATHS[path]] = houses
	_info.visible = false
	_warn.text = ""
	_raise_btn.visible = false
	_bag_btn.visible = false
	var r0: Array = ranges.get("SSP1-2.6", [0, 0])
	var r1: Array = ranges.get("SSP5-8.5", [0, 0])
	var rate: Dictionary = ipcc.get("utem_mm_ev", {})
	for c in _end.get_children():
		c.queue_free()
	_end.visible = true
	_end.add_child(UI.label(L.t("Megmaradt házak: %d / %d") % [houses, HOUSES], 24, UI.CYAN, true))
	if results.size() == 2:
		_end.add_child(UI.label(L.t("Gyors kibocsátáscsökkentéssel: %d ház. Egyre több fosszilis energiával: %d ház.") % [int(results["SSP1-2.6"]), int(results["SSP5-8.5"])], 19, UI.GOLD, true))
	_end.add_child(UI.label(L.t("A tenger 1901 és 2018 között kb. %s cm-t emelkedett, és egyre gyorsabban: 2006 és 2018 között évente kb. %s mm-t.") % [L.num(float(ipcc.get("emelkedes_1901_2018_m", 0.0)) * 100.0, 0), L.num(float(rate.get("2006-2018", 0.0)), 1)], 17, UI.TEXT))
	_end.add_child(UI.label(L.t("2100-ra: alacsony kibocsátással %s–%s cm, nagyon magassal %s–%s cm lesz az emelkedés mértéke (az 1995–2014-es szinthez képest).") % [L.num(float(r0[0]) * 100.0, 0), L.num(float(r0[1]) * 100.0, 0), L.num(float(r1[0]) * 100.0, 0), L.num(float(r1[1]) * 100.0, 0)], 17, UI.TEXT, true))
	_end.add_child(UI.label(L.t("A régen százévente egyszer előforduló magas vízállás 2100-ra a mérőhelyek több mint felén legalább évente egyszer elő fog fordulni."), 17, UI.TEXT))
	_end.add_child(UI.label(L.t("A gát időt ad, de a tenger 2100 után is emelkedni fog. A kibocsátás csökkentése lassítja ezt."), 17, UI.GOLD, true))
	_end.add_child(UI.label(L.t("Forrás: %s; %s") % [source, source2], 12, UI.MUTE))
	var row := UI.hbox(16)
	if results.size() < 2:
		_other_btn = UI.button(L.t("Próbáld ki a másik úton is!"), false)
		_other_btn.pressed.connect(_other)
		row.add_child(_other_btn)
	var b := UI.button(L.t("Tovább") + " →", true)
	b.pressed.connect(func() -> void: finished.emit(true))
	row.add_child(b)
	_end.add_child(row)


## Újra 2020-tól, a másik kibocsátási úton (a múlt nem fut le újra).
func _other() -> void:
	var p := 1 - path
	for s in storms:
		s[2] = false
	year = 2020.0
	dike = DIKE0
	houses = HOUSES
	floods = 0
	_storm = -1
	_bag = false
	done_t = -1.0
	_end.visible = false
	_info.visible = true
	path = -1
	_choose(p)
	queue_redraw()


## Átcsap-e a víz a gáton? Egész centiméterre kerekítve, ahogy a kiírás mutatja.
func _over(water: float, wall: float) -> bool:
	return roundf(water) > roundf(wall)


func _cy(cm: float) -> float:
	return SEA0_Y - cm * PX_CM


func _draw() -> void:
	var font := get_theme_default_font()
	for i in 40:
		var f := i / 39.0
		draw_rect(Rect2(0, f * H, 1040, H / 39.0 + 1.0), Color("#0d1a33").lerp(Color("#36557f"), f))
	draw_rect(Rect2(1040, 0, W - 1040, H), Color("#0b1324"))
	var sea := sea_at(year)
	# --- a közeledő vihar hulláma: balról jön a gát felé ---
	var wave_h := 0.0
	var wave_x := -200.0
	if _storm >= 0:
		wave_h = float(storms[_storm][1])
		wave_x = lerpf(-120.0, DIKE_X - 70.0, clampf(_storm_t, 0.0, 1.0))
	var hit_a := _t - _hit_t
	if hit_a < 1.0 and _storm < 0:
		wave_h = _hit_h * (1.0 - hit_a)
		wave_x = DIKE_X - 70.0
	var top := _cy(sea)
	var pts := PackedVector2Array()
	for k in 57:
		var x := DIKE_X * k / 56.0
		var bump := wave_h * exp(-pow((x - wave_x) / 90.0, 2.0))
		pts.append(Vector2(x, top - bump * PX_CM + sin(_t * 2.0 + x * 0.03) * 4.0))
	pts.append(Vector2(DIKE_X, H))
	pts.append(Vector2(0, H))
	draw_colored_polygon(pts, Color("#1f5f8b"))
	if _storm >= 0:
		draw_string(font, Vector2(wave_x - 70.0, top - wave_h * PX_CM - 16.0), L.t("vihar: +%s cm") % L.num(wave_h, 0), HORIZONTAL_ALIGNMENT_CENTER, 140, 17, UI.TEXT)
	# --- part és házak ---
	draw_colored_polygon(PackedVector2Array([Vector2(DIKE_X, _cy(10.0)), Vector2(1040, _cy(10.0)), Vector2(1040, H), Vector2(DIKE_X, H)]), Color("#4a5a3c"))
	for h in HOUSES:
		var hx := 630.0 + h * 66.0
		var hh := 46.0 + (h % 3) * 14.0
		var gone := h >= houses
		var base := _cy(10.0)
		if gone:      # elöntött ház: romok
			draw_rect(Rect2(hx, base - 14.0, 44, 14), Color("#5a5048"))
			continue
		draw_rect(Rect2(hx, base - hh, 44, hh), Color("#c9b79c"))
		draw_colored_polygon(PackedVector2Array([Vector2(hx - 4, base - hh), Vector2(hx + 22, base - hh - 22), Vector2(hx + 48, base - hh)]), Color("#8a4b3a"))
		draw_rect(Rect2(hx + 14, base - hh + 12, 14, 12), Color("#f1c873"))
	if hit_a < 2.0 and _hit_flood:      # áradás a városban
		var lvl := 50.0 * sin(clampf(hit_a / 2.0, 0.0, 1.0) * PI)
		draw_rect(Rect2(DIKE_X, _cy(10.0) - lvl, 1040 - DIKE_X, lvl + 4.0), Color(0.2, 0.45, 0.7, 0.75))
		draw_string(font, Vector2(700, _cy(10.0) - 130.0), L.t("Elöntötte a víz!"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.EMBER)
	elif hit_a < 1.4:
		draw_string(font, Vector2(700, _cy(10.0) - 130.0), L.t("A gát kitartott!"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.GREEN)
	# --- a gát és a homokzsák ---
	var dy := _cy(dike)
	draw_colored_polygon(PackedVector2Array([Vector2(DIKE_X - 40.0, _cy(-40.0)), Vector2(DIKE_X - 8.0, dy), Vector2(DIKE_X + 14.0, dy), Vector2(DIKE_X + 40.0, _cy(10.0)), Vector2(DIKE_X + 40.0, H), Vector2(DIKE_X - 40.0, H)]), Color("#7c7466"))
	if _bag:
		for k in 3:
			draw_rect(Rect2(DIKE_X - 10.0, dy - (k + 1) * BAG * PX_CM / 3.0, 26, BAG * PX_CM / 3.0 - 2.0), Color("#c2a26a"))
	draw_line(Vector2(DIKE_X - 8.0, dy), Vector2(DIKE_X + 14.0, dy), UI.GOLD, 3.0)
	draw_string(font, Vector2(DIKE_X - 80.0, dy - 10.0 - (BAG * PX_CM if _bag else 0.0)), L.t("gát") + " " + L.num(dike + (BAG if _bag else 0.0), 0) + " cm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.GOLD)
	if _storm >= 0:      # a várható vízszint jele a gáton
		var wy := _cy(sea + wave_h)
		draw_dashed_line(Vector2(DIKE_X - 60.0, wy), Vector2(DIKE_X + 60.0, wy), UI.EMBER, 2.0, 6.0)
	draw_string(font, Vector2(20, top - 12.0), L.t("tenger") + " " + L.num(sea, 0) + " cm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.TEXT)
	draw_string(font, Vector2(860, 330), str(int(year)), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(UI.TEXT, 0.9))
	for c in coins:      # érmék
		draw_circle(Vector2(880.0 + (c % 8) * 20.0, 360.0 + floorf(c / 8.0) * 20.0), 7.0, UI.GOLD)
	if done_t >= 0.0:
		draw_rect(Rect2(40, 124, 1000, 330), Color(0.043, 0.063, 0.114, 0.92 * clampf(done_t / 0.8, 0.0, 1.0)))
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
	if path >= 0:
		for i in 2:
			var r: Array = ranges[PATHS[i]]
			var col := UI.GREEN if i == 0 else UI.EMBER
			var bx: float = gx.call(2100.0) - 10.0 + i * 12.0
			draw_line(Vector2(bx, gy.call(float(r[0]) * 100.0)), Vector2(bx, gy.call(float(r[1]) * 100.0)), Color(col, 0.9 if i == path else 0.35), 6.0)
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
