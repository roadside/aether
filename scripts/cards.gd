extends RefCounted
## Bizonyíték-kártyák: a lektorált kutatási témák (temak/*.txt). Minden kártya egy valódi kérdés,
## a magyarázata és a forrásai. A játék NEM talál ki számot: ami a kártyán áll, a fájlból jön.
## A „témakör” (melyik aggodalomra felel a kártya) a játék saját besorolása: játékszabály.

const FILES := ["anyag", "biologia", "egeszseg", "energia", "fizika", "fold", "kemia", "mernok", "mezogazdasag", "ur"]
## Témakörök: azonosító -> [név, szín]
const THEMES := {
	"aram": ["Áram", "#f4c85a"], "munka": ["Ipar és közlekedés", "#e0935a"], "elelem": ["Élelem", "#8fe388"],
	"part": ["Tenger és part", "#4aa0e0"], "egeszseg": ["Egészség", "#ff8fa8"], "ketseg": ["Honnan tudjuk?", "#b9a2ff"],
	"olaj": ["Olaj és gáz", "#c8b49a"], "erdo": ["Erdő és föld", "#5fbf7a"],
	"kockazat": ["Kockázatos ötletek", "#9fb0cf"],
}
## A „Kockázatos ötletek” kártyái tárgyalásra nem jók (egy csoport sem ettől tart): tudást adnak arról,
## miért nem megoldás a Föld mesterséges hűtése. Játékszabály.
const NO_TALK := ["kockazat"]
const TAGS := {
	"aram": ["napelem", "szelenergia", "tengeri_szel", "atomenergia", "vizi_tarolo", "litium_akku", "hotarolas", "geotermia", "led",
		"napkollektor", "perovszkit", "natrium_akku", "szilard_akku", "fuzio", "urbeli_napelem", "biogaz", "eromu_hoseg", "agrovoltaik", "nap_alulbecsles", "halozat_osszekotes", "akku_olcsobodas", "legkondi", "napelem_ujra", "hosszu_tarolas", "viztarozo_metan"],
	"munka": ["zold_acel", "cement", "ipari_hoszivattyu", "hidrogen", "gyari_co2", "akku_ujra", "muanyag", "fa_epulet", "zold_ammonia",
		"uzemanyagcella", "villanyauto", "teherauto", "hajozas", "vasut", "hoszivattyu", "hoszigeteles", "kerekpar", "tavmunka", "szintetikus_kerozin", "hulladek_metan", "hutokozeg", "n2o_ipar", "repules", "kritikus_asvanyok", "korforgasos", "kevesebb_igeny", "szennyviz_metan"],
	"elelem": ["termes", "kukorica", "ontozes", "etrend", "pazarlas", "mutragya", "agroerdeszet", "metan_rizs", "kerodzok_metan",
		"voros_alga", "tragya", "beporzok", "aszaly", "talaj", "termeloi_kulonbseg", "co2_tapanyag", "hal_fogas", "tehen_nemesites"],
	"part": ["tengerszint", "gronland", "antarktisz", "gatak", "vizes_part", "megemelt_haz", "mangrove", "korai_riasztas", "gleccser",
		"felhoszakadas", "korall", "korall_ujra", "tengerifu", "ocean_savasodas", "tengeri_hohullam", "viharar", "atollok", "sos_viz"],
	"egeszseg": ["hoseg_halal", "legszennyezes", "munkakepesseg", "varosi_fak", "hoseg_riasztas", "feher_teto", "zoldteto", "erdotuz", "dengue", "malaria_hegyvidek", "pollen", "alvas", "klimaszorongas", "vibrio", "terhesseg_hoseg", "lelki_egeszseg", "szalmonella"],
	"ketseg": ["tcre", "klimaerzekenyseg", "napaktivitas", "kozmikus", "felhok", "ocean_ho", "aeroszol", "amoc", "permafroszt", "ozon", "kondenzcsik", "konszenzus", "regi_modellek", "jegfurat", "attribucio", "sztratoszfera", "jegkorszak_ota"],
	"olaj": ["metan_gaz", "metan_szen", "co2_tarolas", "levegoszures", "metan_muhold", "mof",
		"metan_bontas", "novenyi_energia", "faklyazas", "foldben_marad", "elhagyott_kutak", "metan_szivargas", "olajallam_jovo", "elakadt_vagyon", "fosszilis_tamogatas", "olajmezo_kibocsatas", "energia_munkahely", "metan_vallalas", "bezart_banyak"],
	"erdo": ["erdo", "erdo_magatol", "muhold_erdo", "amazonas", "lap", "bioszen", "kozet", "moszaterdo", "erdoirtas_okai", "erdo_nyelo", "erdo_hutes", "erdo_eso", "import_erdoirtas", "oslakos_fold", "erdo_degradacio", "erdo_zavarok", "gyep_nem_erdo"],
	"kockazat": ["napernyo", "felho_fenyesites", "cirrus", "urbeli_arnyekolo", "vas_tenger", "ocean_lugositas"],
}
## A metánról szóló kártyák: a metánvállaláshoz ezek egyike kell.
const METHANE := ["metan_gaz", "metan_szen", "metan_rizs", "kerodzok_metan", "voros_alga", "tragya", "hulladek_metan", "metan_muhold", "biogaz", "metan_szivargas", "elhagyott_kutak", "metan_vallalas", "szennyviz_metan", "bezart_banyak", "tehen_nemesites", "viztarozo_metan"]

## A tárgyalásra is használható témakörök.
static func talk_themes() -> Array:
	return THEMES.keys().filter(func(th: String) -> bool: return not (th in NO_TALK))


static var _all: Dictionary = {}       # azonosító -> téma
static var _tag_of: Dictionary = {}


static func load_all() -> void:
	if not _all.is_empty():
		return
	for th in TAGS:
		for id in TAGS[th]:
			_tag_of[id] = th
	for f in FILES:
		var txt := FileAccess.get_file_as_string("res://temak/%s.txt" % f)
		var cur: Dictionary = {}
		var last := ""
		var tech := false
		for raw in txt.split("\n"):
			var line := raw.strip_edges()
			if line.begins_with("=== ") and line.ends_with(" ==="):
				cur = {"id": line.substr(4, line.length() - 8), "forrasok": [], "tudomany": f}
				_all[cur["id"]] = cur
				tech = false
				last = ""
				continue
			if cur.is_empty() or line == "" or line.begins_with("#"):
				continue
			if line.begins_with("--- technikai"):
				tech = true
				continue
			if tech:
				continue
			var i := line.find(": ")
			var key := line.left(i) if i > 0 else (line.trim_suffix(":") if line.ends_with(":") else "")
			var val := line.substr(i + 2) if i > 0 else ""
			if key == "Forrás":
				var j := val.rfind(" – http")
				cur["forrasok"].append({"cim": val.left(j) if j > 0 else val, "link": val.substr(j + 3) if j > 0 else ""})
				last = ""
			elif key in ["Korszak", "Kérdés", "Röviden", "Ha kikutatod", "Mire jó?", "Mi a gond vele?", "Mennyire bizonyított?", "Lektorálva",
					"Kérdés angolul", "Röviden angolul", "Ha kikutatod angolul", "Mire jó? angolul", "Mi a gond vele? angolul", "Mennyire bizonyított? angolul"]:
				cur[key] = val
				last = key
			elif last != "":
				cur[last] = str(cur[last]) + " " + line      # eltört hosszú sor folytatása
	for id in _all:
		var c: Dictionary = _all[id]
		c["tema"] = _tag_of.get(id, "")
		c["kor"] = {"I.": 1, "II.": 2, "III.": 3, "IV.": 4}.get(str(c.get("Korszak", "I.")).split(" ")[0], 1)


static func card(id: String) -> Dictionary:
	load_all()
	return _all.get(id, {})


static func ids() -> Array:
	load_all()
	return _all.keys()


## A kártya mezője a választott nyelven ("Kérdés" -> "Kérdés angolul").
static func text(id: String, key: String, en: bool) -> String:
	var c := card(id)
	if en and str(c.get(key + " angolul", "")) != "":
		return str(c[key + " angolul"])
	return str(c.get(key, ""))


static func theme_of(id: String) -> String:
	return str(card(id).get("tema", ""))


## A még ki nem kutatott kártyák egy témakörben, a megnyílt korszakig.
static func open_in(theme: String, max_era: int, have: Array) -> Array:
	load_all()
	var out: Array = []
	var later: Array = []
	for id in TAGS.get(theme, []):
		if not _all.has(id) or id in have:
			continue
		if int(_all[id]["kor"]) <= max_era:
			out.append(id)
		else:
			later.append(id)
	# minden témakörben legyen miből választani: ha kevés a megnyílt kérdés, a legkorábbi későbbiek is jönnek
	later.sort_custom(func(x: String, y: String) -> bool: return int(_all[x]["kor"]) < int(_all[y]["kor"]))
	while out.size() < 3 and not later.is_empty():
		out.append(later.pop_front())
	return out


## Kulcsszám a kártyához (adatok/kulcsszamok.json): csak a kézzel ellenőrzött ÉS lektorált mondat jelenik meg.
static var _keys: Dictionary = {}
static var _keys_loaded := false
static var show_unproofed := false     # csak az öntesztben: a még nem lektorált mondat is látszik

static func key_number(id: String) -> Dictionary:
	if not _keys_loaded:
		_keys_loaded = true
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://adatok/kulcsszamok.json"))
		if typeof(j) == TYPE_DICTIONARY and typeof(j.get("szamok")) == TYPE_DICTIONARY:
			_keys = j["szamok"]
	var k: Variant = _keys.get(id)
	if typeof(k) == TYPE_DICTIONARY and (bool(k.get("lektoralva", false)) or show_unproofed) and str(k.get("hu", "")) != "":
		return k
	return {}
