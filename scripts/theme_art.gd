extends RefCounted
## Kis, kódból festett kép minden kutatási témakörhöz (84×40 képpont). Saját rajz, nem átvett kép,
## és nem valós hely: csak hangulat, hogy a témakör első pillantásra felismerhető legyen.

const Landscape := preload("res://scripts/landscape.gd")
const W := 84
const H := 40

static var _cache: Dictionary = {}


static func _sky(img: Image, top: Color, bot: Color) -> void:
	for y in H:
		var c := top.lerp(bot, pow(float(y) / float(H - 1), 1.3))
		for x in W:
			var d := (float((x * 7 + y * 13) % 5) - 2.0) * 0.008
			img.set_pixel(x, y, Color(c.r + d, c.g + d, c.b + d))


static func _box(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			Landscape._px(img, x, y, c)


static func _line(img: Image, a: Vector2i, b: Vector2i, c: Color) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var t := float(i) / float(maxi(n, 1))
		Landscape._px(img, roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)), c)


static func _ground(img: Image, y0: int, c: Color) -> void:
	for y in range(y0, H):
		for x in W:
			img.set_pixel(x, y, c.darkened(0.12 * float(y - y0) / float(H - y0)) if (x * 3 + y * 5) % 7 != 0 else c.lightened(0.06))


static func texture(th: String) -> Texture2D:
	if _cache.has(th):
		return _cache[th]
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	match th:
		"aram":
			_sky(img, Color("#3d5a94"), Color("#f2c27a"))
			Landscape._disc(img, 66, 24, 9, Color(1.0, 0.9, 0.6, 0.25))
			Landscape._disc(img, 66, 24, 5, Color("#fff0b8"))
			Landscape._hills(img, Color("#4a6a6e"), 27.0, 2.5, 0.09, 0.4, 1.2, 0.27)
			Landscape._hills(img, Color("#2f5a48"), 32.0, 1.6, 0.07, 2.0, 0.8, 0.21)
			for px in [12, 38]:                      # távvezeték-oszlopok
				_line(img, Vector2i(px, 17), Vector2i(px - 3, 33), Color("#1c2530"))
				_line(img, Vector2i(px, 17), Vector2i(px + 3, 33), Color("#1c2530"))
				_line(img, Vector2i(px - 4, 20), Vector2i(px + 4, 20), Color("#1c2530"))
				_line(img, Vector2i(px - 3, 24), Vector2i(px + 3, 24), Color("#1c2530"))
				_line(img, Vector2i(px - 2, 28), Vector2i(px + 2, 28), Color("#1c2530"))
			for x in range(0, 84):                    # belógó vezetékek
				var sag := int(round(3.0 * sin(PI * fposmod(float(x - 12), 26.0) / 26.0)))
				Landscape._px(img, x, 20 + sag, Color(0.1, 0.13, 0.18, 0.8))
			Landscape._turbine(img, 56, 30, 0)
			Landscape._turbine(img, 74, 31, 1)
			Landscape._solar(img, 22, 36)
			Landscape._solar(img, 29, 37)
		"munka":
			_sky(img, Color("#6f8fb5"), Color("#e9d6b8"))
			_ground(img, 31, Color("#6a6f66"))
			_box(img, 6, 20, 30, 11, Color("#8a5a48"))          # gyárcsarnok fűrészfogas tetővel
			for i in 5:
				for k in 5:
					_line(img, Vector2i(6 + i * 6 + k, 19 - k), Vector2i(6 + i * 6 + k, 20), Color("#a06a54"))
			for i in 6:
				_box(img, 9 + i * 5, 24, 2, 3, Color("#ffe6a0"))
			_box(img, 38, 9, 4, 22, Color("#7a4c3e"))            # kémény, belőle csak gőz száll
			_box(img, 38, 9, 4, 2, Color("#c9c2b8"))
			for p in [[41, 6, 3], [45, 4, 3], [50, 3, 2]]:
				Landscape._disc(img, int(p[0]), int(p[1]), int(p[2]), Color(1, 1, 1, 0.55))
			_box(img, 0, 33, 84, 1, Color("#3a3d3a"))            # sín és villanyvonat
			_box(img, 46, 27, 34, 6, Color("#2f7fb8"))
			_box(img, 46, 27, 34, 1, Color("#e8f2f8"))
			for i in 6:
				_box(img, 49 + i * 5, 29, 3, 2, Color("#d8f0ff"))
			_line(img, Vector2i(76, 27), Vector2i(83, 31), Color("#2f7fb8"))
			_line(img, Vector2i(60, 26), Vector2i(64, 23), Color("#1c2530"))
			_box(img, 44, 23, 40, 1, Color("#1c2530"))
		"elelem":
			_sky(img, Color("#7fc0e0"), Color("#f6e7b0"))
			Landscape._disc(img, 16, 9, 7, Color(1.0, 0.95, 0.7, 0.25))
			Landscape._disc(img, 16, 9, 4, Color("#fff6c8"))
			Landscape._hills(img, Color("#7fae5a"), 22.0, 2.0, 0.08, 1.0, 1.0, 0.2)
			_ground(img, 26, Color("#d9b24a"))
			for y in range(26, H):                    # a búzatábla sorai összetartanak a látóhatár felé
				for x in W:
					var k := float(y - 25) / 14.0
					if int(floor((float(x) - 42.0) / (1.5 + k * 5.0) + 100.0)) % 2 == 0:
						Landscape._px(img, x, y, Color(0.75, 0.56, 0.18, 0.55))
			_box(img, 58, 17, 12, 8, Color("#a8483a"))           # pajta
			for k in 7:
				_line(img, Vector2i(57 + k, 17 - k), Vector2i(71 - k, 17 - k), Color("#6a3a30"))
			_box(img, 62, 20, 4, 5, Color("#4a2a22"))
			_box(img, 73, 13, 4, 12, Color("#c9c9c0"))           # siló
			Landscape._disc(img, 75, 13, 2, Color("#e2e2da"))
		"part":
			_sky(img, Color("#5aa6d8"), Color("#d8eef2"))
			for c in [[20, 7, 4], [26, 8, 5], [33, 7, 3], [60, 5, 3], [65, 6, 4]]:
				Landscape._disc(img, int(c[0]), int(c[1]), int(c[2]), Color(1, 1, 1, 0.8))
			for y in range(20, H):
				for x in W:
					var sea := Color("#2f7fae").lerp(Color("#1d5f8a"), float(y - 20) / 20.0)
					img.set_pixel(x, y, sea.lightened(0.25) if int(float(x) + sin(float(y) * 1.3) * 3.0 + float(y) * 2.0) % 9 == 0 else sea)
			for x in range(0, 30):                    # szikla a világítótoronnyal
				var top := 30 - int(10.0 * sin(float(x) / 30.0 * PI * 0.62 + 0.5))
				for y in range(top, H):
					img.set_pixel(x, y, Color("#5a6a58") if y > top else Color("#7fae6a"))
			_box(img, 12, 8, 4, 13, Color("#f2f2ea"))
			_box(img, 12, 12, 4, 2, Color("#d8483a"))
			_box(img, 12, 17, 4, 2, Color("#d8483a"))
			_box(img, 11, 6, 6, 2, Color("#2a3a4a"))
			_box(img, 13, 6, 2, 2, Color("#fff2a0"))
			_line(img, Vector2i(17, 7), Vector2i(34, 4), Color(1.0, 0.95, 0.6, 0.35))
			_line(img, Vector2i(17, 7), Vector2i(34, 9), Color(1.0, 0.95, 0.6, 0.35))
			_box(img, 56, 24, 9, 2, Color("#f2f2ea"))            # vitorlás
			_line(img, Vector2i(60, 14), Vector2i(60, 24), Color("#3a3a3a"))
			for k in 8:
				_line(img, Vector2i(61, 15 + k), Vector2i(61 + k / 2 + 1, 15 + k), Color("#ffffff"))
		"egeszseg":
			_sky(img, Color("#78b8e0"), Color("#eef0d8"))
			Landscape._disc(img, 68, 9, 4, Color("#fff6c8"))
			for b in [[4, 14, 9], [14, 9, 8], [23, 16, 10], [34, 11, 7], [42, 18, 9], [52, 13, 8], [61, 17, 10], [72, 12, 9]]:
				_box(img, int(b[0]), int(b[1]), int(b[2]), 30 - int(b[1]), Color("#8fa3b8") if int(b[0]) % 3 != 0 else Color("#a7b6c6"))
				for wy in range(int(b[1]) + 2, 28, 3):
					for wx in range(int(b[0]) + 1, int(b[0]) + int(b[2]) - 1, 2):
						Landscape._px(img, wx, wy, Color("#dff2ff") if (wx + wy) % 5 != 0 else Color("#ffe6a0"))
			for r in [[16, 8], [36, 10], [74, 11]]:   # zöldtetők
				_box(img, int(r[0]) - 2, int(r[1]), 6, 1, Color("#58b060"))
			_ground(img, 30, Color("#6fae5a"))
			for t in [[6, 31], [20, 32], [33, 31], [48, 32], [60, 31], [78, 32]]:   # városi fák
				_box(img, int(t[0]), int(t[1]), 1, 4, Color("#5a4030"))
				Landscape._disc(img, int(t[0]), int(t[1]) - 1, 3, Color("#2f8a4a"))
				Landscape._disc(img, int(t[0]) - 1, int(t[1]) - 2, 1, Color("#58b060"))
			_box(img, 0, 37, 84, 1, Color("#d8d2c0"))
		"ketseg":
			_sky(img, Color("#141a3a"), Color("#3a3f78"))
			for i in 34:                              # csillagok
				Landscape._px(img, (i * 37 + 11) % W, (i * 13 + 3) % 24, Color(1, 1, 1, 0.5 + 0.5 * float(i % 3) / 2.0))
			for i in 30:                              # tejút-sáv
				Landscape._px(img, 20 + i * 2 + (i * 7) % 3, 2 + i / 2 + (i * 5) % 4, Color(0.8, 0.8, 1.0, 0.35))
			Landscape._hills(img, Color("#232a4a"), 29.0, 3.0, 0.07, 0.8, 1.2, 0.19)
			Landscape._hills(img, Color("#161c34"), 34.0, 1.4, 0.1, 2.2, 0.8, 0.3)
			_box(img, 22, 22, 14, 8, Color("#c9cfdc"))           # csillagvizsgáló
			Landscape._disc(img, 29, 22, 7, Color("#e6eaf2"))
			_box(img, 22, 23, 14, 7, Color("#c9cfdc"))
			_box(img, 28, 15, 2, 8, Color("#232a4a"))
			_line(img, Vector2i(29, 16), Vector2i(40, 6), Color(0.7, 0.9, 1.0, 0.28))
			_box(img, 27, 26, 3, 4, Color("#ffe6a0"))
			_line(img, Vector2i(62, 18), Vector2i(62, 31), Color("#8a93a8"))    # mérőállomás antennája
			_line(img, Vector2i(58, 22), Vector2i(66, 22), Color("#8a93a8"))
			Landscape._disc(img, 62, 17, 1, Color("#ff5a5a"))
			Landscape._disc(img, 72, 8, 2, Color("#f2e6d0"))      # időjárási ballon
			_line(img, Vector2i(72, 10), Vector2i(72, 15), Color(0.9, 0.9, 0.9, 0.6))
			_box(img, 71, 15, 2, 2, Color("#d8d8d8"))
		"olaj":
			_sky(img, Color("#5a4a78"), Color("#f2a86a"))
			Landscape._disc(img, 20, 24, 6, Color("#ffd9a0"))
			_ground(img, 29, Color("#8a6a48"))
			Landscape._hills(img, Color("#7a5a40"), 30.0, 1.0, 0.07, 1.0, 0.6, 0.2)
			# bólogató kút
			_line(img, Vector2i(46, 30), Vector2i(50, 18), Color("#1c1c22"))
			_line(img, Vector2i(54, 30), Vector2i(50, 18), Color("#1c1c22"))
			_line(img, Vector2i(40, 21), Vector2i(60, 15), Color("#1c1c22"))
			_line(img, Vector2i(40, 22), Vector2i(60, 16), Color("#1c1c22"))
			_box(img, 37, 20, 4, 5, Color("#1c1c22"))
			_line(img, Vector2i(39, 25), Vector2i(39, 31), Color("#1c1c22"))
			_box(img, 58, 14, 4, 4, Color("#2a2a32"))
			# fáklya: itt ég el a gáz
			_box(img, 72, 14, 2, 17, Color("#2a2a32"))
			Landscape._disc(img, 73, 11, 3, Color(1.0, 0.6, 0.2, 0.55))
			Landscape._disc(img, 73, 12, 2, Color("#ffd24a"))
			_line(img, Vector2i(73, 8), Vector2i(75, 5), Color(1.0, 0.5, 0.2, 0.7))
			for p in [[77, 4, 2], [80, 2, 2]]:
				Landscape._disc(img, int(p[0]), int(p[1]), int(p[2]), Color(0.2, 0.2, 0.25, 0.45))
			_box(img, 4, 26, 10, 5, Color("#c9c2b8"))            # tartály
			_box(img, 4, 26, 10, 1, Color("#e6e0d6"))
		"erdo":
			_sky(img, Color("#6fb0c8"), Color("#e6f0c8"))
			Landscape._hills(img, Color("#5a9a82"), 16.0, 4.0, 0.08, 0.5, 2.0, 0.21)
			Landscape._hills(img, Color("#3f8060"), 22.0, 3.0, 0.1, 2.0, 1.5, 0.27)
			for i in 14:
				Landscape._pine(img, 3 + i * 6, 25 + (i * 5) % 3, Color("#2a6a48"))
			Landscape._hills(img, Color("#2f6a44"), 31.0, 1.5, 0.09, 1.2, 0.8, 0.31)
			for i in 11:
				Landscape._pine(img, 5 + i * 8 + (i * 3) % 4, 33 + (i * 7) % 3, Color("#1c4a30"))
			for y in range(33, H):                    # patak
				var cx := 40 + int(6.0 * sin(float(y) * 0.5))
				_box(img, cx - (y - 32) / 2, y, 2 + (y - 32), 1, Color("#8fd0e8"))
		_:      # kockázatos ötletek: fátyol a Nap előtt, magasan szálló gépek húzzák
			_sky(img, Color("#1c2a5a"), Color("#c8b8a0"))
			Landscape._disc(img, 42, 14, 9, Color(1.0, 0.9, 0.7, 0.2))
			Landscape._disc(img, 42, 14, 6, Color("#f6e2b0"))
			for y in range(9, 21):                    # a fátyol sávjai elhomályosítják a Napot
				if y % 2 == 0:
					for x in W:
						Landscape._px(img, x, y, Color(0.85, 0.85, 0.9, 0.38 if (x + y) % 3 != 0 else 0.22))
			for pl in [[14, 7], [58, 11]]:            # két gép, mögöttük fehér csík
				_box(img, int(pl[0]), int(pl[1]), 4, 1, Color("#f2f2f2"))
				_box(img, int(pl[0]) + 1, int(pl[1]) - 1, 1, 3, Color("#f2f2f2"))
				_line(img, Vector2i(0 if int(pl[0]) < 40 else 34, int(pl[1])), Vector2i(int(pl[0]) - 1, int(pl[1])), Color(1, 1, 1, 0.6))
			# a Föld íve alul
			for x in W:
				var top := 30 + int(pow(float(x - 42) / 42.0, 2.0) * 7.0)
				for y in range(top, H):
					img.set_pixel(x, y, Color("#4f9a5a") if sin(float(x) * 0.21) + sin(float(x) * 0.07 + float(y) * 0.5) > 1.05 else Color("#2f6fae"))
				Landscape._px(img, x, top - 1, Color(0.6, 0.85, 1.0, 0.6))
	var tex := ImageTexture.create_from_image(img)
	_cache[th] = tex
	return tex


static func rect(th: String, width: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture(th)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(width, roundi(width * float(H) / float(W)))
	t.size = t.custom_minimum_size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
