@tool
class_name BjTestPersona
extends McpTestSuite

## 人格 / 演出 / 台词 / 筹码格式化 单测。
##
## 这一层是"它像不像一个对手"的所在，数值公式必须逐条锁死：
## 改一个系数，鲸鱼娘的性格就变了。

const Machine := preload("res://scripts/engine/bj_machine.gd")


func suite_name() -> String:
	return "persona"


func _result(overrides: Dictionary) -> Dictionary:
	var base := {
		"winner": "PLAYER",
		"player_delta": Machine.MIN_BET,
		"opponent_delta": -Machine.MIN_BET,
		"player_total": 20,
		"opponent_total": 18,
		"player_bet": Machine.MIN_BET,
		"player_doubled": false,
		"player_blackjack": false,
		"player_bust": false,
		"hand_no": 1,
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	return base


## 鲸鱼娘赢（它的 P&L 为正）。
func _whale_win(overrides: Dictionary = {}) -> Dictionary:
	var merged := {"winner": "OPPONENT", "player_delta": -Machine.MIN_BET,
		"opponent_delta": Machine.MIN_BET}
	for key in overrides.keys():
		merged[key] = overrides[key]
	return _result(merged)


## 鲸鱼娘输（你赢）。
func _whale_loss(overrides: Dictionary = {}) -> Dictionary:
	return _result(overrides)


# ---------------------------------------------------------------- 人格

func test_empty_persona_defaults() -> void:
	var persona := BjPersona.empty()
	assert_eq(persona["hands_played"], 0)
	assert_eq(persona["confidence"], 0.5)
	assert_eq(persona["tilt"], 0.0)
	assert_eq(persona["grudge"], 0.0)
	assert_eq(persona["recent"].size(), 0)
	assert_false(persona["player_profile"]["aggressive"])


func test_absorb_win_and_loss_drive_tilt() -> void:
	# 它赢：拿到赢的宽慰，tilt 不涨；胜率 EWMA 抬高底气
	var winner := BjPersona.absorb(BjPersona.empty(), _whale_win())
	assert_eq(winner["hands_played"], 1)
	assert_eq(winner["wins"], 1)
	assert_eq(winner["losses"], 0)
	assert_eq(winner["tilt"], 0.0)
	# 0.5*0.7 + 1.0*0.3 在浮点下是 0.6499999…，所以用近似比较
	assert_true(absf(float(winner["confidence"]) - 0.65) < 0.000001,
		"胜率 EWMA 应为 0.65，实际 %f" % float(winner["confidence"]))
	# 它输：一次满档亏损 +0.35 的上头，底气掉到 0.35
	var loser := BjPersona.absorb(BjPersona.empty(), _whale_loss())
	assert_eq(loser["losses"], 1)
	assert_eq(loser["wins"], 0)
	assert_eq(loser["tilt"], 0.35)
	assert_true(absf(float(loser["confidence"]) - 0.35) < 0.000001)
	# 你赢一注 → 它开始忌惮你（15% 权重）
	assert_eq(loser["respect"], 0.15)


func test_absorb_push_changes_nothing_emotional() -> void:
	var push := BjPersona.absorb(BjPersona.empty(), _result({
		"winner": "PUSH", "player_delta": 0, "opponent_delta": 0,
	}))
	assert_eq(push["pushes"], 1)
	assert_eq(push["tilt"], 0.0, "平局不该让人上头")
	assert_eq(push["net_chips"], 0)


func test_absorb_confidence_uses_win_rate_ewma() -> void:
	var persona := BjPersona.empty()
	for i in range(4):
		persona = BjPersona.absorb(persona, _whale_win())
	assert_eq(persona["wins"], 4)
	# 一路赢：0.5 → 0.65 → 0.755 → 0.8285 → 0.87995
	assert_true(persona["confidence"] > 0.85 and persona["confidence"] < 0.9)


func test_absorb_respect_tracks_player_strength() -> void:
	var persona := BjPersona.empty()
	# 玩家黑杰克：delta 400 以上 + 0.3
	persona = BjPersona.absorb(persona, _result({"player_blackjack": true}))
	assert_eq(persona["respect"], 0.15)
	assert_eq(persona["player_blackjacks"], 1)


func test_grudge_only_rises_on_above_one_bet_win() -> void:
	var persona := BjPersona.empty()
	# 普通赢一注：delta == bet，不算"赢得不光彩"，反而衰减
	persona = BjPersona.absorb(persona, _result({}))
	assert_eq(persona["grudge"], 0.0)
	# 黑杰克赔付 1.5 倍：delta > bet → 记仇 +
	persona = BjPersona.absorb(persona, _result({
		"player_delta": Machine.MIN_BET * 15 / 10, "player_blackjack": true,
	}))
	assert_true(persona["grudge"] > 0.1, "1.5 倍赔付必须让它记仇")


func test_player_profile_needs_six_hands() -> void:
	var persona := BjPersona.empty()
	for i in range(5):
		persona = BjPersona.absorb(persona, _result({"player_bust": true}))
	assert_false(persona["player_profile"]["aggressive"], "前 5 局样本太少，不该下判断")
	persona = BjPersona.absorb(persona, _result({"player_bust": true}))
	# 6 局里 0 次加注 → 不激进；爆了 6 次 → 不保守
	assert_false(persona["player_profile"]["aggressive"])
	assert_false(persona["player_profile"]["conservative"])


func test_mood_cascade() -> void:
	var persona := BjPersona.empty()
	assert_eq(BjPersona.mood(persona), "calm")
	persona["tilt"] = 0.7
	assert_eq(BjPersona.mood(persona), "tilted", "上头优先级最高")
	persona["tilt"] = 0.0
	persona["confidence"] = 0.8
	persona["net_chips"] = 100
	assert_eq(BjPersona.mood(persona), "smug")
	persona["confidence"] = 0.5
	persona["grudge"] = 0.6
	assert_eq(BjPersona.mood(persona), "grudge")
	persona["grudge"] = 0.0
	persona["respect"] = 0.7
	assert_eq(BjPersona.mood(persona), "wary")
	persona["respect"] = 0.0
	persona["net_chips"] = -400
	assert_eq(BjPersona.mood(persona), "shaken")


func test_face_mapping_is_many_to_one() -> void:
	assert_eq(BjPersona.face_for("tilted", "PLAYER_TURN", false), "panic")
	assert_eq(BjPersona.face_for("grudge", "PLAYER_TURN", false), "panic")
	assert_eq(BjPersona.face_for("wary", "PLAYER_TURN", false), "thinking")
	assert_eq(BjPersona.face_for("shaken", "PLAYER_TURN", false), "sad")
	# 它在思考时，表情优先于情绪
	assert_eq(BjPersona.face_for("smug", "PLAYER_TURN", true), "thinking")
	assert_eq(BjPersona.face_for("calm", "OPPONENT_TURN", false), "thinking")


func test_memory_ring_buffer_and_summary() -> void:
	var persona := BjPersona.empty()
	for i in range(12):
		persona = BjPersona.absorb(persona, _result({"hand_no": i + 1}))
	assert_eq(persona["recent"].size(), 8, "最近 8 局留原文")
	assert_true(str(persona["summary"]).length() > 0, "更早的局被压成摘要")
	assert_true(str(persona["summary"]).length() <= 300, "摘要不超过 300 字")
	assert_contains(str(persona["recent"][7]), "第12局")


func test_describe_hand_text() -> void:
	var text := BjPersona.describe_hand(_result({"hand_no": 3, "player_total": 18, "opponent_total": 20,
		"winner": "OPPONENT"}))
	assert_eq(text, "第3局 对方18点/我20点，我赢")
	var doubled := BjPersona.describe_hand(_result({"hand_no": 4, "player_doubled": true}))
	assert_contains(doubled, "（对方加了注）")
	var push := BjPersona.describe_hand(_result({"winner": "PUSH"}))
	assert_contains(push, "打平")


# ---------------------------------------------------------------- 下注公式

func test_bet_multiplier_formula() -> void:
	var persona := BjPersona.empty()
	# 中性人格：confidence 0.5 / tilt 0 / grudge 0 → 恰好 1.0
	assert_eq(BjPersona.bet_multiplier(persona), 1.0)
	persona["confidence"] = 1.0
	assert_eq(BjPersona.bet_multiplier(persona), 1.4)
	persona["confidence"] = 0.5
	persona["tilt"] = 1.0
	assert_true(absf(BjPersona.bet_multiplier(persona) - 0.6) < 0.0001)
	persona["tilt"] = 0.0
	persona["grudge"] = 1.0
	assert_true(absf(BjPersona.bet_multiplier(persona) - 1.3) < 0.0001)


func test_fallback_bet_is_midpoint_scaled_and_clamped() -> void:
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	var limits := {"min": Machine.MIN_BET, "max": Machine.MAX_BET, "chips": Machine.STARTING_CHIPS}
	# 中性人格 → 区间中点（数字全部从常量推导，调经济时不用改这里）
	var mid := (Machine.MIN_BET + Machine.MAX_BET) / 2
	assert_eq(BjBrainLocal.fallback_bet(BjPersona.empty(), limits), mid)
	# 胆量拉满（confidence 1.0 → 倍率 1.4）
	var bold := BjPersona.empty()
	bold["confidence"] = 1.0
	assert_true(int(BjBrainLocal.fallback_bet(bold, limits)) > mid, "胆量越大押得越大")
	# 胆量 + 记仇全满（倍率 1.7）→ 现在**会**被最大注夹住：
	# 中点 = 3×最小注，1.7 × 3 = 5.1 × 最小注 > 最大注（5×）。
	# 早期经济里最大注是最小注的 50 倍，所以撞不到；改成 5 倍之后会撞到 —— 这是对的：
	# 她再疯也不能越过当前档位的上限。
	bold["grudge"] = 1.0
	assert_eq(BjBrainLocal.fallback_bet(bold, limits), Machine.MAX_BET)
	# 真正会夹住它的是自己筹码不够（比最大注还少）
	var poor_but_bold := {"min": Machine.MIN_BET, "max": Machine.MAX_BET, "chips": Machine.MIN_BET * 3}
	assert_eq(BjBrainLocal.fallback_bet(bold, poor_but_bold), Machine.MIN_BET * 3)
	# 没有筹码 → 被筹码夹住
	var poor := {"min": Machine.MIN_BET, "max": Machine.MAX_BET, "chips": Machine.MIN_BET * 2}
	assert_eq(BjBrainLocal.fallback_bet(BjPersona.empty(), poor), Machine.MIN_BET * 2)


# ---------------------------------------------------------------- 筹码格式化

func test_token_formatting_matches_original() -> void:
	assert_eq(BjTokens.format(100_000_000), "1亿", "1 亿不带小数点")
	assert_eq(BjTokens.format(120_000_000), "1.2亿")
	assert_eq(BjTokens.format(200_000_000), "2亿")
	assert_eq(BjTokens.format(1_000_000_000), "10亿")
	assert_eq(BjTokens.format(50_000_000), "5000万")
	assert_eq(BjTokens.format(5_000_000), "500万")
	assert_eq(BjTokens.format(1_000_000), "100万")
	assert_eq(BjTokens.format(12_000), "1.2万")
	assert_eq(BjTokens.format(1_500), "1,500")
	assert_eq(BjTokens.format(0), "0")
	assert_eq(BjTokens.format(-120_000_000), "-1.2亿")
	assert_eq(BjTokens.format_exact(120_000_000), "120,000,000")
	assert_eq(BjTokens.format_delta(0), "±0")
	assert_eq(BjTokens.yi(1), 100_000_000)


# ---------------------------------------------------------------- 两套台词

func test_default_lines_are_complete() -> void:
	assert_eq(BjLines.DEFAULT_LINES["player_wins"].size(), 6)
	assert_eq(BjLines.DEFAULT_LINES["opponent_wins"].size(), 7)
	assert_eq(BjLines.DEFAULT_LINES["opponent_wins_big"].size(), 5)
	assert_eq(BjLines.DEFAULT_LINES["push"].size(), 4)
	assert_eq(BjLines.DEFAULT_LINES["player_blackjack"].size(), 4)
	# 原版有这张表却没人引用（死表），这里必须真的接上
	assert_eq(BjLines.DEFAULT_LINES["opponent_wins_small"].size(), 4)
	assert_eq(BjLines.DEFAULT_LINES["idle"].size(), 5)
	assert_true(BjLines.DEFAULT_LINES["opponent_wins"].has("杂鱼♡"))


func test_picker_never_repeats_immediately() -> void:
	var picker := BjLines.Picker.new()
	var pool: Array = ["a", "b", "c", "d", "e", "f"]
	var previous := ""
	var repeats := 0
	for i in range(60):
		var picked := picker.pick(pool, "key")
		if picked == previous:
			repeats += 1
		previous = picked
	assert_eq(repeats, 0, "同一类台词不允许连续重复")


func test_emote_cascade_priority() -> void:
	var picker := BjLines.Picker.new()
	# 1. 你拿到黑杰克 → 震惊脸 + 黑杰克台词（优先级高于它自己的黑杰克）
	var cue := BjEmotes.cue_for_hand({
		"winner": "PLAYER", "player_delta": 100, "opponent_delta": -100,
		"player_blackjack": true, "opponent_blackjack": true,
	}, picker)
	assert_eq(cue["mood"], "shocked")
	assert_true(BjLines.DEFAULT_LINES["player_blackjack"].has(cue["bubble"]))
	assert_contains(cue["fx"], "bj_burst")
	# 2. 它赢一点点 → 走"小赚"那张原版死表
	var small := BjEmotes.cue_for_hand({
		"winner": "OPPONENT", "player_delta": -Machine.MIN_BET,
		"opponent_delta": Machine.MIN_BET,
	}, picker)
	assert_true(BjLines.DEFAULT_LINES["opponent_wins_small"].has(small["bubble"]),
		"小赢必须触发小赚台词（原版这里是永远到不了的）")
	# 3. 它赢很多 → 大赢表 + 震屏
	var big := BjEmotes.cue_for_hand({
		"winner": "OPPONENT", "player_delta": -Machine.BIG_BET,
		"opponent_delta": Machine.BIG_BET,
	}, picker)
	assert_true(BjLines.DEFAULT_LINES["opponent_wins_big"].has(big["bubble"]))
	assert_contains(big["fx"], "screen_shake")
	# 4. 平局
	var push := BjEmotes.cue_for_hand({
		"winner": "PUSH", "player_delta": 0, "opponent_delta": 0,
	}, picker)
	assert_true(BjLines.DEFAULT_LINES["push"].has(push["bubble"]))
	assert_contains(push["fx"], "push_glow")


func test_duel_strategy_table() -> void:
	# 单挑：它看得见你的最终点数，所以规则只有"想办法比你大"
	assert_eq(BjBrainLocal.duel_strategy(20, 18, false), "STAND", "领先就停手保胜")
	assert_eq(BjBrainLocal.duel_strategy(16, 19, false), "HIT", "落后就必须要牌")
	assert_eq(BjBrainLocal.duel_strategy(18, 18, false), "STAND", "平局默认不赌")
	assert_eq(BjBrainLocal.duel_strategy(10, 21, false), "STAND", "你 21 点了，它要牌只会爆")
	assert_eq(BjBrainLocal.duel_strategy(5, 20, true), "STAND", "你已经爆了，白送的局别冒险")
	assert_eq(BjBrainLocal.duel_strategy(12, 12, false), "STAND")


func test_tilt_makes_it_gamble() -> void:
	# 人格不只在嘴上：上头的时候它会拿"平局保本"去赌一个赢
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	brain.think_scale = 0.0
	var tie_view := {"opponent_total": 18, "player_total": 18, "player_bust": false}
	for i in range(30):
		assert_eq(brain.decide_now(tie_view, ["HIT", "STAND"])["action"], "STAND",
			"冷静时平局一律收手")
	brain.persona["tilt"] = 0.9
	var gambles := 0
	for i in range(60):
		if str(brain.decide_now(tie_view, ["HIT", "STAND"])["action"]) == "HIT":
			gambles += 1
	assert_gt(gambles, 0, "上头时它应该会赌一把")
	assert_true(gambles < 60, "但也不是每把都赌")


func test_local_brain_decides_and_talks() -> void:
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	brain.think_scale = 0.0
	var view := {
		"opponent_total": 20, "opponent_soft": false,
		"player_total": 18, "player_bust": false,
		"player_up_value": 10, "running_count": 0,
	}
	var decision: Dictionary = brain.decide_now(view, ["HIT", "STAND"])
	assert_eq(decision["action"], "STAND")
	assert_eq(decision["source"], "local")
	assert_true(str(decision["say"]).length() > 0, "本地大脑也要会说话")
	# 非法动作必须被收敛到合法集合里
	var forced: Dictionary = brain.decide_now({"opponent_total": 5, "player_total": 20}, ["STAND"])
	assert_eq(forced["action"], "STAND")


func test_opening_line_reacts_to_the_stake() -> void:
	var brain := track(BjBrainLocal.new()) as BjBrainLocal
	brain.think_scale = 0.0
	var limits := {"min": Machine.MIN_BET, "max": Machine.MAX_BET, "chips": Machine.STARTING_CHIPS}
	# 你押得比它"敢押"的大得多 → 它会主动开口
	var big: Dictionary = brain.opening_now({
		"stake": Machine.MAX_BET, "opponent_chips": Machine.STARTING_CHIPS,
		"player_chips": Machine.STARTING_CHIPS,
	})
	assert_true(str(big["say"]).length() > 0)
	assert_true(BjLines.TABLE_TALK["bet_big"].has(str(big["say"]))
		or BjLines.TABLE_TALK["bet_small"].has(str(big["say"]))
		or BjLines.MOOD_TALK.has("smug"), "开场台词必须来自新加的注额反应表")
	# 注额极小 → 它也有一句
	var small: Dictionary = brain.opening_now({
		"stake": Machine.MIN_BET, "opponent_chips": Machine.STARTING_CHIPS,
		"player_chips": Machine.STARTING_CHIPS,
	})
	assert_true(str(small["say"]).length() > 0)
	assert_eq(BjBrainLocal.fallback_bet(BjPersona.empty(), limits),
		(Machine.MIN_BET + Machine.MAX_BET) / 2)
