extends RefCounted
## Küldetések: rövid cél, egyértelmű feltétel, 1–3 csillag, egy mondatos tanulság.
## A feltételt a játék a modell eredményéből számolja (osszegzes.kozep), nem az AI.
## A küldetések célja a tanulás: mi hűt és mi nem, mennyit számít az idő,
## és mennyit ér a saját, ellenőrzött kutatásod.

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")

## csillag: [[mutató, határ], ...] – a mutató (T2100 / csucs) legyen a határ alatt.
## co2_ev: ebben a küldetésben rögzített év, amikorra nullára csökken a CO2-kibocsátás.
const LIST := [
	{"id": "alkalmazkodas", "cim": "Megmenti-e a Földet a szárazságtűrő növény?",
	 "cel": "Kutasd ki az aszálytűrő kukoricát, tedd a tervedbe, és futtasd a modellt.",
	 "tanulsag": "Az alkalmazkodás véd, de nem hűt: a termés javul, a hőmérséklet nem változik."},
	{"id": "hutes", "cim": "Mi hűti a bolygót?",
	 "cel": "Tartsd 2100-ra 2 °C alatt a melegedést.",
	 "csillag": [["T2100", 2.0], ["T2100", 1.7], ["T2100", 1.5]],
	 "tanulsag": "A legtöbbet az számít, mikorra lesz nulla a CO2-kibocsátás."},
	{"id": "keso", "cim": "Késői kezdés",
	 "cel": "A CO2 csak 2070-re lesz nulla. Tartsd a csúcsot 1,6 °C alatt.",
	 "co2_ev": 2070,
	 "csillag": [["csucs", 1.6], ["T2100", 1.55], ["T2100", 1.5]],
	 "tanulsag": "A metán és a CO2-kivonás segít, de csak részben pótolja az elvesztegetett éveket."},
	{"id": "masfel", "cim": "Másfél fok",
	 "cel": "A CO2 2060-ra lesz nulla. Vidd 2100-ra 1,45 °C alá. Lehet, hogy nem sikerül!",
	 "co2_ev": 2060,
	 "csillag": [["T2100", 1.45], ["T2100", 1.4], ["T2100", 1.35]],
	 "tanulsag": "Minél később kezdünk, annál több CO2-t kell kivonni, és ennek a kutatás szab határt."},
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


static func first_open() -> int:
	for i in LIST.size():
		if stars_of(LIST[i]["id"]) == 0:
			return i
	return 0


static func star_text(n: int, of: int = 3) -> String:
	return "★".repeat(n) + "☆".repeat(maxi(0, of - n))


## Értékelés a modell eredménye alapján: {"csillag": n, "szoveg": rövid visszajelzés}.
static func evaluate(m: Dictionary, res: Dictionary) -> Dictionary:
	var k: Dictionary = res["osszegzes"]["kozep"]
	var plan: Dictionary = res.get("_terv", {})
	if m["id"] == "alkalmazkodas":
		if float(plan.get("alkalmazkodas_hozam_kompenzacio_pct", 0.0)) <= 0.0:
			return {"csillag": 0, "szoveg": L.t("Még nincs aszálytűrő kukorica a tervedben. Kutasd ki előbb!")}
		var b: Dictionary = res["alapeset_osszegzes"]["kozep"]
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
