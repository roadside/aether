extends Control
## Minijáték: Áramhálózat. A játékos kábeleket épít európai országok között. Ahol egy hónapban kevés
## a szél- és napáram, oda a szomszédtól jöhet. A havi szél-, nap- és igényadat valódi (Ember, 2024;
## adatok/halozat_ember2024.json, a forrás a fájlban).
## Játékszabály: minden ország szél- és napáramát úgy nagyítjuk, hogy egy évre éppen fedezze a saját
## igényét (a havi alak valódi marad); a kábelek száma (KERET) és a hónapok léptetése kitalált.
## A „hiány” az a havi áram, ami tárolóból vagy más erőműből kellene: egy csoport országai közösen
## osztoznak a termelésen, a hiány a csoport havi igénye mínusz a termelése, ha az pozitív.

signal finished(done: bool)

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const W := 1600.0
const H := 900.0
const MONTH_SECONDS := 0.9       # játékszabály: ennyi ideig látszik egy hónap a térképen
const PANEL_X := 1060.0
const MONTHS := ["jan.", "febr.", "márc.", "ápr.", "máj.", "jún.", "júl.", "aug.", "szept.", "okt.", "nov.", "dec."]
const MONTHS_EN := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var data_path := "res://adatok/halozat_ember2024.json"
var auto := false                # próbafutás: magától épít (mindig a legtöbbet segítő kábelt)
var done_t := -1.0               # a befejezés óta eltelt idő; < 0 = még tart
var nodes: Array = []            # [{id, name, pos, wind_share, gen[12], dem[12], size}]
var cables: Array = []           # [[a index, b index]]
var built: Array = []            # a megépített kábelek indexei
var budget := 6
var source := ""
var study := ""
var deficit0 := 0.0              # hiány kábel nélkül (TWh/év)
var deficit_all := 0.0           # hiány, ha minden kábel megépül
var deficit_now := 0.0
var month_def0: Array = []       # havi hiány kábel nélkül
var month_def: Array = []        # havi hiány most
var _node_short: Array = []      # [ország][hónap] -> hiányban van-e a csoportja
var _t := 0.0
var _month := 0
var _hover := -1
var _auto_t := 0.0
var _info: Label
var _count: Label
var _read: Label
var _ready_btn: Button
var _end: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_load()
	var title := UI.heading(L.t("Áramhálózat"), 34)
	title.position = Vector2(PANEL_X, 30)
	add_child(title)
	_info = UI.label(L.t("Kattints két ország közti szaggatott vonalra, és építs kábelt! Ahol kevés a szél- és napáram, oda a szomszéd segíthet."), 18, UI.SOFT)
	_info.position = Vector2(PANEL_X, 84)
	_info.size = Vector2(500, 80)
	add_child(_info)
	_count = UI.label("", 20, UI.GOLD, true, false)
	_count.position = Vector2(PANEL_X, 180)
	add_child(_count)
	_read = UI.label("", 24, UI.CYAN, true, false)
	_read.position = Vector2(PANEL_X, 214)
	add_child(_read)
	_ready_btn = UI.button(L.t("Kész"), true)
	_ready_btn.position = Vector2(1440, 176)
	_ready_btn.pressed.connect(_finish)
	add_child(_ready_btn)
	var hint := UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	hint.position = Vector2(1460, 870)
	add_child(hint)
	_end = UI.vbox(6)
	_end.position = Vector2(PANEL_X, 560)
	_end.size = Vector2(500, 280)
	_end.visible = false
	add_child(_end)
	_recompute()
	grab_focus()


func _load() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(j) != TYPE_DICTIONARY:
		return
	source = str(j.get("forras_en" if L.is_en() else "forras", ""))
	study = str(j.get("tanulmany_en" if L.is_en() else "tanulmany", ""))
	budget = int(j.get("kabel_keret", 6))
	var ids := {}
	for c in j.get("orszagok", []):
		var wind: Array = c["szel"]
		var sun: Array = c["nap"]
		var dem: Array = c["igeny"]
		var sw := 0.0
		var ss := 0.0
		var sd := 0.0
		for m in 12:
			sw += float(wind[m])
			ss += float(sun[m])
			sd += float(dem[m])
		var f := sd / maxf(sw + ss, 0.001)      # játékszabály: egy évre éppen a saját igény
		var gen: Array = []
		var dm: Array = []
		for m in 12:
			gen.append((float(wind[m]) + float(sun[m])) * f)
			dm.append(float(dem[m]))
		ids[str(c["id"])] = nodes.size()
		nodes.append({
			"id": str(c["id"]),
			"name": str(c["en"] if L.is_en() else c["hu"]),
			"pos": _proj(float(c["lon"]), float(c["lat"])),
			"wind_share": sw / maxf(sw + ss, 0.001),
			"gen": gen,
			"dem": dm,
			"size": 12.0 + sqrt(sd) * 1.15,
		})
	for e in j.get("kabelek", []):
		if ids.has(str(e[0])) and ids.has(str(e[1])):
			cables.append([int(ids[str(e[0])]), int(ids[str(e[1])])])
	var none: Array = []
	deficit0 = _deficit(none)
	month_def0 = _month_deficit(none)
	var every: Array = []
	for i in cables.size():
		every.append(i)
	deficit_all = _deficit(every)


## Egyszerű vetítés: hosszúság/szélesség -> a térkép képpontjai (vázlat, nem pontos térkép).
func _proj(lon: float, lat: float) -> Vector2:
	return Vector2(110.0 + (lon + 10.0) * 27.5, 860.0 - (lat - 37.0) * 31.0)


func ok() -> bool:
	return nodes.size() >= 6 and cables.size() >= budget and deficit0 > 0.0


func _groups(edges: Array) -> Array:
	var par: Array = []
	for i in nodes.size():
		par.append(i)
	for ei in edges:
		var a := _root(par, int(cables[int(ei)][0]))
		var b := _root(par, int(cables[int(ei)][1]))
		par[a] = b
	var g := {}
	for i in nodes.size():
		var r := _root(par, i)
		if not g.has(r):
			g[r] = []
		g[r].append(i)
	return g.values()


func _root(par: Array, x: int) -> int:
	while int(par[x]) != x:
		x = int(par[x])
	return x


func _month_deficit(edges: Array) -> Array:
	var out: Array = []
	out.resize(12)
	out.fill(0.0)
	for grp in _groups(edges):
		for m in 12:
			var gsum := 0.0
			var dsum := 0.0
			for i in grp:
				gsum += float(nodes[i]["gen"][m])
				dsum += float(nodes[i]["dem"][m])
			out[m] = float(out[m]) + maxf(0.0, dsum - gsum)
	return out


func _deficit(edges: Array) -> float:
	var s := 0.0
	for v in _month_deficit(edges):
		s += float(v)
	return s


func _recompute() -> void:
	month_def = _month_deficit(built)
	deficit_now = 0.0
	for v in month_def:
		deficit_now += float(v)
	_node_short.clear()
	for i in nodes.size():
		_node_short.append([])
	for grp in _groups(built):
		for m in 12:
			var gsum := 0.0
			var dsum := 0.0
			for i in grp:
				gsum += float(nodes[i]["gen"][m])
				dsum += float(nodes[i]["dem"][m])
			for i in grp:
				_node_short[i].append(dsum > gsum)
	_count.text = L.t("Kábel: %d / %d") % [built.size(), budget]
	_read.text = L.t("Hiány egy év alatt: %s TWh") % L.num(deficit_now, 0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			finished.emit(done_t >= 0.0)
		elif event.keycode in [KEY_SPACE, KEY_ENTER] and done_t < 0.0:
			get_viewport().set_input_as_handled()
			_finish()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _cable_at(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if done_t < 0.0:
			_toggle(_cable_at(event.position))


## A kurzorhoz legközelebbi kábel (14 képponton belül), vagy -1.
func _cable_at(p: Vector2) -> int:
	var best := -1
	var bd := 14.0
	for i in cables.size():
		var a: Vector2 = nodes[int(cables[i][0])]["pos"]
		var b: Vector2 = nodes[int(cables[i][1])]["pos"]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < bd and p.distance_to(a) > 18.0 and p.distance_to(b) > 18.0:
			bd = d
			best = i
	return best


func _toggle(i: int) -> void:
	if i < 0:
		return
	if i in built:
		built.erase(i)
	elif built.size() < budget:
		built.append(i)
	else:
		return
	_recompute()


func _process(delta: float) -> void:
	_t += delta
	_month = int(_t / MONTH_SECONDS) % 12
	if done_t >= 0.0:
		done_t += delta
	elif auto:
		_auto_t += delta
		if _auto_t >= 0.8:
			_auto_t = 0.0
			if built.size() < budget:
				_toggle(_best_next())
			else:
				_finish()
	queue_redraw()


## A próbafutás lépése: az a kábel, amelyik most a legjobban csökkenti a hiányt.
func _best_next() -> int:
	var best := -1
	var bv := INF
	for i in cables.size():
		if i in built:
			continue
		var trial := built.duplicate()
		trial.append(i)
		var v := _deficit(trial)
		if v < bv:
			bv = v
			best = i
	return best


func _finish() -> void:
	if done_t >= 0.0:
		return
	done_t = 0.0
	_info.visible = false
	_ready_btn.visible = false
	var cut := 100.0 * (1.0 - deficit_now / maxf(deficit0, 0.001))
	var cut_all := 100.0 * (1.0 - deficit_all / maxf(deficit0, 0.001))
	_end.visible = true
	_end.add_child(UI.label(L.t("Kábel nélkül: %s TWh hiány egy év alatt.") % L.num(deficit0, 0), 18, UI.SOFT))
	_end.add_child(UI.label(L.t("A te %d kábeleddel: %s TWh, %s%%-kal kevesebb.") % [built.size(), L.num(deficit_now, 0), L.num(cut, 0)], 20, UI.CYAN, true))
	_end.add_child(UI.label(L.t("Ha minden kábel megépülne: %s%%-kal kevesebb.") % L.num(cut_all, 0), 18, UI.SOFT))
	_end.add_child(UI.label(L.t("Egy európai tanulmány szerint a legjobb hálózat kábeleinek 44%-ával már a megtakarítás 85%-a elérhető."), 18, UI.TEXT, true))
	_end.add_child(UI.label(L.t("Adat: %s. Tanulmány: %s") % [source, study], 13, UI.MUTE))
	var b := UI.button(L.t("Tovább") + " →", true)
	b.pressed.connect(func() -> void: finished.emit(true))
	b.position = Vector2(1390, 30)
	add_child(b)


func _draw() -> void:
	var font := get_theme_default_font()
	# --- tenger és éjszakai fény ---
	for i in 40:
		var f := i / 39.0
		draw_rect(Rect2(0, f * H, PANEL_X - 30.0, H / 39.0 + 1.0), Color("#071226").lerp(Color("#10264a"), f))
	draw_rect(Rect2(PANEL_X - 30.0, 0, W - PANEL_X + 30.0, H), Color("#0b1324"))
	draw_line(Vector2(PANEL_X - 30.0, 0), Vector2(PANEL_X - 30.0, H), Color(UI.CYAN, 0.25), 1.0)
	# a hónap jelzője a térkép tetején
	var mn: Array = MONTHS_EN if L.is_en() else MONTHS
	for m in 12:
		var x := 120.0 + m * 66.0
		var on := m == _month
		draw_string(font, Vector2(x, 44), str(mn[m]), HORIZONTAL_ALIGNMENT_CENTER, 60, 17 if on else 14, UI.GOLD if on else UI.MUTE)
	draw_line(Vector2(120.0 + _month * 66.0 + 8.0, 54), Vector2(120.0 + _month * 66.0 + 52.0, 54), UI.GOLD, 2.0)
	# --- kábelek ---
	for i in cables.size():
		var a: Vector2 = nodes[int(cables[i][0])]["pos"]
		var b: Vector2 = nodes[int(cables[i][1])]["pos"]
		if i in built:
			draw_line(a, b, Color(UI.CYAN, 0.9), 5.0)
			var n := int(a.distance_to(b) / 40.0) + 1
			for k in n:      # az áram útja: pontok futnak a kábelen
				var f := fmod(_t * 0.6 + float(k) / n, 1.0)
				draw_circle(a.lerp(b, f), 3.0, Color(1, 1, 1, 0.8))
		else:
			var hov := i == _hover and done_t < 0.0
			var col := Color(UI.GOLD, 0.9) if hov else Color(UI.MUTE, 0.45)
			draw_dashed_line(a, b, col, 3.0 if hov else 2.0, 10.0)
	# --- országok: a gyűrű a szél (cián) és a nap (arany) arányát mutatja; a belseje, hogy ebben a hónapban elég-e az áram ---
	for i in nodes.size():
		var nd: Dictionary = nodes[i]
		var p: Vector2 = nd["pos"]
		var r: float = nd["size"]
		var short: bool = _node_short[i][_month] if _node_short.size() > i and _node_short[i].size() == 12 else false
		var fill := Color(UI.EMBER, 0.75) if short else Color(UI.GREEN, 0.7)
		var glow := 0.5 + 0.5 * sin(_t * 4.0) if short else 1.0
		draw_circle(p, r + 6.0, Color(fill, 0.12 * glow))
		draw_circle(p, r, Color("#0b1324"))
		draw_circle(p, r - 5.0, fill)
		var ws: float = nd["wind_share"]
		draw_arc(p, r - 1.5, -PI / 2.0, -PI / 2.0 + TAU * ws, 48, UI.CYAN, 4.0)
		draw_arc(p, r - 1.5, -PI / 2.0 + TAU * ws, -PI / 2.0 + TAU, 48, UI.GOLD, 4.0)
		var tw := font.get_string_size(str(nd["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_rect(Rect2(p.x - tw * 0.5 - 5.0, p.y + r + 6.0, tw + 10.0, 20.0), Color(0.03, 0.07, 0.15, 0.85))
		draw_string(font, p + Vector2(-80, r + 21.0), str(nd["name"]), HORIZONTAL_ALIGNMENT_CENTER, 160, 14, UI.TEXT)
	# jelmagyarázat
	var ly := 88.0
	draw_arc(Vector2(40, ly), 9.0, 0, TAU, 24, UI.CYAN, 4.0)
	draw_string(font, Vector2(56, ly + 5), L.t("szél"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)
	draw_arc(Vector2(120, ly), 9.0, 0, TAU, 24, UI.GOLD, 4.0)
	draw_string(font, Vector2(136, ly + 5), L.t("nap"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)
	draw_circle(Vector2(200, ly), 8.0, Color(UI.GREEN, 0.7))
	draw_string(font, Vector2(214, ly + 5), L.t("elég az áram"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)
	draw_circle(Vector2(340, ly), 8.0, Color(UI.EMBER, 0.75))
	draw_string(font, Vector2(354, ly + 5), L.t("hiány"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)
	draw_string(font, Vector2(30, 860), L.t("Vázlatos térkép. Az országok mérete az áramigényüket mutatja."), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.MUTE)
	# --- havi hiány oszlopokban: szürke = kábel nélkül, színes = most ---
	var x0 := PANEL_X
	var y0 := 520.0
	var hmax := 0.0
	for v in month_def0:
		hmax = maxf(hmax, float(v))
	hmax = maxf(hmax, 0.001)
	draw_string(font, Vector2(x0, 272), L.t("Havi hiány (TWh)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.SOFT)
	for m in 12:
		var bx := x0 + m * 40.0
		var h0 := float(month_def0[m]) / hmax * 220.0
		var h1 := float(month_def[m]) / hmax * 220.0 if month_def.size() == 12 else h0
		draw_rect(Rect2(bx, y0 - h0, 30, h0), Color(UI.MUTE, 0.25))
		draw_rect(Rect2(bx, y0 - h1, 30, h1), UI.EMBER if m == _month else Color(UI.EMBER, 0.7))
		draw_string(font, Vector2(bx - 6, y0 + 20), str(mn[m]), HORIZONTAL_ALIGNMENT_CENTER, 42, 12, UI.GOLD if m == _month else UI.MUTE)
	draw_line(Vector2(x0 - 4, y0), Vector2(x0 + 480, y0), Color(UI.MUTE, 0.6), 1.0)
