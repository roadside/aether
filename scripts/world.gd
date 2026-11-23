extends RefCounted
## A játék állapota és szabályai (felület nélkül, így magában is tesztelhető).
##
## Egy kör 5 év, 2026-tól 2100-ig 15 kör. Körönként három lépésed van: kutatás, tárgyalás, CO2-kivonás.
## VALÓDI: a klímamodell és a számai (model.gd), a csoportok kibocsátása és a billenőpontok sávjai
## (adatok/*.json, forrással), a kártyák (temak/*.txt), a kivonás határai (archivum/*.json).
## JÁTÉKSZABÁLY: a tárgyalás menete, a csoportok aggodalmai, a megingás, a lépések száma.

const M := preload("res://scripts/model.gd")
const Cards := preload("res://scripts/cards.gd")

const ROUNDS := 15
const ROUND_YEARS := 5
const STEPS := 3
const TARGETS := [2070, 2060, 2050, 2040]     # vállalható „nulla kibocsátás” évek, egyre merészebb
const MIN_YEARS := 10                          # ennyi év legalább kell az átálláshoz (játékszabály)
const METHANE_CUT := 0.30                      # a Globális Metánvállalás mértéke: −30% (10 év alatt)
const METHANE_YEARS := 10
const CDR_YEARS := 20                          # a kivonás ennyi év alatt fut fel (a modell korábbi szabálya)
const SAVE_VERSION := 3                       # ha a szabályok vagy az adatok változnak, a régi mentés helyett új játék indul
const WAVER_CHANCE := 0.30                     # körönként ekkora eséllyel inog meg egy csoport (játékszabály)
## CO2-kivonási programok: kártya -> [a fenntartható sáv alja, teteje] GtCO2/év 2050-re
## (Fuss és mtsai 2018, Environ. Res. Lett. 13 063002; az archívum ellenőrzött idézetei szerint).
const CDR := {"erdo": [0.5, 3.6], "bioszen": [0.5, 2.0], "kozet": [2.0, 4.0], "levegoszures": [0.5, 5.0], "novenyi_energia": [0.5, 5.0]}

var seed_v := 0
var sens := 0.0                  # a Föld rejtett érzékenysége (−1…+1), a végén derül ki
var rng := RandomNumberGenerator.new()
var st: Dictionary = {}
var round_i := 0                 # 0…15 (15 = vége)
var steps := STEPS
var groups: Array = []
var rest_share := 0.0            # a világ többi részének CO2-részesedése: a hat csoport átlagát követi (játékszabály)
var rest_ch4 := 0.0
var hand: Array = []             # kikutatott kártyák azonosítói
var cdr: Array = []              # [{"id", "gt", "ev"}]
var tips: Array = []             # billenőpontok: {"id", ..., "kuszob", "ev" (átlépés éve vagy 0)}
var history: Array = []          # [[év, T]] a megtörtént évek
var base_history: Array = []     # ugyanez „ha semmi sem változik” mellett, ugyanazon a Földön
var news: Array = []             # az utolsó öt év hírei: [{"fajta", ...}]
var data: Dictionary = {}


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func new_game(seed_value: int = -1) -> void:
	data = read_json("res://adatok/csoportok.json")
	seed_v = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) % 1000000
	rng.seed = seed_v
	sens = clampf(rng.randfn(0.0, 0.5), -1.0, 1.0)     # többnyire a sáv közepe táján, néha a szélén
	st = M.new_state()
	M.step(st, {}, params())                            # 2025: a játék 2026 elején indul
	round_i = 0
	steps = STEPS
	hand = []
	cdr = []
	news = []
	history = [[int(st["ev"]), float(st["T"])]]
	base_history = history.duplicate(true)
	_base = st.duplicate()
	groups = []
	rest_share = float(data.get("tobbi_co2_resz", 0.0))
	rest_ch4 = float(data.get("tobbi_ch4_resz", 0.0))
	for g in data["csoportok"]:
		var d: Dictionary = g.duplicate(true)
		# játékszabály: a fő aggodalom állandó, a többiből játékonként kettőt sorsolunk
		var pool: Array = d["felelmek"].duplicate()
		var fears: Array = [pool.pop_front()]
		while fears.size() < 3 and not pool.is_empty():
			fears.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		d["felelmek"] = fears
		d["fok"] = 0            # hányadik vállalásnál tart (0 = nincs)
		d["cel"] = 0            # a vállalt „nulla” év
		d["y0"] = 0
		d["f0"] = 1.0
		d["metan"] = 0          # a metánvállalás éve (0 = nincs)
		d["hasznalt"] = []      # az ennél a csoportnál már kijátszott kártyák
		d["konnyebb"] = false   # katasztrófa után egy kártyával kevesebb kell (játékszabály)
		groups.append(d)
	tips = []
	var tj: Variant = read_json("res://adatok/billenopontok.json")
	if typeof(tj) == TYPE_DICTIONARY:
		for t in tj["elemek"]:
			var e: Dictionary = t.duplicate(true)
			# a rejtett küszöb a közölt sávból: többnyire a legjobb becslés közelében (játékszabály)
			var u := rng.randf()
			var lo := float(e["also"])
			var mid := float(e["kozep"])
			var hi := float(e["felso"])
			var c := (mid - lo) / maxf(hi - lo, 0.001)
			e["kuszob"] = lo + sqrt(u * (hi - lo) * (mid - lo)) if u < c else hi - sqrt((1.0 - u) * (hi - lo) * (hi - mid))
			# játékszabály: a játék elején még egyik küszöböt sem léptük át (a sáv mai melegedés fölötti részéből sorsolunk)
			var tries := 0
			while float(e["kuszob"]) <= float(st["T"]) + 0.03 and hi > float(st["T"]) + 0.05 and tries < 60:
				u = rng.randf()
				e["kuszob"] = lo + sqrt(u * (hi - lo) * (mid - lo)) if u < c else hi - sqrt((1.0 - u) * (hi - lo) * (hi - mid))
				tries += 1
			e["ev"] = 0
			tips.append(e)

var _base: Dictionary = {}


func params() -> Dictionary:
	return M.params(sens)


func year() -> int:
	return int(st["ev"]) + 1          # az az év, amelynek az elején állunk


func over() -> bool:
	return round_i >= ROUNDS


func group(id: String) -> Dictionary:
	for g in groups:
		if g["id"] == id:
			return g
	return {}


# --- kibocsátás ---------------------------------------------------------------

## A csoport kibocsátása a maihoz képest (1 = mai szint) az adott évben.
static func fraction(g: Dictionary, y: int) -> float:
	if int(g["cel"]) == 0:
		return float(g["f0"])
	var y0 := int(g["y0"])
	return float(g["f0"]) * clampf(float(int(g["cel"]) - y) / float(int(g["cel"]) - y0), 0.0, 1.0)


func _avg_fraction(y: int) -> float:
	var s := 0.0
	var w := 0.0
	for g in groups:
		s += float(g["co2_resz"]) * fraction(g, y)
		w += float(g["co2_resz"])
	return s / w if w > 0.0 else 1.0


func drivers(y: int) -> Dictionary:
	var f := 0.0
	var ch4 := 0.0
	var joined := 0.0
	var w := 0.0
	for g in groups:
		f += float(g["co2_resz"]) * fraction(g, y)
		w += float(g["ch4_resz"])
		if int(g["metan"]) > 0:
			var r := clampf(float(y - int(g["metan"])) / METHANE_YEARS, 0.0, 1.0)
			ch4 += float(g["ch4_resz"]) * METHANE_CUT * r
			joined += float(g["ch4_resz"]) * r
	f += rest_share * _avg_fraction(y)
	if w > 0.0:
		ch4 += rest_ch4 * METHANE_CUT * joined / w      # a világ többi része a hat csoport átlagát követi
	var rem := 0.0
	for c in cdr:
		rem += float(c["gt"]) * clampf(float(y - int(c["ev"])) / CDR_YEARS, 0.0, 1.0)
	return {"co2": M.E_CO2_NOW * f, "cdr": rem, "ch4": ch4}


## A világ kibocsátása a maihoz képest (1 = mai), kivonással együtt.
func net_ratio(y: int) -> float:
	var d := drivers(y)
	return (float(d["co2"]) - float(d["cdr"])) / M.E_CO2_NOW


## Előrejelzés 2100-ig a mostani vállalásokkal: {"also","kozep","felso"}: [[év, T], ...]
## A Föld valódi érzékenységét nem ismerjük, ezért mindig a teljes sáv látszik.
func forecast() -> Dictionary:
	var out := {}
	for pair in [["also", -1.0], ["kozep", 0.0], ["felso", 1.0]]:
		# a múlt ugyanaz: a mért hőmérsékletből indul, csak a jövő érzékenysége más
		var p: Dictionary = M.params(pair[1])
		var off: float = float(st["T"]) - (M.T_START + float(p["tcre"]) / 1000.0 * float(st["cum"]) + float(st["t_up"]))
		var rows: Array = M.project(st, drivers, p)
		for r in rows:
			r[1] += off
		out[pair[0]] = rows
	# „ha semmi sem változik”: a mai kibocsátás marad, közepes érzékenységgel
	var pb: Dictionary = M.params(0.0)
	var offb: float = float(_base["T"]) - (M.T_START + float(pb["tcre"]) / 1000.0 * float(_base["cum"]) + float(_base["t_up"]))
	var brows: Array = M.project(_base, func(_y: int) -> Dictionary: return {}, pb)
	for r in brows:
		r[1] += offb
	out["alap"] = brows
	return out


# --- lépések ------------------------------------------------------------------

func max_era() -> int:
	return 1 if round_i < 1 else (2 if round_i < 4 else (3 if round_i < 7 else 4))


## Kutatás: három kérdés a témakörből (a megnyílt korszakig), ebből választasz egyet.
func research_offers(theme: String) -> Array:
	var pool := Cards.open_in(theme, max_era(), hand)
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


func research(id: String) -> bool:
	if steps <= 0 or id in hand:
		return false
	hand.append(id)
	steps -= 1
	return true


## A csoport következő vállalható céljai: csak ami korábbi a mostaninál, és legalább MIN_YEARS évre van.
func targets_for(g: Dictionary) -> Array:
	var out: Array = []
	for t in TARGETS:
		if (int(g["cel"]) == 0 or t < int(g["cel"])) and t >= year() + MIN_YEARS:
			out.append(t)
	return out


## Hány kártya kell a célhoz: 2070-hez és 2060-hoz 1, 2050-hez 2, 2040-hez 3; katasztrófa után eggyel kevesebb (legalább 1).
func cards_needed(g: Dictionary, target: int) -> int:
	var n := 1 if target >= 2060 else (2 if target >= 2050 else 3)
	return maxi(1, n - 1) if g["konnyebb"] else n


## A kézben lévő kártyák, amelyek ennek a csoportnak egy aggodalmára felelnek, és még nem hallották.
## Mennyit változna a 2100-ra várt melegedés (középérték), ha a csoport elfogadná a kérést? (negatív = hűvösebb)
func preview(g: Dictionary, target: int, methane: bool = false) -> float:
	var before := float(forecast()["kozep"][-1][1])
	var keep := {"f0": g["f0"], "y0": g["y0"], "cel": g["cel"], "metan": g["metan"]}
	var y := year()
	if methane:
		g["metan"] = y - 1
	else:
		g["f0"] = fraction(g, y - 1) if int(g["cel"]) > 0 else float(g["f0"])
		g["y0"] = y - 1
		g["cel"] = target
	var after := float(forecast()["kozep"][-1][1])
	for k in keep:
		g[k] = keep[k]
	return after - before


## Van-e most olyan kérés, amihez megvan a kártyád?
func can_convince(g: Dictionary) -> bool:
	if steps <= 0 or over():
		return false
	var n := usable(g).size()
	for t in targets_for(g):
		if n >= cards_needed(g, t):
			return true
	return int(g["metan"]) == 0 and not methane_cards(g).is_empty()


func usable(g: Dictionary) -> Array:
	var out: Array = []
	for id in hand:
		if Cards.theme_of(id) in g["felelmek"] and not (id in g["hasznalt"]):
			out.append(id)
	return out


func negotiate(g: Dictionary, target: int, played: Array) -> bool:
	if steps <= 0 or not (target in targets_for(g)) or played.size() < cards_needed(g, target):
		return false
	for id in played:
		if not (id in usable(g)):
			return false
	var y := year()
	g["f0"] = fraction(g, y - 1) if int(g["cel"]) > 0 else float(g["f0"])
	g["y0"] = y - 1
	g["cel"] = target
	g["fok"] = int(g["fok"]) + 1
	g["konnyebb"] = false
	for id in played:
		g["hasznalt"].append(id)
	steps -= 1
	return true


func methane_cards(g: Dictionary) -> Array:
	var out: Array = []
	for id in hand:
		if id in Cards.METHANE and not (id in g["hasznalt"]):
			out.append(id)
	return out


func pledge_methane(g: Dictionary, card_id: String) -> bool:
	if steps <= 0 or int(g["metan"]) > 0 or not (card_id in methane_cards(g)):
		return false
	g["metan"] = year() - 1
	g["hasznalt"].append(card_id)
	steps -= 1
	return true


func cdr_available() -> Array:
	var out: Array = []
	for id in hand:
		if CDR.has(id) and not cdr.any(func(c: Dictionary) -> bool: return c["id"] == id):
			out.append(id)
	return out


## CO2-kivonás indítása: óvatosan, a fenntartható sáv aljával számolunk.
func start_cdr(id: String) -> bool:
	if steps <= 0 or not (id in cdr_available()):
		return false
	cdr.append({"id": id, "gt": float(CDR[id][0]), "ev": year() - 1})
	steps -= 1
	return true


# --- telik az idő -------------------------------------------------------------

func advance() -> void:
	if over():
		return
	news = []
	var p := params()
	for i in ROUND_YEARS:
		var y := int(st["ev"]) + 1
		M.step(st, drivers(y), p)
		M.step(_base, {}, p)
		history.append([y, float(st["T"])])
		base_history.append([y, float(_base["T"])])
		for t in tips:
			if int(t["ev"]) == 0 and float(st["T"]) >= float(t["kuszob"]):
				t["ev"] = y
				news.append({"fajta": "billenes", "id": t["id"], "ev": y})
	round_i += 1
	steps = STEPS
	if over():
		return
	# megingás (játékszabály): egy vállalást tett csoport visszalépne; ha van a kezedben neki szóló, még nem hallott kártya, marad
	if rng.randf() < WAVER_CHANCE:
		var cand: Array = groups.filter(func(g: Dictionary) -> bool: return int(g["cel"]) > 0 and fraction(g, year()) > 0.0)
		if not cand.is_empty():
			var g: Dictionary = cand[rng.randi_range(0, cand.size() - 1)]
			var u := usable(g)
			if u.is_empty():
				var y := year()
				g["f0"] = fraction(g, y - 1)
				g["y0"] = y - 1
				g["cel"] = int(g["cel"]) + 10       # tíz évvel későbbre tolja a célját
				news.append({"fajta": "visszalepett", "csoport": g["id"], "cel": g["cel"]})
			else:
				g["hasznalt"].append(u[0])
				news.append({"fajta": "kitartott", "csoport": g["id"], "kartya": u[0]})
	# katasztrófa (játékszabály, a melegedéssel gyakoribb): az érintett csoportot utána könnyebb meggyőzni
	if rng.randf() < clampf(0.15 + 0.25 * (float(st["T"]) - M.T_START), 0.15, 0.6):
		var g2: Dictionary = groups[rng.randi_range(0, groups.size() - 1)]
		g2["konnyebb"] = true
		news.append({"fajta": "katasztrofa", "csoport": g2["id"], "mi": ["hoseg", "aszaly", "arviz", "tuz"][rng.randi_range(0, 3)]})


## A játék vége: a te Földed és a „ha semmi sem változik” Föld.
func result() -> Dictionary:
	var peak := 0.0
	for h in history:
		peak = maxf(peak, h[1])
	return {"T": float(history[-1][1]), "alap": float(base_history[-1][1]), "csucs": peak,
		"billenes": tips.filter(func(t: Dictionary) -> bool: return int(t["ev"]) > 0).size(),
		"tenger": M.sea_2100(float(history[-1][1])), "tenger_alap": M.sea_2100(float(base_history[-1][1])), "sens": sens}


# --- mentés -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "mag": seed_v, "sens": sens, "st": st, "alap": _base, "kor": round_i, "lepes": steps, "csoportok": groups, "kez": hand,
		"kivonas": cdr, "billenes": tips, "mult": history, "alap_mult": base_history, "hirek": news, "rng": str(rng.state)}


func from_dict(d: Dictionary) -> bool:
	if int(d.get("v", 0)) != SAVE_VERSION or not d.has("st") or not d.has("csoportok"):
		return false
	data = read_json("res://adatok/csoportok.json")
	seed_v = int(d["mag"]); sens = float(d["sens"]); st = d["st"]; _base = d["alap"]; round_i = int(d["kor"]); steps = int(d["lepes"])
	groups = d["csoportok"]; hand = d["kez"]; cdr = d["kivonas"]; tips = d["billenes"]; history = d["mult"]; base_history = d["alap_mult"]
	news = d.get("hirek", [])
	rest_share = float(data.get("tobbi_co2_resz", 0.0)); rest_ch4 = float(data.get("tobbi_ch4_resz", 0.0))
	rng.seed = seed_v
	rng.state = int(str(d.get("rng", "0")))
	st["ev"] = int(st["ev"]); _base["ev"] = int(_base["ev"])
	for g in groups:
		for k in ["fok", "cel", "y0", "metan"]:
			g[k] = int(g[k])
	for t in tips:
		t["ev"] = int(t["ev"])
	for c in cdr:
		c["ev"] = int(c["ev"])
	for h in history:
		h[0] = int(h[0])
	for h in base_history:
		h[0] = int(h[0])
	return true
