extends PanelContainer
## Kutatás, lépésről lépésre. Minden képernyőn egyetlen döntés:
##   1. Mit kutassunk?  2. Ki kutasson?  3. (vár)  4. Mit találtunk?  5. Jóváhagyás

signal approved(levers: Array)
signal learned(q: Dictionary)
signal results_shown(has_levers: bool)
signal closed

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

## A kérdések a tudásfa témái (knowledge.gd): korszakonként nyílnak meg.
const Knowledge := preload("res://scripts/knowledge.gd")
const Missions := preload("res://scripts/missions.gd")

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
	_body.add_child(h)
	if help != "":
		_body.add_child(UI.label(help, 17, UI.SOFT))


func _close() -> void:
	_poll.stop()
	closed.emit()


# --- 1. Mit kutassunk? -----------------------------------------------------
## Sok téma van, ezért korszakonként és tudományterületenként csoportosítjuk (a csoport
## kattintásra nyílik), és felül kereső van. A keresés csak a nyitott korszakokban keres.
var _filter := ""
var _open_fields := {}        # "korszak:terület" -> true, ha nyitva
var _list: VBoxContainer


func show_questions() -> void:
	_topic_q = {}
	_header(L.t("Mit kutassunk?"), 1, L.t("Válassz kérdést. A válasz valódi tudományos cikkekből jön."))
	if campaign != null:
		_body.add_child(_era_strip())
		var rec := _recommend()
		if not rec.is_empty():
			_body.add_child(_recommend_card(rec))
	_body.add_child(_ai_line())
	var search := LineEdit.new()
	search.placeholder_text = L.t("Keresés a témák között, pl. jég, akkumulátor, metán")
	search.text = _filter
	search.clear_button_enabled = true
	search.add_theme_font_size_override("font_size", 17)
	var on_search := func(t: String) -> void:
		_filter = t
		_fill_questions()
	search.text_changed.connect(on_search)
	_body.add_child(search)
	_list = UI.vbox(12)
	_body.add_child(_list)
	_fill_questions()
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


func _matches(q: Dictionary, f: String) -> bool:
	if f == "":
		return true
	var hay := (Knowledge.text(q, "cim") + " " + Knowledge.text(q, "magyarazat") + " "
		+ Knowledge.field_name(str(q.get("terulet", "")))).to_lower()
	for w in f.split(" ", false):
		if not hay.contains(w):
			return false
	return true


func _fill_questions() -> void:
	UI.clear(_list)
	var era: int = campaign.era if campaign != null else Knowledge.ERAS.size()
	var done: Array = campaign.done if campaign != null else []
	var f := _filter.strip_edges().to_lower()
	var found := 0
	for e in range(1, Knowledge.ERAS.size() + 1):
		if f != "" and e > era:
			continue
		if e > era + 1:   # a távolabbi korszakok csak egy sorban
			_list.add_child(UI.label(Knowledge.era_name(e) + " · " + L.t("zárva"), 16, UI.MUTE, true))
			continue
		var all: Array = Knowledge.topics_of(e)
		var n_done := all.filter(func(t: Dictionary) -> bool: return t["id"] in done).size()
		var head_text := Knowledge.era_name(e) + (" · %d/%d" % [n_done, all.size()] if e <= era else " · " + L.t("zárva"))
		_list.add_child(UI.label(head_text, 20, UI.GOLD if e <= era else UI.MUTE, true))
		if f == "":
			_list.add_child(UI.label(L.t(Knowledge.ERAS[e - 1]["tema"]), 15, UI.SOFT))
		if e > era:   # a következő korszak: mi kell a megnyitásához
			for cond in campaign.era_conditions(e):
				_list.add_child(UI.label(("✓ " if cond[1] else "○ ") + str(cond[0]), 15, UI.GREEN if cond[1] else UI.TEXT))
			continue
		for code in Knowledge.field_codes():
			var qs: Array = all.filter(func(t: Dictionary) -> bool: return str(t.get("terulet", "")) == code and _matches(t, f))
			if qs.is_empty():
				continue
			found += qs.size()
			var key := "%d:%s" % [e, code]
			var is_open: bool = f != "" or _open_fields.has(key)
			var k_done := qs.filter(func(t: Dictionary) -> bool: return t["id"] in done).size()
			var hb := UI.button(("▾  " if is_open else "▸  ") + Knowledge.field_name(code) + "   %d/%d" % [k_done, qs.size()])
			hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			hb.pressed.connect(_toggle_field.bind(key))
			_list.add_child(hb)
			if is_open:
				for q in qs:
					_list.add_child(_question_card(q, q["id"] in done))
	if f != "" and found == 0:
		_list.add_child(UI.label(L.t("Nincs ilyen téma a nyitott korszakokban."), 16, UI.SOFT))


func _toggle_field(key: String) -> void:
	if _open_fields.has(key):
		_open_fields.erase(key)
	else:
		_open_fields[key] = true
	_fill_questions()


## Egy kutatható téma kártyája: kérdés, egy mondat, csillagok vagy mit ad, és két gomb.
func _question_card(q: Dictionary, is_done: bool) -> Control:
	var c := UI.card(UI.GREEN if is_done else UI.CYAN)
	c.add_child(UI.label(Knowledge.text(q, "cim"), 19, UI.TEXT, true))
	c.add_child(UI.label(Knowledge.text(q, "magyarazat"), 16, UI.SOFT))
	var gives := Knowledge.text(q, "nyit")
	var row := UI.hbox(12)
	var l: Label
	if is_done:
		var n: int = int(campaign.stars.get(q["id"], 1)) if campaign != null else 1
		l = UI.label(L.t("✓ Kutatva ") + Missions.star_text(n) + ("  " + gives if gives != "" else ""), 15, UI.GREEN)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.tooltip_text = star_rule()
	else:
		l = UI.label(L.t("Ha kikutatod: ") + gives if gives != "" else "", 15, UI.GOLD)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var info := UI.button(L.t("Mi ez, és mire jó?"))
	info.pressed.connect(_show_topic.bind(q))
	row.add_child(info)
	var b := UI.button(L.t("Újra kutatom") if is_done else L.t("Ezt kutatom"))
	b.pressed.connect(_pick_question.bind(q))
	row.add_child(b)
	c.add_child(row)
	return UI.card_root(c)


## A csillagok szabálya (játékszabály), a csillagok fölé húzott egérnél.
static func star_rule() -> String:
	return L.t("Játékszabály: ★ elolvastad az összefoglalót vagy ellenőrzött számot találtál, ★★ legalább 2 cikk egyezik, ★★★ legalább 3 cikk, köztük összefoglaló elemzés.")


# --- „Mi ez, és mire jó?” ---------------------------------------------------
## Gyorsítás, három szinten:
##  1. a témafájlban (res://temak/*.txt) lévő, lektorálható magyarázat – azonnali,
##  2. különben előbb AI nélkül (Wikipédia, 1–2 mp) jelenik meg valami,
##  3. az AI közben a háttérben dolgozik, és ha kész, lecseréli a részletesre.
## Ami egyszer elkészült, a gépen megmarad (user://aether_temak).
var _topic_out := ""
var _topic_q: Dictionary = {}
var _topic_ai := "none"
var _topic_phase := ""           # "gyors" (AI nélkül) vagy "ai"


func _topic_path(q: Dictionary, ai: String) -> String:
	return bridge.work_dir("aether_temak").path_join("v2_%s_%s_%s.json" % [str(q["wiki_en"]).md5_text().left(10), L.lang, ai])


func _show_topic(q: Dictionary) -> void:
	_topic_q = q
	_topic_ai = L.get_setting("ai", "ollama")
	if Knowledge.has_explanation(q):   # a témafájlban lévő (lektorálható) magyarázat: azonnali
		_render_topic({"magyarazat": {"mire_jo": Knowledge.text_raw(q, "mire_jo"),
			"hatranyok": Knowledge.text_raw(q, "hatranyok"),
			"mennyire_bizonyitott": Knowledge.text_raw(q, "mennyire_bizonyitott")},
			"cikkek": Knowledge.sources(q), "tipus": "fajl"})
		return
	for ai in [_topic_ai, "none"]:
		var cached: Variant = Bridge.read_json(_topic_path(q, ai))
		if typeof(cached) == TYPE_DICTIONARY and not ((cached as Dictionary).get("cikkek", []) as Array).is_empty():
			_render_topic(cached)
			if ai != _topic_ai and _topic_ai != "none":
				_run_topic("ai")
			return
	_header(Knowledge.text(q, "cim"), 0, "")
	_body.add_child(UI.label(L.t("Egy pillanat, töltöm a forrásokat…"), 17, UI.SOFT))
	_run_topic("gyors")


func _run_topic(phase: String) -> void:
	_topic_phase = phase
	var ai := "none" if phase == "gyors" else _topic_ai
	_topic_out = _topic_path(_topic_q, ai)
	if not bridge.run("tema", ["tema", "--wiki", str(_topic_q["wiki"]), "--wiki-en", str(_topic_q["wiki_en"]),
			"--kereses", str(_topic_q["attekintes"]), "--cim", Knowledge.text(_topic_q, "cim"), "--ki", _topic_out, "--ai", ai, "--nyelv", L.lang]):
		if phase == "gyors":
			_show_busy()


func _render_topic(r: Dictionary) -> void:
	_header(Knowledge.text(_topic_q, "cim"), 0, "")
	var m: Variant = r.get("magyarazat")
	if typeof(m) == TYPE_DICTIONARY:
		for part in [["mire_jo", "Mire jó?"], ["hatranyok", "Mi a gond vele?"], ["mennyire_bizonyitott", "Mennyire bizonyított?"]]:
			if str(m.get(part[0], "")).strip_edges() == "":
				continue
			var c := UI.card(UI.GOLD)
			c.add_child(UI.label(L.t(part[1]), 17, UI.GOLD, true))
			c.add_child(UI.label(str(m.get(part[0], "")), 17, UI.TEXT))
			_body.add_child(UI.card_root(c))
	# A források: AI-összefoglaló mellett egy gomb mögött, egymás alatt; anélkül láthatóan.
	var src := UI.vbox(2)
	var w: Variant = r.get("wiki")
	var wiki_shown := false
	if typeof(w) == TYPE_DICTIONARY:
		# AI nélkül a Wikipédia bevezetője, de csak a játékos nyelvén; ha az AI még ír, semmi
		if typeof(m) != TYPE_DICTIONARY and _topic_ai == "none" and str(w.get("nyelv", "")) == L.lang:
			var c := UI.card(UI.GOLD)
			c.add_child(UI.label(L.t("Wikipédia"), 17, UI.GOLD, true))
			c.add_child(UI.label(str(w.get("bevezeto", "")), 17, UI.TEXT))
			_body.add_child(UI.card_root(c))
			wiki_shown = true
		src.add_child(UI.text_link(L.t("Wikipédia: ") + str(w.get("cim", "")) + Knowledge.lang_note(str(w.get("nyelv", "")))
			+ " · CC BY-SA 4.0", str(w.get("link", ""))))
	if typeof(m) != TYPE_DICTIONARY and not wiki_shown:
		var own := Knowledge.text(_topic_q, "magyarazat")
		if own != "":
			var c := UI.card(UI.GOLD)
			c.add_child(UI.label(L.t("Röviden"), 17, UI.GOLD, true))
			c.add_child(UI.label(own, 17, UI.TEXT))
			_body.add_child(UI.card_root(c))
		if _topic_ai == "none":
			_body.add_child(UI.label(L.t("Részletesebb magyarázatot az AI ír. AI-t a kutatás 2. lépésében választhatsz."), 15, UI.SOFT))
	var papers: Array = r.get("cikkek", [])
	if not papers.is_empty():
		src.add_child(UI.label(L.t("Tudományos összefoglaló cikkek"), 15, UI.SOFT, true))
		for p in papers:
			var ev := str(p.get("ev", ""))
			if ev.is_valid_float():
				ev = str(int(float(ev)))   # 2023.0 -> 2023
			var t := "• " + str(p.get("cim", "")) + (" (%s)" % ev if ev != "" else "")
			src.add_child(UI.text_link(t + Knowledge.lang_note(str(p.get("link", ""))), str(p.get("link", ""))))
	if typeof(m) == TYPE_DICTIONARY and src.get_child_count() > 0:
		src.visible = false
		var sb := UI.button(L.t("AI-összefoglaló forrásai"))
		var src_fn := func() -> void: src.visible = not src.visible
		sb.pressed.connect(src_fn)
		_body.add_child(sb)
	_body.add_child(src)
	if typeof(w) != TYPE_DICTIONARY and papers.is_empty() and str(r.get("tipus", "")) != "fajl":
		_body.add_child(UI.label(L.t("Most nem sikerült forrást letölteni. Van internet?"), 17, UI.EMBER))
	if str(r.get("megjegyzes", "")) != "":
		_body.add_child(UI.label(str(r["megjegyzes"]), 13, UI.MUTE))
	if typeof(m) != TYPE_DICTIONARY and _topic_ai != "none" and bridge.is_busy():
		_body.add_child(UI.label(L.t("Az AI részletesebb magyarázatot ír…"), 15, UI.GOLD))
	var row := UI.hbox(12)
	var back := UI.button(L.t("Vissza a kérdésekhez"))
	back.pressed.connect(show_questions)
	row.add_child(back)
	var tid := str(_topic_q.get("id", ""))
	var known: bool = campaign != null and tid in campaign.done
	if str(r.get("tipus", "")) == "fajl" and campaign != null and not known:
		var learn := UI.button(L.t("Elolvastam, értem  ★"), true)
		learn.tooltip_text = L.t("Játékszabály: az összefoglaló elolvasása ★ tudást ad. Számot a tervedbe csak kutatás ad.")
		learn.pressed.connect(_learn.bind(_topic_q))
		row.add_child(learn)
	var go := UI.button(L.t("Ezt kutatom"), known or str(r.get("tipus", "")) != "fajl")
	go.pressed.connect(_pick_question.bind(_topic_q))
	row.add_child(go)
	_body.add_child(row)


func _pick_question(q: Dictionary) -> void:
	_topic_q = {}
	_question = q
	if campaign != null and campaign.research_problem() != "":   # még a választás előtt szólunk
		_header(L.t("Most nem lehet kutatni"), 0, campaign.research_problem())
		var back := UI.button(L.t("Vissza"))
		back.pressed.connect(show_questions)
		_body.add_child(back)
		return
	# Ha már választott AI-t, nem kérdezzük újra (kevesebb kattintás); a „Másik AI” gombbal válthat.
	_quick = not _force_choice and _saved_ai() != "" and not ("--onteszt" in OS.get_cmdline_user_args())
	_force_choice = false
	_header(L.t("Kutatás indul…") if _quick else L.t("Ki kutasson?"), 2,
		L.t("Megnézem, milyen AI érhető el a gépeden…"))
	_ask_ai(0)


var _quick := false
var _force_choice := false
var _from_archive := false       # az eredmény az archívumból jött (nem most kutattuk)


func _saved_ai() -> String:
	return str(L.get_setting("ai", ""))


## Rövid név a „Kutató AI:” sorhoz.
static func _ai_name(id: String) -> String:
	var short := {"claude": "Claude", "openai": "ChatGPT", "gemini": "Gemini",
		"ollama": L.t("helyi Ollama"), "none": L.t("nincs (csak cikkeket keresek)")}
	return str(short.get(id, id))


## Egy sor a kereső fölött: ki kutat, és egy gomb, hogy másik AI-t válasszon a következő kutatáshoz.
func _ai_line() -> Control:
	var row := UI.hbox(12)
	var id := _saved_ai()
	var l := UI.label(L.t("Kutató AI: ") + (_ai_name(id) if id != "" else L.t("az első kutatásnál választod")),
		15, UI.MUTE, false, false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if id != "":
		var b := UI.button(L.t("Másik AI") if not _force_choice else L.t("A következő kutatásnál választasz"))
		b.add_theme_font_size_override("font_size", 15)
		var fn := func() -> void:
			_force_choice = true
			b.text = L.t("A következő kutatásnál választasz")
		b.pressed.connect(fn)
		row.add_child(b)
	return row


## Korszak-sáv: négy csempe, mindegyiken a kutatott témák aránya. A nyitott korszak
## csempéjére kattintva annak minden területe kinyílik.
func _era_strip() -> Control:
	var row := UI.hbox(10)
	var done: Array = campaign.done
	for e in range(1, Knowledge.ERAS.size() + 1):
		var all: Array = Knowledge.topics_of(e)
		var n := all.filter(func(t: Dictionary) -> bool: return t["id"] in done).size()
		var col: Color = UI.GREEN if e < campaign.era else (UI.GOLD if e == campaign.era else UI.EDGE)
		var p := Button.new()
		p.focus_mode = Control.FOCUS_NONE
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(0, 76)
		p.disabled = e > campaign.era
		var sb := StyleBoxFlat.new()
		sb.bg_color = UI.CARD_BG.lerp(col, 0.12 if e <= campaign.era else 0.0)
		sb.border_color = col
		sb.set_border_width_all(2)
		sb.border_width_bottom = 4
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			var x: StyleBoxFlat = sb.duplicate()
			if st == "hover":
				x.bg_color = sb.bg_color.lightened(0.08)
			p.add_theme_stylebox_override(st, x)
		var v := UI.vbox(4)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var era_label: String = Knowledge.era_name(e) if e <= campaign.era + 1 else Knowledge.ROMAN[e - 1] + " " + L.t("zárva")
		var t := UI.label(era_label, 16, col if e <= campaign.era else UI.MUTE, true, false)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.max_value = maxi(1, all.size())
		bar.value = n
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.35)
		var fg := StyleBoxFlat.new()
		fg.bg_color = col if e <= campaign.era else UI.MUTE
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		v.add_child(bar)
		var cnt := UI.label("%d/%d" % [n, all.size()], 14, UI.SOFT, false, false)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(cnt)
		p.add_child(v)
		p.pressed.connect(_open_era.bind(e))
		row.add_child(p)
	var total := 0
	for k in campaign.stars:
		total += int(campaign.stars[k])
	var st_l := UI.label("★ %d" % total, 22, UI.GOLD, true, false)
	st_l.tooltip_text = star_rule()
	st_l.mouse_filter = Control.MOUSE_FILTER_PASS
	st_l.custom_minimum_size = Vector2(70, 0)
	st_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(st_l)
	return row


## Egy korszak minden területét kinyitja, a többit becsukja.
func _open_era(e: int) -> void:
	_open_fields.clear()
	for code in Knowledge.field_codes():
		_open_fields["%d:%s" % [e, code]] = true
	_filter = ""
	show_questions()


## Mit érdemes most kutatni? (játékszabály: a küldetéshez vagy a következő korszakhoz kell)
## {"tema": téma, "miert": egy rövid mondat}, vagy üres.
func _recommend() -> Dictionary:
	var done: Array = campaign.done
	var m: Dictionary = Missions.LIST[Missions.first_open()]
	if m["id"] == "alkalmazkodas" and not ("kukorica" in done) and not Knowledge.topic("kukorica").is_empty():
		return {"tema": Knowledge.topic("kukorica"), "miert": L.t("Ez kell a küldetésedhez.")}
	var era: int = campaign.era
	var open: Array = Knowledge.topics_of(era).filter(func(t: Dictionary) -> bool: return not (t["id"] in done))
	if open.is_empty():
		return {}
	var why := ""
	if era < Knowledge.ERAS.size():
		var need := int(Knowledge.ERAS[era].get("kell", 0))
		var left := need - Knowledge.count_done(done, era)
		if left > 0:
			why = L.t("Még %d kutatott téma, és közelebb kerülsz ehhez: %s.") % [left, Knowledge.era_name(era + 1)]
	if why == "":
		why = L.t("Új tudás ebben a korszakban.")
	# változatosság: abból a területből, ahol a legkevesebb a kutatott téma
	var best: Dictionary = open[0]
	var best_n := 999
	for t in open:
		var f := str(t.get("terulet", ""))
		var n := done.filter(func(id) -> bool: return str(Knowledge.topic(str(id)).get("terulet", "")) == f).size()
		if n < best_n:
			best_n = n
			best = t
	return {"tema": best, "miert": why}


func _recommend_card(rec: Dictionary) -> Control:
	var q: Dictionary = rec["tema"]
	var c := UI.card(UI.GOLD)
	c.add_child(UI.label(L.t("Ajánlott most") + " · " + Knowledge.field_name(str(q.get("terulet", ""))), 15, UI.GOLD, true))
	c.add_child(UI.label(Knowledge.text(q, "cim"), 20, UI.TEXT, true))
	var row := UI.hbox(12)
	var why := UI.label(str(rec["miert"]), 15, UI.SOFT)
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(why)
	var info := UI.button(L.t("Mi ez, és mire jó?"))
	info.pressed.connect(_show_topic.bind(q))
	row.add_child(info)
	var b := UI.button(L.t("Ezt kutatom"), true)
	b.pressed.connect(_pick_question.bind(q))
	row.add_child(b)
	c.add_child(row)
	return UI.card_root(c)


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
	_header(L.t("Ki kutasson?"), 2, L.t("Kérdés: ") + Knowledge.text(_question, "cim"))
	# Miért kell AI? Két rövid mondat, „Részletek” nélkül.
	var why := UI.card(UI.GOLD)
	why.add_child(UI.label(L.t("Miért kell AI?"), 17, UI.GOLD, true))
	why.add_child(UI.label(L.t("Az AI a kutatód: cikkeket olvas és számokat keres. A játék mindet ellenőrzi."), 16, UI.SOFT))
	why.add_child(UI.label(L.t("A ChatGPT, Claude vagy Gemini előfizetés nem elég, API-kulcs kell. Az Ollama ingyenes."), 15, UI.MUTE))
	_body.add_child(UI.card_root(why))
	var best := "none"
	for id in ["ollama", "gemini", "openai", "claude"]:   # a legalaposabb elérhető
		if _ai_status.get(id, {}).get("elerheto", false):
			best = id
	if _saved_ai() != "" and _ai_status.get(_saved_ai(), {}).get("elerheto", false):
		best = _saved_ai()   # amit legutóbb választott
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
		if id == "none" and not archive_of(_question).is_empty():
			c.add_child(UI.label(L.t("Ehhez a kérdéshez van kész, ellenőrzött kutatás az archívumban: azonnal megkapod."), 15, UI.GREEN))
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
# --- Archívum: előre elvégzett, ellenőrzött kutatások (AI nélkül is játszható) ------
## Az archívum egy-egy fájlja ugyanaz az eredmény, amit egy valódi kutatás ír (eredmeny.json):
## valódi cikkek, szó szerinti idézetek, a játék által ellenőrzött számok. Egy „archivum” mező
## mondja meg, mikor és milyen AI-val készült. Semmi sincs benne kézzel kitalálva.
static func archive_path(q: Dictionary, lang: String) -> String:
	return "res://archivum/%s_%s.json" % [str(q.get("id", "")), lang]


static func archive_of(q: Dictionary) -> Dictionary:
	for lang in [L.lang, "hu", "en"]:
		var path := archive_path(q, lang)
		if FileAccess.file_exists(path):
			var d: Variant = Bridge.read_json(path)
			if typeof(d) == TYPE_DICTIONARY and d.has("publikacio") and d.has("javaslatok") and d.has("osszefoglalo"):
				return d
	return {}


## „Elolvastam, értem”: a lektorált összefoglaló elolvasása is tudás (★), AI nélkül.
## Játékszabály: az évi kutatások közé számít, pénzbe nem kerül, számot nem ad a tervbe.
func _learn(q: Dictionary) -> void:
	if campaign == null:
		return
	if campaign.research_this_year >= campaign.research_limit():
		_body.add_child(UI.label(L.t("Idén már eleget tanultál és kutattál. Jövőre folytathatod!"), 17, UI.EMBER))
		return
	campaign.research_this_year += 1
	campaign.mark_researched(str(q["id"]), 1)
	learned.emit(q)
	show_questions()


func _start_research() -> void:
	if campaign != null:
		var problem: String = campaign.research_problem()
		if problem != "":
			_body.add_child(UI.label(problem, 17, UI.EMBER))
			return
		campaign.pay_research()
	L.set_setting("ai", _ai)   # az események összefoglalója is ezt az AI-t használja
	if _ai == "none":   # AI nélkül: ha van kész, ellenőrzött kutatás az archívumban, azt mutatjuk
		var arch := archive_of(_question)
		if not arch.is_empty():
			_result = arch
			_from_archive = true
			_show_results()
			return
	_from_archive = false
	_folder = str(bridge.work_dir("aether_kutatas")).path_join("kutatas_%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_folder)
	_header(L.t("Kutatás folyamatban"), 3, L.t("Pár percig tarthat.") + " " + L.t("Kutató AI: ") + _ai_name(_ai)
		+ (L.t(" · %d pénz") % campaign.research_cost() if campaign != null else ""))
	_step_rows.clear()
	var names := [L.t("Kérdés pontosítása"), L.t("Cikkek keresése 4 tudományos adatbázisban"), L.t("Fontos számok kiemelése"), L.t("Ellenőrzés: tényleg benne van a cikkben?")]
	for n in names:
		var l := UI.label("○  " + n, 18, UI.MUTE)
		_step_rows.append([l, n])
		_body.add_child(l)
	_short_label = UI.label("", 17, UI.SOFT)
	_body.add_child(_short_label)
	if bridge.run("kutat", ["godot-kutat", Knowledge.text(_question, "cim"), "--ai", _ai, "--mappa", _folder, "--nyelv", L.lang,
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
		elif _quick and _ai_status.get(_saved_ai(), {}).get("elerheto", false):
			_ai = _saved_ai()
			_start_research()
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
	if _from_archive:
		var meta: Dictionary = _result.get("archivum", {})
		_body.add_child(UI.label(L.t("Az AETHER archívumából: ezt a kutatást egy AI már elvégezte (%s), a játék ellenőrizte.") % str(meta.get("datum", "")), 15, UI.GOLD))
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
	var tid := str(_question.get("id", ""))
	var n_stars := Knowledge.stars_for(props)
	if n_stars > 0 and campaign != null and tid != "":
		var was_done: bool = tid in campaign.done
		var old := int(campaign.stars.get(tid, 0))
		campaign.mark_researched(tid, n_stars)   # tudásfa: ellenőrzött szám van, a téma kutatott
		if not was_done or n_stars > old:
			var msg := L.t("Új tudás a tudásfán: ") if not was_done else L.t("Erősebb tudás a tudásfán: ")
			var l := UI.label(msg + Missions.star_text(n_stars) + "  " + Knowledge.text(_question, "cim"), 17, UI.GREEN, true)
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			l.tooltip_text = star_rule()
			_body.add_child(l)
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
	t += Knowledge.lang_note(url if url != "" else "en")
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
