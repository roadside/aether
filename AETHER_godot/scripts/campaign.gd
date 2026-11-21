extends Node
## Telő idő és erőforrások.
## A hőmérséklet a klímamodellből jön (idővonallal: egy terv csak a bevezetése
## utáni évtől hat, a múlt nem változik). A pénz és a bizalom JÁTÉKSZABÁLY,
## nem valós adat: azt tanítja, hogy a gyors cselekvéshez bizalom kell,
## a bizalmat pedig ellenőrzött tudással és betartott tervvel lehet szerezni.

signal year_passed(year: int, note: String)
signal changed
signal game_over

const L := preload("res://scripts/i18n.gd")
const Bridge := preload("res://scripts/lab_bridge.gd")

const START_YEAR := 2026
const END_YEAR := 2100
const START_MONEY := 200
const START_TRUST := 50
const RESEARCH_COST := 40
const TRUST_PER_RESULT := 6          # ellenőrzött eredményenként a tervben
const TRUST_STEP_BACK := 10          # visszalépés egy gyengébb tervre
const SECONDS_PER_YEAR := [12.0, 4.0]  # normál, gyors

var year := START_YEAR
var money := START_MONEY
var trust := START_TRUST
var timeline: Array = []             # [{"ev": int, "terv": Dictionary}], időrendben
var model: Dictionary = {}           # a modell eredménye a jelenlegi idővonalra
var running := false
var fast := false
var blocked := false                 # nyitott ablak alatt az idő áll
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


func save() -> void:
	Bridge.write_json(save_path(), {"ev": year, "penz": money, "bizalom": trust, "idovonal": timeline,
		"modell": model})


func new_game() -> void:
	year = START_YEAR
	money = START_MONEY
	trust = START_TRUST
	timeline = []
	model = {}
	running = false
	_acc = 0.0
	save()
	changed.emit()


# --- idő -------------------------------------------------------------------
func _process(delta: float) -> void:
	if not running or blocked or year >= END_YEAR:
		return
	_acc += delta
	if _acc >= SECONDS_PER_YEAR[1 if fast else 0]:
		_acc = 0.0
		advance()


func income() -> int:
	return 40 + trust / 2


func advance() -> void:
	if year >= END_YEAR:
		return
	year += 1
	var inc := income()
	money += inc
	var d := _trust_drift()
	trust = clampi(trust + d, 0, 100)
	var note := L.t("%d: bevétel +%d.") % [year, inc]
	if d > 0:
		note += " " + L.t("A kibocsátás csökken: bizalom +%d.") % d
	elif d < 0:
		note += " " + L.t("A kibocsátás nem csökken: bizalom %d.") % d
	save()
	year_passed.emit(year, note)
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


func research_cost() -> int:
	return RESEARCH_COST


func series_at(key: String, y: int, ens: String = "kozep") -> float:
	var ys: Array = model.get("evek", [])
	for i in ys.size():
		if int(ys[i]) == y:
			return float(model["terv"][ens][key][i])
	return NAN


func temp_now() -> float:
	return series_at("homerseklet", year)


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
	return note


# --- kutatás ---------------------------------------------------------------
func can_research() -> bool:
	return money >= RESEARCH_COST


func pay_research() -> void:
	money -= RESEARCH_COST
	save()
	changed.emit()


func reward_results(n: int) -> void:
	trust = mini(100, trust + n * TRUST_PER_RESULT)
	save()
	changed.emit()
