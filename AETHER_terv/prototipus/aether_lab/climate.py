"""AETHER-mini: egyszerű, átlátható klímamodell a játékhoz.

FONTOS: ez oktatási / játékmodell, NEM kutatási minőségű előrejelzés.
Arra jó, hogy egy beavatkozás IRÁNYÁT és NAGYSÁGRENDJÉT megmutassa,
bizonytalansági sávval együtt. Komolyabb munkához a FaIR modellt
(Smith et al. 2018; Leach et al. 2021) érdemes használni, amelyhez a
játék később adaptert kaphat.

Felépítés (évenkénti lépés, 2025-től):
  1. CO2: a melegedés arányos a kumulatív nettó CO2-kibocsátással
     (TCRE, IPCC AR6 WG1 SPM D.1.1). Feltevés: nulla nettó kibocsátás
     után a hőmérséklet nagyjából stagnál (ZEC ~ 0, AR6 WG1 5.5.2).
  2. Nem-CO2 hatások (metán, aeroszolok, sztratoszférikus aeroszol-
     befecskendezés) a JELENLEGI szinthez képesti kényszer-eltérésként
     (W/m^2) egy kétrétegű energiamérleg-modellt hajtanak
     (Held et al. 2010; Geoffroy et al. 2013).
  3. Minden futás három paraméterkészlettel megy (alacsony / közép / magas
     érzékenység), így a bizonytalanság mindig látszik.

Minden számnak forrása van: lásd PARAMS_SOURCES alább és a
03_klimamodell_es_forrasok.md dokumentumot.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional

# ---------------------------------------------------------------------------
# Kiinduló állapot és paraméterek (mind forrással)
# ---------------------------------------------------------------------------
START_YEAR = 2025
END_YEAR = 2100

# Emberi eredetű melegedés 2024-ben: 1.36 °C (Forster et al. 2025, ESSD,
# "Indicators of Global Climate Change 2024"). ~0.27 °C/évtized üteme mellett
# 2025 elejére ~1.39 °C.
T_START = 1.39

# Teljes CO2-kibocsátás 2025-ben ~42.2 GtCO2/év (fosszilis 38.1 + földhasználat
# 4.1), Global Carbon Budget 2025 (Friedlingstein et al.).
E_CO2_NOW = 42.2

# Antropogén metánkibocsátás nagyságrendje ~370 Tg CH4/év
# (Global Methane Budget, Saunois et al. 2020/2025: antropogén ~60% a
# ~575-600 Tg/év összkibocsátásból). Feltevés, a játékos AI-ja pontosíthatja.
E_CH4_ANTHRO_NOW = 370.0
CH4_PPB_NOW = 1930.0          # NOAA globális átlag, 2024 körül
TG_PER_PPB_CH4 = 2.78         # 1 ppb CH4 ~ 2.78 Tg (Prather et al. 2012)
CH4_PERTURBATION_LIFETIME = 11.8  # év, IPCC AR6 WG1 7.SM
CH4_INDIRECT_FACTOR = 1.5     # troposzférikus ózon + sztrat. vízgőz hozzájárulás (feltevés, AR5 8.SM alapján ~1.5-1.65)

# Aeroszolok: szulfát ERF 1750-2019: -0.9 W/m^2 (-1.6..-0.3);
# korom (black carbon) +0.1 (-0.2..0.4)  [IPCC AR6 WG1 6. fejezet]
SULFATE_ERF_NOW = -0.9
BLACK_CARBON_ERF_NOW = 0.1

# Kétrétegű modell (Geoffroy et al. 2013, CMIP5 sokmodell-átlag)
C_UPPER = 7.3    # W yr m^-2 K^-1
C_DEEP = 106.0   # W yr m^-2 K^-1
GAMMA = 0.73     # W m^-2 K^-1
F_2X = 3.93      # W m^-2, CO2-duplázás kényszere, IPCC AR6 WG1 7.3.2

# Sztratoszférikus SO2: W/m^2 per (Tg SO2/év). NAGYON bizonytalan,
# a GeoMIP / Visioni et al. 2021 jellegű szimulációk nagyságrendje.
# A játékban kötelezően "nagy bizonytalanság" címkét kap.
SAI_EFFICIENCY = {"alacsony": 0.08, "kozep": 0.15, "magas": 0.25}

# Érzékenységi készletek. TCRE: 0.45 °C / 1000 GtCO2 (valószínű sáv
# 0.27-0.63), ECS: 3.0 °C (valószínű sáv 2.5-4.0) — IPCC AR6 WG1 SPM.
ENSEMBLE = {
    "alacsony": {"tcre": 0.27, "ecs": 2.5},
    "kozep": {"tcre": 0.45, "ecs": 3.0},
    "magas": {"tcre": 0.63, "ecs": 4.0},
}

# Termésérzékenység: hozamváltozás %/°C globális melegedés (Zhao et al. 2017,
# PNAS 114(35):9326, négy módszer kombinációja).
CROP_SENSITIVITY_PCT_PER_C = {"buza": -6.0, "rizs": -3.2, "kukorica": -7.4, "szoja": -3.1}

# Szén-dioxid-eltávolítás (CDR) fenntartható potenciál 2050-re, GtCO2/év
# (Fuss et al. 2018, Environ. Res. Lett. 13 063002). A játék nem engedi túllépni
# a felső határt.
CDR_LIMITS = {
    "erdosites": (0.5, 3.6),
    "beccs": (0.5, 5.0),
    "daccs": (0.5, 5.0),
    "kozetmallasztas": (2.0, 4.0),   # enhanced weathering
    "bioszen": (0.5, 2.0),           # biochar
    "talajszen": (0.0, 5.0),
}


# ---------------------------------------------------------------------------
# Forgatókönyv
# ---------------------------------------------------------------------------
@dataclass
class Scenario:
    """Egy játékos által összerakott beavatkozás-csomag.

    Minden mező egyszerű, ellenőrizhető szám. A játékban ezeket a játékos
    AI-ja tölti ki publikált forrásokból, a játékos hagyja jóvá.
    """
    nev: str = "Alapeset"
    leiras: str = ""
    # CO2: kibocsátás-csökkentés üteme. A kibocsátás lineárisan esik
    # co2_cel_ev-re co2_cel_ertekre (GtCO2/év). None = marad a mai szinten.
    co2_cel_ev: Optional[int] = None
    co2_cel_ertek: float = E_CO2_NOW
    co2_kezdo_ev: int = 2025
    # CDR: módszer -> GtCO2/év, 2050-re lineárisan felfuttatva 2030-tól
    cdr: Dict[str, float] = field(default_factory=dict)
    # Metán: az antropogén kibocsátás hány %-át vágjuk le, és meddig érjük el
    metan_csokkentes_pct: float = 0.0
    metan_cel_ev: int = 2030
    # Légszennyezés: a szulfát-aeroszol hány %-át szüntetjük meg (tisztább levegő)
    szulfat_csokkentes_pct: float = 0.0
    korom_csokkentes_pct: float = 0.0
    legszennyezes_cel_ev: int = 2040
    # Sztratoszférikus aeroszol (SAI): Tg SO2/év, kezdés és (opcionális) leállítás
    sai_tg_so2: float = 0.0
    sai_kezdes: int = 2035
    sai_leallitas: Optional[int] = None
    # Alkalmazkodás (NEM hűt! csak a hatást mérsékli): a hozamveszteség hány %-át
    # ellensúlyozzák pl. szárazságtűrő fajták + öntözési hatékonyság.
    # Ezt az értéket forrásból kell kitölteni; 0 = nincs adat.
    alkalmazkodas_hozam_kompenzacio_pct: float = 0.0
    alkalmazkodas_forras: str = ""


def _ramp(year: int, start: int, end: int) -> float:
    """0..1 lineáris felfutás start és end év között."""
    if end <= start:
        return 1.0 if year >= start else 0.0
    return min(1.0, max(0.0, (year - start) / (end - start)))


def co2_emissions(s: Scenario, year: int) -> float:
    """Bruttó CO2-kibocsátás (GtCO2/év) a forgatókönyv szerint."""
    if s.co2_cel_ev is None:
        return E_CO2_NOW
    f = _ramp(year, s.co2_kezdo_ev, s.co2_cel_ev)
    return E_CO2_NOW + (s.co2_cel_ertek - E_CO2_NOW) * f


def cdr_removal(s: Scenario, year: int) -> float:
    total = 0.0
    for method, amount in s.cdr.items():
        lo, hi = CDR_LIMITS.get(method, (0.0, 0.0))
        amount = min(amount, hi)  # fizikai/fenntarthatósági plafon
        total += amount * _ramp(year, 2030, 2050)
    return total


@dataclass
class RunResult:
    nev: str
    ensemble: str
    years: List[int]
    temp: List[float]
    co2_net: List[float]
    forcing_nonco2: List[float]
    crop_change_pct: Dict[str, List[float]]

    def at(self, year: int) -> float:
        return self.temp[self.years.index(year)]

    def peak(self):
        t = max(self.temp)
        return t, self.years[self.temp.index(t)]

    def first_cross(self, level: float) -> Optional[int]:
        for y, t in zip(self.years, self.temp):
            if t >= level:
                return y
        return None


def run(s: Scenario, ensemble: str = "kozep", sai_hatekonysag: str = "kozep") -> RunResult:
    p = ENSEMBLE[ensemble]
    tcre = p["tcre"] / 1000.0          # °C / GtCO2
    lam = F_2X / p["ecs"]              # W m^-2 K^-1
    # A SAI-hatékonyság bizonytalansága független a klímaérzékenységtől, ezért
    # az együttesben a középértéket használjuk; a sávot külön futtatással
    # (sai_hatekonysag paraméter) lehet vizsgálni.
    sai_eff = SAI_EFFICIENCY[sai_hatekonysag]

    years = list(range(START_YEAR, END_YEAR + 1))
    cum = 0.0
    ch4_pert_ppb = 0.0
    t_up = 0.0   # nem-CO2 perturbáció, felső réteg
    t_dp = 0.0   # mély óceán
    temps, nets, forc = [], [], []

    for y in years:
        net = co2_emissions(s, y) - cdr_removal(s, y)
        # Metán: kibocsátás-eltérés (Tg/év) -> koncentráció-eltérés (ppb)
        d_e_ch4 = -E_CH4_ANTHRO_NOW * s.metan_csokkentes_pct / 100.0 * _ramp(y, 2025, s.metan_cel_ev)
        ch4_pert_ppb += d_e_ch4 / TG_PER_PPB_CH4 - ch4_pert_ppb / CH4_PERTURBATION_LIFETIME
        conc = CH4_PPB_NOW + ch4_pert_ppb
        f_ch4 = 0.036 * (math.sqrt(conc) - math.sqrt(CH4_PPB_NOW)) * CH4_INDIRECT_FACTOR
        # Aeroszolok: néhány napos élettartam -> azonnali hatás
        r = _ramp(y, 2025, s.legszennyezes_cel_ev)
        f_aer = -SULFATE_ERF_NOW * s.szulfat_csokkentes_pct / 100.0 * r \
                - BLACK_CARBON_ERF_NOW * s.korom_csokkentes_pct / 100.0 * r
        # SAI
        sai_on = s.sai_tg_so2 > 0 and y >= s.sai_kezdes and (s.sai_leallitas is None or y < s.sai_leallitas)
        f_sai = -sai_eff * s.sai_tg_so2 * _ramp(y, s.sai_kezdes, s.sai_kezdes + 5) if sai_on else 0.0
        f_tot = f_ch4 + f_aer + f_sai
        # Kétrétegű energiamérleg (explicit Euler, 1 év)
        d_up = (f_tot - lam * t_up - GAMMA * (t_up - t_dp)) / C_UPPER
        d_dp = GAMMA * (t_up - t_dp) / C_DEEP
        t_up += d_up
        t_dp += d_dp
        cum += net
        temps.append(round(T_START + tcre * cum + t_up, 4))
        nets.append(round(net, 3))
        forc.append(round(f_tot, 4))

    # Termés: a 2025-ös szinthez képesti további melegedés hatása,
    # mínusz az alkalmazkodás kompenzációja. KORLÁT: csak a hőmérsékletet
    # nézi; a CO2-trágyázást, a csapadékot és SAI esetén a csökkent
    # napfényt (Proctor et al. 2018, Nature) nem.
    crops = {}
    k = 1.0 - s.alkalmazkodas_hozam_kompenzacio_pct / 100.0
    for crop, sens in CROP_SENSITIVITY_PCT_PER_C.items():
        crops[crop] = [round(sens * (t - T_START) * k, 2) for t in temps]
    return RunResult(s.nev, ensemble, years, temps, nets, forc, crops)


def run_ensemble(s: Scenario) -> Dict[str, RunResult]:
    return {e: run(s, e) for e in ENSEMBLE}


def summarize(s: Scenario) -> Dict:
    res = run_ensemble(s)
    out = {"nev": s.nev, "leiras": s.leiras, "eredmenyek": {}}
    for e, r in res.items():
        pk, py = r.peak()
        out["eredmenyek"][e] = {
            "T2050": round(r.at(2050), 2),
            "T2100": round(r.at(2100), 2),
            "csucs": round(pk, 2),
            "csucs_ev": py,
            "1.5C_atlepes": r.first_cross(1.5),
            "2.0C_atlepes": r.first_cross(2.0),
            "kukorica_hozam_2050_pct": r.crop_change_pct["kukorica"][r.years.index(2050)],
        }
    return out


# ---------------------------------------------------------------------------
# Beépített forgatókönyvek: a felhasználó kérdéseire adott őszinte válaszok
# ---------------------------------------------------------------------------
def builtin_scenarios() -> List[Scenario]:
    return [
        Scenario(nev="0. Alapeset: kibocsátás marad a mai szinten",
                 leiras="42 GtCO2/év 2100-ig, semmi más nem változik."),
        Scenario(nev="1. Szárazságtűrő növények + víztakarékosság",
                 leiras="Alkalmazkodás: a hozamveszteség 30%-át ellensúlyozza (FELTEVÉS, forrás kell). A kibocsátás nem változik.",
                 alkalmazkodas_hozam_kompenzacio_pct=30.0,
                 alkalmazkodas_forras="FELTEVÉS – a játékos AI-jának kell forrásból pontosítania"),
        Scenario(nev="2. Légszennyezés csökkentése (csak szulfát és korom)",
                 leiras="A szulfát- és koromszennyezés 80%-a megszűnik 2040-ig. Tisztább levegő, de a szulfát hűtő hatása is eltűnik.",
                 szulfat_csokkentes_pct=80, korom_csokkentes_pct=80, legszennyezes_cel_ev=2040),
        Scenario(nev="3. Gyors metáncsökkentés (-45% 2030-ig)",
                 leiras="Global Methane Assessment (UNEP/CCAC 2021) szerinti cél.",
                 metan_csokkentes_pct=45, metan_cel_ev=2030),
        Scenario(nev="4. Nettó zéró CO2 2050-re",
                 leiras="Lineáris csökkentés 2025-2050 között nullára.",
                 co2_cel_ev=2050, co2_cel_ertek=0.0),
        Scenario(nev="5. Nettó zéró 2050 + metán -45% + CO2-eltávolítás",
                 leiras="Kombinált csomag: CDR a Fuss et al. 2018 potenciálok alsó-közép tartományában (összesen 5 GtCO2/év 2050-re).",
                 co2_cel_ev=2050, co2_cel_ertek=0.0, metan_csokkentes_pct=45, metan_cel_ev=2030,
                 cdr={"erdosites": 1.5, "kozetmallasztas": 2.0, "bioszen": 1.0, "daccs": 0.5},
                 szulfat_csokkentes_pct=80, korom_csokkentes_pct=80, legszennyezes_cel_ev=2040,
                 alkalmazkodas_hozam_kompenzacio_pct=30.0),
        Scenario(nev="6. Csak sztratoszférikus aeroszol (SAI), 2070-ben leáll",
                 leiras="8 Tg SO2/év 2035-től, kibocsátás változatlan, 2070-ben hirtelen leállítás (\"termination shock\").",
                 sai_tg_so2=8.0, sai_kezdes=2035, sai_leallitas=2070),
    ]
