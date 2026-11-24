extends RefCounted
## AI-országok: a csoportok vezetőit a játékos saját nyelvi modellje játssza.
## A modell csak a saját csoportja 2026-ig ismert, forrásolt adatait kapja meg (adatok/orszag_ugynokok.json és
## adatok/csoportok.json), a többiekről csak a vezetők nevét és a nyilvánosan vállalt klímacélt.
## Jövőképet, beállítottságot vagy személyiséget nem adunk meg neki.
## A közhangulat kezdőértéke valós felmérés (UNDP Peoples' Climate Vote 2024); a változás IRÁNYA szakirodalomból jön,
## a MÉRTÉKE játékszabály (lásd a README „Mi valódi, és mi játékszabály?” részét).
const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")

const EVIDENCE := 0.02      # bemutatott bizonyítékonként (Dechezleprêtre és mtsai 2025), legfeljebb 5 kártyáig
const DISASTER := 0.03      # friss szélsőséges időjárás, csak az utóbbi öt évben (Konisky és mtsai 2016)
const MYTH := -0.05         # terjedő tévhit: hamis jelzés a nyilvánosságban (Brulle és mtsai 2012: az elit és a média jelzései hatnak)
const THERMOSTAT := -0.02   # vállalt fokozatonként: aki már kapott erősebb klímavédelmet, kevésbé kér még többet (Wlezien 1995)

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = World.read_json("res://adatok/orszag_ugynokok.json")
		_data = d if typeof(d) == TYPE_DICTIONARY else {"csoportok": {}}
	return _data


static func dossier(id: String) -> Dictionary:
	return data().get("csoportok", {}).get(id, {})


## A valós felmérés szerinti kezdő arány (0–1): a csoportból megnevezett országok egyszerű átlaga.
static func base_mood(id: String) -> float:
	var rows: Array = dossier(id).get("kozvelemeny", [])
	if rows.is_empty():
		return 0.8          # a felmérés világátlaga (80%)
	var s := 0.0
	for r in rows:
		s += float(r["ertek"])
	return s / rows.size() / 100.0


## A közhangulat most: az emberek mekkora része kér erősebb klímavédelmet (0–1).
static func mood(w, g: Dictionary) -> float:
	var m := base_mood(str(g["id"]))
	m += EVIDENCE * minf((g.get("hasznalt", []) as Array).size(), 5.0)
	if int(g.get("cel", 0)) > 0:
		m += THERMOSTAT * int(g.get("fok", 1))
	if str(w.myth.get("csoport", "")) == str(g["id"]):
		m += MYTH
	var hit := false
	for e in w.naplo:
		if str(e.get("csoport", "")) != str(g["id"]) or int(e["ev"]) < w.year() - 5:
			continue
		if e["fajta"] == "baj":
			hit = true
	if hit:
		m += DISASTER
	return clampf(m, 0.05, 0.98)


## Későbbi évek, amelyeket a vezetés a kért helyett vállalhat.
static func later_targets(w, g: Dictionary, target: int) -> Array:
	var out: Array = []
	for t in w.targets_for(g):
		if int(t) > target:
			out.append(int(t))
	return out


static func _leaders(d: Dictionary) -> String:
	var out: Array = []
	for v in d.get("vezetok", []):
		out.append("%s (%s)" % [str(v["nev"]), str(v["tisztseg_en"])])
	return "; ".join(out)


static func _talks(g: Dictionary) -> String:
	return ("zero emissions by %d" % int(g["cel"])) if int(g.get("cel", 0)) > 0 else "nothing yet"


## A kérés a nyelvi modellnek (angolul, mert a modellek így értik a legjobban; a válaszmondat a játék nyelvén jön).
static func _system(w, g: Dictionary, reply: String) -> String:
	var nm := str(g.get("nev_en", g["nev"]))
	return "You speak for the leadership of %s in international climate talks. The year is %d. " % [nm, w.year()] \
		+ "Use only what is really known about them up to 2026: their history, culture, economy, political system and ideas, and the sourced facts below. " \
		+ "Anything after 2026 is what happened in these talks, as listed below. Do not invent facts. " \
		+ "You have no assigned attitude or vision of the future: decide as this leadership realistically would, weighing its real interests and the mood of its people. " \
		+ "Reply with JSON only: " + reply


const LETTERS := "ABCDEF"


## A válasz alakja. A vezetés a saját szavaival felel (a játék nyelvén); ezt a mondatot a játék nem javítja és nem lektorálja.
static func _reply(en: bool) -> String:
	return "{\"real_record\": \"<one English sentence: what your real leadership had decided on this question BEFORE 2026; not today's decision>\", " \
		+ "\"choice\": \"<the letter of one option>\", \"statement\": \"<what you say to the mediator, in your own words, in %s, one or two sentences>\"}. " % ("English" if en else "Hungarian") \
		+ "Your choice must fit your real record."


static func _menu(l: Array, opts: Array) -> void:
	l.append("YOUR OPTIONS")
	for i in opts.size():
		l.append("%s. %s" % [LETTERS[i], str(opts[i]["en"])])
	l.append("A promise made here is public, and you will be held to it.")


static func _pick(opts: Array, content: String) -> Dictionary:
	var ans: Variant = json(content)
	if typeof(ans) != TYPE_DICTIONARY:
		return {}
	var k := LETTERS.find(str(ans.get("choice", "")).strip_edges().to_upper().left(1))
	if k < 0 or k >= opts.size() or str(ans.get("choice", "")).strip_edges() == "":
		return {}
	var out: Dictionary = (opts[k] as Dictionary).duplicate()
	out.erase("en")
	out["szoveg"] = str(ans.get("statement", "")).strip_edges().replace("\n", " ").left(220)
	return out


## Az évszám viszonya a valós, nyilvános vállaláshoz: kódból számolt tény, hogy a modellnek ne kelljen évszámokat összevetnie.
static func _vs(g: Dictionary, year: int) -> String:
	var real := int(dossier(str(g["id"])).get("nyilvanos_cel_ev", 0))
	if real <= 0:
		return ""
	if year == real:
		return " This is the same year as your real pledge."
	return " This is %d years %s than your real pledge of %d, so it is a %s promise than the real one." % [absi(year - real), "later" if year > real else "earlier", real, "weaker" if year > real else "stronger"]


## A kérésre adható válaszok: a kért év, minden későbbi vállalható év, vagy semmi.
static func options(w, g: Dictionary, target: int) -> Array:
	var out: Array = [{"dontes": "accept", "cel": target, "en": "Promise zero emissions by %d, as asked.%s" % [target, _vs(g, target)]}]
	for t in later_targets(w, g, target):
		out.append({"dontes": "later", "cel": int(t), "en": "Promise zero emissions by %d instead (later than asked).%s" % [int(t), _vs(g, int(t))]})
	out.append({"dontes": "refuse", "cel": target, "en": "Make no new promise now."})
	return out


## Kör végi saját lépés: marad, magától vállal egy vállalható évet (bármelyiket), vagy öt évvel elhalaszt.
static func round_options(w, g: Dictionary) -> Array:
	var out: Array = [{"dontes": "keep", "en": "Change nothing."}]
	var ts: Array = w.targets_for(g)
	for t in ts:
		out.append({"dontes": "earlier", "cel": int(t), "en": ("On your own, bring your promise forward to zero emissions by %d." if int(g.get("cel", 0)) > 0 else "On your own, promise zero emissions by %d.") % int(t) + _vs(g, int(t))})
	if int(g.get("cel", 0)) > 0 and int(g["cel"]) < 2090:
		out.append({"dontes": "delay", "en": "Postpone your promise by five years, to %d." % mini(int(g["cel"]) + 5, 2090)})
	return out


## Amit a vezetés magáról, a népéről és a többiekről tud.
static func _brief(w, g: Dictionary) -> Array:
	var id := str(g["id"])
	var d := dossier(id)
	var nm := str(g.get("nev_en", g["nev"]))
	var l: Array = ["WHO YOU ARE", str(d.get("berendezkedes_en", nm)), "Leaders: " + _leaders(d), "SOURCED FACTS ABOUT YOU"]
	for f in g.get("tenyek", []):
		l.append("- %s (%s)" % [str(f.get("szoveg_en", f["szoveg"])), str(f.get("forras_en", f["forras"]))])
	for m in d.get("mutatok", []):
		var row := "- %s: GDP per person about %d US dollars (World Bank, 2025); oil and gas rents %s%% of GDP (World Bank, 2021); %s%% of electricity from fossil fuels (Ember, 2026)" % [str(m["orszag_en"]), int(m["gdp_fo_usd"]), str(m["olaj_gaz_jaradek"]), str(m["fosszilis_aram"])]
		if m.get("valasztasi_demokracia") != null:
			row += "; electoral democracy index %s on a scale from 0 to 1 (V-Dem, 2025)" % str(m["valasztasi_demokracia"])
		l.append(row)
	for f in d.get("tovabbi_tenyek", []):
		l.append("- %s (%s)" % [str(f["szoveg_en"]), str(f["link"])])
	l.append("Your real public climate pledge as of 2026: %s." % str(d.get("nyilvanos_cel_en", "none")))
	l.append("In these talks every party starts with no promise on the table. You have promised here so far: %s." % _talks(g))
	l.append("A promise here that is not earlier than your real public pledge is consistent with your real record. A promise here with a later year than your real public pledge is weaker than what you have really pledged.")
	l.append("YOUR PEOPLE")
	for r in d.get("kozvelemeny", []):
		l.append("- %s: %d%% supported stronger climate action by their country (UNDP Peoples' Climate Vote 2024)." % [str(r["orszag_en"]), int(r["ertek"])])
	l.append("- Worldwide, 89% demand more political action on climate (Andre et al. 2024, Nature Climate Change).")
	l.append("- Estimated share of your people who want stronger climate action now, in these talks: %d%%." % int(round(mood(w, g) * 100.0)))
	l.append("WHAT RESEARCH SAYS ABOUT LEADERS AND PUBLIC OPINION (general findings, not instructions)")
	for r in data().get("vezetoi_irodalom", {}).get("tetelek", []):
		l.append("- %s (%s)" % [str(r["allitas_en"]), str(r["link"])])
	var ev: Array = []
	for e in w.naplo:
		if str(e.get("csoport", "")) == id and e["fajta"] == "baj":
			ev.append("- %d: a weather disaster hit your people." % int(e["ev"]))
	if str(w.myth.get("csoport", "")) == id:
		ev.append("- Now: a false claim about climate is spreading among your people.")
	if not ev.is_empty():
		l.append("EVENTS AT HOME SINCE 2026")
		l.append_array(ev)
	l.append("WHAT YOU KNOW ABOUT THE OTHERS (public knowledge only)")
	for o in w.groups:
		if str(o["id"]) == id:
			continue
		var od := dossier(str(o["id"]))
		l.append("- %s. Leaders: %s. Real public pledge (2026): %s. Promised in these talks: %s." % [str(o.get("nev_en", o["nev"])), _leaders(od), str(od.get("nyilvanos_cel_en", "none")), _talks(o)])
	return l


static func prompt(w, g: Dictionary, target: int, cards: Array, en: bool = true) -> Array:
	var l := _brief(w, g)
	l.append("THE REQUEST")
	l.append("The mediator asks you to promise zero emissions by %d. Evidence they showed you:" % target)
	_evidence(l, cards)
	_menu(l, options(w, g, target))
	return [{"role": "system", "content": _system(w, g, _reply(en))}, {"role": "user", "content": "\n".join(l)}]


static func _evidence(l: Array, cards: Array) -> void:
	for c in cards:
		l.append("- %s %s" % [Cards.text(str(c), "Kérdés", true), Cards.text(str(c), "Röviden", true)])
		for k in ["Mire jó?", "Mi a gond vele?"]:
			if Cards.text(str(c), k, true) != "":
				l.append("  %s" % Cards.text(str(c), k, true))


## Metánvállalás: a vezetés elfogadja vagy nem. A valós helyzet a csoportok adatfájljából jön (Global Methane Pledge résztvevői).
static func methane_options() -> Array:
	return [{"dontes": "accept", "cel": 0, "en": "Promise to cut your methane emissions by 30%."},
		{"dontes": "refuse", "cel": 0, "en": "Make no methane promise now."}]


static func methane_record(g: Dictionary) -> String:
	var src := " (globalmethanepledge.org, participants checked on 2026-11-23)"
	match str(g["id"]):
		"afrika": return "Africa has no single position on the Global Methane Pledge; Nigeria has joined it" + src + "."
		"olaj": return "Russia has not joined the Global Methane Pledge" + src + "."
	return "As of 2026 you %s the Global Methane Pledge%s." % ["have joined" if bool(g.get("metan_valodi", true)) else "have not joined", src]


static func prompt_methane(w, g: Dictionary, cards: Array, en: bool = true) -> Array:
	var l := _brief(w, g)
	l.append("THE REQUEST")
	l.append("The mediator asks you to promise a 30% cut in your methane emissions. This comes in addition to any promise about zero emissions, not instead of it. " + methane_record(g) + " Evidence they showed you:")
	_evidence(l, cards)
	_menu(l, methane_options())
	return [{"role": "system", "content": _system(w, g, _reply(en))}, {"role": "user", "content": "\n".join(l)}]


static func parse_methane(content: String) -> Dictionary:
	return _pick(methane_options(), content)


## JSON olvasása hibaüzenet nélkül (a nyelvi modell válasza gyakran nem szabályos JSON; ez nem a játék hibája).
static func json(content: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(content) == OK else null


## A modell válaszából döntés: {"dontes": "accept"|"later"|"refuse", "cel": év, "szoveg": a vezetés saját mondata}; üres, ha nem szabályos.
static func parse(w, g: Dictionary, target: int, content: String) -> Dictionary:
	return _pick(options(w, g, target), content)


## Klímacsúcs: aki már vállalt célt, és a kártya az ő aggodalmára felel, maga dönt, előbbre hozza-e öt évvel.
static func summit_options(g: Dictionary) -> Array:
	var now := int(g["cel"])
	return [{"dontes": "accept", "cel": now - 5, "en": "Bring your promise forward by five years, to zero emissions by %d.%s" % [now - 5, _vs(g, now - 5)]},
		{"dontes": "keep", "cel": now, "en": "Keep your promise as it is, at %d." % now}]


static func prompt_summit(w, g: Dictionary, card: String, en: bool = true) -> Array:
	var l := _brief(w, g)
	l.append("THE CLIMATE SUMMIT")
	l.append("At a world climate summit the mediator showed this evidence to every party at once, and asks those who have already promised to bring their promise forward by five years:")
	_evidence(l, [card])
	_menu(l, summit_options(g))
	return [{"role": "system", "content": _system(w, g, _reply(en))}, {"role": "user", "content": "\n".join(l)}]


static func parse_summit(g: Dictionary, content: String) -> Dictionary:
	return _pick(summit_options(g), content)


## Megingás: az elbizonytalanodott vezetés maga dönt, kitart-e, vagy tíz évvel későbbre tolja a célját (a játékszabály szerinti visszalépés).
static func waver_options(g: Dictionary) -> Array:
	var now := int(g["cel"])
	var later := mini(now + 10, maxi(now, 2090))
	return [{"dontes": "hold", "cel": now, "en": "Stand by your promise of zero emissions by %d." % now},
		{"dontes": "delay", "cel": later, "en": "Push your promise back to %d.%s" % [later, _vs(g, later)]}]


static func prompt_waver(w, g: Dictionary, en: bool = true) -> Array:
	var l := _brief(w, g)
	l.append("DOUBTS AT HOME")
	l.append("In the last five years doubts about your promise have grown at home, and the mediator has not come back to you with new evidence. Five years are about to pass.")
	_menu(l, waver_options(g))
	return [{"role": "system", "content": _system(w, g, _reply(en))}, {"role": "user", "content": "\n".join(l)}]


static func parse_waver(g: Dictionary, content: String) -> Dictionary:
	return _pick(waver_options(g), content)


static func prompt_round(w, g: Dictionary, en: bool = true) -> Array:
	var l := _brief(w, g)
	l.append("YOUR OWN MOVE")
	l.append("Five years are about to pass. Nobody is asking you anything now.")
	_menu(l, round_options(w, g))
	return [{"role": "system", "content": _system(w, g, _reply(en))}, {"role": "user", "content": "\n".join(l)}]


static func parse_round(w, g: Dictionary, content: String) -> Dictionary:
	return _pick(round_options(w, g), content)
