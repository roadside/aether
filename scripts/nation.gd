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


static func _statement(en: bool) -> String:
	return "\"statement\": \"<one short sentence in %s that a 13-year-old understands>\"}" % ("English" if en else "Hungarian")


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
	l.append("In these talks you have promised so far: %s." % _talks(g))
	l.append("YOUR PEOPLE")
	for r in d.get("kozvelemeny", []):
		l.append("- %s: %d%% supported stronger climate action by their country (UNDP Peoples' Climate Vote 2024)." % [str(r["orszag_en"]), int(r["ertek"])])
	l.append("- Worldwide, 89% demand more political action on climate (Andre et al. 2024, Nature Climate Change).")
	l.append("- Estimated share of your people who want stronger climate action now, in these talks: %d%%." % int(round(mood(w, g) * 100.0)))
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


static func prompt(w, g: Dictionary, target: int, cards: Array, en: bool) -> Array:
	var sys := _system(w, g, "{\"decision\": \"accept\" or \"later\" or \"refuse\", \"year\": <the year you accept, only with \"later\">, " + _statement(en))
	var l := _brief(w, g)
	l.append("THE REQUEST")
	l.append("The mediator asks you to promise zero emissions by %d. Evidence they showed you:" % target)
	for c in cards:
		l.append("- %s %s" % [Cards.text(str(c), "Kérdés", true), Cards.text(str(c), "Röviden", true)])
		for k in ["Mire jó?", "Mi a gond vele?"]:
			if Cards.text(str(c), k, true) != "":
				l.append("  %s" % Cards.text(str(c), k, true))
	var later := later_targets(w, g, target)
	if later.is_empty():
		l.append("You may accept or refuse.")
	else:
		l.append("You may accept, refuse, or accept a later year instead: %s." % ", ".join(later.map(func(t: int) -> String: return str(t))))
	return [{"role": "system", "content": sys}, {"role": "user", "content": "\n".join(l)}]


## A modell válaszából döntés: {"dontes": "accept"|"later"|"refuse", "cel": év, "szoveg": mondat}; üres, ha nem szabályos.
static func parse(w, g: Dictionary, target: int, content: String) -> Dictionary:
	var ans: Variant = JSON.parse_string(content)
	if typeof(ans) != TYPE_DICTIONARY:
		return {}
	var dec := str(ans.get("decision", "")).to_lower().strip_edges()
	if not (dec in ["accept", "later", "refuse"]):
		return {}
	var out := {"dontes": dec, "cel": target, "szoveg": str(ans.get("statement", "")).strip_edges().replace("\n", " ").left(160)}
	if dec == "later":
		var y := int(float(str(ans.get("year", "0")))) if str(ans.get("year", "")).is_valid_float() else 0
		if not (y in later_targets(w, g, target)):
			return {}
		out["cel"] = y
	return out


## Kör végi saját lépés: a vezetés maradhat, magától előbbre hozhatja a célját, vagy öt évvel elhalaszthatja.
static func prompt_round(w, g: Dictionary, en: bool) -> Array:
	var sys := _system(w, g, "{\"decision\": \"keep\" or \"earlier\" or \"delay\", " + _statement(en))
	var l := _brief(w, g)
	l.append("YOUR OWN MOVE")
	l.append("Five years are about to pass. Nobody is asking you anything now. You may:")
	l.append("- \"keep\": change nothing.")
	var ts: Array = w.targets_for(g)
	if not ts.is_empty():
		l.append("- \"earlier\": on your own, promise zero emissions by %d." % int(ts[0]))
	if int(g.get("cel", 0)) > 0 and int(g["cel"]) < 2090:
		l.append("- \"delay\": postpone your promise by five years, to %d." % mini(int(g["cel"]) + 5, 2090))
	return [{"role": "system", "content": sys}, {"role": "user", "content": "\n".join(l)}]


static func parse_round(content: String) -> Dictionary:
	var ans: Variant = JSON.parse_string(content)
	if typeof(ans) != TYPE_DICTIONARY:
		return {}
	var dec := str(ans.get("decision", "")).to_lower().strip_edges()
	if not (dec in ["keep", "earlier", "delay"]):
		return {}
	return {"dontes": dec, "szoveg": str(ans.get("statement", "")).strip_edges().replace("\n", " ").left(160)}
