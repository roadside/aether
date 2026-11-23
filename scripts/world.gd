extends RefCounted
## A játék állapota és szabályai (felület nélkül, így magában is tesztelhető).
##
## Egy kör 5 év, 2026-tól 2100-ig 15 kör. Körönként négy lépésed van: kutatás, tárgyalás, CO2-kivonás.
## VALÓDI: a klímamodell és a számai (model.gd), a csoportok kibocsátása és a billenőpontok sávjai
## (adatok/*.json, forrással), a kártyák (temak/*.txt), a kivonás határai (archivum/*.json).
## JÁTÉKSZABÁLY: a tárgyalás menete, a csoportok aggodalmai, a megingás, a lépések száma.

const M := preload("res://scripts/model.gd")
const Cards := preload("res://scripts/cards.gd")

const ROUNDS := 15
const ROUND_YEARS := 5
const STEPS := 4
const SPEEDS := [40, 30, 20, 15]               # ennyi év alatt állhat át nullára egy csoport, egyre merészebben (játékszabály)
const SUMMIT_ROUNDS := [3, 8]                    # 2041 és 2066 elején klímacsúcs (játékszabály)
const SUMMIT_YEARS := 5                        # ennyi évvel hozza előbbre a célját, akit a csúcson megszólítasz
const METHANE_CUT := 0.30                      # a Globális Metánvállalás mértéke: −30% (10 év alatt)
const METHANE_YEARS := 10
const CDR_YEARS := 20                          # a kivonás ennyi év alatt fut fel (a modell korábbi szabálya)
const SAVE_VERSION := 11                       # ha a szabályok vagy az adatok változnak, a régi mentés helyett új játék indul
const WAVER_CHANCE := 0.30                     # körönként ekkora eséllyel inog meg egy csoport (játékszabály)
## CO2-kivonási programok: kártya -> [a fenntartható sáv alja, teteje] GtCO2/év 2050-re
## (Fuss és mtsai 2018, Environ. Res. Lett. 13 063002; az archívum ellenőrzött idézetei szerint).
const CDR := {"erdo": [0.5, 3.6], "bioszen": [0.5, 2.0], "kozet": [2.0, 4.0], "levegoszures": [0.5, 5.0], "novenyi_energia": [0.5, 5.0]}

var seed_v := 0
var game_id := 0                 # ennek a játszmának az egyedi száma (ugyanaz a Föld-kód többször is játszható)
var sens := 0.0                  # a Föld rejtett érzékenysége (−1…+1), a végén derül ki
var rng := RandomNumberGenerator.new()
var st: Dictionary = {}
var round_i := 0                 # 0…15 (15 = vége)
var steps := STEPS
var max_steps := STEPS           # lépés körönként: 5 könnyű, 4 közepes, 3 nehéz fokozaton (játékszabály)
var groups: Array = []
var rest_share := 0.0            # a világ többi részének CO2-részesedése: a hat csoport átlagát követi (játékszabály)
var rest_ch4 := 0.0
var hand: Array = []             # kikutatott kártyák azonosítói
var cdr: Array = []              # [{"id", "gt", "ev"}]
var tips: Array = []             # billenőpontok: {"id", ..., "kuszob", "ev" (átlépés éve vagy 0)}
var history: Array = []          # [[év, T]] a megtörtént évek
var base_history: Array = []     # ugyanez „ha semmi sem változik” mellett, ugyanazon a Földön
var news: Array = []             # az utolsó öt év hírei: [{"fajta", ...}]
var cdr_total := 0.0             # az eddig kivont CO2 összesen (milliárd tonna)
var net_zero_year := 0           # az első év, amikor a világ több CO2-t von ki, mint amennyit kibocsát (0 = még nem)
var summit_due := false          # most klímacsúcs van: egy kártyát megmutathatsz az egész világnak
var naplo: Array = []            # a játék fontos pillanatai a záró képernyőhöz: [{"ev", "fajta", ...}]
var data: Dictionary = {}


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func new_game(seed_value: int = -1, steps_n: int = STEPS) -> void:
	max_steps = clampi(steps_n, 3, 5)
	data = read_json("res://adatok/csoportok.json")
	seed_v = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) % 1000000
	game_id = int(Time.get_unix_time_from_system() * 1000.0) % 2000000000
	rng.seed = seed_v
	sens = clampf(rng.randfn(0.0, 0.5), -1.0, 1.0)     # többnyire a sáv közepe táján, néha a szélén
	st = M.new_state()
	M.step(st, {}, params())                            # 2025: a játék 2026 elején indul
	round_i = 0
	steps = max_steps
	hand = []
	cdr = []
	news = []
	naplo = []
	summit_due = false
	net_zero_year = 0
	cdr_total = 0.0
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
		d["felkeszult"] = false # felkészült a bajra: nem inog meg
		d["megsporolt"] = 0.0   # ennyi CO2-t nem bocsátott ki eddig a „ha semmi sem változik” úthoz képest (milliárd tonna)
		d["nulla"] = 0          # az év, amikor elérte a nulla kibocsátást (0 = még nem)
		d["inog"] = false       # elbizonytalanodott: ha a kör végéig nem erősíted meg, megingik
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


## A csoport következő vállalható céljai (évek): mostantól 40, 30, 20 vagy 15 év alatt nullára.
## Csak az kérhető, ami a mostani vállalásánál merészebb fokozat, és korábbi évet ad.
func targets_for(g: Dictionary) -> Array:
	var out: Array = []
	if fraction(g, year() - 1) <= 0.0:
		return out
	for i in SPEEDS.size():
		var t: int = year() - 1 + int(SPEEDS[i])
		if i + 1 > int(g["fok"]) and (int(g["cel"]) == 0 or t < int(g["cel"])):
			out.append(t)
	return out


## Hány kártya kell a célhoz: fokozatonként egy (40 → 30 → 20 → 15 év); katasztrófa után eggyel kevesebb (legalább 1).
func cards_needed(g: Dictionary, target: int) -> int:
	var n := maxi(1, stage_of(target) - int(g["fok"]))
	return maxi(1, n - 1) if g["konnyebb"] else n


## A cél éve melyik fokozatnak felel meg most (1 = 40 év, … 4 = 15 év).
func stage_of(target: int) -> int:
	return SPEEDS.find(target - (year() - 1)) + 1


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


## A csoport kibocsátásának útja mostantól 2100-ig: [[év, arány]] (1 = a mai szint).
## target > 0: úgy, mintha most ezt a célt vállalná.
func path(g: Dictionary, target: int = 0) -> Array:
	var keep := {"f0": g["f0"], "y0": g["y0"], "cel": g["cel"]}
	var y := year()
	if target > 0:
		g["f0"] = fraction(g, y - 1) if int(g["cel"]) > 0 else float(g["f0"])
		g["y0"] = y - 1
		g["cel"] = target
	var out: Array = []
	for yy in range(mini(y - 1, 2100), 2101):
		out.append([yy, fraction(g, yy)])
	for k in keep:
		g[k] = keep[k]
	return out


## Van-e most olyan kérés, amihez megvan a kártyád?
func can_convince(g: Dictionary) -> bool:
	if steps <= 0 or over():
		return false
	var n := usable(g).size()
	if g.get("inog", false) and n > 0:
		return true
	for t in targets_for(g):
		if n >= cards_needed(g, t):
			return true
	return int(g["metan"]) == 0 and methane_cards(g).size() >= methane_needed(g)


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
	g["fok"] = stage_of(target)
	g["y0"] = y - 1
	g["cel"] = target
	g["konnyebb"] = false
	g["inog"] = false          # az új egyezség meg is erősíti őket
	for id in played:
		g["hasznalt"].append(id)
	steps -= 1
	naplo.append({"ev": y, "fajta": "cel", "csoport": g["id"], "cel": target})
	return true


func methane_cards(g: Dictionary) -> Array:
	var out: Array = []
	for id in hand:
		if id in Cards.METHANE and not (id in g["hasznalt"]):
			out.append(id)
	return out


## Felkészülés a bajra (játékszabály): egy Tenger és part, Egészség vagy Élelem kártyával segítesz egy csoportnak.
## Aki felkészült, megbízik benned: többé nem inog meg.
const PREPARE_THEMES := ["part", "egeszseg", "elelem"]

func prepare_cards(g: Dictionary) -> Array:
	var out: Array = []
	for id in hand:
		if Cards.theme_of(id) in PREPARE_THEMES and not (id in g["hasznalt"]):
			out.append(id)
	return out


func prepare(g: Dictionary, card_id: String) -> bool:
	if steps <= 0 or g.get("felkeszult", false) or not (card_id in prepare_cards(g)):
		return false
	g["felkeszult"] = true
	g["inog"] = false
	g["hasznalt"].append(card_id)
	steps -= 1
	naplo.append({"ev": year(), "fajta": "felkeszules", "csoport": g["id"]})
	return true


## Klímacsúcs (játékszabály): egy kártyát az egész világnak megmutatsz. Aki már vállalt célt, és a kártya
## az ő aggodalmára felel (és még nem hallotta), öt évvel előbbre hozza a célját. Nem kerül lépésbe.
func summit_listeners(card_id: String) -> Array:
	var th := Cards.theme_of(card_id)
	var y := year()
	return groups.filter(func(g: Dictionary) -> bool:
		return th in g["felelmek"] and not (card_id in g["hasznalt"]) and int(g["cel"]) > 0 \
			and fraction(g, y - 1) > 0.0 and int(g["cel"]) - SUMMIT_YEARS > y)


func summit(card_id: String) -> Array:
	var out: Array = []
	if not summit_due or not (card_id in hand):
		return out
	var y := year()
	for g in summit_listeners(card_id):
		g["f0"] = fraction(g, y - 1)
		g["y0"] = y - 1
		g["cel"] = int(g["cel"]) - SUMMIT_YEARS
		g["hasznalt"].append(card_id)
		out.append(g["id"])
	summit_due = false
	naplo.append({"ev": y, "fajta": "csucs", "db": out.size()})
	return out


func skip_summit() -> void:
	summit_due = false


## Megerősítés (játékszabály): az elbizonytalanodott csoportot egy neki szóló, még nem hallott kártyával megtarthatod.
func reassure(g: Dictionary, card_id: String) -> bool:
	if steps <= 0 or not g.get("inog", false) or not (card_id in usable(g)):
		return false
	g["inog"] = false
	g["hasznalt"].append(card_id)
	steps -= 1
	return true


## Hány metánkártya kell: 1, de 2 azoknál, akik a valóságban nem csatlakoztak a Globális Metánvállaláshoz (játékszabály, valódi tényre építve).
func methane_needed(g: Dictionary) -> int:
	return 1 if bool(g.get("metan_valodi", true)) else 2


func pledge_methane(g: Dictionary, played: Variant) -> bool:
	var ids: Array = played if typeof(played) == TYPE_ARRAY else [played]
	if steps <= 0 or int(g["metan"]) > 0 or ids.size() < methane_needed(g):
		return false
	for id in ids:
		if not (id in methane_cards(g)):
			return false
	g["metan"] = year() - 1
	for id in ids:
		g["hasznalt"].append(id)
	steps -= 1
	naplo.append({"ev": year(), "fajta": "metan", "csoport": g["id"]})
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
	naplo.append({"ev": year(), "fajta": "kivonas", "id": id})
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
		cdr_total += float(drivers(y)["cdr"])
		for g in groups:
			g["megsporolt"] = float(g.get("megsporolt", 0.0)) + (1.0 - fraction(g, y)) * float(g["co2_resz"]) * M.E_CO2_NOW
		for g in groups:              # jó hír: egy csoport elérte a nullát
			if int(g["cel"]) > 0 and int(g.get("nulla", 0)) == 0 and fraction(g, y) <= 0.0:
				g["nulla"] = y
				news.append({"fajta": "nulla", "csoport": g["id"], "ev": y})
				naplo.append({"ev": y, "fajta": "nulla", "csoport": g["id"]})
		if net_zero_year == 0 and net_ratio(y) <= 0.0:
			net_zero_year = y
			news.append({"fajta": "vilag_nulla", "ev": y})
			naplo.append({"ev": y, "fajta": "vilag_nulla"})
		for t in tips:
			if int(t["ev"]) == 0 and float(st["T"]) >= float(t["kuszob"]):
				t["ev"] = y
				news.append({"fajta": "billenes", "id": t["id"], "ev": y})
				naplo.append({"ev": y, "fajta": "billenes", "id": t["id"]})
	round_i += 1
	steps = max_steps
	if over():
		return
	summit_due = round_i in SUMMIT_ROUNDS
	# megingás (játékszabály): aki az előző kör végén elbizonytalanodott, és nem erősítetted meg, visszalép:
	# tíz évvel későbbre tolja a célját (legfeljebb 2100-ig), és egy fokozattal visszaesik
	var just_wavered: Array = []
	for g in groups:
		if g.get("inog", false):
			g["inog"] = false
			if int(g["cel"]) > 0 and fraction(g, year()) > 0.0 and not g.get("felkeszult", false):
				just_wavered.append(g["id"])
				var y := year()
				g["f0"] = fraction(g, y - 1)
				g["y0"] = y - 1
				g["cel"] = mini(int(g["cel"]) + 10, 2100)
				g["fok"] = maxi(1, int(g["fok"]) - 1)
				news.append({"fajta": "visszalepett", "csoport": g["id"], "cel": g["cel"]})
				naplo.append({"ev": y, "fajta": "visszalepett", "csoport": g["id"], "cel": g["cel"]})
	# új elbizonytalanodás: az esély a játék során nő (30% → 60%); a felkészült csoport nem inog meg
	if round_i < ROUNDS - 1 and rng.randf() < WAVER_CHANCE * (1.0 + float(round_i) / float(ROUNDS)):
		var cand: Array = groups.filter(func(g: Dictionary) -> bool:      # aki most ingott meg, az nem bizonytalanodik el rögtön újra
			return int(g["cel"]) > 0 and fraction(g, year()) > 0.0 and not g.get("felkeszult", false) and not (g["id"] in just_wavered))
		if not cand.is_empty():
			var g: Dictionary = cand[rng.randi_range(0, cand.size() - 1)]
			g["inog"] = true
			news.append({"fajta": "inog", "csoport": g["id"]})
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
	return {"v": SAVE_VERSION, "mag": seed_v, "jatek": game_id, "sens": sens, "st": st, "alap": _base, "kor": round_i, "lepes": steps, "max_lepes": max_steps, "csoportok": groups, "kez": hand,
		"kivonas": cdr, "billenes": tips, "mult": history, "alap_mult": base_history, "hirek": news, "naplo": naplo, "csucs": summit_due, "vilag_nulla": net_zero_year, "kivont": cdr_total, "rng": str(rng.state)}


func from_dict(d: Dictionary) -> bool:
	if int(d.get("v", 0)) != SAVE_VERSION or not d.has("st") or not d.has("csoportok"):
		return false
	data = read_json("res://adatok/csoportok.json")
	seed_v = int(d["mag"]); game_id = int(d.get("jatek", 0)); sens = float(d["sens"]); st = d["st"]; _base = d["alap"]; round_i = int(d["kor"]); steps = int(d["lepes"]); max_steps = int(d.get("max_lepes", STEPS))
	groups = d["csoportok"]; hand = d["kez"]; cdr = d["kivonas"]; tips = d["billenes"]; history = d["mult"]; base_history = d["alap_mult"]
	news = d.get("hirek", [])
	summit_due = bool(d.get("csucs", false))
	net_zero_year = int(d.get("vilag_nulla", 0))
	cdr_total = float(d.get("kivont", 0.0))
	naplo = d.get("naplo", [])
	for e in naplo:
		e["ev"] = int(e["ev"])
		if e.has("cel"):
			e["cel"] = int(e["cel"])
	rest_share = float(data.get("tobbi_co2_resz", 0.0)); rest_ch4 = float(data.get("tobbi_ch4_resz", 0.0))
	rng.seed = seed_v
	rng.state = int(str(d.get("rng", "0")))
	st["ev"] = int(st["ev"]); _base["ev"] = int(_base["ev"])
	for g in groups:
		for k in ["fok", "cel", "y0", "metan"]:
			g[k] = int(g[k])
		g["nulla"] = int(g.get("nulla", 0))
	for t in tips:
		t["ev"] = int(t["ev"])
	for c in cdr:
		c["ev"] = int(c["ev"])
	for h in history:
		h[0] = int(h[0])
	for h in base_history:
		h[0] = int(h[0])
	return true
