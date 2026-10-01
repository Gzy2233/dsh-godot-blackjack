@tool
class_name BjTestArt
extends McpTestSuite

## 像素美术的几何自检。
##
## 原版有一份 dev/geometry-check.mjs（137 条断言）专门锁这些不变量 ——
## 因为牌面是**代码画出来的**，一个字符写错就会静默画出一张残牌
## （我就踩过 `".# ".contains("#")` 这个坑，整张牌面变空白）。
## 所以这里逐个像素地验。


func suite_name() -> String:
	return "art"


func _is_ink(color: Color) -> bool:
	return color.is_equal_approx(BjGlyphs.INK)


func _ink_count(image: Image, x: int, y: int, w: int, h: int) -> int:
	var count := 0
	for py in range(y, mini(y + h, image.get_height())):
		for px in range(x, mini(x + w, image.get_width())):
			if _is_ink(image.get_pixel(px, py)):
				count += 1
	return count


func test_every_glyph_row_is_a_rectangle() -> void:
	for rank in BjGlyphs.RANKS_5x7.keys():
		var rows: Array = BjGlyphs.RANKS_5x7[rank]
		assert_eq(rows.size(), 7, "%s 必须是 7 行" % rank)
		var width: int = rows[0].length()
		for row in rows:
			assert_eq(row.length(), width, "%s 的每一行必须等长" % rank)
	# '10' 是唯一的两位数字模：7 列整体设计，不能拼 '1'+'0'（那样 11 列会撑破角标）
	assert_eq(BjGlyphs.RANKS_5x7["10"][0].length(), 7)
	assert_eq(BjGlyphs.RANKS_5x7["A"][0].length(), 5)


func test_suit_glyphs_are_pairwise_distinct() -> void:
	var seen: Array = []
	for suit in ["S", "H", "D", "C"]:
		var rows: Array = BjGlyphs.SUIT_7[suit]
		assert_eq(rows.size(), 7)
		var key := "\n".join(rows)
		assert_false(seen.has(key), "花色 %s 的 7×7 字模与其他花色重复了（牌面上会分不出）" % suit)
		seen.append(key)
		assert_eq(BjGlyphs.SUIT_16[suit].size(), 16, "大号花色必须 16 行")


func test_every_card_has_ink_in_corner_and_center() -> void:
	for suit in BjCards.SUITS:
		for rank in BjCards.RANKS:
			var image := BjGlyphs.card_image(rank, suit)
			assert_eq(image.get_width(), BjGlyphs.CARD_W)
			assert_eq(image.get_height(), BjGlyphs.CARD_H)
			var corner := _ink_count(image, 3, 3, 7, 15)
			assert_gt(corner, 8, "%s%s 的角标区没有墨（字模没画上）" % [suit, rank])
			# 中央现在是用户给的鲸鱼牌面，颜色不是角标墨色，所以按"既不是底色也不是边框色"来数
			var center := _colored_count(image, BjGlyphs.PIP_LEFT, BjGlyphs.PIP_TOP,
				BjGlyphs.PIP_W, BjGlyphs.PIP_H)
			assert_gt(center, 30, "%s%s 的中央花色是空的" % [suit, rank])


## 数"既不是牌面底色、也不是边框色"的像素 —— 中央图案（用户素材）就是这么判定的。
func _colored_count(image: Image, x: int, y: int, w: int, h: int) -> int:
	var count := 0
	for py in range(y, mini(y + h, image.get_height())):
		for px in range(x, mini(x + w, image.get_width())):
			var color := image.get_pixel(px, py)
			if color.a <= 0.5:
				continue
			if color.is_equal_approx(BjGlyphs.FACE) or color.is_equal_approx(BjGlyphs.EDGE):
				continue
			count += 1
	return count


func test_pip_cell_is_centred_on_the_card() -> void:
	# 用户提过"感觉图案不在牌面中心" —— 这里把几何关系钉死。
	assert_eq(BjGlyphs.PIP_LEFT + BjGlyphs.PIP_W / 2, BjGlyphs.CARD_W / 2, "中央花色水平不居中")
	assert_eq(BjGlyphs.PIP_TOP + BjGlyphs.PIP_H / 2, BjGlyphs.CARD_H / 2, "中央花色垂直不居中")
	# 而且每一格的图案在格内也要居中（原版底对齐会让矮一点的花色越坐越低）
	var off_centre: Array = []
	for suit in BjPips.ROW_SUITS:
		for rank in BjPips.COL_RANKS:
			var cell := BjPips.cell_image(rank, suit)
			var box := _content_box(cell)
			var centre_y := float(box.position.y) + float(box.size.y) / 2.0
			if absf(centre_y - float(cell.get_height()) / 2.0) > 2.0:
				off_centre.append("%s%s(%.1f)" % [suit, rank, centre_y])
	assert_eq(off_centre.size(), 0, "这些格子的图案在格内没居中：%s" % str(off_centre))


func test_no_stray_dots_in_pip_art() -> void:
	# 用户提过"一些牌面会有奇怪的点" —— 那是花色边缘的抗锯齿过渡像素被 0.58 倍
	# 最近邻采样成孤立紫点的结果。这里逐格扫：**图里不许有孤立点**。
	#
	# 只扫图本身，不扫整张牌：角标字模（K 的衬角、2/7 的笔画）本来就含
	# 有意为之的单像素细节，扫整张牌会把它们误判成碎点。
	var offenders: Array = []
	for suit in BjPips.ROW_SUITS:
		for rank in BjPips.COL_RANKS:
			var cell := BjPips.cell_image(rank, suit)
			if cell == null:
				offenders.append("%s%s=缺失" % [suit, rank])
				continue
			var strays := _isolated_pixels(cell)
			if strays > 0:
				offenders.append("%s%s=%d" % [suit, rank, strays])
	assert_eq(offenders.size(), 0, "花色图案上还有孤立碎点：%s" % str(offenders.slice(0, 12)))


func test_card_pip_window_is_clean() -> void:
	# 贴到牌面上之后再验一遍：牌面中央那个**不含角标**的窗口里也不许有孤立点
	var offenders: Array = []
	for suit in BjCards.SUITS:
		for rank in BjCards.RANKS:
			var image := BjGlyphs.card_image(rank, suit)
			var strays := _isolated_pixels(image, Rect2i(
				BjGlyphs.PIP_LEFT + 8, BjGlyphs.PIP_TOP + 6,
				BjGlyphs.PIP_W - 16, BjGlyphs.PIP_H - 12))
			if strays > 0:
				offenders.append("%s%s=%d" % [suit, rank, strays])
	assert_eq(offenders.size(), 0, "牌面中央还有孤立碎点：%s" % str(offenders.slice(0, 12)))


## 数"四周都是底色/透明"的实心像素。传入 rect 则只扫那块区域。
func _isolated_pixels(image: Image, rect: Rect2i = Rect2i()) -> int:
	var area := rect
	if area.size.x <= 0:
		area = Rect2i(1, 1, image.get_width() - 2, image.get_height() - 2)
	var count := 0
	for y in range(area.position.y, area.position.y + area.size.y):
		for x in range(area.position.x, area.position.x + area.size.x):
			if x < 1 or y < 1 or x >= image.get_width() - 1 or y >= image.get_height() - 1:
				continue
			var color := image.get_pixel(x, y)
			if color.a <= 0.5:
				continue
			if color.is_equal_approx(BjGlyphs.FACE) or color.is_equal_approx(BjGlyphs.EDGE):
				continue
			var surrounded := 0
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var point: Vector2i = offset
				var neighbour := image.get_pixel(x + point.x, y + point.y)
				if neighbour.a <= 0.5:
					surrounded += 1
				elif neighbour.is_equal_approx(BjGlyphs.FACE) or neighbour.is_equal_approx(BjGlyphs.EDGE):
					surrounded += 1
			if surrounded == 4:
				count += 1
	return count


## 内容包围盒（全透明返回空矩形）。
func _content_box(image: Image) -> Rect2i:
	var min_x := -1
	var min_y := -1
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.5:
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


func test_card_center_is_the_provided_art() -> void:
	# 牌面中央必须**逐像素**等于用户素材缩下来的那一块（不是程序化字模）。
	# 只比对**避开两个角标块**的中间窗口：角标是故意压在花色之上的，
	# 见 BjGlyphs.card_image 里的绘制顺序说明。
	var rank := "5"
	var suit := "S"
	var pip := BjPips.cell_image(rank, suit)
	assert_true(pip != null, "取不到 %s%s 的中央花色" % [suit, rank])
	if pip == null:
		return
	assert_eq(pip.get_size(), Vector2i(BjGlyphs.PIP_W, BjGlyphs.PIP_H))
	var card := BjGlyphs.card_image(rank, suit)
	var mismatches := 0
	# 左上角标盖住 card x3..9 / y3..17；右下角标盖住 card x37..43 / y39..53
	for y in range(6, 27):
		for x in range(8, 35):
			var source := pip.get_pixel(x, y)
			var drawn := card.get_pixel(BjGlyphs.PIP_LEFT + x, BjGlyphs.PIP_TOP + y)
			if source.a > 0.5:
				if not drawn.is_equal_approx(source):
					mismatches += 1
			elif not drawn.is_equal_approx(BjGlyphs.FACE):
				mismatches += 1
	assert_eq(mismatches, 0, "中央花色与用户素材不一致（%d 个像素）" % mismatches)


func test_every_suit_uses_the_same_ink() -> void:
	# 用户要求整副牌一个色号：角标不再按花色分红/黑（原版是红桃方块用红、黑桃梅花用墨）。
	# 色值取自鲸鱼牌面的主体色，所以角标和中央花色看起来是同一种墨。
	assert_true(BjGlyphs.suit_color("H").is_equal_approx(BjGlyphs.suit_color("S")),
		"红桃与黑桃的角标墨色不一致")
	assert_true(BjGlyphs.suit_color("D").is_equal_approx(BjGlyphs.suit_color("C")),
		"方块与梅花的角标墨色不一致")
	var old_red := Color("#c8323c")
	for suit in BjCards.SUITS:
		var image := BjGlyphs.card_image("A", suit)
		var red := 0
		var navy := 0
		for y in range(BjGlyphs.CARD_H):
			for x in range(BjGlyphs.CARD_W):
				var color := image.get_pixel(x, y)
				if color.is_equal_approx(old_red):
					red += 1
				elif color.is_equal_approx(BjGlyphs.INK):
					navy += 1
		assert_eq(red, 0, "%s 还残留旧的红角标" % suit)
		assert_gt(navy, 20, "%s 的角标不是统一墨色" % suit)


func test_corner_index_has_a_knockout_halo() -> void:
	# 统一墨色之后，角标压在中央花色上会糊成一片 ——
	# 所以角标必须带 1 像素的牌面底色描边（实物扑克也是给角标留白的）。
	var canvas := BjPixel.make_image(24, 24)
	canvas.fill(BjGlyphs.INK)   # 假装底下是中央花色
	BjPixel.blit_grid_outlined(canvas, BjGlyphs.RANKS_5x7["K"], Vector2i(8, 8),
		BjGlyphs.INK, BjGlyphs.FACE)
	var halo := 0
	for y in range(canvas.get_height()):
		for x in range(canvas.get_width()):
			if canvas.get_pixel(x, y).is_equal_approx(BjGlyphs.FACE):
				halo += 1
	assert_gt(halo, 0, "角标没有描边（压在花色上会看不清）")
	# 描边要真的包住字形：字形包围盒外侧必须是底色
	assert_true(canvas.get_pixel(7, 7).is_equal_approx(BjGlyphs.FACE), "字形左上外角没有描边")
	assert_true(canvas.get_pixel(13, 8).is_equal_approx(BjGlyphs.FACE), "字形右侧没有描边")
	assert_true(canvas.get_pixel(8, 15).is_equal_approx(BjGlyphs.FACE), "字形下方没有描边")


func test_card_faces_have_no_red_ink() -> void:
	# 整副牌不该再出现"红墨"（原版红桃/方块用红角标）。
	# 注意不能断言"只有一个颜色"：花色素材和洋红之间有抗锯齿过渡像素（偏紫），
	# 那些是素材自带的，这里只挡"第二种**花色色**"。
	for suit in BjCards.SUITS:
		for rank in ["A", "5", "K"]:
			var image := BjGlyphs.card_image(rank, suit)
			var reddish := 0
			for y in range(BjGlyphs.CARD_H):
				for x in range(BjGlyphs.CARD_W):
					var color := image.get_pixel(x, y)
					if color.a <= 0.5:
						continue
					if color.is_equal_approx(BjGlyphs.FACE) or color.is_equal_approx(BjGlyphs.EDGE):
						continue
					# "红"的判据：红分量明显压过蓝与绿
					if color.r > 0.45 and color.r > color.b * 1.4 and color.r > color.g * 2.0:
						reddish += 1
			assert_eq(reddish, 0, "%s%s 上还有红色像素（整副牌应该只有一个藏青墨色）" % [suit, rank])


func test_card_back_is_not_a_face() -> void:
	var back := BjGlyphs.card_image("", "")
	assert_eq(back.get_size(), Vector2i(BjGlyphs.CARD_W, BjGlyphs.CARD_H))
	var stripes := 0
	var emblem := 0
	for y in range(BjGlyphs.CARD_H):
		for x in range(BjGlyphs.CARD_W):
			var color := back.get_pixel(x, y)
			if color.is_equal_approx(BjGlyphs.STRIPE):
				stripes += 1
			elif color.is_equal_approx(BjGlyphs.EMBLEM):
				emblem += 1
	assert_gt(stripes, 100, "牌背必须有斜纹")
	assert_gt(emblem, 50, "牌背必须有菱形徽记")
	# 牌背不能出现牌面墨色
	assert_eq(_ink_count(back, 0, 0, BjGlyphs.CARD_W, BjGlyphs.CARD_H), 0)


func test_court_cards_have_a_crown() -> void:
	# 王冠只画在 y 12..19（中央花色从 y20 开始，不能把花色的墨点算进来）
	for rank in ["J", "Q", "K"]:
		var image := BjGlyphs.card_image(rank, "S")
		assert_gt(_ink_count(image, 20, 12, 22, 8), 3, "%s 应该有王冠标记" % rank)
	# 数字牌没有王冠
	var plain := BjGlyphs.card_image("5", "S")
	assert_eq(_ink_count(plain, 20, 12, 22, 8), 0, "数字牌不该有王冠")


func test_texture_cache_returns_same_instance() -> void:
	var first := BjGlyphs.face_texture("A", "S")
	var second := BjGlyphs.face_texture("A", "S")
	assert_true(first == second, "同一张牌必须复用同一份纹理（52 张只生成一次）")
	assert_ne(BjGlyphs.face_texture("A", "S"), BjGlyphs.face_texture("A", "H"))


func test_chip_texture_is_drawn() -> void:
	var texture := BjGlyphs.chip_texture(BjTheme.ACCENT, BjTheme.ACCENT_DARK)
	assert_eq(texture.get_width(), 16)
	assert_eq(texture.get_height(), 16)
	var image := texture.get_image()
	var body := 0
	var rim := 0
	for y in range(16):
		for x in range(16):
			var color := image.get_pixel(x, y)
			if color.is_equal_approx(BjTheme.ACCENT) or color.is_equal_approx(BjTheme.ACCENT.lightened(0.25)):
				body += 1
			elif color.is_equal_approx(BjTheme.ACCENT_DARK):
				rim += 1
	assert_gt(body, 40, "筹码圆片应该有主体色")
	assert_gt(rim, 10, "筹码圆片应该有边圈")
	# 四角必须透明（是圆片不是方块）
	assert_true(image.get_pixel(0, 0).a < 0.01, "筹码四角应该透明")


func test_chip_breakdown_covers_the_amount() -> void:
	var chips := BjChipStack.breakdown(BjMachine.MAX_BET)
	assert_true(chips.size() <= BjChipStack.MAX_CHIPS)
	assert_eq(chips[0], BjMachine.MAX_BET)
	# 一笔零碎的下注也要有筹码可画
	var odd := BjChipStack.breakdown(BjMachine.MIN_BET)
	assert_eq(odd.size(), 1)
	assert_eq(odd[0], BjMachine.MIN_BET)


func test_whale_pip_sheet_is_built_from_the_provided_art() -> void:
	# 用户给的 picture/whale_pips_*_13.png：928×64、洋红底、一行 13 格。
	# 这里验证抠图 + 等宽切格 + 居中对齐这一整条流水线真的跑出了图集。
	assert_true(BjPips.available(), "找不到 assets/pips/whale_pips_*.png")
	var sheet := BjPips.sheet_image()
	assert_true(sheet != null, "图集没构建出来：%s" % BjPips.status())
	if sheet == null:
		return
	assert_eq(sheet.get_width(), BjPips.CELL_W * BjPips.COLS)
	assert_eq(sheet.get_height(), BjPips.CELL_H * BjPips.ROWS)
	# 抠图必须干净：不许残留洋红（否则牌面上会有一圈粉边）
	var magenta_left := 0
	for y in range(sheet.get_height()):
		for x in range(sheet.get_width()):
			var color := sheet.get_pixel(x, y)
			if color.a <= 0.5:
				continue
			var dr := (color.r - BjPips.MAGENTA.r) * 255.0
			var dg := (color.g - BjPips.MAGENTA.g) * 255.0
			var db := (color.b - BjPips.MAGENTA.b) * 255.0
			if sqrt(dr * dr + dg * dg + db * db) <= BjPips.TOL:
				magenta_left += 1
	assert_eq(magenta_left, 0, "图集里还残留 %d 个洋红像素" % magenta_left)


func test_every_pip_cell_has_content() -> void:
	# 13 格 × 4 行都必须切出内容（空格说明切格逻辑错了）
	var empty: Array = []
	for suit in BjPips.ROW_SUITS:
		for rank in BjPips.COL_RANKS:
			var cell := BjPips.cell_image(rank, suit)
			if cell == null or _colored_count(cell, 0, 0, cell.get_width(), cell.get_height()) < 10:
				empty.append("%s%s" % [suit, rank])
	assert_eq(empty.size(), 0, "这些格是空的：%s" % str(empty))


func test_thin_decoration_survives_downscale() -> void:
	# 回归：72→42 是 0.583 倍，用最近邻只会每隔 ~1.7 像素取一个点 ——
	# **1 像素宽的描边框会被采样成断续虚线甚至整条抹掉**，牌面上就只剩
	# 几根悬空的横线（用户看到的"很多花色都是错误的"）。
	# 这里造一个 1 像素细的方框，验证覆盖率降采样后四条边都还在。
	var source := BjPixel.make_image(BjPips.CELL_W, BjPips.CELL_H)
	var ink := BjGlyphs.INK
	for x in range(4, 68):
		source.set_pixel(x, 4, ink)
		source.set_pixel(x, 51, ink)
	for y in range(4, 52):
		source.set_pixel(4, y, ink)
		source.set_pixel(67, y, ink)

	var small := BjPips._downscale_cover(source, BjGlyphs.PIP_W, BjGlyphs.PIP_H)
	assert_eq(small.get_size(), Vector2i(BjGlyphs.PIP_W, BjGlyphs.PIP_H))

	# 竖边：每一行都要有靠左 + 靠右的实心像素
	var missing_vertical := 0
	for y in range(2, BjGlyphs.PIP_H - 2):
		var left := false
		var right := false
		for x in range(0, 6):
			if small.get_pixel(x, y).a > 0.5:
				left = true
		for x in range(BjGlyphs.PIP_W - 6, BjGlyphs.PIP_W):
			if small.get_pixel(x, y).a > 0.5:
				right = true
		if not (left and right):
			missing_vertical += 1
	assert_eq(missing_vertical, 0, "方框的竖边被采样丢了（%d 行缺边）" % missing_vertical)

	# 横边：每一列都要有靠上 + 靠下的实心像素
	var missing_horizontal := 0
	for x in range(2, BjGlyphs.PIP_W - 2):
		var top := false
		var bottom := false
		for y in range(0, 6):
			if small.get_pixel(x, y).a > 0.5:
				top = true
		for y in range(BjGlyphs.PIP_H - 6, BjGlyphs.PIP_H):
			if small.get_pixel(x, y).a > 0.5:
				bottom = true
		if not (top and bottom):
			missing_horizontal += 1
	assert_eq(missing_horizontal, 0, "方框的横边被采样丢了（%d 列缺边）" % missing_horizontal)


func test_pip_art_survives_texture_cache() -> void:
	assert_true(BjPips.sheet_texture() != null)
	assert_true(BjGlyphs.face_texture("A", "H") != null)
	# 同一张牌复用同一份纹理
	assert_true(BjGlyphs.face_texture("A", "H") == BjGlyphs.face_texture("A", "H"))


func test_bubble_grows_with_long_lines() -> void:
	# 用户报过的 bug：台词超过两行时气泡没跟着长高，文字溢出到框外。
	# 根因是不能用 Label.get_minimum_size() 去估自动换行的高度。
	var bubble := BjBubble.new()
	Engine.get_main_loop().root.add_child(bubble)
	track(bubble)
	bubble.size = Vector2(260, 60)
	bubble.set_text("短")
	var one_line := bubble.size.y
	bubble.set_text("这是一句特别长的台词，长到必须换好几行才放得下，用来验证气泡会不会跟着长高")
	var many_lines := bubble.size.y
	assert_gt(many_lines, one_line, "多行台词必须把气泡撑高")
	assert_gt(many_lines, 70.0, "四五行文字的气泡应该明显比两行高（实际 %.0f）" % many_lines)
	# 气泡高度必须装得下文字：留白 + 尾巴之后的净高度不小于文字高度
	var text_area := many_lines - BjBubble.PADDING_Y * 2.0 - BjBubble.TAIL_H
	assert_gt(text_area, 60.0, "给文字留的高度不够")


func test_integer_scaling_rule() -> void:
	# 像素画永远只做整数倍放大
	assert_eq(BjPixel.best_integer_scale(48.0, 144.0), 3)
	assert_eq(BjPixel.best_integer_scale(48.0, 40.0), 1)
	assert_eq(BjPixel.best_integer_scale(48.0, 1000.0), 8)


func test_upscale_is_lossless_nearest() -> void:
	var source := BjGlyphs.card_image("A", "S")
	var big := BjPixel.upscale(source, 2)
	assert_eq(big.get_size(), Vector2i(BjGlyphs.CARD_W * 2, BjGlyphs.CARD_H * 2))
	# 每个源像素都应变成 2×2 的实心块
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var color := source.get_pixel(x, y)
			assert_true(big.get_pixel(x * 2, y * 2).is_equal_approx(color))
			assert_true(big.get_pixel(x * 2 + 1, y * 2 + 1).is_equal_approx(color))


func test_sfx_builds_every_voice() -> void:
	var sfx := track(BjSfx.new()) as BjSfx
	var names := sfx.names()
	# 13 条与原版音色表一致 + 彩蛋 2 条 + 情境音效 13 条
	assert_eq(names.size(), 28, "音效数量对不上（原版 13 + 彩蛋 2 + 情境 13）")
	for expected in ["deal", "flip", "chip", "hit", "stand", "double", "bust",
			"win", "lose", "push", "blackjack", "talk", "click",
			"charge", "impact",
			# 情境音效：每种情况都该有自己的声音，而不是全在复用 chip/click
			"level_up", "record", "all_in", "turn",
			"favor_up", "favor_down", "coins", "warn",
			"panel_open", "panel_close", "cg_open",
			# 魔改倍率
			"charlie", "bust_bonus"]:
		assert_true(names.has(expected), "缺少音效 %s" % expected)
	# 未知音效必须安全返回 false，而不是抛异常打断牌局
	assert_false(sfx.play("不存在的音效"))


func test_sfx_synthesis_produces_audible_waveforms() -> void:
	var sfx := track(BjSfx.new()) as BjSfx
	# **每一条音效都要查**，不能只查老的那 13 条 ——
	# 新加的情境音效参数写错时（比如频率/时长给成 0），
	# 表现是"播放成功但听不见"，只有这里能抓到。
	for name in sfx.names():
		var stream := sfx.stream_for(name)
		assert_true(stream != null, "%s 没有合成出波形" % name)
		if stream == null:
			continue
		var data := stream.get_data()
		assert_gt(data.size(), 100, "%s 的波形太短（等于没声音）" % name)
		# 波形里必须有非零采样，否则是静音
		var peak := 0
		var index := 0
		while index + 1 < data.size():
			peak = maxi(peak, absi(data.decode_s16(index)))
			index += 2
		assert_gt(peak, 200, "%s 的波形是静音" % name)
		assert_eq(stream.get_mix_rate(), BjSfx.SR)
		assert_false(stream.is_stereo())
