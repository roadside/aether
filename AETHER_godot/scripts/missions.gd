extends RefCounted
## Küldetések: rövid cél, egyértelmű feltétel, 1–3 csillag, egy mondatos tanulság.
## A feltételt a játék a modell eredményéből számolja (osszegzes.kozep), nem az AI.
## A küldetések célja a tanulás: mi hűt és mi nem, mennyit számít az idő,
## és mennyit ér a saját, ellenőrzött kutatásod.

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const Knowledge := preload("res://scripts/knowledge.gd")

## csillag: [[mutató, határ], ...] – a mutató (T2100 / csucs) legyen a határ alatt.
## co2_ev: ebben a küldetésben rögzített év, amikorra nullára csökken a CO2-kibocsátás.
const LIST := [
	{"id": "alkalmazkodas", "max": 1, "cim": "Megmenti-e a Földet a szárazságtűrő növény?",
	 "cel": "Kutasd ki az aszálytűrő kukoricát, tedd a tervedbe, és futtasd a modellt.",
	 "tanulsag": "Az alkalmazkodás véd, de nem hűt: a termés javul, a hőmérséklet nem változik."},
	{"id": "hutes", "cim": "Mi hűti a bolygót?",
	 "cel": "Tartsd 2100-ra 2 °C alatt a melegedést.",
	 "csillag": [["T2100", 2.0], ["T2100", 1.7], ["T2100", 1.5]],
	 "tanulsag": "A legtöbbet az számít, mikorra lesz nulla a CO2-kibocsátás."},
	{"id": "keso", "cim": "Késői kezdés",
	 "cel": "A CO2 csak 2070-re lesz nulla. Tartsd a csúcsot 1,6 °C alatt.",
	 "co2_ev": 2070, "korszak": 2,
	 "csillag": [["csucs", 1.6], ["T2100", 1.55], ["T2100", 1.5]],
	 "tanulsag": "A metán és a CO2-kivonás segít, de csak részben pótolja az elvesztegetett éveket."},
	{"id": "masfel", "cim": "Másfél fok",
	 "cel": "A CO2 2060-ra lesz nulla. Vidd 2100-ra 1,45 °C alá. Lehet, hogy nem sikerül!",
	 "co2_ev": 2060, "korszak": 3,
	 "csillag": [["T2100", 1.45], ["T2100", 1.4], ["T2100", 1.35]],
	 "tanulsag": "Minél később kezdünk, annál több CO2-t kell kivonni, és ennek a kutatás szab határt."},
	# --- az út küldetései: a játék saját állapotából számolva (kutatott témák, terv, krónika) ---
	{"id": "szenkeret", "ut": true, "korszak": 1, "ugras": "kutatas", "temak": ["tcre"],
	 "cim": "Mennyi CO2 jut még?",
	 "cel": "Kutasd ki, mennyi CO2-t bocsáthat még ki a világ 1,5 és 2 fokig.",
	 "tanulsag": "A melegedés a kibocsátott CO2 teljes mennyiségétől függ: amit egyszer kiengedtünk, az ott marad."},
	{"id": "jeg", "ut": true, "korszak": 1, "ugras": "kutatas",
	 "temak": ["gronland", "antarktisz", "gleccser", "tengerszint", "permafroszt"],
	 "cim": "Miért olvad a jég?",
	 "cel": "Kutass ki egy témát a jégről vagy a tengerszintről.",
	 "tanulsag": "A jég lassan reagál: amit ma teszünk, az évszázadokig hat a tengerszintre."},
	{"id": "nalunk", "ut": true, "korszak": 1, "ugras": "nalunk",
	 "cim": "Mit jelent ez nálunk?",
	 "cel": "Nyisd meg a „Nálunk” ablakot: hány kánikulás nap lesz 2100-ban a terved szerint?",
	 "tanulsag": "A globális fokok helyben napokban mérhetők: minden tized fok számít."},
	{"id": "metan", "ut": true, "korszak": 2, "ugras": "terv",
	 "cim": "Gyors győzelem",
	 "cel": "Csökkentsd a metánt legalább 30%-kal 2030-ig.",
	 "tanulsag": "A metán gyorsan hat: néhány évtized alatt lassítja a melegedést, de a CO2-t nem pótolja."},
	{"id": "hoseg", "ut": true, "korszak": 2, "ugras": "kutatas", "temak": ["varosi_fak", "hoseg_riasztas"],
	 "cim": "Hőhullám a városban",
	 "cel": "Kutasd ki a városi fákat vagy a hőségriasztást, hogy a hőhullám kisebb kárt okozzon.",
	 "tanulsag": "A hőség ellen helyben is lehet védekezni, de a melegedést ez nem állítja meg."},
	{"id": "part", "ut": true, "korszak": 3, "ugras": "kutatas", "temak": ["gatak", "vizes_part"],
	 "cim": "Gát vagy mocsár?",
	 "cel": "Kutasd ki a gátakat és a parti vizes élőhelyeket, és védd meg a partot egy dagály idején.",
	 "tanulsag": "A gát gyorsan véd, de drága; a mocsár lassabban, de magától is nő a tengerrel. A legjobb a kettő együtt."},
	{"id": "penz", "ut": true, "korszak": 3, "ugras": "terv",
	 "cim": "Ki fizeti?",
	 "cel": "Vezess be egy tervet úgy, hogy közben a bizalom ne essen 40% alá öt évig.",
	 "tanulsag": "A gyors változáshoz az emberek bizalma kell, és azt ellenőrzött tudással lehet megszerezni."},
	{"id": "csucsrol", "ut": true, "korszak": 4, "ugras": "terv",
	 "cim": "Vissza a csúcsról",
	 "cel": "Érd el, hogy 2100-ra a hőmérséklet alacsonyabb legyen, mint a csúcson volt.",
	 "tanulsag": "A hőmérséklet akkor csökken, ha a metánt is visszafogjuk, és több CO2-t vonunk ki, mint amennyit kibocsátunk."},
	{"id": "napfeny", "ut": true, "korszak": 4, "ugras": "kutatas", "max": 1,
	 "temak": ["napernyo", "felho_fenyesites", "cirrus", "urbeli_arnyekolo"],
	 "cim": "A kockázatos ötlet",
	 "cel": "Kutasd ki, mit tudunk a napfény visszaveréséről, és miért nem lehet bevezetni a játékban.",
	 "tanulsag": "Elfedheti a melegedést, de ha abbahagyják, a hő hirtelen visszatér: a CO2 csökkentését nem pótolja."},
	{"id": "atvetel", "ut": true, "korszak": 2, "ugras": "kutatas", "max": 1, "orok": true,
	 "cim": "Ellenőrizd egy társad kutatását",
	 "cel": "Vegyél át egy megosztott kutatást, és nézd meg, igazolódnak-e a számai.",
	 "tanulsag": "A tudományban az számít, amit más is meg tud ismételni."},
	{"id": "nehez", "ut": true, "korszak": 1, "vegig": true, "orok": true,
	 "cim": "Nehezebb Föld",
	 "cel": "Tartsd 2100-ra 2 °C alatt egy érzékenyebb Földön. Hogy milyen a Földed, a játék végén derül ki.",
	 "tanulsag": "Nem tudjuk pontosan, mennyire érzékeny a Föld: ezért érdemes biztonsággal tervezni."},
]

const NAMES := {"T2100": "2100-ban", "csucs": "a csúcs"}


static func _cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1)


static func stars_of(id: String) -> int:
	var d: Variant = L.get_setting("kuldetesek", {})
	return int(d.get(id, 0)) if typeof(d) == TYPE_DICTIONARY else 0


static func save_stars(id: String, n: int) -> void:
	var d: Variant = L.get_setting("kuldetesek", {})
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
	if n > int(d.get(id, 0)):
		d[id] = n
		L.set_setting("kuldetesek", d)


static func max_stars(m: Dictionary) -> int:
	return int(m.get("max", 3))


## Látszik-e a listában: a korszaka már megnyílt (vagy van rajta csillag). A „Nehezebb Föld”
## az első végigjátszott Föld után jelenik meg.
static func shown(m: Dictionary, campaign) -> bool:
	if stars_of(m["id"]) > 0 or campaign == null:
		return true
	if m.get("vegig", false):
		return int(campaign.games_played) > 0 or not campaign.results().is_empty()
	return int(campaign.era) >= int(m.get("korszak", 1))


static func first_open(campaign = null) -> int:
	for i in LIST.size():
		if stars_of(LIST[i]["id"]) == 0 and shown(LIST[i], campaign) and not LIST[i].get("vegig", false):
			return i
	return 0


## Új játék: a csillagok elölről, kivéve a játékokon átívelő küldetéseket.
static func reset_stars() -> void:
	var keep := {}
	for m in LIST:
		if m.get("orok", false) and stars_of(m["id"]) > 0:
			keep[m["id"]] = stars_of(m["id"])
	L.set_setting("kuldetesek", keep)
	L.set_setting("nalunk_latta", false)
	L.set_setting("nalunk_kulonbseg", 0.0)


static func _count(ids: Array, done: Array) -> int:
	var n := 0
	for id in ids:
		if done.has(id):
			n += 1
	return n


## A legjobb pajzs, amivel a krónika szerint egy ilyen esemény érte a játékost (−1: nem volt).
static func _best_shield(campaign, event_id: String) -> float:
	var best := -1.0
	for h in campaign.history:
		var p: Variant = h.get("pajzs", {})
		if typeof(p) == TYPE_DICTIONARY and p.has(event_id):
			best = maxf(best, float(p[event_id]))
	return best


## Volt-e a terv bevezetése óta öt egymást követő év, amikor a bizalom végig elérte a határt.
static func _trust_streak(campaign, limit: int) -> bool:
	if campaign.timeline.is_empty():
		return false
	var from := int(campaign.timeline[0]["ev"])
	var run := 0
	for h in campaign.history:
		if int(h.get("ev", 0)) >= from and int(h.get("bizalom", -1)) >= limit:
			run += 1
			if run >= 5:
				return true
		else:
			run = 0
	return false


## Az út küldetéseinek csillagai a játék mostani állapotából (0–3). Nem az AI dönti el.
static func journey_stars(m: Dictionary, campaign) -> int:
	var done: Array = campaign.done
	var n := _count(m.get("temak", []), done)
	var plan: Dictionary = {} if campaign.timeline.is_empty() else campaign.timeline[-1]["terv"]
	match str(m["id"]):
		"szenkeret":
			if not done.has("tcre"):
				return 0
			if Knowledge.count_done(done, 1) < 2:
				return 1
			return 3 if int(campaign.stars.get("tcre", 0)) >= 2 else 2
		"jeg":
			return mini(3, n)
		"nalunk":
			if not bool(L.get_setting("nalunk_latta", false)):
				return 0
			if plan.is_empty():
				return 1
			return 3 if float(L.get_setting("nalunk_kulonbseg", 0.0)) >= 10.0 else 2
		"metan":
			var p := float(plan.get("metan_csokkentes_pct", 0.0))
			return 3 if p >= 45.0 else (2 if p >= 40.0 else (1 if p >= 30.0 else 0))
		"hoseg":
			if n < 2:
				return n
			return 3 if _best_shield(campaign, "hoseg") > 0.0 else 2
		"part":
			if n < 2:
				return n
			return 3 if _best_shield(campaign, "dagaly") >= 0.5 else 2
		"penz":
			if plan.is_empty():
				return 0
			if not _trust_streak(campaign, 40):
				return 1
			return 3 if _trust_streak(campaign, 60) else 2
		"csucsrol":
			if plan.is_empty() or not campaign.model.has("osszegzes"):
				return 0
			var k: Dictionary = campaign.model["osszegzes"]["kozep"]
			var d := float(k.get("csucs", 0.0)) - float(k.get("T2100", 0.0))
			return 3 if d >= 0.3 else (2 if d >= 0.2 else (1 if d >= 0.1 else 0))
		"napfeny":
			return 1 if n > 0 else 0
		"atvetel":
			return 1 if int(L.get_setting("atvett_kutatas", 0)) > 0 else 0
	return stars_of(m["id"])


## A játék végén: az érzékenyebb Föld küldetése (a rejtett érzékenység csak ekkor derül ki).
static func finale_check(campaign) -> void:
	if float(campaign.sens) <= 0.33:
		return
	var t := float(campaign.real_t2100())
	save_stars("nehez", 3 if t < 1.6 else (2 if t < 1.8 else (1 if t < 2.0 else 0)))


## Végignézi az út küldetéseit; visszaadja azokat, amelyeken most lett több csillag.
static func check_journey(campaign) -> Array:
	var out: Array = []
	if campaign == null:
		return out
	for m in LIST:
		if not m.get("ut", false) or m.get("vegig", false):
			continue
		var n := journey_stars(m, campaign)
		if n > stars_of(m["id"]):
			save_stars(m["id"], n)
			out.append(m)
	return out


## Az út küldetésénél a következő kikutatandó téma azonosítója (vagy üres).
static func next_topic(m: Dictionary, campaign) -> String:
	for id in m.get("temak", []):
		if not campaign.done.has(id):
			return str(id)
	return ""


static func star_text(n: int, of: int = 3) -> String:
	return "★".repeat(n) + "☆".repeat(maxi(0, of - n))


## Értékelés a modell eredménye alapján: {"csillag": n, "szoveg": rövid visszajelzés}.
static func evaluate(m: Dictionary, res: Dictionary) -> Dictionary:
	if m.get("ut", false):      # az út küldetéseit nem a próbafuttatás, hanem a játék állapota dönti el
		return {"csillag": 0, "szoveg": ""}
	var k: Dictionary = res["osszegzes"]["kozep"]
	var plan: Dictionary = res.get("_terv", {})
	if m["id"] == "alkalmazkodas":
		if float(plan.get("alkalmazkodas_hozam_kompenzacio_pct", 0.0)) <= 0.0:
			return {"csillag": 0, "szoveg": L.t("Még nincs aszálytűrő kukorica a tervedben. Kutasd ki előbb!")}
		# összevetés ugyanazzal a tervvel, alkalmazkodás nélkül (nem az alapesettel)
		var b: Dictionary = res.get("alkalmazkodas_nelkul_osszegzes", res["alapeset_osszegzes"])["kozep"]
		var s := L.t("Kukoricatermés-változás 2050-ben: %s%% helyett %s%%. Hőmérséklet 2100-ban: +%s °C, ugyanannyi.") % [
			UI.hu(float(b["kukorica_hozam_2050_pct"]), 1), UI.hu(float(k["kukorica_hozam_2050_pct"]), 1), UI.hu(float(k["T2100"]), 1)]
		return {"csillag": 1, "szoveg": s}
	var n := 0
	for c in m["csillag"]:
		if float(k[c[0]]) < float(c[1]):
			n += 1
		else:
			break
	var first: Array = m["csillag"][0]
	var got := L.t("%s: +%s °C") % [_cap(L.t(NAMES[first[0]])), UI.hu(float(k[first[0]]), 2)]
	if n == 0:
		return {"csillag": 0, "szoveg": got + L.t(". Még nem sikerült, próbáld újra!")}
	var s2 := got + ". " + star_text(n)
	if n < 3:
		var nxt: Array = m["csillag"][n]
		s2 += L.t(" Következő csillag: %s +%s °C alatt.") % [L.t(NAMES[nxt[0]]), UI.hu(float(nxt[1]), 2)]
	return {"csillag": n, "szoveg": s2}
