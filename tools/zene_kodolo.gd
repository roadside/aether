extends SceneTree
## Zenefájl kódolása a játékhoz: az eredmény önmagában nem játszható le, csak a játék fejti vissza.
## Használat: godot --headless --path . -s tools/zene_kodolo.gd -- <bemenet> <kimenet>
## A már kódolt fájlt nem kódolja újra. Ellenőrzésként visszafejti, és összeveti az eredetivel.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		print("KODOLO hiba: két útvonal kell")
		quit(1)
		return
	var I = load("res://scripts/intro.gd")
	var src := FileAccess.get_file_as_bytes(a[0])
	if src.is_empty():
		print("KODOLO hiba: a bemenet nem olvasható")
		quit(1)
		return
	if src.slice(0, 6).get_string_from_ascii() == I.MUSIC_MAGIC:
		print("KODOLO: már kódolt, nem nyúlok hozzá")
		quit(0)
		return
	var enc: PackedByteArray = I.encode_music(src)
	if I.decode_music(enc) != src:
		print("KODOLO hiba: a visszafejtés nem egyezik")
		quit(1)
		return
	var f := FileAccess.open(a[1], FileAccess.WRITE)
	if f == null:
		print("KODOLO hiba: a kimenet nem írható")
		quit(1)
		return
	f.store_buffer(enc)
	f.close()
	print("KODOLO kész: %d -> %d bájt" % [src.size(), enc.size()])
	quit(0)
