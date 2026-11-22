extends Node
## Kapcsolat a Python AETHER Lab-bal.
## A Python-parancsokat háttérszálon futtatja, hogy a játék ne akadjon meg.
## A kommunikáció fájlokon át történik (allapot.json, eredmeny.json, ...).

signal finished(tag: String, code: int, output: String)

var _thread: Thread
var _python := ""          # az első működő Python-parancs (py / python / python3)
var _tag := ""


func lab_dir() -> String:
	# Szerkesztőből: a projektmappa melletti AETHER_terv\prototipus.
	# Exportált játéknál: a futtatható fájl melletti "prototipus" mappa.
	var dev := ProjectSettings.globalize_path("res://").path_join("../AETHER_terv/prototipus").simplify_path()
	if DirAccess.dir_exists_absolute(dev):
		return dev
	return OS.get_executable_path().get_base_dir().path_join("prototipus")


func work_dir(name: String) -> String:
	var d := OS.get_user_data_dir().path_join(name)
	DirAccess.make_dir_recursive_absolute(d)
	return d


func is_busy() -> bool:
	return _thread != null and _thread.is_alive()


## Elindít egy aether_lab parancsot (pl. ["godot-modell", be, "--ki", ki]).
## A végén a `finished` jelzés érkezik a fő szálon.
func run(tag: String, args: Array) -> bool:
	if is_busy():
		return false
	if _thread != null:
		_thread.wait_to_finish()
	_tag = tag
	_thread = Thread.new()
	_thread.start(_worker.bind(PackedStringArray(args)))
	return true


func _worker(args: PackedStringArray) -> void:
	var wrapper := "import os,runpy,sys; os.chdir(sys.argv[1]); sys.path.insert(0, sys.argv[1]); sys.argv=['aether_lab']+sys.argv[2:]; runpy.run_module('aether_lab', run_name='__main__')"
	var candidates: Array = [_python] if _python != "" else ["py", "python", "python3"]
	# a kiadott játék a saját, mellé csomagolt Pythonját használja (a játékos gépén nem kell Python)
	var own := lab_dir().path_join("python").path_join("python.exe")
	if _python == "" and FileAccess.file_exists(own):
		candidates.push_front(own)
	var code := -1
	var output: Array = []
	for exe in candidates:
		var full := PackedStringArray(["-c", wrapper, lab_dir()])
		full.append_array(args)
		output.clear()
		code = OS.execute(exe, full, output, true)
		if code == 0:
			_python = exe
			break
		if code != -1 and code != 9009 and code != 127:   # 127: nincs ilyen parancs (Linux)
			break  # a Python elindult, de hibával állt le: ezt jelezzük, nem próbálunk mást
	call_deferred("_emit", code, "\n".join(PackedStringArray(output)))


func _emit(code: int, output: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	finished.emit(_tag, code, output)


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, " "))
	f.close()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
