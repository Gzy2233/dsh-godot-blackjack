class_name BjBubble
extends Control

## 鲸鱼娘的对话气泡。
##
## 原版有两套外观：演出台词（米黄色大头气泡）与打牌台词（白色小气泡，
## 边框是蓝色的）。这里保留这个区分 —— 一眼能看出"这句是它自己想的"
## 还是"这句是剧本里的"。
##
## 另外补上原版**承诺了却没做**的逐字显示（docs/两套台词机制.md 说要流式），
## 每出一个字配一声很轻的 blip。

signal blipped

const PADDING_X := 14.0
const PADDING_Y := 10.0
const TAIL_W := 14.0
const TAIL_H := 10.0
const CHAR_INTERVAL := 0.028
const BORDER := 3.0

var kind := "emote"
var full_text := ""

var _shown := 0.0
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = BjTheme.label("", 17, BjTheme.BUBBLE_INK)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _label != null:
		_resize()


func set_text(new_text: String, new_kind: String = "emote") -> void:
	full_text = new_text
	kind = new_kind
	_shown = 0.0
	_label.text = ""
	_resize()


func set_full_text_instantly() -> void:
	_shown = float(full_text.length())
	_label.text = full_text


## 按"这段文字在 text_width 宽度下要占多高"来定气泡高度。
##
## 为什么不用 `Label.get_minimum_size()`：自动换行（AUTOWRAP_WORD_SMART）时
## 它给的是一段不可靠的估算，**超过两行的台词就会溢出气泡**（用户报的 bug）。
## 直接问字体要行高才是准的。
func _resize() -> void:
	var text_width := maxf(120.0, size.x - PADDING_X * 2.0)
	var font := _label.get_theme_font("font")
	var font_size := _label.get_theme_font_size("font_size")
	var needed := float(font_size)
	if font != null and full_text != "":
		var measured := font.get_multiline_string_size(
			full_text, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size)
		needed = maxf(needed, measured.y)
	var height := maxf(38.0, needed + PADDING_Y * 2.0 + TAIL_H)
	custom_minimum_size = Vector2(size.x, height)
	size.y = height
	_label.position = Vector2(PADDING_X, PADDING_Y)
	_label.size = Vector2(text_width, height - PADDING_Y * 2.0 - TAIL_H)
	queue_redraw()


## 换行后的行数（调试/单测用）。
func line_count() -> int:
	if full_text == "":
		return 0
	var font := _label.get_theme_font("font")
	if font == null:
		return 1
	var text_width := maxf(120.0, size.x - PADDING_X * 2.0)
	return int(font.get_multiline_string_size(
		full_text, HORIZONTAL_ALIGNMENT_LEFT, text_width, _label.get_theme_font_size("font_size")
	).y / maxf(1.0, float(_label.get_theme_font_size("font_size"))))


func _process(delta: float) -> void:
	if _shown >= float(full_text.length()):
		return
	_shown += delta / CHAR_INTERVAL
	var count := mini(int(_shown), full_text.length())
	_label.text = full_text.substr(0, count)
	if count > 0 and full_text.substr(count - 1, 1) != " ":
		blipped.emit()


func is_revealing() -> bool:
	return _shown < float(full_text.length())


func _draw() -> void:
	var body := Rect2(Vector2.ZERO, Vector2(size.x, size.y - TAIL_H))
	var fill := BjTheme.BUBBLE if kind == "emote" else BjTheme.BUBBLE_PLAY
	var border := BjTheme.INK if kind == "emote" else BjTheme.OPP
	draw_rect(body, border)
	draw_rect(body.grow(-BORDER), fill)
	# 向下的尾巴（气泡在鲸鱼娘下方，所以尖朝下）
	var tail_x := 26.0
	var left := Vector2(tail_x, body.size.y)
	var right := Vector2(tail_x + TAIL_W, body.size.y)
	var tip := Vector2(tail_x + TAIL_W / 2.0, body.size.y + TAIL_H)
	draw_colored_polygon(PackedVector2Array([left, right, tip]), border)
	var inner_left := Vector2(tail_x + BORDER, body.size.y - 1)
	var inner_right := Vector2(tail_x + TAIL_W - BORDER, body.size.y - 1)
	var inner_tip := Vector2(tail_x + TAIL_W / 2.0, body.size.y + TAIL_H - BORDER)
	draw_colored_polygon(PackedVector2Array([inner_left, inner_right, inner_tip]), fill)
