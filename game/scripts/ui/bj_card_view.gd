class_name BjCardView
extends Control

## 一张牌。纹理是**程序化生成**的（见 BjGlyphs），缩放永远是整数倍。
##
## 动画照原版 CSS 的分步（`steps()`）语义重做：
##   发牌 260ms / 6 步，从 (-160,-120) 旋转 -16° 飞入
##   翻牌 420ms / 8 步，暗牌绕 Y 轴翻开（这里用横向压缩模拟）

const SCALE := 2
const CARD_SIZE := Vector2(46 * SCALE, 56 * SCALE)
const DEAL_TIME := 0.26
const DEAL_STEPS := 6
const FLIP_TIME := 0.42
const FLIP_STEPS := 8
const DEAL_FROM := Vector2(-160, -120)
const DEAL_ANGLE := -16.0

var rank := ""
var suit := ""
var face_up := true

var _flip := 1.0
var _deal := 1.0
var _home := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flip = 1.0 if face_up else 0.0
	visible = true


## 只换牌面数据，不动翻牌状态（翻开暗牌时必须用这个，否则会闪一下正面）。
func set_face_data(new_rank: String, new_suit: String) -> void:
	rank = new_rank
	suit = new_suit
	queue_redraw()


## 设定牌面。rank 为空串 = 牌背（暗牌就是这么表示的，没有"变灰"那种中间态）。
func setup(new_rank: String, new_suit: String, new_face_up: bool) -> void:
	rank = new_rank
	suit = new_suit
	face_up = new_face_up
	_flip = 1.0 if new_face_up else 0.0
	_deal = 1.0
	queue_redraw()


func set_home(position_in_parent: Vector2) -> void:
	_home = position_in_parent
	position = position_in_parent


## 分步量化：把平滑的 0..1 打成 N 档，模拟 CSS 的 steps()。
static func _quantize(progress: float, steps: int) -> float:
	if steps <= 1:
		return progress
	return floor(progress * steps) / float(steps - 1) if progress < 1.0 else 1.0


## 发牌动画（带 delay 的逐张错峰由调用方负责）。
func play_deal(delay: float = 0.0) -> void:
	_deal = 0.0
	_apply_deal()
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(_set_deal, 0.0, 1.0, DEAL_TIME)


func _set_deal(value: float) -> void:
	_deal = _quantize(value, DEAL_STEPS) if value < 1.0 else 1.0
	_apply_deal()


func _apply_deal() -> void:
	var inverse := 1.0 - _deal
	position = _home + DEAL_FROM * inverse
	rotation = deg_to_rad(DEAL_ANGLE) * inverse
	modulate.a = _deal


## 翻暗牌。只在 0.5 处换面，横向压缩模拟绕 Y 轴转。
func play_flip(delay: float = 0.0) -> void:
	face_up = false
	_flip = 0.0
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(_set_flip, 0.0, 1.0, FLIP_TIME)


func _set_flip(value: float) -> void:
	_flip = _quantize(value, FLIP_STEPS) if value < 1.0 else 1.0
	if _flip > 0.5:
		face_up = true
	queue_redraw()


func _draw() -> void:
	var show_face := face_up and _flip > 0.5
	var texture: Texture2D = BjGlyphs.face_texture(rank, suit) if show_face else BjGlyphs.back_texture()
	var width := CARD_SIZE.x
	if _flip > 0.0 and _flip < 1.0:
		# 翻牌中间帧：横向压缩
		var factor := absf(_flip * 2.0 - 1.0)
		width = maxf(2.0, CARD_SIZE.x * factor)
	var rect := Rect2(Vector2((CARD_SIZE.x - width) / 2.0, 0.0), Vector2(width, CARD_SIZE.y))
	draw_texture_rect(texture, rect, false)
	# 硬阴影（原版是 0 4px 0 的实心偏移，不是模糊阴影）
	draw_rect(Rect2(Vector2(4, CARD_SIZE.y - 2), Vector2(CARD_SIZE.x - 4, 4)), Color(0, 0, 0, 0.45))
