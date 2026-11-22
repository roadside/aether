extends PanelContainer
## Egy valós esemény (jelentés) érthetően, külön ablakban:
## rövid összefoglaló a játékos nyelvén (AI-val vagy a forrás adataiból),
## a fontos számok szó szerinti idézettel, a forrás ábrái, és legalul a hivatalos link.

signal closed

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Knowledge := preload("res://scripts/knowledge.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

var bridge
var event: Dictionary = {}
var home := ["Hungary", "Magyarország"]   # a játékos országa (angol, magyar név)
var _body: VBoxContainer
var _summary_box: VBoxContainer
var _out := ""
var _dir := ""
var _retry: Timer


# --- rövid cím és hely (AI nélkül, mindig működik) -------------------------
static func countries_of(e: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for c in str(e.get("orszag", "")).split(","):
		var s := c.strip_edges()
		if s != "":
			out.append(s)
	return out


## A megjelenítendő országnevek: magyar nyelven a magyar nevek (orszag_hu), ha vannak.
static func display_countries(e: Dictionary) -> PackedStringArray:
	if L.is_en() or str(e.get("orszag_hu", "")) == "":
		return countries_of(e)
	return countries_of({"orszag": e["orszag_hu"]})


static func short_place(e: Dictionary) -> String:
	var cs := display_countries(e)
	if cs.size() <= 3:
		return ", ".join(cs)
	return (L.t("%s, %s és még %d ország")) % [cs[0], cs[1], cs.size() - 2]


static func display_title(e: Dictionary, home_country: Array = ["Hungary", "Magyarország"]) -> String:
	var cs := countries_of(e)
	if cs.size() <= 3:
		return L.field(e, "cim")
	var t := L.t("%s %d országban") % [L.category(str(e.get("kategoria", ""))), cs.size()]
	if str(home_country[0]) in cs:
		t += L.t(", köztük %s") % str(home_country[0 if L.is_en() else 1])
	return t


# --- felület ---------------------------------------------------------------
func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.CYAN
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 28
	sb.set_content_margin_all(24)
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = UI.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(UI.scroll_pad(_body))
	bridge.finished.connect(_on_bridge_finished)
	_retry = Timer.new()
	_retry.wait_time = 2.0
	_retry.one_shot = true
	_retry.timeout.connect(_request)
	add_child(_retry)
	_build()
	_request()


func _build() -> void:
	var h := UI.hbox(12)
	var place := short_place(event)
	h.add_child(UI.label(L.category(str(event.get("kategoria", ""))) + (" · " + place if place != "" else ""), 16, UI.MUTE, false))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_body.add_child(h)
	var hd := UI.heading(display_title(event, home), 24)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(hd)
	_body.add_child(UI.label("%s · %s" % [str(event.get("datum", "")), L.field(event, "forras")], 15, UI.MUTE))
	_summary_box = UI.vbox(10)
	_body.add_child(_summary_box)
	_summary_box.add_child(UI.label(L.t("Összefoglaló készül a forrásból…"), 17, UI.SOFT))


func _request() -> void:
	var key := str(event.get("link", "")) + "|" + str(event.get("cim", ""))
	_dir = bridge.work_dir("aether_esemenyek").path_join(key.md5_text().left(16))
	DirAccess.make_dir_recursive_absolute(_dir)
	var ai: String = L.get_setting("ai", "none")
	_out = _dir.path_join("reszlet3_%s_%s.json" % [L.lang, ai])   # 3: magyar országnevek, hazai kiemelés
	var cached: Variant = Bridge.read_json(_out)
	if typeof(cached) == TYPE_DICTIONARY:
		_show(cached)
		return
	var inp := _dir.path_join("esemeny.json")
	Bridge.write_json(inp, event)
	if not bridge.run("reszlet", ["esemeny-reszlet", inp, "--mappa", _dir, "--ki", _out, "--ai", ai, "--nyelv", L.lang,
			"--orszag", L.country()]):
		_retry.start()   # a játék épp mással dolgozik: kicsit később újra


func _on_bridge_finished(tag: String, code: int, output: String) -> void:
	if tag != "reszlet":
		return
	var r: Variant = Bridge.read_json(_out)
	if code != 0 or typeof(r) != TYPE_DICTIONARY:
		UI.clear(_summary_box)
		_summary_box.add_child(UI.label(L.t("Az összefoglaló nem készült el. Lent a forrás."), 17, UI.EMBER))
		print(output)
		_add_source_button()
		return
	_show(r)


func _show(r: Dictionary) -> void:
	UI.clear(_summary_box)
	var c := UI.card(UI.GOLD)
	var ai := str(r.get("osszegzes_tipus", "")) == "ai"
	c.add_child(UI.label(L.t("Összefoglaló (AI, a forrás alapján)") if ai else L.t("Összefoglaló (a forrás saját adataiból)"), 15, UI.GOLD, true))
	c.add_child(UI.label(str(r.get("osszegzes", "")), 18, UI.TEXT))
	if ai:
		c.add_child(UI.label(L.t("A számokat a játék a forrásban ellenőrizte."), 13, UI.MUTE))
	_summary_box.add_child(UI.card_root(c))
	if str(r.get("miert_fontos", "")) != "":
		var w := UI.card(UI.GREEN)
		w.add_child(UI.label(L.t("Miért fontos, és mi köze a klímához?"), 15, UI.GREEN, true))
		w.add_child(UI.label(str(r["miert_fontos"]), 17, UI.TEXT))
		var src: Variant = r.get("miert_forras")
		if typeof(src) == TYPE_DICTIONARY:
			var surl := str(src.get("link", ""))
			var sb := UI.button(L.t("Forrás: ") + str(src.get("nev", "")) + Knowledge.lang_note(surl))
			var s_fn := func() -> void: OS.shell_open(surl)
			sb.pressed.connect(s_fn)
			w.add_child(sb)
		_summary_box.add_child(UI.card_root(w))

	var nums: Array = r.get("fobb_szamok", [])
	if not nums.is_empty():
		_summary_box.add_child(UI.label(L.t("Fontos számok"), 17, UI.CYAN, true))
		for n in nums:
			var nc := UI.card(UI.CYAN)
			nc.add_child(UI.label("%s  ·  %s" % [str(n.get("ertek", "")), str(n.get("jelentes", ""))], 17, UI.TEXT, true))
			nc.add_child(UI.label("„" + str(n.get("idezet", "")) + "”", 14, UI.MUTE))
			_summary_box.add_child(UI.card_root(nc))

	for im in r.get("kepek", []):
		var img := Image.new()
		if img.load(str(im.get("fajl", ""))) != OK:
			continue
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var w := 760.0
		tr.custom_minimum_size = Vector2(w, min(420.0, w * img.get_height() / max(1.0, float(img.get_width()))))
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_summary_box.add_child(tr)
		var cap := str(im.get("alt", ""))
		_summary_box.add_child(UI.label((cap + " · " if cap != "" else "") + L.t("Ábra a forrásból"), 13, UI.MUTE))

	_add_source_button()


func _add_source_button() -> void:
	var link := str(event.get("link", ""))
	if link == "":
		return
	# Ha a link adatfájl (pl. CSV), a fő gomb a forrás honlapját nyitja meg, ne letöltést indítson.
	var path := link.split("?")[0].to_lower()
	var is_data := false
	for ext in [".csv", ".json", ".geojson", ".xml", ".txt", ".zip", ".kml", ".kmz", ".nc"]:
		if path.ends_with(ext):
			is_data = true
	if not is_data:
		var b := UI.button(L.t("Hivatalos forrás megnyitása (eredeti nyelven)"))
		var open_fn := func() -> void: OS.shell_open(link)
		b.pressed.connect(open_fn)
		_summary_box.add_child(b)
	else:
		_add_data_buttons(link, path)
	_add_worldview_button()


func _add_data_buttons(link: String, path: String) -> void:
	var parts := link.split("/")
	var home := "%s//%s/" % [parts[0], parts[2]] if parts.size() > 2 else link
	var hb := UI.button(L.t("A forrás honlapja: ") + (parts[2] if parts.size() > 2 else link) + Knowledge.lang_note(home))
	var home_fn := func() -> void: OS.shell_open(home)
	hb.pressed.connect(home_fn)
	_summary_box.add_child(hb)


## Műholdkép az esemény napjáról és helyéről (NASA Worldview), ha van koordináta.
func _add_worldview_button() -> void:
	var lat: Variant = event.get("lat")
	var lon: Variant = event.get("lon")
	if typeof(lat) in [TYPE_INT, TYPE_FLOAT] and typeof(lon) in [TYPE_INT, TYPE_FLOAT]:
		var wv := "https://worldview.earthdata.nasa.gov/?v=%.1f,%.1f,%.1f,%.1f&t=%s" % [
			maxf(-180.0, float(lon) - 8.0), maxf(-90.0, float(lat) - 6.0), minf(180.0, float(lon) + 8.0), minf(90.0, float(lat) + 6.0), str(event.get("datum", "")).left(10)]
		var wb := UI.button(L.t("Műholdkép aznapról (NASA Worldview)") + Knowledge.lang_note("en"))
		var wv_fn := func() -> void: OS.shell_open(wv)
		wb.pressed.connect(wv_fn)
		_summary_box.add_child(wb)
