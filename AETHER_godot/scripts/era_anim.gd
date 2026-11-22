extends Control
## Korszakváltás: kb. 14 mp-es festett jelenet, amikor a játékos új korszakba lép.
## Hajnalodik egy táj fölött, és megjelenik benne az, amiről az új korszak szól:
##   II. Mérséklés     – a város kéményeinek füstje elfogy,
##   III. Átalakulás   – szélkerekek nőnek ki a dombokból, napelemek csillannak,
##   IV. Helyreállítás – erdő nő, folyó csillog, madarak szállnak.
## Csak szemléltetés, adatot nem mutat. Első alkalommal végigmegy; ha a játékos egy
## korszak jelenetét már látta, kattintással vagy Esc-kel átugorhatja.

signal finished

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Knowledge := preload("res://scripts/knowledge.gd")
const Milestones := preload("res://scripts/milestones.gd")

const W := 1600.0
const H := 900.0
const U := 4.0                # a jelenet egy „pixele” (400×225-ös vászon)
const GW := 400
const GH := 225
const T_END := 14.0
const T_TEXT := 5.5           # ekkor úszik be a korszak neve
const HORIZON := 150.0

var era := 2
var shots_dir := ""           # ha nem üres: képek ellenőrzéshez, és nem ugorható át
var _t := 0.0
var _done := false
var _can_skip := false
var _player: AudioStreamPlayer


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)
	var key := "korszak_anim_%d" % era
	_can_skip = bool(L.get_setting(key, false)) and shots_dir == ""
	if shots_dir == "":
		L.set_setting(key, true)
	_player = AudioStreamPlayer.new()
	_player.stream = Milestones.load_sound("jel_jo")
	_player.volume_db = -6.0
	add_child(_player)
	if _player.stream != null:
		_player.play()
	if shots_dir != "":
		_shots()


func _shots() -> void:
	for at in [4.0, 9.5]:
		await get_tree().create_timer(at - _t).timeout
		for i in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("korszak_%d_%02d.png" % [era, int(at)]))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= T_END:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		get_viewport().set_input_as_handled()
		if _can_skip:
			_finish()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		if _can_skip:
			_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.7)
	await tw.finished
	finished.emit()
	queue_free()


# --- rajz -------------------------------------------------------------------
static func _h(i: float) -> float:
	return fposmod(sin(i * 127.1 + 311.7) * 43758.5453, 1.0)


static func _ss(a: float, b: float, x: float) -> float:
	var k := clampf((x - a) / (b - a), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


func _r(x: float, y: float, w: float, h: float, col: Color) -> void:
	draw_rect(Rect2(floorf(x) * U, floorf(y) * U, ceilf(w) * U, ceilf(h) * U), col)


static func _far(x: float) -> float:
	return HORIZON - 4.0 + 9.0 * sin(x * 0.021 + 0.6) + 5.0 * sin(x * 0.063 + 1.9)


static func _near(x: float) -> float:
	return HORIZON + 22.0 + 11.0 * sin(x * 0.017 + 2.4) + 4.0 * sin(x * 0.081)


func _draw() -> void:
	var dawn := _ss(0.5, 9.0, _t)           # 0 éjszaka, 1 reggel
	# az új korszak színe: II. meleg narancs, III. arany, IV. zöldes arany
	var glow: Color = [Color("#f0935a"), Color("#f6c453"), Color("#d9e27a")][clampi(era - 2, 0, 2)]
	# ég: sávok fentről a horizontig
	var n := 30
	for i in n:
		var k := float(i) / float(n - 1)        # 0 fent, 1 a horizonton
		var night := Color("#04060f").lerp(Color("#111c3a"), k)
		var day := Color("#1c2f66").lerp(Color("#5b79b8"), minf(k * 1.6, 1.0)).lerp(glow, pow(k, 2.6))
		_r(0, k * (HORIZON + 30.0) * (float(n - 1) / n), GW, (HORIZON + 30.0) / n + 1, night.lerp(day, dawn))
	# csillagok, hajnalban elhalványulnak
	for i in 90:
		var a := (1.0 - dawn * 1.25) * (0.45 + 0.55 * sin(_t * (1.0 + _h(i + 7.0) * 2.0) + i))
		if a > 0.02:
			_r(_h(i) * GW, _h(i + 50.0) * (HORIZON - 12.0), 1, 1, Color(0.9, 0.95, 1.0, a))
	# a Nap felkel
	var sx := 262.0
	var sy := HORIZON + 26.0 - 56.0 * _ss(1.0, 10.5, _t)
	for ring in [[46.0, 0.05], [34.0, 0.08], [24.0, 0.13]]:
		_disc(sx, sy, ring[0], Color(glow.r, glow.g, glow.b, ring[1] * dawn))
	_disc(sx, sy, 15.0, Color("#fff3c4").lerp(glow, 0.25))
	# madarak (IV.)
	if era == 4:
		for i in 6:
			var bt := _t - 6.0 - i * 0.35
			if bt > 0.0:
				var bx := 20.0 + bt * 20.0 + i * 17.0
				var by := 46.0 + _h(i + 40.0) * 34.0 + 4.0 * sin(bt * 1.3 + i)
				var flap := 1.0 if fmod(bt * 3.0 + i * 0.3, 1.0) < 0.5 else 0.0
				var bc := Color(0.07, 0.09, 0.12, 0.9)
				_r(bx - 2, by - flap, 2, 1, bc)
				_r(bx, by, 1, 1, bc)
				_r(bx + 1, by - flap, 2, 1, bc)
	# távoli dombok
	var far_col := Color("#0a1226").lerp(Color("#3d5f7a") if era != 4 else Color("#3f7260"), dawn)
	for x in GW:
		var y := _far(x)
		_r(x, y, 1, GH - y, far_col)
	if era == 3:
		_turbines(dawn)
	if era == 4:
		_trees(_far, 40, 3.0, 1.4, Color("#0c2019").lerp(Color("#2f6b4a"), dawn), 0.7)
	# közeli dombok
	var near_col := Color("#060b14").lerp([Color("#35402f"), Color("#2c4a3a"), Color("#2f7a45")][clampi(era - 2, 0, 2)], dawn)
	for x in GW:
		var y := _near(x)
		_r(x, y, 1, GH - y, near_col)
		_r(x, y, 1, 1, near_col.lightened(0.18 * dawn))
	match era:
		2:
			_town(dawn)
		3:
			_panels(dawn)
		4:
			_river(dawn)
			_trees(_near, 46, 2.0, 2.2, Color("#0a1a12").lerp(Color("#1f5a36"), dawn), 1.0)
	# finom sötétítés alul és a szöveg alatt
	var ta := _ss(T_TEXT, T_TEXT + 1.6, _t)
	for i in 34:
		draw_rect(Rect2(0, 220 + i * 10, W, 10), Color(0.01, 0.02, 0.05, 0.55 * ta * sin(PI * (i + 0.5) / 34.0)))
	_text(ta)


func _disc(cx: float, cy: float, rad: float, col: Color) -> void:
	var y := -rad
	while y <= rad:
		var half := sqrt(maxf(rad * rad - y * y, 0.0))
		if cy + y < HORIZON + 40.0:
			_r(cx - half, cy + y, half * 2.0, 1, col)
		y += 1.0


## II. Mérséklés: kisváros a dombon; a kémények füstje a hajnallal elfogy, az ablakok fénye megmarad.
func _town(dawn: float) -> void:
	var wall := Color("#0b0f18").lerp(Color("#4a4640"), dawn)
	var roof := Color("#0d1018").lerp(Color("#7a4a3a"), dawn)
	for i in 16:
		var x := 60.0 + i * 18.0 + _h(i + 3.0) * 6.0
		var w := 9.0 + floorf(_h(i + 11.0) * 6.0)
		var hh := 9.0 + floorf(_h(i + 21.0) * 12.0)
		var base := _near(x + w * 0.5) + 2.0
		_r(x, base - hh, w, hh, wall)
		_r(x - 1, base - hh - 2, w + 2, 2, roof)
		var wy := base - hh + 3.0
		while wy < base - 3.0:
			var wx := x + 2.0
			while wx < x + w - 2.0:
				if _h(wx * 3.1 + wy * 7.7 + i) > 0.35:
					_r(wx, wy, 2, 2, Color(1.0, 0.82, 0.45, 0.9 - 0.45 * dawn))
				wx += 4.0
			wy += 5.0
	for c in 4:
		var x := 96.0 + c * 64.0
		var base := _near(x) + 2.0
		var top := base - 34.0 - _h(c + 5.0) * 8.0
		_r(x, top, 4, base - top, Color("#0a0d14").lerp(Color("#5a5450"), dawn))
		_r(x, top, 4, 2, Color("#0a0d14").lerp(Color("#8a4a40"), dawn))
		# füst: egyre kevesebb és halványabb
		var left := 1.0 - _ss(3.0, 10.0, _t)
		for p in 9:
			var ph := fposmod(_t * 0.22 + p / 9.0 + c * 0.13, 1.0)
			var a := left * (1.0 - ph) * 0.55
			if a > 0.02:
				var s := 3.0 + ph * 9.0
				_r(x + 2.0 - s * 0.5 + ph * 16.0 + 3.0 * sin(p + _t), top - 4.0 - ph * 46.0, s, s * 0.7, Color(0.55, 0.55, 0.6, a))


## III. Átalakulás: szélkerekek nőnek ki a távoli dombokból, és forogni kezdenek.
func _turbines(dawn: float) -> void:
	var col := Color("#1a2238").lerp(Color("#eef2f6"), dawn)
	for i in 6:
		var x := 36.0 + i * 62.0 + _h(i + 2.0) * 14.0
		var grow := _ss(1.5 + i * 0.7, 4.5 + i * 0.7, _t)
		if grow <= 0.0:
			continue
		var base := _far(x) + 1.0
		var hh := (34.0 + _h(i + 9.0) * 12.0) * grow
		_r(x, base - hh, 2, hh, col)
		if grow >= 1.0:
			var hub := Vector2((x + 1.0) * U, (base - hh) * U)
			var spin := (_t - (4.5 + i * 0.7)) * (1.4 + _h(i) * 0.6)
			var len := (15.0 + _h(i + 4.0) * 4.0) * U * _ss(4.5 + i * 0.7, 5.5 + i * 0.7, _t)
			for b in 3:
				var ang := spin + b * TAU / 3.0
				draw_line(hub, hub + Vector2(cos(ang), sin(ang)) * len, col, U * 0.9)
			draw_rect(Rect2(hub - Vector2(U, U), Vector2(U * 2, U * 2)), col)


## III. Átalakulás: napelemsorok a közeli dombon, a felkelő Nap megcsillan rajtuk.
func _panels(dawn: float) -> void:
	for i in 22:
		var x := 18.0 + i * 17.0
		var show := _ss(3.0 + i * 0.12, 4.2 + i * 0.12, _t)
		if show <= 0.0:
			continue
		var y := _near(x + 5.0) + 5.0 + (i % 3) * 9.0
		var c := Color("#0a1020").lerp(Color("#27478f"), dawn)
		c.a = show
		_r(x, y, 11, 4, c)
		_r(x, y, 11, 1, Color(0.6, 0.75, 1.0, 0.5 * show * dawn))
		_r(x + 5, y + 4, 1, 3, Color(0.2, 0.22, 0.26, show))
		# csillanás: egy fényfolt fut végig a sorokon
		var gl := exp(-pow((x - (fposmod(_t - 6.0, 5.0) / 5.0) * (GW + 80.0) + 40.0) / 14.0, 2.0)) * dawn
		if gl > 0.05 and _t > 6.0:
			_r(x + 2, y, 5, 2, Color(1.0, 0.97, 0.8, gl))


## IV. Helyreállítás: fák nőnek egymás után a dombon.
func _trees(ridge: Callable, count: int, t0: float, size_f: float, col: Color, seed_f: float) -> void:
	for i in count:
		var x := _h(i * 1.7 + seed_f * 31.0) * GW
		var g := _ss(t0 + _h(i + seed_f * 5.0) * 5.0, t0 + 2.0 + _h(i + seed_f * 5.0) * 5.0, _t)
		if g <= 0.0:
			continue
		var base: float = ridge.call(x) + 1.0 + _h(i + 77.0) * 10.0 * seed_f
		var hh := (7.0 + _h(i + 13.0) * 7.0) * size_f * g
		var c := col.lightened(_h(i + 3.0) * 0.14)
		_r(x, base - hh * 0.3, 1, hh * 0.3, col.darkened(0.4))
		var rows := int(maxf(hh * 0.8, 1.0))
		for k in rows:
			var wdt := 1.0 + float(k) / rows * hh * 0.55
			_r(x + 0.5 - wdt * 0.5, base - hh + k, wdt, 1, c)


## IV. Helyreállítás: csillogó folyó kanyarog az előtérben.
func _river(dawn: float) -> void:
	var y := 196.0
	while y < GH:
		var k := (y - 196.0) / (GH - 196.0)
		var cx := 150.0 + 60.0 * sin(k * 3.2 + 0.6) + k * 40.0
		var wdt := 6.0 + k * 34.0
		_r(cx - wdt * 0.5, y, wdt, 1, Color("#0b1626").lerp(Color("#5aa6c8"), dawn))
		if _h(y * 3.3 + floorf(_t * 5.0)) > 0.72:
			_r(cx - wdt * 0.5 + _h(y + floorf(_t * 5.0)) * wdt, y, 2, 1, Color(1, 1, 0.9, 0.8 * dawn))
		y += 1.0


func _text(a: float) -> void:
	if a <= 0.0:
		return
	var small := L.t("Új korszak")
	draw_string(UI.font_body, Vector2(0, 318), small, HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color(0.95, 0.96, 0.97, 0.85 * a))
	var title := Knowledge.era_name(era)
	var rise := (1.0 - a) * 14.0
	draw_string(UI.font_pixel, Vector2(4, 414 + rise), title, HORIZONTAL_ALIGNMENT_CENTER, W, 84, Color(0, 0, 0, 0.6 * a))
	draw_string(UI.font_pixel, Vector2(0, 410 + rise), title, HORIZONTAL_ALIGNMENT_CENTER, W, 84, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a))
	var a2 := _ss(T_TEXT + 1.2, T_TEXT + 2.6, _t)
	var lw := 220.0 * a2
	draw_line(Vector2(W / 2.0 - lw, 440), Vector2(W / 2.0 + lw, 440), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.8 * a2), 2.0)
	draw_multiline_string(UI.font_body, Vector2(300, 488), L.t(Knowledge.ERAS[era - 1]["tema"]), HORIZONTAL_ALIGNMENT_CENTER, 1000, 28, 3, Color(0.95, 0.96, 0.97, a2))
	if _can_skip:
		draw_string(UI.font_body, Vector2(1460, 882), L.t("Esc: átugrás"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.74, 0.8, 0.8))
