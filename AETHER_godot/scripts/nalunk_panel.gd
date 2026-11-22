extends PanelContainer
## „Mit jelent ez nálunk?” – a melegedés a játékos helyén: mért adatok (ERA5) és
## egyszerű becslés a jövőre a játékos terve szerint (IPCC AR6 Atlasz, 34 klímamodell).

signal closed

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Knowledge := preload("res://scripts/knowledge.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

var bridge
var campaign
var lat := 47.5
var lon := 19.0
var country := "HU"
var place := "Budapest"
var _body: VBoxContainer
var _out := ""
var _retry: Timer


## Oszlopdiagram: évente a 30 °C feletti napok (mért), a jövő becslése halványan.
class Bars extends Control:
	var years: Array = []        # [[év, érték], ...] mért
	var future: Array = []       # [[év, érték], ...] becslés
	var vmax := 10.0

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 170)

	func _draw() -> void:
		var all := years + future
		if all.is_empty():
			return
		var y0 := int(all[0][0])
		var y1 := int(all[-1][0])
		var w := size.x
		var h := size.y - 22.0
		var bw := w / float(y1 - y0 + 1)
		var font := ThemeDB.fallback_font
		for e in years:
			var x := (int(e[0]) - y0) * bw
			var bh := h * float(e[1]) / vmax
			draw_rect(Rect2(x + 1, h - bh, maxf(1.0, bw - 2), bh), Color("#f4a23a"))
		for e in future:
			var x := (int(e[0]) - y0) * bw
			var bh := h * float(e[1]) / vmax
			draw_rect(Rect2(x + 1, h - bh, maxf(1.0, bw - 2), bh), Color(0.36, 0.88, 0.82, 0.55))
		draw_line(Vector2(0, h), Vector2(w, h), Color("#5d6784"), 1.0)
		for yy in [y0, 2000, 2025, y1]:
			if yy < y0 or yy > y1:
				continue
			var x: float = (int(yy) - y0) * bw
			draw_string(font, Vector2(x, h + 18), str(yy), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#9aa7c4"))


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
	_body = UI.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(UI.scroll_pad(_body))
	_retry = Timer.new()
	_retry.wait_time = 1.0
	_retry.one_shot = true
	_retry.timeout.connect(_load)
	add_child(_retry)
	bridge.finished.connect(_on_bridge_finished)
	_out = bridge.work_dir("aether_nalunk").path_join("v1_%s_%.2f_%.2f.json" % [country, lat, lon])
	var cached: Variant = Bridge.read_json(_out)
	if typeof(cached) == TYPE_DICTIONARY and not cached.has("hiba"):
		_render(cached)
	else:
		_header()
		_body.add_child(UI.label(L.t("Töltöm a mért adatokat (1961 óta, naponta)…"), 17, UI.SOFT))
		_load()


func _exit_tree() -> void:
	if bridge != null and bridge.finished.is_connected(_on_bridge_finished):
		bridge.finished.disconnect(_on_bridge_finished)


func _load() -> void:
	if not bridge.run("nalunk", ["nalunk", "--lat", str(lat), "--lon", str(lon), "--orszag", country,
			"--hely", place, "--ki", _out, "--nyelv", L.lang]):
		_retry.start()


func _on_bridge_finished(tag: String, _code: int, _output: String) -> void:
	if tag != "nalunk":
		return
	var r: Variant = Bridge.read_json(_out)
	if typeof(r) == TYPE_DICTIONARY and not r.has("hiba"):
		_render(r)
	else:
		_header()
		_body.add_child(UI.label(L.t("Most nem sikerült letölteni a mért adatokat. Van internet?"), 17, UI.EMBER))


func _header() -> void:
	UI.clear(_body)
	_body.add_child(UI.heading(L.t("Mit jelent ez nálunk?") + " · " + place))


## A táblázatból az adott globális melegedéshez tartozó sor (0,1 °C-ra kerekítve, a széleken levágva).
static func row_for(r: Dictionary, t: float) -> Dictionary:
	var tab: Array = r.get("tablazat", [])
	if tab.is_empty() or is_nan(t):
		return {}
	var best: Dictionary = tab[0]
	for row in tab:
		if absf(float(row["globalis"]) - t) < absf(float(best["globalis"]) - t):
			best = row
	return best


func _temp_at(y: int) -> float:
	return campaign.series_at("homerseklet", y) if campaign != null else NAN


func _big(parent: Control, caption: String, value: String, sub: String, color: Color) -> void:
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(caption, 14, UI.MUTE))
	v.add_child(UI.label(value, 26, color, true, false))
	if sub != "":
		v.add_child(UI.label(sub, 13, UI.MUTE))
	parent.add_child(v)


func _render(r: Dictionary) -> void:
	_header()
	var regi: Dictionary = r["regi"]
	var mai: Dictionary = r["mai"]
	var plan_name := L.t("a terved szerint") if campaign != null and not campaign.timeline.is_empty() else L.t("terv nélkül")
	# --- forró napok ---
	var c := UI.card(UI.GOLD)
	c.add_child(UI.label(L.t("Hány nap van évente 30 °C fölött?"), 19, UI.TEXT, true))
	var row := UI.hbox(18)
	_big(row, "%d–%d" % [int(regi["idoszak"][0]), int(regi["idoszak"][1])], L.t("%s nap") % UI.hu(float(regi["napok"]), 0), L.t("mért"), UI.SOFT)
	_big(row, "%d–%d" % [int(mai["idoszak"][0]), int(mai["idoszak"][1])], L.t("%s nap") % UI.hu(float(mai["napok"]), 0), L.t("mért"), UI.GOLD)
	var future: Array = []
	var vmax := 10.0
	for e in r["evek"]:
		vmax = maxf(vmax, float(e["napok"]))
	for y in [2050, 2100]:
		var fr := row_for(r, _temp_at(y))
		if fr.is_empty():
			_big(row, str(y), "?", L.t("még nincs modell"), UI.CYAN)
			continue
		_big(row, "%d · %s" % [y, plan_name], L.t("%s nap") % UI.hu(float(fr["napok"]), 0),
			L.t("kb. %s–%s nap") % [UI.hu(float(fr["napok_also"]), 0), UI.hu(float(fr["napok_felso"]), 0)], UI.CYAN)
	c.add_child(row)
	# oszlopok: mért évek + becslés 2026-tól 2100-ig ötévente
	var bars := Bars.new()
	for e in r["evek"]:
		bars.years.append([int(e["ev"]), float(e["napok"])])
	for y in range(2030, 2101, 5):
		var fr := row_for(r, _temp_at(y))
		if not fr.is_empty():
			future.append([y, float(fr["napok"])])
			vmax = maxf(vmax, float(fr["napok"]))
	bars.future = future
	bars.vmax = vmax * 1.1
	c.add_child(bars)
	c.add_child(UI.label(L.t("Narancs: mért évek. Türkiz: becslés a terved szerint."), 13, UI.MUTE))
	_body.add_child(UI.card_root(c))
	# --- nyári csapadék ---
	var p := UI.card(UI.CYAN)
	p.add_child(UI.label(L.t("Mennyi eső esik nyáron (június–augusztus)?"), 19, UI.TEXT, true))
	var prow := UI.hbox(18)
	_big(prow, "%d–%d" % [int(regi["idoszak"][0]), int(regi["idoszak"][1])], "%s mm" % UI.hu(float(regi["nyari_csapadek"]), 0), L.t("mért"), UI.SOFT)
	_big(prow, "%d–%d" % [int(mai["idoszak"][0]), int(mai["idoszak"][1])], "%s mm" % UI.hu(float(mai["nyari_csapadek"]), 0), L.t("mért"), UI.GOLD)
	var f2100 := row_for(r, _temp_at(2100))
	if not f2100.is_empty():
		_big(prow, "2100 · " + plan_name, "%s mm" % UI.hu(float(f2100["nyari_csapadek"]), 0),
			L.t("kb. %s–%s mm") % [UI.hu(float(f2100["csapadek_also"]), 0), UI.hu(float(f2100["csapadek_felso"]), 0)], UI.CYAN)
	p.add_child(prow)
	_body.add_child(UI.card_root(p))
	_body.add_child(UI.label(L.t("A múlt: időjárási mérésekből, egy kb. 25 km-es területre (a város belsejében melegebb). A jövő: a 2006–2025 között mért napokat annyival melegítjük, amennyit 34 klímamodell átlagosan vár a térségben. Ez nem időjárás-jelentés."), 14, UI.MUTE))
	for s in r.get("forrasok", []):
		_body.add_child(UI.text_link(L.t(str(s["nev"])) + Knowledge.lang_note(str(s["link"])), str(s["link"])))
