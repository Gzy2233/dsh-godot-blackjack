@tool
class_name BjTestSim
extends McpTestSuite

## 无头连打：**牌局永远不会卡死** + 筹码严格零和。
##
## 单挑版的性质比原版更强：没有庄家，你赢的每一分都是它输的。
## 所以这里能断言"双方筹码之和**恒定**"（补币除外）—— 原版是三方桌，
## 钱会流进/流出庄家，做不到这条。

const Machine := preload("res://scripts/engine/bj_machine.gd")

## 与 BjGame.OPPONENT_LOOP_CAP 保持一致（它单局行动次数上限）。
const OPPONENT_LOOP_CAP := 20


func suite_name() -> String:
	return "sim"


func _machine_with(ordered: String, pad: int = 100) -> BjMachine:
	var machine := BjMachine.new()
	machine.rng.seed = 20260929
	var cards := BjCards.parse_hand(ordered)
	while cards.size() < pad:
		cards.append(BjCards.make("2", "S"))
	machine.shoe = BjShoe.stacked(cards)
	return machine


## 打完这一局：**谁先手都行**。
##
## 先手轮换之后不能再写死"先打你、再打它"了（偶数局是它先手）。
## 这里按阶段循环，谁该动就动谁，直到进入摊牌。
func _play_hand(machine: BjMachine, brain: BjBrainLocal) -> Dictionary:
	var cap_hits := 0
	var stuck := 0
	var guard := 0
	while machine.phase() != Machine.PHASE_SETTLE and guard < 60:
		guard += 1
		if machine.phase() == Machine.PHASE_PLAYER_TURN:
			_play_player(machine)
		elif machine.phase() == Machine.PHASE_OPPONENT_TURN:
			var turn := _play_opponent(machine, brain)
			if bool(turn["capped"]):
				cap_hits += 1
			if bool(turn["stuck"]):
				stuck += 1
		else:
			break
	if machine.phase() != Machine.PHASE_SETTLE:
		stuck += 1
	return {"capped": cap_hits > 0, "stuck": stuck > 0}


## 你这一手的打法（模拟一个"会打牌的人"）：不到 17 点就继续要。
func _play_player(machine: BjMachine) -> void:
	var guard := 0
	while machine.phase() == Machine.PHASE_PLAYER_TURN and guard < 30:
		guard += 1
		var action := "HIT" if BjHand.value(machine.player_hand()) < 17 else "STAND"
		if not machine.legal_actions().has(action):
			action = "STAND"
		machine.player_action(action)


## 它的回合：每轮重新构建视野（这条曾经是 bug），带回合上限与强制停牌保险丝。
func _play_opponent(machine: BjMachine, brain: BjBrainLocal) -> Dictionary:
	var actions := 0
	while machine.phase() == Machine.PHASE_OPPONENT_TURN and actions < OPPONENT_LOOP_CAP:
		actions += 1
		var view := BjGame.view_of(machine, "", "")
		var decision: Dictionary = brain.decide_now(view, ["HIT", "STAND"])
		if not machine.opponent_action(str(decision["action"]))["ok"]:
			machine.opponent_action("STAND")
	var capped := machine.phase() == Machine.PHASE_OPPONENT_TURN
	if capped:
		machine.opponent_action("STAND")
	return {"actions": actions, "capped": capped, "stuck": machine.phase() == Machine.PHASE_OPPONENT_TURN}


func test_play_many_hands_without_freezing() -> void:
	var machine := BjMachine.new()
	machine.rng.seed = 20260929
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	brain.think_scale = 0.0
	var persona := BjPersona.empty()

	var cap_hits := 0
	var stuck := 0
	var conservation_breaks := 0
	var negative_chips := 0
	var hands := 400

	for hand in range(hands):
		# 下注跟着下注走：始终押"两倍底注"，但不超过当前最大注
		var stake: int = mini(machine.min_stake() * 2, machine.max_stake())
		var started := machine.start_hand(stake)
		assert_true(started["ok"], "第 %d 局开不了局：%s" % [hand, str(started.get("error", ""))])
		if not started["ok"]:
			return

		var played := _play_hand(machine, brain)
		if bool(played["capped"]):
			cap_hits += 1
		if bool(played["stuck"]):
			stuck += 1

		var before := machine.player_chips + machine.opponent_chips
		var settled := machine.settle()
		assert_true(settled["ok"], "第 %d 局结算失败：%s" % [hand, str(settled.get("error", ""))])
		if not settled["ok"]:
			return
		var outcome := machine.outcome()
		var after := machine.player_chips + machine.opponent_chips
		# 零和：双方筹码之和必须一点不差（补币会在下一行破坏它，所以先断言）
		if after != before:
			conservation_breaks += 1
		if int(outcome["player_delta"]) != -int(outcome["opponent_delta"]):
			conservation_breaks += 1
		if machine.player_chips < 0 or machine.opponent_chips < 0:
			negative_chips += 1
		persona = BjPersona.absorb(persona, outcome)
		machine.top_up_if_broke()

	assert_eq(cap_hits, 0, "它的回合数不该触顶（触顶说明它在原地打转）")
	assert_eq(stuck, 0, "不允许任何一局卡在它的回合")
	assert_eq(conservation_breaks, 0, "筹码必须严格零和")
	assert_eq(negative_chips, 0, "筹码不允许变成负数")
	assert_eq(machine.hand_no, hands, "局号必须严格递增")
	assert_eq(persona["hands_played"], hands)


func test_persona_stays_in_range_after_long_session() -> void:
	var machine := BjMachine.new()
	machine.rng.seed = 4242
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	brain.think_scale = 0.0
	var persona := BjPersona.empty()
	for hand in range(120):
		if not machine.start_hand(mini(machine.min_stake() * 2, machine.max_stake()))["ok"]:
			return
		_play_hand(machine, brain)
		machine.settle()
		persona = BjPersona.absorb(persona, machine.outcome())
		machine.top_up_if_broke()

	for key in ["tilt", "respect", "confidence", "grudge"]:
		assert_true(float(persona[key]) >= 0.0 and float(persona[key]) <= 1.0,
			"%s 跑偏了：%f" % [key, float(persona[key])])
	# 摘要与最近记录都要有上限，否则存档会无限膨胀
	assert_true(persona["recent"].size() <= 8)
	assert_true(str(persona["summary"]).length() <= 300)
	assert_eq(int(persona["wins"]) + int(persona["losses"]) + int(persona["pushes"]), 120)


func test_view_reflects_the_live_board() -> void:
	# 回归测试：它的回合里视野**必须每轮重建**。
	# 曾经把视野算一次就在循环里反复用，结果它拿着 20 点还在要牌直到爆。
	var machine := _machine_with("S5 H9 S6 C7")
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")

	var before := BjGame.view_of(machine, "", "")
	machine.opponent_action("HIT")
	var after := BjGame.view_of(machine, "", "")
	assert_eq(after["opponent_hand"].size(), before["opponent_hand"].size() + 1,
		"视野里的手牌必须跟着真实手牌走")
	assert_ne(after["opponent_total"], before["opponent_total"],
		"重建视野后点数必须变化（算一次就复用会让它照着旧点数出牌）")


func test_view_hides_the_shoe() -> void:
	# 隐藏信息的边界：视野里只有"牌靴还剩几张"，没有牌靴内容
	var machine := _machine_with("S5 H9 S6 C7")
	machine.start_hand(Machine.MIN_BET)
	var view := BjGame.view_of(machine, "", "")
	assert_true(view.has("shoe_remaining"))
	assert_false(view.has("shoe"))
	assert_false(view.has("shoe_cards"))
	assert_false(view.has("next_card"))


func test_opponent_never_hits_when_ahead() -> void:
	# 它看得见你的点数：领先时再要牌就是"照着旧视野出牌"的症状
	var machine := BjMachine.new()
	machine.rng.seed = 11
	# 你 16（S10+S6），它 19（S9+S10）
	var cards := BjCards.parse_hand("S10 S9 S6 S10 S2 D3 H4 C5")
	while cards.size() < 100:
		cards.append(BjCards.make("2", "S"))
	machine.shoe = BjShoe.stacked(cards)
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	brain.think_scale = 0.0
	machine.start_hand(Machine.MIN_BET)
	machine.player_action("STAND")
	assert_eq(BjHand.value(machine.player_hand()), 16)
	assert_eq(BjHand.value(machine.opponent_hand()), 19)

	var steps := 0
	var wrong_hits := 0
	while machine.phase() == Machine.PHASE_OPPONENT_TURN and steps < OPPONENT_LOOP_CAP:
		steps += 1
		var view := BjGame.view_of(machine, "", "")
		var action := str(brain.decide_now(view, ["HIT", "STAND"])["action"])
		if int(view["opponent_total"]) > int(view["player_total"]) and action == "HIT":
			wrong_hits += 1
		if not machine.opponent_action(action)["ok"]:
			break
	assert_eq(wrong_hits, 0, "领先时不允许再要牌")
	assert_eq(steps, 1, "领先就一步停手")
	assert_eq(BjHand.value(machine.opponent_hand()), 19)


func test_stake_never_exceeds_either_stack() -> void:
	var machine := BjMachine.new()
	machine.rng.seed = 31337
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	brain.think_scale = 0.0
	machine.opponent_chips = Machine.MIN_BET * 3
	var persona := BjPersona.empty()
	persona["confidence"] = 1.0
	for i in range(40):
		var stake: int = mini(machine.min_stake() * 3, machine.max_stake())
		assert_true(stake >= machine.min_stake())
		assert_true(stake <= machine.player_chips)
		assert_true(stake <= machine.opponent_chips)
		if not machine.start_hand(stake)["ok"]:
			return
		_play_hand(machine, brain)
		machine.settle()
		persona = BjPersona.absorb(persona, machine.outcome())
		machine.top_up_if_broke()
