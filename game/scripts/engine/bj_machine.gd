class_name BjMachine
extends RefCounted

## 21 点状态机（**单挑版**）：开局 / 你行动 / 它行动 / 摊牌结算。
##
## 牌桌上只有两个人：你 和 鲸鱼娘。**没有庄家**。
## 这一点决定了整个游戏的经济学：
##   - 双方各押**同样的注**（你选注，它跟注；它跟不动就按它的筹码封顶）
##   - 谁点数大谁拿走对方那一份 → 筹码严格**零和**
##   - 所以"赢它的 token"是真的在赢它的钱，而不是赢庄家的钱
##
## 与原版（三方桌，庄家是引擎）的差别，都是有意的：
##   1. 没有庄家座位、没有"庄家必须补到 17"那套机械规则
##   2. 它也有黑杰克待遇（2 张 21 赔 1.5 倍）—— 单挑里双方必须对称
##   3. 双方都爆 → 平局（没有庄家可以收钱）
##   4. 加注（DOUBLE）要求**双方都出得起**翻倍后的注额（它必须跟得上）
##
## 保留的硬约束：
##   1. 不抛异常：所有可预期失败都返回 `{ok:false, error}`，RPC/UI 直接转发。
##   2. 零随机、零 IO：唯一的随机入口是构造时传入的 rng，只在洗牌/换靴时消费。

const PHASE_BETTING := "BETTING"
const PHASE_PLAYER_TURN := "PLAYER_TURN"
const PHASE_OPPONENT_TURN := "OPPONENT_TURN"
const PHASE_SETTLE := "SETTLE"

const WHO_PLAYER := "PLAYER"
const WHO_OPPONENT := "OPPONENT"

## 筹码量级：用**万/亿级 token**，不是几百的小数字。
## "输了 500 万 token" 有分量，"输了 200" 没有。
##
## 2026-09 按用户要求整体调小：开局从 1 亿降到 **2000 万**，第一档最小注
## 从 100 万降到 **20 万** —— 这样开局那几局的下注才有存在感
## （原来 100 万对 1 亿的身家，赢了跟没赢一样）。
const STARTING_CHIPS := 20_000_000
const MIN_BET := 200_000
const MAX_BET := 1_000_000
const BLACKJACK_PAYOUT := 1.5

## ---------------------------------------------------------------- 魔改倍率
##
## 三条**只给玩家**的加成（小游戏要的是爽感，不是赌场公平性）：
##   - **抓它爆牌**：它爆、你没爆 → 1.2 倍（下注 100 拿 220）
##   - **五小龙**：手里 5 张牌还没爆（≤21）→ 2 倍
##   - **六小龙**：6 张还没爆 → 2.5 倍
##
## 优先级：**取最大值，不叠乘**。六小龙 2.5 > 五小龙 2 > 抓爆 1.2，
## 黑杰克 1.5 照旧（双方都享受）。叠乘会让一次结算直接把对方清零，
## 单局太短、也看不出是哪条规则发的威。
const BUST_BONUS := 1.2
const CHARLIE_CARDS_5 := 5
const CHARLIE_CARDS_6 := 6
const CHARLIE_5_MULT := 2.0
const CHARLIE_6_MULT := 2.5

## ---------------------------------------------------------------- 下注阶梯
##
## **每 2 局升一档**，最小注往上抬，最大注 = 最小注 × 5。
## 开局 20 万，涨到 2000 万封顶 —— **第 20 局就封顶**（11 档 × 2 局）。
##
## 为什么这么设计：
##   - 前几局是热身，第 6 局起每一局都开始咬手，筹码曲线迅速收紧；
##   - **第 20 局到顶**，顶档最小注 1000 万 = 半副身家（不是全部身家）——
##     刻意留一半：如果封顶就等于全部身家，第 20 局之后每局都成了"必然全押"的
##     突然死亡，太惩罚；留一半还能继续打，纪录也还有得涨。
##   - 到了顶档，最大注（1000万 × 5 = 5000万）已经超过开局身家，
##     所以 **ALL IN 按钮会在第 18 局前后自然出现**。
##   - 档位是**手写的整数**（约 ×1.5 一档），不做 1.5^n：读数干净
##     （20万/30万/40万/60万…），也避免"337万"这种怪数字。
const STAKE_HANDS_PER_LEVEL := 2
const STAKE_MIN_STEPS: Array[int] = [
	200_000,        # 第 0-1 局
	300_000,        # 第 2-3 局
	400_000,        # 第 4-5 局
	600_000,
	800_000,        # 第 8-9 局
	1_000_000,
	1_500_000,
	2_000_000,      # 第 14-15 局
	3_000_000,
	5_000_000,
	10_000_000,     # 第 20 局起封顶
]
## 最大注 = 最小注 × 这个倍数。5 倍够拉开"小注磨 / 大注梭"的层次，
## 又不会让一次失误直接清空（那太惩罚了）。
const MAX_STAKE_MULTIPLIER := 5

## 一局开局要发的牌数：你明、它明、你明、它暗。
const DEAL_COUNT := 4

## 「大幅波动」阈值，用于挑台词（原版那个 150 是亿级筹码改造前的遗留值，这里改成相对下注区间）。
const BIG_BET := MIN_BET * 5

var rng: RandomNumberGenerator
var shoe: BjShoe
## Hi-Lo 计数：只统计**已经公开**的牌，跨局延续，换靴才归零。
var running_count: int = 0
var hand_no: int = 0
var player_chips: int = STARTING_CHIPS
var opponent_chips: int = STARTING_CHIPS

## 当前这一局。空 Dictionary 表示还没发牌。
var state: Dictionary = {}

## 最近一次动作产生的事件流（前端按它做动画）。
var events: Array = []


func _init() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()
	shoe = BjShoe.create(rng)


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _ok(new_events: Array = []) -> Dictionary:
	events = new_events
	return {"ok": true, "events": new_events}


func _seat(who: String) -> Dictionary:
	return state["player"] if who == WHO_PLAYER else state["opponent"]


func has_hand() -> bool:
	return not state.is_empty()


func phase() -> String:
	if state.is_empty():
		return PHASE_BETTING
	return state["phase"]


func hand_of(who: String) -> Array:
	if state.is_empty():
		return []
	return _seat(who)["hand"]


func player_hand() -> Array:
	return hand_of(WHO_PLAYER)


func opponent_hand() -> Array:
	return hand_of(WHO_OPPONENT)


func opponent_hole_hidden() -> bool:
	if state.is_empty():
		return true
	return state["opponent"]["hide_hole"]


func stake() -> int:
	if state.is_empty():
		return 0
	return state["stake"]


## 当前双方各自押在桌上多少（零和：赢家拿走对方那一份）。
func pot() -> int:
	return stake() * 2


## 现在升到第几档下注（每 10 局一档，封顶最后一档）。
func stake_level() -> int:
	@warning_ignore("integer_division")
	return clampi(hand_no / STAKE_HANDS_PER_LEVEL, 0, STAKE_MIN_STEPS.size() - 1)


## 现在的最小注。涨注就是涨它。
func min_stake() -> int:
	return STAKE_MIN_STEPS[stake_level()]


## 本局注额能开到多大：受最大注上限和双方筹码限制。
func max_stake() -> int:
	return mini(min_stake() * MAX_STAKE_MULTIPLIER, mini(player_chips, opponent_chips))


## ALL IN 能押多少：**不受 MAX_BET 限制**，只看双方谁更穷。
##
## 这才是 ALL IN 的意义 —— 一把梭到底，输光就直接进破产流程。
## 因为是对注制（她必须跟同样的注额），所以上限天然被更穷的那一方卡住。
func all_in_stake() -> int:
	return mini(player_chips, opponent_chips)


## 你这一手可以做什么。DOUBLE 要求**双方**都出得起翻倍后的注额。
func legal_actions() -> Array:
	if state.is_empty() or state["phase"] != PHASE_PLAYER_TURN:
		return []
	var player: Dictionary = state["player"]
	if player["busted"] or player["done"]:
		return []
	var actions: Array = ["HIT", "STAND"]
	var doubled_stake: int = state["stake"] * 2
	if player["hand"].size() == 2 and player_chips >= doubled_stake and opponent_chips >= doubled_stake:
		actions.append("DOUBLE")
	return actions


## 校验注额。返回错误字符串或 ""。
func validate_stake(amount: int) -> String:
	var floor_bet := min_stake()
	if amount < floor_bet:
		return "注额不能低于 %s token" % BjTokens.format(floor_bet)
	# 上限放宽到 ALL IN：筹码面额自己不会超过最大注，
	# 但"一把梭"这个动作本身就该能越过它
	var ceiling := maxi(max_stake(), all_in_stake())
	if amount > ceiling:
		return "注额不能高于 %s token" % BjTokens.format(ceiling)
	if player_chips < amount:
		return "你的筹码不够跟这个注"
	if opponent_chips < amount:
		return "它只有 %s token，跟不动这个注" % BjTokens.format(opponent_chips)
	return ""


## 现在能不能 ALL IN（双方都还开得起最小注）。
func can_all_in() -> bool:
	return all_in_stake() >= min_stake()


## 抽一张牌，把"已公开"与否计入 Hi-Lo 累计。
func _take_card(who: String, face_up: bool) -> Dictionary:
	var card := shoe.draw()
	if card.is_empty():
		return {}
	_seat(who)["hand"].append(card)
	if face_up:
		running_count += BjCards.hi_lo(card)
	return card


## 翻开它的暗牌（公开接口）：把隐藏的牌计入 Hi-Lo，返回给前端做翻牌动画。
##
## 由**游戏层**在"你的回合结束、轮到它"时调用 —— 也就是标准 21 点的
## "庄家先翻暗牌再补牌"。这样它在自己回合里补的每一张牌都是明的，
## 玩家看到的点数就是真实点数，不用自己心算。
func reveal_opponent() -> Array:
	return _reveal_opponent()


## 翻开它的暗牌：把隐藏的牌计入 Hi-Lo。
func _reveal_opponent() -> Array:
	var opponent: Dictionary = state["opponent"]
	if not opponent["hide_hole"]:
		return []
	opponent["hide_hole"] = false
	if opponent["hand"].size() < 2:
		return []
	var card: Dictionary = opponent["hand"][1]
	running_count += BjCards.hi_lo(card)
	return [{"type": "REVEAL", "who": WHO_OPPONENT, "card": card}]


## 开局：校验注额 → 发 4 张牌 → 判定你是否有天然黑杰克。
##
## 发牌顺序（固定，逐张动画与测试夹具都依赖它）：
##   1 你明  2 它明  3 你明  4 它暗
func start_hand(amount: int) -> Dictionary:
	var error := validate_stake(amount)
	if error != "":
		return _fail(error)

	# 低于 25% 换靴：换靴后历史累计失效，必须归零，否则算牌会带着上一靴的偏差继续走。
	if shoe.needs_reshuffle():
		shoe = BjShoe.create(rng)
		running_count = 0
	if shoe.remaining() < DEAL_COUNT:
		return _fail("牌靴剩余不足 %d 张，无法开局" % DEAL_COUNT)

	hand_no += 1
	# **先手轮换**：第 1 局你先，第 2 局它先，交替。
	# 单挑的两个对等玩家轮流坐庄，比"永远你先"更像一场对决。
	var opponent_first := hand_no % 2 == 0
	state = {
		"hand_no": hand_no,
		"phase": PHASE_BETTING,
		"stake": amount,
		"first_actor": WHO_OPPONENT if opponent_first else WHO_PLAYER,
		"player": {
			"hand": [], "doubled": false,
			"done": false, "busted": false, "blackjack": false,
		},
		"opponent": {
			"hand": [], "done": false,
			"busted": false, "hide_hole": true,
		},
		"outcome": {},
	}

	var new_events: Array = [
		{"type": "BET", "who": WHO_PLAYER, "amount": amount},
		{"type": "BET", "who": WHO_OPPONENT, "amount": amount},
	]

	var plan := [
		[WHO_PLAYER, true],
		[WHO_OPPONENT, true],
		[WHO_PLAYER, true],
		[WHO_OPPONENT, false],
	]
	for entry in plan:
		var card := _take_card(entry[0], entry[1])
		if card.is_empty():
			state = {}
			return _fail("牌靴已空")
		new_events.append({
			"type": "DEAL", "who": entry[0], "card": card, "face_up": entry[1],
		})

	if BjHand.is_blackjack(player_hand()):
		# 你天然黑杰克：你没有可做的决定，直接把回合交给它（它停手后立刻摊牌）。
		state["phase"] = PHASE_OPPONENT_TURN
		state["player"]["blackjack"] = true
		state["player"]["done"] = true
		new_events.append({"type": "BLACKJACK", "who": WHO_PLAYER})
	elif opponent_first:
		# **它先手**的局：它的暗牌开局就翻开 —— 它得先做决定，不能拿暗牌做决策；
		# 反过来你因此能看到它的全部牌，这是这一局你的信息红利。
		state["opponent"]["hide_hole"] = false
		state["phase"] = PHASE_OPPONENT_TURN
	else:
		state["phase"] = PHASE_PLAYER_TURN

	return _ok(new_events)


## 你的动作：HIT / STAND / DOUBLE。
## DOUBLE 把**双方**的注额一起翻倍（它必须跟），然后只发一张牌并自动停牌。
func player_action(action: String) -> Dictionary:
	if state.is_empty():
		return _fail("这一局还没开始")
	if action != "HIT" and action != "STAND" and action != "DOUBLE":
		return _fail("未知动作：%s" % action)
	if state["phase"] != PHASE_PLAYER_TURN:
		return _fail("当前阶段你不能行动：%s" % state["phase"])
	var player: Dictionary = state["player"]
	if player["done"]:
		return _fail("你本局已结束行动")
	if player["busted"]:
		return _fail("你已经爆牌，不能继续行动")

	if action == "STAND":
		player["done"] = true
		_advance_phase(WHO_PLAYER)
		return _ok([{"type": "STAND", "who": WHO_PLAYER}])

	if action == "DOUBLE":
		if not BjHand.can_double(player["hand"]):
			return _fail("加注只能在恰好两张牌时使用")
		var extra: int = state["stake"]
		var doubled: int = state["stake"] * 2
		if player_chips < doubled:
			return _fail("你的筹码不足以加注")
		if opponent_chips < doubled:
			return _fail("它跟不动加注（它只有 %s token）" % BjTokens.format(opponent_chips))

		var card := _take_card(WHO_PLAYER, true)
		if card.is_empty():
			return _fail("牌靴已空")
		state["stake"] = doubled
		player["doubled"] = true
		player["done"] = true
		# DOUBLE 事件不带牌，而前端要靠事件重放渲染这张加注牌，
		# 所以紧跟一条 HIT 事件把牌带出去。
		var doubled_events: Array = [
			{"type": "DOUBLE", "who": WHO_PLAYER, "extra_bet": extra, "stake": doubled},
			{"type": "HIT", "who": WHO_PLAYER, "card": card},
		]
		if BjHand.is_bust(player["hand"]):
			player["busted"] = true
			doubled_events.append({
				"type": "BUST", "who": WHO_PLAYER, "total": BjHand.value(player["hand"]),
			})
		_advance_phase(WHO_PLAYER)
		return _ok(doubled_events)

	# HIT
	var drawn := _take_card(WHO_PLAYER, true)
	if drawn.is_empty():
		return _fail("牌靴已空")
	var new_events: Array = [{"type": "HIT", "who": WHO_PLAYER, "card": drawn}]
	if BjHand.is_bust(player["hand"]):
		# 爆牌立即结束本方行动，但仍要等它行动完（它也爆了才算平局）。
		player["busted"] = true
		player["done"] = true
		new_events.append({
			"type": "BUST", "who": WHO_PLAYER, "total": BjHand.value(player["hand"]),
		})
		_advance_phase(WHO_PLAYER)
	elif player_charlie() >= CHARLIE_CARDS_5:
		# 五小龙：摸到第 5 张还没爆。**故意不自动停牌** ——
		# 因为"六小龙"要求你主动再要一张，自动停牌会让那条规则永远不可能达成。
		# 所以这里只发一个事件让前端报喜，去留由你决定。
		# 第 6 张到手就自动停：倍率已经顶格（2.5），再要只会找死。
		new_events.append({
			"type": "CHARLIE", "who": WHO_PLAYER, "cards": player_charlie(),
			"total": BjHand.value(player["hand"]),
		})
		if player_charlie() >= CHARLIE_CARDS_6:
			player["done"] = true
			_advance_phase(WHO_PLAYER)
	return _ok(new_events)


## 它的动作：HIT / STAND。它的手牌只在摊牌时公开。
func opponent_action(action: String) -> Dictionary:
	if state.is_empty():
		return _fail("这一局还没开始")
	if action != "HIT" and action != "STAND":
		return _fail("未知动作：%s" % action)
	if state["phase"] != PHASE_OPPONENT_TURN:
		return _fail("当前阶段它不能行动：%s" % state["phase"])
	var opponent: Dictionary = state["opponent"]
	if opponent["done"]:
		return _fail("它本局已结束行动")
	if opponent["busted"]:
		return _fail("它已经爆牌，不能继续行动")

	if action == "STAND":
		opponent["done"] = true
		_advance_phase(WHO_OPPONENT)
		return _ok([{"type": "STAND", "who": WHO_OPPONENT}])

	var card := _take_card(WHO_OPPONENT, true)
	if card.is_empty():
		return _fail("牌靴已空")
	var new_events: Array = [{"type": "HIT", "who": WHO_OPPONENT, "card": card}]
	if BjHand.is_bust(opponent["hand"]):
		opponent["busted"] = true
		opponent["done"] = true
		new_events.append({
			"type": "BUST", "who": WHO_OPPONENT, "total": BjHand.value(opponent["hand"]),
		})
		_advance_phase(WHO_OPPONENT)
	return _ok(new_events)


## 玩家是不是"龙"：**≥5 张牌且没爆**。返回张数，0 = 不是。
##
## 民间 21 点的经典魔改：摸到 5 张还没爆就直接赢（五小龙），
## 6 张更狠（六小龙）。这里只算**玩家**的 —— 这是刻意的玩家向规则，
## 庄家侧（它）不享受这三条加成，否则"爽感"全被抵消。
func player_charlie() -> int:
	if state.is_empty() or not has_hand():
		return 0
	var hand := player_hand()
	if BjHand.is_bust(hand):
		return 0
	var count := hand.size()
	if count >= CHARLIE_CARDS_5:
		return count
	return 0


## 某一方结束行动之后，阶段该给谁。
##
## 先手轮换之后不能再写死"你停牌 → 它回合、它停牌 → 摊牌"了：
## 双方都完成才结算，否则把阶段交给**还没行动的那一方**。
func _advance_phase(_who: String) -> void:
	var player_done: bool = state["player"]["done"] or state["player"]["busted"]
	var opponent_done: bool = state["opponent"]["done"] or state["opponent"]["busted"]
	if player_done and opponent_done:
		state["phase"] = PHASE_SETTLE
	elif player_done:
		state["phase"] = PHASE_OPPONENT_TURN
	else:
		state["phase"] = PHASE_PLAYER_TURN


func _round_chips(value: float) -> int:
	# BJ 的 3:2 在奇数注下会出现 .5，筹码不允许有小数。
	return int(round(value))


## 摊牌结算。**零和**：你赢多少，它就输多少。
##
## 规则（单挑，双方对称）：
##   双方黑杰克 → 平局；一方黑杰克 → 赢 1.5 倍注
##   双方都爆 → 平局（没有庄家可以收钱）
##   一方爆 → 另一方赢；否则比点数，大者赢，相同为平局
##
## chips 不在下注时扣除，统一在这里按 delta 一次性增减 ——
## outcome 的语义就是 delta，两处都改会让人对不上账。
func settle() -> Dictionary:
	if state.is_empty():
		return _fail("这一局还没开始")
	if not state["outcome"].is_empty():
		return _fail("本局已结算")
	if state["phase"] == PHASE_PLAYER_TURN or state["phase"] == PHASE_OPPONENT_TURN:
		return _fail("当前阶段不可结算：%s" % state["phase"])

	var new_events: Array = []
	# 它的暗牌到摊牌才公开：这也是 running_count 只统计已公开牌的原因。
	new_events.append_array(_reveal_opponent())

	var player_total := BjHand.value(player_hand())
	var opponent_total := BjHand.value(opponent_hand())
	var player_bj := BjHand.is_blackjack(player_hand())
	var opponent_bj := BjHand.is_blackjack(opponent_hand())
	var player_busted := BjHand.is_bust(player_hand())
	var opponent_busted := BjHand.is_bust(opponent_hand())
	var amount: int = state["stake"]

	var player_delta := 0
	var reason := ""
	# 魔改倍率的结果（0 = 这次没有额外倍率）
	var bonus := ""
	var bonus_mult := 0.0
	var charlie := player_charlie()
	if player_bj and opponent_bj:
		player_delta = 0
		reason = "双方黑杰克"
	elif player_bj:
		player_delta = _round_chips(amount * BLACKJACK_PAYOUT)
		reason = "你黑杰克"
		bonus = "黑杰克"
		bonus_mult = BLACKJACK_PAYOUT
	elif opponent_bj:
		player_delta = -_round_chips(amount * BLACKJACK_PAYOUT)
		reason = "它黑杰克"
	elif player_busted and opponent_busted:
		player_delta = 0
		reason = "都爆了"
	elif player_busted:
		player_delta = -amount
		reason = "你爆牌"
	elif charlie >= CHARLIE_CARDS_6:
		# 六小龙：6 张不爆，2.5 倍（民间规则里比五小龙更稀罕，所以更狠）
		bonus = "六小龙"
		bonus_mult = CHARLIE_6_MULT
		player_delta = _round_chips(amount * bonus_mult)
		reason = "六小龙 %d 张" % charlie
	elif charlie >= CHARLIE_CARDS_5:
		bonus = "五小龙"
		bonus_mult = CHARLIE_5_MULT
		player_delta = _round_chips(amount * bonus_mult)
		reason = "五小龙 %d 张" % charlie
	elif opponent_busted:
		# 抓对方爆牌：1.2 倍（用户要的"抓庄家爆牌"收益）
		bonus = "抓它爆牌"
		bonus_mult = BUST_BONUS
		player_delta = _round_chips(amount * bonus_mult)
		reason = "它爆牌"
	elif player_total > opponent_total:
		player_delta = amount
		reason = "点数比较"
	elif player_total < opponent_total:
		player_delta = -amount
		reason = "点数比较"
	else:
		player_delta = 0
		reason = "点数比较"

	# 零和：它的 delta 恒等于你的相反数。
	# **桌上筹码规则**：输家只赔得出自己摆着的那些。
	# 满注 + 黑杰克（要赔 1.5 倍）时对方可能"赔穿"，那就把赔付压到它剩下的筹码 ——
	# 否则筹码会变成负数（400 局连打的单测就是这么抓到的）。
	if player_delta > 0:
		player_delta = mini(player_delta, opponent_chips)
	elif player_delta < 0:
		player_delta = -mini(-player_delta, player_chips)
	var opponent_delta := -player_delta
	var winner := "PUSH"
	if player_delta > 0:
		winner = WHO_PLAYER
	elif player_delta < 0:
		winner = WHO_OPPONENT

	var settled_outcome := {
		"winner": winner,
		"player_delta": player_delta,
		"opponent_delta": opponent_delta,
		"reason": reason,
		"player_total": player_total,
		"opponent_total": opponent_total,
		"stake": amount,
		"player_blackjack": player_bj,
		"opponent_blackjack": opponent_bj,
		"player_bust": player_busted,
		"opponent_bust": opponent_busted,
		"player_doubled": state["player"]["doubled"],
		"player_bet": amount,
		"opponent_bet": amount,
		"hand_no": state["hand_no"],
		# 魔改倍率：bonus 是给玩家看的名字（空 = 没触发），mult 是倍率
		"bonus": bonus,
		"bonus_mult": bonus_mult,
		"player_charlie": charlie,
	}

	player_chips += player_delta
	opponent_chips += opponent_delta
	state["phase"] = PHASE_SETTLE
	state["outcome"] = settled_outcome
	state["player"]["done"] = true
	state["opponent"]["done"] = true

	var settle_event := {"type": "SETTLE"}
	settle_event.merge(settled_outcome)
	new_events.append(settle_event)
	if player_delta != 0:
		new_events.append({
			"type": "CHIPS", "who": WHO_PLAYER,
			"from": player_chips - player_delta, "to": player_chips,
		})
		new_events.append({
			"type": "CHIPS", "who": WHO_OPPONENT,
			"from": opponent_chips - opponent_delta, "to": opponent_chips,
		})

	return _ok(new_events)


## 破产保护：任一方低于最小注就补回起始额度。返回是否发生了补币。
## （零和的代价：补币会让桌上总额增加，这是刻意的 —— 否则牌局会永久停摆。）
func top_up_if_broke() -> bool:
	var topped := false
	if player_chips < min_stake():
		player_chips = maxi(player_chips, STARTING_CHIPS)
		topped = true
	if opponent_chips < min_stake():
		opponent_chips = maxi(opponent_chips, STARTING_CHIPS)
		topped = true
	return topped


func outcome() -> Dictionary:
	if state.is_empty():
		return {}
	return state["outcome"]
