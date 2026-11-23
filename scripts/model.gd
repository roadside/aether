extends RefCounted
## AETHER-mini: egyszerű, átlátható klímamodell a játék saját kódjában (Python nélkül).
## Oktatási / játékmodell, NEM kutatási minőségű előrejelzés: egy döntés IRÁNYÁT és NAGYSÁGRENDJÉT mutatja.
## Ugyanaz a számítás, mint a korábbi aether_lab/climate.py (a tools/modell_teszt.gd ahhoz méri).
##
##  1. CO2: a melegedés arányos az összes eddigi nettó CO2-kibocsátással (TCRE, IPCC AR6 WG1 SPM D.1.1).
##     Nulla nettó kibocsátás után a hőmérséklet nagyjából megáll (ZEC ~ 0, AR6 WG1 5.5.2).
##  2. Metán: a MAI szinthez képesti kényszer-eltérés (W/m²) egy kétrétegű energiamérleg-modellt hajt
##     (Held és mtsai 2010; Geoffroy és mtsai 2013).
##  3. A Föld érzékenysége bizonytalan: a TCRE és az ECS az IPCC „valószínű” sávján belül bármi lehet.

const START_YEAR := 2025
const END_YEAR := 2100
const T_START := 1.39            # °C 2025 elején (Forster és mtsai 2025: 2024-ben 1,36 °C, ~0,27 °C/évtized)
const E_CO2_NOW := 42.2          # GtCO2/év, fosszilis 38,1 + földhasználat 4,1 (Global Carbon Budget 2025)
const E_CH4_ANTHRO_NOW := 370.0  # Tg CH4/év, emberi eredetű (Global Methane Budget, Saunois és mtsai)
const CH4_PPB_NOW := 1930.0      # NOAA globális átlag
const TG_PER_PPB_CH4 := 2.78     # Prather és mtsai 2012
const CH4_LIFETIME := 11.8       # év, IPCC AR6 WG1 7.SM
const CH4_INDIRECT := 1.5        # ózon és sztratoszférikus vízgőz (feltevés, AR5 8.SM alapján)
const C_UPPER := 7.3             # W év m⁻² K⁻¹ (Geoffroy és mtsai 2013)
const C_DEEP := 106.0
const GAMMA := 0.73
const F_2X := 3.93               # W/m², IPCC AR6 WG1 7.3.2
## IPCC AR6 WG1 SPM: TCRE 0,45 °C / 1000 GtCO2 (valószínű sáv 0,27–0,63); ECS 3,0 °C (2,5–4,0).
const TCRE := [0.27, 0.45, 0.63]
const ECS := [2.5, 3.0, 4.0]


## A Föld érzékenysége: sens −1 (a sáv alja) … 0 (közép) … +1 (a sáv teteje).
static func params(sens: float) -> Dictionary:
	var s := clampf(sens, -1.0, 1.0)
	var f := func(a: Array) -> float:
		return lerpf(a[1], a[2], s) if s >= 0.0 else lerpf(a[1], a[0], -s)
	return {"tcre": f.call(TCRE), "ecs": f.call(ECS)}


static func new_state() -> Dictionary:
	return {"ev": START_YEAR - 1, "cum": 0.0, "ch4": 0.0, "t_up": 0.0, "t_dp": 0.0, "T": T_START}


## Egy év. d: {"co2": bruttó kibocsátás GtCO2/év, "cdr": kivonás GtCO2/év, "ch4": a metánkibocsátás levágott hányada 0–1}
static func step(st: Dictionary, d: Dictionary, p: Dictionary) -> void:
	var lam: float = F_2X / float(p["ecs"])
	var net: float = float(d.get("co2", E_CO2_NOW)) - float(d.get("cdr", 0.0))
	var d_e: float = -E_CH4_ANTHRO_NOW * float(d.get("ch4", 0.0))
	st["ch4"] += d_e / TG_PER_PPB_CH4 - st["ch4"] / CH4_LIFETIME
	var f_ch4: float = 0.036 * (sqrt(CH4_PPB_NOW + st["ch4"]) - sqrt(CH4_PPB_NOW)) * CH4_INDIRECT
	var d_up: float = (f_ch4 - lam * st["t_up"] - GAMMA * (st["t_up"] - st["t_dp"])) / C_UPPER
	var d_dp: float = GAMMA * (st["t_up"] - st["t_dp"]) / C_DEEP
	st["t_up"] += d_up
	st["t_dp"] += d_dp
	st["cum"] += net
	st["ev"] += 1
	st["netto"] = net
	st["T"] = T_START + float(p["tcre"]) / 1000.0 * st["cum"] + st["t_up"]


## Előrejelzés: az állapot másolatát futtatja `to` évig; drivers.call(év) adja az év hajtóerőit.
## Vissza: [[év, T], ...]
static func project(st: Dictionary, drivers: Callable, p: Dictionary, to: int = END_YEAR) -> Array:
	var s := st.duplicate()
	var out: Array = []
	while int(s["ev"]) < to:
		step(s, drivers.call(int(s["ev"]) + 1), p)
		out.append([int(s["ev"]), float(s["T"])])
	return out


## Tengerszint 2100-ban (m, az 1995–2014-es átlaghoz képest) a 2100-as melegedés szerint:
## IPCC AR6 WG1 9.9 táblázat (Fox-Kemper és mtsai 2021), a sorok között egyenesen közelítve.
## A táblázat szélein kívül a szélső sor marad (nem találunk ki a táblázaton túli számot).
const SEA_2100 := [[1.4, 0.38], [1.8, 0.44], [2.7, 0.56], [3.6, 0.68], [4.4, 0.77]]


static func sea_2100(t2100: float) -> float:
	if t2100 <= SEA_2100[0][0]:
		return SEA_2100[0][1]
	for i in SEA_2100.size() - 1:
		var a: Array = SEA_2100[i]
		var b: Array = SEA_2100[i + 1]
		if t2100 <= b[0]:
			return lerpf(a[1], b[1], (t2100 - a[0]) / (b[0] - a[0]))
	return SEA_2100[-1][1]
