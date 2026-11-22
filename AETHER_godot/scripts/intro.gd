extends Control
## Kezdő animáció (kb. 66 mp), minden indításkor. Esc, szóköz, Enter vagy kattintás átugorja.
## A főképernyő saját elemeiből készül, valós idejű: a földgömb (valódi Nap-állás), az évszámláló
## a valódi éves eltéréssel, a mai hőmérséklet-eltérés térkép, a festett képek.
##
## Nyitány (0–11 mp): egy handpanen játszó, erdőben ülő alak (saját, festett pixeles figura,
## nem valódi személy képmása); a keze a zene ütéseire mozdul. Utána jönnek az alábbi snittek.
## Snittek (mp, a bevezető kezdetétől; a zene 65,9 mp):
##   0–11       nyitány: a handpan-játékos az erdőben
##   11–14      űr, „2026.” – egy fénypontból nő ki a Föld
##   14–18,5    „Ez a Föld ma.”
##   18,5–26    évszámláló 1940-től máig a VALÓDI éves eltéréssel, alul melegedési csíkok
##              (Copernicus Climate Pulse; ha még nincs letöltve, számok nélkül megy)
##   26–31      a mai hőmérséklet-eltérés térkép
##   31–47      négy festett pixeles kép (olvadó jég, aszály, árvíz, erdőtűz), 4–4 mp
##   47–52      hívás: a játékos helyén fény gyúl, fényívek futnak a világ sok pontjára
##   52–57,5    a görbe elágazik: „A jövő még nincs megírva.” (a jövő vonalai jelképek)
##   57,5–65,5  a Föld, a cím halványan a csillagok között, az utolsó dallam alatt
## Zene: ha a játékos gépén ott van a saját zenefájl (sajat_zene/intro.wav a projektmappában,
## vagy user://sajat_zene/intro.wav), azt játssza; ez a fájl NEM része a játéknak és nem kerül
## fel a GitHubra (más szerző jogvédett felvétele lehet). Ha nincs, a saját, kódból előállított
## handpan dallam szól (tools/intro_zene_handpan.py). A zene a végén lágyan elhalkul.

signal finished

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

const W := 1600.0
const H := 900.0
const U := 5.0                 # a festett képek egy „pixele” (320×180-as vászon)
const SCENE_LEN := 4.0         # egy festett kép ennyi mp
const SCENE_SPEED := 0.55      # a festett képek mozgása ennyivel lassabb (nyugodtabb)

const PRELUDE := 11.0          # a handpan-játékos nyitány hossza
## A zene ne érjen véget a cím előtt: a darab vége előtt (CONT_BEFORE mp-cel) lágyan
## újraindul egy nyugodt pontjáról (CONT_FROM), és a bevezető után is szól még egy kicsit,
## a játék elején lassan (END_FADE mp alatt) halkul el.
const CONT_BEFORE := 5.0
const CONT_FROM := 12.0
const END_FADE := 9.0
const OWN_MUSIC := ["res://sajat_zene/intro.wav", "user://sajat_zene/intro.wav"]
## A nyitány ütései (mp) a saját zenefájl első 11 másodpercéből kimérve: [idő, kéz (0 bal, 1 jobb), hangmező]
const HITS := [[3.09, 1, 0], [3.36, 0, 3], [4.18, 1, 2], [4.46, 0, 1], [5.07, 1, 4], [5.61, 0, 5], [5.90, 1, 0],
	[6.17, 0, 3], [6.45, 1, 6], [6.70, 0, 1], [7.56, 1, 2], [7.85, 0, 5], [8.41, 1, 0]]
var main                       # main.gd példány (földgömb, világállapot, eltérés-térkép)
var shots_dir := ""            # ha nem üres: minden snittről képernyőkép (ellenőrzéshez)
var _caption: Label
var _sub: Label
var _hint: Label
var _locked := false           # az előhang alatt nincs átugrás
var _pro: Label                # az előhang középre írt mondatai
var _black: ColorRect
var _logo: Control
var _done := false
var _hidden: Array = []        # az intro alatt elrejtett felületelemek
var _globe_pos: Vector2
var _globe_scale: Vector2
var _globe_center: Vector2     # a gömb helye az intro alatt (képernyő közepe)
var _music: AudioStreamPlayer  # lágy handpan-zene (tools/intro_zene_handpan.py állítja elő)
var _dim: ColorRect            # a gömb shadere nem veszi figyelembe a modulate-et: ezzel sötétítünk
var _fx: Control               # rajzolt előtér: évszámláló, festett képek, elágazó görbe
var _t := 0.0                  # az intro kezdete óta eltelt idő
var _music2: AudioStreamPlayer # a zene folytatása (ugyanaz a darab, egy nyugodt pontjáról)
var _natural_end := false      # a bevezető magától ért véget (nem átugrották)
var _mode := ""                # "jatekos" | "szamlalo" | "kep" | "jovo" | ""
var _mode_t0 := 0.0            # az aktuális rajzolt jelenet kezdete (_t-ben)
var _scene_idx := 0
var _years: Array = []         # [[év, eltérés], ...] valódi adat; üres, ha még nincs letöltve
var _today: Dictionary = {}    # Climate Pulse „ma”: dátum, eltérés (1991–2020 / iparosodás előtti)
var _today_rank := 0           # a mai nap hányadik a mért években (1 = a legmelegebb ilyen nap)
var _pre_industrial := false   # az eltérés az iparosodás előtti szinthez képest értendő-e
var _vmin := 0.0
var _vmax := 1.0
var _year_now := 2026


## A Climate Pulse éves adatok helye (a „pulse --ki” parancs írja, naponta egyszer frissül).
static func pulse_path() -> String:
	return OS.get_user_data_dir().path_join("aether_vilag").path_join("pulse_levego.json")


func _ready() -> void:
	# a szülő mérete nem mindig ismert: kifejezetten a teljes (1600×900-as) képre feszül
	position = Vector2.ZERO
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	if shots_dir == "":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN   # a bevezető alatt nincs kurzor
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
	_black.size = Vector2(W, H)
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
	_year_now = int(Time.get_date_dict_from_system()["year"])
	_load_data()
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.01, 0.03, 0.0)
	_dim.size = Vector2(W, H)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	move_child(_dim, 1)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	move_child(_fx, 2)             # a fekete áttűnés és a sötétítés fölött, a feliratok alatt
	_hint = UI.label(L.t("Esc: átugrás"), 14, UI.MUTE, false, false)
	_hint.position = Vector2(1460, 870)
	add_child(_hint)
	_pro = UI.label("", 40, UI.TEXT, false, false)
	_pro.add_theme_font_override("font", UI.font_body)
	_pro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pro.position = Vector2(250, 300)
	_pro.size = Vector2(1100, 300)
	_pro.modulate.a = 0.0
	add_child(_pro)
	_play()


## A zene a főjelenethez kerül, hogy átugráskor / a végén lágyan elhalkulhasson,
## akkor is, ha az intro már eltűnt.
func _start_music() -> void:
	var stream: AudioStream = null
	for path in OWN_MUSIC:        # a játékos saját zenefájlja, ha van (nem része a játéknak)
		var full := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(full):
			stream = AudioStreamWAV.load_from_file(full)
			if stream != null:
				break
	if stream == null:
		stream = load("res://assets/hang/intro_handpan.wav")
	if stream == null:
		return
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -4.0
	main.add_child(_music)
	_music.play()


## A darab vége előtt a folytatás lágyan beúszik (az eredeti közben magától lecseng).
func _continue_music() -> void:
	if _music2 != null or _music == null or not is_instance_valid(_music) or not _music.playing:
		return
	var length := _music.stream.get_length()
	if length <= CONT_FROM + CONT_BEFORE or _music.get_playback_position() < length - CONT_BEFORE:
		return
	_music2 = AudioStreamPlayer.new()
	_music2.stream = _music.stream
	_music2.volume_db = -30.0
	main.add_child(_music2)
	_music2.play(CONT_FROM)
	_music2.create_tween().tween_property(_music2, "volume_db", -4.0, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Átugráskor gyorsan (2 mp), a bevezető természetes végén lassan (END_FADE) halkul el,
## így a zene a játék elején még szól egy kicsit.
func _stop_music() -> void:
	var fade := END_FADE if _natural_end else 2.0
	for m in [_music, _music2]:
		if m == null or not is_instance_valid(m):
			continue
		var tw: Tween = m.create_tween()
		tw.tween_property(m, "volume_db", -45.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(m.queue_free)
	_music = null
	_music2 = null


func _unhandled_input(event: InputEvent) -> void:
	# képkészítő próbafutásnál nem lehet átugrani (egy véletlen kattintás ne szakítsa meg)
	if _done or shots_dir != "":
		return
	if _locked:                   # a cím és a három mondat nem ugorható át
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
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
		if shots_dir != "" or _locked:
			return
		_finish()


## Felirat finom be- és kiúsztatással.
func _say(text: String, sub: String = "") -> void:
	_caption.text = text
	_sub.text = sub
	_caption.modulate.a = 0.0
	_sub.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_caption, "modulate:a", 1.0, 0.9)
	tw.tween_property(_sub, "modulate:a", 1.0, 1.2)


## A felirat (és az alsó sor) lágyan eltűnik.
func _fade_caption(sec: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_caption, "modulate:a", 0.0, sec)
	tw.tween_property(_sub, "modulate:a", 0.0, sec)


func _process(delta: float) -> void:
	_t += delta
	if _mode != "":
		_fx.queue_redraw()
	_continue_music()


func _wait(sec: float) -> bool:
	await get_tree().create_timer(sec).timeout
	return not _done


func _globe_to(scale_f: float, sec: float) -> void:
	var g = main.globe
	g.pivot_offset = g.size * 0.5
	create_tween().tween_property(g, "scale", Vector2.ONE * scale_f, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A háttér (gömb, csillagok) sötétítése a rajzolt jelenetek / az állomás mögött.
func _dim_to(a: float, sec: float) -> void:
	create_tween().tween_property(_dim, "color:a", a, sec).set_trans(Tween.TRANS_SINE)


func _set_mode(m: String) -> void:
	_mode = m
	_mode_t0 = _t
	_fx.queue_redraw()


func _end_mode() -> void:
	_mode = ""
	_fx.queue_redraw()


func _play() -> void:
	var g = main.globe
	g.pivot_offset = g.size * 0.5
	g.home()
	# a gömb a képernyő közepén
	g.position = Vector2((W - g.size.x) / 2.0, 60)
	_globe_center = g.position
	await _play_full()
	_natural_end = not _done
	_finish()


func _play_full() -> void:
	var g = main.globe
	main.load_anomaly_quietly()
	g.scale = Vector2.ONE * 0.04
	# Előhang, még zene nélkül: a cím és három mondat (kb. 27 mp)
	_locked = true
	_hint.visible = false
	if not await _prologue(): return
	_locked = false
	_hint.visible = true
	_start_music()
	# 0. Nyitány: a handpan-játékos az erdőben (11 mp)
	_set_mode("jatekos")
	if not await _wait(7.0): return
	await _shot("intro_00_jatekos.png")
	if not await _wait(PRELUDE - 7.0): return
	_end_mode()
	# Időrend (a zene 65,9 mp; az utolsó dallam 56–61,5 mp között szól, a cím ez alatt jön fel):
	#   nyitány 11 · űr 3 · Föld 4,5 · évszámláló 7,5 · eltérés 5 · festett képek 16 ·
	#   hívás 5 · jövő 5,5 → a cím 57,5 mp-nél, és 8 mp-ig marad (65,5 mp).
	# 1. Csillagos űr, egy fénypont nő: a Föld (3 mp)
	create_tween().tween_property(_black, "color:a", 0.0, 1.2)
	_say("2026.")
	_globe_to(0.35, 2.8)
	if not await _wait(1.5): return
	await _shot("intro_01_ur.png")
	if not await _wait(1.5): return
	# 2. Ez a Föld ma (valódi Nap-állás, városfények) (4,5 mp)
	_say(L.t("Ez a Föld ma."))
	_globe_to(1.0, 3.0)
	create_tween().tween_property(g, "spin", g.spin + 0.14, 8.0)
	if not await _wait(3.0): return
	await _shot("intro_02_fold.png")
	if not await _wait(1.5): return
	# 3. Évszámláló: 1940-től máig, a gömb közben „melegszik” (7,5 mp)
	_say(L.t("Egyre melegebb..."))
	create_tween().tween_property(g, "position:x", _globe_center.x - 230.0, 1.5).set_trans(Tween.TRANS_SINE)
	_globe_to(0.9, 1.5)
	_set_mode("szamlalo")
	if not await _wait(4.5): return
	await _shot("intro_03_szamlalo.png")
	if not await _wait(3.0): return
	_end_mode()
	# 4. A mai hőmérséklet-eltérés (Copernicus Climate Pulse), ha betöltött (5 mp)
	create_tween().tween_property(g, "position:x", _globe_center.x, 1.2).set_trans(Tween.TRANS_SINE)
	_globe_to(1.0, 1.2)
	create_tween().tween_property(g, "heat", 0.0, 1.0)
	if main.anomaly_ready():
		g.show_anomaly(true)
	var cap: Array = _today_caption()
	_say(cap[0], cap[1])
	if not await _wait(3.0): return
	await _shot("intro_04_elteres.png")
	if not await _wait(2.0): return
	# 5. Négy festett kép, 4–4 mp, puha sötét áttűnéssel (16 mp)
	var words := [L.t("Olvadó jég."), L.t("Aszály."), L.t("Árvizek."), L.t("Erdőtüzek.")]
	var cats := ["jeg", "aszaly", "arviz", "tuz"]
	for i in 4:
		_scene_idx = i
		_set_mode("kep")
		if i == 0:
			g.show_anomaly(false)
		_say(str(words[i]))          # minden képnél csak a saját szava, külön-külön
		_sub.text = ""
		if not await _wait(SCENE_LEN * 0.6): return
		await _shot("intro_%02d_kep_%s.png" % [5 + i, cats[i]])
		if not await _wait(SCENE_LEN * 0.4): return
	_end_mode()
	# 6. Hívás (5 mp): a gömb a játékos helyére fordul, ott kigyullad egy fény, és tőle
	#    fényívek indulnak a világ sok pontjára, ahol sorra új fények gyúlnak:
	#    egy kérdésből sokak munkája lesz.
	g.home()
	_globe_to(1.05, 1.5)
	_dim_to(0.25, 1.0)
	_say(L.t("Minden változás egyetlen kérdéssel kezdődik."))
	_set_mode("hivas")
	if not await _wait(3.1): return
	_say(L.t("A tiéddel."))
	if not await _wait(1.2): return
	await _shot("intro_09_hivas.png")
	if not await _wait(0.7): return
	_end_mode()
	# 7. A görbe elágazik: a jövő még nincs megírva (5,5 mp)
	_dim_to(0.68, 1.0)
	_set_mode("jovo")
	if not await _wait(1.0): return          # „A tiéddel.” még 1 mp-ig a képernyőn marad
	_fade_caption(0.6)
	if not await _wait(1.0): return          # a felirat a görbe elágazásakor jön
	_say(L.t("A jövő még nincs megírva."))
	if not await _wait(2.5): return
	await _shot("intro_10_jovo.png")
	if not await _wait(1.0): return
	_end_mode()
	# 8. A Föld, a cím halványan a csillagok között (8 mp, az utolsó dallam alatt)
	_dim_to(0.0, 1.2)
	_globe_to(0.8, 2.5)
	_show_logo()
	if not await _wait(4.0): return
	await _shot("intro_11_vege.png")
	if not await _wait(4.0): return


## A hőtérkép snittjének felirata CSAK valódi mérésből (Copernicus Climate Pulse, „ma”):
## az iparosodás előtti szinthez mért eltérés, ha van, különben az 1991–2020-as átlaghoz mért.
## „Melegebb, mint valaha” csak akkor, ha a mai nap a valaha mért legmelegebb ilyen nap.
## Ha nincs adat, nincs szám sem (a játék modelljének becslését itt nem mutatjuk).
## Előhang a zene előtt: 2 mp sötét, felfénylik a cím a jelentésével (7 mp),
## majd három mondat egymás után, mindegyik sötétből jön és sötétbe megy.
const PRO_LINES := [
	["A játékban minden adat, grafikon és hír valós.", 3.6],
	["Minden tudományos cikk forrásmegjelöléssel megtalálható, így bárki elolvashatja.", 4.8],
	["Talán köztük van a megoldás...", 3.6],
]
## A cím feloldása (a játékterv szerint); a páros indexű darabok a kiemelt kezdőbetűk.
const TITLE_PARTS := ["A", "rtificial Intelligence for ", "E", "arth's ", "Th", "ermal & ", "E", "cological ", "R", "ecovery"]


func _prologue() -> bool:
	if not await _wait(2.0): return false
	_set_mode("cim")
	if not await _wait(3.4): return false
	await _shot("intro_a_cim.png")
	if not await _wait(TITLE_IN + TITLE_HOLD + TITLE_OUT - 3.4): return false
	_end_mode()
	for i in PRO_LINES.size():
		_pro.text = L.t(PRO_LINES[i][0])
		create_tween().tween_property(_pro, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
		if not await _wait(1.1 + float(PRO_LINES[i][1]) * 0.5): return false
		await _shot("intro_b_felirat_%d.png" % (i + 1))
		if not await _wait(float(PRO_LINES[i][1]) * 0.5): return false
		create_tween().tween_property(_pro, "modulate:a", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
		if not await _wait(1.5): return false
	return true


const TITLE_IN := 1.6
const TITLE_HOLD := 7.0
const TITLE_OUT := 1.4
## A cím betűi vonalakból (egységnyi magas, 0,7 széles dobozban; y lefelé nő).
const GLYPHS := {
	"A": [[Vector2(0, 1), Vector2(0.35, 0), Vector2(0.7, 1)], [Vector2(0.23, 0.66), Vector2(0.47, 0.66)]],
	"E": [[Vector2(0, 0), Vector2(0.66, 0)], [Vector2(0, 0.5), Vector2(0.5, 0.5)], [Vector2(0, 1), Vector2(0.66, 1)]],
	"T": [[Vector2(0, 0), Vector2(0.7, 0)], [Vector2(0.35, 0), Vector2(0.35, 1)]],
	"H": [[Vector2(0, 0), Vector2(0, 1)], [Vector2(0.7, 0), Vector2(0.7, 1)], [Vector2(0, 0.5), Vector2(0.7, 0.5)]],
	"R": [[Vector2(0, 1), Vector2(0, 0), Vector2(0.42, 0), Vector2(0.56, 0.04), Vector2(0.65, 0.13), Vector2(0.68, 0.25),
		Vector2(0.65, 0.37), Vector2(0.56, 0.46), Vector2(0.42, 0.5), Vector2(0, 0.5)], [Vector2(0.36, 0.5), Vector2(0.7, 1)]],
}


## A cím: vékony, fénylő vonalbetűk; felfénylik, egy fénycsík fut végig rajta, majd elsötétül.
func _draw_title(lt: float) -> void:
	var a := _ss(0.0, TITLE_IN, lt) * (1.0 - _ss(TITLE_IN + TITLE_HOLD, TITLE_IN + TITLE_HOLD + TITLE_OUT, lt))
	if a <= 0.0:
		return
	var word := "AETHER"
	var hgt := 170.0
	var gap := 78.0
	var lw := 0.7 * hgt
	var total := word.length() * lw + (word.length() - 1) * gap
	var x0 := (W - total) / 2.0
	var y0 := 290.0
	var flash := 1.0 + 0.9 * (1.0 - _ss(TITLE_IN * 0.6, TITLE_IN + 1.2, lt)) * _ss(0.2, TITLE_IN, lt)   # felfénylés
	var sweep_x := x0 - 200.0 + (total + 400.0) * _ss(TITLE_IN + 0.3, TITLE_IN + 2.6, lt)
	for i in word.length():
		var ox := x0 + i * (lw + gap)
		var near := exp(-pow((ox + lw * 0.5 - sweep_x) / 150.0, 2.0))
		var bright := a * minf(flash + 0.8 * near, 2.0)
		for stroke in GLYPHS[word[i]]:
			var pts := PackedVector2Array()
			for q in stroke:
				pts.append(Vector2(ox + q.x * hgt, y0 + q.y * hgt))
			for pass_i in [[30.0, 0.035], [18.0, 0.07], [10.0, 0.14]]:
				_fx.draw_polyline(pts, Color(0.39, 0.95, 0.89, pass_i[1] * bright), pass_i[0], true)
			var core := Color(0.80, 1.0, 0.97).lerp(Color.WHITE, clampf(bright - 1.0, 0.0, 1.0))
			core.a = clampf(bright, 0.0, 1.0)
			_fx.draw_polyline(pts, core, 5.0, true)
			for q in [pts[0], pts[pts.size() - 1]]:
				_fx.draw_circle(q, 2.5, core)
	# vékony vonal a cím színében, és a cím jelentése
	var a2 := a * _ss(TITLE_IN * 0.7, TITLE_IN + 0.9, lt)
	_fx.draw_line(Vector2(W / 2.0 - 190.0, y0 + hgt + 62), Vector2(W / 2.0 + 190.0, y0 + hgt + 62), Color(0.80, 1.0, 0.97, 0.85 * a), 2.0, true)
	var fs := 34
	var full := "".join(PackedStringArray(TITLE_PARTS))
	var px := (W - UI.font_body.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) / 2.0
	for i in TITLE_PARTS.size():
		var part: String = TITLE_PARTS[i]
		var hi := i % 2 == 0
		var f: Font = UI.font_bold if hi else UI.font_body
		var col := Color(0.39, 0.95, 0.89, a2) if hi else Color(0.95, 0.96, 0.97, 0.9 * a2)
		_fx.draw_string(f, Vector2(px, y0 + hgt + 124), part, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		px += f.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _today_caption() -> Array:
	var v: Variant = _today.get("elteres_ipar_elott")
	var basis := L.t("az iparosodás előtti (1850–1900) átlaghoz képest")
	if v == null:
		v = _today.get("elteres_1991_2020")
		basis = L.t("az 1991–2020-as átlaghoz képest")
	if v == null:
		return [L.t("Melegebb, mint valaha."), ""]
	var num := _signed(float(v)) + " °C"
	var date := str(_today.get("datum", ""))
	if not L.is_en() and date.length() == 10:
		date = date.replace("-", ". ") + "."
	var sub := basis + (", " + date if date != "" else "") + " · Copernicus Climate Pulse"
	if _today_rank == 1:
		return [L.t("%s. Melegebb, mint valaha.") % num, sub]
	return [num + ".", sub]


## A valódi éves eltérések a gépen lévő Climate Pulse-adatból. Ha nincs, vagy egy napnál
## régebbi, a háttérben frissítjük (a hídon át): a következő indításkor már ebből megy.
func _load_data() -> void:
	var path := pulse_path()
	var d: Variant = Bridge.read_json(path)
	if typeof(d) == TYPE_DICTIONARY and typeof(d.get("ma")) == TYPE_DICTIONARY:
		_today = d["ma"]
		_today_rank = int(d.get("rang", 0)) if d.get("rang") != null else 0
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
	if age > 86400.0 and shots_dir == "":
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var b = Bridge.new()
		main.add_child.call_deferred(b)     # a főjelenethez: az intro vége után is lefuthat
		var start := func() -> void: b.run("pulse", ["pulse", "--ki", path])
		start.call_deferred()
		b.finished.connect(func(_tag: String, _code: int, _out: String) -> void: b.queue_free())


func _shot(name: String) -> void:
	if shots_dir == "" or _done:
		return
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name))
	print("INTRO kép: ", shots_dir.path_join(name))


## Záró kép: nincs szlogen, csak a játék címe – kicsiben, halványan a csillagok
## között „elrejtve”, ahol a figyelmes néző észreveszi.
func _show_logo() -> void:
	_caption.text = ""
	_sub.text = ""
	# a cím és alatta kisebben a szerző, együtt úsznak be és pislákolnak
	_logo = Control.new()
	_logo.position = Vector2(1060, 100)
	_logo.size = Vector2(440, 90)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	add_child(_logo)
	var title := UI.label("A E T H E R", 38, UI.CYAN, false, false)
	title.add_theme_font_override("font", UI.font_pixel)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(440, 52)
	_logo.add_child(title)
	var by := UI.label("by Zoltán Németh", 18, UI.TEXT, false, false)
	by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	by.position = Vector2(0, 54)
	by.size = Vector2(440, 26)
	_logo.add_child(by)
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(_logo, "modulate:a", 0.42, 2.8).set_trans(Tween.TRANS_SINE)
	# két halk pislákolás, mint egy csillag
	tw.tween_property(_logo, "modulate:a", 0.25, 0.5)
	tw.tween_property(_logo, "modulate:a", 0.42, 0.5)


# --- rajzolt előtér ------------------------------------------------------------
static func _h(i: float) -> float:
	return fposmod(sin(i * 127.1 + 311.7) * 43758.5453, 1.0)


static func _ss(a: float, b: float, x: float) -> float:
	var k := clampf((x - a) / (b - a), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## 0 a jeleneten kívül, 1 belül; a széleken `f` mp alatt úszik be és ki (jelenet-időben).
func _win(lt: float, a: float, b: float, f: float = 0.5) -> float:
	return _ss(a, a + f, lt) * (1.0 - _ss(b - f, b, lt))


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


func _draw_fx() -> void:
	var lt := _t - _mode_t0
	match _mode:
		"cim":
			_draw_title(lt)
		"jatekos":
			_scene_player(_music_time(lt))
		"szamlalo":
			_draw_counter(lt)
		"kep":
			[_scene_ice, _scene_drought, _scene_flood, _scene_fire][_scene_idx].call(lt * SCENE_SPEED)
			# puha áttűnés: sötétből be, a végén (az utolsó kivételével) sötétbe ki
			var dark := 1.0 - _ss(0.0, 0.7, lt)
			if _scene_idx < 3:
				dark = maxf(dark, _ss(SCENE_LEN - 0.6, SCENE_LEN, lt))
			if dark > 0.0:
				_fx.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, dark))
			# a felirat alatt sötétebb sáv, hogy a festett képen is olvasható legyen
			_fx.draw_rect(Rect2(0, 735, W, 135), Color(0.02, 0.03, 0.07, 0.55))
		"jovo":
			_draw_future(lt)
		"hivas":
			_draw_call(lt)


## Évszámláló a valódi éves eltéréssel, alul a „melegedési csíkok” (minden év egy csík).
## A gömb közben fokozatosan „melegszik” (csak szemléltetés).
func _draw_counter(lt: float) -> void:
	var pos := _ss(0.8, 6.4, lt)
	var a := _win(lt, 0.0, 7.5, 0.6)
	main.globe.heat = 0.75 * (_norm(_value_at(pos)) if not _years.is_empty() else pos)
	if _years.is_empty():
		return
	var n := _years.size()
	var idx := int(round(pos * float(n - 1)))
	var year: int = _years[idx][0]
	var v: float = _years[idx][1]
	var x := 1040.0
	_fx.draw_string(UI.font_bold, Vector2(x, 330.0), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1, 112, Color(UI.TEXT, a))
	var col := UI.EMBER if v > 0.0 else Color("#7fb2ff")
	_fx.draw_string(UI.font_bold, Vector2(x, 410.0), _signed(v) + " °C", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, Color(col, a))
	var basis := L.t("az iparosodás előtti szinthez képest") if _pre_industrial else L.t("az 1991–2020-as átlaghoz képest")
	_fx.draw_string(UI.font_body, Vector2(x, 450.0), basis, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UI.SOFT, a))
	_fx.draw_string(UI.font_body, Vector2(x, 478.0), L.t("Adat: Copernicus Climate Pulse"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UI.MUTE, a))
	var bw := W / float(n)
	for i in idx + 1:
		_fx.draw_rect(Rect2(floorf(i * bw), 690.0, ceilf(bw) + 1.0, 30.0), Color(_stripe(_norm(_years[i][1])), a))


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


# --- hívás: a játékos fénye, és ahogy a fény szétterjed a Földön ------------------
## Kutatóhelyek a világon, ahová a fényívek futnak (csak a látható oldaliak rajzolódnak ki).
const CALL_PLACES := [
	[64.1, -21.9], [38.7, -9.1], [40.4, -3.7], [59.3, 18.1], [69.6, 18.9], [55.8, 37.6],
	[41.0, 29.0], [30.0, 31.2], [24.7, 46.7], [6.5, 3.4], [14.7, -17.5], [-4.3, 15.3],
	[-1.3, 36.8], [-33.9, 18.4], [28.6, 77.2], [43.2, 76.9], [23.8, 90.4], [-22.9, -43.2],
	[9.0, 38.7], [33.6, -7.6], [52.5, 13.4], [60.2, 24.9], [-18.9, 47.5], [35.7, 51.4]]


## A gömb egy pontja képernyő-koordinátában (Vector3: x, y, látszik-e).
func _globe_screen(lat: float, lon: float) -> Vector3:
	var g = main.globe
	var p: Vector3 = g.project(lat, lon)
	var q: Vector2 = g.get_global_transform() * Vector2(p.x, p.y)
	return Vector3(q.x, q.y, p.z)


func _draw_call(lt: float) -> void:
	var a := _win(lt, 0.0, 5.0, 0.6)
	var home := Vector2(800, 450)
	for s in main.globe.stations:
		if s.get("me", false):
			var h := _globe_screen(float(s["lat"]), float(s["lon"]))
			home = Vector2(h.x, h.y)
	var center: Vector2 = main.globe.get_global_transform() * (main.globe.size * 0.5)
	# 1. a játékos fénye: lassan kigyúl, lüktet
	var glow := _ss(0.2, 1.4, lt)
	var beat := 1.0 + 0.18 * sin(_t * 4.0)
	for r in [90.0, 60.0, 38.0, 22.0]:
		_fx.draw_circle(home, r * glow * beat, Color(1.0, 0.85, 0.45, 0.10 * a))
	_fx.draw_circle(home, 9.0 * glow, Color(1.0, 0.96, 0.82, a))
	# 2. fényívek indulnak sorban, a végükön új fények gyúlnak
	var k := 0
	for pl in CALL_PLACES:
		var t := _globe_screen(pl[0], pl[1])
		if t.z < 0.5:
			continue
		var dst := Vector2(t.x, t.y)
		if dst.distance_to(home) < 30.0:
			continue
		var t0 := 1.0 + k * 0.14
		k += 1
		var p := clampf((lt - t0) / 1.1, 0.0, 1.0)
		if p <= 0.0:
			continue
		var mid := (home + dst) * 0.5
		var lift := (mid - center).normalized() * home.distance_to(dst) * 0.32
		var ctrl := mid + lift
		var e := 1.0 - pow(1.0 - p, 2.0)
		var pts := PackedVector2Array()
		var steps := 24
		for i in int(e * steps) + 1:
			var u := float(i) / steps
			pts.append(home.lerp(ctrl, u).lerp(ctrl.lerp(dst, u), u))
		if pts.size() > 1:
			_fx.draw_polyline(pts, Color(1.0, 0.82, 0.40, 0.55 * a), 3.0)
			_fx.draw_circle(pts[pts.size() - 1], 4.0, Color(1.0, 0.95, 0.75, a))
		if p >= 1.0:   # megérkezett: új fény gyúl, egy pillanatra gyűrű fut ki belőle
			var q := clampf((lt - t0 - 1.1) / 0.9, 0.0, 1.0)
			_fx.draw_circle(dst, 16.0 * (0.6 + 0.4 * sin(_t * 3.0 + k)), Color(1.0, 0.85, 0.45, 0.16 * a))
			_fx.draw_circle(dst, 5.0, Color(1.0, 0.93, 0.70, a))
			if q < 1.0:
				_fx.draw_arc(dst, 6.0 + q * 34.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.6, (1.0 - q) * a), 2.0)


# --- a jövő: a görbe elágazik --------------------------------------------------
func _draw_future(lt: float) -> void:
	var a := _win(lt, 0.0, 5.5, 0.6)
	var x0 := 150.0
	var xn := 900.0
	var now := Vector2(xn, 420.0)
	var pts := PackedVector2Array()
	if not _years.is_empty():      # a múlt: a valódi éves eltérések
		var n := _years.size()
		var show := int(ceil(_ss(0.3, 2.0, lt) * float(n)))
		for i in show:
			pts.append(Vector2(lerpf(x0, xn, float(i) / float(n - 1)), lerpf(640.0, 420.0, _norm(_years[i][1]))))
		for i in pts.size() - 1:
			_fx.draw_line(pts[i], pts[i + 1], Color(_stripe(_norm(_years[i + 1][1])), a), 6.0)
		if show >= n:
			now = pts[n - 1]
		_fx.draw_string(UI.font_bold, Vector2(x0, 690.0), str(_years[0][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(UI.MUTE, a))
	var f := _ss(2.0, 4.6, lt)
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
	var na := a * _ss(1.8, 2.3, lt) if not _years.is_empty() else a
	_fx.draw_circle(now, 20.0 * pulse, Color(UI.GOLD, 0.25 * na))
	_fx.draw_circle(now, 10.0, Color(UI.GOLD, na))
	_fx.draw_string(UI.font_bold, now + Vector2(-40.0, -30.0), str(_year_now), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 26, Color(UI.GOLD, na))


# --- nyitány: handpan-játékos az erdőben -----------------------------------------
## Festett pixeles képekből áll (640×360): az erdő (tools/intro_erdo.py), a játékos, a hangszer
## és a két kar három-három mozgásfázisa (tools/intro_jatekos.py). A karok fázisát a zene
## ütései vezérlik: fent lebeg -> félúton -> a hangmezőn -> vissza.
const P := 2.5                  # a nyitány egy „pixele” a képernyőn (640×360 -> 1600×900)
const PAN := Vector2(322, 262)  # a hangszer közepe a képen
const HIT_SPOT := [Vector2(-24, -2), Vector2(24, -2)]   # ahová a bal és a jobb kéz üt (a hangszer közepéhez képest)
var _tex := {}


## Kép betöltése; ha a Godot még nem importálta (új fájl, szerkesztő nélkül), közvetlenül a fájlból.
func _img(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var path := "res://assets/intro/%s.png" % name
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	if t == null:
		var im := Image.load_from_file(ProjectSettings.globalize_path(path))
		if im != null:
			t = ImageTexture.create_from_image(im)
	_tex[name] = t
	return t


## A nyitány ideje a zene tényleges lejátszási helyéből (a hangkártya késését levonva),
## hogy a kéz pontosan akkor érjen a hangszerhez, amikor a hang megszólal.
func _music_time(lt: float) -> float:
	if _music == null or not is_instance_valid(_music) or not _music.playing:
		return lt
	var mt: float = _music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	if absf(mt - lt) > 0.5:       # ha a zene és a kép nagyon elcsúszna, marad a kép saját órája
		return lt
	return maxf(mt, 0.0)


## A kar mozgásfázisa (0 fent, 1 félúton, 2 a hangmezőn) a zene ütéseiből.
func _arm_phase(side: int, lt: float) -> int:
	var ph := 0
	for h in HITS:
		if int(h[1]) != side:
			continue
		var dt := lt - float(h[0])
		if dt >= -0.03 and dt < 0.12:
			return 2
		if (dt >= -0.12 and dt < -0.03) or (dt >= 0.12 and dt < 0.24):
			ph = 1
	return ph


func _scene_player(lt: float) -> void:
	# lassú közelítés a kép közepe felé
	var z := lerpf(1.0, 1.06, lt / PRELUDE)
	var c := Vector2(W, H) * 0.5
	var base := c - c * z
	_fx.draw_set_transform(base, 0.0, Vector2(z, z))
	var full := Rect2(0, 0, W, H)
	for name in ["erdo", "jatekos", "handpan"]:
		var t := _img(name)
		if t != null:
			_fx.draw_texture_rect(t, full, false)
	# fénypászmák a lombon át
	for i in 4:
		var lx := 140.0 + i * 330.0 + sin(lt * 0.22 + i) * 10.0
		_fx.draw_colored_polygon(PackedVector2Array([Vector2(lx, 0), Vector2(lx + 70, 0), Vector2(lx + 300, 700), Vector2(lx + 150, 700)]),
			Color(0.75, 0.95, 0.65, 0.030 + 0.012 * sin(lt * 0.6 + i * 2.0)))
	# a megütött hangmező felfénylik
	for h in HITS:
		var d := lt - float(h[0])
		if d >= 0.0 and d < 0.5:
			var fp: Vector2 = (PAN + HIT_SPOT[int(h[1])]) * P
			_fx.draw_set_transform(base + fp * z, 0.0, Vector2(z, z * 0.45))
			_fx.draw_circle(Vector2.ZERO, 16.0 * P, Color(1.0, 0.97, 0.85, 0.40 * (1.0 - d / 0.5)))
			_fx.draw_set_transform(base, 0.0, Vector2(z, z))
	# a karok: a jobb (árnyékos) hátul, a bal elöl
	for side in [1, 0]:
		var t2 := _img("kar_%s_%d" % ["b" if side == 0 else "j", _arm_phase(side, lt)])
		if t2 != null:
			_fx.draw_texture_rect(t2, full, false)
	# a hangból táguló, halvány fénygyűrűk
	for h in HITS:
		var d2 := lt - float(h[0])
		if d2 >= 0.0 and d2 < 1.8:
			var k3 := d2 / 1.8
			var rc: Vector2 = (PAN + HIT_SPOT[int(h[1])]) * P
			_fx.draw_set_transform(base + rc * z, 0.0, Vector2(z, z * 0.42))
			for ring in 2:
				var rr := (30.0 + 420.0 * k3) * (1.0 - ring * 0.35)
				_fx.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 64, Color(0.80, 0.97, 0.88, 0.30 * (1.0 - k3) * (1.0 - ring * 0.4)), 4.0)
			_fx.draw_set_transform(base, 0.0, Vector2(z, z))
	# szálló fénypontok
	for i in 60:
		var life := fposmod(_h(i + 700.0) + lt * (0.03 + _h(i + 720.0) * 0.05), 1.0)
		var mx := _h(i + 740.0) * W + sin(lt * 0.5 + i) * 30.0
		var my := H - 40.0 - life * 780.0
		var a := sin(life * PI) * (0.35 + 0.35 * sin(lt * 2.0 + i * 1.3))
		var sz := P * (1.0 + float(i % 2))
		_fx.draw_rect(Rect2(Vector2(mx, my).snappedf(P), Vector2(sz, sz)), Color(0.85, 1.0, 0.6, maxf(a, 0.0)))
	_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# a zene szerzője (jobbra lent), Zoltán kérése szerinti szöveggel
	var ca := _win(lt, 3.0, PRELUDE - 0.9, 1.0)
	_fx.draw_string(UI.font_bold, Vector2(W - 520.0, H - 78.0), "Music: Malte Marten", HORIZONTAL_ALIGNMENT_RIGHT, 500.0, 24, Color(UI.TEXT, ca))
	_fx.draw_string(UI.font_body, Vector2(W - 520.0, H - 54.0), "www.maltemarten.com", HORIZONTAL_ALIGNMENT_RIGHT, 500.0, 16, Color(UI.SOFT, ca))
	# lassú beúszás a sötétből, a végén vissza a sötétbe
	var dark := maxf(1.0 - _ss(0.8, 4.2, lt), _ss(PRELUDE - 0.9, PRELUDE - 0.05, lt))
	if dark > 0.0:
		_fx.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, dark))


func _finish() -> void:
	if _done:
		return
	_done = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_stop_music()
	var g = main.globe
	g.highlight = {}
	g.show_anomaly(false)
	g.heat = 0.0
	_mode = ""
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
