extends RefCounted
## A témakörök kis, kódból rajzolt képjele (12×12 képpont). Saját rajz, nem átvett kép.

const GRID := {
	"aram": [
		"......##....", ".....##.....", "....##......", "...###......", "..######....", ".....###....",
		".....##.....", "....##......", "...##.......", "..##........", "..#.........", "............"],
	"munka": [
		"............", ".........#..", ".........#..", ".#..#..#.#..", ".##.##.###..", ".#########..",
		".#########..", ".#.#.#.#.#..", ".#########..", ".#.#.#.#.#..", ".#########..", "............"],
	"elelem": [
		".....#......", "....###.....", ".....#......", "...#.#.#....", "..##.#.##...", "...#.#.#....",
		"..##.#.##...", "...#.#.#....", ".....#......", ".....#......", ".....#......", "............"],
	"part": [
		"............", "............", "..#.....#...", ".#.#...#.#..", "#...#.#...#.", ".....#......",
		"..#.....#...", ".#.#...#.#..", "#...#.#...#.", ".....#......", "............", "............"],
	"egeszseg": [
		"............", "..##...##...", ".####.####..", ".#########..", ".#########..", ".#########..",
		"..#######...", "...#####....", "....###.....", ".....#......", "............", "............"],
	"ketseg": [
		"............", "...####.....", "..##..##....", "......##....", ".....##.....", "....##......",
		"....##......", "............", "....##......", "....##......", "............", "............"],
	"olaj": [
		".....#......", ".....#......", "....###.....", "....###.....", "...#####....", "..#######...",
		"..#######...", "..#######...", "..#######...", "...#####....", "....###.....", "............"],
	"erdo": [
		".....#......", "....###.....", "...#####....", "....###.....", "...#####....", "..#######...",
		"...#####....", "..#######...", ".#########..", ".....#......", ".....#......", "............"],
	"kockazat": [
		"............", ".....##.....", ".....##.....", "....####....", "....#..#....", "...##..##...",
		"...##..##...", "..###..###..", "..########..", ".####..####.", ".##########.", "............"],
}

static var _cache: Dictionary = {}


static func texture(theme: String, color: Color) -> Texture2D:
	var key := theme + color.to_html()
	if _cache.has(key):
		return _cache[key]
	if not GRID.has(theme):
		return null
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rows: Array = GRID[theme]
	for y in 12:
		for x in 12:
			if str(rows[y])[x] == "#":
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Képjel a felületre: éles képpontokkal, a kért méretben.
static func rect(theme: String, color: Color, px: int = 36) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture(theme, color)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(px, px)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
