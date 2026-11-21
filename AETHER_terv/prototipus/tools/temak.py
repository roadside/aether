"""Az AETHER kutatási témái (küldetések): a játék tudásfája.

Ez a fájl az egyetlen forrás. Futtatva megírja a játék katalógusát:
    python tools/temak.py   ->   AETHER_godot/assets/temak_katalogus.json

Minden téma egy valódi kutatási kérdés. A témákat mi írtuk, de a válasz (a szám) mindig a
játékos kutatásából, valódi cikkekből jön. Hogy minden témához tényleg van-e szakirodalom,
azt a tools/temak_ellenorzes.py nézi meg (OpenAlex: áttekintő cikkek száma).

Mezők:
  id, korszak (1–4), terulet (lásd TERULETEK), cim/cim_en, magyarazat/magyarazat_en,
  kereses (angol keresőkifejezések, "|" választja el), parameterek (aether_lab/evidence.py
  PARAMETERS kulcsai, vesszővel), wiki/wiki_en (Wikipédia-keresőszó), attekintes (angol
  keresés áttekintő cikkekre), nyit/nyit_en (mit ad a játékban; csak ha valóban ad valamit).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "AETHER_godot" / "assets" / "temak_katalogus.json"

TERULETEK = {
    "fizika": ("Fizika", "Physics"),
    "kemia": ("Kémia", "Chemistry"),
    "anyag": ("Anyagtudomány", "Materials science"),
    "ur": ("Csillagászat és űrkutatás", "Astronomy and space"),
    "fold": ("Földtudomány", "Earth science"),
    "biologia": ("Biológia", "Biology"),
    "energia": ("Energia", "Energy"),
    "mernok": ("Közlekedés és épületek", "Transport and buildings"),
    "mezogazdasag": ("Mezőgazdaság és élelem", "Farming and food"),
    "egeszseg": ("Egészség és alkalmazkodás", "Health and adaptation"),
}

CDR = "cdr_potencial_gtco2_ev,cdr_koltseg_usd_tco2"
NET_REVIEW = "negative emissions technologies potentials costs side effects"

TEMAK: list = []


def T(id, korszak, terulet, cim, cim_en, magy, magy_en, kereses, param, wiki, wiki_en, attekintes,
      nyit=None):
    d = {"id": id, "korszak": korszak, "terulet": terulet, "cim": cim, "cim_en": cim_en,
         "magyarazat": magy, "magyarazat_en": magy_en, "kereses": kereses, "parameterek": param,
         "wiki": wiki, "wiki_en": wiki_en, "attekintes": attekintes, "nyit": "", "nyit_en": ""}
    if nyit:
        d["nyit"], d["nyit_en"] = nyit
    TEMAK.append(d)


# =============================================================================
# I. Felismerés: mérés és megértés
# =============================================================================
T("tcre", 1, "fizika",
  "Mennyit melegít a kibocsátott CO2?", "How much does emitted CO2 warm the Earth?",
  "Minden elégetett tonna szén-dioxid melegít. Mennyit, ha összeadjuk?",
  "Every tonne of carbon dioxide burned warms the Earth. How much, added up?",
  "transient climate response to cumulative CO2 emissions estimate|remaining carbon budget warming per 1000 GtCO2|TCRE observational constraint",
  "tcre_c_per_1000gtco2", "szén-dioxid globális felmelegedés", "carbon budget",
  "carbon budget cumulative emissions warming review",
  ("Megérted, miért számít minden tonna.", "You understand why every tonne counts."))
T("klimaerzekenyseg", 1, "fizika",
  "Mennyit melegszik a Föld, ha kétszer annyi lesz a CO2?", "How much does Earth warm if CO2 doubles?",
  "Ez a klímaérzékenység: ebből látszik, mekkora melegedés vár ránk.",
  "This is climate sensitivity: it tells us how much warming lies ahead.",
  "equilibrium climate sensitivity assessment multiple lines of evidence|equilibrium climate sensitivity estimate paleoclimate|effective climate sensitivity observational constraint",
  "klimaerzekenyseg_c", "klímaérzékenység", "climate sensitivity",
  "equilibrium climate sensitivity review")
T("aeroszol", 1, "fizika",
  "Mennyit hűt a levegő szennyezése?", "How much does air pollution cool the Earth?",
  "A füst és a kénes szennyezés apró részecskéi visszaverik a napfényt, és elfedik a melegedés egy részét.",
  "Tiny particles of smoke and sulphur pollution reflect sunlight and hide part of the warming.",
  "aerosol effective radiative forcing estimate|aerosol cloud interactions radiative forcing|anthropogenic aerosol forcing observational constraint",
  "aeroszol_erf_w_m2", "aeroszol éghajlat", "aerosol",
  "aerosol radiative forcing review")
T("felhok", 1, "fizika",
  "Erősítik vagy fékezik a felhők a melegedést?", "Do clouds amplify or slow warming?",
  "A melegedés megváltoztatja a felhőket, és ez visszahat a hőmérsékletre.",
  "Warming changes clouds, and that feeds back on temperature.",
  "cloud feedback climate change estimate|low cloud feedback observational constraint|cloud feedback climate sensitivity",
  "visszacsatolas_w_m2_c", "felhő éghajlat visszacsatolás", "cloud feedback",
  "cloud feedback review")
T("ocean_ho", 1, "fizika",
  "A melegedés hőjének mekkora részét nyeli el az óceán?", "What share of the extra heat does the ocean absorb?",
  "A többlethő a tengerbe, a jégbe, a talajba és a levegőbe kerül. A tengerben évszázadokig megmarad.",
  "The extra heat goes into the sea, ice, land and air. In the sea it stays for centuries.",
  "ocean heat content increase observations|ocean warming heat uptake|Earth energy imbalance ocean heat",
  "reszarany_pct", "óceán hőtartalom", "ocean heat content",
  "ocean heat content review")
T("amoc", 1, "fizika",
  "Lassul-e a Golf-áramlat rendszere?", "Is the Gulf Stream system slowing down?",
  "Az Atlanti-óceán nagy áramlása meleget visz Európába. Ha gyengül, megváltozik az időjárásunk.",
  "The Atlantic's great current carries heat to Europe. If it weakens, our weather changes.",
  "Atlantic meridional overturning circulation slowdown|AMOC weakening projections|AMOC tipping point early warning",
  "csokkenes_pct", "Golf-áramlat", "Atlantic meridional overturning circulation",
  "Atlantic meridional overturning circulation review")
T("napaktivitas", 1, "ur",
  "Okozhatja-e a Nap a mai melegedést?", "Could the Sun be causing today's warming?",
  "A Nap fénye kicsit ingadozik. A mérések megmutatják, mennyit számít ez.",
  "The Sun's output varies a little. Measurements show how much that matters.",
  "solar irradiance variability contribution to global warming|total solar irradiance trend climate|solar forcing twentieth century temperature",
  "sugarzasi_kenyszer_w_m2", "naptevékenység éghajlat", "solar activity and climate",
  "solar influence on climate review")
T("kozmikus", 1, "ur",
  "Befolyásolják-e a kozmikus sugarak a felhőket?", "Do cosmic rays affect clouds?",
  "Egy régi ötlet szerint a világűrből jövő sugárzás felhőket kelt. Mit mutatnak a mérések?",
  "An old idea says radiation from space creates clouds. What do measurements show?",
  "cosmic rays cloud formation climate|galactic cosmic rays cloud condensation nuclei|CLOUD experiment ion-induced nucleation",
  "valtozas_pct", "kozmikus sugárzás felhő", "cosmic ray",
  "cosmic rays clouds climate review")
T("metan_muhold", 1, "ur",
  "Megtalálják-e a műholdak a nagy metánszivárgásokat?", "Can satellites find large methane leaks?",
  "Az űrből mért adatokkal kiderül, hol szökik a legtöbb metán a levegőbe.",
  "Data measured from space reveal where the most methane escapes into the air.",
  "satellite detection of methane super-emitters|TROPOMI methane emissions point sources|satellite methane plume detection oil and gas",
  "reszarany_pct", "metán műhold", "atmospheric methane",
  "satellite methane observations review")
T("muhold_erdo", 1, "ur",
  "Mennyi erdő tűnik el évente a műholdképek szerint?", "How much forest disappears each year, according to satellites?",
  "Az űrfelvételekből évről évre látszik, hol vágják ki vagy égetik fel az erdőt.",
  "Satellite images show year by year where forests are cut or burned.",
  "satellite monitoring global forest loss|remote sensing deforestation carbon emissions|Landsat global forest change",
  "terulet_mha_ev", "erdőirtás", "deforestation",
  "remote sensing deforestation review")
T("ocean_savasodas", 1, "kemia",
  "Mennyire savasodik az óceán?", "How acidic is the ocean becoming?",
  "A tenger elnyeli a CO2 egy részét, és ettől savasabb lesz. Ez árt a kagylóknak és a koralloknak.",
  "The sea absorbs part of the CO2 and becomes more acidic. This harms shellfish and corals.",
  "ocean acidification pH decline observations|ocean acidification impacts marine calcifiers meta-analysis",
  "ph_valtozas", "óceánok savasodása", "ocean acidification",
  "ocean acidification review")
T("tengerszint", 1, "fold",
  "Mennyit emelkedik a tenger 2100-ig?", "How much will the sea rise by 2100?",
  "Az olvadó jég és a melegedő, táguló víz megemeli a tenger szintjét.",
  "Melting ice and warming, expanding water raise the sea level.",
  "global mean sea level rise projections 2100|sea level rise projections ice sheet contribution|sea level rise observations acceleration",
  "tengerszint_cm", "tengerszint-emelkedés", "sea level rise",
  "sea level rise projections review")
T("gronland", 1, "fold",
  "Milyen gyorsan olvad Grönland jege?", "How fast is Greenland's ice melting?",
  "Grönland jégtakarója évről évre veszít a tömegéből, és ez emeli a tengert.",
  "Greenland's ice sheet loses mass year after year, raising the sea.",
  "Greenland ice sheet mass loss rate|Greenland ice sheet mass balance|Greenland surface melt runoff",
  "jegveszteseg_gt_ev", "grönlandi jégtakaró", "Greenland ice sheet",
  "Greenland ice sheet mass balance review")
T("antarktisz", 1, "fold",
  "Mennyi jeget veszít az Antarktisz?", "How much ice is Antarctica losing?",
  "A déli jégtakaró a legnagyobb jégtömeg a Földön. Ha nagy része elolvadna, méterekkel emelné a tengert.",
  "The southern ice sheet is the largest mass of ice on Earth. If much of it melted, the sea would rise by metres.",
  "Antarctic ice sheet mass balance|Antarctic ice sheet mass loss acceleration|West Antarctic ice sheet instability",
  "jegveszteseg_gt_ev", "antarktiszi jégtakaró", "Antarctic ice sheet",
  "Antarctic ice sheet mass balance review")
T("gleccser", 1, "fold",
  "Mennyit olvadnak a hegyi gleccserek?", "How much are mountain glaciers melting?",
  "Az Alpok és a Himalája gleccserei nyáron sok folyó vizét adják.",
  "Glaciers in the Alps and the Himalayas feed many rivers in summer.",
  "global glacier mass loss|glacier mass change worldwide|mountain glacier retreat projections",
  "jegveszteseg_gt_ev", "gleccser visszahúzódás", "retreat of glaciers since 1850",
  "glacier mass loss review")
T("permafroszt", 1, "fold",
  "Mennyi szenet enged ki a felolvadó fagyott talaj?", "How much carbon does thawing frozen ground release?",
  "Az északi fagyott talajban több szén van, mint a levegőben. Olvadáskor egy része kiszabadul.",
  "The frozen northern ground holds more carbon than the air. When it thaws, part of it escapes.",
  "permafrost carbon feedback emissions|permafrost thaw carbon release projections|permafrost carbon climate feedback",
  "szen_gtc", "permafroszt", "permafrost carbon cycle",
  "permafrost carbon feedback review")
T("aszaly", 1, "fold",
  "Gyakoribb lesz-e az aszály?", "Will droughts become more frequent?",
  "A melegebb levegő több vizet párologtat el a talajból és a növényekből.",
  "Warmer air draws more water out of soil and plants.",
  "drought frequency increase climate change|soil moisture drought projections warming|agricultural drought attribution",
  "valtozas_pct", "aszály", "drought",
  "drought climate change review")
T("felhoszakadas", 1, "fold",
  "Hevesebbek lesznek-e a nagy esők?", "Will heavy rain get heavier?",
  "A meleg levegő több vizet tart, ezért a felhőszakadások erősebbek lehetnek.",
  "Warm air holds more water, so downpours can be stronger.",
  "extreme precipitation intensification per degree warming|heavy rainfall scaling with temperature|observed increase extreme precipitation",
  "valtozas_pct_per_c", "szélsőséges időjárás csapadék", "extreme weather",
  "extreme precipitation climate change review")
T("erdotuz", 1, "fold",
  "Több erdőtűz lesz-e a melegedéssel?", "Will warming bring more wildfires?",
  "A forró, száraz nyarakon könnyebben és nagyobb területen ég az erdő.",
  "In hot, dry summers forests catch fire more easily and burn over larger areas.",
  "climate change wildfire burned area increase|fire weather climate change attribution|wildfire carbon emissions trend",
  "valtozas_pct", "erdőtűz", "wildfire",
  "wildfire climate change review")
T("termes", 1, "mezogazdasag",
  "Mennyit csökken a termés, ha melegszik a Föld?", "How much do harvests fall as the Earth warms?",
  "A búza, a kukorica és a rizs érzékeny a hőségre. Mennyit veszít egy fok melegedéstől?",
  "Wheat, maize and rice are sensitive to heat. How much do they lose per degree of warming?",
  "crop yield change per degree of warming meta-analysis|temperature increase reduces global yields of major crops|maize wheat rice yield sensitivity to temperature",
  "hozam_valtozas_pct_per_c", "éghajlatváltozás mezőgazdaság", "effects of climate change on agriculture",
  "climate change crop yield review",
  ("Megérted, miért kell alkalmazkodni is.", "You understand why we must adapt too."))
T("kukorica", 1, "mezogazdasag",
  "Segítenek-e az aszálytűrő kukoricafajták?", "Do drought-tolerant maize varieties help?",
  "Ez nem hűti a Földet, de megvédheti a termést a forró, száraz években.",
  "This does not cool the Earth, but it can protect harvests in hot, dry years.",
  "drought tolerant maize yield advantage under drought|drought tolerant maize varieties yield on-farm trials",
  "alkalmazkodas_hozam_elony_pct", "kukorica szárazságtűrés", "drought tolerance maize",
  "drought tolerant maize review",
  ("Aszálytűrő fajták a tervedben.", "Drought-tolerant varieties in your plan."))
T("beporzok", 1, "biologia",
  "Mit okoz a melegedés a beporzó rovaroknak?", "What does warming do to pollinating insects?",
  "A méhek és más beporzók nélkül sok gyümölcs és zöldség nem terem.",
  "Without bees and other pollinators, many fruits and vegetables do not grow.",
  "climate change effects on pollinators bumblebee decline|pollinator decline climate warming|climate change plant pollinator mismatch",
  "csokkenes_pct", "beporzás", "pollinator decline",
  "climate change pollinators review")
T("korall", 1, "biologia",
  "Túlélik-e a korallzátonyok a melegedést?", "Can coral reefs survive warming?",
  "A túl meleg víz kifehéríti, majd megöli a korallokat.",
  "Water that is too warm bleaches corals and then kills them.",
  "coral reef bleaching warming thresholds|mass coral bleaching events frequency|coral reefs under 1.5 degrees warming",
  "csokkenes_pct", "korallzátony kifehéredés", "coral bleaching",
  "coral bleaching climate change review")
T("amazonas", 1, "biologia",
  "Közel van-e az Amazonas esőerdő az átbillenéshez?", "Is the Amazon rainforest near a tipping point?",
  "Ha az esőerdő túl sokat szárad és ritkul, szavannává alakulhat.",
  "If the rainforest dries and thins too much, it could turn into savanna.",
  "Amazon rainforest tipping point dieback|Amazon forest resilience loss|Amazon deforestation drought carbon sink",
  "csokkenes_pct", "amazóniai esőerdő", "Amazon rainforest",
  "Amazon forest tipping point review")
T("hoseg_halal", 1, "egeszseg",
  "A hőség okozta halálesetek mekkora része jön a melegedésből?", "What share of heat deaths is caused by warming?",
  "A forró napokon több idős és beteg ember hal meg. A melegedéssel ez nő.",
  "On hot days more elderly and sick people die. Warming makes this worse.",
  "heat-related mortality attributable to climate change|heat wave mortality temperature|temperature mortality association multi-country",
  "reszarany_pct", "hőhullám egészség", "heat wave",
  "heat-related mortality review")
T("munkakepesseg", 1, "egeszseg",
  "Mennyi munkaidőt visz el a hőség?", "How much working time does heat take away?",
  "Nagy melegben kint dolgozni veszélyes, ezért kevesebbet lehet dolgozni.",
  "Working outdoors in great heat is dangerous, so less work gets done.",
  "heat stress labour productivity loss climate change|occupational heat exposure labor capacity|heat stress outdoor workers productivity",
  "csokkenes_pct", "hőstressz munka", "occupational heat stress",
  "occupational heat stress review")
T("legszennyezes", 1, "egeszseg",
  "Hány életet ment, ha kevesebb szenet és olajat égetünk?", "How many lives are saved by burning less coal and oil?",
  "A kémények és kipufogók füstje betegséget okoz. A tisztább levegő a klímának is jó.",
  "Smoke from chimneys and exhausts causes disease. Cleaner air also helps the climate.",
  "air quality health co-benefits of climate mitigation|fossil fuel air pollution premature deaths|PM2.5 mortality fossil fuel combustion",
  "kockazat_csokkentes_pct", "légszennyezés", "air pollution",
  "health co-benefits climate mitigation review")

# =============================================================================
# II. Mérséklés: metán, takarékosság, alkalmazkodás
# =============================================================================
T("metan_rizs", 2, "mezogazdasag",
  "Mennyi metán spórolható meg a rizsföldeken?", "How much methane can rice fields save?",
  "Az elárasztott rizsföld metánt enged a levegőbe. Ha időnként lecsapolják, kevesebbet.",
  "Flooded rice fields release methane. Draining them from time to time releases less.",
  "alternate wetting and drying rice methane emission reduction meta-analysis|rice paddy methane mitigation practices",
  "metan_csokkentes_pct", "rizs metán", "alternate wetting and drying",
  "rice paddy methane mitigation review",
  ("Megérted, hol lehet gyorsan metánt spórolni.", "You understand where methane can be cut quickly."))
T("metan_gaz", 2, "energia",
  "Mennyi metánszivárgás szüntethető meg a gáziparban?", "How much methane leakage can the gas industry stop?",
  "A földgáz főleg metán. A szivárgó kutakból és csövekből sok jut a levegőbe.",
  "Natural gas is mostly methane. Leaking wells and pipes release a lot of it into the air.",
  "oil and gas methane emissions abatement potential|methane leak detection and repair emission reduction|fossil fuel methane mitigation potential",
  "metan_csokkentes_pct", "földgáz metánszivárgás", "methane emissions",
  "oil and gas methane mitigation review",
  ("Megérted, hol lehet gyorsan metánt spórolni.", "You understand where methane can be cut quickly."))
T("metan_szen", 2, "energia",
  "Mennyi metán fogható fel a szénbányákban?", "How much methane can coal mines capture?",
  "A szénrétegekből metán szabadul fel a bányákban, a bezárt bányákból is.",
  "Coal seams release methane in mines, even in closed ones.",
  "coal mine methane emissions mitigation|coal mine methane capture utilization|abandoned coal mine methane emissions",
  "metan_csokkentes_pct", "bányagáz metán", "coal mine methane",
  "coal mine methane review")
T("hulladek_metan", 2, "kemia",
  "Mennyi metán fogható fel a szeméttelepeken?", "How much methane can landfills capture?",
  "A lerakott ételmaradék és papír rothadás közben metánt termel.",
  "Dumped food waste and paper produce methane as they rot.",
  "landfill methane emissions mitigation potential|landfill gas capture efficiency|landfill methane oxidation cover",
  "metan_csokkentes_pct", "hulladéklerakó gáz", "landfill gas",
  "landfill methane mitigation review")
T("hutokozeg", 2, "kemia",
  "Mennyit számít a hűtők és légkondik gázának cseréje?", "How much does replacing the gas in fridges and air conditioners matter?",
  "A hűtőgépek egyes gázai, ha kiszöknek, akár ezerszer erősebben melegítenek, mint a CO2.",
  "When they leak, some gases in cooling machines warm the Earth up to a thousand times more than CO2.",
  "hydrofluorocarbon phase-down Kigali amendment avoided warming|HFC emissions mitigation refrigerants|low global warming potential refrigerants",
  "kibocsatas_potencial_gtco2e_ev", "hűtőközeg", "hydrofluorocarbon",
  "hydrofluorocarbon phase-down review")
T("n2o_ipar", 2, "kemia",
  "Mennyi kéjgáz szűrhető ki a vegyi gyárakban?", "How much laughing gas can chemical plants filter out?",
  "A salétromsav és a nejlon alapanyagának gyártása dinitrogén-oxidot (kéjgázt) enged ki, ami erősen melegít.",
  "Making nitric acid and a raw material for nylon releases nitrous oxide (laughing gas), which warms strongly.",
  "nitric acid adipic acid N2O abatement|industrial nitrous oxide emissions reduction|catalytic N2O decomposition nitric acid plants",
  "kibocsatas_csokkentes_pct", "dinitrogén-oxid", "nitrous oxide",
  "industrial nitrous oxide abatement review")
T("mutragya", 2, "mezogazdasag",
  "Mennyi kéjgáz spórolható a műtrágya okosabb használatával?", "How much laughing gas can smarter fertiliser use save?",
  "A túl sok nitrogénműtrágyából a talajban dinitrogén-oxid lesz, ami erős üvegházgáz.",
  "Too much nitrogen fertiliser turns into nitrous oxide in soil, a strong greenhouse gas.",
  "nitrogen fertilizer nitrous oxide emissions reduction|nitrification inhibitors N2O mitigation meta-analysis|nitrogen use efficiency nitrous oxide",
  "kibocsatas_csokkentes_pct", "műtrágya", "fertilizer",
  "agricultural nitrous oxide mitigation review")
T("kerodzok_metan", 2, "biologia",
  "Csökkenthető-e a tehenek metánja takarmánnyal?", "Can feed reduce methane from cows?",
  "A kérődzők emésztés közben metánt böfögnek. Egyes takarmány-kiegészítők ezt csökkentik.",
  "Ruminants burp methane as they digest. Some feed additives reduce it.",
  "enteric methane mitigation feed additives meta-analysis|3-nitrooxypropanol methane reduction dairy cows|enteric methane mitigation strategies ruminants",
  "metan_csokkentes_pct", "kérődzők metán", "enteric fermentation",
  "enteric methane mitigation review")
T("voros_alga", 2, "biologia",
  "Tényleg csökkenti-e egy tengeri alga a tehenek metánját?", "Does a seaweed really cut cattle methane?",
  "Egy vörös tengeri alga kis adagban a takarmányban erősen csökkentheti a metánt.",
  "A red seaweed, in small amounts in feed, may strongly reduce methane.",
  "Asparagopsis seaweed enteric methane reduction|red seaweed cattle methane|Asparagopsis taxiformis beef cattle methane",
  "metan_csokkentes_pct", "vörösmoszatok", "Asparagopsis taxiformis",
  "seaweed feed methane review")
T("tragya", 2, "mezogazdasag",
  "Mennyi metán spórolható a trágya kezelésével?", "How much methane can manure management save?",
  "A trágyatárolókból metán és kéjgáz száll fel. Lefedve vagy erjesztve kevesebb.",
  "Manure stores release methane and laughing gas. Covered or digested, they release less.",
  "manure management methane emissions mitigation|anaerobic digestion manure methane reduction|slurry storage methane mitigation",
  "metan_csokkentes_pct", "trágya", "manure management",
  "manure greenhouse gas mitigation review")
T("pazarlas", 2, "mezogazdasag",
  "Mennyi kibocsátás jön a kidobott ételből?", "How much emission comes from wasted food?",
  "Az élelmiszer egy része a földtől az asztalig elvész, vagy a szemétbe kerül.",
  "Part of our food is lost between field and table, or thrown away.",
  "food loss and waste greenhouse gas emissions|food waste reduction emissions mitigation potential",
  "kibocsatas_potencial_gtco2e_ev", "élelmiszer-pazarlás", "food loss and waste",
  "food waste greenhouse gas review")
T("etrend", 2, "mezogazdasag",
  "Mennyit számít, ha kevesebb húst eszünk?", "How much does eating less meat matter?",
  "A hús, főleg a marhahús előállítása sok földet és sok kibocsátást igényel.",
  "Producing meat, especially beef, takes a lot of land and causes a lot of emissions.",
  "dietary change greenhouse gas emissions reduction plant-based|shift to plant-based diets mitigation potential|diet greenhouse gas emissions meta-analysis",
  "kibocsatas_potencial_gtco2e_ev", "növényi étrend", "environmental impact of meat production",
  "dietary change climate mitigation review")
T("ontozes", 2, "mezogazdasag",
  "Mennyi vizet takarít meg a csepegtető öntözés?", "How much water does drip irrigation save?",
  "A csepegtető cső a vizet egyenesen a növény gyökeréhez juttatja.",
  "A drip line delivers water straight to the plant's roots.",
  "drip irrigation water saving compared to flood irrigation meta-analysis|drip irrigation water use efficiency yield",
  "viztakarekossag_pct", "csepegtető öntözés", "drip irrigation",
  "drip irrigation water saving review",
  ("Megérted, hogyan védhető a víz aszályban.", "You understand how to protect water in a drought."))
T("napelem", 2, "energia",
  "Mennyi CO2-t spórol a napelem?", "How much CO2 do solar panels save?",
  "A szilícium napelem a napfényt közvetlenül árammá alakítja. Gyártása is jár kibocsátással.",
  "A silicon solar panel turns sunlight straight into electricity. Making it also causes emissions.",
  "photovoltaic life cycle greenhouse gas emissions|solar PV carbon payback time|crystalline silicon photovoltaic life cycle assessment",
  "kibocsatas_csokkentes_pct", "napelem", "photovoltaics",
  "photovoltaic life cycle assessment review")
T("szelenergia", 2, "energia",
  "Mennyi kibocsátást válthat ki a szélenergia?", "How much emission can wind power replace?",
  "A szélturbinák a szél mozgási energiáját alakítják árammá.",
  "Wind turbines turn the energy of moving air into electricity.",
  "wind power greenhouse gas mitigation potential|onshore wind energy technical potential|wind turbine life cycle emissions",
  "kibocsatas_potencial_gtco2e_ev", "szélenergia", "wind power",
  "wind energy potential review")
T("geotermia", 2, "energia",
  "Mennyi fűtést és áramot adhat a föld hője?", "How much heat and power can the Earth's heat provide?",
  "A föld mélyének hője fűtésre és áramtermelésre is használható. Magyarországon különösen sok van belőle.",
  "Heat from deep underground can be used for heating and electricity. Hungary has a great deal of it.",
  "geothermal energy potential emissions reduction|geothermal district heating potential|geothermal power life cycle emissions",
  "kibocsatas_csokkentes_pct", "geotermikus energia", "geothermal energy",
  "geothermal energy review")
T("napkollektor", 2, "energia",
  "Mennyi energiát spórol a napkollektor?", "How much energy does a solar water heater save?",
  "A napkollektor a napfénnyel melegíti a vizet, áram nélkül.",
  "A solar collector heats water with sunlight, without electricity.",
  "solar water heating energy savings emissions|solar thermal collectors domestic hot water performance|solar thermal heating life cycle assessment",
  "kibocsatas_csokkentes_pct", "napkollektor", "solar water heating",
  "solar thermal collectors review")
T("hoszivattyu", 2, "mernok",
  "Mennyit spórol a hőszivattyú a gázkazánhoz képest?", "How much does a heat pump save compared to a gas boiler?",
  "A hőszivattyú a kinti levegő vagy a föld hőjét hozza be a házba, árammal.",
  "A heat pump brings heat from the outside air or the ground into the house, using electricity.",
  "heat pump greenhouse gas emissions reduction compared to gas boiler|air source heat pump life cycle emissions|residential heat pump decarbonization",
  "kibocsatas_csokkentes_pct", "hőszivattyú", "heat pump",
  "heat pump decarbonization review")
T("hoszigeteles", 2, "mernok",
  "Mennyi fűtést spórol a hőszigetelés?", "How much heating does insulation save?",
  "A jól szigetelt fal, tető és ablak bent tartja a meleget.",
  "Well-insulated walls, roofs and windows keep the warmth in.",
  "building envelope retrofit energy savings|thermal insulation retrofit heating energy reduction|deep energy renovation residential buildings",
  "kibocsatas_csokkentes_pct", "hőszigetelés", "building insulation",
  "building energy retrofit review")
T("led", 2, "fizika",
  "Mennyi áramot spórol a LED-lámpa?", "How much electricity does an LED lamp save?",
  "A LED (világító dióda) ugyanannyi fényt kevesebb árammal ad, mint a régi izzó.",
  "An LED (light-emitting diode) gives the same light with less electricity than an old bulb.",
  "LED lighting energy savings|solid-state lighting energy efficiency|LED retrofit electricity savings",
  "kibocsatas_csokkentes_pct", "LED-lámpa", "LED lamp",
  "LED lighting energy efficiency review")
T("villanyauto", 2, "mernok",
  "Mennyivel kevesebb CO2-t okoz a villanyautó?", "How much less CO2 does an electric car cause?",
  "Az elektromos autó teljes élete alatt, az akkumulátor gyártásával együtt számolva.",
  "Counted over the electric car's whole life, including making the battery.",
  "battery electric vehicle life cycle emissions compared to internal combustion|electric vehicle lifecycle greenhouse gas",
  "kibocsatas_csokkentes_pct", "elektromos autó", "electric car",
  "electric vehicle life cycle assessment review")
T("vasut", 2, "mernok",
  "Mennyi CO2-t spórol, ha vonattal utazunk autó és repülő helyett?", "How much CO2 is saved by taking the train instead of car or plane?",
  "A vonat sok utast visz egyszerre, és gyakran árammal megy.",
  "A train carries many passengers at once and often runs on electricity.",
  "modal shift rail greenhouse gas emissions reduction|high speed rail emissions compared to aviation|rail passenger transport life cycle emissions",
  "kibocsatas_csokkentes_pct", "vasúti közlekedés", "rail transport",
  "rail transport emissions review")
T("kerekpar", 2, "mernok",
  "Mennyit segít, ha többen kerékpárral járnak?", "How much does it help if more people cycle?",
  "A rövid városi utak egy részét kerékpárral is meg lehet tenni.",
  "Many short city trips can be made by bicycle.",
  "cycling mode shift carbon emissions reduction|active travel climate change mitigation|bicycle commuting emissions savings",
  "kibocsatas_csokkentes_pct", "kerékpáros közlekedés", "utility cycling",
  "active travel emissions review")
T("tavmunka", 2, "mernok",
  "Csökkenti-e a kibocsátást az otthoni munka?", "Does working from home cut emissions?",
  "Kevesebb az ingázás, de otthon több a fűtés és az áram.",
  "There is less commuting, but more heating and electricity at home.",
  "teleworking energy consumption emissions review|remote work commuting emissions net effect",
  "kibocsatas_csokkentes_pct", "távmunka", "telecommuting",
  "telework energy review")
T("kondenzcsik", 2, "fizika",
  "Mennyit melegítenek a repülők kondenzcsíkjai?", "How much do aircraft contrails warm the Earth?",
  "A repülők mögötti fehér csíkok vékony felhőként csapdába ejtik a hőt. Elkerülhetők, ha a gép más magasságon repül.",
  "The white trails behind aircraft trap heat like thin clouds. Flying at another altitude can avoid them.",
  "contrail cirrus radiative forcing|aviation non-CO2 effects contrails mitigation|contrail avoidance flight altitude",
  "sugarzasi_kenyszer_w_m2", "kondenzcsík", "contrail",
  "aviation contrails climate review")
T("varosi_fak", 2, "egeszseg",
  "Mennyivel hűvösebb a fák alatt a város?", "How much cooler is the city under trees?",
  "A fák árnyéka és párologtatása nyáron hűti az utcát.",
  "Tree shade and evaporation cool the street in summer.",
  "urban trees cooling effect air temperature|urban greening heat island mitigation meta-analysis|street trees land surface temperature",
  "lehules_c", "városi hősziget", "urban heat island",
  "urban green space cooling review")
T("feher_teto", 2, "egeszseg",
  "Mennyit hűtenek a világos tetők?", "How much do light-coloured roofs cool?",
  "A fehér tető visszaveri a napfényt, ezért kevésbé melegszik fel a ház.",
  "A white roof reflects sunlight, so the house heats up less.",
  "cool roofs high albedo urban temperature reduction|reflective roofs cooling energy savings",
  "lehules_c", "hűvös tető", "reflective surfaces climate engineering",
  "cool roofs review")
T("zoldteto", 2, "egeszseg",
  "Mennyit hűt a zöldtető?", "How much does a green roof cool?",
  "A növényekkel borított tető hűti az épületet, és visszatartja az esővizet.",
  "A roof covered in plants cools the building and holds back rainwater.",
  "green roof cooling effect building energy|green roofs urban heat island temperature reduction",
  "lehules_c", "zöldtető", "green roof",
  "green roofs review")
T("hoseg_riasztas", 2, "egeszseg",
  "Hány életet ment a hőségriasztás?", "How many lives do heat warnings save?",
  "Figyelmeztetés, hűvös termek és segítség az időseknek a hőhullámok idején.",
  "Warnings, cool rooms and help for the elderly during heatwaves.",
  "heat health warning system mortality reduction|heat action plan effectiveness mortality",
  "kockazat_csokkentes_pct", "hőségriasztás", "heat health warning",
  "heat action plans effectiveness review")
T("korai_riasztas", 2, "egeszseg",
  "Hány életet ment az árvíz- és viharriasztás?", "How many lives do flood and storm warnings save?",
  "Ha időben szólnak, az emberek elmenekülhetnek és megvédhetik a házukat.",
  "With warnings in time, people can flee and protect their homes.",
  "early warning systems disaster mortality reduction|flood early warning effectiveness|tropical cyclone early warning mortality",
  "kockazat_csokkentes_pct", "korai előrejelző rendszer", "early warning system",
  "early warning systems effectiveness review")

# =============================================================================
# III. Átalakulás: új energia, új anyagok, CO2-kivonás
# =============================================================================
T("bioszen", 3, "kemia",
  "Mennyi CO2-t vonhat ki a levegőből a bioszén?", "How much CO2 can biochar remove from the air?",
  "A bioszén elszenesített növényi hulladék. A talajba keverve hosszú ideig tárolja a szenet.",
  "Biochar is charred plant waste. Mixed into soil, it stores carbon for a long time.",
  "biochar carbon dioxide removal potential global|biochar soil carbon sequestration meta-analysis|" + NET_REVIEW,
  CDR, "bioszén", "biochar", "biochar carbon sequestration review",
  ("Bioszén a tervedben.", "Biochar in your plan."))
T("kozet", 3, "fold",
  "Mennyit segít a kőzetmállasztás?", "How much does rock weathering help?",
  "Finomra őrölt kőzetet szórnak a földekre, ami lassan megköti a levegő CO2-jét.",
  "Finely ground rock is spread on fields, where it slowly binds CO2 from the air.",
  "enhanced rock weathering carbon dioxide removal potential|enhanced weathering croplands global potential|" + NET_REVIEW,
  CDR, "kőzetmállás szén-dioxid", "enhanced weathering", "enhanced rock weathering review",
  ("Kőzetpor a földekre a tervedben.", "Rock dust on fields in your plan."))
T("levegoszures", 3, "mernok",
  "Mennyi CO2-t szűrhetnek ki gépek a levegőből?", "How much CO2 can machines filter from the air?",
  "Nagy ventilátoros gépek kiszűrik a CO2-t, és a föld alá zárják. Sok energiát igényel.",
  "Large fan-driven machines filter out CO2 and store it underground. It takes a lot of energy.",
  "direct air capture carbon dioxide removal potential cost|direct air carbon capture and storage scale-up|" + NET_REVIEW,
  CDR, "szén-dioxid-leválasztás levegőből", "direct air capture", "direct air capture review",
  ("CO2-szűrés a levegőből a tervedben.", "Filtering CO2 from the air in your plan."))
T("novenyi_energia", 3, "energia",
  "Mennyi CO2-t zárhat a föld alá a növényi energia?", "How much CO2 can plant-based energy lock underground?",
  "Növényeket égetnek energiáért, a keletkező CO2-t pedig a föld alá zárják.",
  "Plants are burned for energy, and the resulting CO2 is stored underground.",
  "bioenergy with carbon capture and storage BECCS removal potential|BECCS land use sustainable potential|" + NET_REVIEW,
  CDR, "biomassza szén-dioxid-tárolás", "bioenergy with carbon capture and storage", "BECCS review",
  ("Növényi energia CO2-tárolással a tervedben.", "Plant energy with CO2 storage in your plan."))
T("mof", 3, "kemia",
  "Megköthetik-e a CO2-t a lyukacsos, fémtartalmú kristályok?", "Can porous metal-containing crystals capture CO2?",
  "Ezeknek a kristályoknak apró pórusai vannak, amelyek megkötik a gázokat, akár a levegőből is.",
  "These crystals have tiny pores that trap gases, even from the air.",
  "metal-organic frameworks CO2 capture performance|MOF direct air capture sorbent|metal-organic framework carbon capture humid conditions",
  "megkotes_mmol_g", "fémorganikus vázszerkezet", "metal–organic framework",
  "metal-organic frameworks carbon capture review")
T("perovszkit", 3, "anyag",
  "Lehet-e jobb napelemet gyártani perovszkitból?", "Can perovskite make better solar cells?",
  "A perovszkit egy kristályszerkezet. Vékony rétege a szilíciummal együtt több fényt alakít áramra.",
  "Perovskite is a crystal structure. A thin layer of it on silicon turns more light into electricity.",
  "perovskite silicon tandem solar cell efficiency|perovskite solar cell stability degradation|perovskite solar cell efficiency record",
  "hatasfok_pct", "perovszkit napelem", "perovskite solar cell",
  "perovskite solar cells review")
T("litium_akku", 3, "anyag",
  "Mennyi energiát tárolnak a mai akkumulátorok?", "How much energy do today's batteries store?",
  "A lítiumion-akkumulátor hajtja a villanyautókat, és tárolja a napenergiát.",
  "Lithium-ion batteries power electric cars and store solar energy.",
  "lithium-ion battery energy density progress|lithium-ion battery cathode energy density|high nickel cathode lithium-ion energy density",
  "energiasuruseg_wh_kg", "lítiumion-akkumulátor", "lithium-ion battery",
  "lithium-ion battery review")
T("szilard_akku", 3, "anyag",
  "Jobb lesz-e a szilárd elektrolitos akkumulátor?", "Will solid-state batteries be better?",
  "Ebben folyadék helyett szilárd anyag vezeti az áramot. Biztonságosabb lehet, és többet tárolhat.",
  "In these, a solid material carries the current instead of a liquid. They may be safer and store more.",
  "solid-state lithium metal battery energy density|solid electrolyte battery review|sulfide solid electrolyte all-solid-state battery",
  "energiasuruseg_wh_kg", "szilárdtest-akkumulátor", "solid-state battery",
  "solid-state battery review")
T("natrium_akku", 3, "anyag",
  "Kiválthatja-e a nátrium a lítiumot az akkumulátorban?", "Can sodium replace lithium in batteries?",
  "A nátrium olcsó, és bőven van belőle, például a konyhasóban.",
  "Sodium is cheap and plentiful, for example in table salt.",
  "sodium-ion battery energy density cost|sodium-ion battery cathode materials|sodium-ion battery commercialization",
  "energiasuruseg_wh_kg", "nátriumion-akkumulátor", "sodium-ion battery",
  "sodium-ion battery review")
T("akku_ujra", 3, "kemia",
  "Mennyi fém nyerhető vissza a régi akkumulátorokból?", "How much metal can be recovered from old batteries?",
  "A lítium, a kobalt és a nikkel újra felhasználható, ha visszanyerik.",
  "Lithium, cobalt and nickel can be used again if they are recovered.",
  "lithium-ion battery recycling recovery efficiency|hydrometallurgical battery recycling|direct recycling lithium-ion cathode",
  "hatasfok_pct", "akkumulátor-újrahasznosítás", "battery recycling",
  "lithium-ion battery recycling review")
T("hidrogen", 3, "kemia",
  "Milyen hatékonyan lesz vízből hidrogén?", "How efficiently can water be turned into hydrogen?",
  "Árammal a víz hidrogénre és oxigénre bontható. A hidrogén tiszta üzemanyag lehet.",
  "Electricity can split water into hydrogen and oxygen. Hydrogen can be a clean fuel.",
  "water electrolysis efficiency PEM alkaline|green hydrogen production electrolyzer efficiency|solid oxide electrolysis efficiency",
  "hatasfok_pct", "vízbontás hidrogén", "electrolysis of water",
  "water electrolysis hydrogen review")
T("uzemanyagcella", 3, "kemia",
  "Milyen hatásfokú az üzemanyagcella?", "How efficient is a fuel cell?",
  "Az üzemanyagcella hidrogénből égés nélkül állít elő áramot, csak víz keletkezik.",
  "A fuel cell makes electricity from hydrogen without burning; only water is produced.",
  "fuel cell efficiency review|proton exchange membrane fuel cell efficiency durability|solid oxide fuel cell efficiency",
  "hatasfok_pct", "üzemanyagcella", "fuel cell",
  "fuel cell review")
T("zold_acel", 3, "anyag",
  "Gyártható-e acél szén helyett hidrogénnel?", "Can steel be made with hydrogen instead of coal?",
  "Az acélgyártás az egyik legnagyobb kibocsátó. A hidrogén kiválthatja a kokszot.",
  "Steelmaking is one of the largest emitters. Hydrogen can replace coke.",
  "hydrogen direct reduction steel emissions reduction|green steel decarbonization|hydrogen-based steelmaking life cycle",
  "kibocsatas_csokkentes_pct", "acélgyártás", "hydrogen direct reduced iron",
  "steel decarbonization review")
T("cement", 3, "anyag",
  "Mennyivel csökkenthető a cementgyártás kibocsátása?", "How much can cement emissions be cut?",
  "A cementgyártás a mészkő hevítésekor is CO2-t enged ki, nem csak az égetéstől.",
  "Making cement releases CO2 when limestone is heated, not only from burning fuel.",
  "cement clinker substitution CO2 emissions reduction|low carbon cement limestone calcined clay|cement industry decarbonization pathways",
  "kibocsatas_csokkentes_pct", "cement", "environmental impact of concrete",
  "cement decarbonization review")
T("zold_ammonia", 3, "kemia",
  "Gyártható-e műtrágya kibocsátás nélkül?", "Can fertiliser be made without emissions?",
  "Az ammóniát ma földgázból gyártják. Tiszta hidrogénnel kibocsátás nélkül is lehetne.",
  "Ammonia is made from natural gas today. With clean hydrogen it could be made without emissions.",
  "green ammonia production emissions|electrochemical ammonia synthesis decarbonization|renewable ammonia life cycle assessment",
  "kibocsatas_csokkentes_pct", "ammónia", "green ammonia",
  "green ammonia review")
T("szintetikus_kerozin", 3, "kemia",
  "Repülhetünk-e áramból és CO2-ből gyártott üzemanyaggal?", "Can we fly on fuel made from electricity and CO2?",
  "Hidrogénből és a levegő CO2-jéből szintetikus repülőgép-üzemanyag készülhet.",
  "Synthetic jet fuel can be made from hydrogen and CO2 from the air.",
  "power-to-liquid synthetic kerosene aviation emissions|electrofuels aviation life cycle emissions|sustainable aviation fuel greenhouse gas reduction",
  "kibocsatas_csokkentes_pct", "szintetikus üzemanyag", "electrofuel",
  "sustainable aviation fuels review")
T("fa_epulet", 3, "anyag",
  "Mennyi CO2-t spórol, ha fából építünk beton helyett?", "How much CO2 is saved by building with wood instead of concrete?",
  "A fa építés után is tárolja a szenet, és kiválthatja a betont és az acélt.",
  "Wood keeps storing carbon after it is built in, and can replace concrete and steel.",
  "mass timber buildings embodied carbon compared to concrete|cross-laminated timber life cycle emissions|wood construction substitution effect",
  "kibocsatas_csokkentes_pct", "faépítészet", "mass timber",
  "timber buildings carbon review")
T("muanyag", 3, "kemia",
  "Mennyit spórol a műanyag újrahasznosítása?", "How much does recycling plastic save?",
  "Az új műanyag kőolajból készül. Az újrahasznosítás ennek egy részét kiválthatja.",
  "New plastic is made from oil. Recycling can replace part of it.",
  "plastic recycling greenhouse gas emissions savings|chemical recycling plastics life cycle assessment|mechanical recycling plastics emissions",
  "kibocsatas_csokkentes_pct", "műanyag újrahasznosítás", "plastic recycling",
  "plastic recycling life cycle review")
T("gyari_co2", 3, "mernok",
  "Mennyi CO2 fogható fel a gyárkéményekben?", "How much CO2 can be captured from factory chimneys?",
  "Az erőművek és gyárak füstjéből a CO2 kiválasztható, mielőtt a levegőbe jut.",
  "CO2 can be separated from the smoke of power plants and factories before it reaches the air.",
  "post-combustion carbon capture efficiency|carbon capture and storage industrial capture rate|amine carbon capture energy penalty",
  "hatasfok_pct", "szén-dioxid-leválasztás", "carbon capture and storage",
  "carbon capture and storage review")
T("co2_tarolas", 3, "fold",
  "Biztonságosan tárolható-e a CO2 a föld alatt?", "Can CO2 be stored safely underground?",
  "A kiválasztott CO2-t mély kőzetrétegekbe sajtolják. Mennyi szivároghat vissza?",
  "Captured CO2 is pumped into deep rock layers. How much could leak back?",
  "geological CO2 storage leakage risk|CO2 storage capacity saline aquifers|CO2 mineralization basalt storage",
  "reszarany_pct", "szén-dioxid tárolás föld alatt", "carbon sequestration",
  "geological carbon storage review")
T("tengeri_szel", 3, "energia",
  "Mennyi kibocsátást válthat ki a tengeri szélenergia?", "How much emission can offshore wind replace?",
  "A tengeren erősebb és egyenletesebb a szél, mint a szárazföldön.",
  "At sea the wind is stronger and steadier than on land.",
  "offshore wind technical potential global|floating offshore wind potential|offshore wind greenhouse gas mitigation",
  "kibocsatas_potencial_gtco2e_ev", "tengeri szélerőmű", "offshore wind power",
  "offshore wind energy review")
T("atomenergia", 3, "fizika",
  "Mennyi kibocsátást válthat ki az atomenergia?", "How much emission can nuclear power replace?",
  "Az atomerőmű nem éget semmit, de az építésnek és az üzemanyagnak is van kibocsátása.",
  "A nuclear plant burns nothing, but building it and its fuel cause some emissions.",
  "nuclear power life cycle greenhouse gas emissions|nuclear energy climate change mitigation potential|small modular reactors decarbonization",
  "kibocsatas_potencial_gtco2e_ev", "atomenergia", "nuclear power",
  "nuclear power climate mitigation review")
T("vizi_tarolo", 3, "energia",
  "Milyen hatékony az energiatárolás víztározókkal?", "How efficient is energy storage with reservoirs?",
  "Ha sok az áram, vizet szivattyúznak fel. Ha kevés, leengedik, és turbinát hajt.",
  "When power is plentiful, water is pumped up. When it is scarce, it flows down and drives a turbine.",
  "pumped hydro energy storage round-trip efficiency|pumped storage hydropower potential|closed-loop pumped hydro storage",
  "hatasfok_pct", "szivattyús energiatározó", "pumped-storage hydroelectricity",
  "pumped hydro storage review")
T("hotarolas", 3, "fizika",
  "Eltehető-e a napenergia hőként, sóban vagy kőben?", "Can solar energy be stored as heat, in salt or stone?",
  "A felforrósított só vagy kő órákig, akár napokig megtartja a hőt.",
  "Heated salt or stone holds heat for hours or even days.",
  "thermal energy storage molten salt efficiency|sand rock thermal energy storage|Carnot battery round-trip efficiency",
  "hatasfok_pct", "hőtárolás", "thermal energy storage",
  "thermal energy storage review")
T("ipari_hoszivattyu", 3, "energia",
  "Mennyit spórolhat a gyárakban a hőszivattyú?", "How much can heat pumps save in factories?",
  "Sok gyár forró vizet és gőzt használ. Ipari hőszivattyú is előállíthatja áramból.",
  "Many factories use hot water and steam. Industrial heat pumps can make it from electricity.",
  "industrial heat pumps decarbonization potential process heat|high temperature heat pump industrial applications",
  "kibocsatas_csokkentes_pct", "ipari hőszivattyú", "industrial heat pump",
  "industrial heat pumps review")
T("biogaz", 3, "energia",
  "Mennyi kibocsátást spórol a biogáz?", "How much emission does biogas save?",
  "A trágya és az ételmaradék erjesztésekor éghető gáz keletkezik.",
  "Fermenting manure and food waste produces a gas that can be burned.",
  "biogas anaerobic digestion greenhouse gas emissions savings|biomethane life cycle emissions|anaerobic digestion food waste life cycle assessment",
  "kibocsatas_csokkentes_pct", "biogáz", "biogas",
  "biogas life cycle review")
T("teherauto", 3, "mernok",
  "Mennyit spórol az elektromos teherautó?", "How much does an electric truck save?",
  "A teherautók sok gázolajat fogyasztanak. Akkumulátorral hosszabb utakra is képesek.",
  "Trucks burn a lot of diesel. With batteries they can also make longer trips.",
  "battery electric heavy-duty truck life cycle emissions|electric trucks emissions reduction|zero emission heavy duty vehicles",
  "kibocsatas_csokkentes_pct", "elektromos teherautó", "electric truck",
  "electric heavy-duty trucks review")
T("hajozas", 3, "mernok",
  "Mennyivel csökkenthető a hajózás kibocsátása?", "How much can shipping emissions be cut?",
  "A teherhajók nehézolajat égetnek. Új üzemanyag, lassabb haladás vagy szélvitorla segíthet.",
  "Cargo ships burn heavy fuel oil. New fuels, slower sailing or wind sails can help.",
  "shipping decarbonization emissions reduction potential|wind-assisted ship propulsion fuel savings|slow steaming emissions reduction",
  "kibocsatas_csokkentes_pct", "hajózás kibocsátás", "environmental impact of shipping",
  "shipping decarbonization review")
T("urbeli_napelem", 3, "ur",
  "Küldhetnek-e áramot a Földre napelemek a világűrből?", "Could solar panels in space send power to Earth?",
  "Az űrben mindig süt a Nap. Az áramot rádióhullámokkal sugároznák le a Földre.",
  "In space the Sun always shines. The power would be beamed down to Earth by radio waves.",
  "space-based solar power feasibility|space solar power wireless power transmission efficiency",
  "hatasfok_pct", "űrbeli napenergia", "space-based solar power",
  "space-based solar power review")

# =============================================================================
# IV. Helyreállítás: erdők, vizek, talaj, és a kockázatos ötletek
# =============================================================================
T("erdo", 4, "biologia",
  "Mennyi CO2-t köthet meg az erdősítés?", "How much CO2 can new forests store?",
  "Új erdők telepítése: a fák növekedés közben szenet építenek be.",
  "Planting new forests: trees build carbon into themselves as they grow.",
  "afforestation reforestation carbon dioxide removal potential global|global tree restoration potential carbon|" + NET_REVIEW,
  CDR, "erdősítés", "afforestation", "afforestation carbon sequestration review",
  ("Erdősítés a tervedben.", "Afforestation in your plan."))
T("erdo_magatol", 4, "biologia",
  "Mennyi szenet köt meg az erdő, ha hagyjuk magától visszanőni?", "How much carbon does a forest store if left to regrow by itself?",
  "Az elhagyott földeken az erdő ültetés nélkül is visszanőhet.",
  "On abandoned land, forest can grow back without planting.",
  "natural forest regrowth carbon accumulation rates|natural regeneration versus tree planting carbon|secondary forest carbon sequestration",
  CDR, "erdő természetes felújulás", "natural regeneration",
  "natural forest regeneration carbon review")
T("talaj", 4, "mezogazdasag",
  "Mennyi szenet köthet meg újra a talaj?", "How much carbon can soil store again?",
  "Takarónövényekkel és kíméletes műveléssel a talaj több szenet tarthat meg.",
  "With cover crops and gentle tillage, soil can hold more carbon.",
  "soil carbon sequestration global potential croplands|soil organic carbon sequestration practices meta-analysis|" + NET_REVIEW,
  CDR, "talaj szerves szén", "soil carbon", "soil carbon sequestration review",
  ("Több szén a talajban a tervedben.", "More carbon in soil in your plan."))
T("agroerdeszet", 4, "mezogazdasag",
  "Mennyi szenet köt meg a fákkal tarkított szántó és legelő?", "How much carbon do fields and pastures with trees store?",
  "Fák a szántók és legelők között: árnyék, szén és termés egyszerre.",
  "Trees among fields and pastures: shade, carbon and harvest at once.",
  "agroforestry carbon sequestration meta-analysis|silvopasture carbon storage|agroforestry soil organic carbon",
  CDR, "agrárerdészet", "agroforestry",
  "agroforestry carbon review")
T("lap", 4, "fold",
  "Mennyi szenet ment meg a lápok újra elárasztása?", "How much carbon does rewetting peatlands save?",
  "A kiszárított láp szenet enged ki. Ha újra vizes lesz, megint tárolja.",
  "A drained peatland releases carbon. Made wet again, it stores carbon once more.",
  "peatland rewetting greenhouse gas emissions reduction|peatland restoration carbon|drained peatland emissions",
  CDR, "láp", "peatland",
  "peatland rewetting review")
T("mangrove", 4, "biologia",
  "Mennyi szenet tárolnak a mangroveerdők?", "How much carbon do mangrove forests store?",
  "A trópusi partok mangroveerdői sok szenet zárnak a sáros talajba, és védik a partot.",
  "Mangrove forests on tropical coasts lock a lot of carbon in their muddy soil and protect the shore.",
  "mangrove blue carbon sequestration rate|mangrove restoration carbon|mangrove soil carbon stocks",
  CDR, "mangrove", "mangrove",
  "mangrove blue carbon review")
T("tengerifu", 4, "biologia",
  "Mennyi szenet köt meg a tengerifű?", "How much carbon does seagrass store?",
  "A sekély tengerek fűmezői szenet raktároznak az aljzatban.",
  "Meadows of seagrass in shallow seas store carbon in the seabed.",
  "seagrass blue carbon sequestration|seagrass meadow restoration carbon|seagrass sediment carbon stocks",
  CDR, "tengerifű", "seagrass",
  "seagrass blue carbon review")
T("moszaterdo", 4, "biologia",
  "Megköthet-e szenet a tengeri moszaterdő?", "Can kelp forests store carbon?",
  "A nagy barna moszatok gyorsan nőnek. Ha a mélybe süllyednek, a szén ott maradhat.",
  "Large brown seaweeds grow fast. If they sink to the deep, the carbon can stay there.",
  "kelp forest carbon sequestration|macroalgae cultivation carbon dioxide removal|seaweed carbon export deep ocean",
  CDR, "barnamoszatok", "kelp forest",
  "seaweed carbon sequestration review")
T("korall_ujra", 4, "biologia",
  "Megmenthetők-e a korallzátonyok ültetéssel?", "Can coral reefs be saved by replanting?",
  "Korallokat nevelnek és telepítenek vissza, köztük olyanokat, amelyek jobban bírják a meleget.",
  "Corals are grown and replanted, including ones that cope better with heat.",
  "coral reef restoration effectiveness survival|assisted evolution heat tolerant corals|coral gardening outplanting survival",
  "reszarany_pct", "korallzátony helyreállítása", "coral reef restoration",
  "coral reef restoration review")
T("ocean_lugositas", 4, "kemia",
  "Vonhat-e ki több CO2-t a tenger, ha lúgosabbá tesszük?", "Can the sea take up more CO2 if we make it more alkaline?",
  "Ásványi port juttatnak a tengerbe, így a víz több CO2-t nyel el a levegőből.",
  "Mineral powder is added to the sea, so the water absorbs more CO2 from the air.",
  "ocean alkalinity enhancement carbon dioxide removal potential|ocean alkalinity enhancement side effects|" + NET_REVIEW,
  CDR, "óceán lúgosítás", "ocean alkalinity enhancement",
  "ocean alkalinity enhancement review")
T("vas_tenger", 4, "fold",
  "Segít-e, ha vassal trágyázzuk a tengert?", "Does fertilising the sea with iron help?",
  "A vas serkenti a tengeri algák növekedését. Kérdés, mennyi szén süllyed le tartósan.",
  "Iron boosts the growth of ocean algae. The question is how much carbon sinks for good.",
  "ocean iron fertilization carbon sequestration experiments|iron fertilization efficiency carbon export",
  CDR, "vastrágyázás óceán", "iron fertilization",
  "ocean iron fertilization review")
T("ozon", 4, "kemia",
  "Mennyi melegedést előzött meg az ózonréteg védelme?", "How much warming did protecting the ozone layer prevent?",
  "A régi hűtőgázok az ózont bontották, és a Földet is melegítették. A betiltásuk mindkettőn segített.",
  "Old refrigerant gases destroyed ozone and also warmed the Earth. Banning them helped both.",
  "Montreal Protocol avoided global warming|ozone layer recovery climate benefit|CFC phase-out avoided climate change",
  "elkerult_melegedes_c", "montreali jegyzőkönyv", "Montreal Protocol",
  "Montreal Protocol climate benefits review")
T("metan_bontas", 4, "kemia",
  "Lebontható-e a metán közvetlenül a levegőből?", "Can methane be broken down directly in the air?",
  "Kísérleti módszerek a levegőben lévő metánt gyorsabban bontanák le, mint a természet.",
  "Experimental methods would break down methane in the air faster than nature does.",
  "atmospheric methane removal technologies|methane removal photocatalysis|iron salt aerosol methane oxidation",
  "metan_csokkentes_pct", "metán lebomlás légkör", "atmospheric methane removal",
  "atmospheric methane removal review")
T("fuzio", 4, "fizika",
  "Mennyi energiát nyernek ma a magfúziós kísérletek?", "How much energy do fusion experiments produce today?",
  "A Nap energiáját utánozza: könnyű atommagok egyesülnek, és sok energia szabadul fel.",
  "It copies the Sun: light atomic nuclei fuse and release a lot of energy.",
  "inertial confinement fusion target gain ignition|tokamak fusion energy gain record|fusion power plant timeline review",
  "energia_nyereseg", "magfúzió", "fusion power",
  "fusion energy review")
T("napernyo", 4, "fizika",
  "Mennyire hűtene a kén a magaslégkörben?", "How much would sulphur in the upper atmosphere cool the Earth?",
  "A magaslégkörbe juttatott kén visszaverné a napfényt. Nagy a kockázata: ha leáll, gyors melegedés jön.",
  "Sulphur in the upper atmosphere would reflect sunlight. The risk is high: if it stops, rapid warming follows.",
  "stratospheric aerosol injection radiative forcing per Tg SO2|stratospheric sulfate geoengineering efficacy|solar geoengineering termination shock",
  "sai_kenyszer_w_m2_per_tg", "napsugárzás-módosítás", "stratospheric aerosol injection",
  "stratospheric aerosol injection review",
  ("Csak megérted: a játékban nem vezethető be.", "Understanding only: it cannot be deployed in the game."))
T("felho_fenyesites", 4, "fizika",
  "Hűthetik-e a Földet a fényesebbé tett tengeri felhők?", "Could brighter sea clouds cool the Earth?",
  "Tengervíz-permetet fújnának a felhőkbe, így azok több napfényt vernének vissza. Kockázatos ötlet.",
  "Sea-water spray would be blown into clouds so they reflect more sunlight. A risky idea.",
  "marine cloud brightening cooling potential|marine cloud brightening aerosol cloud interactions",
  "sugarzasi_kenyszer_w_m2", "felhőfényesítés", "marine cloud brightening",
  "marine cloud brightening review",
  ("Csak megérted: a játékban nem vezethető be.", "Understanding only: it cannot be deployed in the game."))
T("cirrus", 4, "fizika",
  "Hűtene-e a magas jégfelhők ritkítása?", "Would thinning high ice clouds cool the Earth?",
  "A vékony, magas jégfelhők csapdába ejtik a hőt. Ritkításuk hűthetne, de nagyon bizonytalan.",
  "Thin, high ice clouds trap heat. Thinning them might cool, but it is very uncertain.",
  "cirrus cloud thinning climate engineering|cirrus seeding radiative effect",
  "sugarzasi_kenyszer_w_m2", "pehelyfelhő", "cirrus cloud thinning",
  "cirrus cloud thinning review",
  ("Csak megérted: a játékban nem vezethető be.", "Understanding only: it cannot be deployed in the game."))
T("urbeli_arnyekolo", 4, "ur",
  "Hűthetné-e a Földet egy árnyékoló a világűrben?", "Could a sunshade in space cool the Earth?",
  "Egy óriási árnyékoló a Nap és a Föld között kevesebb napfényt engedne át.",
  "A giant shade between the Sun and the Earth would let less sunlight through.",
  "space sunshade solar radiation management Lagrange point|space-based geoengineering sunshade",
  "sugarzasi_kenyszer_w_m2", "űrbeli napernyő", "space sunshade",
  "space-based solar geoengineering review",
  ("Csak megérted: a játékban nem vezethető be.", "Understanding only: it cannot be deployed in the game."))


def validate() -> list:
    """Hibák listája (üres, ha minden rendben)."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from aether_lab.evidence import PARAMETERS
    errs, ids, wikis = [], set(), set()
    for t in TEMAK:
        if t["id"] in ids:
            errs.append(f"dupla id: {t['id']}")
        ids.add(t["id"])
        if not t["id"].isascii():
            errs.append(f"nem ASCII id: {t['id']}")
        if t["wiki_en"].lower() in wikis:
            errs.append(f"dupla wiki_en: {t['wiki_en']}")
        wikis.add(t["wiki_en"].lower())
        if t["korszak"] not in (1, 2, 3, 4):
            errs.append(f"rossz korszak: {t['id']}")
        if t["terulet"] not in TERULETEK:
            errs.append(f"rossz terület: {t['id']}")
        for p in t["parameterek"].split(","):
            if p not in PARAMETERS:
                errs.append(f"ismeretlen paraméter {p}: {t['id']}")
        for k in ("cim", "cim_en", "magyarazat", "magyarazat_en", "kereses", "wiki", "wiki_en", "attekintes"):
            if not str(t[k]).strip():
                errs.append(f"üres {k}: {t['id']}")
        if not t["cim"].endswith("?") or not t["cim_en"].endswith("?"):
            errs.append(f"a cím nem kérdés: {t['id']}")
    return errs


def catalog() -> dict:
    return {"terulet": {k: {"nev": v[0], "nev_en": v[1]} for k, v in TERULETEK.items()}, "temak": TEMAK}


def main() -> int:
    errs = validate()
    if errs:
        print("\n".join(errs))
        return 1
    OUT.write_text(json.dumps(catalog(), ensure_ascii=False, indent=1), encoding="utf-8")
    per = {e: sum(1 for t in TEMAK if t["korszak"] == e) for e in (1, 2, 3, 4)}
    print(f"{len(TEMAK)} téma -> {OUT}  korszakonként: {per}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
