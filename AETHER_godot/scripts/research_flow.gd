extends PanelContainer
## Kutatás, lépésről lépésre. Minden képernyőn egyetlen döntés:
##   1. Mit kutassunk?  2. Ki kutasson?  3. (vár)  4. Mit találtunk?  5. Jóváhagyás

signal approved(levers: Array)
signal results_shown(has_levers: bool)
signal closed

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

## Előre összeállított kérdések. "kereses": angol keresőkifejezések ("|" választja el),
## "parameterek": mely modellparaméterekhez keresünk számot, "wiki"/"wiki_en"/"attekintes":
## a „Mi ez, és mire jó?” magyarázat forrásai (Wikipédia + összefoglaló cikkek).
const CDR_PARAMS := "cdr_potencial_gtco2_ev,cdr_koltseg_usd_tco2"
const NET_REVIEW := "negative emissions technologies potentials costs side effects"
const QUESTIONS := [
	{"cim": "Mennyi CO2-t vonhat ki a levegőből a bioszén?",
	 "magyarazat": "A bioszén elszenesített növényi hulladék. A talajba keverve hosszú ideig tárolja a szenet.",
	 "kereses": "biochar carbon dioxide removal potential global|biochar soil carbon sequestration meta-analysis|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "bioszén", "wiki_en": "biochar", "attekintes": "biochar carbon sequestration review"},
	{"cim": "Mennyit segít a kőzetmállasztás?",
	 "magyarazat": "Finomra őrölt kőzetet szórnak a földekre, ami lassan megköti a levegő CO2-jét.",
	 "kereses": "enhanced rock weathering carbon dioxide removal potential|enhanced weathering croplands global potential|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "kőzetmállás szén-dioxid", "wiki_en": "enhanced weathering", "attekintes": "enhanced rock weathering review"},
	{"cim": "Mennyi CO2-t köthet meg az erdősítés?",
	 "magyarazat": "Új erdők telepítése: a fák növekedés közben szenet építenek be.",
	 "kereses": "afforestation reforestation carbon dioxide removal potential global|global tree restoration potential carbon|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "erdősítés", "wiki_en": "afforestation", "attekintes": "afforestation carbon sequestration review"},
	{"cim": "Segítenek-e az aszálytűrő kukoricafajták?",
	 "magyarazat": "Ez nem hűti a Földet, de megvédheti a termést a forró, száraz években.",
	 "kereses": "drought tolerant maize yield advantage under drought|drought tolerant maize varieties yield on-farm trials",
	 "parameterek": "alkalmazkodas_hozam_elony_pct", "wiki": "kukorica szárazságtűrés", "wiki_en": "drought tolerance maize",
	 "attekintes": "drought tolerant maize review"},
]

## A választható AI-k. "kulcs": melyik környezeti változóba kerül a játékban
## megadott kulcs (csak a futás idejére, sehova nem mentjük), "link": hol lehet kulcsot kérni.
const AI_CHOICES := [
	{"id": "claude", "cim": "Claude (Anthropic)", "magyarazat": "Nagyon alapos. API-kulcs kell (fizetős).",
	 "kulcs": "ANTHROPIC_API_KEY", "minta": "sk-ant-…", "link": "https://console.anthropic.com/settings/keys"},
	{"id": "openai", "cim": "ChatGPT (OpenAI)", "magyarazat": "Alapos. API-kulcs kell (fizetős).",
	 "kulcs": "OPENAI_API_KEY", "minta": "sk-…", "link": "https://platform.openai.com/api-keys"},
	{"id": "gemini", "cim": "Gemini (Google)", "magyarazat": "Alapos. API-kulcs kell, van ingyenes keret.",
	 "kulcs": "GEMINI_API_KEY", "minta": "AIza…", "link": "https://aistudio.google.com/apikey"},
	{"id": "ollama", "cim": "Helyi AI a gépeden (Ollama)", "magyarazat": "Ingyenes, de lassabb."},
	{"id": "none", "cim": "AI nélkül: csak cikkeket keresek", "magyarazat": "Csak cikklista, számok nélkül."},
]

var bridge                  # lab_bridge.gd példány (a main.gd adja át)
var campaign                  # campaign.gd: a kutatás pénzbe kerül
var _body: VBoxContainer
var _question: Dictionary = {}
var _ai := "none"
var _ai_status: Dictionary = {}
var _folder := ""
var _poll: Timer
var _result: Dictionary = {}
var _checks: Array = []     # [[CheckBox, javaslat], ...]
var _step_rows: Array = []
var _log_label: Label
var _short_label: Label
var _dots := 0
var _title_label: Label        # a fejléc címe (kutatás közben pontok futnak utána)
var _title_text := ""


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
	_body = UI.vbox(14)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(UI.scroll_pad(_body))
	_poll = Timer.new()
	_poll.wait_time = 0.4
	_poll.timeout.connect(_on_poll)
	add_child(_poll)
	bridge.finished.connect(_on_bridge_finished)
	show_questions()


func _header(title: String, step: int, help: String) -> void:
	UI.clear(_body)
	var h := UI.hbox(12)
	_title_text = title
	_title_label = UI.heading(title)
	h.add_child(_title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	if step > 0:
		h.add_child(UI.label(L.t("%d. lépés / 4") % step, 15, UI.MUTE, false, false))
	var x := UI.button(L.t("Bezárás"))
	x.pressed.connect(_close)
	h.add_child(x)
	_body.add_child(h)
	if help != "":
		_body.add_child(UI.label(help, 17, UI.SOFT))


func _close() -> void:
	_poll.stop()
	closed.emit()


# --- 1. Mit kutassunk? -----------------------------------------------------
func show_questions() -> void:
	_topic_q = {}
	_header(L.t("Mit kutassunk?"), 1, L.t("Válassz kérdést. A válasz valódi tudományos cikkekből jön."))
	for q in QUESTIONS:
		var c := UI.card(UI.CYAN)
		c.add_child(UI.label(L.t(q["cim"]), 19, UI.TEXT, true))
		c.add_child(UI.label(L.t(q["magyarazat"]), 16, UI.SOFT))
		var row := UI.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_END
		var info := UI.button(L.t("Mi ez, és mire jó?"))
		info.pressed.connect(_show_topic.bind(q))
		row.add_child(info)
		var b := UI.button(L.t("Ezt kutatom"))
		b.pressed.connect(_pick_question.bind(q))
		row.add_child(b)
		c.add_child(row)
		_body.add_child(UI.card_root(c))
	# saját kérdés: haladóknak, alapból rejtve
	var more := UI.button(L.t("Saját kérdést írok (haladó)"))
	var box := UI.hbox(8)
	box.visible = false
	var edit := LineEdit.new()
	edit.placeholder_text = L.t("Pl.: Mennyi metánt bocsátanak ki a rizsföldek?")
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(edit)
	var go := UI.button(L.t("Ezt kutatom"))
	var go_fn := func() -> void:
		var q := edit.text.strip_edges()
		if q != "":
			_pick_question({"cim": q, "magyarazat": "", "kereses": q})
	go.pressed.connect(go_fn)
	box.add_child(go)
	var more_fn := func() -> void: box.visible = not box.visible
	more.pressed.connect(more_fn)
	_body.add_child(more)
	_body.add_child(box)


# --- „Mi ez, és mire jó?” ---------------------------------------------------
## Gyorsítás, három szinten:
##  1. a beépített kérdések magyarázata a játékkal együtt jön (res://assets/temak) – azonnali,
##  2. különben előbb AI nélkül (Wikipédia, 1–2 mp) jelenik meg valami,
##  3. az AI közben a háttérben dolgozik, és ha kész, lecseréli a részletesre.
## Ami egyszer elkészült, a gépen megmarad (user://aether_temak).
var _topic_out := ""
var _topic_q: Dictionary = {}
var _topic_ai := "none"
var _topic_phase := ""           # "gyors" (AI nélkül) vagy "ai"


func _topic_path(q: Dictionary, ai: String) -> String:
	return bridge.work_dir("aether_temak").path_join("%s_%s_%s.json" % [str(q["wiki_en"]).md5_text().left(10), L.lang, ai])


func _show_topic(q: Dictionary) -> void:
	_topic_q = q
	_topic_ai = L.get_setting("ai", "ollama")
	var key := str(q["wiki_en"]).md5_text().left(10)
	var bundled: Variant = Bridge.read_json("res://assets/temak/%s_%s.json" % [key, L.lang])
	if typeof(bundled) == TYPE_DICTIONARY:
		_render_topic(bundled)
		return
	for ai in [_topic_ai, "none"]:
		var cached: Variant = Bridge.read_json(_topic_path(q, ai))
		if typeof(cached) == TYPE_DICTIONARY:
			_render_topic(cached)
			if ai != _topic_ai and _topic_ai != "none":
				_run_topic("ai")
			return
	_header(L.t(q["cim"]), 0, "")
	_body.add_child(UI.label(L.t("Egy pillanat, töltöm a forrásokat…"), 17, UI.SOFT))
	_run_topic("gyors")


func _run_topic(phase: String) -> void:
	_topic_phase = phase
	var ai := "none" if phase == "gyors" else _topic_ai
	_topic_out = _topic_path(_topic_q, ai)
	if not bridge.run("tema", ["tema", "--wiki", str(_topic_q["wiki"]), "--wiki-en", str(_topic_q["wiki_en"]),
			"--kereses", str(_topic_q["attekintes"]), "--ki", _topic_out, "--ai", ai, "--nyelv", L.lang]):
		if phase == "gyors":
			_show_busy()


func _render_topic(r: Dictionary) -> void:
	_header(L.t(_topic_q["cim"]), 0, "")
	var m: Variant = r.get("magyarazat")
	if typeof(m) == TYPE_DICTIONARY:
		for part in [["mi_ez", "Mi ez?"], ["mire_jo", "Mire jó?"], ["hatranyok", "Mi a gond vele?"], ["mennyire_bizonyitott", "Mennyire bizonyított?"]]:
			var c := UI.card(UI.GOLD)
			c.add_child(UI.label(L.t(part[1]), 17, UI.GOLD, true))
			c.add_child(UI.label(str(m.get(part[0], "")), 17, UI.TEXT))
			_body.add_child(UI.card_root(c))
	# A források: AI-összefoglaló mellett egy gomb mögött, egymás alatt; anélkül láthatóan.
	var src := UI.vbox(2)
	var w: Variant = r.get("wiki")
	if typeof(w) == TYPE_DICTIONARY:
		if typeof(m) != TYPE_DICTIONARY:
			var c := UI.card(UI.GOLD)
			c.add_child(UI.label(L.t("Mi ez? (Wikipédia)"), 17, UI.GOLD, true))
			c.add_child(UI.label(str(w.get("bevezeto", "")), 17, UI.TEXT))
			_body.add_child(UI.card_root(c))
		src.add_child(_text_link(L.t("Wikipédia: ") + str(w.get("cim", "")) + " (" + str(w.get("nyelv", "")) + ", CC BY-SA 4.0)",
			str(w.get("link", ""))))
	var papers: Array = r.get("cikkek", [])
	if not papers.is_empty():
		src.add_child(UI.label(L.t("Tudományos összefoglaló cikkek"), 15, UI.SOFT, true))
		for p in papers:
			var ev := str(p.get("ev", ""))
			if ev.is_valid_float():
				ev = str(int(float(ev)))   # 2023.0 -> 2023
			var t := "• " + str(p.get("cim", "")) + (" (%s)" % ev if ev != "" else "")
			src.add_child(_text_link(t, str(p.get("link", ""))))
	if typeof(m) == TYPE_DICTIONARY and src.get_child_count() > 0:
		src.visible = false
		var sb := UI.button(L.t("AI-összefoglaló forrásai"))
		var src_fn := func() -> void: src.visible = not src.visible
		sb.pressed.connect(src_fn)
		_body.add_child(sb)
	_body.add_child(src)
	if typeof(w) != TYPE_DICTIONARY and papers.is_empty():
		_body.add_child(UI.label(L.t("Most nem sikerült forrást letölteni. Van internet?"), 17, UI.EMBER))
	if str(r.get("megjegyzes", "")) != "":
		_body.add_child(UI.label(str(r["megjegyzes"]), 13, UI.MUTE))
	if typeof(m) != TYPE_DICTIONARY and _topic_ai != "none" and bridge.is_busy():
		_body.add_child(UI.label(L.t("Az AI részletesebb magyarázatot ír…"), 15, UI.GOLD))
	var row := UI.hbox(12)
	var back := UI.button(L.t("Vissza a kérdésekhez"))
	back.pressed.connect(show_questions)
	row.add_child(back)
	var go := UI.button(L.t("Ezt kutatom"), true)
	go.pressed.connect(_pick_question.bind(_topic_q))
	row.add_child(go)
	_body.add_child(row)


func _pick_question(q: Dictionary) -> void:
	_topic_q = {}
	_question = q
	_header(L.t("Ki kutasson?"), 2, L.t("Megnézem, milyen AI érhető el a gépeden…"))
	_ask_ai(0)


## Az elérhető AI-k lekérdezése; ha a játék épp mással dolgozik (pl. egy esemény
## összefoglalóján), fél másodpercenként újrapróbálja, legfeljebb egy percig.
func _ask_ai(tries: int) -> void:
	if not is_inside_tree():
		return
	var path: String = bridge.work_dir("aether_kutatas").path_join("ai.json")
	if bridge.run("ai", ["godot-ai", "--ki", path, "--nyelv", L.lang]):
		return
	if tries >= 120:
		_show_busy()
		return
	get_tree().create_timer(0.5).timeout.connect(_ask_ai.bind(tries + 1))


func _show_busy() -> void:
	_header(L.t("Egy pillanat…"), 0, L.t("A játék épp mással dolgozik. Próbáld újra pár másodperc múlva."))
	var back := UI.button(L.t("Újra"))
	back.pressed.connect(show_questions)
	_body.add_child(back)


# --- 2. Ki kutasson? -------------------------------------------------------
func _show_ai_choice() -> void:
	_header(L.t("Ki kutasson?"), 2, L.t("Kérdés: ") + L.t(str(_question["cim"])))
	# Miért kell AI? Egy mondat mindig látszik, a többi a Részletek mögött.
	var why := UI.card(UI.GOLD)
	why.add_child(UI.label(L.t("Miért kell AI?"), 17, UI.GOLD, true))
	why.add_child(UI.label(L.t("Az AI a kutatód: cikkeket olvas és számokat keres. A játék mindet ellenőrzi."), 16, UI.SOFT))
	var why_more := UI.label(L.t("A játék nem hisz vakon az AI-nak: minden számot szó szerint visszakeres a cikkben, és csak azt fogadja el, ami tényleg benne van. Fontos: a ChatGPT Plus, Claude Pro vagy Gemini előfizetés önmagában nem elég, a játékhoz API-kulcs kell. Ez külön, használat szerint fizetendő: egy kutatás a választott AI-tól függően néhány forinttól pár száz forintig terjed. A Geminihez van ingyenes keret, az Ollama pedig teljesen ingyenes."), 15, UI.MUTE)
	why_more.visible = false
	var why_btn := UI.button(L.t("Részletek"))
	var why_fn := func() -> void: why_more.visible = not why_more.visible
	why_btn.pressed.connect(why_fn)
	why.add_child(why_btn)
	why.add_child(why_more)
	_body.add_child(UI.card_root(why))
	var best := "none"
	for id in ["ollama", "gemini", "openai", "claude"]:   # a legalaposabb elérhető
		if _ai_status.get(id, {}).get("elerheto", false):
			best = id
	var group := ButtonGroup.new()
	var key_box := UI.vbox(6)
	var key_label := UI.label("", 16, UI.SOFT)
	var key := LineEdit.new()
	key.secret = true
	var key_link := UI.button(L.t("Kulcs létrehozása (megnyílik a böngészőben)"))
	var key_state := {"env": "", "link": ""}
	for ch in AI_CHOICES:
		var id: String = ch["id"]
		var st: Dictionary = _ai_status.get(id, {})
		var c := UI.card(UI.GREEN if st.get("elerheto", false) else UI.EDGE)
		var rb := CheckBox.new()
		rb.button_group = group
		rb.text = L.t(ch["cim"]) + (L.t(" (ajánlott)") if id == best else "")
		rb.add_theme_font_override("font", UI.font_bold)
		rb.add_theme_font_size_override("font_size", 18)
		rb.button_pressed = id == best
		var need_key: bool = ch.has("kulcs") and not st.get("elerheto", false)
		var pick_fn := func(on: bool) -> void:
			if on:
				_ai = id
				key_box.visible = need_key
				if need_key:
					key_state["env"] = ch["kulcs"]
					key_state["link"] = ch["link"]
					key_label.text = L.t("%s API-kulcs (csak amíg a játék fut, nem mentjük el):") % L.t(ch["cim"])
					key.placeholder_text = ch["minta"]
					key.text = OS.get_environment(ch["kulcs"])
		rb.toggled.connect(pick_fn)
		c.add_child(rb)
		c.add_child(UI.label(L.t(ch["magyarazat"]), 16, UI.SOFT))
		if id != "none" and not st.get("elerheto", false):  # csak ha valami hiányzik
			c.add_child(UI.label(str(st.get("ok", "")), 15, UI.MUTE))
		if id == "ollama":
			_add_hardware_info(c, st)
		_body.add_child(UI.card_root(c))
	_ai = best
	# API-kulcs megadása: csak erre a futásra kerül a környezetbe, sehova nem mentjük
	key_box.visible = false
	key_box.add_child(key_label)
	var key_fn := func(t: String) -> void:
		if key_state["env"] != "":
			OS.set_environment(key_state["env"], t.strip_edges())
	key.text_changed.connect(key_fn)
	key_box.add_child(key)
	var link_fn := func() -> void:
		if key_state["link"] != "":
			OS.shell_open(key_state["link"])
	key_link.pressed.connect(link_fn)
	key_box.add_child(key_link)
	_body.add_child(key_box)
	var row := UI.hbox(12)
	var back := UI.button(L.t("Vissza"))
	back.pressed.connect(show_questions)
	row.add_child(back)
	var start := UI.button(L.t("Indulhat a kutatás"), true)
	if campaign != null:
		start.text += L.t(" (%d pénz)") % campaign.research_cost()
		start.tooltip_text = L.t("Az AI-mag %d cikket néz át. Idén még %d kutatást indíthatsz.") % [
			campaign.papers_per_research(), maxi(0, campaign.research_limit() - campaign.research_this_year)]
	start.pressed.connect(_start_research)
	row.add_child(start)
	_body.add_child(row)


## A géped videókártyái és az ajánlott helyi modell (ami teljesen elfér a videómemóriában).
var _dl_poll: Timer
var _dl_label: Label
var _dl_path := ""


func _add_hardware_info(c: VBoxContainer, st: Dictionary) -> void:
	var gep: Dictionary = _ai_status.get("gep", {})
	var cards: Array = gep.get("kartyak", [])
	if cards.is_empty() and not gep.has("ajanlas"):
		return
	var names := PackedStringArray()
	for g in cards:
		var s := str(g.get("nev", ""))
		if g.get("vram_gb") != null:
			s += " (%s GB)" % UI.hu(float(g["vram_gb"]), 0)
		if not g.get("ollama_hasznalja", true):
			s += L.t(" – ezt az Ollama nem használja")
		names.append(s)
	var rec: Dictionary = gep.get("ajanlas", {})
	if rec.is_empty():
		return
	var model := str(rec.get("modell", ""))
	var have: Array = st.get("modellek", [])
	var has_it := false
	for m in have:
		if str(m) == model or str(m).begins_with(model + "-"):
			has_it = true
	if has_it:
		return
	var rec_l := UI.label(L.t("Ajánlott a gépedhez: %s") % model, 15, UI.GOLD)
	rec_l.tooltip_text = "; ".join(names) + "\n" + str(rec.get("indoklas", ""))
	rec_l.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(rec_l)
	if not str(st.get("ok", "")).begins_with("Fut") and not str(st.get("ok", "")).begins_with("Running"):
		var inst := UI.button(L.t("Az Ollama telepítése (ollama.com, ingyenes)"))
		var inst_fn := func() -> void: OS.shell_open("https://ollama.com/download")
		inst.pressed.connect(inst_fn)
		c.add_child(inst)
		return
	var dl := UI.button(L.t("Letöltöm: %s (%s GB)") % [model, UI.hu(float(rec.get("letoltes_gb", 0)), 1)])
	_dl_label = UI.label("", 15, UI.SOFT)
	var dl_fn := func() -> void:
		_dl_path = bridge.work_dir("aether_kutatas").path_join("letoltes.json")
		DirAccess.remove_absolute(_dl_path)
		if bridge.run("letolt", ["ollama-letolt", model, "--allapot", _dl_path]):
			dl.disabled = true
			_dl_label.text = L.t("Letöltés indul…")
			if _dl_poll == null:
				_dl_poll = Timer.new()
				_dl_poll.wait_time = 1.0
				_dl_poll.timeout.connect(_on_dl_poll)
				add_child(_dl_poll)
			_dl_poll.start()
		else:
			_dl_label.text = L.t("A játék épp mással dolgozik. Próbáld újra pár másodperc múlva.")
	dl.pressed.connect(dl_fn)
	c.add_child(dl)
	c.add_child(_dl_label)


func _on_dl_poll() -> void:
	var st: Variant = Bridge.read_json(_dl_path)
	if typeof(st) != TYPE_DICTIONARY or _dl_label == null or not is_instance_valid(_dl_label):
		return
	if st.get("szazalek") != null:
		_dl_label.text = L.t("Letöltés: %d%%") % int(st["szazalek"])
	if st.get("kesz", false):
		_dl_label.text = L.t("Kész, a játék ezt használja.")
		_dl_poll.stop()
	elif str(st.get("allapot", "")) == "hiba":
		_dl_label.text = L.t("A letöltés nem sikerült: ") + str(st.get("hiba", ""))
		_dl_poll.stop()


# --- 3. Kutatás folyamatban -----------------------------------------------
func _start_research() -> void:
	if campaign != null:
		var problem: String = campaign.research_problem()
		if problem != "":
			_body.add_child(UI.label(problem, 17, UI.EMBER))
			return
		campaign.pay_research()
	L.set_setting("ai", _ai)   # az események összefoglalója is ezt az AI-t használja
	_folder = str(bridge.work_dir("aether_kutatas")).path_join("kutatas_%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_folder)
	_header(L.t("Kutatás folyamatban"), 3, L.t("Pár perc."))
	_step_rows.clear()
	var names := [L.t("Kérdés pontosítása"), L.t("Cikkek keresése 4 tudományos adatbázisban"), L.t("Fontos számok kiemelése"), L.t("Ellenőrzés: tényleg benne van a cikkben?")]
	for n in names:
		var l := UI.label("○  " + n, 18, UI.MUTE)
		_step_rows.append([l, n])
		_body.add_child(l)
	_short_label = UI.label("", 17, UI.SOFT)
	_body.add_child(_short_label)
	# A technikai napló (keresőszavak, adatbázisok találatai) csak a Részletek mögött.
	_log_label = UI.label("", 13, UI.MUTE)
	_log_label.visible = false
	var log_btn := UI.button(L.t("Részletek"))
	var log_fn := func() -> void: _log_label.visible = not _log_label.visible
	log_btn.pressed.connect(log_fn)
	_body.add_child(log_btn)
	_body.add_child(_log_label)
	if bridge.run("kutat", ["godot-kutat", L.t(str(_question["cim"])), "--ai", _ai, "--mappa", _folder, "--nyelv", L.lang,
			"--kereses", str(_question.get("kereses", "")), "--parameterek", str(_question.get("parameterek", "")),
			"--orszag", L.country(), "--cikkek", str(campaign.papers_per_research() if campaign != null else 12)]):
		_poll.start()
	else:
		_show_busy()


func _on_poll() -> void:
	# a cím után 1, 2, 3 pont jelenik meg balról jobbra, aztán újra elölről
	_dots = _dots % 3 + 1
	if is_instance_valid(_title_label):
		_title_label.text = _title_text + ".".repeat(_dots)
	var st: Variant = Bridge.read_json(_folder.path_join("allapot.json"))
	if typeof(st) != TYPE_DICTIONARY:
		return
	var step := int(st.get("lepes", 0))
	for i in _step_rows.size():
		var l: Label = _step_rows[i][0]
		var n: String = _step_rows[i][1]
		if i + 1 < step or st.get("allapot", "") == "kesz":
			l.text = "✓  " + n
			l.add_theme_color_override("font_color", UI.GREEN)
		elif i + 1 == step:
			l.text = "●  " + n
			l.add_theme_color_override("font_color", UI.GOLD)
	var lines: Array = st.get("naplo", [])
	_log_label.text = "\n".join(PackedStringArray(lines.slice(max(0, lines.size() - 12))))
	_short_label.text = str(st.get("rovid", ""))


func _on_bridge_finished(tag: String, code: int, output: String) -> void:
	if tag == "tema":
		var t: Variant = Bridge.read_json(_topic_out)
		var still_here := not _topic_q.is_empty()
		if typeof(t) == TYPE_DICTIONARY:
			var was_quick := _topic_phase == "gyors"
			if was_quick and _topic_ai != "none":
				_run_topic("ai")    # a részletes AI-magyarázat a háttérben
			if still_here and (was_quick or t.get("tipus") == "ai"):
				_render_topic(t)
		elif _topic_phase == "gyors":
			_show_python_error(code, output)
		return
	if tag == "ai":
		var d: Variant = Bridge.read_json(bridge.work_dir("aether_kutatas").path_join("ai.json"))
		_ai_status = d if typeof(d) == TYPE_DICTIONARY else {}
		if _ai_status.is_empty():
			_show_python_error(code, output)
		else:
			_show_ai_choice()
	elif tag == "kutat":
		_poll.stop()
		_on_poll()
		var st: Variant = Bridge.read_json(_folder.path_join("allapot.json"))
		if typeof(st) == TYPE_DICTIONARY and st.get("allapot", "") == "kesz":
			var r: Variant = Bridge.read_json(_folder.path_join("eredmeny.json"))
			if typeof(r) == TYPE_DICTIONARY:
				_result = r
				_show_results()
				return
		var msg := ""
		if typeof(st) == TYPE_DICTIONARY:
			msg = str(st.get("uzenet", ""))
		_show_python_error(code, output if msg == "" else msg)


func _show_python_error(code: int, output: String) -> void:
	_header(L.t("Valami nem sikerült"), 0, "")
	var hint := L.t("Ellenőrizd, hogy telepítve van-e a Python 3.10 vagy újabb, és van-e internet.")
	if code == -1 or code == 9009:
		hint = L.t("Nem találom a Pythont. Telepítsd a python.org oldalról (3.10 vagy újabb), majd indítsd újra a játékot.")
	_body.add_child(UI.label(hint, 18, UI.TEXT))
	var det := UI.label(output.right(1200), 14, UI.MUTE)
	det.visible = false
	var more := UI.button(L.t("Részletek"))
	var det_fn := func() -> void: det.visible = not det.visible
	more.pressed.connect(det_fn)
	_body.add_child(more)
	_body.add_child(det)
	var back := UI.button(L.t("Újra"))
	back.pressed.connect(show_questions)
	_body.add_child(back)
	print(output)


# --- 4. Mit találtunk? -----------------------------------------------------
func _show_results() -> void:
	_header(L.t("Mit találtunk?"), 4, "")
	var o: Dictionary = _result["osszefoglalo"]
	var pub: Dictionary = _result["publikacio"]
	var s := L.t("%d cikk. ") % int(o["cikkek"])
	if int(o.get("hazai", 0)) > 0:   # a játékos országának kutatóintézeteiből
		s = L.t("%d cikk (%d hazai). ") % [int(o["cikkek"]), int(o["hazai"])]
	if int(o["allitasok"]) > 0:
		s += L.t("%d szám ellenőrizve, %d elvetve.") % [int(o["ellenorizve"]), int(o["elutasitva"])]
	_body.add_child(UI.label(s, 18, UI.TEXT))
	var summary := str(pub.get("ai_osszegzes", ""))
	if summary != "":
		var c := UI.card(UI.GOLD)
		c.add_child(UI.label(L.t("Az AI összefoglalója"), 16, UI.GOLD, true))
		c.add_child(UI.label(summary, 16, UI.SOFT))
		_body.add_child(UI.card_root(c))
	_checks.clear()
	var props: Array = _result["javaslatok"]
	for j in props:
		_body.add_child(_proposal_card(j, pub))
	if props.is_empty():
		var why := L.t("AI nélkül csak cikklista készül, számok nem.") if _ai == "none" \
			else L.t("Nem találtunk ellenőrizhető számot. Ez is eredmény.")
		_body.add_child(UI.label(why, 17, UI.SOFT))
	_body.add_child(_paper_list(pub))
	var row := UI.hbox(12)
	var again := UI.button(L.t("Új kutatás"))
	again.pressed.connect(show_questions)
	row.add_child(again)
	if not _checks.is_empty():
		var ok := UI.button(L.t("Jóváhagyom, mehet a tervembe"), true)
		ok.pressed.connect(_approve)
		row.add_child(ok)
	_body.add_child(row)
	results_shown.emit(not _checks.is_empty())


func _proposal_card(j: Dictionary, _pub: Dictionary) -> Control:
	var usable: bool = j.get("kar") != null
	var c := UI.card(UI.CYAN if usable else UI.EDGE)
	var sub := str(j.get("alkategoria_nev", j.get("alkategoria", "")))   # köznapi név, nem a nyers (angol) alkategória
	c.add_child(UI.label(str(j["nev"]) + (" – " + sub if sub != "" else ""), 17, UI.SOFT))
	var big := "%s %s" % [L.num_short(float(j["ertek"]), 2), j["egyseg"]]
	c.add_child(UI.label(big, 26, UI.CYAN if usable else UI.TEXT, true))
	c.add_child(UI.label(str(j["jelentes"]), 17, UI.TEXT))
	var conf := str(j["bizonyossag"])
	c.add_child(UI.label(str(j["bizonyossag_szoveg"]), 15, UI.GREEN if conf == "magas" else (UI.GOLD if conf == "közepes" else UI.EMBER)))
	if str(j.get("megjegyzes", "")) != "":
		c.add_child(UI.label(str(j["megjegyzes"]), 14, UI.MUTE))
	if usable:
		var cb := CheckBox.new()
		cb.text = L.t("Beteszem a tervembe: ") + str(j["kar_nev"])
		cb.button_pressed = true
		cb.add_theme_font_size_override("font_size", 17)
		c.add_child(cb)
		_checks.append([cb, j])
	return UI.card_root(c)


## Egyszerű, kattintható szöveges link (nem gomb): ciánkék, balra, sort tör.
func _text_link(text: String, url: String, size: int = 15) -> Button:
	UI.load_fonts()
	var lb := Button.new()
	lb.text = text
	lb.flat = true
	lb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.add_theme_font_size_override("font_size", size)
	if UI.font_body != null:   # normál szöveg, nem a gombok vastag betűje
		lb.add_theme_font_override("font", UI.font_body)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		lb.add_theme_color_override(st, UI.CYAN)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 2
	empty.content_margin_bottom = 2
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		lb.add_theme_stylebox_override(st, empty)
	if url != "":
		lb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		lb.tooltip_text = url
		var open_fn := func() -> void: OS.shell_open(url)
		lb.pressed.connect(open_fn)
	return lb


func _paper_link(p: Dictionary) -> Control:
	var authors: Array = p.get("authors", [])
	var who := "?"
	if not authors.is_empty():
		who = str(authors[0]) + (L.t(" és mtsai") if authors.size() > 1 else "")
	var yr: Variant = p.get("year")
	var yr_s := str(int(yr)) if typeof(yr) in [TYPE_INT, TYPE_FLOAT] else "?"
	var t := "%s (%s): %s" % [who, yr_s, str(p.get("title", ""))]
	var home := ""
	if L.country() in Array(p.get("orszagok", [])):
		t = L.t("[Hazai] ") + t
		var inst: Variant = p.get("intezmenyek", {})
		if typeof(inst) == TYPE_DICTIONARY and inst.has(L.country()):
			home = L.t("Hazai intézmény: %s") % ", ".join(PackedStringArray(Array(inst[L.country()]).slice(0, 3))) + "\n"
	if typeof(p.get("peer_reviewed")) == TYPE_BOOL and p.get("peer_reviewed") == false:
		t += L.t("  [preprint, nem lektorált]")
	var url := ""
	var doi: Variant = p.get("doi")
	var plain: Variant = p.get("url")
	if doi != null and str(doi) != "":
		url = "https://doi.org/" + str(doi)
	elif plain != null:
		url = str(plain)
	# LinkButton nem tud sort törni, ezért lapos Button (hosszú cikkcímek miatt).
	var lb := Button.new()
	lb.text = t
	lb.flat = true
	lb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	lb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lb.add_theme_font_size_override("font_size", 14)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		lb.add_theme_color_override(st, UI.CYAN)
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.tooltip_text = home + url
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if url != "":
		var open_fn := func() -> void: OS.shell_open(url)
		lb.pressed.connect(open_fn)
	return lb


func _paper_list(pub: Dictionary) -> Control:
	var papers: Dictionary = pub.get("cikkek", {})
	var box := UI.vbox(4)
	var det := UI.vbox(4)
	det.visible = _result["javaslatok"].is_empty()
	for pid in papers:
		det.add_child(_paper_link(papers[pid]))
	var b := UI.button(L.t("Az átnézett cikkek listája (%d)") % papers.size())
	var det_fn := func() -> void: det.visible = not det.visible
	b.pressed.connect(det_fn)
	box.add_child(b)
	box.add_child(det)
	return box


# --- 5. Jóváhagyás ---------------------------------------------------------
func _approve() -> void:
	var levers: Array = []
	for pair in _checks:
		var cb: CheckBox = pair[0]
		if cb.button_pressed:
			levers.append(pair[1])
	approved.emit(levers)
