class_name BjPixel
extends RefCounted

## 像素画底层工具：字符网格 → Image。
##
## 移植自 dsh-deepseek-blackjack/src/client/pixel.js 的思路：
## "像素就是代码里的一个字符"。好处是画得准（不存在 AI 出图那种
## 角标歪斜、描边不一致），而且每个字形都能被单元测试断言。
##
## 与 JS 版的区别：那边输出 SVG `<rect>` 串（浏览器才能显示），
## 这里直接烤成 Image + ImageTexture，配合 nearest 过滤做整数倍放大。
## 内存里按 (宽,高) 缓存，一副牌的 52 张面 + 1 张背只生成一次。


## 网格里的透明字符：'.' 与空格。
## 注意不能用 `TRANSPARENT.contains(ch)` 判断 —— ".# ".contains("#") 也是 true，
## 那会把所有实心像素都当透明跳过（牌面直接变空白，踩过一次）。
static func is_transparent(ch: String) -> bool:
	return ch == "." or ch == " "


## 生成一张全透明的图。
static func make_image(width: int, height: int) -> Image:
	return Image.create_empty(width, height, false, Image.FORMAT_RGBA8)


## 把字符网格贴到图上。`rows` 每行等长；透明字符与调色板里没有的字符跳过。
static func blit_grid(image: Image, rows: Array, origin: Vector2i, color: Color) -> void:
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if is_transparent(row[x]):
				continue
			var px := origin.x + x
			var py := origin.y + y
			if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
				continue
			image.set_pixel(px, py, color)


## 带 1 像素描边的字形：先铺一圈描边，再把字形压上去。
##
## 用途：角标要压在中央花色之上，而整副牌统一墨色之后两者**颜色一样** ——
## 没有这圈牌面底色的描边，角标会和花色糊成一片（实物扑克也是给角标留白的）。
static func blit_grid_outlined(image: Image, rows: Array, origin: Vector2i, color: Color,
		outline: Color) -> void:
	_blit_grid_with_halo(image, rows, origin, color, outline, Vector2i.ZERO)


static func blit_grid_outlined_rot180(image: Image, rows: Array, origin: Vector2i, color: Color,
		outline: Color, pivot_twice: Vector2i) -> void:
	_blit_grid_with_halo(image, rows, origin, color, outline, pivot_twice)


static func _blit_grid_with_halo(image: Image, rows: Array, origin: Vector2i, color: Color,
		outline: Color, pivot_twice: Vector2i) -> void:
	var points: Array[Vector2i] = []
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if is_transparent(row[x]):
				continue
			var point := origin + Vector2i(x, y)
			if pivot_twice != Vector2i.ZERO:
				point = pivot_twice - point
			points.append(point)
	# 第一遍：描边（八邻域，斜角也补，像素风更干净）
	var offsets := [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	for point in points:
		for offset in offsets:
			var target: Vector2i = point + offset
			_put_pixel(image, target, outline)
	# 第二遍：字形本身
	for point in points:
		_put_pixel(image, point, color)


static func _put_pixel(image: Image, point: Vector2i, color: Color) -> void:
	if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
		return
	image.set_pixel(point.x, point.y, color)


## 把字符网格**旋转 180°**后贴上去。
## 牌面的右下角标就是这么来的：转一次比手写第二套字模可靠得多。
## pivot_twice 是旋转中心的两倍坐标（卡片 46×56 对应 (46, 56)）。
static func blit_grid_rot180(image: Image, rows: Array, origin: Vector2i, color: Color,
		pivot_twice: Vector2i) -> void:
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if is_transparent(row[x]):
				continue
			var px := pivot_twice.x - (origin.x + x)
			var py := pivot_twice.y - (origin.y + y)
			if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
				continue
			image.set_pixel(px, py, color)


## 实心矩形（带边界裁剪）。
static func fill(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var rect := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	image.fill_rect(rect, color)


## 只画空心框（2px 牌边用）。
static func frame(image: Image, x: int, y: int, w: int, h: int, thickness: int, color: Color) -> void:
	fill(image, x, y, w, thickness, color)
	fill(image, x, y + h - thickness, w, thickness, color)
	fill(image, x, y, thickness, h, color)
	fill(image, x + w - thickness, y, thickness, h, color)


## 把一张图（带透明）贴到另一张上。透明像素跳过，其余按 alpha 覆盖。
static func blit_image(dst: Image, src: Image, origin: Vector2i) -> void:
	for y in range(src.get_height()):
		for x in range(src.get_width()):
			var color := src.get_pixel(x, y)
			if color.a <= 0.01:
				continue
			var px := origin.x + x
			var py := origin.y + y
			if px < 0 or py < 0 or px >= dst.get_width() or py >= dst.get_height():
				continue
			dst.set_pixel(px, py, color)


## 整数倍放大（像素画**永远不做非整数缩放**，否则会糊）。
static func upscale(image: Image, factor: int) -> Image:
	if factor <= 1:
		return image
	var out := make_image(image.get_width() * factor, image.get_height() * factor)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			out.fill_rect(Rect2i(x * factor, y * factor, factor, factor), color)
	return out


static func texture_of(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)


## 把 `natural` 尺寸的图按整数倍塞进 `available`（最大 8 倍）。
## 这就是"永远整数缩放"这条规则的实现。
static func best_integer_scale(natural: float, available: float, max_scale: int = 8) -> int:
	if natural <= 0.0:
		return 1
	return clampi(int(floor(available / natural)), 1, max_scale)
