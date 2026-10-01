@tool
class_name BjTestPlea
extends McpTestSuite

## 输光之后：**自由对话**求情 + 心情值掷金额 + 欠条 + 还债。
##
## 这一套把"它肯不肯借、借多少"钉死成可验算的数值 ——
## 否则这就是个纯看脸的黑盒，玩家会觉得被骗。
##
## 分工也在这里体现：**算账全在本地**（心情值、金额、利息、还债都是纯函数），
## 模型/关键词只负责"她这句话说得像不像她"。

const Machine := preload("res://scripts/engine/bj_machine.gd")


func suite_name() -> String:
	return "plea"


func _rng(seed_value: int = 1234) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 一个"好脾气"的它：忌惮你、有底气、赢着钱、不记仇、不上头。
func _friendly() -> Dictionary:
	var p := BjPersona.empty()
	p["respect"] = 0.9
	p["confidence"] = 0.95
	p["net_chips"] = 400_000_000
	return p


## 一个"记仇又上头"的它。
func _hostile() -> Dictionary:
	var p := BjPersona.empty()
	p["respect"] = 0.0
	p["confidence"] = 0.3
	p["grudge"] = 0.9
	p["tilt"] = 0.9
	p["net_chips"] = -200_000_000
	return p


# ---------------------------------------------------------------- 判意图

func test_intent_of_reads_chinese_keywords() -> void:
	assert_eq(BjPlea.intent_of("我连底注都付不起了，行行好"), BjPlea.INTENT_BEG)
	assert_eq(BjPlea.intent_of("你打得比我想的稳，我服你"), BjPlea.INTENT_FLATTER)
	assert_eq(BjPlea.intent_of("怎么？不敢跟我打了？"), BjPlea.INTENT_TAUNT)
	assert_eq(BjPlea.intent_of("算我借的，双倍还你，欠条现在就写"), BjPlea.INTENT_DEAL)
	assert_eq(BjPlea.intent_of("你这杂鱼"), BjPlea.INTENT_INSULT)
	assert_eq(BjPlea.intent_of("我不还了你等着"), BjPlea.INTENT_THREAT)
	assert_eq(BjPlea.intent_of("今天天气不错"), BjPlea.INTENT_NONE)
	assert_eq(BjPlea.intent_of("   "), BjPlea.INTENT_NONE)


func test_intent_keywords_do_not_false_positive() -> void:
	# 回归：侮辱词里的"就这"曾经命中"就这样吧"，把一句好话判成骂它、一次扣 20 分。
	# 关键词是子串匹配，所以每个词都得经得起"别的意思顺带命中"的检验。
	assert_ne(BjPlea.intent_of("嗯……那个……就这样吧"), BjPlea.INTENT_INSULT)
	assert_eq(BjPlea.intent_of("嗯……那个……就这样吧"), BjPlea.INTENT_NONE)
	assert_ne(BjPlea.intent_of("我想想条件再说"), BjPlea.INTENT_INSULT)


func test_bad_lines_can_lose_softness() -> void:
	# 用户报的："无论说什么都会最低加 1 好感度，这是不对的"
	var persona := BjPersona.empty()
	persona["respect"] = 0.6
	persona["confidence"] = 0.7
	persona["grudge"] = 0.1
	persona["tilt"] = 0.2
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 没说到点上 → 扣分
	var st := BjPlea.start(persona, 100000000, 0)
	var before := int(st["softness"])
	st = BjPlea.say(st, "今天天气不错", persona, rng)
	var line: Dictionary = st["lines"][0]
	assert_true(int(line["delta"]) < 0, "没说到点上不该加分")
	assert_true(int(st["softness"]) < before)
	# 她不吃这套的话术 → 同样扣分（激将在她不上头、又不怕你的时候没用）
	var st2 := BjPlea.start(persona, 100000000, 0)
	st2 = BjPlea.say(st2, "怎么？不敢跟我打了？", persona, rng)
	assert_true(int((st2["lines"][0] as Dictionary)["delta"]) < 0, "她不吃这套就该倒扣")


func test_borrowing_gets_harder_every_time() -> void:
	var persona := BjPersona.empty()
	persona["respect"] = 0.6
	persona["confidence"] = 0.7
	var first := BjPlea.initial_softness(persona, 100000000, 0)
	var second := BjPlea.initial_softness(persona, 100000000, 1)
	var third := BjPlea.initial_softness(persona, 100000000, 2)
	assert_gt(first, second, "借过一次之后起点必须更低")
	assert_gt(second, third, "越借越难借")
	# 借到底也不会低于下限
	assert_true(BjPlea.initial_softness(persona, 100000000, 99) >= BjPlea.MIN_SOFTNESS)


func test_softness_bottoming_out_is_a_total_failure() -> void:
	# 心情扣光 → 她不想听了，直接终止对话、彻底失败（只能重开）
	var persona := BjPersona.empty()
	persona["grudge"] = 0.9
	persona["tilt"] = 0.8
	persona["respect"] = 0.0
	persona["confidence"] = 0.1
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var st := BjPlea.start(persona, 100000000, 0)
	var guard := 0
	while not bool(st["finished"]) and guard < 6:
		guard += 1
		st = BjPlea.say(st, "你就是个杂鱼", persona, rng)
	assert_true(bool(st["finished"]))
	assert_true(bool(st.get("failed", false)), "扣到底必须判彻底失败")
	assert_eq(int(st.get("amount", -1)), 0, "彻底失败不能借到钱")
	assert_false(bool(st["agreed"]))
	assert_true(str(st.get("verdict", "")) != "")


func test_intent_labels_cover_every_intent() -> void:
	for intent in [BjPlea.INTENT_BEG, BjPlea.INTENT_FLATTER, BjPlea.INTENT_TAUNT,
			BjPlea.INTENT_DEAL, BjPlea.INTENT_INSULT, BjPlea.INTENT_THREAT, BjPlea.INTENT_NONE]:
		assert_true(BjPlea.INTENT_LABELS.has(intent), "缺少 %s 的标签" % intent)
	for intent in [BjPlea.INTENT_BEG, BjPlea.INTENT_FLATTER, BjPlea.INTENT_TAUNT, BjPlea.INTENT_DEAL]:
		assert_true(BjPlea.QUICK_FILL.has(intent), "缺少 %s 的快捷模板" % intent)
		assert_true(BjPlea.REPLY_GOOD[intent].size() > 0)
		assert_true(BjPlea.REPLY_BAD[intent].size() > 0)


# ---------------------------------------------------------------- 心情值

func test_initial_softness_is_driven_by_persona() -> void:
	var full := Machine.STARTING_CHIPS
	assert_eq(BjPlea.initial_softness(BjPersona.empty(), full), 35)
	assert_gt(BjPlea.initial_softness(_friendly(), full), 60)
	assert_eq(BjPlea.initial_softness(_hostile(), full), BjPlea.MIN_SOFTNESS)
	assert_true(BjPlea.initial_softness(BjPersona.empty(), Machine.STARTING_CHIPS / 4)
		< BjPlea.initial_softness(BjPersona.empty(), full))


func test_affinity_reads_her_mood() -> void:
	var smug := BjPersona.empty()
	smug["confidence"] = 0.9
	smug["net_chips"] = 100_000_000
	assert_eq(BjPersona.mood(smug), "smug")
	assert_gt(BjPlea.affinity(BjPlea.INTENT_BEG, smug), 1.4)
	assert_gt(BjPlea.affinity(BjPlea.INTENT_FLATTER, smug), 1.0)
	assert_true(BjPlea.affinity(BjPlea.INTENT_FLATTER, _hostile()) <= 0.4)
	assert_gt(BjPlea.affinity(BjPlea.INTENT_TAUNT, _hostile()), 1.0)
	var wary := BjPersona.empty()
	wary["respect"] = 0.9
	assert_true(BjPlea.affinity(BjPlea.INTENT_TAUNT, wary) <= 0.5)
	assert_eq(BjPlea.affinity(BjPlea.INTENT_DEAL, _hostile()), 1.0)


# ---------------------------------------------------------------- 三轮自由对话

func test_saying_the_right_thing_moves_her() -> void:
	var rng := _rng(7)
	var state := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
	var before := int(state["softness"])
	state = BjPlea.say(state, "行行好，我输光了", _friendly(), rng)
	assert_gt(int(state["softness"]), before, "装可怜对好脾气的它应该有效")
	assert_eq(int(state["round"]), 1)
	assert_eq(state["lines"].size(), 1)
	var entry: Dictionary = state["lines"][0]
	assert_eq(entry["you"], "行行好，我输光了")
	assert_true(str(entry["her"]).length() > 0, "它必须回一句")


func test_insulting_her_backfires() -> void:
	var rng := _rng(9)
	var state := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
	var before := int(state["softness"])
	state = BjPlea.say(state, "你这杂鱼，快点借我", _friendly(), rng)
	assert_true(int(state["softness"]) < before, "骂它一定掉心情值")
	assert_eq(str(state["last_intent"]), BjPlea.INTENT_INSULT)


func test_threat_also_backfires() -> void:
	var state := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
	var before := int(state["softness"])
	state = BjPlea.say(state, "不借我就不还你钱", _friendly(), _rng(11))
	assert_true(int(state["softness"]) < before)


func test_empty_line_does_not_consume_a_turn() -> void:
	var state := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
	state = BjPlea.say(state, "   ", _friendly(), _rng(3))
	assert_eq(int(state["round"]), 0, "空话不该浪费一次机会")
	assert_eq(state["lines"].size(), 0)


func test_three_turns_then_she_decides() -> void:
	var rng := _rng(5)
	var state := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
	for i in range(BjPlea.ROUNDS):
		state = BjPlea.say(state, "行行好，借我点", _friendly(), rng)
	assert_true(bool(state["finished"]), "三轮之后必须表态")
	assert_eq(int(state["round"]), BjPlea.ROUNDS)
	# 第四句不再起作用
	var frozen := BjPlea.say(state, "再借点", _friendly(), rng)
	assert_eq(int(frozen["round"]), BjPlea.ROUNDS, "轮次不能超过 ROUNDS")
	assert_eq(frozen["lines"].size(), BjPlea.ROUNDS)


func test_state_is_immutable() -> void:
	var start := BjPlea.start(BjPersona.empty(), Machine.STARTING_CHIPS)
	var after := BjPlea.say(start, "行行好", BjPersona.empty(), _rng(2))
	assert_eq(int(start["round"]), 0, "say 不许改入参（纯函数）")
	assert_eq(int(after["round"]), 1)


func test_model_reply_overrides_the_canned_line() -> void:
	# 接真模型时：她说的话由模型给，但**心情值仍在本地算**
	var state := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
	var before := int(state["softness"])
	state = BjPlea.say(state, "行行好", _friendly(), _rng(4), "哼，就这一次。")
	assert_eq(str(state["last_reply"]), "哼，就这一次。")
	assert_gt(int(state["softness"]), before, "模型改不了账本")


# ---------------------------------------------------------------- 掷金额

func test_higher_mood_gives_more_on_average() -> void:
	var low_total := 0
	var high_total := 0
	var trials := 80
	for i in range(trials):
		var low := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
		low["softness"] = 15
		low = BjPlea._settle(low, _rng(1000 + i))
		var high := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
		high["softness"] = 95
		high = BjPlea._settle(high, _rng(1000 + i))
		low_total += int(low["amount"])
		high_total += int(high["amount"])
	assert_gt(high_total, low_total * 2,
		"心情高时给的总额必须明显更多（低 %d vs 高 %d）" % [low_total, high_total])
	assert_gt(high_total, 0)


func test_low_mood_often_refuses_outright() -> void:
	var refusals := 0
	for i in range(60):
		var state := BjPlea.start(_friendly(), Machine.STARTING_CHIPS)
		state["softness"] = 5
		state = BjPlea._settle(state, _rng(2000 + i))
		if int(state["amount"]) == 0:
			refusals += 1
	assert_gt(refusals, 20, "心情触底时经常一分不给（%d/60）" % refusals)


func test_amount_never_exceeds_what_she_has() -> void:
	for i in range(60):
		var poor := Machine.MIN_BET * 12      # 她只有 1200 万
		var state := BjPlea.start(BjPersona.empty(), poor)
		state["softness"] = 100
		state = BjPlea._settle(state, _rng(3000 + i))
		var amount := int(state["amount"])
		assert_true(amount <= BjPlea.loan_amount(poor), "借出额不能超过她的余力")
		assert_true(amount >= 0)
		# 她还得给自己留底注
		assert_true(poor - amount >= Machine.MIN_BET * 2 - 1, "借完必须还留得下底注")


func test_amount_is_rounded_to_ten_thousands() -> void:
	# 经济调小之后取整单位也跟着细：10 万（原来是百万）
	var state := BjPlea.start(BjPersona.empty(), Machine.STARTING_CHIPS * 3)
	state["softness"] = 70
	state = BjPlea._settle(state, _rng(77))
	var amount := int(state["amount"])
	assert_eq(amount % 100_000, 0, "金额要取整到十万，别出现零头")


func test_deal_raises_the_interest() -> void:
	var state := BjPlea.start(BjPersona.empty(), Machine.STARTING_CHIPS)
	assert_true(absf(float(state["interest"]) - BjPlea.BASE_INTEREST) < 0.001)
	state = BjPlea.say(state, "算我借的，双倍还你，欠条现在就写", BjPersona.empty(), _rng(3))
	assert_true(absf(float(state["interest"]) - (BjPlea.BASE_INTEREST + BjPlea.DEAL_INTEREST)) < 0.001,
		"谈条件必须涨利息")


func test_deal_terms_carry_interest() -> void:
	var state := BjPlea.start(BjPersona.empty(), Machine.STARTING_CHIPS * 2)
	state["softness"] = 100
	state = BjPlea._settle(state, _rng(4))
	var terms := BjPlea.deal_terms(state)
	assert_eq(int(terms["amount"]), int(state["amount"]))
	assert_eq(int(terms["debt"]),
		int(round(float(state["amount"]) * float(state["interest"]))))


func test_loan_comes_out_of_her_stack_and_keeps_her_playing() -> void:
	assert_eq(BjPlea.loan_amount(Machine.MIN_BET * 2), 0)
	assert_eq(BjPlea.loan_amount(Machine.MIN_BET * 3), Machine.MIN_BET)
	assert_false(BjPlea.can_lend(Machine.MIN_BET * 2))
	assert_true(BjPlea.can_lend(Machine.STARTING_CHIPS))
	assert_eq(BjPlea.loan_amount(Machine.STARTING_CHIPS * 5), BjPlea.MAX_LOAN)


# ---------------------------------------------------------------- 还债

func test_repayment_takes_half_of_the_winnings() -> void:
	var debt := Machine.MIN_BET * 10
	assert_eq(int(BjPlea.repayment(Machine.MIN_BET * 2, debt)["repay"]), Machine.MIN_BET)
	assert_eq(int(BjPlea.repayment(Machine.MIN_BET * 2, debt)["left"]), Machine.MIN_BET * 9)
	assert_eq(int(BjPlea.repayment(Machine.MIN_BET * 100, debt)["repay"]), debt)
	assert_eq(int(BjPlea.repayment(Machine.MIN_BET * 100, debt)["left"]), 0)
	assert_eq(int(BjPlea.repayment(-Machine.MIN_BET, debt)["repay"]), 0)
	assert_eq(int(BjPlea.repayment(Machine.MIN_BET, 0)["repay"]), 0)


func test_profile_keeps_the_debt() -> void:
	# 注意：这条测试会碰真实的存档文件，所以**先备份原文再还原** ——
	# 测试不许把真人正在玩的档案清掉。
	var backup := ""
	if FileAccess.file_exists(BjProfile.PROFILE_FILE):
		var file := FileAccess.open(BjProfile.PROFILE_FILE, FileAccess.READ)
		if file != null:
			backup = file.get_as_text()
			file.close()
	var profile := BjProfile.default_profile()
	assert_eq(int(profile["debt"]), 0, "新档案不该有欠条")
	profile["debt"] = 150_000_000
	assert_true(BjProfile.save_profile(profile))
	var loaded := BjProfile.load_profile()
	assert_eq(int(loaded["debt"]), 150_000_000, "欠条必须存得住")
	assert_eq(int(loaded["player_chips"]), Machine.STARTING_CHIPS)
	if backup != "":
		var restore := FileAccess.open(BjProfile.PROFILE_FILE, FileAccess.WRITE)
		if restore != null:
			restore.store_string(backup)
			restore.close()
		assert_eq(int(BjProfile.load_profile()["debt"]),
			int(JSON.parse_string(backup).get("debt", 0)), "存档必须原样还原")
