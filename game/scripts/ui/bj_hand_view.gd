class_name BjHandView
extends Control

## 一手牌的容器：横向排布 + 超过宽度就重叠（**不压缩**）。
##
## 原版是 CSS flex 行，第 6 张牌起会把所有牌压扁（flex-shrink 默认 1），
## 牌面被挤变形 —— 那是原版的显示 bug。这里改成"超出就重叠"，
## 牌永远保持 92×112 的整数倍尺寸。

const GAP := 6.0

var max_width := 520.0
var stagger := 0.0

var _views: Array[BjCardView] = []
var _placeholders := 0
## 动画（发牌/翻牌）结束的绝对时刻，毫秒。视图用它决定点数何时出现。
var _anim_end_msec := 0
var _placeholder_alpha := 0.18


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, BjCardView.CARD_SIZE.y + 8)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reposition()


## 设定整手牌。`hole_flags` 每项表示该张是否盖着（对手的第 2 张就是暗牌）。
## `animate_from` 之前的张数不重播动画（增量发牌时只动新来的那张）。
func set_cards(cards: Array, hole_flags: Array, animate_from: int = 0, stagger_step: float = 0.0,
		start_delay: float = 0.0) -> void:
	stagger = stagger_step
	# 多的删掉
	while _views.size() > cards.size():
		var extra: BjCardView = _views.pop_back()
		extra.queue_free()

	for i in range(cards.size()):
		var card: Dictionary = cards[i]
		var is_hidden: bool = i < hole_flags.size() and bool(hole_flags[i])
		var rank := "" if is_hidden else str(card.get("rank", ""))
		var suit := "" if is_hidden else str(card.get("suit", ""))
		if i < _views.size():
			var view: BjCardView = _views[i]
			var was_hidden := not view.face_up
			if was_hidden and not is_hidden:
				# 暗牌翻开：走翻牌动画，不重播发牌
				view.set_face_data(rank, suit)
				view.play_flip(i * 0.04)
				_note_anim(i * 0.04, BjCardView.FLIP_TIME)
			elif was_hidden == is_hidden:
				view.setup(rank, suit, not is_hidden)
		else:
			var created := BjCardView.new()
			add_child(created)
			created.setup(rank, suit, not is_hidden)
			_views.append(created)
			if i >= animate_from:
				var card_delay := start_delay + stagger_step * float(i - animate_from)
				created.play_deal(card_delay)
				_note_anim(card_delay, BjCardView.DEAL_TIME)

	_reposition()


## 还没发到的牌：画虚线槽位（原版也是这么提示的）。
func set_placeholders(count: int) -> void:
	_placeholders = count
	_reposition()
	queue_redraw()


func clear() -> void:
	for view in _views:
		view.queue_free()
	_views.clear()
	_placeholders = 0
	_anim_end_msec = 0
	queue_redraw()


## 记一笔动画的结束时刻（发牌 / 翻牌都算）。
## 视图靠 anim_remaining() 决定"点数什么时候才该出现"。
func _note_anim(delay: float, duration: float) -> void:
	_anim_end_msec = maxi(_anim_end_msec,
		Time.get_ticks_msec() + int((maxf(delay, 0.0) + duration) * 1000.0))


## 这副牌还要多久才动完（秒）。0 表示已经静止。
func anim_remaining() -> float:
	return maxf(0.0, float(_anim_end_msec - Time.get_ticks_msec()) / 1000.0)


func card_count() -> int:
	return _views.size()


func _reposition() -> void:
	var total := _views.size() + _placeholders
	if total == 0:
		return
	var card_w := BjCardView.CARD_SIZE.x
	var step := card_w + GAP
	if total > 1:
		var available := max_width - card_w
		step = minf(step, available / float(total - 1))
	var used := card_w + step * float(total - 1)
	var start_x := maxf(0.0, (max_width - used) / 2.0)
	for i in range(_views.size()):
		_views[i].set_home(Vector2(start_x + step * float(i), 0))


func _draw() -> void:
	if _placeholders <= 0:
		return
	var card_w := BjCardView.CARD_SIZE.x
	var total := _views.size() + _placeholders
	var step := card_w + GAP
	if total > 1:
		step = minf(step, (max_width - card_w) / float(total - 1))
	var used := card_w + step * float(total - 1)
	var start_x := maxf(0.0, (max_width - used) / 2.0)
	var color := Color(1, 1, 1, _placeholder_alpha)
	for i in range(_placeholders):
		var index := _views.size() + i
		var origin := Vector2(start_x + step * float(index), 0)
		var size_vec := Vector2(card_w, BjCardView.CARD_SIZE.y)
		# 虚线框：每 6 像素画一段
		var dashed := 6.0
		var x := origin.x
		while x < origin.x + size_vec.x:
			var length := minf(dashed, origin.x + size_vec.x - x)
			draw_rect(Rect2(x, origin.y, length, 2), color)
			draw_rect(Rect2(x, origin.y + size_vec.y - 2, length, 2), color)
			x += dashed * 2
		var y := origin.y
		while y < origin.y + size_vec.y:
			var length := minf(dashed, origin.y + size_vec.y - y)
			draw_rect(Rect2(origin.x, y, 2, length), color)
			draw_rect(Rect2(origin.x + size_vec.x - 2, y, 2, length), color)
			y += dashed * 2
