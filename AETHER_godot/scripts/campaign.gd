extends Node
## Telő idő és erőforrások.
## A hőmérséklet a klímamodellből jön (idővonallal: egy terv csak a bevezetése
## utáni évtől hat, a múlt nem változik). A pénz és a bizalom JÁTÉKSZABÁLY,
## nem valós adat: azt tanítja, hogy a gyors cselekvéshez bizalom kell,
## a bizalmat pedig ellenőrzött tudással és betartott tervvel lehet szerezni.

signal year_passed(year: int, note: String)
signal changed
signal game_over
signal era_reached(era: int)

const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")
const Knowledge := preload("res://scripts/knowledge.gd")

const START_YEAR := 2026
const END_YEAR := 2100
const START_MONEY := 200
const START_TRUST := 50
const RESEARCH_COST := 40
const TRUST_PER_RESULT := 6          # ellenőrzött eredményenként a tervben
const TRUST_STEP_BACK := 10          # visszalépés egy gyengébb tervre
const SECONDS_PER_YEAR := [48.0, 48.0]  # egy év 48 másodperc (gyorsítás nincs)

## A kutatóállomás moduljai (játékszabály). Szintenkénti építési ár; az építés 1 évig tart.
const MODULES := {
	"ai_mag": {"nev": "AI-mag", "ar": [80, 160, 300]},
	"archivum": {"nev": "Archívum", "ar": [60, 120, 240]},
	"uveghaz": {"nev": "Üvegház", "ar": [70, 140, 260]},
}
const MAX_LEVEL := 3

var year := START_YEAR
var money := START_MONEY
var trust := START_TRUST
var timeline: Array = []             # [{"ev": int, "terv": Dictionary}], időrendben
var model: Dictionary = {}           # a modell eredménye a jelenlegi idővonalra
var running := false
var fast := false
var blocked := false                 # nyitott ablak alatt az idő áll
var station := {"ai_mag": 0, "archivum": 0, "uveghaz": 0}
var building := {}                   # {"modul": "ai_mag", "kesz": 2028} amíg épül
var research_this_year := 0
var done: Array = []                 # tudásfa: a kutatott témák azonosítói
var stars: Dictionary = {}           # tudásfa: téma -> 1–3 csillag (a legjobb kutatás ereje)
var era := 1                         # korszak (1–4), csak nő
var levers: Dictionary = {}          # jóváhagyott tervkarok: kar -> javaslat (a kutatásokból)
var world_seed := 0                   # ennek a játéknak a „világa”: ebből jön minden véletlen
var sens := 0.0                      # a Föld rejtett érzékenysége: −1 (a sáv alja) … +1 (a sáv teteje)
var noise: Array = []                # természetes évi ingadozás 2026-tól (°C), a magból előre kisorsolva
var history: Array = []              # az évek krónikája: [{"ev", "T", "esemenyek": [...]}]
var games_played := 0
var volcanoes: Array = []            # nagy vulkánkitörések évei ebben a világban (a magból sorsolva)

## Partvédelem (játékszabály): ezek a kutatások csökkentik az emelkedő tenger okozta kárt.
const COAST_TOPICS := ["gatak", "vizes_part", "megemelt_haz", "tengerszint", "mangrove", "korai_riasztas", "tengerifu", "korall_ujra"]
const COAST_COST_PER_M := 60.0       # évi partkár pénzben, a 2026 óta emelkedett tenger minden méterére
var save_file := "aether_jatek.json"  # az önteszt külön fájlt használ
var _acc := 0.0


func save_path() -> String:
	return OS.get_user_data_dir().path_join(save_file)


func load_game() -> void:
	var d: Variant = Bridge.read_json(save_path())
	if typeof(d) != TYPE_DICTIONARY:
		return
	year = int(d.get("ev", START_YEAR))
	money = int(d.get("penz", START_MONEY))
	trust = int(d.get("bizalom", START_TRUST))
	timeline = d.get("idovonal", [])
	var m: Variant = d.get("modell", {})
	model = m if typeof(m) == TYPE_DICTIONARY else {}
	var st: Variant = d.get("allomas", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in station:
			station[k] = int(st.get(k, 0))
	var b: Variant = d.get("epul", {})
	building = b if typeof(b) == TYPE_DICTIONARY else {}
	research_this_year = int(d.get("kutatas_ev", 0))
	var dn: Variant = d.get("tudas", [])
	done = dn if typeof(dn) == TYPE_ARRAY else []
	era = clampi(int(d.get("korszak", 1)), 1, Knowledge.ERAS.size())
	var lv: Variant = d.get("karok", {})
	levers = lv if typeof(lv) == TYPE_DICTIONARY else {}
	var cs: Variant = d.get("csillagok", {})
	stars = {}
	if typeof(cs) == TYPE_DICTIONARY:
		for k in cs:
			stars[str(k)] = clampi(int(cs[k]), 1, 3)
	world_seed = int(d.get("mag", 0))
	sens = clampf(float(d.get("erzekenyseg", 0.0)), -1.0, 1.0)
	var nz: Variant = d.get("ingadozas", [])
	noise = nz if typeof(nz) == TYPE_ARRAY else []
	var hs: Variant = d.get("kronika", [])
	history = hs if typeof(hs) == TYPE_ARRAY else []
	var vk: Variant = d.get("vulkanok", [])
	volcanoes = vk if typeof(vk) == TYPE_ARRAY else []
	for id in done:   # régi mentés: a kutatott téma legalább 1 csillag
		if not stars.has(str(id)):
			stars[str(id)] = 1


func save() -> void:
	Bridge.write_json(save_path(), {"ev": year, "penz": money, "bizalom": trust, "idovonal": timeline,
		"modell": model, "allomas": station, "epul": building, "kutatas_ev": research_this_year,
		"tudas": done, "korszak": era, "karok": levers, "csillagok": stars,
		"mag": world_seed, "erzekenyseg": sens, "ingadozas": noise, "kronika": history, "vulkanok": volcanoes})


## seed_value >= 0: ugyanaz a Föld újra (ugyanaz az érzékenység, ingadozás, események).
func new_game(seed_value: int = -1) -> void:
	year = START_YEAR
	money = START_MONEY
	trust = START_TRUST
	timeline = []
	model = {}
	station = {"ai_mag": 0, "archivum": 0, "uveghaz": 0}
	building = {}
	research_this_year = 0
	done = []
	stars = {}
	era = 1
	levers = {}
	running = false
	fast = false
	_acc = 0.0
	history = []
	roll_world(seed_value if seed_value >= 0 else (-1 if save_file == "aether_jatek.json" else 2026))
	if save_file == "aether_jatek.json":   # az önteszt ne törölje a játékos küldetéscsillagait
		L.set_setting("kuldetesek", {})   # a küldetések csillagai is alapra állnak
	save()
	changed.emit()


# --- idő: körökre osztott évek ------------------------------------------------
## Az év addig tart, amíg a játékos kutat, épít és dönt; az „Év lezárása” lépteti tovább.
## (A `running`, `fast`, `blocked` a régi, valós idejű menetből maradt; már semmi sem használja.)
func year_progress() -> float:
	return 0.0


func month() -> int:
	return 1


# --- a világ véletlene (játékszabály, a tudományos bizonytalanságon belül) ---------
## Minden új játék más Föld. A klímamodell három pályát számol (a sáv alja, közepe, teteje),
## mert a tudomány nem tudja pontosan, mennyire érzékeny a Föld a CO2-re. A játék ebből a
## sávból sorsol egy rejtett értéket: a játékos csak az évek múlásával látja, melyik Földet kapta.
## Erre jön a természetes évi ingadozás (meleg és hűvös évek, pl. El Niño): átlagosan 0,1 °C körül.
func roll_world(seed_value: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value < 0:
		rng.randomize()
		world_seed = int(rng.randi() % 900000) + 100000
	else:
		world_seed = seed_value
	rng.seed = world_seed
	sens = clampf(rng.randfn(0.0, 0.5), -1.0, 1.0)
	noise = []
	var v := 0.0
	for i in END_YEAR - START_YEAR + 1:
		v = 0.5 * v + rng.randfn(0.0, 0.085)     # egymást követő évek hasonlítanak egymásra
		noise.append(snappedf(clampf(v, -0.25, 0.25), 0.001))
	# Nagy vulkánkitörés (játékszabály, valódi mintára: a Pinatubo 1991-es kitörése után a Föld
	# átlaga egy-két évre néhány tized fokkal hűlt). Ritka, és csak átmeneti: a CO2 marad.
	volcanoes = []
	var i2 := 3
	while i2 < noise.size() - 3:
		if rng.randf() < 0.02:
			volcanoes.append(START_YEAR + i2)
			noise[i2 + 1] = snappedf(float(noise[i2 + 1]) - 0.30, 0.001)
			noise[i2 + 2] = snappedf(float(noise[i2 + 2]) - 0.15, 0.001)
			i2 += 8
		i2 += 1
	if save_file != "aether_jatek.json":   # az önteszt Földje mindig a sáv közepe, ingadozás nélkül
		sens = 0.0
		noise = []
		volcanoes = []


## A valódi (ebben a játékban megvalósuló) érték a három modellpályából, ingadozás nélkül.
func world_value(group: String, key: String, y: int) -> float:
	var ys: Array = model.get("evek", [])
	var g: Variant = model.get(group, {})
	if typeof(g) != TYPE_DICTIONARY or not g.has("kozep") or not g["kozep"].has(key):
		return NAN
	for i in ys.size():
		if int(ys[i]) == y:
			var mid := float(g["kozep"][key][i])
			var side := "magas" if sens > 0.0 else "alacsony"
			if not g.has(side) or not g[side].has(key):
				return mid
			return lerpf(mid, float(g[side][key][i]), absf(sens))
	return NAN


## Az adott év „mért” hőmérséklete ebben a játékban: a valódi pálya + természetes ingadozás.
func measured_temp(y: int) -> float:
	var t := world_value("terv", "homerseklet", y)
	var i := y - START_YEAR
	if is_nan(t) or i < 0 or i >= noise.size():
		return t
	return t + float(noise[i])


## A tengerszint ebben a játékban (méter, 2005-höz képest; IPCC AR6 a modellből). A sávon belül
## a Föld rejtett érzékenysége dönt (játékszabály: az érzékenyebb Földön a tenger is gyorsabban nő).
func sea_level(y: int, group: String = "terv") -> float:
	var sl: Variant = model.get("tengerszint", {})
	var ys: Array = model.get("evek", [])
	if typeof(sl) != TYPE_DICTIONARY or not sl.has(group):
		return NAN
	var g: Dictionary = sl[group]
	for i in ys.size():
		if int(ys[i]) == y:
			var mid := float(g["kozep"][i])
			var side := "felso" if sens > 0.0 else "also"
			if not g.has(side):
				return mid
			return lerpf(mid, float(g[side][i]), absf(sens))
	return NAN


## A partvédelmi tudás ennyi részét fogja meg a tenger okozta kárnak (0–0,75).
func coast_shield() -> float:
	var n := 0
	for id in COAST_TOPICS:
		if id in done:
			n += 1
	return minf(0.75, 0.15 * n)


## Évi partkár pénzben (játékszabály): a 2026 óta emelkedett tengerrel arányos.
func coast_cost(y: int) -> int:
	var now := sea_level(y)
	var base := sea_level(START_YEAR)
	if is_nan(now) or is_nan(base):
		return 0
	return int(round(maxf(0.0, now - base) * COAST_COST_PER_M * (1.0 - coast_shield())))


## A 2100-as melegedés és a csúcs ezen a Földön (ingadozás nélkül).
func real_t2100() -> float:
	return world_value("terv", "homerseklet", END_YEAR)


func real_peak() -> float:
	var best := -99.0
	for y in range(START_YEAR, END_YEAR + 1):
		var t := world_value("terv", "homerseklet", y)
		if not is_nan(t):
			best = maxf(best, t)
	return best


## Pontszám (játékszabály): a hűvösebb Föld, a tudás és a bizalom ér pontot.
func score() -> int:
	var t := real_t2100()
	if is_nan(t):
		return 0
	return maxi(0, int(round((4.0 - t) * 300.0))) + 10 * done.size() + 2 * trust


# --- eddigi játékok (külön fájl: az új játék nem törli) -------------------------
func results_path() -> String:
	return OS.get_user_data_dir().path_join("aether_eredmenyek.json")


func results() -> Array:
	var d: Variant = Bridge.read_json(results_path())
	return d if typeof(d) == TYPE_ARRAY else []


## A befejezett játék bejegyzése. Az önteszt nem ír a játékos listájába.
func record_result() -> Dictionary:
	var e := {"datum": Time.get_date_string_from_system(), "mag": world_seed, "pont": score(),
		"T2100": snappedf(real_t2100(), 0.0001), "csucs": snappedf(real_peak(), 0.0001),
		"temak": done.size(), "bizalom": trust}
	if save_file == "aether_jatek.json":
		var all := results()
		all.append(e)
		Bridge.write_json(results_path(), all)
	return e


## Technikai hibával leállt kutatás: a pénz és az évi kutatási hely visszajár.
func refund_research() -> void:
	money += research_cost()
	research_this_year = maxi(0, research_this_year - 1)
	save()
	changed.emit()


func income() -> int:
	return 40 + trust / 2 + knowledge_income()


## A tudás hasznot hoz (játékszabály): minden kutatott téma évente +1 pénz, a ★★★ témák +2.
func knowledge_income() -> int:
	var n := 0
	for id in done:
		n += 2 if int(stars.get(str(id), 1)) >= 3 else 1
	return n


func advance() -> void:
	if year >= END_YEAR:
		return
	year += 1
	var inc := income()
	money += inc
	var d := _trust_drift()
	trust = clampi(trust + d, 0, 100)
	research_this_year = 0
	var note := L.t("%d: bevétel +%d.") % [year, inc]
	if knowledge_income() > 0:
		note = L.t("%d: bevétel +%d, ebből a tudásodból +%d.") % [year, inc, knowledge_income()]
	var cc := coast_cost(year)
	if cc > 0:
		money = maxi(0, money - cc)
		note += " " + L.t("Emelkedő tenger: partkár −%d.") % cc
	if d > 0:
		note += " " + L.t("A kibocsátás csökken: bizalom +%d.") % d
	elif d < 0:
		note += " " + L.t("A kibocsátás nem csökken: bizalom %d.") % d
	var g := greenhouse_trust()
	if g > 0:
		trust = mini(100, trust + g)
		note += " " + L.t("Üvegház: bizalom +%d.") % g
	if not building.is_empty() and year >= int(building["kesz"]):
		var mod := str(building["modul"])
		station[mod] = int(station[mod]) + 1
		building = {}
		note += " " + L.t("Elkészült: %s, %d. szint.") % [L.t(MODULES[mod]["nev"]), station[mod]]
	history.append({"ev": year, "T": snappedf(measured_temp(year), 0.01)})
	save()
	year_passed.emit(year, note)
	check_era()
	changed.emit()
	if year >= END_YEAR:
		running = false
		game_over.emit()


## Évente: ha a nettó CO2-kibocsátás csökken (vagy már közel nulla), nő a bizalom; ha nem, csökken.
func _trust_drift() -> int:
	var now := series_at("netto_co2", year)
	var before := series_at("netto_co2", year - 1)
	if is_nan(now) or is_nan(before):
		return 0
	return 1 if (now < before - 0.05 or now <= 1.0) else -1


# --- állomás ---------------------------------------------------------------
## AI-mag: ennyi cikket néz át egy kutatás (több cikk = alaposabb, de lassabb kutatás).
func papers_per_research() -> int:
	return 12 + 4 * int(station["ai_mag"])


## AI-mag: ennyi kutatást lehet indítani egy játékévben.
func research_limit() -> int:
	return 2 + int(station["ai_mag"])


## Archívum: a már letöltött cikkeket nem kell újra keresni, ezért olcsóbb a kutatás.
func research_cost() -> int:
	return RESEARCH_COST - 8 * int(station["archivum"])


## Üvegház: a helyi kísérletek eredményét az emberek látják: évente ennyi bizalom.
func greenhouse_trust() -> int:
	return int(station["uveghaz"])


func module_cost(mod: String) -> int:
	var lvl := int(station[mod])
	if lvl >= MAX_LEVEL:
		return -1
	return int(MODULES[mod]["ar"][lvl])


## "" ha építhető, különben az ok.
func build_problem(mod: String) -> String:
	if int(station[mod]) >= MAX_LEVEL:
		return L.t("Elérte a legmagasabb szintet.")
	if not building.is_empty():
		return L.t("Egyszerre egy modul épülhet.")
	if year >= END_YEAR:
		return L.t("A játék véget ért.")
	if money < module_cost(mod):
		return L.t("Ehhez %d pénz kell, neked %d van.") % [module_cost(mod), money]
	return ""


func build(mod: String) -> String:
	var problem := build_problem(mod)
	if problem != "":
		return problem
	money -= module_cost(mod)
	building = {"modul": mod, "kesz": year + 1}
	save()
	changed.emit()
	return L.t("Építés indult: %s, kész: %d.") % [L.t(MODULES[mod]["nev"]), year + 1]


func series_at(key: String, y: int, ens: String = "kozep") -> float:
	var ys: Array = model.get("evek", [])
	for i in ys.size():
		if int(ys[i]) == y:
			return float(model["terv"][ens][key][i])
	return NAN


func temp_now() -> float:
	return measured_temp(year)


# --- terv ------------------------------------------------------------------
## Mennyi bizalom kell egy tervhez (játékszabály): minél gyorsabb, annál több.
static func required_trust(sc: Dictionary) -> int:
	var r := 0
	if sc.has("co2_cel_ev"):
		r = maxi(r, clampi(int((2070 - int(sc["co2_cel_ev"])) * 2.5), 0, 90))
	r = maxi(r, int(float(sc.get("metan_csokkentes_pct", 0.0))))
	var cdr := 0.0
	for v in Dictionary(sc.get("cdr", {})).values():
		cdr += float(v)
	r = maxi(r, mini(90, int(cdr * 8.0)))
	return r


static func plan_cost(sc: Dictionary) -> int:
	return 30 + required_trust(sc)


func start_year() -> int:
	return year + 1


## Az új tervvel kiegészített idővonal (előnézethez és bevezetéshez).
func timeline_with(sc: Dictionary) -> Array:
	var out: Array = []
	for seg in timeline:
		if int(seg["ev"]) < start_year():
			out.append(seg)
	out.append({"ev": start_year(), "terv": sc})
	return out


## "" ha bevezethető, különben az ok egy rövid mondatban.
func adopt_problem(sc: Dictionary) -> String:
	if year >= END_YEAR:
		return L.t("A játék véget ért.")
	var need := required_trust(sc)
	if trust < need:
		return L.t("Ehhez %d%% bizalom kell, neked %d%% van. Kutass, és tartsd a terved!") % [need, trust]
	var cost := plan_cost(sc)
	if money < cost:
		return L.t("Ehhez %d pénz kell, neked %d van. Évente %d pénzt kapsz.") % [cost, money, income()]
	return ""


func is_step_back(sc: Dictionary) -> bool:
	if timeline.is_empty():
		return false
	var cur: Dictionary = timeline[-1]["terv"]
	var cur_y := int(cur.get("co2_cel_ev", 9999))
	var new_y := int(sc.get("co2_cel_ev", 9999))
	return new_y > cur_y or float(sc.get("metan_csokkentes_pct", 0.0)) < float(cur.get("metan_csokkentes_pct", 0.0))


## Bevezeti a tervet; res a modell eredménye erre az idővonalra (az előnézetből).
func adopt(sc: Dictionary, res: Dictionary) -> String:
	var problem := adopt_problem(sc)
	if problem != "":
		return problem
	money -= plan_cost(sc)
	var note := L.t("A terved életbe lép, első éve: %d.") % start_year()
	if is_step_back(sc):
		trust = maxi(0, trust - TRUST_STEP_BACK)
		note += " " + L.t("Visszaléptél egy gyengébb tervre: bizalom −%d.") % TRUST_STEP_BACK
	timeline = timeline_with(sc)
	model = res
	save()
	changed.emit()
	check_era()
	return note


# --- kutatás ---------------------------------------------------------------
func research_problem() -> String:
	if research_this_year >= research_limit():
		return L.t("Idén már %d kutatást indítottál, ennyit enged az AI-mag. Várj egy évet, vagy fejleszd az AI-magot!") % research_limit()
	if money < research_cost():
		return L.t("Nincs elég pénz kutatásra (%d kell, neked %d van). Indítsd el az időt, évente kapsz pénzt.") % [research_cost(), money]
	return ""


func can_research() -> bool:
	return research_problem() == ""


func pay_research() -> void:
	money -= research_cost()
	research_this_year += 1
	save()
	changed.emit()


## Ha egy kutatás technikai hiba miatt állt le (nem a játékos hibája), visszajár a pénz
## és az idei kutatási hely. Az összeg az, amit a kutatás indításakor ténylegesen fizetett.
func refund_research(amount: int) -> void:
	money += maxi(0, amount)
	research_this_year = maxi(0, research_this_year - 1)
	save()
	changed.emit()


func reward_results(n: int) -> void:
	trust = mini(100, trust + n * TRUST_PER_RESULT)
	save()
	changed.emit()


# --- tudásfa és korszakok (játékszabály) -----------------------------------
## Egy téma akkor kutatott, ha a kutatás legalább egy ellenőrzött számot talált róla.
## A témát kutatottnak jelöli; a csillag a legjobb eddigi eredmény marad.
func mark_researched(id: String, n_stars: int = 1) -> void:
	if id == "":
		return
	var old := int(stars.get(id, 0))
	if id in done and n_stars <= old:
		return
	if not (id in done):
		done.append(id)
	stars[id] = clampi(maxi(old, n_stars), 1, 3)
	save()
	changed.emit()
	check_era()


func add_levers(new_levers: Array) -> void:
	for j in new_levers:
		levers[str(j["kar"])] = j
	save()


## Ha a modell szerint a nettó CO2-kibocsátás 5 év alatt érezhetően csökkent (vagy már közel nulla).
func co2_falling() -> bool:
	var now := series_at("netto_co2", year)
	var before := series_at("netto_co2", year - 5)
	if is_nan(now) or is_nan(before):
		return false
	return now < before - 0.5 or now <= 1.0


## A target korszak belépési feltételei: [[rövid szöveg, teljesül-e], ...].
func era_conditions(target: int) -> Array:
	var out: Array = []
	if target < 2 or target > Knowledge.ERAS.size():
		return out
	var e: Dictionary = Knowledge.ERAS[target - 1]
	var need := int(e.get("kell", 0))
	var have := mini(need, Knowledge.count_done(done, target - 1))
	out.append([L.t("Kutatott téma a(z) %s korszakból: %d/%d") % [Knowledge.era_name(target - 1), have, need], have >= need])
	if bool(e.get("terv", false)):
		out.append([L.t("Bevezetett terv"), not timeline.is_empty()])
	if e.has("bizalom"):
		out.append([L.t("Bizalom legalább %d%%") % int(e["bizalom"]), trust >= int(e["bizalom"])])
	if bool(e.get("csokkeno_co2", false)):
		out.append([L.t("Csökkenő CO2-kibocsátás a modellben (5 év alatt)"), co2_falling()])
	return out


static func _all_met(conds: Array) -> bool:
	for c in conds:
		if not bool(c[1]):
			return false
	return true


## Ha teljesül a következő korszak minden feltétele, belép (akár több lépést is).
func check_era() -> void:
	var start := era
	while era < Knowledge.ERAS.size() and _all_met(era_conditions(era + 1)):
		era += 1
	if era != start:
		save()
		changed.emit()
		era_reached.emit(era)
