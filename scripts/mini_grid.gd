extends Control
## Minijáték: Áramhálózat. Három nyugodt kör, időnyomás nélkül: a játékos megnézi, mely hónapokban kevés
## egy ország szél- és napárama, és kiválasztja, melyik másik országgal érdemes kábellel összekötni.
## A havi szél-, nap- és igényadat valódi (Ember, 2024; adatok/halozat_ember2024.json, a forrás a fájlban).
## Játékszabály: minden ország szél- és napáramát úgy nagyítjuk, hogy egy évre éppen fedezze a saját
## igényét (a havi alak valódi marad); a kábel korlátlanul szállít; a három kör és a jelöltek kiválasztása.
## A „hiány” az a havi áram, ami tárolóból vagy más erőműből kellene (igény mínusz termelés, ha pozitív).

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const MONTHS := ["jan.", "febr.", "márc.", "ápr.", "máj.", "jún.", "júl.", "aug.", "szept.", "okt.", "nov.", "dec."]
const MONTHS_EN := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const ROUNDS := [["HUN", ["AUT", "NOR", "ITA"]], ["ESP", ["FRA", "GBR", "PRT"]], ["GBR", ["DNK", "POL", "NOR"]]]   # játékszabály
const FOCUS := Rect2(60, 200, 700, 250)
const BOTH := Rect2(60, 560, 700, 250)
const CAND_X := 860.0
const CAND_W := 680.0
const CAND_H := 150.0
const WIND := Color("#8fe0d6")
const SUN := Color("#f1c873")
const SHORT := Color("#ec5a59")

var data_path := "res://adatok/halozat_ember2024.json"
var auto := false                # próbafutás: magától választ
var done_t := -1.0               # a befejezés óta eltelt idő; < 0 = még tart
var by_id := {}                  # ország -> {name, gen[12], wind[12], sun[12], dem[12], wind_share}
var source := ""
var study := ""
var round_i := 0
var picked := -1                 # a választott jelölt (0..2), -1 = még nincs
var good := 0
var best_pairs: Array = []       # [fókusz neve, legjobb pár neve, százalék]
var _t := 0.0
var _pick_t := 0.0
var _hover := -1
var _wait := 0.0
var _info: Label
var _say: Label
var _next_btn: Button
var _end: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	var title := UI.heading(L.t("Áramhálózat"), 34)
	title.position = Vector2(60, 28)
	add_child(title)
	_info = UI.label(L.t("Nézd a piros hónapokat: ott kevés a szél- és napáram. Melyik ország termel sokat éppen akkor? Kattints rá, és kösd össze vele!"), 18, UI.SOFT)
	_info.position = Vector2(60, 84)
	_info.size = Vector2(1200, 60)
	add_child(_info)
	_say = UI.label("", 20, UI.TEXT, true)
	_say.position = Vector2(60, 470)
	_say.size = Vector2(700, 80)
	add_child(_say)
	_next_btn = UI.button(L.t("Tovább") + " →", true)
	_next_btn.position = Vector2(1390, 30)
	_next_btn.visible = false
	_next_btn.pressed.connect(_next)
	add_child(_next_btn)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(8)
	_end.position = Vector2(860, 200)
	_end.size = Vector2(680, 500)
	_end.visible = false
	add_child(_end)
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	var en := L.is_en()
	source = str(j.get("forras_en" if en else "forras", ""))
	study = str(j.get("tanulmany_en" if en else "tanulmany", ""))
	for c in j.get("orszagok", []):
		var wind: Array = c["szel"]
		var sun: Array = c["nap"]
		var dem: Array = c["igeny"]
		var gsum := 0.0
		var dsum := 0.0
		var wsum := 0.0
		for m in 12:
			gsum += float(wind[m]) + float(sun[m])
			wsum += float(wind[m])
			dsum += float(dem[m])
		var k := dsum / maxf(gsum, 0.001)      # játékszabály: a termelést az évi igény szintjére nagyítjuk
		var w2: Array = []
		var s2: Array = []
		var g2: Array = []
		var d2: Array = []
		for m in 12:
			w2.append(float(wind[m]) * k)
			s2.append(float(sun[m]) * k)
			g2.append((float(wind[m]) + float(sun[m])) * k)
			d2.append(float(dem[m]))
		by_id[str(c["id"])] = {"name": str(c["en"] if en else c["hu"]), "wind": w2, "sun": s2, "gen": g2, "dem": d2, "wind_share": wsum / maxf(gsum, 0.001)}


func ok() -> bool:
	for r in ROUNDS:
		if not by_id.has(r[0]):
			return false
		for c in r[1]:
			if not by_id.has(c):
				return false
	return true


## Egy országcsoport évi hiánya (TWh): közösen osztoznak a termelésen.
func _deficit(ids: Array) -> float:
	var s := 0.0
	for m in 12:
		var g := 0.0
		var d := 0.0
		for id in ids:
			g += float(by_id[id]["gen"][m])
			d += float(by_id[id]["dem"][m])
		s += maxf(0.0, d - g)
	return s


## Ennyi százalékkal kevesebb a két ország hiánya összekötve, mint külön-külön.
func _gain(a: String, b: String) -> float:
	var sep := _deficit([a]) + _deficit([b])
	return 100.0 * (1.0 - _deficit([a, b]) / maxf(sep, 0.001))


func _focus() -> String:
	return str(ROUNDS[mini(round_i, ROUNDS.size() - 1)][0])


func _cands() -> Array:
	return ROUNDS[mini(round_i, ROUNDS.size() - 1)][1]


func _best() -> int:
	var b := 0
	for i in 3:
		if _gain(_focus(), str(_cands()[i])) > _gain(_focus(), str(_cands()[b])):
			b = i
	return b


func _cand_rect(i: int) -> Rect2:
	return Rect2(CAND_X, 200.0 + i * (CAND_H + 62.0), CAND_W, CAND_H)


func _pick(i: int) -> void:
	if done_t >= 0.0 or picked >= 0:
		return
	picked = i
	_pick_t = _t
	var b := _best()
	var f := _focus()
	var gain := _gain(f, str(_cands()[i]))
	if i == b:
		good += 1
		_say.text = L.t("Jó választás! Összekötve %s%%-kal kevesebb a hiány.") % L.num(gain, 0)
		_say.add_theme_color_override("font_color", UI.GREEN)
	else:
		_say.text = L.t("Összekötve %s%%-kal kevesebb a hiány. Többet segített volna: %s (%s%%).") % [L.num(gain, 0), str(by_id[_cands()[b]]["name"]), L.num(_gain(f, str(_cands()[b])), 0)]
		_say.add_theme_color_override("font_color", UI.TEXT)
	best_pairs.append([str(by_id[f]["name"]), str(by_id[_cands()[b]]["name"]), _gain(f, str(_cands()[b]))])
	_info.visible = false
	_next_btn.visible = true
	_wait = 0.0


func _next() -> void:
	if done_t >= 0.0:
		finished.emit(true)
		return
	if picked < 0:
		return
	round_i += 1
	picked = -1
	_say.text = ""
	_next_btn.visible = false
	if round_i >= ROUNDS.size():
		_finish()
	else:
		_info.visible = true


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		finished.emit(done_t >= 0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = -1
		for i in 3:
			if _cand_rect(i).has_point(event.position):
				_hover = i
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		for i in 3:
			if _cand_rect(i).has_point(event.position):
				_pick(i)


func _process(delta: float) -> void:
	_t += delta
	if done_t >= 0.0:
		done_t += delta
	elif auto:
		_wait += delta
		if picked < 0 and _wait > 2.5:
			_pick(_best())
		elif picked >= 0 and _wait > 3.5:
			_wait = 0.0
			_next()
	queue_redraw()


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_info.visible = false
	_say.visible = false
	_end.visible = true
	_end.add_child(UI.label(L.t("Jó választás: %d / %d") % [good, ROUNDS.size()], 22, UI.CYAN, true))
	_end.add_child(UI.label(L.t("A kábel akkor segít sokat, ha a két országban máskor fúj a szél és máskor süt a nap."), 20, UI.GOLD, true))
	for bp in best_pairs:
		_end.add_child(UI.label("%s + %s: −%s%%" % [bp[0], bp[1], L.num(float(bp[2]), 0)], 19, UI.TEXT))
	_end.add_child(UI.label(L.t("Egy európai tanulmány szerint a legjobb hálózat kábeleinek 44%-ával már a megtakarítás 85%-a elérhető."), 18, UI.TEXT))
	_end.add_child(UI.label(L.t("Forrás: %s. Tanulmány: %s") % [source, study], 13, UI.MUTE))
	_next_btn.visible = true


## Egy ország (vagy pár) havi oszlopai: szél + nap az igényhez mérve; az igény a vízszintes vonal.
func _chart(r: Rect2, ids: Array, title: String, font: Font, small: bool, frame: Color, mark_other: Array = []) -> void:
	draw_rect(r, Color(0.09, 0.13, 0.22, 1.0))
	draw_rect(r, frame, false, 2.0)
	draw_string(font, r.position + Vector2(4, -10), title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 15 if small else 18, UI.TEXT)
	var pad_l := 14.0
	var bw := (r.size.x - pad_l * 2.0) / 12.0
	var base := r.end.y - (16.0 if small else 22.0)
	var top := r.position.y + 10.0
	var line_y := lerpf(base, top, 1.0 / 1.9)      # az igény szintje (100%); a skála 190%-ig ér
	for m in 12:
		var w := 0.0
		var s := 0.0
		var d := 0.0
		for id in ids:
			w += float(by_id[id]["wind"][m])
			s += float(by_id[id]["sun"][m])
			d += float(by_id[id]["dem"][m])
		var x := r.position.x + pad_l + m * bw
		var hw := (base - top) * minf(w / d, 1.9) / 1.9
		var hs := (base - top) * minf((w + s) / d, 1.9) / 1.9 - hw
		draw_rect(Rect2(x + 3.0, base - hw, bw - 6.0, hw), WIND)
		draw_rect(Rect2(x + 3.0, base - hw - hs, bw - 6.0, hs), SUN)
		if w + s < d:      # hiány: piros a termelés és az igény között
			var pulse := 0.75 + 0.25 * sin(_t * 3.0)
			draw_rect(Rect2(x + 3.0, line_y, bw - 6.0, base - hw - hs - line_y), Color(SHORT, 0.55 * pulse))
			draw_rect(Rect2(x + 3.0, line_y, bw - 6.0, base - hw - hs - line_y), SHORT, false, 1.5)
		elif not mark_other.is_empty():      # jelölt: zöld keret ott, ahol a fókuszország hiányban van, ő pedig bőven termel
			if bool(mark_other[m]):
				draw_rect(Rect2(x + 1.0, base - hw - hs - 2.0, bw - 2.0, hw + hs + 2.0), UI.GREEN, false, 2.0)
		var mn: String = (MONTHS_EN if L.is_en() else MONTHS)[m]
		draw_string(font, Vector2(x, r.end.y - 3.0), mn, HORIZONTAL_ALIGNMENT_CENTER, bw, 10 if small else 12, UI.MUTE)
	draw_line(Vector2(r.position.x + 6.0, line_y), Vector2(r.end.x - 6.0, line_y), UI.TEXT, 2.0)
	draw_string(font, Vector2(r.end.x - 86.0, line_y - 5.0), L.t("igény"), HORIZONTAL_ALIGNMENT_RIGHT, 80, 12, UI.TEXT)


func _share_text(id: String) -> String:
	var ws := float(by_id[id]["wind_share"]) * 100.0
	return "%s  ·  %s %s%%, %s %s%%" % [by_id[id]["name"], L.t("szél"), L.num(ws, 0), L.t("nap"), L.num(100.0 - ws, 0)]


func _short_months(id: String) -> Array:
	var out: Array = []
	for m in 12:
		out.append(float(by_id[id]["gen"][m]) < float(by_id[id]["dem"][m]))
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, W, H), Color("#0b1324"))
	if by_id.is_empty():
		return
	# jelmagyarázat
	var lx := 1060.0
	for it in [[WIND, L.t("szél")], [SUN, L.t("nap")], [SHORT, L.t("hiány")]]:
		draw_rect(Rect2(lx, 150, 16, 16), it[0])
		draw_string(font, Vector2(lx + 22.0, 164), str(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)
		lx += 110.0
	var f := _focus()
	if done_t >= 0.0:      # zárókép: az utolsó kör párja marad a bal oldalon
		var lastc := str(ROUNDS[-1][1][0])
		for i in 3:
			if str(by_id[ROUNDS[-1][1][i]]["name"]) == str(best_pairs[-1][1]):
				lastc = str(ROUNDS[-1][1][i])
		_chart(FOCUS, [f], _share_text(f), font, false, UI.EDGE)
		_chart(BOTH, [f, lastc], "%s + %s" % [by_id[f]["name"], by_id[lastc]["name"]], font, false, UI.GREEN)
		return
	_chart(FOCUS, [f], _share_text(f), font, false, UI.GOLD)
	var shorts := _short_months(f)
	var best := _best()
	for i in 3:
		var id := str(_cands()[i])
		var r := _cand_rect(i)
		var frame := UI.EDGE
		if picked < 0 and _hover == i:
			frame = UI.CYAN
		elif picked >= 0 and i == best:
			frame = UI.GREEN
		elif picked == i:
			frame = UI.GOLD
		_chart(r, [id], _share_text(id), font, true, frame, shorts if picked >= 0 else [])
		if picked >= 0:
			draw_string(font, Vector2(r.end.x - 260.0, r.position.y - 10.0), L.t("−%s%% hiány") % L.num(_gain(f, id), 0), HORIZONTAL_ALIGNMENT_RIGHT, 256, 17, UI.GREEN if i == best else UI.SOFT)
			if picked == i:      # a megépült kábel
				var a := Vector2(FOCUS.end.x, FOCUS.position.y + FOCUS.size.y * 0.5)
				var b := Vector2(r.position.x, r.position.y + r.size.y * 0.5)
				var k := clampf((_t - _pick_t) / 0.6, 0.0, 1.0)
				draw_line(a, a.lerp(b, k), UI.GOLD, 5.0, true)
				if k >= 1.0:
					var ph := fmod(_t * 0.8, 1.0)
					draw_circle(b.lerp(a, ph), 6.0, UI.TEXT)
	if picked >= 0:
		var id2 := str(_cands()[picked])
		_chart(BOTH, [f, id2], L.t("Összekötve: %s + %s") % [by_id[f]["name"], by_id[id2]["name"]], font, false, UI.GOLD)
	else:
		draw_string(font, Vector2(CAND_X, 172), L.t("Kivel kötöd össze?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.GOLD)
	draw_string(font, Vector2(60, 880), L.t("Az oszlopok a szél- és napáramot mutatják az igényhez mérve (Ember, 2024)."), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.MUTE)
