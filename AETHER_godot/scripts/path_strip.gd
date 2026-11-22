extends Control
## „A jövő görbéje”: a főképernyő alján mindig látszik, merre tart a Föld hőmérséklete.
## Arany vonal: a te utad (a bevezetett terved szerint). Tompa piros: ha semmi sem változik.
## Minden érték a klímamodellből jön (campaign.model), a fehér pont a mostani év.

const UI := preload("res://scripts/ui.gd")
const L := preload("res://scripts/i18n.gd")

var campaign                  # campaign.gd példány
const Y0 := 2026
const Y1 := 2100
const RIGHT := 214.0          # a jobb oldali számok helye
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 78)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = L.t("A klímamodell szerint. Arany: a te utad, a sávval, amin belül a Föld járhat. Piros: ha semmi sem változik. Fehér: ami eddig történt.")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _series(group: String, ens: String) -> Array:
	var m: Dictionary = campaign.model
	var g: Variant = m.get(group, {})
	if typeof(g) != TYPE_DICTIONARY or not g.has(ens):
		return []
	var s: Variant = g[ens].get("homerseklet", [])
	return s if typeof(s) == TYPE_ARRAY else []


static func temp_color(t: float) -> Color:
	if t < 1.5:
		return UI.GREEN
	if t < 2.0:
		return UI.GOLD
	return UI.EMBER


func _draw() -> void:
	if campaign == null or campaign.model.is_empty():
		draw_string(UI.font_body, Vector2(8, 44), L.t("Számolok…"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.MUTE)
		return
	var years: Array = campaign.model.get("evek", [])
	var plan: Array = _series("terv", "kozep")
	var lo: Array = _series("terv", "alacsony")
	var hi: Array = _series("terv", "magas")
	var base: Array = _series("alapeset", "kozep")
	if years.is_empty() or plan.size() != years.size():
		return
	if base.size() != years.size():
		base = plan
	var has_plan: bool = not campaign.timeline.is_empty()
	var i0 := 0
	for i in years.size():
		if int(years[i]) == Y0:
			i0 = i
	var tmin := 1.2
	var tmax := 3.0
	for i in range(i0, years.size()):
		tmax = maxf(tmax, float(base[i]) + 0.1)
		tmax = maxf(tmax, float(plan[i]) + 0.1)
	var x0 := 6.0
	var x1 := size.x - RIGHT
	var y0 := size.y - 14.0
	var y1 := 6.0
	var px := func(year: float) -> float:
		return x0 + (year - Y0) / float(Y1 - Y0) * (x1 - x0)
	var py := func(t: float) -> float:
		return y0 + (t - tmin) / (tmax - tmin) * (y1 - y0)
	# háttér és a két határ: 1,5 és 2 °C
	draw_rect(Rect2(x0, y1, x1 - x0, y0 - y1), Color(0.03, 0.05, 0.10, 0.85))
	for lim in [1.5, 2.0]:
		var ly: float = py.call(lim)
		var x := x0
		while x < x1:
			draw_line(Vector2(x, ly), Vector2(minf(x + 6.0, x1), ly), Color(1, 1, 1, 0.22), 1.0)
			x += 12.0
		draw_string(UI.font_body, Vector2(x0 + 4, ly - 3), "%s °C" % UI.hu(lim, 1 if lim < 2.0 else 0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
	# évtizedek az alján
	for dec in [2030, 2050, 2075, 2100]:
		var dx: float = px.call(float(dec))
		draw_line(Vector2(dx, y0), Vector2(dx, y0 + 3), Color(1, 1, 1, 0.35), 1.0)
		draw_string(UI.font_body, Vector2(dx - (26 if dec == 2100 else 14), size.y - 1), str(dec), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.MUTE)
	var pts_base := PackedVector2Array()
	var pts_plan := PackedVector2Array()
	var band_top := PackedVector2Array()
	var band_bot := PackedVector2Array()
	for i in range(i0, years.size()):
		var xx: float = px.call(float(years[i]))
		pts_base.append(Vector2(xx, py.call(float(base[i]))))
		pts_plan.append(Vector2(xx, py.call(float(plan[i]))))
		if hi.size() == years.size() and lo.size() == years.size():
			band_top.append(Vector2(xx, py.call(float(hi[i]))))
			band_bot.append(Vector2(xx, py.call(float(lo[i]))))
	var t_end := float(plan[-1])
	var col := temp_color(t_end)
	# bizonytalansági sáv a te utad körül
	if has_plan and band_top.size() > 1:
		var poly := PackedVector2Array(band_top)
		for i in range(band_bot.size() - 1, -1, -1):
			poly.append(band_bot[i])
		draw_colored_polygon(poly, Color(col, 0.13))
	# ha semmi sem változik
	draw_polyline(pts_base, Color(UI.EMBER, 0.75 if has_plan else 1.0), 2.0 if has_plan else 3.0, true)
	if has_plan:
		draw_polyline(pts_plan, col, 3.0, true)
		# a két út közti rés a végén: ennyit számít a terved
		var ex := x1 - 1.0
		draw_line(Vector2(ex, pts_base[-1].y + 3), Vector2(ex, pts_plan[-1].y - 3), Color(1, 1, 1, 0.5), 1.0)
	# ami eddig történt ebben a játékban (a „mért” évek): fehér vonal
	var hist := PackedVector2Array()
	hist.append(Vector2(px.call(float(Y0)), py.call(float(plan[i0]))))
	for h in campaign.history:
		hist.append(Vector2(px.call(float(h["ev"])), py.call(float(h["T"]))))
	if hist.size() > 1:
		draw_polyline(hist, Color(1, 1, 1, 0.9), 2.0, true)
	# a mostani év: lüktető pont
	var tn: float = campaign.measured_temp(campaign.year)
	if is_nan(tn):
		tn = float(plan[i0])
	var np := Vector2(px.call(clampf(float(campaign.year), Y0, Y1)), py.call(tn))
	draw_line(Vector2(np.x, y1), Vector2(np.x, y0), Color(1, 1, 1, 0.18), 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(np, 7.0 + 3.0 * pulse, Color(1, 1, 1, 0.16))
	draw_circle(np, 4.0, Color.WHITE)
	# jobb oldal: hová jutunk 2100-ra
	var rx := x1 + 16.0
	draw_string(UI.font_body, Vector2(rx, 18), L.t("2100-ban"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.MUTE)
	if has_plan:
		draw_string(UI.font_bold, Vector2(rx, 50), "+%s °C" % UI.hu(t_end, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, col)
		draw_string(UI.font_body, Vector2(rx, 70), L.t("terv nélkül +%s °C") % UI.hu(float(base[-1]), 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UI.EMBER, 0.95))
	else:
		draw_string(UI.font_bold, Vector2(rx, 50), "+%s °C" % UI.hu(float(base[-1]), 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UI.EMBER)
		draw_string(UI.font_body, Vector2(rx, 70), L.t("Még nincs terved."), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.SOFT)
