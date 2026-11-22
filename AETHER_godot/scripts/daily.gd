extends RefCounted
## „A mai nap”: a friss, VALÓDI jelentések közül naponta egy lesz a napi kérdés alapja.
## Az esemény valódi (dátum, hely, forrás a listában); a hozzá rendelt kutatási kérdés és a
## napi csillag játékszabály. Egy nap egy kérdés: a dátumból jön, tehát aznap nem változik.

const L := preload("res://scripts/i18n.gd")
const Knowledge := preload("res://scripts/knowledge.gd")

## eseményfajta -> kutatási témák (elöl a korai korszak témái)
const CAT_TOPICS := {
	"aszaly": ["kukorica", "aszaly", "termes", "ontozes", "talaj"],
	"ehezes": ["termes", "kukorica", "pazarlas", "etrend"],
	"arviz": ["felhoszakadas", "korai_riasztas", "vizes_part", "megemelt_haz"],
	"vihar": ["ocean_ho", "korai_riasztas", "gatak", "mangrove"],
	"tuz": ["erdotuz", "muhold_erdo", "erdo"],
	"jeg": ["gronland", "antarktisz", "gleccser", "tengerszint"],
	"hoseg": ["hoseg_halal", "munkakepesseg", "hoseg_riasztas", "varosi_fak", "feher_teto", "zoldteto"],
	"tenger": ["tengerszint", "ocean_ho", "korall", "gatak"],
	"szennyezes": ["legszennyezes", "villanyauto", "kerekpar"],
	"levego": ["legszennyezes", "villanyauto", "kerekpar"],
	"uv": ["ozon"],
}


static func today() -> String:
	return Time.get_date_string_from_system()


static func state() -> Dictionary:
	var s: Variant = L.get_setting("napi", {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


static func stars() -> int:
	return int(L.get_setting("napi_csillag", 0))


## A mai kérdés: {"esemeny": {...}, "tema": {...}, "kesz": bool} vagy üres, ha ma nincs
## olyan valódi jelentés, amelyhez elérhető, még nem kutatott téma tartozik.
static func pick(events: Array, campaign) -> Dictionary:
	var st := state()
	var day := today()
	if str(st.get("datum", "")) == day:
		var q: Dictionary = Knowledge.topic(str(st.get("tema", "")))
		if not q.is_empty():
			return {"esemeny": st.get("esemeny", {}), "tema": q, "kesz": bool(st.get("kesz", false))}
	if events.is_empty():
		return {}
	var start: int = abs(hash(day)) % events.size()
	for k in events.size():
		var e: Dictionary = events[(start + k) % events.size()]
		for id in CAT_TOPICS.get(str(e.get("kategoria", "")), []):
			var q2: Dictionary = Knowledge.topic(str(id))
			if q2.is_empty() or int(q2["korszak"]) > campaign.era or id in campaign.done:
				continue
			var keep := {}
			for key in ["cim", "cim_en", "kategoria", "orszag", "orszag_en", "hely", "datum", "link", "forras", "lat", "lon"]:
				if e.has(key):
					keep[key] = e[key]
			L.set_setting("napi", {"datum": day, "tema": id, "esemeny": keep, "kesz": false})
			return {"esemeny": keep, "tema": q2, "kesz": false}
	return {}


## Ha a mai téma közben kutatott lett, jár a napi csillag. Igaz, ha most lett kész.
static func check(campaign) -> bool:
	var st := state()
	if str(st.get("datum", "")) != today() or bool(st.get("kesz", false)):
		return false
	if not (str(st.get("tema", "")) in campaign.done):
		return false
	st["kesz"] = true
	L.set_setting("napi", st)
	L.set_setting("napi_csillag", stars() + 1)
	return true
