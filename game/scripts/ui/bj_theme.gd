class_name BjTheme
extends RefCounted

## 牌桌配色与控件工厂。
##
## 色值逐条移植自 dsh-deepseek-blackjack/src/client/theme.js（真实赌场配色：
## 绿呢毯 + 暖黄聚光 + 金属筹码）。**不要随机换色** —— 这套色是调过的。

const FELT_1 := Color("#1d6b45")
const FELT_2 := Color("#14512f")
const FELT_LINE := Color("#2a8a5c")
const RAIL := Color("#5a3a22")
const RAIL_LIGHT := Color("#8a5a34")
const INK := Color("#0f1a14")
const TEXT := Color("#f2f6f3")
const TEXT_DIM := Color("#a8c4b4")
const ACCENT := Color("#f0b429")
const ACCENT_DARK := Color("#b8821a")
const ACCENT_LIGHT := Color("#ffc94d")
const DANGER := Color("#d9483f")
const DANGER_LIGHT := Color("#e85b52")
const WIN := Color("#58c470")
const OPP := Color("#7fb4ff")
const PANEL := Color("#12261c")
const PANEL_LINE := Color("#2c5540")
const BUBBLE := Color("#fdf6e3")
const BUBBLE_PLAY := Color("#ffffff")
const BUBBLE_INK := Color("#1a2340")

## 牌桌逻辑分辨率：所有像素坐标都按这个尺寸设计，再整体整数倍缩放。
const DESIGN_SIZE := Vector2(1280, 760)

static var _font: SystemFont = null


## 中文字体：Godot 内置字体**没有 CJK 字形**，不换字体所有中文都是空白。
## 用 SystemFont 让引擎自己去系统里找（微软雅黑 / 黑体 / Noto）。
static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray([
			"Microsoft YaHei UI", "Microsoft YaHei", "SimHei",
			"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "sans-serif",
		])
	return _font


static func label(text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	node.add_theme_constant_override("shadow_offset_x", 1)
	node.add_theme_constant_override("shadow_offset_y", 1)
	return node


## 像素风按钮：3px 硬边 + 底部 5px（像凸起的塑料键）。
static func button_style(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(3)
	box.border_width_bottom = 5
	box.set_corner_radius_all(0)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


static func empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func make_button(text: String, variant: String = "normal") -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", 17)
	node.focus_mode = Control.FOCUS_NONE
	var background := PANEL_LINE
	var border := INK
	var foreground := TEXT
	match variant:
		"primary":
			background = ACCENT
			foreground = INK
		"accent":
			background = DANGER
			foreground = TEXT
		"chip":
			background = RAIL
			border = RAIL_LIGHT
		"toggle":
			background = Color(0, 0, 0, 0)
			border = PANEL_LINE
			foreground = TEXT_DIM
	var normal := button_style(background, border)
	var hover := button_style(background.lightened(0.18), border)
	var pressed := button_style(background.darkened(0.12), border)
	pressed.content_margin_top = 10
	pressed.content_margin_bottom = 6
	pressed.border_width_bottom = 3
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("disabled", normal)
	node.add_theme_stylebox_override("focus", empty_style())
	node.add_theme_color_override("font_color", foreground)
	node.add_theme_color_override("font_hover_color", foreground)
	node.add_theme_color_override("font_pressed_color", foreground)
	node.add_theme_color_override("font_disabled_color", Color(foreground.r, foreground.g, foreground.b, 0.35))
	return node


static func panel_style(background: Color, border: Color, border_width: int = 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


## 筹码面额 → (主体色, 边圈色)。按"当前档位的最大注 / 中档 / 小档"分色，
## 阈值跟着 MIN_BET 走，所以调小经济时不用改这里。
static func chip_colors(amount: int) -> Array:
	var unit := BjMachine.MIN_BET
	if amount >= unit * BjMachine.MAX_STAKE_MULTIPLIER:
		return [OPP, Color("#3f6fa8")]
	if amount >= unit * 3:
		return [WIN, Color("#2f7a42")]
	if amount >= unit * 2:
		return [DANGER, Color("#8f2b26")]
	return [ACCENT, ACCENT_DARK]
