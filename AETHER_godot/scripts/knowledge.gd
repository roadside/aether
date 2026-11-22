extends RefCounted
## Tudásfa és korszakok (játékszabály, nem valós adat).
## A csomópontok valódi kutatási TÉMÁK, nem kitalált technológiák. Egy téma akkor
## „kutatott”, ha a kutatás legalább egy ellenőrzött számot talált róla (a szám a
## cikkekből jön, nem a játéktervezőtől). A csillagok a talált tudás erejét mutatják.
## A korszakok a témák sorrendjét adják: előbb megérted a bajt, aztán mérsékled, aztán átalakítasz, végül helyreállítasz.

const L := preload("res://scripts/i18n.gd")

## A témák a lektorálható szövegfájlokban vannak: res://temak/<terület>.txt (egyetlen forrás;
## formátum: AETHER_terv/prototipus/aether_lab/temak_txt.py). Mezők: id, korszak, terulet,
## cim, magyarazat, nyit, mire_jo, hatranyok, mennyire_bizonyitott (és _en párjuk), forras
## (lista), lektoralva, kereses, parameterek, wiki, wiki_en, attekintes.
const TOPIC_DIR := "res://temak"
const FIELDS := {
	"fizika": ["Fizika", "Physics"], "kemia": ["Kémia", "Chemistry"], "anyag": ["Anyagtudomány", "Materials science"],
	"ur": ["Csillagászat és űrkutatás", "Astronomy and space"], "fold": ["Földtudomány", "Earth science"],
	"biologia": ["Biológia", "Biology"], "energia": ["Energia", "Energy"],
	"mernok": ["Közlekedés és épületek", "Transport and buildings"],
	"mezogazdasag": ["Mezőgazdaság és élelem", "Farming and food"],
	"egeszseg": ["Egészség és alkalmazkodás", "Health and adaptation"],
}
## Mezőnév a fájlban -> kulcs (a hosszabb név előbb, pl. "Kérdés angolul" a "Kérdés" előtt).
const LABELS := [
	["Mennyire bizonyított? angolul", "mennyire_bizonyitott_en"], ["Áttekintő cikkek keresése", "attekintes"],
	["Mi a gond vele? angolul", "hatranyok_en"], ["Ad a játékban angolul", "nyit_en"],
	["Ha kikutatod angolul", "nyit_en"],
	["Mennyire bizonyított?", "mennyire_bizonyitott"], ["Wikipédia angolul", "wiki_en"],
	["Mire jó? angolul", "mire_jo_en"], ["Röviden angolul", "magyarazat_en"], ["Kérdés angolul", "cim_en"],
	["Mi a gond vele?", "hatranyok"], ["Ad a játékban", "nyit"], ["Ha kikutatod", "nyit"], ["Lektorálva", "lektoralva"],
	["Wikipédia", "wiki"], ["Paraméter", "parameterek"], ["Mire jó?", "mire_jo"], ["Keresés", "kereses"],
	["Korszak", "korszak"], ["Röviden", "magyarazat"], ["Kérdés", "cim"], ["Forrás", "forras"],
]

## A korszakok. "kell": ennyi kutatott téma kell az ELŐZŐ korszakból a belépéshez.
## A további feltételeket (bevezetett terv, bizalom, csökkenő kibocsátás) a campaign.gd nézi.
const ERAS := [
	{"nev": "Felismerés", "tema": "Mérés és megértés: a melegedés, a jég, a tenger, az élővilág és a termés."},
	{"nev": "Mérséklés", "tema": "Takarékosság, metán, alkalmazkodás. Megnyílik a metán a tervedben.", "kell": 2},
	{"nev": "Átalakulás", "tema": "Új energia, új anyagok, és a CO2 kivonása a levegőből.", "kell": 2,
	 "terv": true, "bizalom": 50},
	{"nev": "Helyreállítás", "tema": "Erdők, vizek, talaj, és a legkockázatosabb ötletek megértése.", "kell": 2,
	 "csokkeno_co2": true},
]
const ROMAN := ["I.", "II.", "III.", "IV."]

static var _topics: Array = []


static func _load() -> void:
	if not _topics.is_empty():
		return
	for code in FIELDS:
		var path: String = TOPIC_DIR.path_join(code + ".txt")
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_error("Hiányzik a témafájl: " + path)
			continue
		_topics.append_array(parse(f.get_as_text(), code))


## Egy témafájl beolvasása (ugyanaz a szabály, mint a Python temak_txt.parse).
static func parse(text: String, code: String) -> Array:
	var out: Array = []
	var cur: Dictionary = {}
	var last := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges().trim_prefix("\ufeff")
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("===") and line.ends_with("===") and line.length() > 6:
			cur = {"id": line.trim_prefix("===").trim_suffix("===").strip_edges(), "terulet": code, "forras": []}
			for pair in LABELS:
				if pair[1] != "forras":
					cur[pair[1]] = ""
			out.append(cur)
			last = ""
			continue
		if cur.is_empty() or line.begins_with("---"):
			continue
		var hit := false
		for pair in LABELS:
			if line.begins_with(str(pair[0]) + ":"):
				var val := line.substr(str(pair[0]).length() + 1).strip_edges()
				last = str(pair[1])
				if last == "forras":
					if val != "":
						(cur["forras"] as Array).append(val)
				else:
					cur[last] = val
				hit = true
				break
		if not hit and last != "":   # folytatósor
			if last == "forras":
				var fs: Array = cur["forras"]
				if not fs.is_empty():
					fs[fs.size() - 1] = str(fs[fs.size() - 1]) + " " + line
			else:
				cur[last] = (str(cur[last]) + " " + line).strip_edges()
	for t in out:
		var e := str(t["korszak"]).get_slice(" ", 0).trim_suffix(".").to_upper()
		var idx := ["I", "II", "III", "IV"].find(e)
		t["korszak"] = idx + 1 if idx >= 0 else int(e)
		t["lektoralva"] = str(t["lektoralva"]).to_lower() in ["igen", "i", "yes", "x"]
	return out


static func topics() -> Array:
	_load()
	return _topics


static func topic(id: String) -> Dictionary:
	for t in topics():
		if t["id"] == id:
			return t
	return {}


static func topics_of(era: int) -> Array:
	return topics().filter(func(t: Dictionary) -> bool: return int(t["korszak"]) == era)


static func count_done(done: Array, era: int) -> int:
	var n := 0
	for t in topics_of(era):
		if t["id"] in done:
			n += 1
	return n


static func era_name(era: int) -> String:
	return ROMAN[era - 1] + " " + L.t(ERAS[era - 1]["nev"])


## A téma egy szövegmezője a választott nyelven ("cim" -> "cim_en" angolul).
static func text(q: Dictionary, key: String) -> String:
	if L.is_en() and str(q.get(key + "_en", "")) != "":
		return str(q[key + "_en"])
	return L.t(str(q.get(key, "")))


## A tudományterület neve (pl. "fizika" -> "Fizika").
static func field_name(code: String) -> String:
	if not FIELDS.has(code):
		return code
	return str(FIELDS[code][1 if L.is_en() else 0])


## A területek a megjelenítés sorrendjében.
static func field_codes() -> Array:
	return FIELDS.keys()


## Van-e kész (beépített) magyarázat a választott nyelven.
static func has_explanation(q: Dictionary) -> bool:
	return text_raw(q, "mire_jo") != ""


## Mint a text(), de fordítás nélkül, és angolul nincs visszaesés a magyarra.
static func text_raw(q: Dictionary, key: String) -> String:
	return str(q.get(key + "_en" if L.is_en() else key, ""))


## A források: [{"cim": ..., "link": ...}] ("Cím (2024) – https://..." sorokból).
static func sources(q: Dictionary) -> Array:
	var out: Array = []
	for s in q.get("forras", []):
		var line := str(s)
		var at := line.find("http")
		if at < 0:
			out.append({"cim": line, "link": ""})
		else:
			out.append({"cim": line.substr(0, at).strip_edges().trim_suffix("–").trim_suffix("-").strip_edges(),
				"link": line.substr(at).get_slice(" ", 0)})
	return out


## Csillagok egy kutatás eredményéből (játékszabály):
##   ★ legalább egy ellenőrzött szám; ★★ közepes bizonyosság (legalább 2 cikk egyezik);
##   ★★★ magas bizonyosság (legalább 3 cikk, köztük összefoglaló elemzés).
static func stars_for(props: Array) -> int:
	if props.is_empty():
		return 0
	var best := 1
	for j in props:
		var b := str(j.get("bizonyossag", ""))
		if b == "magas":
			return 3
		if b == "közepes":
			best = 2
	return best
