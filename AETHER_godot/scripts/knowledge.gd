extends RefCounted
## Tudásfa és korszakok (játékszabály, nem valós adat).
## A csomópontok valódi kutatási TÉMÁK, nem kitalált technológiák. Egy téma akkor
## „kutatott”, ha a kutatás legalább egy ellenőrzött számot talált róla (a szám a
## cikkekből jön, nem a játéktervezőtől). A korszakok a témák sorrendjét adják:
## előbb megérted a bajt, aztán mérsékled, aztán átalakítasz, végül helyreállítasz.

const L := preload("res://scripts/i18n.gd")

const CDR_PARAMS := "cdr_potencial_gtco2_ev,cdr_koltseg_usd_tco2"
const NET_REVIEW := "negative emissions technologies potentials costs side effects"

## A korszakok. "kell": ennyi kutatott téma kell az ELŐZŐ korszakból a belépéshez.
## A további feltételeket (bevezetett terv, bizalom, csökkenő kibocsátás) a campaign.gd nézi.
const ERAS := [
	{"nev": "Felismerés", "tema": "Mérés és megértés: mennyit melegít a CO2, mi lesz a terméssel."},
	{"nev": "Mérséklés", "tema": "Metán, víz, alkalmazkodás. Megnyílik a metán a tervedben.", "kell": 2},
	{"nev": "Átalakulás", "tema": "CO2 kivonása a levegőből: kutasd ki, és tedd a tervedbe.", "kell": 2,
	 "terv": true, "bizalom": 50},
	{"nev": "Helyreállítás", "tema": "Erdők, talaj, és a legkockázatosabb ötlet megértése.", "kell": 2,
	 "csokkeno_co2": true},
]
const ROMAN := ["I.", "II.", "III.", "IV."]

## A témák. "kereses": angol keresőkifejezések ("|" választja el), "parameterek": mely
## modellparaméterekhez keresünk számot; "wiki"/"wiki_en"/"attekintes": a „Mi ez, és mire jó?”
## magyarázat forrásai. "nyit": egy rövid mondat arról, mit ad a téma a játékban.
const TOPICS := [
	# --- I. Felismerés -------------------------------------------------------
	{"id": "tcre", "korszak": 1, "cim": "Mennyit melegít a kibocsátott CO2?",
	 "magyarazat": "Minden elégetett tonna szén-dioxid melegít. Mennyit, ha összeadjuk?",
	 "kereses": "transient climate response to cumulative CO2 emissions estimate|remaining carbon budget warming per 1000 GtCO2|TCRE observational constraint",
	 "parameterek": "tcre_c_per_1000gtco2", "wiki": "szén-dioxid globális felmelegedés", "wiki_en": "carbon budget",
	 "attekintes": "carbon budget cumulative emissions warming review",
	 "nyit": "Megérted, miért számít minden tonna."},
	{"id": "termes", "korszak": 1, "cim": "Mennyit csökken a termés, ha melegszik a Föld?",
	 "magyarazat": "A búza, a kukorica és a rizs érzékeny a hőségre. Mennyit veszít egy fok melegedéstől?",
	 "kereses": "crop yield change per degree of warming meta-analysis|temperature increase reduces global yields of major crops|maize wheat rice yield sensitivity to temperature",
	 "parameterek": "hozam_valtozas_pct_per_c", "wiki": "éghajlatváltozás mezőgazdaság", "wiki_en": "effects of climate change on agriculture",
	 "attekintes": "climate change crop yield review",
	 "nyit": "Megérted, miért kell alkalmazkodni is."},
	{"id": "kukorica", "korszak": 1, "cim": "Segítenek-e az aszálytűrő kukoricafajták?",
	 "magyarazat": "Ez nem hűti a Földet, de megvédheti a termést a forró, száraz években.",
	 "kereses": "drought tolerant maize yield advantage under drought|drought tolerant maize varieties yield on-farm trials",
	 "parameterek": "alkalmazkodas_hozam_elony_pct", "wiki": "kukorica szárazságtűrés", "wiki_en": "drought tolerance maize",
	 "attekintes": "drought tolerant maize review",
	 "nyit": "Aszálytűrő fajták a tervedben."},
	# --- II. Mérséklés -------------------------------------------------------
	{"id": "metan_rizs", "korszak": 2, "cim": "Mennyi metán spórolható meg a rizsföldeken?",
	 "magyarazat": "Az elárasztott rizsföld metánt enged a levegőbe. Ha időnként lecsapolják, kevesebbet.",
	 "kereses": "alternate wetting and drying rice methane emission reduction meta-analysis|rice paddy methane mitigation practices",
	 "parameterek": "metan_csokkentes_pct", "wiki": "rizs metán", "wiki_en": "alternate wetting and drying",
	 "attekintes": "rice paddy methane mitigation review",
	 "nyit": "Megérted, hol lehet gyorsan metánt spórolni."},
	{"id": "metan_gaz", "korszak": 2, "cim": "Mennyi metánszivárgás szüntethető meg a gáziparban?",
	 "magyarazat": "A földgáz főleg metán. A szivárgó kutakból és csövekből sok jut a levegőbe.",
	 "kereses": "oil and gas methane emissions abatement potential|methane leak detection and repair emission reduction|fossil fuel methane mitigation potential",
	 "parameterek": "metan_csokkentes_pct", "wiki": "földgáz metánszivárgás", "wiki_en": "methane emissions",
	 "attekintes": "oil and gas methane mitigation review",
	 "nyit": "Megérted, hol lehet gyorsan metánt spórolni."},
	{"id": "ontozes", "korszak": 2, "cim": "Mennyi vizet takarít meg a csepegtető öntözés?",
	 "magyarazat": "A csepegtető cső a vizet egyenesen a növény gyökeréhez juttatja.",
	 "kereses": "drip irrigation water saving compared to flood irrigation meta-analysis|drip irrigation water use efficiency yield",
	 "parameterek": "viztakarekossag_pct", "wiki": "csepegtető öntözés", "wiki_en": "drip irrigation",
	 "attekintes": "drip irrigation water saving review",
	 "nyit": "Megérted, hogyan védhető a víz aszályban."},
	# --- III. Átalakulás -----------------------------------------------------
	{"id": "bioszen", "korszak": 3, "cim": "Mennyi CO2-t vonhat ki a levegőből a bioszén?",
	 "magyarazat": "A bioszén elszenesített növényi hulladék. A talajba keverve hosszú ideig tárolja a szenet.",
	 "kereses": "biochar carbon dioxide removal potential global|biochar soil carbon sequestration meta-analysis|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "bioszén", "wiki_en": "biochar", "attekintes": "biochar carbon sequestration review",
	 "nyit": "Bioszén a tervedben."},
	{"id": "kozet", "korszak": 3, "cim": "Mennyit segít a kőzetmállasztás?",
	 "magyarazat": "Finomra őrölt kőzetet szórnak a földekre, ami lassan megköti a levegő CO2-jét.",
	 "kereses": "enhanced rock weathering carbon dioxide removal potential|enhanced weathering croplands global potential|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "kőzetmállás szén-dioxid", "wiki_en": "enhanced weathering",
	 "attekintes": "enhanced rock weathering review",
	 "nyit": "Kőzetpor a földekre a tervedben."},
	{"id": "levegoszures", "korszak": 3, "cim": "Mennyi CO2-t szűrhetnek ki gépek a levegőből?",
	 "magyarazat": "Nagy ventilátoros gépek kiszűrik a CO2-t, és a föld alá zárják. Sok energiát igényel.",
	 "kereses": "direct air capture carbon dioxide removal potential cost|direct air carbon capture and storage scale-up|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "szén-dioxid-leválasztás levegőből", "wiki_en": "direct air capture",
	 "attekintes": "direct air capture review",
	 "nyit": "CO2-szűrés a levegőből a tervedben."},
	{"id": "novenyi_energia", "korszak": 3, "cim": "Mennyi CO2-t zárhat a föld alá a növényi energia?",
	 "magyarazat": "Növényeket égetnek energiáért, a keletkező CO2-t pedig a föld alá zárják.",
	 "kereses": "bioenergy with carbon capture and storage BECCS removal potential|BECCS land use sustainable potential|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "biomassza szén-dioxid-tárolás", "wiki_en": "bioenergy with carbon capture and storage",
	 "attekintes": "BECCS review",
	 "nyit": "Növényi energia CO2-tárolással a tervedben."},
	# --- IV. Helyreállítás ---------------------------------------------------
	{"id": "erdo", "korszak": 4, "cim": "Mennyi CO2-t köthet meg az erdősítés?",
	 "magyarazat": "Új erdők telepítése: a fák növekedés közben szenet építenek be.",
	 "kereses": "afforestation reforestation carbon dioxide removal potential global|global tree restoration potential carbon|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "erdősítés", "wiki_en": "afforestation", "attekintes": "afforestation carbon sequestration review",
	 "nyit": "Erdősítés a tervedben."},
	{"id": "talaj", "korszak": 4, "cim": "Mennyi szenet köthet meg újra a talaj?",
	 "magyarazat": "Takarónövényekkel és kíméletes műveléssel a talaj több szenet tarthat meg.",
	 "kereses": "soil carbon sequestration global potential croplands|soil organic carbon sequestration practices meta-analysis|" + NET_REVIEW,
	 "parameterek": CDR_PARAMS, "wiki": "talaj szerves szén", "wiki_en": "soil carbon",
	 "attekintes": "soil carbon sequestration review",
	 "nyit": "Több szén a talajban a tervedben."},
	{"id": "napernyo", "korszak": 4, "cim": "Mennyire hűtene a kén a magaslégkörben?",
	 "magyarazat": "A magaslégkörbe juttatott kén visszaverné a napfényt. Nagy a kockázata: ha leáll, gyors melegedés jön.",
	 "kereses": "stratospheric aerosol injection radiative forcing per Tg SO2|stratospheric sulfate geoengineering efficacy|solar geoengineering termination shock",
	 "parameterek": "sai_kenyszer_w_m2_per_tg", "wiki": "napsugárzás-módosítás", "wiki_en": "stratospheric aerosol injection",
	 "attekintes": "stratospheric aerosol injection review",
	 "nyit": "Csak megérted: a játékban nem vezethető be."},
]


static func topic(id: String) -> Dictionary:
	for t in TOPICS:
		if t["id"] == id:
			return t
	return {}


static func topics_of(era: int) -> Array:
	return TOPICS.filter(func(t: Dictionary) -> bool: return int(t["korszak"]) == era)


static func count_done(done: Array, era: int) -> int:
	var n := 0
	for t in topics_of(era):
		if t["id"] in done:
			n += 1
	return n


static func era_name(era: int) -> String:
	return ROMAN[era - 1] + " " + L.t(ERAS[era - 1]["nev"])
