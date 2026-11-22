extends RefCounted
## Nyelvek: magyar (alap) és angol.
## Használat: const L := preload("res://scripts/i18n.gd")  ->  L.t("Kutatás")
## A kulcs maga a magyar szöveg; ha nincs angol fordítás, a magyar marad.

const SETTINGS := "user://beallitasok.cfg"
const I2 := preload("res://scripts/i18n_2.gd")   # további fordítások (külön fájl, hogy ne ütközzenek)

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


static func set_lang(l: String) -> void:
	lang = l
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("jatek", "nyelv", l)
	cfg.save(SETTINGS)


## Egyéb beállítások ugyanabban a fájlban (pl. a választott AI).
static func get_setting(key: String, default: Variant = "") -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return default
	return cfg.get_value("jatek", key, default)


static func set_setting(key: String, value: Variant) -> void:
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
	return EN.get(hu, I2.EN.get(hu, hu))


## Adatmező a választott nyelven (pl. "cim" -> "cim_en", ha van).
static func field(d: Dictionary, key: String) -> String:
	if is_en() and d.has(key + "_en"):
		return str(d[key + "_en"])
	return str(d.get(key, ""))


## Szám a nyelvnek megfelelő tizedesjellel.
static func num(x: float, decimals: int = 1) -> String:
	var s := String.num(x, decimals)
	return s if is_en() else s.replace(".", ",")


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
	"szennyezes": ["Szennyezés", "Pollution"], "viz": ["Vízminőség", "Water quality"], "hoseg": ["Hőség", "Heat"],
	"ehezes": ["Élelmiszerhiány", "Food insecurity"], "jarvany": ["Járvány", "Epidemic"],
	"uv": ["Erős UV-sugárzás", "Strong UV radiation"], "egyeb": ["Egyéb", "Other"],
}


static func category(code: String) -> String:
	var pair: Array = CATEGORY.get(code, [code, code])
	return str(pair[1] if is_en() else pair[0])


const EN := {
	# főképernyő
	"Nézd meg a mai Földet": "Look at today's Earth",
	"A bal oldali lista és a földgömb pöttyei valódi, friss jelentések. Kattints egyre!": "The list on the left and the dots on the globe are real, recent reports. Click one!",
	"Kutass!": "Do some research!",
	"Nyomd meg lent a „Kutatás” gombot, és válassz egy kérdést.": "Press the “Research” button below and pick a question.",
	"Nézd meg, mit találtál": "See what you found",
	"A játék csak azt fogadja el, ami szó szerint benne van a cikkekben.": "The game only accepts what is literally written in the papers.",
	"Készítsd el a terved": "Make your plan",
	"Nyomd meg „A terved” gombot, állítsd be a csúszkákat, és nézd meg, mi lesz 2100-ban.": "Press “Your plan”, set the sliders and see what happens by 2100.",
	"Te · Budapest": "You · Budapest",
	"Forrás: Forster és mtsai 2025 (kattints a megnyitáshoz)": "Source: Forster et al. 2025 (click to open)",
	"Ma": "Today",
	"Ember okozta melegedés (2024)": "Human-caused warming (2024)",
	"CO2 a levegőben": "CO2 in the air",
	"letöltés…": "downloading…",
	"Északi-sarki tengeri jég": "Arctic sea ice",
	"A terved szerint": "With your plan",
	"még nincs terv": "no plan yet",
	"Mi történik most?": "What is happening now?",
	"Valós jelentések betöltése…": "Loading real reports…",
	"Frissítés valós adatokkal": "Refresh with real data",
	"Első küldetés": "First mission",
	"Kutatás": "Research",
	"A terved": "Your plan",
	"Üdv az AETHER-ben! Kezdd a jobb oldali küldetéssel.": "Welcome to AETHER! Start with the mission on the right.",
	"Forrás megnyitása": "Open source",
	"Év:": "Year:",
	"A te kutatóállomásod: ": "Your research station: ",
	"Kész! Húzd az év-csúszkát, és nézd a Földet.": "Done! Drag the year slider and watch the Earth.",
	"Letöltés folyamatban…": "Downloading…",
	"Valós jelentések letöltése…": "Downloading real reports…",
	"Valós jelentések, letöltve: %s (UTC). %d/%d forrás elérhető.": "Real reports, downloaded: %s (UTC). %d/%d sources available.",
	"Nem sikerült jelentést letölteni. Van internet?": "Could not download reports. Are you online?",
	"%s millió km²": "%s million km²",
	"nem elérhető": "unavailable",
	"%s%s (%s): %s. Forrás: %s.": "%s%s (%s): %s. Source: %s.",
	"%d eredmény a tervedben. Nyomd meg „A terved” gombot!": "%d results in your plan. Press “Your plan”!",
	"Az adatletöltés nem sikerült. Van Python 3.10+ és internet?": "Data download failed. Is Python 3.10+ installed and are you online?",
	# kutatás
	"Mennyi CO2-t vonhat ki a levegőből a bioszén?": "How much CO2 can biochar remove from the air?",
	"A bioszén elszenesített növényi hulladék. A talajba keverve hosszú ideig tárolja a szenet.": "Biochar is charred plant waste. Mixed into soil, it stores carbon for a long time.",
	"Mennyit segít a kőzetmállasztás?": "How much does rock weathering help?",
	"Finomra őrölt kőzetet szórnak a földekre, ami lassan megköti a levegő CO2-jét.": "Finely ground rock is spread on fields, where it slowly binds CO2 from the air.",
	"Mennyi CO2-t köthet meg az erdősítés?": "How much CO2 can new forests store?",
	"Új erdők telepítése: a fák növekedés közben szenet építenek be.": "Planting new forests: trees build carbon into themselves as they grow.",
	"Segítenek-e az aszálytűrő kukoricafajták?": "Do drought-tolerant maize varieties help?",
	"Ez nem hűti a Földet, de megvédheti a termést a forró, száraz években.": "This does not cool the Earth, but it can protect harvests in hot, dry years.",
	"A legalaposabb. Kell hozzá egy Anthropic API-kulcs.": "The most thorough. Needs an Anthropic API key.",
	"Helyi AI a gépeden (Ollama)": "Local AI on your computer (Ollama)",
	"AI nélkül: csak cikkeket keresek": "No AI: just search for papers",
	"Csak cikklista, számok nélkül.": "Paper list only, no numbers.",
	"%d. lépés / 4": "Step %d of 4",
	"Bezárás": "Close",
	"Mit kutassunk?": "What should we research?",
	"Válassz kérdést. A válasz valódi tudományos cikkekből jön.": "Pick a question. The answer comes from real scientific papers.",
	"Ezt kutatom": "Research this",
	"Saját kérdést írok (haladó)": "Write my own question (advanced)",
	"Pl.: Mennyi metánt bocsátanak ki a rizsföldek?": "E.g.: How much methane do rice paddies emit?",
	"Ki kutasson?": "Who should do the research?",
	"Megnézem, milyen AI érhető el a gépeden…": "Checking which AI is available on your computer…",
	"Egy pillanat…": "Just a moment…",
	"A játék még letölti a valós adatokat. Próbáld újra pár másodperc múlva.": "The game is still downloading real data. Try again in a few seconds.",
	"Újra": "Try again",
	"Kérdés: ": "Question: ",
	" (ajánlott)": " (recommended)",
	"Vissza": "Back",
	"Indulhat a kutatás": "Start the research",
	"Kutatás folyamatban": "Research in progress",
	"Pár perc.": "A few minutes.",
	"Kérdés pontosítása": "Sharpening the question",
	"Cikkek keresése 4 tudományos adatbázisban": "Searching 4 scientific databases",
	"Fontos számok kiemelése": "Picking out key numbers",
	"Ellenőrzés: tényleg benne van a cikkben?": "Checking: is it really in the paper?",
	"Valami nem sikerült": "Something went wrong",
	"Ellenőrizd, hogy telepítve van-e a Python 3.10 vagy újabb, és van-e internet.": "Check that Python 3.10 or newer is installed and that you are online.",
	"Nem találom a Pythont. Telepítsd a python.org oldalról (3.10 vagy újabb), majd indítsd újra a játékot.": "Python was not found. Install it from python.org (3.10 or newer), then restart the game.",
	"Mit találtunk?": "What did we find?",
	"%d cikket olvastunk el. ": "We read %d papers. ",
	"%d szám ellenőrizve, %d elvetve.": "%d numbers checked, %d rejected.",
	"Az AI összefoglalója": "The AI's summary",
	"AI nélkül csak cikklista készül, számok nem.": "Without AI there is only a paper list, no numbers.",
	"Nem találtunk ellenőrizhető számot. Ez is eredmény.": "No checkable number found. That is a result too.",
	"Új kutatás": "New research",
	"Jóváhagyom, mehet a tervembe": "Approve, add it to my plan",
	"Beteszem a tervembe: ": "Add to my plan: ",
	" és mtsai": " et al.",
	"  [preprint, nem lektorált]": "  [preprint, not peer-reviewed]",
	"Az átnézett cikkek listája (%d)": "Papers we looked at (%d)",
	# terv
	"Soha": "Never",
	"Forrás: ": "Source: ",
	"Állítsd be, mit tegyen a világ, és nézd meg, mi lesz 2100-ig.": "Set what the world does and see what happens by 2100.",
	" mrd t": " bn t",
	"Mikorra csökkenjen nullára a CO2-kibocsátás?": "By when should CO2 emissions reach zero?",
	"A melegedés fő oka. Minél hamarabb nulla, annál jobb.": "The main cause of warming. The sooner it is zero, the better.",
	"IPCC AR6: a melegedés a kibocsátott CO2 összmennyiségével arányos": "IPCC AR6: warming is proportional to the total amount of CO2 emitted",
	"Mennyivel csökkentsük a metánt 2030-ig?": "How much should methane be cut by 2030?",
	"Gyorsan hat: csökkentése pár évtized alatt lassítja a melegedést.": "Acts fast: cutting it slows warming within decades.",
	"UNEP/CCAC Global Methane Assessment (2021): 45% elérhető 2030-ig": "UNEP/CCAC Global Methane Assessment (2021): 45% achievable by 2030",
	"%s: évente mennyi CO2-t vonjon ki 2050-re?": "%s: how much CO2 per year should it remove by 2050?",
	"A kutatásod szerint legfeljebb ennyi lehetséges. ": "According to your research, at most this much is possible. ",
	"saját kutatásod, ": "your own research, ",
	"Aszálytűrő fajták: mekkora részét védjék a termésnek?": "Drought-tolerant varieties: how much of the harvest should they protect?",
	"Ez nem hűti a Földet, de csökkenti a termésveszteséget. ": "This does not cool the Earth, but it reduces crop losses. ",
	"Zárolva: CO2-kivonás és alkalmazkodás": "Locked: CO2 removal and adaptation",
	"Ezeket előbb ki kell kutatnod.": "Research these first.",
	"Mi lesz a Földdel? (modell futtatása)": "What will happen to the Earth? (run the model)",
	"Számolok…": "Calculating…",
	"Egy pillanat, próbáld újra": "One moment, try again",
	"Újraszámolás": "Recalculate",
	"A modell nem futott le. Telepítve van a Python 3.10+?": "The model did not run. Is Python 3.10+ installed?",
	"Egyszerű oktatási modell: irányt mutat, nem jósol.": "A simple teaching model: it shows direction, not a forecast.",
	"Megnézem a földgömbön": "Show me on the globe",
	"Ha semmi sem változik": "If nothing changes",
	"A te terved (sáv = bizonytalanság)": "Your plan (band = uncertainty)",
	"Nyelv": "Language",
	"%d/%s városban túl sok a finom por (WHO-határ felett). Legrosszabb: %s, %s µg/m³": "Too much fine dust (above the WHO limit) in %d/%s cities. Worst: %s, %s µg/m³",
	# AI-választás (több szolgáltató)
	"Claude (Anthropic)": "Claude (Anthropic)",
	"Nagyon alapos. API-kulcs kell (fizetős).": "Very thorough. Needs an API key (paid).",
	"ChatGPT (OpenAI)": "ChatGPT (OpenAI)",
	"Alapos. API-kulcs kell (fizetős).": "Thorough. Needs an API key (paid).",
	"Gemini (Google)": "Gemini (Google)",
	"Alapos. API-kulcs kell, van ingyenes keret.": "Thorough. Needs an API key, has a free tier.",
	"Ingyenes, de lassabb.": "Free, but slower.",
	"Miért kell AI?": "Why do you need an AI?",
	"Az AI a kutatód: cikkeket olvas és számokat keres. A játék mindet ellenőrzi.": "The AI is your researcher: it reads papers and finds numbers. The game checks every one.",
	"A ChatGPT, Claude vagy Gemini előfizetés nem elég, API-kulcs kell. Az Ollama ingyenes.": "A ChatGPT, Claude or Gemini subscription is not enough; you need an API key. Ollama is free.",
	"Kulcs létrehozása (megnyílik a böngészőben)": "Create a key (opens in your browser)",
	"%s API-kulcs (csak amíg a játék fut, nem mentjük el):": "%s API key (only while the game runs, never saved):",
	# esemény-ablak és téma-magyarázat
	"%s %d országban": "%s in %d countries",
	"%s, %s és még %d ország": "%s, %s and %d more countries",
	", köztük %s": ", including %s",
	"A részletek a megnyílt ablakban.": "Details are in the window that opened.",
	"AI-összefoglaló forrásai": "Sources of the AI summary",
	"Az AI elolvassa a Wikipédia-cikket és néhány tudományos összefoglalót, és érthetően elmondja, mi ez. Ez fél–két percig is tarthat…": "The AI reads the Wikipedia article and a few scientific reviews, and explains in plain words what this is. This can take half a minute to two minutes…",
	"A számokat a játék a forrásban ellenőrizte.": "The game checked the numbers in the source.",
	"Az összefoglaló nem készült el. Lent a forrás.": "No summary this time. The source is below.",
	"Fontos számok": "Key numbers",
	"Hivatalos forrás megnyitása (eredeti nyelven)": "Open the official source (original language)",
	"Mennyire bizonyított?": "How well proven is it?",
	"Mi a gond vele?": "What are the problems?",
	"Mi ez, és mire jó?": "What is it, and what is it good for?",
	"Mi ez?": "What is it?",
	"Mi ez? (Wikipédia)": "What is it? (Wikipedia)",
	"Mire jó?": "What is it good for?",
	"Miért fontos, és mi köze a klímához?": "Why does it matter, and what does it have to do with the climate?",
	"Most nem sikerült forrást letölteni. Van internet?": "No source could be downloaded right now. Are you online?",
	"Tudományos összefoglaló cikkek": "Scientific review articles",
	"Vissza a kérdésekhez": "Back to the questions",
	"Wikipédia: ": "Wikipedia: ",
	"Ábra a forrásból": "Figure from the source",
	"Általános AI-magyarázat, számok nélkül.": "General AI explanation, without numbers.",
	"Érintett országok: ": "Affected countries: ",
	"Összefoglaló (AI, a forrás alapján)": "Summary (AI, based on the source)",
	"Összefoglaló (a forrás saját adataiból)": "Summary (from the source's own data)",
	"Összefoglaló készül a forrásból…": "Making a summary from the source…",
	"A játék épp mással dolgozik. Próbáld újra pár másodperc múlva.": "The game is busy. Try again in a few seconds.",
	"Egy pillanat, töltöm a forrásokat…": "One moment, loading the sources…",
	"Az AI részletesebb magyarázatot ír…": "The AI is writing a fuller explanation…",
	# gépfelmérés, modell-letöltés
	" – ezt az Ollama nem használja": " – Ollama does not use this one",
	"A géped videókártyái: ": "Your graphics cards: ",
	"Ajánlott helyi modell: %s (%s GB letöltés). ": "Recommended local model: %s (%s GB download). ",
	"Ez a modell már le van töltve, a játék ezt használja.": "This model is already downloaded; the game uses it.",
	"Az Ollama telepítése (ollama.com, ingyenes)": "Install Ollama (ollama.com, free)",
	"Letöltöm: %s (%s GB)": "Download: %s (%s GB)",
	"Letöltés indul…": "Download starting…",
	"Letöltés: %d%%": "Downloading: %d%%",
	"Ajánlott a gépedhez: %s": "Recommended for your computer: %s",
	"%d cikk. ": "%d papers. ",
	"Megmenti-e a Földet a szárazságtűrő növény?": "Can drought-tolerant crops save the Earth?",
	"Kutasd ki az aszálytűrő kukoricát, tedd a tervedbe, és futtasd a modellt.": "Research drought-tolerant maize, add it to your plan and run the model.",
	"Az alkalmazkodás véd, de nem hűt: a termés javul, a hőmérséklet nem változik.": "Adaptation protects but does not cool: harvests improve, temperature stays the same.",
	"Mi hűti a bolygót?": "What cools the planet?",
	"Tartsd 2100-ra 2 °C alatt a melegedést.": "Keep warming below 2 °C by 2100.",
	"A legtöbbet az számít, mikorra lesz nulla a CO2-kibocsátás.": "What matters most is when CO2 emissions reach zero.",
	"Késői kezdés": "Late start",
	"A CO2 csak 2070-re lesz nulla. Tartsd a csúcsot 1,6 °C alatt.": "CO2 only reaches zero by 2070. Keep the peak below 1.6 °C.",
	"A metán és a CO2-kivonás segít, de csak részben pótolja az elvesztegetett éveket.": "Methane cuts and CO2 removal help, but only partly make up for lost years.",
	"Másfél fok": "One and a half degrees",
	"A CO2 2060-ra lesz nulla. Vidd 2100-ra 1,45 °C alá. Lehet, hogy nem sikerül!": "CO2 reaches zero by 2060. Get below 1.45 °C by 2100. It may not be possible!",
	"Minél később kezdünk, annál több CO2-t kell kivonni, és ennek a kutatás szab határt.": "The later we start, the more CO2 must be removed, and research sets the limit.",
	"2100-ban": "in 2100",
	"a csúcs": "the peak",
	"Még nincs aszálytűrő kukorica a tervedben. Kutasd ki előbb!": "There is no drought-tolerant maize in your plan yet. Research it first!",
	"Kukoricatermés-változás 2050-ben: %s%% helyett %s%%. Hőmérséklet 2100-ban: +%s °C, ugyanannyi.": "Maize harvest change in 2050: %s%% without it, %s%% with it. Temperature in 2100: +%s °C, the same.",
	"%s: +%s °C": "%s: +%s °C",
	". Még nem sikerült, próbáld újra!": ". Not yet, try again!",
	" Következő csillag: %s +%s °C alatt.": " Next star: %s below +%s °C.",
	"Küldetések": "Missions",
	"Küldetés: ": "Mission: ",
	"Ebben a küldetésben rögzített.": "Fixed in this mission.",
	"Első küldetés kész! Jöhet a következő.": "First mission done! On to the next one.",
	"%d cikk (%d hazai). ": "%d papers (%d from your country). ",
	"%d: bevétel +%d.": "%d: income +%d.",
	"A játék véget ért.": "The game is over.",
	"A kibocsátás csökken: bizalom +%d.": "Emissions are falling: trust +%d.",
	"A kibocsátás nem csökken: bizalom %d.": "Emissions are not falling: trust %d.",
	"A terved életbe lép, első éve: %d.": "Your plan takes effect, first year: %d.",
	"Ehhez %d pénz kell, neked %d van. Évente %d pénzt kapsz.": "This needs %d money, you have %d. You get %d money per year.",
	"Ehhez %d%% bizalom kell, neked %d%% van. Kutass, és tartsd a terved!": "This needs %d%% trust, you have %d%%. Do research and keep your plan!",
	"Visszaléptél egy gyengébb tervre: bizalom −%d.": "You stepped back to a weaker plan: trust −%d.",
	"most": "now",
	"%d eredmény a tervedben, bizalom +%d%%. Nyomd meg „A terved” gombot!": "%d results in your plan, trust +%d%%. Press the “Your plan” button!",
	"+1 év": "+1 year",
	"2100: vége a játéknak. A Föld +%s °C-kal melegebb, a csúcs +%s °C volt. „Új játék”: próbáld meg jobban!": "2100: the game is over. The Earth is +%s °C warmer, the peak was +%s °C. “New game”: try to do better!",
	"A klímamodell becslése erre az évre: %d. (2024-ben mért érték: +1,36 °C, Forster és mtsai 2025.)": "The climate model's estimate for this year: %d. (Measured in 2024: +1.36 °C, Forster et al. 2025.)",
	"Az évek telnek. Ha egy ablak nyitva van, az idő áll.": "Years pass. While a window is open, time stops.",
	"Bizalom": "Trust",
	"Biztos? Kattints újra": "Sure? Click again",
	"Egy évvel előre.": "One year forward.",
	"Elölről kezdi 2026-tól. A küldetések csillagai megmaradnak.": "Starts again from 2026. Mission stars are kept.",
	"Gyors": "Fast",
	"Gyorsabban telik az idő.": "Time passes faster.",
	"Idő indítása": "Start time",
	"Játékszabály, nem valós adat. Pénz: kutatás és tervek bevezetése; évente kapsz. Bizalom: a gyors tervekhez kell; ellenőrzött kutatással és csökkenő kibocsátással nő.": "Game rule, not real data. Money: pays for research and new plans; you get some every year. Trust: needed for fast plans; grows with verified research and falling emissions.",
	"Melegedés (modell)": "Warming (model)",
	"Pénz": "Money",
	"Szünet": "Pause",
	"Telik az idő, de még nincs terved: a kibocsátás nem csökken. Nyisd meg „A terved” ablakot!": "Time is passing, but you have no plan yet: emissions are not falling. Open “Your plan”!",
	"Év": "Year",
	"Új játék": "New game",
	"Új játék 2026-tól. Kutass, készíts tervet, és indítsd el az időt!": "New game from 2026. Do research, make a plan, and start time!",
	"A pénz és a bizalom játékszabály, nem valós adat. A hőmérséklet a klímamodellből jön.": "Money and trust are game rules, not real data. The temperature comes from the climate model.",
	"Bevezetem": "Put it into effect",
	"Első év: %d. Ára: %d pénz, és legalább %d%% bizalom kell.": "First year: %d. Cost: %d money, and at least %d%% trust is needed.",
	"Ez gyengébb a mostani tervednél: a bizalom csökken.": "This is weaker than your current plan: trust will fall.",
	"Nincs elég pénz kutatásra (%d kell, neked %d van). Indítsd el az időt, évente kapsz pénzt.": "Not enough money for research (%d needed, you have %d). Start time; you get money every year.",
	"Üvegház: bizalom +%d.": "Greenhouse: trust +%d.",
	"Elkészült: %s, %d. szint.": "Finished: %s, level %d.",
	"Elérte a legmagasabb szintet.": "It has reached the highest level.",
	"Egyszerre egy modul épülhet.": "Only one module can be built at a time.",
	"Ehhez %d pénz kell, neked %d van.": "This needs %d money, you have %d.",
	"Építés indult: %s, kész: %d.": "Construction started: %s, ready in %d.",
	"Idén már %d kutatást indítottál, ennyit enged az AI-mag. Várj egy évet, vagy fejleszd az AI-magot!": "You have already started %d research projects this year, the AI core's limit. Wait a year or upgrade the AI core!",
	"Állomás": "Station",
	"A kutatóállomásod: modulok építése és fejlesztése.": "Your research station: build and upgrade modules.",
	"Kutatóállomás: ": "Research station: ",
	" (%d pénz)": " (%d money)",
	"Az AI-mag %d cikket néz át. Idén még %d kutatást indíthatsz.": "The AI core reviews %d papers. You can start %d more research projects this year.",
	"Kutatóállomás": "Research station",
	"Fejleszd az állomásodat: több és alaposabb kutatás, több bizalom. Egy modul építése 1 évig tart.": "Upgrade your station: more and deeper research, more trust. Building a module takes 1 year.",
	"még nincs": "not built yet",
	"%d. szint": "level %d",
	"%d cikket néz át, évente %d kutatás.": "Reviews %d papers, %d research projects per year.",
	"Egy kutatás ára: %d pénz.": "One research project costs %d money.",
	"Évente +%d bizalom.": "+%d trust per year.",
	"Nincs bizalom-bónusz.": "No trust bonus.",
	"Nagyobb számítási kapacitás: több cikket olvas el, de egy kutatás tovább tart.": "More computing power: reads more papers, but each research project takes longer.",
	"Cikktár: a már letöltött cikkeket nem kell újra keresni.": "Paper library: papers already downloaded don't need to be searched again.",
	"Helyi kísérletek: az emberek a saját szemükkel látják az eredményt.": "Local experiments: people see the results with their own eyes.",
	"Most: ": "Now: ",
	"Épül, kész: %d.": "Under construction, ready in %d.",
	"Következő szint: ": "Next level: ",
	"Építés: %d pénz": "Build: %d money",
	"Kész, legmagasabb szint.": "Done, highest level.",
	"AI-mag": "AI core",
	"Archívum": "Archive",
	"Üvegház": "Greenhouse",
	"épül": "under construction",
	"[Hazai] ": "[Your country] ",
	"Hazai intézmény: %s": "Institution in your country: %s",
	"A forrás honlapja: ": "Source website: ",
	"Nyers adat letöltése (%s-fájl)": "Download raw data (%s file)",
	"Műholdkép aznapról (NASA Worldview)": "Satellite image of that day (NASA Worldview)",
	"Kész, a játék ezt használja.": "Done, the game uses it now.",
	"A letöltés nem sikerült: ": "The download failed: ",
	"Felismerés": "Recognition",
	"Mérséklés": "Mitigation",
	"Átalakulás": "Transformation",
	"Helyreállítás": "Restoration",
	"Mérés és megértés: a melegedés, a jég, a tenger, az élővilág és a termés.": "Measure and understand: warming, ice, the sea, wildlife and harvests.",
	"Takarékosság, metán, alkalmazkodás. Megnyílik a metán a tervedben.": "Saving energy, methane, adaptation. Methane opens in your plan.",
	"Új energia, új anyagok, és a CO2 kivonása a levegőből.": "New energy, new materials, and removing CO2 from the air.",
	"Erdők, vizek, talaj, és a legkockázatosabb ötletek megértése.": "Forests, waters, soil, and understanding the riskiest ideas.",
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
	"zárva": "locked",
	"✓ Kutatva ": "✓ Researched ",
	"Röviden": "In short",
	"Részletesebb magyarázatot az AI ír. AI-t a kutatás 2. lépésében választhatsz.": "The AI writes a more detailed explanation. You can choose an AI in step 2 of research.",
	"Keresés a témák között, pl. jég, akkumulátor, metán": "Search topics, e.g. ice, battery, methane",
	"Nincs ilyen téma a nyitott korszakokban.": "No such topic in the open eras.",
	"Erősebb tudás a tudásfán: ": "Stronger knowledge in the tree: ",
	"Játékszabály: ★ ellenőrzött szám, ★★ legalább 2 cikk egyezik, ★★★ legalább 3 cikk, köztük összefoglaló elemzés.": "Game rule: ★ a verified number, ★★ at least 2 papers agree, ★★★ at least 3 papers, including a summary analysis.",
	"Ha kikutatod: ": "If you research it: ",
	"Újra kutatom": "Research again",
	"Új tudás a tudásfán: ": "New knowledge in the tree: ",
	"Kutatott téma a(z) %s korszakból: %d/%d": "Researched topics from era %s: %d/%d",
	"Bevezetett terv": "A plan in force",
	"Bizalom legalább %d%%": "Trust at least %d%%",
	"Csökkenő CO2-kibocsátás a modellben (5 év alatt)": "Falling CO2 emissions in the model (over 5 years)",
	"A II. Mérséklés korszakban nyílik meg. Kutass ki 2 témát az I. korszakból!": "Opens in era II Mitigation. Research 2 topics from era I!",
	"Korszak": "Era",
	"Tudásfa (játékszabály): a kutatott témák új korszakot, új témákat és új tervlehetőségeket nyitnak. Kutatás gomb.": "Knowledge tree (game rule): researched topics open new eras, topics and plan options. See the Research button.",
	"Új korszak: %s! %s": "New era: %s! %s",
	"Wikipédia": "Wikipedia",
	"Nálunk": "Back home",
	"Mit jelent a melegedés nálunk: forró napok és nyári eső, mért adatokból és a terved szerint.": "What warming means where you live: hot days and summer rain, from measurements and according to your plan.",
	"Töltöm a mért adatokat (1961 óta, naponta)…": "Loading measured data (daily, since 1961)…",
	"Most nem sikerült letölteni a mért adatokat. Van internet?": "Could not download the measured data. Are you online?",
	"Mit jelent ez nálunk?": "What does it mean here?",
	"a terved szerint": "your plan",
	"terv nélkül": "no plan",
	"Hány nap van évente 30 °C fölött?": "How many days a year are above 30 °C?",
	"%s nap": "%s days",
	"mért": "measured",
	"még nincs modell": "no model yet",
	"kb. %s–%s nap": "about %s–%s days",
	"Narancs: mért évek. Türkiz: becslés a terved szerint.": "Orange: measured years. Teal: estimate under your plan.",
	"Mennyi eső esik nyáron (június–augusztus)?": "How much rain falls in summer (June–August)?",
	"kb. %s–%s mm": "about %s–%s mm",
	"Mért adat: ERA5, kb. 25 km-es rácspont (a város belsejében melegebb). Becslés: a 2006–2025 között mért napokat a régió várható melegedésével toljuk el (34 klímamodell). Nem helyi előrejelzés.": "Measured data: ERA5, a grid point about 25 km wide (city centres are hotter). Estimate: the days measured in 2006–2025 are shifted by the region's expected warming (34 climate models). Not a local forecast.",
	"ERA5 (Copernicus/ECMWF) az Open-Meteón keresztül": "ERA5 (Copernicus/ECMWF) via Open-Meteo",
	"IPCC AR6 Interaktív Atlasz, CMIP6 (Iturbide et al. 2021)": "IPCC AR6 Interactive Atlas, CMIP6 (Iturbide et al. 2021)",
	"Forster et al. 2025, globális melegedés": "Forster et al. 2025, global warming",
	# --- főképernyő: súgó, gyorsbillentyűk, értesítések, játék vége ---
	"Hogyan játssz? (F1)": "How to play? (F1)",
	"Válassz kérdést, a válasz valódi cikkekből jön. Gyorsbillentyű: K": "Pick a question; the answer comes from real papers. Shortcut: K",
	"Állítsd be, mit tegyen a világ, és nézd meg, mi lesz 2100-ig. Gyorsbillentyű: T": "Set what the world should do and see what happens by 2100. Shortcut: T",
	"A kutatóállomásod: modulok építése és fejlesztése. Gyorsbillentyű: A": "Your research station: build and upgrade modules. Shortcut: A",
	"Mit jelent a melegedés nálunk: forró napok és nyári eső, mért adatokból és a terved szerint. Gyorsbillentyű: N": "What warming means where you live: hot days and summer rain, measured and under your plan. Shortcut: N",
	"Az évek telnek. Ha egy ablak nyitva van, az idő áll. Gyorsbillentyű: szóköz": "Years pass. While a window is open, time stops. Shortcut: Space",
	"Egy évvel előre. Gyorsbillentyű: jobbra nyíl": "One year ahead. Shortcut: right arrow",
	"Hogyan játssz?": "How to play?",
	"1. Nézz körül": "1. Look around",
	"A bal oldali lista és a földgömb pöttyei valódi, mai jelentések.": "The list on the left and the dots on the globe are real reports from today.",
	"2. Kutass": "2. Research",
	"Válassz kérdést: a válasz valódi tudományos cikkekből jön.": "Pick a question: the answer comes from real scientific papers.",
	"3. Tervezz": "3. Plan",
	"A kutatott megoldásokat tedd a tervedbe, és nézd meg, mi lesz 2100-ig.": "Put the solutions you researched into your plan and see what happens by 2100.",
	"4. Indítsd az időt": "4. Start the clock",
	"Telnek az évek, nő a pénz és a bizalom. Fejleszd az állomásod.": "Years pass, money and trust grow. Upgrade your station.",
	"Gyorsbillentyűk": "Shortcuts",
	"Szóköz": "Space",
	"idő indítása / szünet": "start / pause time",
	"földgömb: vissza a helyedre": "globe: back to your place",
	"ablak bezárása": "close window",
	"teljes képernyő": "full screen",
	"A földgömb egérrel forgatható, görgővel nagyítható; dupla kattintás: vissza a helyedre.": "Drag to turn the globe, scroll to zoom; double-click: back to your place.",
	"Kutatás →": "Research →",
	"A terved →": "Your plan →",
	"Friss: %s · %d/%d forrás": "Updated: %s · %d/%d sources",
	"Új lehetőség a tervedben: %d": "New options in your plan: %d",
	"Új korszak: %s": "New era: %s",
	"2100 – így alakult": "2100 – how it turned out",
	"Másfél fok alatt maradt. Kiváló!": "Below one and a half degrees. Excellent!",
	"Két fok alatt maradt.": "Below two degrees.",
	"Két fok fölé ment. Próbáld korábbi CO2-nullával!": "Above two degrees. Try reaching zero CO2 earlier!",
	"Melegedés 2100-ban": "Warming in 2100",
	"Csúcs": "Peak",
	"Kutatott témák": "Topics researched",
	"Küldetések: %s  (%d/%d csillag)": "Missions: %s  (%d/%d stars)",
}
