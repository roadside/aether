extends Control
## Fordulópontok: amikor a klímamodell szerint valami fontos történik (átlépjük a másfél fokot,
## megáll a melegedés, nulla lesz a kibocsátás), egy széles sáv úszik be a földgömb elé, hanggal.
## Semmi sincs kitalálva: minden feltétel a modell eredményéből (campaign.model) számolódik.
## Az idő közben nem áll meg.

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")

const SHOW := 5.2             # egy sáv ideje (mp)
const CENTER := Vector2(800, 434)
var campaign
var _queue: Array = []
var _cur: Dictionary = {}
var _t := 0.0
var _player: AudioStreamPlayer
var _sounds := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	_player = AudioStreamPlayer.new()
	_player.volume_db = -6.0
	add_child(_player)


static func load_sound(name: String) -> AudioStream:
	var path := "res://assets/hang/%s.wav" % name
	if ResourceLoader.exists(path):
		return load(path)
	var full := ProjectSettings.globalize_path(path)   # ha a Godot még nem importálta
	if FileAccess.file_exists(full):
		return AudioStreamWAV.load_from_file(full)
	return null


func _sound(name: String) -> void:
	if not _sounds.has(name):
		_sounds[name] = load_sound(name)
	if _sounds[name] != null:
		_player.stream = _sounds[name]
		_player.play()


func _at(group: String, key: String, y: int) -> float:
	var m: Dictionary = campaign.model
	var ys: Array = m.get("evek", [])
	var g: Variant = m.get(group, {})
	if typeof(g) != TYPE_DICTIONARY or not g.has("kozep") or not g["kozep"].has(key):
		return NAN
	for i in ys.size():
		if int(ys[i]) == y:
			return float(g["kozep"][key][i])
	return NAN


static func _year_of(v: Variant) -> int:
	return -1 if v == null else int(v)


## Mi történt ebben az évben a modell szerint? [{cim, alcim, fajta: "jo" | "rossz" | "evtized"}]
func for_year(y: int) -> Array:
	var out: Array = []
	var m: Dictionary = campaign.model
	if m.is_empty() or not m.has("osszegzes"):
		return out
	var k: Dictionary = m["osszegzes"]["kozep"]
	var has_plan: bool = not campaign.timeline.is_empty()
	var t := _at("terv", "homerseklet", y)
	var b := _at("alapeset", "homerseklet", y)
	if is_nan(b):
		b = t
	if _year_of(k.get("1.5C_atlepes")) == y:
		out.append({"cim": L.t("Átléptük a másfél fokot"), "alcim": L.t("A Föld 1,5 °C-kal melegebb, mint 150 éve."), "fajta": "rossz"})
	if _year_of(k.get("2.0C_atlepes")) == y:
		out.append({"cim": L.t("Átléptük a két fokot"), "alcim": L.t("A Föld 2 °C-kal melegebb, mint 150 éve."), "fajta": "rossz"})
	if has_plan:
		var n1 := _at("terv", "netto_co2", y)
		var n0 := _at("terv", "netto_co2", y - 1)
		if not is_nan(n1) and not is_nan(n0) and n1 <= 0.5 and n0 > 0.5:
			out.append({"cim": L.t("Nulla lett a CO2-kibocsátás"), "alcim": L.t("Ettől kezdve nem melegítjük tovább a Földet."), "fajta": "jo"})
		var peak_y := _year_of(k.get("csucs_ev"))
		if peak_y == y and y < 2095 and float(k.get("T2100", 99.0)) <= float(k.get("csucs", 0.0)) + 0.005:
			out.append({"cim": L.t("Megállt a melegedés"), "alcim": L.t("A csúcs +%s °C volt.") % UI.hu(float(k["csucs"]), 2), "fajta": "jo"})
		var b0 := _at("alapeset", "homerseklet", y - 1)
		var t0 := _at("terv", "homerseklet", y - 1)
		if not is_nan(b0) and not is_nan(t0) and not is_nan(t):
			for step in [[0.5, L.t("Fél fokkal hűvösebb a Föld")], [1.0, L.t("Egy egész fokkal hűvösebb a Föld")]]:
				if b - t >= float(step[0]) and b0 - t0 < float(step[0]):
					out.append({"cim": step[1], "alcim": L.t("Ennyit ért eddig a terved."), "fajta": "jo"})
	if out.is_empty() and y % 10 == 0 and y < 2100 and not is_nan(t):
		var sub := L.t("+%s °C. Még nincs terved.") % UI.hu(t, 1)
		if has_plan:
			sub = L.t("+%s °C · terv nélkül +%s °C lenne") % [UI.hu(t, 1), UI.hu(b, 1)]
		out.append({"cim": str(y), "alcim": sub, "fajta": "evtized"})
	return out


func on_year(y: int) -> void:
	for ms in for_year(y):
		show_banner(ms)


func show_banner(ms: Dictionary) -> void:
	_queue.append(ms)


func _process(delta: float) -> void:
	if _cur.is_empty():
		if _queue.is_empty():
			return
		_cur = _queue.pop_front()
		_t = 0.0
		_sound({"jo": "jel_jo", "rossz": "jel_rossz"}.get(str(_cur["fajta"]), "jel_evtized"))
	_t += delta
	if _t >= SHOW:
		_cur = {}
	queue_redraw()


func _draw() -> void:
	if _cur.is_empty():
		return
	var kind := str(_cur["fajta"])
	var col: Color = {"jo": UI.GREEN, "rossz": UI.EMBER}.get(kind, UI.GOLD)
	var a := clampf(_t / 0.45, 0.0, 1.0) * clampf((SHOW - _t) / 0.8, 0.0, 1.0)
	var big := kind != "evtized"
	# táguló gyűrűk a földgömb közepéből
	for r in 3:
		var rt := _t - float(r) * 0.35
		if rt > 0.0 and rt < 2.4:
			var rr := 120.0 + rt * (300.0 if big else 160.0)
			draw_arc(CENTER, rr, 0.0, TAU, 96, Color(col, 0.35 * (1.0 - rt / 2.4)), 3.0, true)
	var h := 150.0 if big else 104.0
	var slide := (1.0 - clampf(_t / 0.45, 0.0, 1.0)) * 40.0
	var top := CENTER.y - h * 0.5 + slide
	# sötét sáv, a szélein elhalványul
	var steps := 40
	for i in steps:
		var fx := float(i) / steps
		var edge := clampf(minf(fx, 1.0 - fx) * 5.0, 0.0, 1.0)
		draw_rect(Rect2(1600.0 * fx, top, 1600.0 / steps + 1.0, h), Color(0.02, 0.04, 0.09, 0.86 * a * edge))
	var wline := 1600.0 * clampf(_t / 0.9, 0.0, 1.0)
	draw_rect(Rect2(800.0 - wline * 0.5, top, wline, 3), Color(col, a))
	draw_rect(Rect2(800.0 - wline * 0.5, top + h - 3, wline, 3), Color(col, a))
	var title := str(_cur["cim"])
	var rx := RegEx.create_from_string("[0-9()]")
	var font: Font = UI.font_bold if rx.search(title) != null else UI.font_pixel
	var fs := 54 if big else 44
	draw_string(font, Vector2(0, top + (72 if big else 52)), title, HORIZONTAL_ALIGNMENT_CENTER, 1600, fs, Color(col, a))
	draw_string(UI.font_body, Vector2(0, top + (108 if big else 82)), str(_cur["alcim"]), HORIZONTAL_ALIGNMENT_CENTER, 1600, 22, Color(UI.TEXT, a))
	if big:
		draw_string(UI.font_body, Vector2(0, top + 134), L.t("a klímamodell szerint"), HORIZONTAL_ALIGNMENT_CENTER, 1600, 14, Color(UI.MUTE, a))
