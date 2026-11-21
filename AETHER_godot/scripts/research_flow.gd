extends PanelContainer
## Kutatás, lépésről lépésre. Minden képernyőn egyetlen döntés:
##   1. Mit kutassunk?  2. Ki kutasson?  3. (vár)  4. Mit találtunk?  5. Jóváhagyás

signal approved(levers: Array)
signal results_shown(has_levers: bool)
signal closed

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

const QUESTIONS := [
	{"cim": "Mennyi CO2-t vonhat ki a levegőből a bioszén?",
	 "magyarazat": "A bioszén elszenesített növényi hulladék. A talajba keverve hosszú ideig tárolja a szenet.",
	 "kereses": "biochar carbon dioxide removal potential"},
	{"cim": "Mennyit segít a kőzetmállasztás?",
	 "magyarazat": "Finomra őrölt kőzetet szórnak a földekre, ami lassan megköti a levegő CO2-jét.",
	 "kereses": "enhanced rock weathering carbon dioxide removal potential"},
	{"cim": "Mennyi CO2-t köthet meg az erdősítés?",
	 "magyarazat": "Új erdők telepítése: a fák növekedés közben szenet építenek be.",
	 "kereses": "afforestation reforestation carbon dioxide removal potential"},
	{"cim": "Segítenek-e az aszálytűrő kukoricafajták?",
	 "magyarazat": "Ez nem hűti a Földet, de megvédheti a termést a forró, száraz években.",
	 "kereses": "drought tolerant maize yield advantage under drought"},
]

const AI_CHOICES := [
	{"id": "claude", "cim": "Claude (saját előfizetés)", "magyarazat": "A legalaposabb. Kell hozzá egy Anthropic API-kulcs."},
	{"id": "ollama", "cim": "Helyi AI a gépeden (Ollama)", "magyarazat": "Ingyenes és internet nélkül is gondolkodik, de lassabb."},
	{"id": "none", "cim": "AI nélkül: csak cikkeket keresek", "magyarazat": "Mindig működik. Megmutatja a cikkeket, de számokat nem emel ki."},
]

var bridge                  # lab_bridge.gd példány (a main.gd adja át)
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
var _dots := 0


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.CYAN
	sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = UI.vbox(14)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_poll = Timer.new()
	_poll.wait_time = 0.4
	_poll.timeout.connect(_on_poll)
	add_child(_poll)
	bridge.finished.connect(_on_bridge_finished)
	show_questions()


func _header(title: String, step: int, help: String) -> void:
	UI.clear(_body)
	var h := UI.hbox(12)
	h.add_child(UI.heading(title))
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
	_header(L.t("Mit kutassunk?"), 1, L.t("Válassz egy kérdést. A játék valódi, megjelent tudományos cikkekben keres rá választ."))
	for q in QUESTIONS:
		var c := UI.card(UI.CYAN)
		c.add_child(UI.label(L.t(q["cim"]), 19, UI.TEXT, true))
		c.add_child(UI.label(L.t(q["magyarazat"]), 16, UI.SOFT))
		var b := UI.button(L.t("Ezt kutatom"))
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.pressed.connect(_pick_question.bind(q))
		c.add_child(b)
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


func _pick_question(q: Dictionary) -> void:
	_question = q
	_header(L.t("Ki kutasson?"), 2, L.t("Megnézem, milyen AI érhető el a gépeden…"))
	var path: String = bridge.work_dir("aether_kutatas").path_join("ai.json")
	if not bridge.run("ai", ["godot-ai", "--ki", path, "--nyelv", L.lang]):
		_show_busy()


func _show_busy() -> void:
	_header(L.t("Egy pillanat…"), 0, L.t("A játék még letölti a valós adatokat. Próbáld újra pár másodperc múlva."))
	var back := UI.button(L.t("Újra"))
	back.pressed.connect(show_questions)
	_body.add_child(back)


# --- 2. Ki kutasson? -------------------------------------------------------
func _show_ai_choice() -> void:
	_header(L.t("Ki kutasson?"), 2, L.t("Kérdés: ") + L.t(str(_question["cim"])))
	var best := "none"
	if _ai_status.get("ollama", {}).get("elerheto", false):
		best = "ollama"
	if _ai_status.get("claude", {}).get("elerheto", false):
		best = "claude"
	var group := ButtonGroup.new()
	var key_box := UI.vbox(6)
	for ch in AI_CHOICES:
		var id: String = ch["id"]
		var st: Dictionary = _ai_status.get(id, {})
		var c := UI.card(UI.GREEN if st.get("elerheto", false) else UI.EDGE)
		var rb := CheckBox.new()
		rb.button_group = group
		rb.text = L.t(ch["cim"]) + (L.t("   (ajánlott)") if id == best else "")
		rb.add_theme_font_override("font", UI.font_bold)
		rb.add_theme_font_size_override("font_size", 18)
		rb.button_pressed = id == best
		var need_key: bool = id == "claude" and not _ai_status.get("claude", {}).get("elerheto", false)
		var pick_fn := func(on: bool) -> void:
			if on:
				_ai = id
				key_box.visible = need_key
		rb.toggled.connect(pick_fn)
		c.add_child(rb)
		c.add_child(UI.label(L.t(ch["magyarazat"]), 16, UI.SOFT))
		c.add_child(UI.label(str(st.get("ok", "")), 15, UI.GREEN if st.get("elerheto", false) else UI.MUTE))
		_body.add_child(UI.card_root(c))
	_ai = best
	key_box.visible = false
	# API-kulcs megadása: csak erre a futásra, sehova nem mentjük
	key_box.visible = false
	key_box.add_child(UI.label(L.t("Anthropic API-kulcs (csak amíg a játék fut, nem mentjük el):"), 16, UI.SOFT))
	var key := LineEdit.new()
	key.secret = true
	key.placeholder_text = "sk-ant-…"
	var key_fn := func(t: String) -> void: OS.set_environment("ANTHROPIC_API_KEY", t.strip_edges())
	key.text_changed.connect(key_fn)
	key_box.add_child(key)
	_body.add_child(key_box)
	var row := UI.hbox(12)
	var back := UI.button(L.t("Vissza"))
	back.pressed.connect(show_questions)
	row.add_child(back)
	var start := UI.button(L.t("Indulhat a kutatás"), true)
	start.pressed.connect(_start_research)
	row.add_child(start)
	_body.add_child(row)


# --- 3. Kutatás folyamatban -----------------------------------------------
func _start_research() -> void:
	_folder = str(bridge.work_dir("aether_kutatas")).path_join("kutatas_%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_folder)
	_header(L.t("Kutatás folyamatban"), 3, L.t("Az AI cikkeket olvas, a játék pedig mindent szó szerint ellenőriz. Ez 1–5 percig is tarthat."))
	_step_rows.clear()
	var names := [L.t("Kérdés pontosítása"), L.t("Cikkek keresése 4 tudományos adatbázisban"), L.t("Fontos számok kiemelése"), L.t("Ellenőrzés: tényleg benne van a cikkben?")]
	for n in names:
		var l := UI.label("○  " + n, 18, UI.MUTE)
		_step_rows.append([l, n])
		_body.add_child(l)
	_log_label = UI.label("", 14, UI.MUTE)
	_body.add_child(_log_label)
	if bridge.run("kutat", ["godot-kutat", L.t(str(_question["cim"])), "--ai", _ai, "--mappa", _folder, "--nyelv", L.lang,
			"--kereses", str(_question.get("kereses", ""))]):
		_poll.start()
	else:
		_show_busy()


func _on_poll() -> void:
	_dots = (_dots + 1) % 4
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
			l.text = "●  " + n + ".".repeat(_dots)
			l.add_theme_color_override("font_color", UI.GOLD)
	var lines: Array = st.get("naplo", [])
	_log_label.text = "\n".join(PackedStringArray(lines.slice(max(0, lines.size() - 5))))


func _on_bridge_finished(tag: String, code: int, output: String) -> void:
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
	var s := L.t("%d cikket olvastunk el. ") % int(o["cikkek"])
	if int(o["allitasok"]) > 0:
		s += L.t("%d számot szó szerint megtaláltunk a cikkekben, %d másikat kidobtunk, mert nem szerepelt bennük pontosan így.") % [int(o["ellenorizve"]), int(o["elutasitva"])]
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
		var why := L.t("AI nélkül csak a cikkeket gyűjtöttük össze. Számokat az AI tud kiemelni belőlük.") if _ai == "none" \
			else L.t("Ezekben a cikkekben nem találtunk ellenőrizhető számot erre a kérdésre. Ez is eredmény: érdemes másképp kérdezni.")
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
	_body.add_child(UI.label(L.t("Ez játékon belüli, gépi irodalmi összefoglaló, nem lektorált szakvélemény."), 14, UI.MUTE))
	results_shown.emit(not _checks.is_empty())


func _proposal_card(j: Dictionary, pub: Dictionary) -> Control:
	var usable: bool = j.get("kar") != null
	var c := UI.card(UI.CYAN if usable else UI.EDGE)
	c.add_child(UI.label(str(j["nev"]) + (" – " + str(j["alkategoria"]) if str(j["alkategoria"]) != "" else ""), 17, UI.SOFT))
	var big := "%s %s" % [UI.hu(float(j["ertek"]), 2).trim_suffix("0").trim_suffix(",0").trim_suffix(".0"), j["egyseg"]]
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
	# Részletek: a szó szerinti idézetek és a forrás
	var det := UI.vbox(6)
	det.visible = false
	for cl in pub.get("allitasok", []):
		if str(cl["parameter"]) != str(j["parameter"]) or not str(cl["statusz"]).begins_with("ellenorizve"):
			continue
		det.add_child(UI.label("„" + str(cl["szo_szerinti_idezet"]) + "”", 15, UI.SOFT))
		var paper: Dictionary = pub["cikkek"].get(str(cl["cikk_azonosito"]), {})
		det.add_child(_paper_link(paper))
	var more := UI.button(L.t("Részletek: honnan tudjuk?"))
	var det_fn := func() -> void: det.visible = not det.visible
	more.pressed.connect(det_fn)
	c.add_child(more)
	c.add_child(det)
	return UI.card_root(c)


func _paper_link(p: Dictionary) -> Control:
	var authors: Array = p.get("authors", [])
	var who := "?"
	if not authors.is_empty():
		who = str(authors[0]) + (L.t(" és mtsai") if authors.size() > 1 else "")
	var yr: Variant = p.get("year")
	var yr_s := str(int(yr)) if typeof(yr) in [TYPE_INT, TYPE_FLOAT] else "?"
	var t := "%s (%s): %s" % [who, yr_s, str(p.get("title", ""))]
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
	lb.tooltip_text = url
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
