extends RefCounted
## Klímacsúcs (JÁTÉKSZABÁLY): ötévente a világ vezetői összegyűlnek, és egy vállalást kérnek a
## játékostól: vezessen be tervet, hozza előre a CO2-nulla évét, csökkentse jobban a metánt, vagy
## adjon pénzt a szegényebb országok védelmére. A vállalás teljesítése pénzt és bizalmat hoz,
## az elmulasztása bizalmat visz. Ez nem valódi adat: a késői évtizedekre ad célt és döntést.
##
## Az állapot a campaign.pledges szótárában van (mentési kulcs: "vallalasok"):
##   {"2030": {"fajta": "co2", "cel": 2045, "hatarido": 2032, "allapot": "vallalt"|"elutasitva"|"teljesitve"|"elmulasztva"}}
## Ha a campaign-nek még nincs ilyen mezője, a modul a campaign metaadatában tartja (nem mentődik).

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")

const FIRST := 2030
const EVERY := 5
const LAST := 2095
const DEADLINE := 2             # a vállalást ennyi év alatt kell teljesíteni (a csúcs évével együtt +2)
const NEVER := 2105             # a terv-ablak „Soha” állása a CO2-nullánál
const CO2_STEP := 5             # ennyivel kell előrébb hozni a CO2-nulla évét
const CO2_MIN := 2035
const CH4_STEP := 10            # ennyi százalékponttal több metáncsökkentés
const CH4_MAX := 45
const WIN_MONEY := 60
const WIN_TRUST := 6
const FAIL_TRUST := 10
const DECLINE_TRUST := 4
const FUND_SHARE := 0.3         # a klímaalapba a pénzed ennyi része megy
const FUND_MIN := 60
const FUND_TRUST := 8

## A csúcs évei: 2030, 2035, …, 2095.
static func is_summit_year(y: int) -> bool:
	return y >= FIRST and y <= LAST and (y - FIRST) % EVERY == 0


static func _store(campaign) -> Dictionary:
	if "pledges" in campaign:
		return campaign.pledges
	if not campaign.has_meta("pledges"):
		campaign.set_meta("pledges", {})
	return campaign.get_meta("pledges")


static func _plan(campaign) -> Dictionary:
	return {} if campaign.timeline.is_empty() else Dictionary(campaign.timeline[-1]["terv"])


## A legkorábbi CO2-nulla év, amit a terv-ablak a határidőig enged (legalább 5 évvel a bevezetés után).
static func _co2_floor(deadline: int) -> int:
	return maxi(CO2_MIN, int(ceil((deadline + 5) / 5.0)) * 5)


## Az adott év csúcsa (ha van, és még nem volt), különben üres. Tiszta függvény.
static func pick(campaign, y: int) -> Dictionary:
	if not is_summit_year(y) or _store(campaign).has(str(y)):
		return {}
	var d := {"ev": y, "hatarido": y + DEADLINE}
	var cur := _plan(campaign)
	if cur.is_empty():
		d["fajta"] = "terv"
		return d
	var co2 := int(cur.get("co2_cel_ev", NEVER))
	var ch4 := int(float(cur.get("metan_csokkentes_pct", 0.0)))
	var co2_target := maxi(_co2_floor(y + DEADLINE), co2 - CO2_STEP)
	var can_co2 := co2_target < co2
	var can_ch4: bool = int(campaign.era) >= 2 and ch4 < CH4_MAX
	# váltakozva kér: páros csúcson inkább CO2-t, páratlanon inkább metánt
	var odd := ((y - FIRST) / EVERY) % 2 == 1
	if can_co2 and (not odd or not can_ch4):
		d["fajta"] = "co2"
		d["cel"] = co2_target
		d["most"] = co2
	elif can_ch4:
		d["fajta"] = "metan"
		d["cel"] = mini(CH4_MAX, ch4 + CH4_STEP)
		d["most"] = ch4
	else:   # a terv már a legerősebb: pénzt kér a szegényebb országok védelmére
		d["fajta"] = "alap"
		d["penz"] = maxi(FUND_MIN, int(round(campaign.money * FUND_SHARE / 10.0)) * 10)
	return d


## A kérés egy mondatban.
static func ask_text(d: Dictionary) -> String:
	match str(d["fajta"]):
		"terv":
			return L.t("Vezess be egy tervet %d végéig.") % int(d["hatarido"])
		"co2":
			var now := L.t("soha") if int(d["most"]) >= NEVER else str(int(d["most"]))
			return L.t("Hozd előre, mikor lesz nulla a CO2-kibocsátás: legkésőbb %d (most: %s). Határidő: %d vége.") % [int(d["cel"]), now, int(d["hatarido"])]
		"metan":
			return L.t("Csökkentsd a metánt legalább %d%%-kal (most: %d%%). Határidő: %d vége.") % [int(d["cel"]), int(d["most"]), int(d["hatarido"])]
		"alap":
			return L.t("Adj %d pénzt a klímaalapba: ebből a szegényebb országok gátakat és korai riasztást építenek.") % int(d["penz"])
	return ""


## Teljesül-e most a vállalás (a jelenlegi terv alapján).
static func fulfilled(campaign, d: Dictionary) -> bool:
	var cur := _plan(campaign)
	match str(d["fajta"]):
		"terv":
			return not cur.is_empty()
		"co2":
			return not cur.is_empty() and int(cur.get("co2_cel_ev", NEVER)) <= int(d["cel"])
		"metan":
			return not cur.is_empty() and int(float(cur.get("metan_csokkentes_pct", 0.0))) >= int(d["cel"])
	return false


static func can_fund(campaign, d: Dictionary) -> bool:
	return campaign.money >= int(d.get("penz", 0))


## Vállalom. A klímaalap azonnal fizet és bizalmat hoz; a többi a határidőkor dől el.
static func accept(campaign, d: Dictionary) -> String:
	var rec := d.duplicate()
	if str(d["fajta"]) == "alap":
		if not can_fund(campaign, d):
			return L.t("Erre most nincs elég pénzed.")
		campaign.money -= int(d["penz"])
		campaign.trust = clampi(campaign.trust + FUND_TRUST, 0, 100)
		rec["allapot"] = "teljesitve"
		_store(campaign)[str(d["ev"])] = rec
		_saved(campaign)
		return L.t("Befizetted: −%d pénz, +%d%% bizalom.") % [int(d["penz"]), FUND_TRUST]
	rec["allapot"] = "vallalt"
	_store(campaign)[str(d["ev"])] = rec
	_saved(campaign)
	if fulfilled(campaign, d):
		return L.t("A terved már most teljesíti. A jutalmat a határidőkor kapod meg.")
	return L.t("Vállaltad. Nyisd meg „A terved” ablakot, és állítsd be a határidőig!")


static func decline(campaign, d: Dictionary) -> String:
	var rec := d.duplicate()
	rec["allapot"] = "elutasitva"
	_store(campaign)[str(d["ev"])] = rec
	campaign.trust = clampi(campaign.trust - DECLINE_TRUST, 0, 100)
	_saved(campaign)
	return L.t("Nem vállaltad: −%d%% bizalom.") % DECLINE_TRUST


static func _saved(campaign) -> void:
	campaign.save()
	campaign.changed.emit()


## Az év elején (az új év y): a lejárt vállalások elszámolása. A mérleghez fűzhető szöveget ad vissza.
static func check(campaign, y: int) -> String:
	var notes: Array = []
	var st := _store(campaign)
	for k in st.keys():
		var rec: Dictionary = st[k]
		if str(rec.get("allapot", "")) != "vallalt" or y <= int(rec["hatarido"]):
			continue
		if fulfilled(campaign, rec):
			rec["allapot"] = "teljesitve"
			campaign.money += WIN_MONEY
			campaign.trust = clampi(campaign.trust + WIN_TRUST, 0, 100)
			notes.append(L.t("Teljesítetted a klímacsúcs (%d) vállalását: +%d pénz, +%d%% bizalom.") % [int(rec["ev"]), WIN_MONEY, WIN_TRUST])
		else:
			rec["allapot"] = "elmulasztva"
			campaign.trust = clampi(campaign.trust - FAIL_TRUST, 0, 100)
			notes.append(L.t("Nem teljesítetted a klímacsúcs (%d) vállalását: −%d%% bizalom.") % [int(rec["ev"]), FAIL_TRUST])
	if not notes.is_empty():
		_saved(campaign)
	return " ".join(notes)


## A futó vállalás egy sorban (a felső sávhoz vagy a terv-ablakhoz), vagy üres.
static func pending_text(campaign) -> String:
	for rec in _store(campaign).values():
		if str(rec.get("allapot", "")) == "vallalt":
			return L.t("Klímacsúcs-vállalás: ") + ask_text(rec)
	return ""


## A csúcs ablaka. on_close: bezárás; on_plan: „A terved” ablak megnyitása (vállalás után).
static func panel(campaign, d: Dictionary, on_close: Callable, on_plan: Callable = Callable()) -> Control:
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
	head.add_child(UI.heading(L.t("Klímacsúcs, %d") % int(d["ev"])))
	var tag := UI.label(L.t("játékszabály"), 13, UI.MUTE, false, false)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	tag.tooltip_text = L.t("Ötévente összeülnek a világ vezetői. A kérésük játékszabály, nem valódi esemény.")
	head.add_child(tag)
	v.add_child(head)
	v.add_child(UI.label(L.t("A világ vezetői összegyűltek, és ezt kérik tőled:"), 17, UI.SOFT))
	var c := UI.card(UI.GOLD)
	c.add_child(UI.label(ask_text(d), 22, UI.TEXT, true))
	if str(d["fajta"]) == "alap":
		c.add_child(UI.label(L.t("Ha vállalod: +%d%% bizalom, azonnal.") % FUND_TRUST, 17, UI.GREEN))
	else:
		c.add_child(UI.label(L.t("Ha teljesíted: +%d pénz, +%d%% bizalom. Ha vállalod, de nem teljesíted: −%d%% bizalom.") % [WIN_MONEY, WIN_TRUST, FAIL_TRUST], 17, UI.GREEN))
	v.add_child(UI.card_root(c))
	var box := UI.vbox(10)
	v.add_child(box)
	var row := UI.hbox(12)
	box.add_child(row)
	var yes := UI.button(L.t("Vállalom"), true)
	var no := UI.button(L.t("Nem vállalom (−%d%% bizalom)") % DECLINE_TRUST)
	if str(d["fajta"]) == "alap" and not can_fund(campaign, d):
		yes.disabled = true
		yes.tooltip_text = L.t("Erre most nincs elég pénzed.")
	row.add_child(yes)
	row.add_child(no)
	var finish := func(msg: String, accepted: bool) -> void:
		UI.clear(box)
		box.add_child(UI.label(msg, 19, UI.GREEN if accepted else UI.EMBER, true))
		var r2 := UI.hbox(12)
		var needs_plan: bool = accepted and str(d["fajta"]) != "alap" and not fulfilled(campaign, d)
		if needs_plan and on_plan.is_valid():
			var go := UI.button(L.t("A terved →"), true)
			go.pressed.connect(on_plan)
			r2.add_child(go)
		var ok := UI.button(L.t("Rendben"), not needs_plan)
		ok.pressed.connect(on_close)
		r2.add_child(ok)
		box.add_child(r2)
	yes.pressed.connect(func() -> void: finish.call(accept(campaign, d), true))
	no.pressed.connect(func() -> void: finish.call(decline(campaign, d), false))
	return p
