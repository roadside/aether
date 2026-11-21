extends RefCounted
## Tudásfa és korszakok (játékszabály, nem valós adat).
## A csomópontok valódi kutatási TÉMÁK, nem kitalált technológiák. Egy téma akkor
## „kutatott”, ha a kutatás legalább egy ellenőrzött számot talált róla (a szám a
## cikkekből jön, nem a játéktervezőtől). A csillagok a talált tudás erejét mutatják.
## A korszakok a témák sorrendjét adják: előbb megérted a bajt, aztán mérsékled, aztán átalakítasz, végül helyreállítasz.

const L := preload("res://scripts/i18n.gd")

## A témák a katalógusban vannak (egyetlen forrás: AETHER_terv/prototipus/tools/temak.py,
## onnan generálva). Mezők: id, korszak, terulet, cim/cim_en, magyarazat/magyarazat_en,
## kereses, parameterek, wiki, wiki_en, attekintes, nyit/nyit_en.
const CATALOG := "res://assets/temak_katalogus.json"

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
static var _fields: Dictionary = {}


static func _load() -> void:
	if not _topics.is_empty():
		return
	var f := FileAccess.open(CATALOG, FileAccess.READ)
	if f == null:
		push_error("Hiányzik a témakatalógus: " + CATALOG)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		push_error("Hibás témakatalógus: " + CATALOG)
		return
	_topics = d.get("temak", [])
	_fields = d.get("terulet", {})


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
	_load()
	var f: Variant = _fields.get(code, {})
	if typeof(f) != TYPE_DICTIONARY or (f as Dictionary).is_empty():
		return code
	return L.field(f, "nev")


## A területek a katalógus sorrendjében.
static func field_codes() -> Array:
	_load()
	return _fields.keys()


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
