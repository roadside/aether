extends RefCounted
## Ügynök-felület: a játék szabályai gép számára olvasható formában.
##   observe()  – az állapot (amit a játékos is lát; a Föld rejtett érzékenysége és a küszöbök nincsenek benne),
##   actions()  – a most szabályos lépések listája,
##   apply(a)   – egy lépés végrehajtása (csak szabályos lépést fogad el),
##   policy(k)  – a beépített, szabályalapú gépek lépése indoklással ("kezdo", "atlagos", "okos").
## Ugyanezt használja a játékbeli „AI játszik” mód, a külső híd (tools/ugynok_hid.gd) és a gépek ranglistája.
## A beépített gépek nem tanuló rendszerek: rögzített szabályokat követnek (játékszabály, nem mesterséges intelligencia).

const World := preload("res://scripts/world.gd")
const Cards := preload("res://scripts/cards.gd")
const L := preload("res://scripts/i18n.gd")
const KINDS := ["kezdo", "atlagos", "okos"]

var w
var offers: Dictionary = {}          # témakör -> a körben felkínált kérdések (a felülettel közös lehet)
var rng := RandomNumberGenerator.new()


func _init(world, seed_n: int = 0) -> void:
	w = world
	rng.seed = seed_n * 31 + 7


func themes() -> Array:
	var out: Array = []
	for th in Cards.THEMES:
		if th in Cards.NO_TALK and w.max_era() < 4:
			continue
		out.append(th)
	return out


func offers_for(th: String) -> Array:
	if not offers.has(th):
		offers[th] = w.research_offers(th)
	return (offers[th] as Array).filter(func(id: String) -> bool: return not (id in w.hand))


# --- állapot --------------------------------------------------------------------
func observe(with_actions: bool = true) -> Dictionary:
	var en := L.is_en()
	var fc: Dictionary = {} if w.over() else w.forecast()
	var gs: Array = []
	for g in w.groups:
		gs.append({"id": g["id"], "name": L.field(g, "nev"), "co2_share": float(g["co2_resz"]), "emission_now": w.fraction(g, w.year() - 1),
			"target": int(g["cel"]), "methane_pledged": int(g["metan"]) > 0, "prepared": bool(g.get("felkeszult", false)),
			"wavering": bool(g.get("inog", false)), "stubborn": bool(g.get("makacs", false)), "fears": g["felelmek"],
			"myth_spreading": w.myth_on(g), "usable_cards": w.usable(g)})
	var hand: Array = []
	for id in w.hand:
		hand.append({"id": id, "theme": Cards.theme_of(id), "question": Cards.text(id, "Kérdés", en)})
	var out := {"year": w.year(), "round": w.round_i + 1, "rounds": World.ROUNDS, "steps": w.steps, "over": w.over(),
		"warming_now": float(w.st["T"]),
		"forecast_2100": {} if w.over() else {"low": float(fc["also"][-1][1]), "mid": float(fc["kozep"][-1][1]), "high": float(fc["felso"][-1][1])},
		"groups": gs, "hand": hand, "threat": w.threat, "myth": w.myth, "summit": w.summit_due, "dilemma": w.dilemma,
		"removal_running": w.cdr.map(func(c: Dictionary) -> String: return str(c["id"])), "missions_done": w.missions_done(),
		"earth_code": w.seed_v, "machine": w.ai}
	if w.over():
		var r: Dictionary = w.result()
		out["result"] = {"warming_2100": float(r["T"]), "if_nothing_changes": float(r["alap"]), "thresholds_crossed": int(r["billenes"])}
	if with_actions:
		out["actions"] = actions()
	return out


# --- szabályos lépések ----------------------------------------------------------
func actions() -> Array:
	var out: Array = []
	if w.over():
		return out
	if w.summit_due:
		for id in w.hand:
			var n: int = w.summit_listeners(id).size()
			if n > 0:
				out.append({"type": "summit", "card": id, "listeners": n})
		out.append({"type": "skip_summit"})
		return out
	if not w.dilemma.is_empty():
		var n2 := 3 if w.dilemma["fajta"] == "kviz" else 2
		for i in n2:
			out.append({"type": "dilemma", "choice": i})
		return out
	if w.steps > 0:
		if not w.myth.is_empty() and str(w.myth["kartya"]) in w.hand:
			out.append({"type": "refute", "group": str(w.myth["csoport"])})
		for g in w.groups:
			var us: Array = w.usable(g)
			if g.get("inog", false):
				for id in us:
					out.append({"type": "reassure", "group": g["id"], "card": id})
			for t in w.targets_for(g):
				if us.size() >= w.cards_needed(g, t):
					out.append({"type": "negotiate", "group": g["id"], "target": int(t), "cards_needed": w.cards_needed(g, t), "cooling": w.preview(g, int(t))})
			if int(g["metan"]) == 0 and w.methane_cards(g).size() >= w.methane_needed(g):
				out.append({"type": "methane", "group": g["id"], "cooling": w.preview(g, 0, true)})
			if not g.get("felkeszult", false) and not w.prepare_cards(g).is_empty():
				out.append({"type": "prepare", "group": g["id"], "card": w.prepare_cards(g)[0]})
		for id in w.cdr_available():
			out.append({"type": "cdr", "id": id})
		for th in themes():
			for id in offers_for(th):
				out.append({"type": "research", "theme": th, "card": id, "question": Cards.text(id, "Kérdés", L.is_en())})
	out.append({"type": "end_round"})
	return out


func apply(a: Dictionary) -> bool:
	if w.over():
		return false
	var kind := str(a.get("type", ""))
	if w.summit_due and not (kind in ["summit", "skip_summit"]):
		return false
	if not w.dilemma.is_empty() and kind != "dilemma":
		return false
	var g: Dictionary = w.group(str(a.get("group", ""))) if a.has("group") else {}
	match kind:
		"research":
			var th := str(a.get("theme", Cards.theme_of(str(a.get("card", "")))))
			if not (th in themes()) or not (str(a.get("card", "")) in offers_for(th)):
				return false
			if w.research(str(a["card"])):
				offers.erase(th)
				return true
			return false
		"negotiate":
			if g.is_empty():
				return false
			var t := int(a.get("target", 0))
			var cards: Array = a.get("cards", w.usable(g).slice(0, w.cards_needed(g, t)))
			for id in cards:
				if not (id in w.usable(g)):
					return false
			return w.negotiate(g, t, cards)
		"methane":
			if g.is_empty():
				return false
			return w.pledge_methane(g, a.get("cards", w.methane_cards(g).slice(0, w.methane_needed(g))))
		"prepare":
			return not g.is_empty() and w.prepare(g, str(a.get("card", w.prepare_cards(g)[0] if not w.prepare_cards(g).is_empty() else "")))
		"reassure":
			return not g.is_empty() and w.reassure(g, str(a.get("card", w.usable(g)[0] if not w.usable(g).is_empty() else "")))
		"refute":
			return not w.myth.is_empty() and w.refute(w.group(str(w.myth["csoport"])))
		"cdr":
			return w.start_cdr(str(a.get("id", "")))
		"summit":
			if not w.summit_due or w.summit_listeners(str(a.get("card", ""))).is_empty():
				return false
			w.summit(str(a["card"]), a.get("staying", []))
			return true
		"skip_summit":
			if not w.summit_due:
				return false
			w.skip_summit()
			return true
		"dilemma":
			if w.dilemma.is_empty():
				return false
			w.resolve_dilemma(int(a.get("choice", 0)))
			return true
		"end_round":
			w.advance()
			offers.clear()
			return true
	return false


# --- beépített gépek ------------------------------------------------------------
## Vissza: a lépés, benne "miert" (a mondat magyar kulcsa) és "mivel" (a mondatba illő név, ha kell).
func policy(kind: String) -> Dictionary:
	if w.over():
		return {}
	if w.summit_due:
		var best := ""
		for id in w.hand:
			if w.summit_listeners(id).size() > (w.summit_listeners(best).size() if best != "" else 0):
				best = id
		if kind != "kezdo" and best != "":
			return {"type": "summit", "card": best, "miert": "Klímacsúcs: azt a kártyát mutatom meg, amelyik a legtöbb csoportnak szól."}
		return {"type": "skip_summit", "miert": "A klímacsúcson most nem mutatok kártyát."}
	if not w.dilemma.is_empty():
		var d: Dictionary = w.dilemma
		var c := 0
		if d["fajta"] == "kviz":
			# Az okos gép a saját kártyáit olvassa el: a kérdés mondata a kártyán álló kulcsszám, a kezében lévő kártyán megtalálja.
			# Ha a kártya nincs a kezében (vagy nincs rajta kulcsszám), ő is csak tippel.
			c = rng.randi_range(0, 2)
			if kind == "okos" and str(d["id"]) in w.hand and not Cards.key_number(str(d["id"])).is_empty():
				c = (d["valasz"] as Array).find(d["id"])
		elif d["fajta"] == "tamogatas":
			c = 1 if kind == "okos" and int(w.group(str(d["a"])).get("cel", 0)) > 0 else 0
		else:
			var ga: Dictionary = w.group(str(d["a"]))
			var gb: Dictionary = w.group(str(d["b"]))
			c = 0 if kind != "okos" or float(ga["co2_resz"]) >= float(gb["co2_resz"]) else 1
		return {"type": "dilemma", "choice": c, "miert": "Döntök a két lehetőség közül." if d["fajta"] != "kviz" else "Válaszolok a tudáspróbára."}
	if w.steps <= 0:
		return {"type": "end_round", "miert": "Elfogytak a lépéseim. Jöhet a következő öt év."}
	var order: Array = w.groups.duplicate()
	if kind == "okos":
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["co2_resz"]) > float(b["co2_resz"]))
	else:
		for i in range(order.size() - 1, 0, -1):          # saját véletlenforrásból keverünk, hogy megismételhető legyen
			var j := rng.randi_range(0, i)
			var tmp: Dictionary = order[i]
			order[i] = order[j]
			order[j] = tmp
	if kind == "okos" and not w.myth.is_empty():
		var mg: Dictionary = w.group(str(w.myth["csoport"]))
		if str(w.myth["kartya"]) in w.hand:
			return {"type": "refute", "group": mg["id"], "miert": "Tévhit terjed. Megcáfolom: %s", "mivel": L.field(mg, "nev")}
		if str(w.myth["kartya"]) in offers_for("ketseg"):
			return {"type": "research", "theme": "ketseg", "card": str(w.myth["kartya"]), "miert": "Tévhit terjed. Kikutatom a cáfolatát."}
	if kind != "kezdo":
		for g in order:
			if g.get("inog", false) and not w.usable(g).is_empty() and (kind == "okos" or rng.randf() < 0.5):
				return {"type": "reassure", "group": g["id"], "card": w.usable(g)[0], "miert": "Elbizonytalanodtak. Megerősítem őket: %s", "mivel": L.field(g, "nev")}
	if kind == "okos" and not w.threat.is_empty():
		var tg: Dictionary = w.group(str(w.threat["csoport"]))
		if not tg.is_empty() and not tg.get("felkeszult", false) and not w.prepare_cards(tg).is_empty():
			return {"type": "prepare", "group": tg["id"], "card": w.prepare_cards(tg)[0], "miert": "Baj fenyeget. Felkészítem őket: %s", "mivel": L.field(tg, "nev")}
	for g in order:
		var n: int = w.usable(g).size()
		var ok: Array = w.targets_for(g).filter(func(t: int) -> bool: return n >= w.cards_needed(g, t))
		if not ok.is_empty():
			var t: int = ok[0] if kind == "kezdo" else (ok[rng.randi_range(0, ok.size() - 1)] if kind == "atlagos" else ok[ok.size() - 1])
			return {"type": "negotiate", "group": g["id"], "target": t,
				"miert": "Van hozzájuk illő kártyám. Tárgyalok: %s" if kind != "okos" else "A legnagyobb kibocsátóval kezdem, akit meg tudok győzni: %s", "mivel": L.field(g, "nev")}
		if kind != "kezdo" and int(g["metan"]) == 0 and w.methane_cards(g).size() >= w.methane_needed(g):
			return {"type": "methane", "group": g["id"], "miert": "A metán gyorsan hat. Metáncsökkentést kérek: %s", "mivel": L.field(g, "nev")}
	if kind == "okos":
		for id in w.cdr_available():
			return {"type": "cdr", "id": id, "miert": "Megvan a kártyám hozzá: elindítom a CO2-kivonást."}
		for g in order:
			if not g.get("felkeszult", false) and int(g["cel"]) > 0 and not w.prepare_cards(g).is_empty():
				return {"type": "prepare", "group": g["id"], "card": w.prepare_cards(g)[0], "miert": "Felkészítem őket, hogy ne inogjanak meg: %s", "mivel": L.field(g, "nev")}
	var ths: Array = Cards.talk_themes()
	var who := ""
	if kind == "okos":
		ths = []
		for g in order:
			if not w.targets_for(g).is_empty() and ths.is_empty():
				ths = (g["felelmek"] as Array).duplicate()
				who = L.field(g, "nev")
		if ths.is_empty():
			ths = Cards.talk_themes()
	for i in 6:                                   # néhány témakört megpróbál, hátha valahol van új kérdés
		var th: String = ths[rng.randi_range(0, ths.size() - 1)]
		var of := offers_for(th)
		if not of.is_empty():
			if who != "":
				return {"type": "research", "theme": th, "card": of[0], "miert": "Az ő aggodalmukhoz kutatok: %s", "mivel": who}
			return {"type": "research", "theme": th, "card": of[0], "miert": "Kutatok, hogy legyen mivel érvelnem."}
		ths = Cards.talk_themes() if i >= 2 else ths
	return {"type": "end_round", "miert": "Most nincs jó lépésem. Jöhet a következő öt év."}


## Egy teljes játék a megadott géppel (ablak nélkül): a ranglistához és a mérésekhez.
static func play(kind: String, seed_n: int, steps_n: int, challenge_n: int) -> Dictionary:
	var world = World.new()
	world.new_game(seed_n, steps_n, challenge_n)
	world.ai = true
	var ag = (load("res://scripts/agent.gd") as GDScript).new(world, seed_n)
	var guard := 0
	while not world.over() and guard < 4000:
		guard += 1
		var a: Dictionary = ag.policy(kind)
		if a.is_empty() or not ag.apply(a):
			ag.apply({"type": "skip_summit"})
			if not world.dilemma.is_empty():
				world.resolve_dilemma(0)
			if not ag.apply({"type": "end_round"}):
				break
	return world.result()
