class_name BjPips
extends RefCounted

## 用户提供的鲸鱼牌面 → 牌中央的装饰花色。
##
## 素材是四张 928×64 的图（picture/whale_pips_*.png）：**洋红背景**、
## 一行 13 格 = A,2..10,J,Q,K，每格的鲸鱼花色带不同的装饰强度
## （描边框、斜纹、绶带、菱形/圆环轮廓、尖刺……）。
##
## 这里用 GDScript 重做了原版 tools/prepare-cards.py 的整条流水线，
## **一步都没省**，因为它每一步都在解决一个真实的坑：
##
##   1. **抠洋红**用距离阈值而不是精确相等 —— 否则会留下一圈洋红描边。
##      阈值与原版一致（RGB 欧氏距离 ≤ 90）。
##   2. **等宽切 13 格再取格内包围盒**，而不是按"空白列"切 ——
##      实测格子间距不均（69~78px），红桃那行按空白切会切出 14 段。
##   3. **内容居中 + 底对齐（留 2px）** —— 花色底部都是尖角，底对齐看着最稳，
##      而且 13 格高度不一时不会上下跳。
##   4. 输出 4 行 × 13 列的图集（行序 S,H,D,C），格 72×56。
##
## 牌面合成时把它缩到 42×32 贴在 (2,18) —— 也就是原版的 0.58 倍最近邻缩放，
## 角标那部分仍然是**程序化**的（AI 画的角标一定是歪的，这是原版就定下的分工）。

const SOURCE_DIR := "res://assets/pips/"
const ROWS := 4
const COLS := 13
const CELL_W := 72
const CELL_H := 56
const PAD_BOTTOM := 2

## 与原版 prepare-cards.py 完全一致的抠图参数。
const MAGENTA := Color(1, 0, 1)
const TOL := 90.0

## 小于这个像素数的连通块会被当作碎点清掉（见 _despeckle）。
## 取 5：素材里那些 2~3 像素的"点缀小点"缩完会变成 2~4 像素的孤块，
## 必须在牌面上清干净（那正是用户说的"奇怪的点"）。
const MIN_SPECK_AREA := 5

## 行序 / 列序：与图集约定一致，不许改。
const ROW_SUITS: Array[String] = ["S", "H", "D", "C"]
const COL_RANKS: Array[String] = [
	"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K",
]

const SOURCE_FILES := {
	"S": "whale_pips_spades_13.png",
	"H": "whale_pips_hearts_13.png",
	"D": "whale_pips_diamonds_13.png",
	"C": "whale_pips_clubs_13.png",
}

static var _sheet_image: Image = null
static var _sheet_texture: ImageTexture = null
static var _scaled_cells: Dictionary = {}
static var _status := ""


## 素材是否可用（缺文件时整套牌回落到程序化花色字模）。
static func available() -> bool:
	for suit in SOURCE_FILES.keys():
		if not ResourceLoader.exists(SOURCE_DIR + str(SOURCE_FILES[suit])):
			return false
	return true


static func status() -> String:
	sheet_image()
	return _status


## 4 行 × 13 列 的图集（936×224）。只构建一次。
static func sheet_image() -> Image:
	if _sheet_image != null:
		return _sheet_image
	if not available():
		_status = "缺少 whale_pips_*.png，中央花色回落到程序化字模"
		return null
	var sheet := BjPixel.make_image(CELL_W * COLS, CELL_H * ROWS)
	var cell_count := 0
	for row in range(ROWS):
		var suit: String = ROW_SUITS[row]
		var source := _load_keyed(str(SOURCE_FILES[suit]))
		if source == null:
			_status = "读不出 %s" % str(SOURCE_FILES[suit])
			return null
		var band := float(source.get_width()) / float(COLS)
		for col in range(COLS):
			# 原版就是 round(col*band) .. round((col+1)*band)-1
			var x0 := int(round(float(col) * band))
			var x1 := int(round(float(col + 1) * band)) - 1
			var box := _content_box(source, x0, x1)
			if box.size.x <= 0 or box.size.y <= 0:
				continue
			var content := source.get_region(box)
			# 格内容超框就直接跳过这一格（原版是报错退出，这里不让整副牌开天窗）
			if content.get_width() > CELL_W or content.get_height() > CELL_H:
				continue
			# **垂直居中**（原版是底对齐）。
			# 底对齐是为了一整行图集看起来齐脚，但每张牌只显示一格 ——
			# 底对齐会让"矮一点"的花色在牌面上越坐越低，13 张牌高度还各不相同。
			var dx := int((CELL_W - content.get_width()) / 2.0)
			var dy := int((CELL_H - content.get_height()) / 2.0)
			sheet.blit_rect(content, Rect2i(Vector2i.ZERO, content.get_size()),
				Vector2i(col * CELL_W + dx, row * CELL_H + dy))
			cell_count += 1
	if cell_count == 0:
		_status = "13 格全都切不出内容"
		return null
	_sheet_image = sheet
	_status = "已用上你的鲸鱼牌面（%d 格）" % cell_count
	return _sheet_image


static func sheet_texture() -> ImageTexture:
	if _sheet_texture == null:
		var image := sheet_image()
		if image == null:
			return null
		_sheet_texture = BjPixel.texture_of(image)
	return _sheet_texture


## 某张牌中央那一小块（已按 0.58 倍最近邻缩到 42×32），可直接贴到牌面上。
static func cell_image(rank: String, suit: String) -> Image:
	var col := COL_RANKS.find(rank)
	var row := ROW_SUITS.find(suit)
	if col < 0 or row < 0:
		return null
	var key := "%d_%d" % [row, col]
	if _scaled_cells.has(key):
		return _scaled_cells[key]
	var sheet := sheet_image()
	if sheet == null:
		return null
	var region := sheet.get_region(Rect2i(col * CELL_W, row * CELL_H, CELL_W, CELL_H))
	# 缩到 42×32（原版 SVG 里那个 0.58 倍）
	region = _downscale_cover(region, BjGlyphs.PIP_W, BjGlyphs.PIP_H)
	# 缩完之后再清碎点
	_despeckle(region, MIN_SPECK_AREA)
	_scaled_cells[key] = region
	return region


# ---------------------------------------------------------------- 内部

## 覆盖率降采样：目标像素对应的源块里**只要有实心像素，目标像素就实心**。
##
## 为什么不能用 `Image.resize(..., INTERPOLATE_NEAREST)`：
## 72→42 是 0.583 倍，最近邻只是在源图上每隔 ~1.7 像素取一个点。
## 于是**1 像素宽的装饰线**（描边框、绶带、卷角）会被采样成断续的虚线，
## 甚至整条消失 —— 牌面上就只剩几根悬空的横线，看起来像画错了。
## 用覆盖率取"这块里有没有东西"，细线就能完整保留下来。
static func _downscale_cover(source: Image, target_w: int, target_h: int) -> Image:
	var out := BjPixel.make_image(target_w, target_h)
	var src_w := source.get_width()
	var src_h := source.get_height()
	for ty in range(target_h):
		var y0 := int(floor(float(ty) * float(src_h) / float(target_h)))
		var y1 := int(ceil(float(ty + 1) * float(src_h) / float(target_h)))
		for tx in range(target_w):
			var x0 := int(floor(float(tx) * float(src_w) / float(target_w)))
			var x1 := int(ceil(float(tx + 1) * float(src_w) / float(target_w)))
			var counts := {}
			for sy in range(y0, mini(y1, src_h)):
				for sx in range(x0, mini(x1, src_w)):
					var color := source.get_pixel(sx, sy)
					if color.a <= 0.5:
						continue
					var key := color.to_html(true)
					if counts.has(key):
						counts[key]["count"] = int(counts[key]["count"]) + 1
					else:
						counts[key] = {"count": 1, "color": color}
			if counts.is_empty():
				continue
			# 取这块里出现最多的实心颜色
			var best_count := -1
			var best_color := Color(0, 0, 0, 1)
			for key in counts.keys():
				if int(counts[key]["count"]) > best_count:
					best_count = int(counts[key]["count"])
					best_color = counts[key]["color"]
			out.set_pixel(tx, ty, best_color)
	return out


## 清掉孤立的小碎点。
##
## 为什么需要它：花色边缘和洋红背景之间有**抗锯齿的过渡像素**（深紫），
## 它们离洋红够远、抠图阈值放不掉；0.58 倍最近邻缩小时这些过渡像素会被采样成
## **孤立的紫点**散在牌面上（用户原话："一些牌面会有奇怪的点"）。
## 这里对缩完的小图做一次连通块过滤：小于 MIN_SPECK_AREA 的直接抹掉。
static func _despeckle(image: Image, min_area: int) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var visited := {}
	for y in range(height):
		for x in range(width):
			var start_key := y * width + x
			if visited.has(start_key):
				continue
			visited[start_key] = true
			if image.get_pixel(x, y).a <= 0.5:
				continue
			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			while not queue.is_empty():
				var point: Vector2i = queue.pop_back()
				component.append(point)
				for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					# 显式标注类型：`offset` 从数组里取出来是 Variant，用 := 推断会直接解析失败
					var next: Vector2i = point + offset
					if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
						continue
					var next_key := next.y * width + next.x
					if visited.has(next_key):
						continue
					visited[next_key] = true
					if image.get_pixel(next.x, next.y).a <= 0.5:
						continue
					queue.append(next)
			if component.size() < min_area:
				for point in component:
					image.set_pixel(point.x, point.y, Color(0, 0, 0, 0))


## 读一张源图并抠掉洋红。读不出来返回 null。
static func _load_keyed(file_name: String) -> Image:
	var path := SOURCE_DIR + file_name
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	image = image.duplicate()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	# 距离阈值抠图：精确相等会留下一圈洋红描边
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a <= 0.01:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var dr := color.r - MAGENTA.r
			var dg := color.g - MAGENTA.g
			var db := color.b - MAGENTA.b
			var distance := sqrt(dr * dr + dg * dg + db * db) * 255.0
			if distance <= TOL:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image


## 一格内的内容包围盒（全部透明则返回空矩形）。
static func _content_box(image: Image, x0: int, x1: int) -> Rect2i:
	var min_x := -1
	var min_y := -1
	var max_x := -1
	var max_y := -1
	var left: int = clampi(x0, 0, image.get_width() - 1)
	var right: int = clampi(x1, 0, image.get_width() - 1)
	for y in range(image.get_height()):
		for x in range(left, right + 1):
			if image.get_pixel(x, y).a <= 0.01:
				continue
			if min_x == -1:
				min_x = x
				min_y = y
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if min_x == -1:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
