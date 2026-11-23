extends SceneTree
## A GDScript-modell a Python-modell (aether_lab/climate.py) számaihoz mérve. Futtatás:
##   godot --headless -s tools/modell_teszt.gd
const M := preload("res://scripts/model.gd")

func _ramp(y: int, a: int, b: int) -> float:
	return clampf(float(y - a) / float(b - a), 0.0, 1.0)

func _init() -> void:
	var cases := {
		"alap": func(_y: int) -> Dictionary: return {},
		"nulla2050": func(y: int) -> Dictionary: return {"co2": M.E_CO2_NOW * (1.0 - _ramp(y, 2025, 2050))},
		"metan45": func(y: int) -> Dictionary: return {"ch4": 0.45 * _ramp(y, 2025, 2030)},
	}
	for name in cases:
		var line: String = str(name) + ":"
		for s in [-1.0, 0.0, 1.0]:
			var pr: Array = M.project(M.new_state(), cases[name], M.params(s))
			var t50 := 0.0
			for r in pr:
				if r[0] == 2050:
					t50 = r[1]
			line += " %.2f/%.2f" % [t50, pr[-1][1]]
		print("MODELL ", line)
	quit()
