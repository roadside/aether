extends RefCounted
## Éves események (JÁTÉKSZABÁLY, nem előrejelzés). Minden évben sorsolunk: hőhullám, aszály,
## áradás, erdőtűz, vihardagály. A melegebb Földön gyakoribbak (ez egyezik az IPCC AR6
## megállapításával: a hőség, a heves eső, az aszály és a tűzveszélyes idő a melegedéssel
## gyakoribbá válik; a parti elöntés a tengerszinttel nő). A kár mértéke és a pontos esély a
## játék szabálya. A kár ellen a kikutatott témák védenek: így kap értelmet minden tudományág.
## A sorsolás a játék magjából és az évből jön, tehát egy adott Földön mindig ugyanaz történik.

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const Knowledge := preload("res://scripts/knowledge.gd")

## esely: alap + no * (melegedés − 1,2 °C); a vihardagálynál a tengerszint (m) számít.
const DECK := [
	{"id": "hoseg", "cim": "Hőhullám", "szoveg": "Hetekig tartó forróság a városokban.",
	 "szin": "#ff8a3a", "alap": 0.05, "no": 0.11, "penz": 40, "bizalom": 2,
	 "ved": ["hoseg_riasztas", "varosi_fak", "feher_teto", "zoldteto", "hoseg_halal"]},
	{"id": "aszaly", "cim": "Aszály", "szoveg": "Kevés az eső, gyenge a termés.",
	 "szin": "#e0a24a", "alap": 0.045, "no": 0.09, "penz": 45, "bizalom": 2,
	 "ved": ["kukorica", "ontozes", "aszaly", "talaj", "agroerdeszet", "termes"]},
	{"id": "arviz", "cim": "Áradás", "szoveg": "Egy nap alatt egy hónapnyi eső esett.",
	 "szin": "#4aa0e0", "alap": 0.04, "no": 0.08, "penz": 45, "bizalom": 1,
	 "ved": ["felhoszakadas", "korai_riasztas", "vizes_part", "megemelt_haz", "zoldteto", "lap"]},
	{"id": "tuz", "cim": "Erdőtűz", "szoveg": "Száraz, szeles időben ég az erdő.",
	 "szin": "#ff5a3a", "alap": 0.035, "no": 0.08, "penz": 35, "bizalom": 1,
	 "ved": ["erdotuz", "muhold_erdo", "erdo", "amazonas"]},
	{"id": "dagaly", "cim": "Vihardagály", "szoveg": "A vihar a tengert a partra nyomta.",
	 "szin": "#3fa8d8", "alap": 0.015, "no": 0, "tenger": 0.25, "penz": 55, "bizalom": 2,
	 "ved": ["gatak", "vizes_part", "megemelt_haz", "tengerszint", "mangrove", "korai_riasztas", "tengerifu", "korall_ujra"]},
]
## Jó hírek (játékszabály): a tudás és a bizalom hozza őket.
## esely: alap + tema * (kutatott témák száma) + biz * (bizalom / 100)
const GOOD := [
	{"id": "attores", "cim": "Áttörés a laborban", "szoveg": "Egy kutatócsoport a te eredményeidre épített.",
	 "szin": "#5fe0c0", "alap": 0.0, "tema": 0.006, "biz": 0.0, "penz": 30, "bizalom": 2},
	{"id": "osszefogas", "cim": "Összefogás", "szoveg": "Több ország csatlakozott a tervedhez.",
	 "szin": "#8fd45a", "alap": 0.0, "tema": 0.0, "biz": 0.12, "penz": 20, "bizalom": 4, "terv": true},
]
const SHIELD := 0.25          # minden ismert védő téma ennyivel csökkenti a kárt
const SHIELD_MAX := 0.75


static func _rng(campaign, y: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(campaign.world_seed) * 1009 + y
	return rng


static func _sea(campaign, y: int) -> float:
	var v: float = campaign.sea_level(y)
	return 0.0 if is_nan(v) else v


## Az adott év eseményei (legfeljebb 2). Tiszta függvény: nem módosít semmit.
static func draw(campaign, y: int) -> Array:
	var out: Array = []
	var t: float = campaign.measured_temp(y)
	if is_nan(t) or campaign.world_seed == 0:
		return out
	var rng := _rng(campaign, y)
	for e in DECK:
		var p: float = float(e["alap"]) + float(e["no"]) * maxf(0.0, t - 1.2) + float(e.get("tenger", 0.0)) * _sea(campaign, y)
		var roll := rng.randf()
		if roll < minf(p, 0.6) and out.size() < 2:
			var known: Array = []
			for id in e["ved"]:
				if id in campaign.done:
					known.append(id)
			var shield := minf(SHIELD_MAX, SHIELD * known.size())
			var ev: Dictionary = e.duplicate()
			ev["ev"] = y
			ev["vedett"] = known
			ev["pajzs"] = shield
			ev["kar_penz"] = int(round(float(e["penz"]) * (1.0 - shield)))
			# aki felkészült (legalább két védő téma), annál nem vész el bizalom
			ev["kar_bizalom"] = 0 if shield >= 0.5 else int(e["bizalom"])
			out.append(ev)
	for e in GOOD:
		if e.get("terv", false) and campaign.timeline.is_empty():
			continue
		var pg: float = float(e["alap"]) + float(e["tema"]) * campaign.done.size() + float(e["biz"]) * campaign.trust / 100.0
		if rng.randf() < minf(pg, 0.25) and out.size() < 3:
			var gv: Dictionary = e.duplicate()
			gv["ev"] = y
			gv["jo"] = true
			out.append(gv)
			break
	return out


## Az események kára a játékra (pénz, bizalom), és bejegyzés a krónikába.
static func apply(campaign, events: Array) -> void:
	for ev in events:
		if ev.get("jo", false):
			campaign.money += int(ev["penz"])
			campaign.trust = clampi(campaign.trust + int(ev["bizalom"]), 0, 100)
			continue
		campaign.money = maxi(0, campaign.money - int(ev["kar_penz"]))
		campaign.trust = clampi(campaign.trust - int(ev["kar_bizalom"]), 0, 100)
	if not events.is_empty() and not campaign.history.is_empty():
		var ids: Array = []
		for ev in events:
			ids.append(ev["id"])
		campaign.history[-1]["esemenyek"] = ids
		var shields := {}       # a küldetésekhez: melyik eseményt mekkora védelemmel érte a játékos
		for ev in events:
			if ev.has("pajzs"):
				shields[ev["id"]] = float(ev["pajzs"])
		if not shields.is_empty():
			campaign.history[-1]["pajzs"] = shields
	if not events.is_empty():
		campaign.save()
		campaign.changed.emit()


static func _topic_names(ids: Array, limit: int = 3) -> String:
	var names: Array = []
	for id in ids:
		var q: Dictionary = Knowledge.topic(str(id))
		if not q.is_empty() and names.size() < limit:
			names.append(Knowledge.text(q, "cim"))
	return "\n".join(names.map(func(n): return "• " + str(n)))


## Az évzáró lap: mi történt idén, mennyi kár lett, és mi védett vagy védene.
static func panel(campaign, events: Array, on_research: Callable, on_ok: Callable) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.GOLD
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 28
	sb.set_content_margin_all(26)
	p.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(14)
	p.add_child(v)
	var head := UI.hbox(14)
	head.add_child(UI.heading(L.t("Ez történt %d-ben") % int(events[0]["ev"])))
	var tag := UI.label(L.t("játékesemény"), 13, UI.MUTE, false, false)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	tag.tooltip_text = L.t("Játékszabály: a játék sorsolja. A melegebb Földön az ilyen események gyakoribbak (IPCC AR6).")
	head.add_child(tag)
	v.add_child(head)
	for ev in events:
		var c := UI.card(Color(str(ev["szin"])))
		c.add_child(UI.label(L.t(ev["cim"]), 26, Color(str(ev["szin"])), true))
		c.add_child(UI.label(L.t(ev["szoveg"]), 18, UI.TEXT))
		if ev.get("jo", false):
			c.add_child(UI.label(L.t("Nyereség: +%d pénz, +%d bizalom") % [int(ev["penz"]), int(ev["bizalom"])], 18, UI.GREEN, true))
			v.add_child(UI.card_root(c))
			continue
		var loss := L.t("Kár: −%d pénz, −%d bizalom") % [int(ev["kar_penz"]), int(ev["kar_bizalom"])]
		c.add_child(UI.label(loss, 18, UI.EMBER, true))
		var known: Array = ev["vedett"]
		if not known.is_empty():
			c.add_child(UI.label(L.t("A tudásod megvédett: a kár %d%%-kal kisebb.") % int(round(float(ev["pajzs"]) * 100.0)), 17, UI.GREEN, true))
			c.add_child(UI.label(_topic_names(known), 15, UI.GREEN))
		var missing: Array = []
		for id in ev["ved"]:
			if not (id in campaign.done):
				missing.append(id)
		if not missing.is_empty() and float(ev["pajzs"]) < SHIELD_MAX:
			c.add_child(UI.label(L.t("Ez ellen véd, ha kikutatod:"), 15, UI.GOLD, true))
			c.add_child(UI.label(_topic_names(missing, 2), 15, UI.SOFT))
		v.add_child(UI.card_root(c))
	var row := UI.hbox(12)
	var ok := UI.button(L.t("Rendben"), true)
	ok.pressed.connect(on_ok)
	row.add_child(ok)
	var res := UI.button(L.t("Kutatás →"))
	res.pressed.connect(on_research)
	row.add_child(res)
	v.add_child(row)
	return p
