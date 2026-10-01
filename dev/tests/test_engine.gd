@tool
class_name BjTestEngine
extends McpTestSuite

## 规则引擎单测：牌 / 点数 / 牌靴 / 状态机 / 摊牌结算 / Hi-Lo。
##
## 这一套是"这游戏没有 bug"的地基：规则正确性用毫秒级单测锁死，
## 不受随机与 UI 影响。**单挑版**：没有庄家，双方同注，赢家拿走对方那份。

const Cards := preload("res://scripts/engine/bj_cards.gd")
const Hand := preload("res://scripts/engine/bj_hand.gd")
const Shoe := preload("res://scripts/engine/bj_shoe.gd")
const Machine := preload("res://scripts/engine/bj_machine.gd")


func suite_name() -> String:
	return "engine"


func _machine_with(ordered: String) -> BjMachine:
	var machine := BjMachine.new()
	machine.rng.seed = 20260929
	# 必须垫足牌：剩余低于 52 张会触发**换靴**，那样就把夹具牌序冲掉了。
	var cards := BjCards.parse_hand(ordered)
	while cards.size() < 100:
		cards.append(BjCards.make("2", "S"))
	machine.shoe = BjShoe.stacked(cards)
	return machine


# ---------------------------------------------------------------- 牌与点数

func test_rank_values() -> void:
	assert_eq(BjCards.rank_value("A"), 11)
	assert_eq(BjCards.rank_value("K"), 10)
	assert_eq(BjCards.rank_value("10"), 10)
	assert_eq(BjCards.rank_value("2"), 2)
	assert_eq(BjCards.full_deck().size(), 52)


func test_hand_totals_and_aces() -> void:
	assert_eq(BjHand.value(BjCards.parse_hand("SA SK")), 21)
	assert_eq(BjHand.value(BjCards.parse_hand("SA HA")), 12)
	assert_eq(BjHand.value(BjCards.parse_hand("SA HA DA")), 13)
	assert_eq(BjHand.value(BjCards.parse_hand("S10 H6 SA")), 17)


func test_soft_definitions_differ() -> void:
	assert_true(BjHand.is_soft(BjCards.parse_hand("S10 H6 SA")), "10+6+A 宽松口径应为软牌")
	assert_false(BjHand.has_soft_ace(BjCards.parse_hand("S10 H6 SA")), "10+6+A 严格口径应为硬牌")
	assert_true(BjHand.has_soft_ace(BjCards.parse_hand("SA H6")))
	assert_true(BjHand.is_soft(BjCards.parse_hand("SA H6")))


func test_blackjack_requires_two_cards() -> void:
	assert_true(BjHand.is_blackjack(BjCards.parse_hand("SA SK")))
	assert_false(BjHand.is_blackjack(BjCards.parse_hand("SA HA D9")))
	assert_true(BjHand.is_bust(BjCards.parse_hand("S10 H6 D9")))
	assert_false(BjHand.is_bust(BjCards.parse_hand("S10 HA")))


func test_display_text_marks_special_hands() -> void:
	assert_eq(BjHand.describe(BjCards.parse_hand("SA SK")), "21 点 · 黑杰克")
	assert_eq(BjHand.describe(BjCards.parse_hand("SA HA D9")), "21 点（软牌）")
	assert_eq(BjHand.describe(BjCards.parse_hand("S10 H9")), "19 点")
	assert_eq(BjHand.describe(BjCards.parse_hand("S10 H6 D9")), "25 点 · 爆牌")


func test_double_requires_two_cards() -> void:
	assert_true(BjHand.can_double(BjCards.parse_hand("S5 H6")))
	assert_false(BjHand.can_double(BjCards.parse_hand("S5 H6 D2")))


# ---------------------------------------------------------------- 牌靴

func test_shoe_geometry_and_reshuffle_threshold() -> void:
	var machine := BjMachine.new()
	machine.rng.seed = 12345
	machine.shoe = BjShoe.create(machine.rng)
	assert_eq(machine.shoe.cards.size(), 208)
	assert_false(machine.shoe.needs_reshuffle(), "满靴不该换靴")
	for i in range(157):
		machine.shoe.draw()
	assert_eq(machine.shoe.remaining(), 51)
	assert_true(machine.shoe.needs_reshuffle())


func test_shoe_shuffle_is_deterministic_with_seed() -> void:
	var first := BjShoe.create(_seeded(777))
	var second := BjShoe.create(_seeded(777))
	var same := true
	for i in range(first.cards.size()):
		if first.cards[i] != second.cards[i]:
			same = false
			break
	assert_true(same, "同一个种子必须洗出同一副牌（否则单测无法复现）")


func _seeded(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


# ---------------------------------------------------------------- 单挑的桌子

func test_table_has_no_dealer() -> void:
	# 单挑的核心：桌上只有你和它，没有任何"庄家"座位或机械补牌规则。
	var machine := _machine_with("SA H3 S4 C6")
	machine.start_hand(Machine.MIN_BET)
	assert_false(machine.state.has("dealer"), "单挑版不该有庄家座位")
	assert_false(machine.has_method("resolve_dealer"), "单挑版不该有庄家补牌")


func test_deal_order_is_fixed() -> void:
	# 发牌顺序：你明、它明、你明、它暗
	var machine := _machine_with("SA H3 S4 C6")
	var result := machine.start_hand(Machine.MIN_BET)
	assert_true(result["ok"], "开局应该成功")
	assert_eq(BjCards.hand_text(machine.player_hand()), "♠A ♠4")
	assert_eq(BjCards.hand_text(machine.opponent_hand()), "♥3 ♣6")
	assert_eq(machine.phase(), Machine.PHASE_PLAYER_TURN)
	assert_true(machine.opponent_hole_hidden(), "它的第二张必须是暗牌")
	assert_eq(machine.stake(), Machine.MIN_BET)
	assert_eq(machine.pot(), Machine.MIN_BET * 2, "底池 = 双方各押一份")


func test_chips_are_not_deducted_at_bet_time() -> void:
	var machine := _machine_with("SA H3 S4 C6")
	var before := machine.player_chips
	machine.start_hand(Machine.MIN_BET * 3)
	assert_eq(machine.player_chips, before, "下注时不扣筹码，摊牌时按 delta 一次增减")


func test_stake_validation() -> void:
	var machine := _machine_with("SA H3 S4 C6")
	var floor_bet := machine.min_stake()
	assert_contains(machine.start_hand(floor_bet - 1)["error"], "不能低于")
	# 上限：涨注的上限，同时被"双方里更穷那一边"压住（所以永远轮不到"跟不动"分支，
	# 这里只断言"超了就拒绝"）
	assert_contains(machine.start_hand(Machine.STARTING_CHIPS + 1)["error"], "不能高于")
	machine.opponent_chips = floor_bet * 3
	assert_contains(machine.start_hand(Machine.STARTING_CHIPS + 1)["error"], "不能高于")
	# 自己也押不起（注额压到她的上限以内，但仍然超过你的筹码）
	machine.opponent_chips = Machine.STARTING_CHIPS
	machine.player_chips = floor_bet * 3
	assert_contains(machine.start_hand(Machine.STARTING_CHIPS + 1)["error"], "不能高于")


func test_stake_ladder_grows_with_hands() -> void:
	# 下注每 10 局升一档，最大注 = 最小注 × 5
	var machine := BjMachine.new()
	machine.player_chips = Machine.STARTING_CHIPS
	machine.opponent_chips = Machine.STARTING_CHIPS
	assert_eq(machine.stake_level(), 0)
	assert_eq(machine.min_stake(), Machine.MIN_BET, "开局最小注就是基准值")
	assert_eq(machine.max_stake(), Machine.MIN_BET * BjMachine.MAX_STAKE_MULTIPLIER)
	var first := machine.min_stake()
	machine.hand_no = BjMachine.STAKE_HANDS_PER_LEVEL
	assert_eq(machine.stake_level(), 1)
	assert_gt(machine.min_stake(), first, "第 10 局起底注要涨")
	# 涨到顶就不再涨了（否则会溢出整数区间）
	machine.hand_no = 100_000
	assert_eq(machine.stake_level(), BjMachine.STAKE_MIN_STEPS.size() - 1)
	assert_eq(machine.min_stake(), BjMachine.STAKE_MIN_STEPS[-1])
	assert_eq(machine.max_stake(), Machine.STARTING_CHIPS, "上限还是被筹码压住")


func test_max_stake_is_limited_by_both_sides() -> void:
	var machine := BjMachine.new()
	machine.player_chips = Machine.MIN_BET * 7
	machine.opponent_chips = Machine.MIN_BET * 4
	assert_eq(machine.max_stake(), Machine.MIN_BET * 4, "注额上限由筹码少的一方决定")


func test_player_blackjack_skips_player_turn() -> void:
	var machine := _machine_with("SA H3 SK C6")
	machine.start_hand(Machine.MIN_BET)
	assert_eq(machine.phase(), Machine.PHASE_OPPONENT_TURN, "天然黑杰克直接进它的回合")
	assert_eq(machine.legal_actions().size(), 0, "黑杰克时你没有可行动作")
	assert_true(machine.state["player"]["blackjack"])


# ---------------------------------------------------------------- 你的动作

func test_player_action_guards() -> void:
	var machine := _machine_with("SA H3 S4 C6")
	assert_false(machine.player_action("HIT")["ok"], "没开局时不该能行动")
	machine.start_hand(Machine.MIN_BET)
	assert_false(machine.player_action("SPLIT")["ok"], "分牌不在范围里，必须被拒")
	machine.player_action("STAND")
	assert_eq(machine.phase(), Machine.PHASE_OPPONENT_TURN)
	assert_false(machine.player_action("HIT")["ok"], "轮到它时你不能再动")


func test_double_doubles_the_stake_for_both_sides() -> void:
	var machine := _machine_with("S5 S9 S6 S9 S10")
	machine.start_hand(Machine.MIN_BET * 2)
	var result := machine.player_action("DOUBLE")
	assert_true(result["ok"])
	assert_eq(machine.stake(), Machine.MIN_BET * 4, "加注把双方注额一起翻倍")
	assert_eq(machine.player_hand().size(), 3, "加注只发恰好一张")
	assert_true(machine.state["player"]["done"], "加注后自动停牌")
	assert_eq(machine.phase(), Machine.PHASE_OPPONENT_TURN)
	# DOUBLE 事件后面必须紧跟一张 HIT 事件，否则前端重放不出这张牌
	var types: Array = []
	for event in result["events"]:
		types.append(event["type"])
	assert_eq(types, ["DOUBLE", "HIT"])


func test_double_needs_both_sides_to_cover() -> void:
	# 注额 200 万、翻倍要 400 万，它只有 300 万 → 跟不动，加注根本不该出现在可选动作里
	var machine := _machine_with("S5 S9 S6 S9 S10")
	machine.opponent_chips = Machine.MIN_BET * 3
	machine.start_hand(Machine.MIN_BET * 2)
	assert_false(machine.legal_actions().has("DOUBLE"), "它跟不动时不给加注按钮")
	assert_contains(str(machine.player_action("DOUBLE").get("error", "")), "跟不动")


func test_hit_bust_ends_turn() -> void:
	var machine := _machine_with("S10 H3 S6 C6 SK")
	machine.start_hand(Machine.MIN_BET)
	assert_eq(BjHand.value(machine.player_hand()), 16)
	assert_true(machine.player_action("HIT")["ok"])
	assert_true(machine.state["player"]["busted"], "拿到 K 应该爆牌")
	assert_eq(machine.phase(), Machine.PHASE_OPPONENT_TURN, "爆牌立即结束你的行动")
	assert_eq(machine.legal_actions().size(), 0)


# ---------------------------------------------------------------- ALL IN

func test_all_in_ignores_the_bet_cap() -> void:
	var machine := BjMachine.new()
	machine.player_chips = 200_000_000
	machine.opponent_chips = 200_000_000
	# 普通上限是"下注最大注"，ALL IN 直接越过它
	assert_eq(machine.max_stake(), machine.min_stake() * BjMachine.MAX_STAKE_MULTIPLIER)
	assert_eq(machine.all_in_stake(), 200_000_000, "ALL IN 不该被最大注卡住")
	# 对注制：谁更穷就以谁为准
	machine.opponent_chips = 30_000_000
	assert_eq(machine.all_in_stake(), 30_000_000)
	assert_true(machine.can_all_in())
	# 校验：正好全押合法，再多一个 token 就不合法
	assert_eq(machine.validate_stake(machine.all_in_stake()), "")
	assert_true(machine.validate_stake(machine.all_in_stake() + 1) != "")
	# 对方连最小注都开不起 → 不能全押
	machine.opponent_chips = BjMachine.MIN_BET - 1
	assert_false(machine.can_all_in())


func test_all_in_hand_takes_everything_from_the_loser() -> void:
	# 一把梭：双方各出 min(筹码)，输的一方直接见底（下注时不扣，摊牌按 delta 结算）
	var machine := _machine_with("S10 S7 S9 S5")   # 你 19，它 12
	machine.player_chips = 90_000_000
	machine.opponent_chips = 60_000_000
	var stake := machine.all_in_stake()
	assert_eq(stake, 60_000_000, "全押额度由更穷的一方决定")
	assert_true(bool(machine.start_hand(stake)["ok"]))
	assert_eq(machine.pot(), stake * 2, "底池是双方各押一份")

	machine.player_action("STAND")
	machine.opponent_action("STAND")
	assert_true(machine.settle()["ok"])
	var outcome := machine.outcome()
	assert_eq(str(outcome["winner"]), "PLAYER")
	assert_eq(machine.player_chips, 90_000_000 + stake)
	assert_eq(machine.opponent_chips, 0, "它的家底被一把清空")
	assert_true(machine.opponent_chips < BjMachine.MIN_BET, "这一步之后就该进破产流程了")


func test_double_is_not_all_in() -> void:
	# 加倍只翻倍**当前注额**，不会顺手把你变成全押
	var machine := _machine_with("S10 S7 S9 S5")
	machine.player_chips = 200_000_000
	machine.opponent_chips = 200_000_000
	machine.start_hand(BjMachine.MAX_BET)
	machine.player_action("DOUBLE")
	assert_eq(machine.stake(), BjMachine.MAX_BET * 2, "加倍后注额翻倍")
	assert_true(machine.stake() < machine.all_in_stake(), "加倍 ≠ 全押")


# ---------------------------------------------------------------- 摊牌

func test_settle_player_wins_by_points() -> void:
	var machine := _machine_with("S10 S8 S9 S9")   # 你 19，它 17
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	assert_true(machine.settle()["ok"])
	var outcome := machine.outcome()
	assert_eq(outcome["player_delta"], Machine.MIN_BET)
	assert_eq(outcome["reason"], "点数比较")
	assert_eq(machine.player_chips, Machine.STARTING_CHIPS + Machine.MIN_BET)
	assert_eq(machine.opponent_chips, Machine.STARTING_CHIPS - Machine.MIN_BET)


func test_settle_is_zero_sum() -> void:
	# 这是单挑最重要的性质：你赢的每一分都是它的
	var machine := _machine_with("S10 S8 S9 S9")
	var before := machine.player_chips + machine.opponent_chips
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	machine.settle()
	assert_eq(machine.player_chips + machine.opponent_chips, before,
		"筹码必须严格零和（没有庄家可以吞钱）")
	assert_eq(machine.outcome()["player_delta"], -machine.outcome()["opponent_delta"])


func test_settle_player_bust() -> void:
	var machine := _machine_with("S10 S9 S6 S7 S10")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("HIT")
	machine.opponent_action("STAND")
	machine.settle()
	assert_eq(machine.outcome()["player_delta"], -Machine.MIN_BET)
	assert_eq(machine.outcome()["reason"], "你爆牌")


func test_settle_opponent_bust() -> void:
	# 它爆牌 → 你赢，而且现在有**1.2 倍加成**（魔改："抓它爆牌"）
	var machine := _machine_with("S10 S9 S9 S7 S10")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	machine.opponent_action("HIT")
	machine.settle()
	assert_true(machine.outcome()["opponent_bust"])
	assert_eq(machine.outcome()["reason"], "它爆牌")
	assert_eq(str(machine.outcome()["bonus"]), "抓它爆牌")
	assert_eq(machine.outcome()["player_delta"],
		int(round(float(Machine.MIN_BET) * BjMachine.BUST_BONUS)))


func test_settle_both_bust_is_a_push() -> void:
	# 没有庄家可以收钱：两个人都爆 → 谁也没拿到
	var machine := _machine_with("S10 S10 S6 S6 S10 S10")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("HIT")
	machine.opponent_action("HIT")
	machine.settle()
	assert_true(machine.outcome()["player_bust"])
	assert_true(machine.outcome()["opponent_bust"])
	assert_eq(machine.outcome()["player_delta"], 0)
	assert_eq(machine.outcome()["reason"], "都爆了")
	assert_eq(machine.outcome()["winner"], "PUSH")


func test_settle_push_on_equal_totals() -> void:
	var machine := _machine_with("S10 S9 S9 S10")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	machine.settle()
	assert_eq(machine.outcome()["player_delta"], 0)
	assert_eq(machine.player_chips, Machine.STARTING_CHIPS)


func test_settle_blackjack_pays_three_to_two() -> void:
	var machine := _machine_with("SA H3 SK C6")
	var stake := Machine.MIN_BET * 2
	machine.start_hand(stake)
	machine.opponent_action("STAND")
	machine.settle()
	assert_eq(machine.outcome()["player_delta"], int(round(float(stake) * 1.5)))
	assert_eq(machine.outcome()["reason"], "你黑杰克")


func test_settle_opponent_blackjack_is_symmetric() -> void:
	# 单挑里它也有黑杰克待遇 —— 双方对称，不存在"对手没有黑杰克"那种单方面规则
	var machine := _machine_with("S3 HA C6 HK")
	var stake := Machine.MIN_BET * 2
	machine.start_hand(stake)
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	machine.settle()
	assert_true(machine.outcome()["opponent_blackjack"])
	assert_eq(machine.outcome()["player_delta"], -int(round(float(stake) * 1.5)))
	assert_eq(machine.outcome()["reason"], "它黑杰克")


func test_settle_both_blackjack_is_a_push() -> void:
	var machine := _machine_with("SA HA SK HK")
	machine.start_hand(Machine.MIN_BET * 2)
	machine.opponent_action("STAND")
	machine.settle()
	assert_eq(machine.outcome()["player_delta"], 0)
	assert_eq(machine.outcome()["reason"], "双方黑杰克")


func test_settle_twice_is_rejected() -> void:
	var machine := _machine_with("S10 S8 S9 S9")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	assert_true(machine.settle()["ok"])
	assert_false(machine.settle()["ok"], "同一局不能结算两次（否则筹码会凭空翻倍）")


func test_settle_reveals_opponent_hole_card() -> void:
	var machine := _machine_with("S10 S8 S9 S9")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	assert_true(machine.opponent_hole_hidden())
	machine.settle()
	assert_false(machine.opponent_hole_hidden(), "摊牌必须翻开它的暗牌")


func test_first_actor_alternates_every_hand() -> void:
	# 用户要的"轮流"：第 1 局你先，第 2 局它先，第 3 局又你先。
	var machine := _machine_with("S10 S8 S9 S7 S6 S5 S4 S3")
	machine.player_chips = Machine.STARTING_CHIPS
	machine.opponent_chips = Machine.STARTING_CHIPS

	machine.start_hand(machine.min_stake())                 # 第 1 局
	assert_eq(machine.state["first_actor"], Machine.WHO_PLAYER)
	assert_eq(machine.phase(), Machine.PHASE_PLAYER_TURN, "第 1 局你先")
	machine.player_action("STAND")
	assert_eq(machine.phase(), Machine.PHASE_OPPONENT_TURN, "你打完才轮到它")
	machine.opponent_action("STAND")
	assert_eq(machine.phase(), Machine.PHASE_SETTLE)
	machine.settle()

	machine.start_hand(machine.min_stake())                 # 第 2 局
	assert_eq(machine.state["first_actor"], Machine.WHO_OPPONENT)
	assert_eq(machine.phase(), Machine.PHASE_OPPONENT_TURN, "第 2 局它先手")
	assert_false(machine.opponent_hole_hidden(), "它先手时暗牌开局就是明的")
	machine.opponent_action("STAND")
	assert_eq(machine.phase(), Machine.PHASE_PLAYER_TURN, "它打完才轮到你")
	machine.player_action("STAND")
	assert_eq(machine.phase(), Machine.PHASE_SETTLE, "双方都完成才结算")

	machine.settle()
	var third := machine.start_hand(machine.min_stake())     # 第 3 局
	assert_true(third["ok"], "第 3 局开局失败：%s" % str(third.get("error", "")))
	assert_eq(machine.state.get("first_actor", "?"), Machine.WHO_PLAYER,
		"又轮到你（hand_no=%d，实际=%s）" % [
			machine.hand_no, str(machine.state.get("first_actor", "?"))])


# ---------------------------------------------------------------- 魔改倍率

## 叠一副"玩家连摸低牌"的靴：你能拿到 5 张 2（10 点，绝不爆）。
func _charlie_shoe() -> BjMachine:
	return _machine_with("S2 H10 S2 D10 S2 C2 S2 S2 S2 S2")


func test_bust_bonus_pays_one_point_two() -> void:
	# 它爆、你没爆 → 1.2 倍（下注 100 拿 220）
	var machine := _machine_with("S10 H10 S9 D6 S10")
	machine.start_hand(machine.min_stake())
	machine.player_action("STAND")
	machine.opponent_action("HIT")      # 它 16 → 摸到 10 爆掉（26）
	assert_true(machine.state["opponent"]["busted"], "它应该爆了")
	machine.settle()
	var outcome := machine.outcome()
	assert_eq(str(outcome["bonus"]), "抓它爆牌")
	assert_eq(int(outcome["player_delta"]),
		int(round(float(machine.min_stake()) * BjMachine.BUST_BONUS)))


func test_five_card_charlie_pays_double() -> void:
	var machine := _charlie_shoe()
	var stake := machine.min_stake()
	machine.start_hand(stake)
	machine.player_action("HIT")
	machine.player_action("HIT")
	machine.player_action("HIT")        # 第 5 张
	assert_eq(machine.player_charlie(), 5)
	# 关键：第 5 张**不该**自动停牌，否则六小龙永远拿不到
	assert_false(machine.state["player"]["done"], "五小龙之后必须还能继续要牌")
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	machine.settle()
	var outcome := machine.outcome()
	assert_eq(str(outcome["bonus"]), "五小龙")
	assert_eq(int(outcome["player_delta"]), int(round(float(stake) * BjMachine.CHARLIE_5_MULT)))


func test_six_card_charlie_pays_two_point_five() -> void:
	var machine := _charlie_shoe()
	var stake := machine.min_stake()
	machine.start_hand(stake)
	for i in range(4):
		machine.player_action("HIT")
	assert_eq(machine.player_charlie(), 6)
	assert_true(machine.state["player"]["done"], "第六张到手应该自动停牌")
	machine.opponent_action("STAND")
	machine.settle()
	var outcome := machine.outcome()
	assert_eq(str(outcome["bonus"]), "六小龙")
	assert_eq(int(outcome["player_delta"]), int(round(float(stake) * BjMachine.CHARLIE_6_MULT)))


func test_charlie_beats_a_plain_twenty() -> void:
	# 民间规则：五小龙直接赢，哪怕对方点数更高（黑杰克除外）
	var machine := _charlie_shoe()
	var stake := machine.min_stake()
	machine.start_hand(stake)
	for i in range(3):
		machine.player_action("HIT")
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	machine.settle()
	var outcome := machine.outcome()
	assert_eq(str(outcome["winner"]), Machine.WHO_PLAYER, "五小龙该赢过普通点数")
	assert_eq(str(outcome["bonus"]), "五小龙")


func test_busted_hand_is_not_a_charlie() -> void:
	# 5 张但爆了 → 没有倍率（"≤21"是硬条件）
	var machine := _machine_with("S10 H10 S10 D6 S10 C10 S10 S9")
	machine.start_hand(machine.min_stake())
	for i in range(3):
		machine.player_action("HIT")
	assert_true(machine.state["player"]["busted"], "这一手应该爆")
	assert_eq(machine.player_charlie(), 0, "爆了就不是龙")
	machine.opponent_action("STAND")
	machine.settle()
	assert_eq(float(machine.outcome()["bonus_mult"]), 0.0)


# ---------------------------------------------------------------- Hi-Lo

func test_hi_lo_counts_only_face_up_cards() -> void:
	var machine := _machine_with("S10 H3 S9 C6")
	machine.start_hand(Machine.MIN_BET)
	# 明牌：♠10(-1) ♥3(+1) ♠9(0) = 0；它的暗牌 ♣6 不计
	assert_eq(machine.running_count, 0, "只有公开的牌才计入 Hi-Lo")
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	machine.settle()
	# 摊牌翻开 ♣6 → +1
	assert_eq(machine.running_count, 1, "暗牌翻开后才计入")


func test_hi_lo_survives_across_hands() -> void:
	# 这是**修掉的原版 bug**：原版每局都把计数清零
	var machine := _machine_with("S10 H3 S9 C6 S7 H8 S6 C4")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	machine.opponent_action("STAND")
	machine.settle()
	var after_first := machine.running_count
	machine.start_hand(Machine.MIN_BET)
	assert_ne(machine.running_count, 0, "计数必须跨局延续（原版这里是 0）")
	assert_gt(machine.running_count, after_first, "第二局的明牌要在上一局的计数上继续累加")


func test_reshuffle_resets_count() -> void:
	var machine := BjMachine.new()
	machine.rng.seed = 42
	var few: Array = []
	for i in range(10):
		few.append(BjCards.make("2", "S"))
	machine.shoe = BjShoe.stacked(few)
	machine.running_count = 7
	assert_true(machine.shoe.needs_reshuffle())
	machine.start_hand(Machine.MIN_BET)
	assert_eq(machine.shoe.cards.size(), 208, "低于阈值必须换靴")
	assert_true(machine.running_count <= 4, "换靴后计数必须归零重算（新靴只算了这 3 张明牌）")


func test_empty_shoe_draw_is_safe() -> void:
	var shoe := BjShoe.stacked([])
	assert_eq(shoe.remaining(), 0)
	assert_true(shoe.draw().is_empty(), "空靴发牌必须安全返回")


# ---------------------------------------------------------------- 破产保护

func test_top_up_when_broke() -> void:
	var machine := BjMachine.new()
	machine.player_chips = 0
	assert_true(machine.top_up_if_broke())
	assert_eq(machine.player_chips, Machine.STARTING_CHIPS)
