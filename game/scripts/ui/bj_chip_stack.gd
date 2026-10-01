class_name BjChipStack
extends Control

## 筹码堆：把下注额拆成面额，画成一小摞筹码。
##
## **原版完全没有筹码图形**（只有文字和按钮），这是移植时补的美术。
## 面额色沿用牌桌主题：100万金 / 500万红 / 1000万绿 / 5000万蓝。

const CHIP_PIXELS := 16
const SCALE := 2
const CHIP_SIZE := CHIP_PIXELS * SCALE
const X_STEP := 18.0
const Y_STEP := 3.0
const MAX_CHIPS := 5

var amount := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_amount(new_amount: int) -> void:
	amount = new_amount
	var chips := breakdown(new_amount)
	var count := chips.size()
	var width := CHIP_SIZE + X_STEP * float(maxi(0, count - 1))
	var height := CHIP_SIZE + Y_STEP * float(maxi(0, count - 1))
	custom_minimum_size = Vector2(width, height)
	size = custom_minimum_size
	queue_redraw()


## 贪心拆面额，最多 MAX_CHIPS 枚（只用于视觉）。
## 面额跟着阶梯走：最大注 / 2 倍最小注 / 最小注（从大到小，必须递减，
## 否则贪心会拆出重复面额）。
static func breakdown(value: int) -> Array:
	var denominations := [
		BjMachine.MAX_BET, BjMachine.MIN_BET * 2, BjMachine.MIN_BET,
	]
	var chips: Array = []
	var left := value
	for denomination in denominations:
		while left >= denomination and chips.size() < MAX_CHIPS:
			chips.append(denomination)
			left -= denomination
	if chips.is_empty() and value > 0:
		chips.append(value)
	return chips


func _draw() -> void:
	var chips := breakdown(amount)
	for i in range(chips.size()):
		var colors := BjTheme.chip_colors(chips[i])
		var texture := BjGlyphs.chip_texture(colors[0], colors[1])
		var offset := Vector2(X_STEP * float(i), -Y_STEP * float(i))
		draw_texture_rect(texture, Rect2(offset, Vector2(CHIP_SIZE, CHIP_SIZE)), false)
