extends Control
## Kezdő animáció (kb. 30 mp; ismételt indításkor rövid, kb. 9 mp).
## A főképernyő saját elemeiből készül, valós idejű: a földgömb (valódi Nap-állás),
## a mai hőmérséklet-eltérés térkép, a valós események és a festett kutatóállomás.
## Esc, szóköz, Enter vagy kattintás: azonnal átugorja.
##
## Snittek: 1. űr → 2. „Ez a Föld ma” → 3. hőmérséklet-eltérés → 4. események →
##          5. kutatóállomás → 6. AETHER logó, áttűnés a játékba.

signal finished

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")

var main                       # main.gd példány (földgömb, világállapot, eltérés-térkép)
var short := false             # rövid változat (ismételt indítás)
var shots_dir := ""            # ha nem üres: minden snittről képernyőkép (önteszt)
var _caption: Label
var _sub: Label
var _hint: Label
var _black: ColorRect
var _station: Control
var _logo: Label
var _done := false
var _hidden: Array = []        # az intro alatt elrejtett felületelemek
var _globe_pos: Vector2
var _globe_scale: Vector2
var _music: AudioStreamPlayer  # lágy handpan-zene (tools/intro_zene_handpan.py állítja elő)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	# a játék felülete az intro alatt nem látszik, csak a háttér, a csillagok és a gömb
	var keep: Array = main.intro_keep()
	for c in main.get_children():
		if c == self or c in keep or not (c is CanvasItem) or not c.visible:
			continue
		c.visible = false
		_hidden.append(c)
	_globe_pos = main.globe.position
	_globe_scale = main.globe.scale
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_caption = UI.label("", 44, UI.GOLD, true, false)
	_caption.add_theme_font_override("font", UI.font_bold)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.position = Vector2(0, 760)
	_caption.size = Vector2(1600, 60)
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("shadow_offset_x", 3)
	_caption.add_theme_constant_override("shadow_offset_y", 3)
	add_child(_caption)
	_sub = UI.label("", 22, UI.TEXT, false, false)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.position = Vector2(0, 822)
	_sub.size = Vector2(1600, 34)
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_sub)
	_hint = UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	_hint.position = Vector2(1460, 870)
	add_child(_hint)
	_start_music()
	_play()


## A zene a főjelenethez kerül, hogy átugráskor / a végén lágyan elhalkulhasson,
## akkor is, ha az intro már eltűnt.
func _start_music() -> void:
	var stream = load("res://assets/hang/intro_handpan.wav")
	if stream == null:
		return
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -6.0
	main.add_child(_music)
	# a rövid változat a dallam közepéről indul (események + zárás)
	_music.play(13.8 if short else 0.0)


func _stop_music() -> void:
	if _music == null or not is_instance_valid(_music):
		return
	var m := _music
	_music = null
	var tw := m.create_tween()
	tw.tween_property(m, "volume_db", -40.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(m.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		skip = true
	elif event is InputEventMouseButton and event.pressed:
		skip = true
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _done:
		accept_event()
		_finish()


## Felirat finom be- és kiúsztatással.
func _say(text: String, sub: String = "") -> void:
	_caption.text = text
	_sub.text = sub
	_caption.modulate.a = 0.0
	_sub.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_caption, "modulate:a", 1.0, 0.5)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.7)


func _wait(sec: float) -> bool:
	await get_tree().create_timer(sec).timeout
	return not _done


func _shot(name: String) -> void:
	if shots_dir == "" or _done:
		return
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name))
	print("INTRO kép: ", shots_dir.path_join(name))


func _globe_to(scale_f: float, sec: float) -> void:
	var g = main.globe
	g.pivot_offset = g.size * 0.5
	create_tween().tween_property(g, "scale", Vector2.ONE * scale_f, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play() -> void:
	var g = main.globe
	g.pivot_offset = g.size * 0.5
	g.home()
	# a gömb a képernyő közepén
	g.position = Vector2((1600 - g.size.x) / 2.0, 60)
	if short:
		await _play_short()
	else:
		await _play_full()
	_finish()


func _play_full() -> void:
	var g = main.globe
	main.load_anomaly_quietly()
	# 1. Csillagos űr, egy fénypont nő: a Föld
	g.scale = Vector2.ONE * 0.04
	create_tween().tween_property(_black, "color:a", 0.0, 1.2)
	_say("2026.")
	_globe_to(0.35, 3.5)
	if not await _wait(1.6): return
	await _shot("intro_1_ur.png")
	if not await _wait(2.2): return
	# 2. Ez a Föld ma (valódi Nap-állás, városfények)
	_say(L.t("Ez a Föld ma."), L.t("Valódi napfény, valódi adatok."))
	_globe_to(1.0, 2.5)
	create_tween().tween_property(g, "spin", g.spin + 0.12, 5.0)
	if not await _wait(3.0): return
	await _shot("intro_2_fold.png")
	if not await _wait(2.0): return
	# 3. Hőmérséklet-eltérés (Copernicus Climate Pulse), ha betöltött
	var t: String = main.warming_text()
	if main.anomaly_ready():
		g.show_anomaly(true)
	_say(L.t("%s – melegebb, mint valaha.") % t, L.t("Piros: ma melegebb, mint az 1991–2020-as átlag."))
	if not await _wait(3.0): return
	await _shot("intro_3_eltérés.png")
	if not await _wait(2.0): return
	g.show_anomaly(false)
	# 4. Valós események villannak fel
	await _events_montage(5.0)
	if _done: return
	# 5. A kutatóállomás (Magyarország felé közelítve)
	g.highlight = {}
	g.home()
	# a gömb háttérbe húzódik, hogy az állomás és a felirat jól látszódjon
	create_tween().tween_property(g, "modulate", Color(0.45, 0.45, 0.5), 1.2)
	_say(L.t("Itt kezdődik a kutatásod."))
	if not await _wait(1.2): return
	_show_station()
	if not await _wait(2.6): return
	await _shot("intro_5_allomas.png")
	if not await _wait(1.2): return
	_hide_station()
	create_tween().tween_property(g, "modulate", Color.WHITE, 1.0)
	# 6. AETHER logó
	_globe_to(0.8, 1.5)
	_show_logo()
	if not await _wait(2.4): return
	await _shot("intro_6_logo.png")
	if not await _wait(1.6): return


func _play_short() -> void:
	var g = main.globe
	g.scale = Vector2.ONE * 0.8
	create_tween().tween_property(_black, "color:a", 0.0, 0.8)
	await _events_montage(4.5)
	if _done: return
	g.highlight = {}
	g.home()
	_show_logo()
	if not await _wait(3.2): return


## 3-4 valós esemény: a gömb odafordul, gyűrű jelöli, egy szó kategóriánként.
func _events_montage(total: float) -> void:
	var g = main.globe
	var words := {"vihar": L.t("Viharok."), "aszaly": L.t("Aszály."), "jeg": L.t("Olvadó jég."),
		"tuz": L.t("Erdőtüzek."), "levego": L.t("Szennyezett levegő."), "arviz": L.t("Árvizek."), "hoseg": L.t("Hőség.")}
	var picked: Array = []
	var seen := {}
	for e in main.world.get("esemenyek", []):
		var k := str(e.get("kategoria", ""))
		if words.has(k) and not seen.has(k) and e.get("lat") != null:
			seen[k] = true
			picked.append(e)
		if picked.size() >= 4:
			break
	if picked.is_empty():
		_say(L.t("Viharok. Aszály. Olvadó jég."))
		await _wait(total)
		return
	var text := ""
	var step := total / picked.size()
	for i in picked.size():
		var e: Dictionary = picked[i]
		g.highlight = e
		g.look_at_event(e)
		text += ("" if text == "" else " ") + str(words[str(e.get("kategoria"))])
		_caption.text = text
		_caption.modulate.a = 1.0
		_sub.text = _short(str(e.get("cim", "")), 90)
		_sub.modulate.a = 1.0
		if not await _wait(step * 0.6): return
		if i == 1:
			await _shot("intro_4_esemenyek.png")
		if not await _wait(step * 0.4): return


## Rövid felirat: szóhatáron vágja, „…”-tel jelzi a vágást.
func _short(s: String, n: int) -> String:
	if s.length() <= n:
		return s
	var cut := s.left(n)
	var sp := cut.rfind(" ")
	return (cut.left(sp) if sp > n / 2 else cut).strip_edges() + "…"


func _show_station() -> void:
	var holder := Control.new()
	var bg: Texture2D = load("res://assets/allomas/hatter.png")
	var sc := 3.0
	holder.size = Vector2(bg.get_width(), bg.get_height()) * sc
	holder.position = Vector2((1600 - holder.size.x) / 2.0, 150)
	for name in ["hatter.png"] + _module_files():
		var t := TextureRect.new()
		t.texture = load("res://assets/allomas/" + name)
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.stretch_mode = TextureRect.STRETCH_SCALE
		var pos := Vector2.ZERO
		if name != "hatter.png":
			pos = {"ai_mag": Vector2(22, 32), "archivum": Vector2(72, 32), "uveghaz": Vector2(122, 32)}[name.get_slice("_", 0) if not name.begins_with("ai_mag") else "ai_mag"] * sc
		t.position = pos
		t.size = Vector2(t.texture.get_width(), t.texture.get_height()) * sc
		holder.add_child(t)
	var frame := ReferenceRect.new()
	frame.border_color = UI.GOLD
	frame.border_width = 3
	frame.editor_only = false
	frame.size = holder.size
	holder.add_child(frame)
	holder.modulate.a = 0.0
	add_child(holder)
	move_child(holder, 1)
	_station = holder
	create_tween().tween_property(holder, "modulate:a", 1.0, 0.8)


## A játékos állomásának modulképei (legalább 1. szintű AI-mag, hogy legyen mit látni).
func _module_files() -> Array:
	var st: Dictionary = main.campaign.station
	return ["ai_mag_%d.png" % maxi(1, int(st.get("ai_mag", 0))),
		"archivum_%d.png" % int(st.get("archivum", 0)), "uveghaz_%d.png" % int(st.get("uveghaz", 0))]


func _hide_station() -> void:
	if _station != null:
		create_tween().tween_property(_station, "modulate:a", 0.0, 0.6)


## Záró kép: nincs szlogen, csak a játék címe – kicsiben, halványan a csillagok
## között „elrejtve”, ahol a figyelmes néző észreveszi.
func _show_logo() -> void:
	_caption.text = ""
	_sub.text = ""
	_logo = UI.label("A E T H E R", 30, UI.CYAN, false, false)
	_logo.add_theme_font_override("font", UI.font_pixel)
	_logo.position = Vector2(1180, 120)
	_logo.size = Vector2(320, 40)
	_logo.modulate.a = 0.0
	add_child(_logo)
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_logo, "modulate:a", 0.42, 1.6).set_trans(Tween.TRANS_SINE)
	# két halk pislákolás, mint egy csillag
	tw.tween_property(_logo, "modulate:a", 0.25, 0.5)
	tw.tween_property(_logo, "modulate:a", 0.42, 0.5)


func _finish() -> void:
	if _done:
		return
	_done = true
	_stop_music()
	var g = main.globe
	g.highlight = {}
	g.show_anomaly(false)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_property(g, "scale", _globe_scale, 0.5)
	tw.tween_property(g, "modulate", Color.WHITE, 0.5)
	tw.tween_property(g, "position", _globe_pos, 0.5)
	for c in _hidden:
		if is_instance_valid(c):
			c.visible = true
			c.modulate.a = 0.0
			tw.tween_property(c, "modulate:a", 1.0, 0.6)
	await tw.finished
	# a félbeszakított snitt-tweenek ne hagyják a gömböt sötéten / rossz méretben
	g.scale = _globe_scale
	g.modulate = Color.WHITE
	g.position = _globe_pos
	g.home()
	finished.emit()
	queue_free()
