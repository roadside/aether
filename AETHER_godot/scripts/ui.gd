extends RefCounted
## Közös felület-segédek: színek, betűk, címkék, gombok.
## Használat: const UI := preload("res://scripts/ui.gd")  ->  UI.label("szöveg")

const GOLD := Color("#f4c85a")
const CYAN := Color("#63f3e2")
const EMBER := Color("#f07a4a")
const GREEN := Color("#8fe388")
const TEXT := Color("#f2f4f8")
const SOFT := Color("#c9d1de")
const MUTE := Color("#a7b2c4")
const PANEL_BG := Color(0.043, 0.063, 0.114, 0.96)
const CARD_BG := Color(0.09, 0.13, 0.22, 1.0)
const EDGE := Color("#33476b")

static var font_body: FontFile
static var font_bold: FontFile
static var font_pixel: FontFile


static func load_fonts() -> void:
	if font_body == null:
		font_body = load("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
		font_bold = load("res://assets/fonts/AtkinsonHyperlegible-Bold.ttf")
		font_pixel = load("res://assets/fonts/PixelifySans.ttf")


static func label(text: String, fsize: int = 18, color: Color = TEXT, bold: bool = false, wrap: bool = true) -> Label:
	load_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func heading(text: String, fsize: int = 26) -> Label:
	var l := label(text, fsize, GOLD, false, false)
	l.add_theme_font_override("font", font_pixel)
	return l


static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1f6f66")
		sb.border_color = CYAN
		sb.set_border_width_all(2)
		sb.set_content_margin_all(12)
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		b.add_theme_stylebox_override("normal", sb)
		var sh: StyleBoxFlat = sb.duplicate()
		sh.bg_color = Color("#2a8a7f")
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_color_override("font_color", Color.WHITE)
	return b


## Kártya: halvány háttér, bal oldali színes csík.
static func card(accent: Color = CYAN) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = accent
	sb.border_width_left = 5
	sb.set_content_margin_all(12)
	sb.content_margin_left = 16
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


## A card() által visszaadott belső VBox szülő-panelje (ezt kell a fába tenni).
static func card_root(inner: VBoxContainer) -> Control:
	return inner.get_parent() as Control


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Szám a választott nyelv tizedesjelével (magyarul vessző, angolul pont).
static func hu(x: float, decimals: int = 1) -> String:
	return preload("res://scripts/i18n.gd").num(x, decimals)
