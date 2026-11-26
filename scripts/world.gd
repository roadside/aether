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
const SAVE_VERSION := 12                       # ha a szabályok vagy az adatok változnak, a régi mentés helyett új játék indul
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
var banned: Array = []           # az alacsonyabb kihívás-szinteken már felhasznált kártyák: itt nem kutathatók (játékszabály)
var cdr: Array = []              # [{"id", "gt", "ev"}]
var tips: Array = []             # billenőpontok: {"id", ..., "kuszob", "ev" (átlépés éve vagy 0)}
var history: Array = []          # [[év, T]] a megtörtént évek
var base_history: Array = []     # ugyanez „ha semmi sem változik” mellett, ugyanazon a Földön
var news: Array = []             # az utolsó öt év hírei: [{"fajta", ...}]
var cdr_total := 0.0             # az eddig kivont CO2 összesen (milliárd tonna)
var net_zero_year := 0           # az első év, amikor a világ több CO2-t von ki, mint amennyit kibocsát (0 = még nem)
var dilemma: Dictionary = {}      # függőben lévő döntés: {"fajta": "tamogatas"|"meghivas", "a": csoport, "b": csoport}
var summit_due := false          # most klímacsúcs van: egy kártyát megmutathatsz az egész világnak
var missions: Array = []         # a játék három küldetése: [{"id", "arg"}] (játékszabály; a Föld-kódból sorsoljuk)
var hajto: Array = []            # évenként a tényleges hajtóerők: [co2, kivonás, metán] (a „mi lett volna, ha” számításhoz)
var naplo: Array = []            # a játék fontos pillanatai a záró képernyőhöz: [{"ev", "fajta", ...}]
var threat: Dictionary = {}       # előre látható baj: {"csoport", "mi"} – a kör végén csap le (játékszabály)
var streak := 0                  # megállapodások ebben a körben (lendület: minden második visszaad egy lépést)
var streak_bonus := false        # a legutóbbi megállapodás lendületből lépést adott
var myth: Dictionary = {}         # terjedő tévhit: {"csoport", "kartya"} – a kártya a cáfolata (játékszabály)
var gentle := false              # az első játék: a nehezítések később és ritkábban jönnek (a felület állítja be)
var myths_seen: Array = []        # ebben a játékban már előkerült tévhitek (kártyaazonosítók)
var ai := false                  # ebben a játékban gép is lépett (ilyenkor a játék nem számít bele a gyűjteménybe és a jelvényekbe)
var challenge := 0               # kihívás-lépcső: 0–5, szintenként egy új nehezítés (játékszabály)
var data: Dictionary = {}


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Gyakori tévhitek, és melyik „Honnan tudjuk?” kártya felel rájuk (a mondatok a felületen: main.gd MYTH).
const MYTH_CARDS := ["napaktivitas", "kozmikus", "tcre", "felhok"]
const MYTH_CHANCE := 0.4
const MYTH_FROM_ROUND := 2
const CHALLENGE_MAX := 5
const CHALLENGE_SECONDS := 75.0                # 1. szint: rövidebb körök (a felület használja)
const CHALLENGE_SENS := 0.4                    # 2. szint: érzékenyebb Föld (a tudományos sávon belül)
const CHALLENGE_WAVER := 1.5                   # 4. szint: gyakoribb megingás


func new_game(seed_value: int = -1, steps_n: int = STEPS, challenge_n: int = 0) -> void:
	challenge = clampi(challenge_n, 0, CHALLENGE_MAX)
	max_steps = clampi(steps_n, 3, 5) - (1 if challenge >= 5 else 0)      # 5. szint: eggyel kevesebb lépés
	threat = {}
	myth = {}
	myths_seen = []
	gentle = false
	ai = false
	streak = 0
	streak_bonus = false
	data = read_json("res://adatok/csoportok.json")
	seed_v = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) % 1000000
	game_id = int(Time.get_unix_time_from_system() * 1000.0) % 2000000000
	rng.seed = seed_v
	sens = clampf(rng.randfn(0.0, 0.5), -1.0, 1.0)     # többnyire a sáv közepe táján, néha a szélén
	if challenge >= 2:
		sens = clampf(sens + CHALLENGE_SENS, -1.0, 1.0)
	st = M.new_state()
	M.step(st, {}, params())                            # 2025: a játék 2026 elején indul
	round_i = 0
	steps = max_steps
	hand = []
	cdr = []
	news = []
	naplo = []
	hajto = []
	_pick_missions()
	summit_due = false
	dilemma = {}
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
		d["maradek"] = 0        # az év, amikor a maradék kiváltása elindult (0 = még nem)
		d["nulla"] = 0          # az év, amikor elérte a nulla kibocsátást (0 = még nem)
		d["inog"] = false       # elbizonytalanodott: ha a kör végéig nem erősíted meg, megingik
		d["hasznalt"] = []      # az ennél a csoportnál már kijátszott kártyák
		d["konnyebb"] = false   # katasztrófa után egy kártyával kevesebb kell (játékszabály)
		d["makacs"] = challenge >= 3 and groups.size() == seed_v % 6     # 3. szint: egy csoportnak eggyel több kártya kell
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


## Maradék kibocsátás (játékszabály; alapja: Davis és mtsai 2018, Science, eaas9793: a cement, az acél, a repülés,
## a távolsági szállítás kibocsátását a legnehezebb megszüntetni). A vállalt cél a kibocsátás 94%-át viszi nullára;
## a maradék 6% (ez az arány játékszabály, a forrás nem ad egységes számot) addig megmarad, amíg ágazati
## kártyával ki nem váltod. Onnan tíz év alatt tűnik el.
const RESIDUAL := 0.06
const RESIDUAL_YEARS := 10
const RESIDUAL_CARDS := ["cement", "zold_acel", "repules", "szintetikus_kerozin", "hajozas", "teherauto", "hidrogen", "zold_ammonia",
	"kerodzok_metan", "tragya", "mutragya", "korforgasos", "kevesebb_igeny"]

## A csoport teljes kibocsátása a maihoz képest: a cél szerinti rész és a maradék együtt.
static func emission(g: Dictionary, y: int) -> float:
	var k := int(g.get("maradek", 0))
	var left := 1.0 if k == 0 else clampf(1.0 - float(y - k) / RESIDUAL_YEARS, 0.0, 1.0)
	return (1.0 - RESIDUAL) * fraction(g, y) + RESIDUAL * float(g.get("f_alap", 1.0)) * left


func residual_cards(g: Dictionary) -> Array:
	var out: Array = []
	for id in hand:
		if id in RESIDUAL_CARDS and not (id in g["hasznalt"]):
			out.append(id)
	return out


## A maradék kiváltása kérhető, ha a csoport már vállalt célt, és megnyílt a III. korszak.
func can_residual(g: Dictionary) -> bool:
	return int(g["cel"]) > 0 and int(g.get("maradek", 0)) == 0 and max_era() >= 3 and not over()


func cut_residual(g: Dictionary, card_id: String) -> bool:
	if steps <= 0 or not can_residual(g) or not (card_id in residual_cards(g)):
		return false
	g["maradek"] = year() - 1
	_spend(g, card_id)
	steps -= 1
	naplo.append({"ev": year(), "fajta": "maradek", "csoport": g["id"]})
	return true


func _avg_fraction(y: int) -> float:
	var s := 0.0
	var w := 0.0
	for g in groups:
		s += float(g["co2_resz"]) * emission(g, y)
		w += float(g["co2_resz"])
	return s / w if w > 0.0 else 1.0


func drivers(y: int) -> Dictionary:
	var f := 0.0
	var ch4 := 0.0
	var joined := 0.0
	var w := 0.0
	for g in groups:
		f += float(g["co2_resz"]) * emission(g, y)
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
		if c.has("gt2"):      # bővítés: a többlet a bővítés évétől ugyanúgy húsz év alatt fut fel
			rem += float(c["gt2"]) * clampf(float(y - int(c["ev2"])) / CDR_YEARS, 0.0, 1.0)
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
	var pool := Cards.open_in(theme, max_era(), hand + banned)
	if pool.size() < 3:      # ha a témakör új kártyái elfogytak, a korábbi szinteken használtak is visszajöhetnek, hogy mindig legyen miből választani
		for id in Cards.open_in(theme, max_era(), hand + pool):
			if pool.size() < 3:
				pool.append(id)
	var out: Array = []
	if theme == "ketseg" and not myth.is_empty() and not (str(myth["kartya"]) in hand):     # a terjedő tévhit cáfolata mindig kikutatható
		out.append(str(myth["kartya"]))
		pool.erase(str(myth["kartya"]))
	while out.size() < 3 and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


## A játékban felhasznált kártyák: amit a játékos bármelyik csoportnál kijátszott.
func used_cards() -> Array:
	var out: Array = []
	for g in groups:
		for id in g["hasznalt"]:
			if not (id in out):
				out.append(id)
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
## Vulkánkitörés (játékszabály): játékonként egyszer, a Föld-magból sorsolt kör elején kitör egy nagy vulkán.
## A kénes pára egy-két évre lehűti a Földet: a görbén átmeneti visszaesés látszik (a nagysága a valódi mintát követi:
## a Pinatubo 1991-es kitörése után a globális átlag 1991-ről 1992-re kb. 0,2 °C-ot esett, 1995-re visszatért – NASA GISTEMP v4).
## A melegedés hosszú távú menetét nem változtatja meg. Abban a körben minden csoportnak eggyel több kártya kell.
const VOLCANO_DIP := [0.2, 0.1]

func volcano_round() -> int:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 7919 + 13
	return r.randi_range(3, 10)


func volcano_now() -> bool:
	return not over() and round_i == volcano_round()


func cards_needed(g: Dictionary, target: int) -> int:
	var n := maxi(1, stage_of(target) - int(g["fok"])) + (1 if g.get("makacs", false) else 0) + (1 if myth_on(g) else 0) + (1 if volcano_now() else 0)
	return maxi(1, n - 1) if g["konnyebb"] else n


## A cél éve melyik fokozatnak felel meg most (1 = 40 év, … 4 = 15 év).
func stage_of(target: int) -> int:
	var k := SPEEDS.find(target - (year() - 1))
	if k >= 0:
		return k + 1
	var n := 0                 # köztes év (AI-ország a valós célévét vállalja): annyi fokozat, ahányat ez az év már elér
	for sp in SPEEDS:
		if int(sp) >= target - (year() - 1):
			n += 1
	return n


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


## A hőmérséklet várható útja (középérték), ha a csoport most ezt a célt vállalná: [[év, T], ...]
func preview_path(g: Dictionary, target: int) -> Array:
	var keep := {"f0": g["f0"], "y0": g["y0"], "cel": g["cel"]}
	var y := year()
	g["f0"] = fraction(g, y - 1) if int(g["cel"]) > 0 else float(g["f0"])
	g["y0"] = y - 1
	g["cel"] = target
	var rows: Array = forecast()["kozep"]
	for k in keep:
		g[k] = keep[k]
	return rows


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


## Egy kártya csak egy csoportnál hat (Zoltán döntése, 2026-11-24): amivel megállapodtál valakivel (cél vagy metán),
## azt a többi csoport is hallottnak veszi. A megerősítés, a felkészítés és a klímacsúcs csak annál számít, aki hallotta.
const CARD_ONCE := true


func _spend(g: Dictionary, id: String) -> void:
	for h in (groups if CARD_ONCE else [g]):
		if not (id in h["hasznalt"]):
			h["hasznalt"].append(id)


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
		_spend(g, id)
	steps -= 1
	_momentum()
	naplo.append({"ev": y, "fajta": "cel", "csoport": g["id"], "cel": target})
	return true


## Lendület (játékszabály): egy körön belül minden második megállapodás visszaad egy lépést.
func _momentum() -> void:
	streak += 1
	streak_bonus = streak % 2 == 0
	if streak_bonus:
		steps += 1
		naplo.append({"ev": year(), "fajta": "lendulet"})


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
		_spend(g, id)
	steps -= 1
	_momentum()
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


## Bővítés (játékszabály): ami legalább tíz éve fut, azt egyszer a fenntartható sáv közepéig lehet bővíteni.
## A sáv maga valódi (Fuss és mtsai 2018); a tetejéig nem megyünk, mert a programok egymás elől veszik el a földet.
const CDR_GROW_AFTER := 10

func cdr_growable() -> Array:
	var out: Array = []
	for c in cdr:
		if not c.has("gt2") and year() - 1 - int(c["ev"]) >= CDR_GROW_AFTER:
			out.append(str(c["id"]))
	return out


func grow_cdr(id: String) -> bool:
	if steps <= 0 or over() or not (id in cdr_growable()):
		return false
	for c in cdr:
		if c["id"] == id:
			c["gt2"] = (float(CDR[id][0]) + float(CDR[id][1])) * 0.5 - float(CDR[id][0])
			c["ev2"] = year() - 1
	steps -= 1
	naplo.append({"ev": year(), "fajta": "kivonas", "id": id, "bov": true})
	return true


# --- telik az idő -------------------------------------------------------------

func advance() -> void:
	if over():
		return
	news = []
	var p := params()
	for i in ROUND_YEARS:
		var y := int(st["ev"]) + 1
		var dy := drivers(y)
		hajto.append([float(dy["co2"]), float(dy["cdr"]), float(dy["ch4"])])
		M.step(st, dy, p)
		M.step(_base, {}, p)
		var dip: float = float(VOLCANO_DIP[i]) if (round_i == volcano_round() and i < VOLCANO_DIP.size()) else 0.0      # a kitörés utáni két év
		history.append([y, float(st["T"]) - dip])
		base_history.append([y, float(_base["T"]) - dip])
		cdr_total += float(drivers(y)["cdr"])
		for g in groups:
			g["megsporolt"] = float(g.get("megsporolt", 0.0)) + (1.0 - emission(g, y)) * float(g["co2_resz"]) * M.E_CO2_NOW
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
	streak = 0
	streak_bonus = false
	if over():
		return
	summit_due = round_i in SUMMIT_ROUNDS
	_roll_dilemma()
	if round_i == volcano_round():
		news.append({"fajta": "vulkan"})
		naplo.append({"ev": year(), "fajta": "vulkan"})
	elif round_i == volcano_round() + 1:
		news.append({"fajta": "vulkan_vege"})
	# megingás (játékszabály): aki az előző kör végén elbizonytalanodott, és nem erősítetted meg, visszalép:
	# tíz évvel későbbre tolja a célját (legfeljebb 2090-ig, hogy a vállalás valódi maradjon), és egy fokozattal visszaesik
	var just_wavered: Array = []
	for g in groups:
		if g.get("inog", false):
			g["inog"] = false
			if int(g["cel"]) > 0 and fraction(g, year()) > 0.0 and not g.get("felkeszult", false):
				just_wavered.append(g["id"])
				var y := year()
				g["f0"] = fraction(g, y - 1)
				g["y0"] = y - 1
				g["cel"] = mini(int(g["cel"]) + 10, maxi(int(g["cel"]), 2090))
				g["fok"] = maxi(1, int(g["fok"]) - 1)
				news.append({"fajta": "visszalepett", "csoport": g["id"], "cel": g["cel"]})
				naplo.append({"ev": y, "fajta": "visszalepett", "csoport": g["id"], "cel": g["cel"]})
	# új elbizonytalanodás: az esély a játék során nő (30% → 60%); a felkészült csoport nem inog meg
	if round_i < ROUNDS - 1 and rng.randf() < WAVER_CHANCE * (CHALLENGE_WAVER if challenge >= 4 else 1.0) * (1.0 + float(round_i) / float(ROUNDS)) and not (gentle and round_i < 3):
		var cand: Array = groups.filter(func(g: Dictionary) -> bool:      # aki most ingott meg, az nem bizonytalanodik el rögtön újra
			return int(g["cel"]) > 0 and fraction(g, year()) > 0.0 and not g.get("felkeszult", false) and not (g["id"] in just_wavered))
		if not cand.is_empty():
			var g: Dictionary = cand[rng.randi_range(0, cand.size() - 1)]
			g["inog"] = true
			news.append({"fajta": "inog", "csoport": g["id"]})
	# terjedő tévhit (játékszabály): amíg nem cáfolod meg, a csoport minden kör végén elbizonytalanodik
	if not myth.is_empty():
		var gm := group(str(myth["csoport"]))
		if not gm.is_empty() and int(gm["cel"]) > 0 and fraction(gm, year()) > 0.0 and not gm.get("felkeszult", false) and not gm.get("inog", false) and not (gm["id"] in just_wavered):
			gm["inog"] = true
			news.append({"fajta": "inog", "csoport": gm["id"]})
	elif round_i >= MYTH_FROM_ROUND + (2 if gentle else 0) and round_i < ROUNDS - 1 and rng.randf() < MYTH_CHANCE:
		var left: Array = MYTH_CARDS.filter(func(id: String) -> bool: return not (id in myths_seen))
		if not left.is_empty():
			var mid: String = left[rng.randi_range(0, left.size() - 1)]
			var mg: Dictionary = groups[rng.randi_range(0, groups.size() - 1)]
			if fraction(mg, year()) > 0.0:
				myth = {"csoport": mg["id"], "kartya": mid}
				myths_seen.append(mid)
				news.append({"fajta": "tevhit", "csoport": mg["id"], "kartya": mid})
	# aki elérte a nullát, segít egy másiknak (játékszabály): azt a csoportot most könnyebb meggyőzni
	for n in news.duplicate():
		if n["fajta"] == "nulla":
			var need: Array = groups.filter(func(g: Dictionary) -> bool:
				return g["id"] != n["csoport"] and not g["konnyebb"] and not targets_for(g).is_empty())
			if not need.is_empty():
				var gh: Dictionary = need[rng.randi_range(0, need.size() - 1)]
				gh["konnyebb"] = true
				news.append({"fajta": "segit", "csoport": n["csoport"], "kinek": gh["id"]})
	for g in groups:
		g["baj"] = ""
	# az előre látott baj most csap le (játékszabály): utána könnyebb meggyőzni a csoportot;
	# ha nem készült fel, a mentés elvisz egy lépést ebből a körből
	if not threat.is_empty():
		var g2 := group(str(threat["csoport"]))
		if not g2.is_empty():
			g2["konnyebb"] = true
			var ready: bool = g2.get("felkeszult", false)
			if not ready:
				steps = maxi(1, steps - 1)
				g2["baj"] = threat["mi"]          # ebben a körben a kártyájuk tájképe is a bajt mutatja
			news.append({"fajta": "katasztrofa", "csoport": g2["id"], "mi": threat["mi"], "lepes": not ready})
			naplo.append({"ev": year(), "fajta": "baj", "csoport": g2["id"], "mi": threat["mi"], "vedve": ready})
		threat = {}
	# a következő baj már most látszik (a melegedéssel gyakoribb), fel lehet rá készülni
	if round_i < ROUNDS - 1 and rng.randf() < clampf(0.15 + 0.25 * (float(st["T"]) - M.T_START), 0.15, 0.6) and not (gentle and round_i < 2):
		var open: Array = groups.filter(func(g: Dictionary) -> bool: return not g.get("felkeszult", false))
		var kind: String = ["hoseg", "aszaly", "arviz", "tuz"][rng.randi_range(0, 3)]
		if not open.is_empty():       # aki már felkészült, azt nem fenyegeti újabb baj
			threat = {"csoport": open[rng.randi_range(0, open.size() - 1)]["id"], "mi": kind}


## A játék vége: a te Földed és a „ha semmi sem változik” Föld.
func result() -> Dictionary:
	var peak := 0.0
	for h in history:
		peak = maxf(peak, h[1])
	return {"T": float(history[-1][1]), "alap": float(base_history[-1][1]), "csucs": peak,
		"billenes": tips.filter(func(t: Dictionary) -> bool: return int(t["ev"]) > 0).size(),
		"tenger": M.sea_2100(float(history[-1][1])), "tenger_alap": M.sea_2100(float(base_history[-1][1])), "sens": sens}


# --- döntési helyzetek (játékszabály) -------------------------------------------

const DILEMMA_CHANCE := 0.3


## Néhány kör elején döntened kell (a Föld-kódból sorsolva, külön véletlenforrásból).
func _roll_dilemma() -> void:
	dilemma = {}
	if round_i < 1 or round_i >= ROUNDS - 1 or summit_due:
		return
	var dr := RandomNumberGenerator.new()
	dr.seed = seed_v * 104729 + round_i * 31 + 7
	if dr.randf() >= DILEMMA_CHANCE:
		return
	var open_g: Array = groups.filter(func(g: Dictionary) -> bool: return not g["konnyebb"] and not targets_for(g).is_empty())
	var unprep: Array = groups.filter(func(g: Dictionary) -> bool: return not g.get("felkeszult", false))
	var known: Array = hand.filter(func(id: String) -> bool: return not Cards.key_number(id).is_empty())
	var kind := dr.randf()
	if kind < 0.34 and not known.is_empty() and hand.size() >= 3:
		# tudáspróba: melyik kártyádon áll ez a mondat? (a mondat a kártya lektorált kulcsszáma)
		var right: String = known[dr.randi_range(0, known.size() - 1)]
		var others: Array = hand.filter(func(id: String) -> bool: return id != right)
		var opts: Array = [right]
		while opts.size() < 3:
			opts.append(others.pop_at(dr.randi_range(0, others.size() - 1)))
		for i in range(opts.size() - 1, 0, -1):
			var j := dr.randi_range(0, i)
			var tmp: String = opts[i]
			opts[i] = opts[j]
			opts[j] = tmp
		dilemma = {"fajta": "kviz", "id": right, "valasz": opts}
	elif kind < 0.67 and open_g.size() >= 2:
		var a: Dictionary = open_g.pop_at(dr.randi_range(0, open_g.size() - 1))
		var b: Dictionary = open_g[dr.randi_range(0, open_g.size() - 1)]
		dilemma = {"fajta": "meghivas", "a": a["id"], "b": b["id"]}
	elif not unprep.is_empty():
		dilemma = {"fajta": "tamogatas", "a": unprep[dr.randi_range(0, unprep.size() - 1)]["id"]}


## choice: a választott lehetőség sorszáma. Támogatás: 0 = eggyel több lépés, 1 = a megnevezett csoport felkészül.
## Meghívás: a választott csoportot most eggyel kevesebb kártyával is meg lehet győzni.
## Tudáspróba: a jó válasz eggyel több lépést ad. Vissza: igaz, ha a választás „sikerült” (a próbánál: jó válasz).
## Terjed-e most tévhit ennél a csoportnál? Amíg terjed, eggyel több kártya kell a meggyőzésükhöz.
func myth_on(g: Dictionary) -> bool:
	return not myth.is_empty() and str(myth.get("csoport", "")) == str(g["id"])


## A tévhit cáfolata: a hozzá tartozó kártyával, egy lépésért. Utána a csoportot könnyebb meggyőzni.
func refute(g: Dictionary) -> bool:
	if steps <= 0 or over() or not myth_on(g) or not (str(myth["kartya"]) in hand):
		return false
	steps -= 1
	naplo.append({"ev": year(), "fajta": "cafolat", "csoport": g["id"], "kartya": myth["kartya"]})
	myth = {}
	g["konnyebb"] = true
	g["inog"] = false
	return true


## Pillanat a Földön (játékszabály): a csoport most figyel, eggyel kevesebb kártya is elég neki ebben a körben.
func moment_attention(id: String) -> bool:
	var g := group(id)
	if g.is_empty() or g["konnyebb"] or over():
		return false
	g["konnyebb"] = true
	return true


## Pillanat a Földön (játékszabály): új felfedezés, ebben a körben eggyel több lépés.
func moment_discovery() -> void:
	if not over():
		steps += 1


func resolve_dilemma(choice: int) -> bool:
	if dilemma.is_empty():
		return false
	if dilemma["fajta"] == "kviz":
		var ok: bool = choice >= 0 and choice < (dilemma["valasz"] as Array).size() and dilemma["valasz"][choice] == dilemma["id"]
		if ok:
			steps += 1
		dilemma = {}
		return ok
	if dilemma["fajta"] == "tamogatas":
		if choice == 0:
			steps += 1
		else:
			var g := group(str(dilemma["a"]))
			if not g.is_empty():
				g["felkeszult"] = true
				g["inog"] = false
				naplo.append({"ev": year(), "fajta": "felkeszules", "csoport": g["id"]})
	else:
		var g2 := group(str(dilemma["a" if choice == 0 else "b"]))
		if not g2.is_empty():
			g2["konnyebb"] = true
	dilemma = {}
	return true


# --- küldetések (játékszabály) --------------------------------------------------

const MISSION_KINDS := ["korai", "metan3", "kivonas2", "tema", "felkeszul3", "nulla2065", "csucs3", "kartya20", "lendulet2"]


## Három különböző küldetés a Föld-kódból (külön véletlenforrásból, hogy a játék menete ne változzon tőle).
func _pick_missions() -> void:
	var mr := RandomNumberGenerator.new()
	mr.seed = seed_v * 7919 + 13
	var pool := MISSION_KINDS.duplicate()
	var ids: Array = (data.get("csoportok", []) as Array).map(func(g: Dictionary) -> String: return str(g["id"]))
	missions = []
	while missions.size() < 3 and not pool.is_empty():
		var k: String = pool.pop_at(mr.randi_range(0, pool.size() - 1))
		var arg := ""
		if k == "korai" and not ids.is_empty():
			arg = ids[mr.randi_range(0, ids.size() - 1)]
		elif k == "tema":
			var ths: Array = Cards.talk_themes()
			arg = ths[mr.randi_range(0, ths.size() - 1)]
		missions.append({"id": k, "arg": arg})


func mission_done(m: Dictionary) -> bool:
	var arg := str(m.get("arg", ""))
	match str(m["id"]):
		"korai":
			return naplo.any(func(e: Dictionary) -> bool: return e["fajta"] == "cel" and e.get("csoport", "") == arg and int(e["ev"]) <= 2040)
		"metan3":
			return naplo.filter(func(e: Dictionary) -> bool: return e["fajta"] == "metan" and int(e["ev"]) <= 2050).size() >= 3
		"kivonas2":
			return cdr.size() >= 2
		"tema":
			return hand.filter(func(id: String) -> bool: return Cards.theme_of(id) == arg).size() >= 5
		"felkeszul3":
			return groups.filter(func(g: Dictionary) -> bool: return g.get("felkeszult", false)).size() >= 3
		"nulla2065":
			return groups.any(func(g: Dictionary) -> bool: return int(g.get("nulla", 0)) > 0 and int(g["nulla"]) <= 2065)
		"csucs3":
			return naplo.any(func(e: Dictionary) -> bool: return e["fajta"] == "csucs" and int(e.get("db", 0)) >= 3)
		"kartya20":
			return hand.size() >= 20
		"lendulet2":
			return naplo.filter(func(e: Dictionary) -> bool: return e["fajta"] == "lendulet").size() >= 2
	return false


func missions_done() -> int:
	return missions.filter(mission_done).size()


## Mi lett volna, ha minden vállalás és kivonás `delay` évvel később (vagy korábban) történik?
## Ugyanaz a modell, ugyanaz az érzékenység; csak a ténylegesen megtörtént kibocsátási út tolódik el.
## Vissza: a 2100-as hőmérséklet, vagy -1, ha nincs meg a teljes út (régi mentés).
func what_if(delay: int) -> float:
	var n := M.END_YEAR - M.START_YEAR
	if hajto.size() < n:
		return -1.0
	var s := M.new_state()
	var p := params()
	M.step(s, {}, p)
	for i in n:
		var j := i - delay
		var d := {}
		if j >= 0:
			var h: Array = hajto[mini(j, n - 1)]
			d = {"co2": float(h[0]), "cdr": float(h[1]), "ch4": float(h[2])}
		M.step(s, d, p)
	return float(s["T"])


# --- mentés -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "mag": seed_v, "jatek": game_id, "sens": sens, "st": st, "alap": _base, "kor": round_i, "lepes": steps, "max_lepes": max_steps, "csoportok": groups, "kez": hand,
		"kivonas": cdr, "billenes": tips, "mult": history, "alap_mult": base_history, "hirek": news, "naplo": naplo, "hajto": hajto, "kuldetes": missions, "csucs": summit_due, "dontes": dilemma, "vilag_nulla": net_zero_year, "kivont": cdr_total, "rng": str(rng.state),
		"veszely": threat, "sorozat": streak, "kihivas": challenge, "tevhit": myth, "tevhitek": myths_seen, "szelid": gentle, "gep": ai, "tiltott": banned}


func from_dict(d: Dictionary) -> bool:
	if int(d.get("v", 0)) != SAVE_VERSION or not d.has("st") or not d.has("csoportok"):
		return false
	data = read_json("res://adatok/csoportok.json")
	seed_v = int(d["mag"]); game_id = int(d.get("jatek", 0)); sens = float(d["sens"]); st = d["st"]; _base = d["alap"]; round_i = int(d["kor"]); steps = int(d["lepes"]); max_steps = int(d.get("max_lepes", STEPS))
	groups = d["csoportok"]; hand = d["kez"]; cdr = d["kivonas"]; tips = d["billenes"]; history = d["mult"]; base_history = d["alap_mult"]
	news = d.get("hirek", [])
	banned = d.get("tiltott", [])
	summit_due = bool(d.get("csucs", false))
	dilemma = d.get("dontes", {})
	net_zero_year = int(d.get("vilag_nulla", 0))
	cdr_total = float(d.get("kivont", 0.0))
	naplo = d.get("naplo", [])
	hajto = d.get("hajto", [])
	missions = d.get("kuldetes", [])
	threat = d.get("veszely", {})
	myth = d.get("tevhit", {})
	myths_seen = d.get("tevhitek", [])
	gentle = bool(d.get("szelid", false))
	ai = bool(d.get("gep", false))
	streak = int(d.get("sorozat", 0))
	streak_bonus = false
	challenge = int(d.get("kihivas", 0))
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
