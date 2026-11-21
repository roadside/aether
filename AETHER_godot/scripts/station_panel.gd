extends PanelContainer
## A kutatóállomás: festett pixeles kép, amely szintenként bővül, és alatta
## a három modul kártyája (mit ad most, mit ad a következő szint, mennyibe kerül).

signal closed
signal built(note: String)

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Campaign := preload("res://scripts/campaign.gd")

const SCALE := 3
## A modulok helye a háttérképen (pixelben, nagyítás előtt).
const POS := {"ai_mag": Vector2(22, 32), "archivum": Vector2(72, 32), "uveghaz": Vector2(122, 32)}
const ORDER := ["ai_mag", "archivum", "uveghaz"]

var campaign
var _body: VBoxContainer


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
	campaign.changed.connect(rebuild)
	rebuild()


func _exit_tree() -> void:
	if campaign != null and campaign.changed.is_connected(rebuild):
		campaign.changed.disconnect(rebuild)


func rebuild() -> void:
	if _body == null:
		return
	UI.clear(_body)
	var h := UI.hbox(12)
	h.add_child(UI.heading(L.t("Kutatóállomás")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var x := UI.button(L.t("Bezárás"))
	var close_fn := func() -> void: closed.emit()
	x.pressed.connect(close_fn)
	h.add_child(x)
	_body.add_child(h)
	_body.add_child(UI.label(L.t("Fejleszd az állomásodat: több és alaposabb kutatás, több bizalom. Egy modul építése 1 évig tart."), 16, UI.SOFT))
	_body.add_child(_picture())
	var row := UI.hbox(10)
	for mod in ORDER:
		row.add_child(_card(mod))
	_body.add_child(row)


func _picture() -> Control:
	var holder := Control.new()
	var bg: Texture2D = load("res://assets/allomas/hatter.png")
	holder.custom_minimum_size = Vector2(bg.get_width(), bg.get_height()) * SCALE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(_sprite(bg, Vector2.ZERO))
	for mod in ORDER:
		var lvl := int(campaign.station[mod])
		var tex: Texture2D = load("res://assets/allomas/%s_%d.png" % [mod, lvl])
		var spr := _sprite(tex, POS[mod] * SCALE)
		if not campaign.building.is_empty() and str(campaign.building["modul"]) == mod:
			spr.modulate = Color(1, 1, 1, 0.55)   # épül: halványan
		spr.tooltip_text = "%s · %s" % [L.t(Campaign.MODULES[mod]["nev"]), _level_text(lvl)]
		holder.add_child(spr)
	return holder


func _sprite(tex: Texture2D, pos: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = pos
	t.size = Vector2(tex.get_width(), tex.get_height()) * SCALE
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	return t


func _level_text(lvl: int) -> String:
	return L.t("még nincs") if lvl == 0 else L.t("%d. szint") % lvl


## Mit ad a modul az adott szinten (egy rövid mondat).
func _effect(mod: String, lvl: int) -> String:
	match mod:
		"ai_mag":
			return L.t("%d cikket néz át, évente %d kutatás.") % [12 + 4 * lvl, 2 + lvl]
		"archivum":
			return L.t("Egy kutatás ára: %d pénz.") % (Campaign.RESEARCH_COST - 8 * lvl)
		"uveghaz":
			return L.t("Évente +%d bizalom.") % lvl if lvl > 0 else L.t("Nincs bizalom-bónusz.")
	return ""


func _why(mod: String) -> String:
	match mod:
		"ai_mag":
			return L.t("Nagyobb számítási kapacitás: több cikket olvas el, de egy kutatás tovább tart.")
		"archivum":
			return L.t("Cikktár: a már letöltött cikkeket nem kell újra keresni.")
		"uveghaz":
			return L.t("Helyi kísérletek: az emberek a saját szemükkel látják az eredményt.")
	return ""


func _card(mod: String) -> Control:
	var lvl := int(campaign.station[mod])
	var c := UI.card(UI.CYAN)
	c.custom_minimum_size = Vector2(270, 0)
	var is_building: bool = not campaign.building.is_empty() and str(campaign.building["modul"]) == mod
	var title := L.t(Campaign.MODULES[mod]["nev"]) + " · " + (L.t("épül") if is_building else _level_text(lvl))
	c.add_child(UI.label(title, 18, UI.TEXT, true))
	c.add_child(UI.label(_why(mod), 14, UI.SOFT))
	c.add_child(UI.label(L.t("Most: ") + _effect(mod, lvl), 15, UI.TEXT))
	if is_building:
		c.add_child(UI.label(L.t("Épül, kész: %d.") % int(campaign.building["kesz"]), 16, UI.GOLD, true))
	elif lvl < Campaign.MAX_LEVEL:
		c.add_child(UI.label(L.t("Következő szint: ") + _effect(mod, lvl + 1), 15, UI.GREEN))
		var b := UI.button(L.t("Építés: %d pénz") % campaign.module_cost(mod), true)
		var problem: String = campaign.build_problem(mod)
		if problem != "":
			b.disabled = true
			b.tooltip_text = problem
		var build_fn := func() -> void:
			built.emit(campaign.build(mod))
		b.pressed.connect(build_fn)
		c.add_child(b)
		if problem != "":
			c.add_child(UI.label(problem, 13, UI.EMBER))
	else:
		c.add_child(UI.label(L.t("Kész, legmagasabb szint."), 15, UI.GOLD))
	return UI.card_root(c)
