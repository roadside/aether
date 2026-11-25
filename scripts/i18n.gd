extends RefCounted
## Nyelvek: magyar (alap) és angol.
## Használat: const L := preload("res://scripts/i18n.gd")  ->  L.t("Kutatás")
## A kulcs maga a magyar szöveg; ha nincs angol fordítás, a magyar marad.

const SETTINGS := "user://beallitasok.cfg"
const I2 := preload("res://scripts/i18n_2.gd")
const I3 := preload("res://scripts/i18n_3.gd")       # az új játék szövegei   # további fordítások (külön fájl, hogy ne ütközzenek)

static var lang := ""


static func init() -> void:
	if lang != "":
		return
	var args := OS.get_cmdline_user_args()
	if "--en" in args or "--hu" in args:
		lang = "en" if "--en" in args else "hu"
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		lang = str(cfg.get_value("jatek", "nyelv", ""))
	if lang == "":
		lang = "hu" if OS.get_locale_language() == "hu" else "en"


## Ellenőrző futásban (dry) a beállítások csak a memóriában változnak, a fájl érintetlen marad.
static var dry := false
static var _mem := {}


static func set_lang(l: String) -> void:
	lang = l
	if dry:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("jatek", "nyelv", l)
	cfg.save(SETTINGS)


## Egyéb beállítások ugyanabban a fájlban (pl. a választott AI).
static func get_setting(key: String, default: Variant = "") -> Variant:
	if dry and _mem.has(key):
		return _mem[key]
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return default
	return cfg.get_value("jatek", key, default)


static func set_setting(key: String, value: Variant) -> void:
	if dry:
		_mem[key] = value
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("jatek", key, value)
	cfg.save(SETTINGS)


## A játékos országa (ISO-kód, pl. HU): a beállításból, különben a gép területi beállításából.
static func country() -> String:
	var c := str(get_setting("orszag", ""))
	if c == "":
		var parts := OS.get_locale().split("_")
		c = parts[1] if parts.size() > 1 else "HU"
	return c.to_upper().left(2)


static func is_en() -> bool:
	init()
	return lang == "en"


static func t(hu: String) -> String:
	if not is_en():
		return hu
	return I3.EN.get(hu, EN.get(hu, I2.EN.get(hu, hu)))


## Adatmező a választott nyelven (pl. "cim" -> "cim_en", ha van).
static func field(d: Dictionary, key: String) -> String:
	if is_en() and d.has(key + "_en"):
		return str(d[key + "_en"])
	return str(d.get(key, ""))


## Szám a nyelvnek megfelelő tizedesjellel.
static func num(x: float, decimals: int = 1) -> String:
	var s := ("%." + str(maxi(decimals, 0)) + "f") % x       # mindig ugyanannyi tizedes: +1,50 és +1,58 egymás mellett is rendezett
	return s if is_en() else s.replace(".", ",")


## Magyar toldalék szám után: „2060-re” → „2060-ra” (a kiejtett szám hangrendje szerint). Angolul változatlan.
static func rag(text: String) -> String:
	if is_en():
		return text
	var re := RegEx.new()
	re.compile("(\\d+)-r[ae](?![a-zA-Záéíóöőúüű])")
	var out := text
	for m in re.search_all(text):
		var digits := m.get_string(1)
		var back := false      # mély hangrendű-e az utolsó kiejtett tag
		var pos := digits.length() - 1
		while pos > 0 and digits[pos] == "0":
			pos -= 1
		var d := int(digits[pos])
		match digits.length() - 1 - pos:
			0: back = d in [3, 6, 8]                 # három, hat, nyolc
			1: back = d in [2, 3, 6, 8]              # húsz, harminc, hatvan, nyolcvan
			2: back = true                           # száz
			_: back = false                          # ezer
		out = out.replace(m.get_string(0), digits + ("-ra" if back else "-re"))
	return out


## Szám legfeljebb ennyi tizedessel, a felesleges nullák nélkül (5,0 -> 5; 0,50 -> 0,5).
static func num_short(x: float, decimals: int = 2) -> String:
	var s := String.num(snappedf(x, pow(10.0, -decimals)), decimals)
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	return s if is_en() else s.replace(".", ",")


const CATEGORY := {
	"aszaly": ["Aszály", "Drought"], "arviz": ["Árvíz", "Flood"], "vihar": ["Vihar", "Storm"],
	"foldrenges": ["Földrengés", "Earthquake"], "vulkan": ["Vulkán", "Volcano"], "tuz": ["Erdőtűz", "Wildfire"],
	"jeg": ["Jég és hó", "Ice and snow"], "levego": ["Levegőminőség", "Air quality"],
	"szennyezes": ["Szennyezés", "Pollution"], "viz": ["Vízminőség", "Water quality"], "hoseg": ["Hőség", "Heat"], "tenger": ["Óceán", "Ocean"],
	"ehezes": ["Élelmiszerhiány", "Food insecurity"], "jarvany": ["Járvány", "Epidemic"],
	"uv": ["Erős UV-sugárzás", "Strong UV radiation"], "egyeb": ["Egyéb", "Other"],
}


static func category(code: String) -> String:
	var pair: Array = CATEGORY.get(code, [code, code])
	return str(pair[1] if is_en() else pair[0])


const EN := {
	# főképernyő
	"Ma": "Today",
	"Kutatás": "Research",
	"A terved": "Your plan",
	# kutatás
	"Mennyi CO2-t vonhat ki a levegőből a bioszén?": "How much CO2 can biochar remove from the air?",
	"A bioszén elszenesített növényi hulladék. A talajba keverve hosszú ideig tárolja a szenet.": "Biochar is charred plant waste. Mixed into soil, it stores carbon for a long time.",
	"Mennyit segít a kőzetmállasztás?": "How much does rock weathering help?",
	"Finomra őrölt kőzetet szórnak a földekre, ami lassan megköti a levegő CO2-jét.": "Finely ground rock is spread on fields, where it slowly binds CO2 from the air.",
	"Mennyi CO2-t köthet meg az erdősítés?": "How much CO2 can new forests store?",
	"Új erdők telepítése: a fák növekedés közben szenet építenek be.": "Planting new forests: trees build carbon into themselves as they grow.",
	"Segítenek-e az aszálytűrő kukoricafajták?": "Do drought-tolerant maize varieties help?",
	"Ez nem hűti a Földet, de megvédheti a termést a forró, száraz években.": "This does not cool the Earth, but it can protect harvests in hot, dry years.",
	"Ezt kutatom": "Research this",
	"Újra": "Try again",
	"Kérdés: ": "Question: ",
	"Vissza": "Back",
	" és mtsai": " et al.",
	# terv
	"Forrás: ": "Source: ",
	"Ha semmi sem változik": "If nothing changes",
	"Nyelv": "Language",
	# AI-választás (több szolgáltató)
	# esemény-ablak és téma-magyarázat
	"Mennyire bizonyított?": "How well proven is it?",
	"Mi a gond vele?": "What are the problems?",
	"Mire jó?": "What is it good for?",
	"Wikipédia: ": "Wikipedia: ",
	# gépfelmérés, modell-letöltés
	"2100-ban": "in 2100",
	"a csúcs": "the peak",
	"%s: +%s °C": "%s: +%s °C",
	"Küldetések": "Missions",
	"most": "now",
	"Biztos? Kattints még egyszer!": "Sure? Click again",
	"Gyors": "Fast",
	"Gyorsabban telik az idő.": "Time passes faster.",
	"Év": "Year",
	"Új játék": "New game",
	"még nincs": "not built yet",
	"%d. szint": "level %d",
	"épül": "under construction",
	"Felismerés": "Recognition",
	"Mérséklés": "Mitigation",
	"Átalakulás": "Transformation",
	"Helyreállítás": "Restoration",
	"Mennyit melegít a kibocsátott CO2?": "How much does emitted CO2 warm the Earth?",
	"Minden elégetett tonna szén-dioxid melegít. Mennyit, ha összeadjuk?": "Every tonne of carbon dioxide burned warms the Earth. How much, added up?",
	"Megérted, miért számít minden tonna.": "You understand why every tonne counts.",
	"Mennyit csökken a termés, ha melegszik a Föld?": "How much do harvests fall as the Earth warms?",
	"A búza, a kukorica és a rizs érzékeny a hőségre. Mennyit veszít egy fok melegedéstől?": "Wheat, maize and rice are sensitive to heat. How much do they lose per degree of warming?",
	"Megérted, miért kell alkalmazkodni is.": "You understand why we must adapt too.",
	"Aszálytűrő fajták a tervedben.": "Drought-tolerant varieties in your plan.",
	"Mennyi metán spórolható meg a rizsföldeken?": "How much methane can rice fields save?",
	"Az elárasztott rizsföld metánt enged a levegőbe. Ha időnként lecsapolják, kevesebbet.": "Flooded rice fields release methane. Draining them from time to time releases less.",
	"Megérted, hol lehet gyorsan metánt spórolni.": "You understand where methane can be cut quickly.",
	"Mennyi metánszivárgás szüntethető meg a gáziparban?": "How much methane leakage can the gas industry stop?",
	"A földgáz főleg metán. A szivárgó kutakból és csövekből sok jut a levegőbe.": "Natural gas is mostly methane. Leaking wells and pipes release a lot of it into the air.",
	"Mennyi vizet takarít meg a csepegtető öntözés?": "How much water does drip irrigation save?",
	"A csepegtető cső a vizet egyenesen a növény gyökeréhez juttatja.": "A drip line delivers water straight to the plant's roots.",
	"Megérted, hogyan védhető a víz aszályban.": "You understand how to protect water in a drought.",
	"Bioszén a tervedben.": "Biochar in your plan.",
	"Kőzetpor a földekre a tervedben.": "Rock dust on fields in your plan.",
	"Mennyi CO2-t szűrhetnek ki gépek a levegőből?": "How much CO2 can machines filter from the air?",
	"Nagy ventilátoros gépek kiszűrik a CO2-t, és a föld alá zárják. Sok energiát igényel.": "Large fan-driven machines filter out CO2 and store it underground. It takes a lot of energy.",
	"CO2-szűrés a levegőből a tervedben.": "Filtering CO2 from the air in your plan.",
	"Mennyi CO2-t zárhat a föld alá a növényi energia?": "How much CO2 can plant-based energy lock underground?",
	"Növényeket égetnek energiáért, a keletkező CO2-t pedig a föld alá zárják.": "Plants are burned for energy, and the resulting CO2 is stored underground.",
	"Növényi energia CO2-tárolással a tervedben.": "Plant energy with CO2 storage in your plan.",
	"Erdősítés a tervedben.": "Afforestation in your plan.",
	"Mennyi szenet köthet meg újra a talaj?": "How much carbon can soil store again?",
	"Takarónövényekkel és kíméletes műveléssel a talaj több szenet tarthat meg.": "With cover crops and gentle tillage, soil can hold more carbon.",
	"Több szén a talajban a tervedben.": "More carbon in soil in your plan.",
	"Mennyire hűtene a kén a magaslégkörben?": "How much would sulphur in the upper atmosphere cool the Earth?",
	"A magaslégkörbe juttatott kén visszaverné a napfényt. Nagy a kockázata: ha leáll, gyors melegedés jön.": "Sulphur in the upper atmosphere would reflect sunlight. The risk is high: if it stops, rapid warming follows.",
	"Csak megérted: a játékban nem vezethető be.": "Understanding only: it cannot be deployed in the game.",
	"Röviden": "In short",
	"Ha kikutatod: ": "If you research it: ",
	"Korszak": "Era",
	"Wikipédia": "Wikipedia",
	"terv nélkül": "no plan",
	"%s nap": "%s days",
	"mért": "measured",
	# --- főképernyő: súgó, gyorsbillentyűk, értesítések, játék vége ---
	"Hogyan játssz?": "How to play?",
	"ablak bezárása": "close window",
	"teljes képernyő": "full screen",
	"hidegebb": "colder",
	"melegebb": "warmer",
	# kezdő animáció
	"Esc: átugrás": "Esc: skip",
	"Ez a Föld ma.": "This is Earth today.",
	"%s. Melegebb, mint valaha.": "%s. Warmer than ever.",
	"az iparosodás előtti (1850–1900) átlaghoz képest": "compared with the pre-industrial (1850–1900) average",
	"Melegebb, mint valaha.": "Warmer than ever.",
	"Minden változás egyetlen kérdéssel kezdődik.": "Every change begins with a single question.",
	"A tiéddel.": "Yours.",
	"Aszály.": "Drought.",
	"Olvadó jég.": "Melting ice.",
	"Erdőtüzek.": "Wildfires.",
	"Árvizek.": "Floods.",
}

