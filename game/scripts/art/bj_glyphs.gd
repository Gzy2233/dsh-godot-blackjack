class_name BjGlyphs
extends RefCounted

## 牌面字模与整张牌的合成。
##
## 字模逐字移植自 dsh-deepseek-blackjack/src/client/pixelfont.js：
## 5×7 点数、7×7 小花色、16×16 大花色。**这些位图是手写调过的，
## 不要"顺手优化"** —— 比如'10'必须是一个 7 列的整体字模，
## 拼 '1'+'0' 会变成 11 列、撑破角标挤到中央花色（原版踩过这个坑）。

const CARD_W := 46
const CARD_H := 56
const BORDER := 2

## 牌面墨色：**整副牌只有一个色号**。
##
## 色值是直接从用户给的鲸鱼牌面里取的主体色（四门都是这个深藏青），
## 所以角标与中央花色看起来是同一种墨 —— 不再按花色分红/黑两色。
const INK := Color("#061b6e")
const FACE := Color("#f4efe3")
const EDGE := Color("#cfc6b0")
const BACK := Color("#2f4a8c")
const STRIPE := Color("#3f5fa8")
const EMBLEM := Color("#8fb4e8")

## 角标的描边色：用牌面底色。角标压在花色上时靠它保证点数读得出来。
const INDEX_HALO := Color("#f4efe3")

const CHIP_INK := Color("#0f1a14")

## 5×7 点数（'10' 是 7×7 整体字模）。
const RANKS_5x7 := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"2": ["####.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "#...#", "....#", ".###.", "....#", "#...#", "####."],
	"4": ["#...#", "#...#", "#...#", "#####", "....#", "....#", "....#"],
	"5": ["#####", "#....", "#....", "####.", "....#", "....#", "####."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "....#", "...#.", "..#..", "..#..", "..#.."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	"10": [".#..##.", "##.#..#", ".#.#..#", ".#.#..#", ".#.#..#", ".#.#..#", ".#..##."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
}

## 7×7 小花色：靠**底部剪影**两两可分（黑桃收腰+柄、红桃双峰、方块纯菱形、梅花长柄）。
const SUIT_7 := {
	"S": ["...#...", "..###..", ".#####.", "#######", ".#####.", "...#...", "..###.."],
	"H": [".##.##.", "#######", "#######", "#######", ".#####.", "..###..", "...#..."],
	"D": ["...#...", "..###..", ".#####.", "#######", ".#####.", "..###..", "...#..."],
	"C": [".##.##.", "#######", "#######", "..###..", "...#...", "...#...", "..###.."],
}

## 16×16 大花色（牌面中央）。
const SUIT_16 := {
	"S": [
		".......##.......", ".......##.......", "......####......", "......####......",
		".....######.....", ".....######.....", "....########....", "...##########...",
		"..############..", ".##############.", "################", "################",
		"......####......", ".....######.....", ".....######.....", "......####......",
	],
	"H": [
		"...####..####...", "..######.#####..", ".##############.", "################",
		"################", "################", "################", ".##############.",
		".##############.", "..############..", "...##########...", "....########....",
		".....######.....", "......####......", ".......##.......", "................",
	],
	"D": [
		".......##.......", "......####......", "......####......", ".....######.....",
		"....########....", "....########....", "...##########...", "..############..",
		"..############..", "...##########...", "....########....", "....########....",
		".....######.....", "......####......", "......####......", ".......##.......",
	],
	"C": [
		".....####.......", "...########.....", "..##########....", ".############...",
		".############...", "####......####..", "###........###..", "###.........###.",
		"###.........###.", "###........###..", "####......####..", ".############...",
		".############...", "..##########....", "...########.....", ".....####.......",
	],
}

## 角标锚点（原版 card.js 的常量，逐一对齐）。
const IDX_X := 3
const IDX_Y := 3
const IDX_SUIT_TOP := 11
const BIG_LEFT := 15
const BIG_TOP := 20

## 中央装饰花色的位置与尺寸：
## 用户给的鲸鱼牌面（72×56 的格）按 0.58 倍缩到 42×32，
## 再**贴着牌面可视中心**放 —— 42 宽正好等于内框宽度（2..43），
## 32 高居中在 56 高的牌上（12..43，中心 27.5 ≈ 牌面中心 28）。
##
## 位置是调过的：原版放在 (2,18) 会让图案整体偏低约 4~6 像素，
## 因为它的流水线把每格内容**底对齐**（矮的花色坐得更低）。
const PIP_LEFT := 2
const PIP_TOP := 12
const PIP_W := 42
const PIP_H := 32

## 王冠标记（J/Q/K 才有），锚点与每张的 2×2 点阵。
const CROWN_X := 27
const CROWN_Y := 17
const CROWNS := {
	"J": [Vector2i(2, 1)],
	"Q": [Vector2i(-1, 1), Vector2i(2, -1), Vector2i(5, 1)],
	"K": [Vector2i(-3, 1), Vector2i(-1, -2), Vector2i(2, -3), Vector2i(5, -2), Vector2i(7, 1)],
}

static var _face_cache: Dictionary = {}
static var _back_texture: ImageTexture = null
static var _chip_cache: Dictionary = {}


## 花色 → 墨色。**四门同色**：用户给的鲸鱼牌面是统一深藏青，
## 角标再分红/黑就变成"一副牌两种风格"了。
static func suit_color(_suit: String) -> Color:
	return INK


## 画一张牌面。rank 传空串得到牌背。
static func card_image(rank: String, suit: String) -> Image:
	var image := BjPixel.make_image(CARD_W, CARD_H)
	if rank == "" or not RANKS_5x7.has(rank):
		_draw_back(image)
		return image

	BjPixel.fill(image, 0, 0, CARD_W, CARD_H, FACE)
	BjPixel.frame(image, 0, 0, CARD_W, CARD_H, BORDER, EDGE)

	var rank_rows: Array = RANKS_5x7[rank]

	# 中央花色**先画**：优先用用户提供的鲸鱼牌面（缩到 42×32 贴进来），
	# 素材缺失时回落到程序化的 16×16 字模。
	# 顺序很重要：它横跨整张牌，会和**右下角标**在 x37..43 / y39..49 重叠，
	# 让角标压在它上面，点数才永远读得出来。
	var pip := BjPips.cell_image(rank, suit)
	if pip != null:
		BjPixel.blit_image(image, pip, Vector2i(PIP_LEFT, PIP_TOP))
	else:
		BjPixel.blit_grid(image, SUIT_16[suit], Vector2i(BIG_LEFT, BIG_TOP), INK)

	# 左上角标：点数 + 小花色（带一圈牌面底色的描边，压在花色上也读得出来）
	# （小花色永远从 IDX_X 起画：5 列与 7 列字模的居中偏移都是 0，
	#   原版那个 max(0, floor((rankW-7)/2)) 在这里恒为 0）
	BjPixel.blit_grid_outlined(image, rank_rows, Vector2i(IDX_X, IDX_Y), INK, INDEX_HALO)
	BjPixel.blit_grid_outlined(image, SUIT_7[suit], Vector2i(IDX_X, IDX_SUIT_TOP), INK, INDEX_HALO)

	# 右下角标：把同一组**旋转 180°**，比手写第二套字模可靠得多
	var pivot := Vector2i(CARD_W, CARD_H)
	BjPixel.blit_grid_outlined_rot180(image, rank_rows, Vector2i(IDX_X, IDX_Y), INK, INDEX_HALO, pivot)
	BjPixel.blit_grid_outlined_rot180(image, SUIT_7[suit], Vector2i(IDX_X, IDX_SUIT_TOP), INK, INDEX_HALO, pivot)

	# 花牌的王冠（画在花色之上，用来区分 J/Q/K）——同样两遍：先铺底再压墨
	if CROWNS.has(rank):
		for mark: Vector2i in CROWNS[rank]:
			BjPixel.fill(image, CROWN_X + mark.x - 1, CROWN_Y + mark.y - 1, 4, 4, INDEX_HALO)
		for mark: Vector2i in CROWNS[rank]:
			BjPixel.fill(image, CROWN_X + mark.x, CROWN_Y + mark.y, 2, 2, INK)

	return image


static func _draw_back(image: Image) -> void:
	BjPixel.fill(image, 0, 0, CARD_W, CARD_H, EDGE)
	BjPixel.fill(image, BORDER, BORDER, CARD_W - BORDER * 2, CARD_H - BORDER * 2, BACK)

	# 斜纹：每行错开 1 像素，形成 45° 的点阵
	for y in range(BORDER, CARD_H - BORDER):
		var offset: int = y % 4
		var x := BORDER + offset
		while x < CARD_W - BORDER:
			image.set_pixel(x, y, STRIPE)
			x += 4

	# 只描边的菱形徽记（描边是为了让斜纹还看得见 —— 原版刻意的选择）
	var cx := 23
	var cy := 28
	var radius := 9
	for dy in range(-radius, radius + 1):
		var half: int = radius - absi(dy)
		image.set_pixel(cx - half, cy + dy, EMBLEM)
		image.set_pixel(cx + half - 1, cy + dy, EMBLEM)
	for dx in range(-radius, radius + 1):
		var half: int = radius - absi(dx)
		image.set_pixel(cx + dx, cy - half, EMBLEM)
		image.set_pixel(cx + dx, cy + half - 1, EMBLEM)
	BjPixel.fill(image, 21, 26, 4, 4, EMBLEM)
	BjPixel.fill(image, 22, 27, 2, 2, BACK)


## 牌面纹理（按 rank+suit 缓存，52 张只生成一次）。
## 注意：**null 不进缓存** —— 否则一次失败会把这张牌永久钉成空纹理。
static func face_texture(rank: String, suit: String) -> ImageTexture:
	var key := "%s%s" % [suit, rank]
	if _face_cache.has(key):
		var cached: ImageTexture = _face_cache[key]
		if cached != null:
			return cached
	var texture := BjPixel.texture_of(card_image(rank, suit))
	if texture != null:
		_face_cache[key] = texture
	return texture


static func back_texture() -> ImageTexture:
	if _back_texture == null:
		_back_texture = BjPixel.texture_of(card_image("", ""))
	return _back_texture


## 筹码圆片：16×16 像素，边缘一圈间隔色点（赌场筹码的样子）。
## 原版**完全没有筹码图形**，只有文字和按钮 —— 这是移植时补的美术。
static func chip_texture(body: Color, rim: Color) -> ImageTexture:
	var key := "%s|%s" % [body.to_html(false), rim.to_html(false)]
	if _chip_cache.has(key):
		return _chip_cache[key]
	var size := 16
	var image := BjPixel.make_image(size, size)
	var center := Vector2(size / 2.0 - 0.5, size / 2.0 - 0.5)
	var light := body.lightened(0.25)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(center)
			if d > 7.6:
				continue
			if d > 6.0:
				# 边缘：交替的间隔点
				var angle := atan2(y - center.y, x - center.x) + PI
				var slice := int(angle / (TAU / 12.0))
				image.set_pixel(x, y, body if slice % 2 == 0 else rim)
			elif d > 5.0:
				image.set_pixel(x, y, rim)
			else:
				# 左上有 1 像素高光，看起来才像塑料片
				image.set_pixel(x, y, light if (x + y) < size - 4 else body)
	var texture := BjPixel.texture_of(image)
	_chip_cache[key] = texture
	return texture
