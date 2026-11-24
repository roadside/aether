extends SceneTree
## A beépített gépek mérése: godot --headless --path . -s tools/ugynok_teszt.gd -- [N]
const Agent := preload("res://scripts/agent.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n: int = int(a[0]) if a.size() > 0 else 30
	for kind in Agent.KINDS:
		var ts: Array = []
		for i in n:
			ts.append(float(Agent.play(kind, 1000 + i, 4, 0)["T"]))
		ts.sort()
		print("GEP %s (%d Föld): 10%%/közép/90%% = %.2f / %.2f / %.2f" % [kind, n, ts[int(0.1 * (n - 1))], ts[int(0.5 * (n - 1))], ts[int(0.9 * (n - 1))]])
	quit()
