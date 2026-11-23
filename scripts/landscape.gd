extends RefCounted
## Kis, kódból festett tájkép minden országcsoporthoz (84×40 képpont). Saját rajz, nem átvett kép,
## és nem egy valós hely ábrázolása: csak hangulat (erdős dombok, fennsík, karszthegyek, monszun, szavanna, dűnék).

const W := 84
const H := 40

## ég felül, ég alul, nap [x, y, sugár, szín], távoli réteg, közeli réteg
const SPEC := {
	"europa": ["#7fb4d8", "#e7d9b8", [64, 11, 4, "#fff3c8"], "#5f8f7a", "#3f7a4a"],
	"usa": ["#5a6fae", "#f0b08a", [18, 15, 5, "#ffd9a0"], "#b0603c", "#c79a55"],
	"kina": ["#8fb8b4", "#dfe6d0", [60, 9, 4, "#fbf6dc"], "#6f9c94", "#4f8a5c"],
	"india": ["#5f7890", "#b9c4c0", [0, 0, 0, "#ffffff"], "#5d8a72", "#4c9a58"],
	"afrika": ["#e98a4a", "#f7cf7a", [56, 20, 7, "#fff0b0"], "#b8743a", "#c9a14a"],
	"olaj": ["#8cc4e0", "#f3e2b4", [66, 8, 4, "#fffbe0"], "#d9b877", "#e6c98a"],
}

static var _cache: Dictionary = {}


static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	if not SPEC.has(id):
		return null
	var sp: Array = SPEC[id]
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var top := Color(str(sp[0]))
	var bot := Color(str(sp[1]))
	for y in H:
		var c := top.lerp(bot, pow(float(y) / float(H - 1), 1.3))
		for x in W:
			# rendezett szemcse: festett, nem sima átmenet
			var d := (float((x * 7 + y * 13) % 5) - 2.0) * 0.008
			img.set_pixel(x, y, Color(c.r + d, c.g + d, c.b + d))
	var sun: Array = sp[2]
	if int(sun[2]) > 0:
		_disc(img, int(sun[0]), int(sun[1]), int(sun[2]) + 3, Color(Color(str(sun[3])), 0.22))
		_disc(img, int(sun[0]), int(sun[1]), int(sun[2]), Color(str(sun[3])))
	var far := Color(str(sp[3]))
	var near := Color(str(sp[4]))
	match id:
		"europa":
			_hills(img, far, 22.0, 3.0, 0.11, 0.6, 1.5, 0.31)
			_hills(img, near, 29.0, 2.5, 0.08, 2.1, 1.2, 0.23)
			for t in [[8, 27], [14, 29], [21, 28], [70, 30], [76, 29]]:
				_pine(img, int(t[0]), int(t[1]), Color("#24543a"))
			_turbine(img, 44, 27)
			_turbine(img, 54, 28)
		"usa":
			_butte(img, 40, 30, 16, 13, far)
			_butte(img, 62, 30, 9, 9, far.darkened(0.12))
			_butte(img, 74, 30, 7, 6, far.darkened(0.2))
			_hills(img, near, 30.0, 1.2, 0.07, 0.4, 0.8, 0.19)
			for x in [6, 15, 27, 52, 69]:
				_tuft(img, int(x), 34, Color("#8a7a3c"))
		"kina":
			for k in [[10, 12, 5], [22, 8, 6], [36, 14, 5], [50, 7, 7], [66, 12, 6], [78, 15, 5]]:
				_peak(img, int(k[0]), int(k[1]), int(k[2]), far.lerp(Color("#dfe6d0"), 0.25))
			for k in [[16, 17, 6], [44, 15, 7], [72, 18, 6]]:
				_peak(img, int(k[0]), int(k[1]), int(k[2]), far.darkened(0.12))
			_hills(img, near, 30.0, 2.0, 0.09, 1.0, 1.0, 0.27)
			for y in [33, 36, 39]:                    # teraszos földek világosabb sávjai
				for x in W:
					if img.get_pixel(x, y).is_equal_approx(near) and (x + y) % 3 != 0:
						img.set_pixel(x, y, near.lightened(0.18))
		"india":
			for c in [[12, 6, 9], [26, 4, 8], [40, 7, 10], [58, 5, 9], [72, 7, 8]]:
				_disc(img, int(c[0]), int(c[1]), int(c[2]) - 3, Color("#7d8fa0"))
				_disc(img, int(c[0]) + 4, int(c[1]) + 2, int(c[2]) - 4, Color("#93a3b0"))
			for i in 26:                             # ferde esőcsíkok
				var x0 := (i * 17) % W
				var y0 := 10 + (i * 5) % 14
				for k in 3:
					_px(img, x0 - k, y0 + k * 2, Color(0.85, 0.9, 0.95, 0.5))
			_hills(img, far, 26.0, 1.5, 0.09, 0.2, 1.0, 0.21)
			_hills(img, near, 31.0, 1.2, 0.12, 1.4, 0.6, 0.33)
			_palm(img, 66, 30)
			_palm(img, 16, 31)
		"afrika":
			_hills(img, far, 27.0, 1.2, 0.06, 0.9, 0.7, 0.17)
			_hills(img, near, 31.0, 0.9, 0.10, 0.3, 0.5, 0.29)
			_acacia(img, 24, 31, 1.0)
			_acacia(img, 70, 30, 0.7)
			for x in [6, 38, 47, 58, 80]:
				_tuft(img, int(x), 35, Color("#8f6a2a"))
		"olaj":
			for y in range(21, 25):                  # tengercsík a látóhatáron
				for x in range(0, 40):
					img.set_pixel(x, y, Color("#3f8fb0").lerp(Color("#8cc4e0"), 0.25 if (x + y) % 4 == 0 else 0.0))
			_hills(img, far, 25.0, 2.6, 0.07, 2.6, 1.0, 0.16)
			_hills(img, near, 31.0, 2.8, 0.06, 0.2, 1.2, 0.14)
			for x in W:                               # a dűnék árnyékos oldala
				for y in range(26, H):
					if img.get_pixel(x, y).is_equal_approx(near) and sin(float(x) * 0.06 + 0.2 + float(y) * 0.12) > 0.55:
						img.set_pixel(x, y, near.darkened(0.14))
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	return tex


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < W and y >= 0 and y < H:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(c, 1.0), c.a))


static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				_px(img, x, y, c)


## Dombsor: az alapvonal fölött két szinuszhullám összege; alatta kitöltve.
static func _hills(img: Image, c: Color, base: float, amp: float, f: float, ph: float, amp2: float, f2: float) -> void:
	for x in W:
		var top := int(round(base - amp * sin(float(x) * f + ph) - amp2 * sin(float(x) * f2 + ph * 2.3)))
		for y in range(maxi(top, 0), H):
			var shade := c.darkened(0.10 * float(y - top) / float(H)) if y > top else c.lightened(0.14)
			img.set_pixel(x, y, shade)


static func _pine(img: Image, x: int, y: int, c: Color) -> void:
	for k in 6:
		for dx in range(-(k / 2) - (1 if k % 2 == 1 else 0), (k / 2) + 1):
			_px(img, x + dx, y - 6 + k, c)
	_px(img, x, y, Color("#4a3524"))


static func _turbine(img: Image, x: int, y: int) -> void:
	var c := Color("#f2f4f8")
	for k in 9:
		_px(img, x, y - k, c)
	for k in range(1, 4):
		_px(img, x - k, y - 9 - k, c)
		_px(img, x + k, y - 9 - k / 2, c)
		_px(img, x, y - 9 + k, Color(c, 0.0))
	_px(img, x + 1, y - 8, c)
	_px(img, x + 2, y - 7, c)


static func _butte(img: Image, cx: int, base: int, half: int, h: int, c: Color) -> void:
	for k in h + 1:
		var w := half + (2 if k < 3 else 0) - (1 if k > h - 2 else 0)
		for x in range(cx - w, cx + w + 1):
			var col := c.lightened(0.16) if k == h else (c.darkened(0.12) if (x + k) % 5 == 0 else c)
			_px(img, x, base - k, col)


static func _peak(img: Image, cx: int, top: int, half: int, c: Color) -> void:
	for y in range(top, H):
		var t := float(y - top)
		var w := int(round(float(half) * (1.0 - exp(-t / 3.5)) + t * 0.08))
		for x in range(cx - w, cx + w + 1):
			_px(img, x, y, c.lightened(0.10) if x < cx - w / 2 else c)


static func _palm(img: Image, x: int, y: int) -> void:
	var trunk := Color("#5a4630")
	for k in 8:
		_px(img, x + (1 if k > 4 else 0), y - k, trunk)
	var leaf := Color("#2f6a3c")
	for k in range(1, 5):
		_px(img, x + 1 - k, y - 8 + k / 2, leaf)
		_px(img, x + 1 + k, y - 8 + k / 2, leaf)
		_px(img, x + 1 - k, y - 9 - (0 if k > 2 else 1), leaf)
		_px(img, x + 1 + k, y - 9 - (0 if k > 2 else 1), leaf)
	_px(img, x + 1, y - 9, leaf)


static func _acacia(img: Image, x: int, y: int, s: float) -> void:
	var trunk := Color("#4a3320")
	var h := int(round(9.0 * s))
	for k in h:
		_px(img, x, y - k, trunk)
	_px(img, x - 1, y - h + 2, trunk)
	_px(img, x - 2, y - h + 1, trunk)
	_px(img, x + 1, y - h + 2, trunk)
	_px(img, x + 2, y - h + 1, trunk)
	var crown := Color("#3f5a2a")
	var rw := int(round(8.0 * s))
	for dy in range(-2, 1):
		var w := rw - (3 if dy == -2 else (1 if dy == 0 else 0))
		for dx in range(-w, w + 1):
			_px(img, x + dx, y - h + dy, crown.lightened(0.12) if dy == -2 else crown)


static func _tuft(img: Image, x: int, y: int, c: Color) -> void:
	_px(img, x, y, c)
	_px(img, x - 1, y - 1, c)
	_px(img, x + 1, y - 1, c)
	_px(img, x, y - 2, c)


## A tájkép a felületre: éles képpontokkal, a kért szélességben (a magasság arányos).
static func rect(id: String, width: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture(id)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(width, round(float(width) * float(H) / float(W)))
	t.size = t.custom_minimum_size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
