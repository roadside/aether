extends RefCounted
## Nyelvek: magyar (alap) és angol.
## Használat: const L := preload("res://scripts/i18n.gd")  ->  L.t("Kutatás")
## A kulcs maga a magyar szöveg; ha nincs angol fordítás, a magyar marad.

const SETTINGS := "user://beallitasok.cfg"

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


static func is_en() -> bool:
	init()
	return lang == "en"


static func t(hu: String) -> String:
	if not is_en():
		return hu
	return EN.get(hu, hu)


## Adatmező a választott nyelven (pl. "cim" -> "cim_en", ha van).
static func field(d: Dictionary, key: String) -> String:
	if is_en() and d.has(key + "_en"):
		return str(d[key + "_en"])
	return str(d.get(key, ""))


## Szám a nyelvnek megfelelő tizedesjellel.
static func num(x: float, decimals: int = 1) -> String:
	var s := String.num(x, decimals)
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
	"Kész! Húzd az év-csúszkát lent, és nézd, hogyan változik a Föld. Próbálj ki egy új kutatást vagy egy másik tervet!": "Done! Drag the year slider below and watch the Earth change. Try new research or another plan!",
	"Letöltés folyamatban…": "Downloading…",
	"Valós jelentések letöltése (GDACS, ReliefWeb, NASA, NOAA, NSIDC)…": "Downloading real reports (GDACS, ReliefWeb, NASA, NOAA, NSIDC)…",
	"Valós jelentések, letöltve: %s (UTC). %d/%d forrás elérhető.": "Real reports, downloaded: %s (UTC). %d/%d sources available.",
	"Most nem sikerült valós jelentést letölteni. Van internet? A játék nem pótolja kitalált adattal.": "No real reports could be downloaded right now. Are you online? The game never fills the gap with made-up data.",
	"%s millió km²": "%s million km²",
	"nem elérhető": "unavailable",
	"%s%s (%s): %s. Forrás: %s.": "%s%s (%s): %s. Source: %s.",
	"%d kutatási eredményt beépítettél a tervedbe. Nyomd meg „A terved” gombot!": "You added %d research results to your plan. Press “Your plan”!",
	"A valós adatok letöltése nem sikerült. Telepítve van a Python 3.10+, és van internet?": "Downloading the real data failed. Is Python 3.10+ installed, and are you online?",
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
	"Mindig működik. Megmutatja a cikkeket, de számokat nem emel ki.": "Always works. Shows the papers but does not pick out numbers.",
	"%d. lépés / 4": "Step %d of 4",
	"Bezárás": "Close",
	"Mit kutassunk?": "What should we research?",
	"Válassz egy kérdést. A játék valódi, megjelent tudományos cikkekben keres rá választ.": "Pick a question. The game looks for the answer in real, published scientific papers.",
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
	"Az AI cikkeket olvas, a játék pedig mindent szó szerint ellenőriz. Ez 1–5 percig is tarthat.": "The AI reads papers and the game checks everything word for word. This can take 1–5 minutes.",
	"Kérdés pontosítása": "Sharpening the question",
	"Cikkek keresése 4 tudományos adatbázisban": "Searching 4 scientific databases",
	"Fontos számok kiemelése": "Picking out key numbers",
	"Ellenőrzés: tényleg benne van a cikkben?": "Checking: is it really in the paper?",
	"Valami nem sikerült": "Something went wrong",
	"Ellenőrizd, hogy telepítve van-e a Python 3.10 vagy újabb, és van-e internet.": "Check that Python 3.10 or newer is installed and that you are online.",
	"Nem találom a Pythont. Telepítsd a python.org oldalról (3.10 vagy újabb), majd indítsd újra a játékot.": "Python was not found. Install it from python.org (3.10 or newer), then restart the game.",
	"Részletek": "Details",
	"Mit találtunk?": "What did we find?",
	"%d cikket olvastunk el. ": "We read %d papers. ",
	"%d számot szó szerint megtaláltunk a cikkekben, %d másikat kidobtunk, mert nem szerepelt bennük pontosan így.": "We found %d numbers word for word in the papers and threw out %d others because they were not written there exactly like that.",
	"Az AI összefoglalója": "The AI's summary",
	"AI nélkül csak a cikkeket gyűjtöttük össze. Számokat az AI tud kiemelni belőlük.": "Without AI we only collected the papers. An AI is needed to pick out numbers.",
	"Ezekben a cikkekben nem találtunk ellenőrizhető számot erre a kérdésre. Ez is eredmény: érdemes másképp kérdezni.": "These papers had no checkable number for this question. That is a result too: try asking differently.",
	"Új kutatás": "New research",
	"Jóváhagyom, mehet a tervembe": "Approve, add it to my plan",
	"Ez játékon belüli, gépi irodalmi összefoglaló, nem lektorált szakvélemény.": "This is an in-game, machine-made literature summary, not a peer-reviewed expert opinion.",
	"Beteszem a tervembe: ": "Add to my plan: ",
	"Részletek: honnan tudjuk?": "Details: how do we know?",
	" és mtsai": " et al.",
	"  [preprint, nem lektorált]": "  [preprint, not peer-reviewed]",
	"Az átnézett cikkek listája (%d)": "Papers we looked at (%d)",
	# terv
	"Soha": "Never",
	"Forrás: ": "Source: ",
	"Állítsd be, mit tegyen a világ. Utána megnézzük, mi lesz a Föld hőmérsékletével 2100-ig.": "Decide what the world should do. Then we'll see what happens to Earth's temperature until 2100.",
	" mrd t": " bn t",
	"Mikorra csökkenjen nullára a CO2-kibocsátás?": "By when should CO2 emissions reach zero?",
	"A CO2 a fő oka a melegedésnek. Minél hamarabb nullázzuk, annál kevésbé melegszik a Föld.": "CO2 is the main cause of warming. The sooner it reaches zero, the less the Earth warms.",
	"IPCC AR6: a melegedés a kibocsátott CO2 összmennyiségével arányos": "IPCC AR6: warming is proportional to the total amount of CO2 emitted",
	"Mennyivel csökkentsük a metánt 2030-ig?": "How much should methane be cut by 2030?",
	"A metán gyorsan hat: ha csökken, pár évtized alatt érezhetően lassul a melegedés.": "Methane acts fast: cutting it noticeably slows warming within a few decades.",
	"UNEP/CCAC Global Methane Assessment (2021): 45% elérhető 2030-ig": "UNEP/CCAC Global Methane Assessment (2021): 45% achievable by 2030",
	"%s: évente mennyi CO2-t vonjon ki 2050-re?": "%s: how much CO2 per year should it remove by 2050?",
	"A kutatásod szerint legfeljebb ennyi lehetséges. ": "According to your research, at most this much is possible. ",
	"saját kutatásod, ": "your own research, ",
	"Aszálytűrő fajták: mekkora részét védjék a termésnek?": "Drought-tolerant varieties: how much of the harvest should they protect?",
	"Ez nem hűti a Földet, de csökkenti a termésveszteséget. ": "This does not cool the Earth, but it reduces crop losses. ",
	"Zárolva: CO2-kivonás és alkalmazkodás": "Locked: CO2 removal and adaptation",
	"Ezeket előbb ki kell kutatnod. Csak olyan szám kerülhet a tervbe, amit valódi cikkekben ellenőriztünk.": "Research these first. Only numbers checked in real papers can go into the plan.",
	"Mi lesz a Földdel? (modell futtatása)": "What will happen to the Earth? (run the model)",
	"Számolok…": "Calculating…",
	"Még dolgozom egy másik feladaton, nyomd meg újra pár másodperc múlva": "Still busy with another task, press again in a few seconds",
	"Újraszámolás": "Recalculate",
	"A modell nem futott le. Telepítve van a Python 3.10+?": "The model did not run. Is Python 3.10+ installed?",
	"Ez egy egyszerű oktatási modell: az irányt és a nagyságrendet mutatja, nem pontos jövendölést.": "This is a simple educational model: it shows direction and size, not an exact forecast.",
	"Megnézem a földgömbön": "Show me on the globe",
	"Ha semmi sem változik": "If nothing changes",
	"A te terved (sáv = bizonytalanság)": "Your plan (band = uncertainty)",
	"Nyelv": "Language",
	"%d/%s városban túl sok a finom por (WHO-határ felett). Legrosszabb: %s, %s µg/m³": "Too much fine dust (above the WHO limit) in %d/%s cities. Worst: %s, %s µg/m³",
	# AI-választás (több szolgáltató)
	"Claude (Anthropic)": "Claude (Anthropic)",
	"Nagyon alapos. Anthropic API-kulcs kell hozzá (használat szerint fizetős).": "Very thorough. Needs an Anthropic API key (pay as you go).",
	"ChatGPT (OpenAI)": "ChatGPT (OpenAI)",
	"Alapos. OpenAI API-kulcs kell hozzá (használat szerint fizetős).": "Thorough. Needs an OpenAI API key (pay as you go).",
	"Gemini (Google)": "Gemini (Google)",
	"Alapos. Google API-kulcs kell hozzá, ingyenes kerettel is kipróbálható.": "Thorough. Needs a Google API key; you can try it with the free tier.",
	"Ingyenes, és internet nélkül is gondolkodik, de lassabb és kevésbé alapos.": "Free and thinks even without internet, but slower and less thorough.",
	"Miért kell AI?": "Why do you need an AI?",
	"Az AI a te kutatód: elolvassa a valódi tudományos cikkeket, és kiemeli belőlük a fontos számokat. Ettől lesz a terved igazi tudományon alapuló.": "The AI is your researcher: it reads real scientific papers and picks out the important numbers. That is what makes your plan based on real science.",
	"A játék nem hisz vakon az AI-nak: minden számot szó szerint visszakeres a cikkben, és csak azt fogadja el, ami tényleg benne van. Fontos: a ChatGPT Plus, Claude Pro vagy Gemini előfizetés önmagában nem elég, a játékhoz API-kulcs kell. Ez külön, használat szerint fizetendő: egy kutatás a választott AI-tól függően néhány forinttól pár száz forintig terjed. A Geminihez van ingyenes keret, az Ollama pedig teljesen ingyenes.": "The game does not trust the AI blindly: it looks up every number word for word in the paper and only accepts what is really there. Important: a ChatGPT Plus, Claude Pro or Gemini subscription is not enough on its own; the game needs an API key. That is billed separately by usage: one research run costs from a few cents to around a dollar, depending on the AI. Gemini has a free tier, and Ollama is completely free.",
	"Kulcs létrehozása (megnyílik a böngészőben)": "Create a key (opens in your browser)",
	"%s API-kulcs (csak amíg a játék fut, nem mentjük el):": "%s API key (only while the game runs, never saved):",
	# esemény-ablak és téma-magyarázat
	"%s %d országban": "%s in %d countries",
	"%s, %s és még %d ország": "%s, %s and %d more countries",
	", köztük %s": ", including %s",
	"A részletek a megnyílt ablakban.": "Details are in the window that opened.",
	"AI-összefoglaló, kizárólag a lenti forrásokból. Az AI is tévedhet, a forrásokban ellenőrizheted.": "AI summary, based only on the sources below. The AI can make mistakes; you can check the sources.",
	"Az AI elolvassa a Wikipédia-cikket és néhány tudományos összefoglalót, és érthetően elmondja, mi ez. Ez fél–két percig is tarthat…": "The AI reads the Wikipedia article and a few scientific reviews, and explains in plain words what this is. This can take half a minute to two minutes…",
	"Az AI is tévedhet: a számokat a játék szó szerint visszakereste a forrásban, a szöveget lent ellenőrizheted.": "The AI can make mistakes: the game looked up the numbers word for word in the source, and you can check the text below.",
	"Az összefoglaló most nem készült el. A hivatalos forrást lent megnyithatod.": "The summary could not be made right now. You can open the official source below.",
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
	"A játék még dolgozik egy másik feladaton (pl. adatletöltés vagy AI-magyarázat). Próbáld újra pár másodperc múlva.": "The game is still busy with another task (e.g. downloading data or an AI explanation). Try again in a few seconds.",
	"Egy pillanat, töltöm a forrásokat…": "One moment, loading the sources…",
	"Az AI a háttérben részletesebb magyarázatot ír; ha kész, itt megjelenik.": "The AI is writing a more detailed explanation in the background; it will appear here when ready.",
}
