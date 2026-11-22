extends Node
## Kezdőanimáció (kb. 40 mp), minden indításkor. Esc, szóköz, Enter vagy kattintás átugorja.
##   0–5   napfelkelte a Föld pereme mögül
##   5–13  a forgó földgömb és az évszámláló: a VALÓDI éves hőmérséklet-eltérés
##         (Copernicus Climate Pulse, ERA5); ha még nincs letöltve, számok nélkül megy
##   13–21 négy festett pixeles kép: olvadó jég, aszály, árvíz, erdőtűz (illusztrációk)
##   21–30 a kutatóállomás: kigyulladnak a fények, cikkek repülnek be, zöld pipák
##   30–36 a görbe elágazik: a jövő még nincs megírva (a jövő vonalai jelképek, nem előrejelzés)
##   36–40 az AETHER felirat, majd áttűnés a játékra
## Minden kép az időből (_t) számolódik, ezért bárhol megszakítható.
## A zenét a tools/intro_zene.py állítja elő (saját, handpan hangzású dallam).

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Globe := preload("res://scripts/globe.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")
const Station := preload("res://scripts/station_panel.gd")
const MAIN := "res://scenes/main.tscn"
const MUSIC := "res://assets/hang/intro.wav"

const W := 1600.0
const H := 900.0
const END := 39.4                 # eddig tart; utána áttűnés a játékra
const U := 5.0                    # a festett képek egy „pixele” (320×180-as vászon)
const ST := 8.0                   # az állomáskép nagyítása (200×110 -> 1600×880)
const ST_Y := 10.0
const MODS := ["ai_mag", "archivum", "uveghaz"]
const SUN_DAY := Vector3(-0.62, -0.38, 0.69)
const PAPERS := 16

var _t := 0.0
var _done := false
var _test := false
var _layer: CanvasLayer
var _bg: Control
var _globe
var _station: Control
var _mod_rects: Array = []        # [[TextureRect 1. szint, 2. szint, 3. szint], ...]
var _mod_blink: Control
var _fx: Control
var _music: AudioStreamPlayer
var _nebula: Texture2D
var _years: Array = []            # [[év, eltérés], ...] valódi adat; üres, ha még nincs letöltve
var _pre_industrial := false      # az eltérés az iparosodás előtti szinthez képest értendő-e
var _vmin := 0.0
var _vmax := 1.0
var _year_now := 2026


static func pulse_path() -> String:
	return OS.get_user_data_dir().path_join("aether_vilag").path_join("pulse_levego.json")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_test = "--introteszt" in args
	if "--onteszt" in args and not _test:      # az önteszt egyből a játékkal indul
		get_tree().change_scene_to_file.call_deferred(MAIN)
		return
	L.init()
	UI.load_fonts()
	_year_now = int(Time.get_date_dict_from_system()["year"])
	_load_data()
	ResourceLoader.load_threaded_request(MAIN)
	_nebula = load("res://assets/nebula_bg.png")

	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	_bg = _canvas(_draw_bg)
	_globe = Globe.new()
	_globe.real_sun = false
	_globe.spin_speed = 0.02
	_globe.spin = -0.17
	_layer.add_child(_globe)
	_globe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_station()
	_fx = _canvas(_draw_fx)
	_fx.mouse_filter = Control.MOUSE_FILTER_STOP

	if ResourceLoader.exists(MUSIC):
		_music = AudioStreamPlayer.new()
		_music.stream = load(MUSIC)
		_music.volume_db = -3.0
		add_child(_music)
		_music.play()
	if _test:
		_run_test()
	_apply()


func _canvas(draw_fn: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(draw_fn)
	_layer.add_child(c)
	return c


## A valódi éves eltérések a gépen lévő (legfeljebb napi) Climate Pulse-adatból.
## Ha nincs vagy régi, a háttérben letöltjük: a következő indításkor már ebből megy.
func _load_data() -> void:
	var path := pulse_path()
	var d: Variant = Bridge.read_json(path)
	if typeof(d) == TYPE_DICTIONARY and typeof(d.get("evente")) == TYPE_ARRAY:
		var rows: Array = d["evente"]
		_pre_industrial = not rows.is_empty() and rows.all(func(r: Variant) -> bool: return r[2] != null)
		for r in rows:
			_years.append([int(r[0]), float(r[2] if _pre_industrial else r[1])])
		if _years.size() < 10:
			_years.clear()
	if not _years.is_empty():
		_vmin = _years[0][1]
		_vmax = _years[0][1]
		for y in _years:
			_vmin = minf(_vmin, y[1])
			_vmax = maxf(_vmax, y[1])
	var age := INF
	if FileAccess.file_exists(path):
		age = Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(path))
	if age > 86400.0 and not _test:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var b = Bridge.new()
		get_tree().root.add_child.call_deferred(b)
		var start := func() -> void: b.run("pulse", ["pulse", "--ki", path])
		start.call_deferred()
		b.finished.connect(func(_tag: String, _code: int, _out: String) -> void: b.queue_free())


func _build_station() -> void:
	_station = Control.new()
	_station.size = Vector2(W, H)
	_station.pivot_offset = Vector2(W * 0.5, 520)
	_station.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_station.visible = false
	_layer.add_child(_station)
	var black := ColorRect.new()
	black.color = Color("#070b16")
	black.size = Vector2(W, H)
	_station.add_child(black)
	var bg: Texture2D = load("res://assets/allomas/hatter.png")
	_station.add_child(_sprite(bg, Vector2(0, ST_Y)))
	var blink = Station.Blink.new()
	blink.scale_px = int(ST)
	blink.position = Vector2(0, ST_Y)
	blink.add_light(Vector2(12, 69), Color("#ffd97a"), 0.6)
	blink.add_light(Vector2(188, 69), Color("#ffd97a"), 0.7)
	for x in range(20, 182, 12):
		blink.add_light(Vector2(x, 87), Color("#f4c85a"), 1.5 + float(x % 5) * 0.3)
	for mod in MODS:
		var levels: Array = []
		for lvl in [1, 2, 3]:
			var spr := _sprite(load("res://assets/allomas/%s_%d.png" % [mod, lvl]), Station.POS[mod] * ST + Vector2(0, ST_Y))
			spr.modulate.a = 0.0
			_station.add_child(spr)
			levels.append(spr)
		_mod_rects.append(levels)
	blink.size = Vector2(W, H)
	_station.add_child(blink)
	_mod_blink = Station.Blink.new()      # a kész (3. szintű) modulok pislákoló fényei
	_mod_blink.scale_px = int(ST)
	_mod_blink.position = Vector2(0, ST_Y)
	_mod_blink.size = Vector2(W, H)
	for mod in MODS:
		_mod_blink.add_from_texture(load("res://assets/allomas/%s_3.png" % mod), Station.POS[mod], mod == "uveghaz")
	_mod_blink.modulate.a = 0.0
	_station.add_child(_mod_blink)
	# a játék címe elrejtve: kis tábla az ösvény mellett
	var sign := Control.new()
	sign.position = Vector2(113 * ST, 95 * ST + ST_Y)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.draw.connect(func() -> void:
		sign.draw_rect(Rect2(40, 30, 8, 34), Color("#3a2c20"))
		sign.draw_rect(Rect2(0, 0, 88, 32), Color("#1c2740"))
		sign.draw_rect(Rect2(0, 0, 88, 32), Color("#5c7098"), false, 2.0)
		sign.draw_string(UI.font_pixel, Vector2(0, 23), "AETHER", HORIZONTAL_ALIGNMENT_CENTER, 88, 19, UI.GOLD))
	_station.add_child(sign)


func _sprite(tex: Texture2D, pos: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = pos
	t.size = Vector2(tex.get_width(), tex.get_height()) * ST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _input(ev: InputEvent) -> void:
	if _done or _layer == null:
		return
	var skip := false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		skip = ev.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	elif ev is InputEventMouseButton and ev.pressed:
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_finish(0.5)


func _process(delta: float) -> void:
	if _layer == null:
		return
	_t += delta
	if not _done:
		_apply()
		if _t >= END:
			_finish(1.0)
	_bg.queue_redraw()
	_fx.queue_redraw()


## A jelenet végén (vagy átugráskor) a játék betöltődik az animáció alá, az pedig elhalványul.
func _finish(fade: float) -> void:
	if _done:
		return
	_done = true
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var main: Node = (ResourceLoader.load_threaded_get(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	var holder := Control.new()            # a CanvasLayer nem halványítható: a tartalmát halványítjuk
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(holder)
	for c in [_bg, _globe, _station, _fx]:
		c.reparent(holder)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(holder, "modulate:a", 0.0, fade)
	if _music != null:
		tw.tween_property(_music, "volume_db", -50.0, fade + 0.6)
	tw.chain().tween_callback(queue_free)


# --- segédek ---------------------------------------------------------------
static func _h(i: float) -> float:
	return fposmod(sin(i * 127.1 + 311.7) * 43758.5453, 1.0)


static func _ss(a: float, b: float, x: float) -> float:
	var k := clampf((x - a) / (b - a), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## 0 a jeleneten kívül, 1 belül; a széleken `f` mp alatt úszik be és ki.
func _win(a: float, b: float, f: float = 0.4) -> float:
	return _ss(a, a + f, _t) * (1.0 - _ss(b - f, b, _t))


func _year_pos() -> float:
	return _ss(6.3, 12.3, _t) if _t < 30.0 else 1.0


func _value_at(pos: float) -> float:
	var fi := pos * float(_years.size() - 1)
	var i := int(fi)
	var j := mini(i + 1, _years.size() - 1)
	return lerpf(_years[i][1], _years[j][1], fi - float(i))


func _norm(v: float) -> float:
	return clampf((v - _vmin) / maxf(_vmax - _vmin, 0.001), 0.0, 1.0)


## Előjeles szám két tizedessel, a nyelv tizedesjelével (+0,60).
static func _signed(v: float) -> String:
	var s := ("%+.2f" % v)
	return s if L.is_en() else s.replace(".", ",")


static func _stripe(n: float) -> Color:
	if n < 0.5:
		return Color("#2f6fd0").lerp(Color("#e9edf2"), n * 2.0)
	return Color("#e9edf2").lerp(Color("#d2342a"), (n - 0.5) * 2.0)


# --- a jelenetek állapota az időből ------------------------------------------
func _apply() -> void:
	var t := _t
	# földgömb: lentről (napfelkelte) középre, a végén halványan a felirat mögött
	var k := _ss(4.6, 6.6, t)
	var gsize := lerpf(1700.0, 720.0, k)
	var center := Vector2(W * 0.5, lerpf(1330.0, 450.0, k))
	_globe.size = Vector2(gsize, gsize)
	_globe.position = center - _globe.size * 0.5
	var e := lerpf(0.10, 1.0, _ss(0.3, 5.0, t))
	var rise := Vector3(0.22, -sin(e), -cos(e) * 0.9).normalized()
	_globe._mat.set_shader_parameter("sun_dir", rise.lerp(SUN_DAY, k).normalized())
	_globe.visible = t < 13.0 or t >= 30.0
	var warm := 0.75 * (_norm(_value_at(_year_pos())) if not _years.is_empty() else _year_pos())
	_globe.heat = warm * (1.0 - _ss(32.5, 36.0, t)) if t > 5.0 else 0.0
	var dim := 1.0
	if t >= 30.0:
		dim = lerpf(0.42, 0.26, _ss(35.6, 36.6, t))
	_globe.modulate = Color(dim, dim, dim)
	# kutatóállomás: lassú közelítés, a modulok szintenként kigyulladnak
	_station.visible = t >= 21.0 and t < 30.0
	if _station.visible:
		var z := lerpf(1.0, 1.10, (t - 21.0) / 9.0)
		_station.scale = Vector2(z, z)
		for m in _mod_rects.size():
			for lvl in 3:
				var at := 21.3 + 2.1 * lvl + 0.35 * m
				_mod_rects[m][lvl].modulate.a = _ss(at, at + 0.7, t)
		_mod_blink.modulate.a = _ss(26.6, 27.4, t)


# --- háttér: csillagok, köd, a felkelő Nap ----------------------------------
func _draw_bg() -> void:
	var c := _bg
	c.draw_rect(Rect2(0, 0, W, H), Color("#04060d"))
	if _nebula != null:
		c.draw_texture_rect(_nebula, Rect2(0, 0, W, H), false, Color(1, 1, 1, 0.35 * _ss(0.0, 3.0, _t)))
	for i in 150:
		var p := Vector2(_h(i) * W, _h(i + 500.0) * H)
		var tw := 0.55 + 0.45 * sin(_t * (0.6 + _h(i + 900.0) * 2.0) + i)
		var s := 2.0 if _h(i + 77.0) < 0.8 else 4.0
		c.draw_rect(Rect2(p.snappedf(2.0), Vector2(s, s)), Color(0.85, 0.92, 1.0, tw * 0.8 * _ss(0.0, 1.5, _t)))
	if _t < 7.0:        # a Nap a Föld pereme mögül bukkan elő
		var up := _ss(0.6, 5.0, _t)
		var a := (1.0 - _ss(4.8, 6.6, _t)) * _ss(0.4, 1.6, _t)
		var sp := Vector2(W * 0.5 + 90.0, lerpf(640.0, 548.0, up))
		for r in [420.0, 300.0, 210.0, 140.0, 90.0, 56.0]:
			c.draw_circle(sp, r * (0.7 + 0.3 * up), Color(1.0, 0.82, 0.45, 0.07 * a))
		c.draw_circle(sp, 34.0, Color(1.0, 0.96, 0.82, a))
		for i in 12:    # pixeles sugarak
			var ang := TAU * i / 12.0 + _t * 0.05
			var len := (150.0 + 60.0 * sin(_t * 1.3 + i)) * up
			c.draw_line(sp + Vector2.from_angle(ang) * 46.0, sp + Vector2.from_angle(ang) * (46.0 + len), Color(1.0, 0.86, 0.5, 0.22 * a), 4.0)


# --- előtér ------------------------------------------------------------------
func _draw_fx() -> void:
	var t := _t
	if t >= 5.0 and t < 13.4:
		_draw_counter()
	if t >= 13.0 and t < 21.0:
		var idx := int((t - 13.0) / 2.0)
		var lt := fmod(t - 13.0, 2.0)
		[_scene_ice, _scene_drought, _scene_flood, _scene_fire][idx].call(lt)
		_fx.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, 0.75 * (1.0 - _ss(0.0, 0.16, lt))))
	if t >= 21.0 and t < 30.0:
		_draw_papers()
	if t >= 30.0 and t < 36.4:
		_draw_future()
	if t >= 36.0:
		_draw_title()
	# rövid sötét áttűnések a nagy váltásoknál
	for cut in [13.0, 21.0, 30.0]:
		var d := absf(t - cut)
		if d < 0.3:
			_fx.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 1.0 - d / 0.3))
	_caption(L.t("Föld, %d.") % _year_now, 300.0, _win(1.4, 4.7, 0.7))
	_caption(L.t("Egyre melegebb."), 852.0, _win(7.2, 12.8, 0.6))
	_caption(L.t("A jövő még nincs megírva."), 800.0, _win(32.2, 35.9, 0.7))
	var hint := 0.75 * (1.0 - _ss(END - 1.0, END, t))
	_fx.draw_string(UI.font_body, Vector2(W - 420.0, H - 18.0), L.t("Esc: átugrás"), HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 17, Color(UI.MUTE, hint))


func _caption(text: String, y: float, a: float) -> void:
	if a <= 0.01:
		return
	var pos := Vector2(0, y)
	_fx.draw_string_outline(UI.font_bold, pos, text, HORIZONTAL_ALIGNMENT_CENTER, W, 40, 10, Color(0.02, 0.03, 0.07, a))
	_fx.draw_string(UI.font_bold, pos, text, HORIZONTAL_ALIGNMENT_CENTER, W, 40, Color(UI.TEXT, a))


## Évszámláló a valódi éves eltéréssel, alul a „melegedési csíkok” (minden év egy csík).
func _draw_counter() -> void:
	if _years.is_empty():
		return
	var a := _win(6.0, 13.2, 0.5)
	var pos := _year_pos()
	var n := _years.size()
	var idx := int(round(pos * float(n - 1)))
	var year: int = _years[idx][0]
	var v: float = _years[idx][1]
	var x := 1190.0
	_fx.draw_string(UI.font_bold, Vector2(x, 400.0), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1, 112, Color(UI.TEXT, a))
	var col := UI.EMBER if v > 0.0 else Color("#7fb2ff")
	_fx.draw_string(UI.font_bold, Vector2(x, 480.0), _signed(v) + " °C", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, Color(col, a))
	var basis := L.t("az iparosodás előtti szinthez képest") if _pre_industrial else L.t("az 1991–2020-as átlaghoz képest")
	_fx.draw_string(UI.font_body, Vector2(x, 520.0), basis, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UI.SOFT, a))
	_fx.draw_string(UI.font_body, Vector2(x, 548.0), L.t("Adat: Copernicus Climate Pulse"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UI.MUTE, a))
	var bw := W / float(n)
	for i in idx + 1:
		_fx.draw_rect(Rect2(floorf(i * bw), H - 26.0, ceilf(bw) + 1.0, 26.0), Color(_stripe(_norm(_years[i][1])), a))


# --- négy festett pixeles kép (320×180-as vászon, illusztrációk) --------------
func _r(x: float, y: float, w: float, h: float, col: Color) -> void:
	_fx.draw_rect(Rect2(roundf(x) * U, roundf(y) * U, roundf(w) * U, roundf(h) * U), col)


func _bands(cols: Array, y0: float, y1: float) -> void:
	var bh := (y1 - y0) / float(cols.size())
	for i in cols.size():
		_r(0, y0 + i * bh, 320, bh + 1.0, Color(cols[i]))


func _scene_ice(lt: float) -> void:
	_bands(["#9fd0ea", "#b4dcf0", "#c8e7f5", "#dbf0f8", "#ecf7fb"], 0, 96)
	# távoli jéghegyek
	for x in range(0, 320, 4):
		var hh := 14.0 + 10.0 * sin(x * 0.045) + 6.0 * sin(x * 0.13 + 1.0)
		_r(x, 96 - hh, 4, hh, Color("#cfe6f2"))
		_r(x, 96 - hh, 4, 2, Color("#f4fbff"))
	# tenger
	_bands(["#2a6f8f", "#236585", "#1d5a7a", "#184f6e", "#134461"], 96, 180)
	for i in 46:
		var wx := fposmod(_h(i) * 340.0 + lt * (4.0 + _h(i + 9.0) * 6.0), 340.0) - 10.0
		_r(wx, 100.0 + _h(i + 50.0) * 78.0, 5.0 + _h(i + 3.0) * 9.0, 1, Color(0.75, 0.92, 1.0, 0.35))
	# a gleccser fala balra
	for x in range(0, 136, 4):
		var top := 34.0 + 7.0 * sin(x * 0.09) + 4.0 * sin(x * 0.31) + x * 0.07
		_r(x, top, 4, 118 - top, Color("#a9d4ea") if (x / 4) % 3 != 0 else Color("#96c6e0"))
		_r(x, top, 4, 5, Color("#ffffff"))
		_r(x, top + 5, 4, 4, Color("#e3f3fb"))
		if x % 20 == 8:
			_r(x + 1, top + 14, 1, 70 - x * 0.2, Color("#6fa9cc"))   # repedések
	for i in 7:   # olvadékvíz csorog a falon
		var dx := 10.0 + i * 17.0
		var dy := fposmod(lt * 46.0 + _h(i) * 60.0, 60.0)
		_r(dx, 52.0 + dy, 1, 5, Color("#e9fbff"))
	# leszakadó jégtömb és a csobbanás
	var fall := clampf((lt - 0.35) / 0.75, 0.0, 1.0)
	var by := lerpf(44.0, 104.0, fall * fall)
	_r(136, by, 20, 26, Color("#b9def0"))
	_r(136, by, 20, 5, Color("#ffffff"))
	_r(152, by + 5, 4, 21, Color("#8fc0dc"))
	if fall >= 1.0:
		var sp := (lt - 1.1) / 0.8
		for i in 12:
			var ax := 146.0 + (i - 5.5) * 5.0 * (0.4 + sp)
			var ay := 118.0 - sin(clampf(sp, 0.0, 1.0) * PI) * (14.0 + _h(i) * 22.0)
			_r(ax, ay, 2, 2, Color(1, 1, 1, 1.0 - clampf(sp, 0.0, 1.0)))
		_r(124, 118, 46, 2, Color(1, 1, 1, 0.7 * (1.0 - clampf(sp, 0.0, 1.0))))
	# úszó jégtáblák
	for i in 6:
		var fx := 170.0 + i * 26.0 + sin(lt * 0.8 + i) * 2.0
		var fy := 112.0 + _h(i + 20.0) * 54.0 + sin(lt * 2.0 + i * 1.7)
		var fw := 12.0 + _h(i + 30.0) * 16.0
		_r(fx, fy, fw, 3, Color("#f2fbff"))
		_r(fx + 1, fy + 3, fw - 2, 2, Color("#8fc3de"))


func _scene_drought(lt: float) -> void:
	_bands(["#e98a3a", "#f09a44", "#f5ad52", "#f8c066", "#fbd384"], 0, 104)
	var sun := Vector2(232.0, 46.0) * U
	for r in [34.0, 27.0, 21.0]:
		_fx.draw_circle(sun, (r + sin(lt * 3.0) * 1.2) * U, Color(1.0, 0.95, 0.75, 0.16))
	_fx.draw_circle(sun, 16.0 * U, Color("#fff6d8"))
	for x in range(0, 320, 4):   # távoli dombok
		var hh := 7.0 + 5.0 * sin(x * 0.03 + 2.0) + 3.0 * sin(x * 0.11)
		_r(x, 104 - hh, 4, hh, Color("#c98248"))
	_bands(["#c0793c", "#b46f36", "#a86531", "#9b5b2c"], 104, 180)
	for i in 5:   # hőség: remegő levegő a látóhatárnál
		_r(fposmod(_h(i) * 320.0 + lt * 9.0, 340.0) - 20.0, 97.0 + i * 2.0 + sin(lt * 5.0 + i), 60, 1, Color(1.0, 0.93, 0.75, 0.30))
	# repedések: a jelenet alatt terjednek
	var grow := 0.35 + 0.65 * _ss(0.0, 1.7, lt)
	for i in 15:
		var cx := _h(i) * 320.0
		var cy := 110.0 + _h(i + 40.0) * 66.0
		var steps := int((10.0 + _h(i + 80.0) * 16.0) * grow)
		for s in steps:
			cx += 3.0 if _h(i * 31.0 + floorf(s / 3.0)) > 0.5 else -3.0
			cy += 2.0
			if cy > 179.0:
				break
			_r(cx, cy, 3, 1, Color("#5d3a20"))
			_r(cx, cy + 1, 1, 1, Color("#5d3a20"))
	# kiszáradt fa
	var tr := Color("#3b2416")
	_r(64, 62, 6, 62, tr)
	_r(60, 120, 14, 4, tr)
	for b in [[70, 80, 1], [58, 72, -1], [70, 66, 1], [59, 92, -1]]:
		for s in 9:
			_r(b[0] + b[2] * s * 3.0, b[1] - s * 2.0, 3, 2, tr)
		for s in 4:
			_r(b[0] + b[2] * (14.0 + s * 2.0), b[1] - 12.0 + s * 3.0 * 0.0 - s * 3.0, 2, 3, tr)
	# elszáradt kukoricatövek
	for i in 16:
		var kx := 112.0 + i * 13.0
		var kh := 20.0 + _h(i + 5.0) * 12.0
		var lean := sin(lt * 1.5 + i) * 1.0
		var kc := Color("#7a5a2a") if i % 2 == 0 else Color("#8a6a34")
		_r(kx, 150.0 - kh, 2, kh, kc)
		_r(kx + 2.0 + lean, 150.0 - kh * 0.7, 5, 2, kc)
		_r(kx - 5.0 + lean, 150.0 - kh * 0.45, 5, 2, kc)
		_r(kx + 2.0, 150.0 - kh * 0.25, 4, 2, Color("#9a7a40"))
	for i in 30:   # szálló por
		var px := fposmod(_h(i + 200.0) * 320.0 + lt * (20.0 + _h(i) * 30.0), 320.0)
		_r(px, 120.0 + _h(i + 300.0) * 50.0 - lt * 3.0, 2, 1, Color(1.0, 0.86, 0.6, 0.45))


func _scene_flood(lt: float) -> void:
	_bands(["#2b3442", "#35404f", "#3f4b5b", "#4a5767", "#566373"], 0, 110)
	for i in 9:   # felhők
		var cx := fposmod(_h(i) * 380.0 + lt * 6.0, 380.0) - 40.0
		_r(cx, 8.0 + _h(i + 10.0) * 34.0, 46.0 + _h(i + 20.0) * 40.0, 9, Color("#242c38"))
		_r(cx + 8.0, 4.0 + _h(i + 10.0) * 34.0, 30.0 + _h(i + 20.0) * 20.0, 6, Color("#242c38"))
	var level := lerpf(152.0, 116.0, _ss(0.0, 1.9, lt))
	for x in range(0, 320, 4):   # távoli, esőbe vesző dombok
		var hh := 16.0 + 8.0 * sin(x * 0.025 + 0.5) + 4.0 * sin(x * 0.08)
		_r(x, 110 - hh, 4, hh, Color("#3a4654"))
	_r(0, 108, 320, 72, Color("#2c3a36"))
	# fák és házak
	for i in 7:
		var tx := 8.0 + i * 49.0 + _h(i) * 10.0
		_r(tx + 5.0, 96, 3, 60, Color("#1f2a26"))
		_r(tx, 84, 13, 16, Color("#24382f"))
		_r(tx + 2.0, 78, 9, 8, Color("#2b4337"))
	for i in 4:
		var hx := 28.0 + i * 76.0
		var hw := 44.0
		var wall := Color("#b9a58a") if i % 2 == 0 else Color("#a8b0a0")
		_r(hx, 112, hw, 50, wall)
		_r(hx, 112, hw, 3, wall.darkened(0.25))
		for s in 12:   # tető
			_r(hx - 4.0 + s * 2.0, 110.0 - s * 2.0, hw + 8.0 - s * 4.0, 2, Color("#7a3b30") if s % 2 == 0 else Color("#8a463a"))
		for wx2 in [6.0, 26.0]:
			var lit := _h(i * 7.0 + wx2) > 0.35
			_r(hx + wx2, 120, 10, 10, Color("#ffd97a") if lit else Color("#2a3340"))
			_r(hx + wx2 + 4.0, 120, 1, 10, wall.darkened(0.4))
		_r(hx + 16.0, 138, 9, 24, Color("#4a3426"))
	# a víz
	_r(0, level, 320, 180 - level, Color("#5b6f63"))
	_r(0, level + 14.0, 320, 180, Color("#51655b"))
	_r(0, level + 34.0, 320, 180, Color("#475a52"))
	for i in 4:   # a világos ablakok tükröződése
		for wx2 in [6.0, 26.0]:
			if _h(i * 7.0 + wx2) > 0.35:
				for s in 5:
					_r(28.0 + i * 76.0 + wx2 + sin(lt * 4.0 + s) * 1.5, level + 3.0 + s * 4.0, 10, 2, Color(1.0, 0.85, 0.48, 0.30 - s * 0.05))
	for i in 60:
		var wx := fposmod(_h(i) * 340.0 + lt * (10.0 + _h(i + 9.0) * 14.0), 340.0) - 10.0
		var wy := level + 1.0 + _h(i + 50.0) * (179.0 - level)
		_r(wx, wy, 6.0 + _h(i + 3.0) * 10.0, 1, Color(0.82, 0.90, 0.86, 0.40))
	_r(0, level, 320, 1, Color("#a9bdb0"))
	for i in 150:   # eső
		var rx := fposmod(_h(i) * 360.0 - lt * 60.0, 360.0) - 20.0
		var ry := fposmod(_h(i + 400.0) * 180.0 + lt * (190.0 + _h(i + 7.0) * 80.0), 180.0)
		_r(rx, ry, 1, 5, Color(0.80, 0.88, 1.0, 0.45))
		_r(rx - 1.0, ry + 5.0, 1, 3, Color(0.80, 0.88, 1.0, 0.30))
	var flash := maxf(0.0, 1.0 - absf(lt - 1.05) / 0.12)   # villám
	if flash > 0.0:
		_fx.draw_rect(Rect2(0, 0, W, H), Color(0.9, 0.95, 1.0, 0.55 * flash))
		var lx := 214.0
		for s in 14:
			lx += (_h(s * 3.0) - 0.5) * 12.0
			_r(lx, s * 6.0, 2, 7, Color(1, 1, 1, flash))


func _scene_fire(lt: float) -> void:
	_bands(["#120810", "#1e0b12", "#330f12", "#521610", "#7a2410", "#a83a12", "#d2561a"], 0, 124)
	for i in 14:   # füst
		var sx := fposmod(_h(i) * 360.0 + lt * 10.0, 360.0) - 30.0
		var sy := 60.0 - fposmod(_h(i + 5.0) * 70.0 + lt * 9.0, 70.0)
		_r(sx, sy, 40.0 + _h(i + 6.0) * 40.0, 10.0 + _h(i + 8.0) * 8.0, Color(0.05, 0.03, 0.05, 0.42))
	for x in range(0, 320, 4):   # domb
		var hh := 20.0 + 12.0 * sin(x * 0.02 + 1.0) + 5.0 * sin(x * 0.09)
		_r(x, 150 - hh, 4, hh + 32.0, Color("#0c0507"))
	# lángok a fák mögött
	for x in range(0, 320, 2):
		var base := 150.0 - (20.0 + 12.0 * sin(x * 0.02 + 1.0) + 5.0 * sin(x * 0.09))
		var fh := (26.0 + 16.0 * sin(x * 0.07 + lt * 7.0) + 12.0 * sin(x * 0.19 - lt * 11.0) + 8.0 * sin(x * 0.43 + lt * 17.0)) \
			* (0.55 + 0.45 * sin(x * 0.013 + 0.6))
		fh = maxf(fh, 4.0)
		_r(x, base - fh, 2, fh, Color("#c7301a"))
		_r(x, base - fh * 0.66, 2, fh * 0.66, Color("#ee7a24"))
		_r(x, base - fh * 0.34, 2, fh * 0.34, Color("#ffd65a"))
	# fenyők sziluettje
	for i in 15:
		var tx := -6.0 + i * 23.0 + _h(i) * 9.0
		var th := 46.0 + _h(i + 11.0) * 30.0
		var foot := 158.0 - 6.0 * sin(i * 0.9)
		_r(tx + 7.0, foot - th * 0.3, 3, th * 0.3 + 6.0, Color("#070304"))
		var rows := int(th * 0.8 / 3.0)
		for s in rows:
			var wd := 2.0 + (16.0 * float(s) / float(rows)) * (0.75 + 0.25 * float(s % 4) / 3.0)
			_r(tx + 8.5 - wd * 0.5, foot - th + s * 3.0, wd, 3, Color("#070304"))
	_r(0, 164, 320, 16, Color("#050203"))
	for i in 70:   # szálló parázs
		var life := fposmod(_h(i) + lt * (0.35 + _h(i + 3.0) * 0.4), 1.0)
		var ex := _h(i + 50.0) * 320.0 + sin(life * 6.0 + i) * 8.0 + life * 14.0
		_r(ex, 150.0 - life * 140.0, 1.0 + float(i % 2), 1.0 + float(i % 2), Color(1.0, 0.75 - life * 0.4, 0.25, 1.0 - life))
	_fx.draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.35, 0.1, 0.05 + 0.03 * sin(lt * 9.0)))


# --- a kutatóállomás: berepülő cikkek, zöld pipák -----------------------------
func _draw_papers() -> void:
	var z: float = _station.scale.x
	var pivot: Vector2 = _station.pivot_offset
	for i in PAPERS:
		var mod: String = MODS[i % 2]      # az AI-mag és az archívum kapja a cikkeket
		var target: Vector2 = (Station.POS[mod] + Vector2(28, 26)) * ST + Vector2(0, ST_Y)
		target = pivot + (target - pivot) * z
		var t0 := 22.0 + i * 0.42
		var p := (_t - t0) / 1.5
		if p < 0.0:
			continue
		if p < 1.0:
			var ang := -PI * (0.08 + 0.84 * _h(i + 3.0))
			var from := target + Vector2.from_angle(ang) * 1150.0
			var e := 1.0 - pow(1.0 - p, 2.2)
			var pos := from.lerp(target, e) + Vector2(0, -sin(p * PI) * 90.0)
			var sc := lerpf(1.5, 0.45, e)
			_fx.draw_set_transform(pos, (1.0 - e) * (3.0 + _h(i) * 4.0) * (1.0 if i % 2 == 0 else -1.0), Vector2(sc, sc))
			_fx.draw_rect(Rect2(-15, -20, 30, 40), Color("#eef2f8"))
			_fx.draw_rect(Rect2(-15, -20, 30, 40), Color("#8fa0bb"), false, 2.0)
			for ln in 5:
				_fx.draw_rect(Rect2(-10, -13 + ln * 7, 20 if ln % 3 != 2 else 12, 3), Color("#7c8aa3"))
			_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var q := (p - 1.0) / 0.9       # megérkezett: zöld pipa száll fel
			if q < 1.0:
				var a := 1.0 - q * q
				var c := target + Vector2((i % 4 - 1.5) * 26.0, -40.0 - q * 70.0)
				var s := 1.0 + 0.5 * maxf(0.0, 1.0 - q * 5.0)
				for w in [[12.0, Color(0.02, 0.10, 0.04, a)], [7.0, Color(UI.GREEN, a)]]:
					_fx.draw_polyline(PackedVector2Array([c + Vector2(-16, 0) * s, c + Vector2(-5, 12) * s, c + Vector2(17, -14) * s]), w[1], w[0])
				_fx.draw_circle(target, 30.0 + q * 60.0, Color(UI.GREEN, 0.18 * a))


# --- a jövő: a görbe elágazik --------------------------------------------------
func _draw_future() -> void:
	var a := _win(30.0, 36.4, 0.5)
	var x0 := 150.0
	var xn := 900.0
	var now := Vector2(xn, 420.0)
	var pts := PackedVector2Array()
	if not _years.is_empty():      # a múlt: a valódi éves eltérések
		var n := _years.size()
		var show := int(ceil(_ss(30.3, 32.3, _t) * float(n)))
		for i in show:
			pts.append(Vector2(lerpf(x0, xn, float(i) / float(n - 1)), lerpf(640.0, 420.0, _norm(_years[i][1]))))
		for i in pts.size() - 1:
			_fx.draw_line(pts[i], pts[i + 1], Color(_stripe(_norm(_years[i + 1][1])), a), 6.0)
		if show >= n:
			now = pts[n - 1]
		_fx.draw_string(UI.font_bold, Vector2(x0, 690.0), str(_years[0][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(UI.MUTE, a))
	var f := _ss(32.3, 35.2, _t)
	if f > 0.0:
		var red := PackedVector2Array()
		var green := PackedVector2Array()
		var steps := 40
		for i in int(f * steps) + 1:
			var u := float(i) / float(steps)
			var x := lerpf(now.x, 1450.0, u)
			red.append(Vector2(x, now.y - 250.0 * (0.55 * u + 0.45 * u * u)))
			green.append(Vector2(x, now.y - 70.0 * sin(u * PI * 0.5) + 150.0 * u * u))
		for i in range(0, red.size() - 1, 2):     # szaggatott: ha minden marad
			_fx.draw_line(red[i], red[i + 1], Color(UI.EMBER, 0.75 * a), 6.0)
		if green.size() > 1:
			_fx.draw_polyline(green, Color(UI.GREEN, a), 7.0)
			var head := green[green.size() - 1]
			for r in [26.0, 17.0]:
				_fx.draw_circle(head, r, Color(UI.GREEN, 0.20 * a))
			_fx.draw_circle(head, 9.0, Color(UI.GREEN, a))
	var pulse := 1.0 + 0.25 * sin(_t * 5.0)
	var na := a * _ss(32.0, 32.5, _t) if not _years.is_empty() else a
	_fx.draw_circle(now, 20.0 * pulse, Color(UI.GOLD, 0.25 * na))
	_fx.draw_circle(now, 10.0, Color(UI.GOLD, na))
	_fx.draw_string(UI.font_bold, now + Vector2(-40.0, -30.0), str(_year_now), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 26, Color(UI.GOLD, na))


# --- a cím ---------------------------------------------------------------------
func _draw_title() -> void:
	var word := "AETHER"
	var fs := 190
	var total := UI.font_pixel.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := (W - total) * 0.5
	for i in word.length():
		var ch := word[i]
		var cw := UI.font_pixel.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var k := _ss(36.15 + i * 0.2, 36.55 + i * 0.2, _t)
		if k > 0.0:
			var pos := Vector2(x, 505.0 + (1.0 - k) * 26.0)
			for g in [18, 10]:
				_fx.draw_string_outline(UI.font_pixel, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, g, Color(UI.GOLD, 0.10 * k))
			_fx.draw_string_outline(UI.font_pixel, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.20, 0.10, 0.02, k))
			_fx.draw_string(UI.font_pixel, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.GOLD, k))
		x += cw
	var line := _ss(37.4, 38.2, _t)
	_fx.draw_rect(Rect2(W * 0.5 - 260.0 * line, 548.0, 520.0 * line, 4.0), Color(UI.CYAN, 0.8 * line))


# --- próba: képek a jelenetekről (Godot ... -- --onteszt --introteszt) ---------
func _run_test() -> void:
	var dir := OS.get_user_data_dir().path_join("aether_onteszt")
	DirAccess.make_dir_recursive_absolute(dir)
	for at in [3.6, 5.8, 9.5, 12.4, 13.9, 15.9, 17.9, 19.9, 23.0, 28.6, 31.6, 35.3, 37.3, 39.0]:
		while _t < at:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("intro_%04.1f.png" % at))
	print("INTRO képek: ", dir)
	while not _done:
		await get_tree().process_frame
	await get_tree().create_timer(2.5).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join("intro_vege.png"))
	print("INTRO kész")
	get_tree().quit()
