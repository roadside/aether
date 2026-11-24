extends SceneTree
## Fej nélküli próba az AI-országok szabályaira (godot --headless -s tools/orszag_teszt.gd). Nyelvi modell nem kell hozzá.
const World := preload("res://scripts/world.gd")
const Nation := preload("res://scripts/nation.gd")


func _init() -> void:
	var ok := true
	var w = World.new()
	w.new_game(2026)
	var g: Dictionary = w.group("kina")
	# 1. kezdő hangulat = a valós felmérés száma; minden csoportnak van adatlapja, vezetője és forrása
	var base: bool = is_equal_approx(Nation.mood(w, g), 0.73) and is_equal_approx(Nation.base_mood("europa"), 0.80)
	var files := true
	for x in w.groups:
		var d := Nation.dossier(str(x["id"]))
		files = files and not (d.get("vezetok", []) as Array).is_empty() and str(d.get("berendezkedes_link", "")).begins_with("http") and not (d.get("kozvelemeny", []) as Array).is_empty()
		for f in d.get("tovabbi_tenyek", []):
			files = files and str(f["link"]).begins_with("http")
	# 2. a kérés nem ad beállítottságot, és a többiekről nem árul el gazdasági adatot
	var t0 := int(w.targets_for(g)[0])
	var msg: Array = Nation.prompt(w, g, t0, [], true)
	var user := str(msg[1]["content"])
	var others := user.substr(user.find("WHAT YOU KNOW ABOUT THE OTHERS"), user.find("THE REQUEST") - user.find("WHAT YOU KNOW ABOUT THE OTHERS"))
	var secret := not ("GDP" in others) and not ("electricity" in others) and not ("tonnes" in others) and ("Narendra Modi" in others)
	var own := ("GDP per person" in user.substr(0, user.find("WHAT YOU KNOW"))) and ("no assigned attitude" in str(msg[0]["content"]))
	# 3. válaszok értelmezése
	var o: Array = Nation.options(w, g, int(w.targets_for(g)[-1]))        # a legmerészebb kérés: van későbbi év is
	var parse: bool = Nation.parse(w, g, t0, "{\"choice\":\"A\",\"reason\":1}").get("dontes", "") == "accept" \
		and Nation.parse(w, g, t0, "{\"choice\":\"B\",\"reason\":4}").get("dontes", "") == "refuse" \
		and Nation.parse(w, g, t0, "{\"choice\":\"C\"}").is_empty() and Nation.parse(w, g, t0, "nem json").is_empty() \
		and o.size() == 5 and str(o[1]["dontes"]) == "later" and int(o[1]["cel"]) > int(o[0]["cel"]) \
		and Nation.parse(w, g, int(w.targets_for(g)[-1]), "{\"choice\":\"b\",\"statement\":\"Kell még idő.\"}").get("szoveg", "") == "Kell még idő." \
		and Nation.parse_round(w, g, "{\"choice\":\"A\",\"reason\":9}").get("dontes", "") == "keep" and Nation.parse_round(w, g, "{\"choice\":\"C\"}").is_empty()
	# 4. nem: elvisz egy lépést, a cél nem változik; önkéntes vállalás: a legkönnyebb fokozat; halasztás: +5 év
	var s0: int = w.steps
	var no: bool = w.rebuff(g, t0) and w.steps == s0 - 1 and int(g["cel"]) == 0
	var vol: bool = w.volunteer(g) == t0 and int(g["cel"]) == t0 and w.steps == s0 - 1
	var m_after: float = Nation.mood(w, g)
	var thermo: bool = m_after < 0.73          # a vállalás után kevesebben kérnek még többet
	var post: bool = w.postpone(g) == t0 + 5 and int(g["cel"]) == t0 + 5
	ok = base and files and secret and own and parse and no and vol and thermo and post
	print("ORSZAGTESZT kezdo=%s adatlap=%s titok=%s sajat=%s ertelmezes=%s nem=%s onkent=%s termosztat=%s halaszt=%s => %s" % [base, files, secret, own, parse, no, vol, thermo, post, "RENDBEN" if ok else "HIBA"])
	quit()
