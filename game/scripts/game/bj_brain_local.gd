class_name BjBrainLocal
extends Node

## 本地对手大脑：**离线也能打，而且打得像个人**。
##
## 单挑版策略的出发点变了：现在**你的两张牌都是明牌**，它看得见你的最终点数，
## 所以它的目标不再是"照着庄家明牌打牌理"，而是**赢过你**：
##   - 你已经爆了 → 它站着就赢，不再冒险
##   - 它已经领先 → 停手保胜
##   - 你已经 21 点 → 它要牌只会爆，停手保平局
##   - 平局 → 不赌（**除非它上头/记仇，见 decide_now**）
##   - 落后 → 必须要牌，硬扛
##
## 这条规则同时给了人格一个真实的杠杆：**上头的时候它会拿平局去赌一把赢**，
## 于是"人格"不只影响它说什么，还影响它怎么打。
##
## 保真的部分：
##   - 软牌判定用严格口径 has_soft_ace()
##   - 下注胆量仍是那一个公式（1 + 0.8*(confidence-0.5) - 0.4*tilt + 0.3*grudge），
##     单挑里它不再"自己押注"（同注对赌），这个值改成用于**它对注额的反应**：
##     你押得比它敢押的大，它会主动说点什么。

## "思考"时长，让牌桌有呼吸感。原版是模型的真实延迟。
const THINK_MIN := 0.45
const THINK_MAX := 1.15

var picker: BjLines.Picker
var persona: Dictionary = BjPersona.empty()
## 思考时长倍率。0 = 不等待（单测用）。
var think_scale := 1.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	picker = BjLines.Picker.new(_rng)


## 单挑的基本打法：**目标只有一个 —— 最后比你大**。
## 纯函数，方便单测直接钉死每一格。
static func duel_strategy(my_total: int, your_total: int, your_bust: bool) -> String:
	if your_bust:
		# 你已经爆了，它站着就赢：任何一张牌都可能把白送的局送回去
		return "STAND"
	if my_total > your_total:
		return "STAND"
	if your_total >= 21:
		# 你已经 21（非黑杰克的三张以上 21）：它要牌只能爆，站着至少平局
		return "STAND"
	if my_total == your_total:
		# 平局：站着是平局，要牌是拿爆牌风险换一个赢。默认不赌。
		return "STAND"
	return "HIT"


## 决定这一手。协程（await 一下装思考），签名与真模型大脑一致。
func decide(view: Dictionary, legal: Array, context: Dictionary = {}) -> Dictionary:
	if think_scale > 0.0 and is_inside_tree():
		await get_tree().create_timer(_rng.randf_range(THINK_MIN, THINK_MAX) * think_scale).timeout
	return decide_now(view, legal, context)


## 同步版本：单测与"不要延迟"的场合用它。
func decide_now(view: Dictionary, legal: Array, _context: Dictionary = {}) -> Dictionary:
	var my_total: int = int(view.get("opponent_total", 0))
	var your_total: int = int(view.get("player_total", 0))
	var your_bust: bool = bool(view.get("player_bust", false))
	var action := duel_strategy(my_total, your_total, your_bust)

	# 人格杠杆：平局本来可以收平局保本，但**上头/记仇的它会拿这个平局去赌一把赢**。
	if action == "STAND" and not your_bust and my_total == your_total and your_total < 21:
		var reckless := float(persona["tilt"]) > 0.6 or float(persona["grudge"]) > 0.7
		if reckless and _rng.randf() < 0.6:
			action = "HIT"

	if not legal.has(action):
		action = legal[0] if not legal.is_empty() else "STAND"
	return {
		"action": action,
		"say": talk_for_decision(view, action),
		"source": "local",
		"note": "本地策略",
	}


## 开局前对注额的一句反应（同注对赌：注是你定的，它跟）。
func opening_line(view: Dictionary, _limits: Dictionary = {}) -> Dictionary:
	if think_scale > 0.0 and is_inside_tree():
		await get_tree().create_timer(_rng.randf_range(0.3, 0.8) * think_scale).timeout
	return opening_now(view)


func opening_now(view: Dictionary) -> Dictionary:
	var stake: int = int(view.get("stake", BjMachine.MIN_BET))
	var chips: int = int(view.get("opponent_chips", BjMachine.STARTING_CHIPS))
	var comfort := fallback_bet(persona, {
		"min": int(view.get("min_bet", BjMachine.MIN_BET)),
		"max": mini(int(view.get("max_bet", BjMachine.MAX_BET)), chips),
		"chips": chips,
	})
	var situation := "betting"
	if stake >= comfort * 2:
		situation = "bet_big"      # 你押得比它敢押的大得多
	elif float(stake) <= float(comfort) / 2.0:
		situation = "bet_small"    # 你押得很小气
	return {
		"say": BjLines.talk_for(situation, BjPersona.mood(persona), picker),
		"source": "local",
	}


## 人格 → 它"敢押"的注额。原版 fallbackBet 的公式，一位不改。
## 单挑里注额由你定、它跟，所以这个值只用来判断"你这个注对它算大还是小"。
static func fallback_bet(persona_in: Dictionary, limits: Dictionary) -> int:
	var low: int = int(limits["min"])
	var high: int = int(limits["max"])
	var chips: int = int(limits["chips"])
	var mid := (float(low) + float(high)) / 2.0
	var multiplier := 1.0
	if not persona_in.is_empty():
		multiplier = BjPersona.bet_multiplier(persona_in)
	var want := mid * multiplier
	# 取整到 10 —— 与大额筹码的 10 的幂保持一致
	var rounded := int(round(want / 10.0)) * 10
	return maxi(low, mini(high, mini(rounded, chips)))


## 选一句"看得见牌"的牌桌台词。
func talk_for_decision(view: Dictionary, action: String) -> String:
	var candidates: Array = []
	var my_total: int = int(view.get("opponent_total", 0))
	var your_total: int = int(view.get("player_total", 0))
	var your_up_value: int = int(view.get("player_up_value", 10))
	var your_bust: bool = bool(view.get("player_bust", false))
	var count: int = int(view.get("running_count", 0))

	candidates.append("i_hit" if action == "HIT" else "i_stand")
	if your_bust:
		candidates.append("you_busted")
	elif my_total > your_total:
		candidates.append("i_ahead")
	elif my_total < your_total:
		candidates.append("i_behind")
	if my_total >= 19:
		candidates.append("my_turn_strong")
	elif my_total <= 11:
		candidates.append("my_turn_weak")
	if your_up_value >= 10:
		candidates.append("your_scary")
	elif your_up_value <= 6:
		candidates.append("your_weak")
	if count >= 3:
		candidates.append("count_high")
	elif count <= -3:
		candidates.append("count_low")

	var situation: String = candidates[_rng.randi_range(0, candidates.size() - 1)]
	return BjLines.talk_for(situation, BjPersona.mood(persona), picker)
