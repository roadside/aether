extends RefCounted
## Vita (JÁTÉKSZABÁLY): időnként valaki egy gyakori tévhitet állít. A játékos a saját, már
## kikutatott témái közül választja ki, melyik cáfolja. A válasz szövege nem itt van megírva:
## a téma lektorált „Mennyire bizonyított?” mezője (temak/*.txt), a forrásaival együtt.
## Jó válasz: bizalom nő. Csak olyan tévhit jön elő, amelynek a témáját a játékos már kikutatta.

const L := preload("res://scripts/i18n.gd")
const UI := preload("res://scripts/ui.gd")
const Knowledge := preload("res://scripts/knowledge.gd")

const CHANCE := 0.22          # évente ekkora eséllyel jön vita, ha van hozzá kikutatott téma
const WIN_TRUST := 3
const LOSE_TRUST := 1

## tema: ennek a témának a lektorált szövege a válasz.
const CLAIMS := [
	{"id": "nap", "tema": "napaktivitas", "allitas": "A Nap okozza a felmelegedést, nem az ember."},
	{"id": "kozmikus", "tema": "kozmikus", "allitas": "A kozmikus sugarak okozzák a felmelegedést."},
	{"id": "gronland", "tema": "gronland", "allitas": "Grönland jege nem olvad."},
	{"id": "tenger", "tema": "tengerszint", "allitas": "A tenger szintje nem fog emelkedni."},
	{"id": "villanyauto", "tema": "villanyauto", "allitas": "A villanyautó a teljes élete alatt több CO2-t okoz, mint a benzines."},
	{"id": "napelem", "tema": "napelem", "allitas": "A napelem nem csökkenti a CO2-kibocsátást."},
	{"id": "felhok", "tema": "felhok", "allitas": "A felhők majd megállítják a felmelegedést."},
	{"id": "korall", "tema": "korall", "allitas": "A korallok jól bírják a melegebb vizet."},
	{"id": "termes", "tema": "termes", "allitas": "A felmelegedéstől több lesz a termés."},
	{"id": "atom", "tema": "atomenergia", "allitas": "Az atomerőmű áramtermelése sok CO2 kibocsátással jár."},
	{"id": "szel", "tema": "szelenergia", "allitas": "A szélerőmű árama sok CO2 kibocsátással jár."},
	{"id": "savasodas", "tema": "ocean_savasodas", "allitas": "Az óceán savasodásának semmi köze a CO2-höz."},
]


static func _rng(campaign, y: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(campaign.world_seed) * 7919 + y * 31 + 5
	return rng


## Az adott év vitája, vagy üres. Tiszta függvény (a magból és az évből sorsol).
## force: az önteszthez, sorsolás nélkül az első lehetséges vita.
static func pick(campaign, y: int, force: bool = false) -> Dictionary:
	if campaign.done.size() < 3:
		return {}
	var rng := _rng(campaign, y)
	if not force and rng.randf() >= CHANCE:
		return {}
	var pool: Array = []
	for c in CLAIMS:
		if c["tema"] in campaign.done and not (c["id"] in campaign.debated) \
				and Knowledge.text(Knowledge.topic(c["tema"]), "mennyire_bizonyitott") != "":
			pool.append(c)
	if pool.is_empty():
		return {}
	var claim: Dictionary = pool[rng.randi() % pool.size()]
	var others: Array = []
	for id in campaign.done:
		if id != claim["tema"] and not Knowledge.topic(str(id)).is_empty():
			others.append(str(id))
	var opts: Array = [str(claim["tema"])]
	while opts.size() < 3 and not others.is_empty():
		var i := rng.randi() % others.size()
		opts.append(others[i])
		others.remove_at(i)
	for i in range(opts.size() - 1, 0, -1):     # keverés
		var j := rng.randi() % (i + 1)
		var tmp: String = opts[i]
		opts[i] = opts[j]
		opts[j] = tmp
	return {"id": claim["id"], "tema": claim["tema"], "allitas": claim["allitas"], "valaszok": opts, "ev": y}


## A játékos válasza: bizalom változik, a tévhit többé nem jön elő. Visszaadja, jó volt-e.
static func answer(campaign, d: Dictionary, topic_id: String) -> bool:
	var good := topic_id == str(d["tema"])
	campaign.trust = clampi(campaign.trust + (WIN_TRUST if good else -LOSE_TRUST), 0, 100)
	if not (d["id"] in campaign.debated):
		campaign.debated.append(d["id"])
	campaign.save()
	campaign.changed.emit()
	return good


static func panel(campaign, d: Dictionary, on_ok: Callable) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.border_color = UI.CYAN
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 28
	sb.set_content_margin_all(26)
	p.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(14)
	p.add_child(v)
	var head := UI.hbox(14)
	head.add_child(UI.heading(L.t("Vita")))
	var tag := UI.label(L.t("gyakori tévhit"), 13, UI.MUTE, false, false)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(tag)
	v.add_child(head)
	v.add_child(UI.label(L.t("Valaki ezt állítja:"), 16, UI.SOFT))
	var c := UI.card(UI.EMBER)
	c.add_child(UI.label("„%s”" % L.t(d["allitas"]), 24, UI.TEXT, true))
	v.add_child(UI.card_root(c))
	var box := UI.vbox(10)
	v.add_child(box)
	box.add_child(UI.label(L.t("Melyik kutatásod cáfolja?"), 18, UI.GOLD, true))
	for id in d["valaszok"]:
		var q: Dictionary = Knowledge.topic(str(id))
		var b := UI.button(Knowledge.text(q, "cim"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		var pick_fn := func() -> void:
			var good := answer(campaign, d, str(id))
			UI.clear(box)
			var right: Dictionary = Knowledge.topic(str(d["tema"]))
			if good:
				box.add_child(UI.label(L.t("Jó válasz! +%d%% bizalom") % WIN_TRUST, 22, UI.GREEN, true))
			else:
				box.add_child(UI.label(L.t("Nem ez cáfolja. −%d%% bizalom") % LOSE_TRUST, 22, UI.EMBER, true))
			box.add_child(UI.label(Knowledge.text(right, "cim"), 18, UI.CYAN, true))
			box.add_child(UI.label(Knowledge.text(right, "mennyire_bizonyitott"), 18, UI.TEXT))
			var ok := UI.button(L.t("Rendben"), true)
			ok.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			ok.pressed.connect(on_ok)
			box.add_child(ok)
		b.pressed.connect(pick_fn)
		box.add_child(b)
	return p
