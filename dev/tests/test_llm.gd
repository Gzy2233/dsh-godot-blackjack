@tool
class_name BjTestLlm
extends McpTestSuite

## 真模型大脑的**离线可测部分**：提示词构造 + 脏输出解析。
##
## 这一层是"接真 DeepSeek 也不会崩"的保证：模型输出的不可靠是必然，
## 所以容错逻辑必须自己有单测（不需要 API Key、不花 token）。

const Machine := preload("res://scripts/engine/bj_machine.gd")


func suite_name() -> String:
	return "llm"


func _machine_with(ordered: String) -> BjMachine:
	var machine := BjMachine.new()
	var cards := BjCards.parse_hand(ordered)
	while cards.size() < 100:
		cards.append(BjCards.make("2", "S"))
	machine.shoe = BjShoe.stacked(cards)
	machine.start_hand(Machine.MIN_BET)
	return machine


# ---------------------------------------------------------------- DSH 自动连接

## 造一个最小可用的 BjGame（不落盘、不碰真存档）。
func _auto_connect_game() -> BjGame:
	var game := track(BjGame.new()) as BjGame
	game.settings = {"api_key": "sk-manual", "use_llm": false, "model": "deepseek-chat"}
	game.brain_local = BjBrainLocal.new()
	game.add_child(game.brain_local)
	game.brain_llm = BjBrainLlm.new()
	game.add_child(game.brain_llm)
	return game


func test_dsh_host_key_wins_over_manual_key() -> void:
	var game := _auto_connect_game()
	assert_false(game.auto_connected(), "没有宿主注入时不该报自动连接")
	assert_eq(game.effective_api_key(), "sk-manual")

	game.dsh_key = "sk-from-dsh"
	assert_true(game.auto_connected())
	assert_eq(game.effective_api_key(), "sk-from-dsh", "宿主注入的 key 必须优先于手填的")


func test_dsh_auto_connect_enables_the_real_model() -> void:
	# 玩家没打开开关，但插件注入了 key → 直接用真模型（"装完就能玩"）
	var game := _auto_connect_game()
	assert_eq(game.brain(), game.brain_local, "没 key 时是本地大脑")
	game.dsh_key = "sk-from-dsh"
	game._apply_llm_settings()
	assert_eq(game.brain(), game.brain_llm, "自动连接应直接启用真模型")


func test_dsh_host_key_never_leaks_into_saved_settings() -> void:
	# 安全：宿主给的 key 只在内存里用，**绝不写进存档/设置字典**
	var game := _auto_connect_game()
	game.dsh_key = "sk-from-dsh"
	game._apply_llm_settings()
	assert_eq(str(game.settings.get("api_key", "")), "sk-manual",
		"_apply_llm_settings 不能改写 settings（那份会被存成明文 JSON）")
	assert_eq(game.brain_llm.api_key, "sk-from-dsh", "但大脑必须拿到宿主注入的那把")


func test_dsh_env_names_are_the_documented_ones() -> void:
	# 插件注入的变量名必须和这里读的一致，否则"自动连接"会静默失效
	assert_eq(BjGame.ENV_API_KEY, "DEEPSEEK_API_KEY")
	assert_eq(BjGame.ENV_BASE_URL, "DEEPSEEK_BASE_URL")
	assert_eq(BjGame.ENV_MODEL, "DEEPSEEK_MODEL")


# ---------------------------------------------------------------- 动作解析

func test_parse_clean_json() -> void:
	var parsed := BjBrainLlm.parse_decision('{"action": "HIT", "say": "再来一张"}', ["HIT", "STAND"])
	assert_false(parsed.has("error"))
	assert_eq(parsed["action"], "HIT")
	assert_eq(parsed["say"], "再来一张")


func test_parse_strips_markdown_fence() -> void:
	var parsed := BjBrainLlm.parse_decision("```json\n{\"action\": \"STAND\", \"say\": \"够了\"}\n```", ["HIT", "STAND"])
	assert_false(parsed.has("error"), "markdown 围栏必须能被剥掉")
	assert_eq(parsed["action"], "STAND")


func test_parse_survives_trailing_commas_and_chatter() -> void:
	var messy := "我决定好了：{\"action\": \"hit\", \"say\": \"跟\", }  就这样。"
	var parsed := BjBrainLlm.parse_decision(messy, ["HIT", "STAND"])
	assert_false(parsed.has("error"), "尾随逗号与前后废话都要能容错：%s" % str(parsed))
	assert_eq(parsed["action"], "HIT", "动作名要大小写收敛")


func test_parse_rejects_illegal_action() -> void:
	var parsed := BjBrainLlm.parse_decision('{"action": "SPLIT"}', ["HIT", "STAND"])
	assert_true(parsed.has("error"))
	assert_contains(str(parsed["error"]), "非法动作")


func test_parse_error_messages() -> void:
	assert_eq(str(BjBrainLlm.parse_decision("", ["HIT"])["error"]), "空回复")
	assert_eq(str(BjBrainLlm.parse_decision("我觉得应该要牌", ["HIT"])["error"]), "没找到 JSON 对象")
	assert_eq(str(BjBrainLlm.parse_decision('{"action": ""}', ["HIT"])["error"]), "非法动作: (缺失)")


func test_parse_truncates_long_lines() -> void:
	var long_say := "一".repeat(120)
	var parsed := BjBrainLlm.parse_decision('{"action": "HIT", "say": "%s"}' % long_say, ["HIT"])
	assert_eq(str(parsed["say"]).length(), BjBrainLlm.MAX_SAY, "台词超过 40 字必须硬截断")


func test_parse_say_accepts_json_or_plain_text() -> void:
	var from_json := BjBrainLlm.parse_say('{"say": "押这么大？"}')
	assert_eq(str(from_json["say"]), "押这么大？")
	# 模型经常不听话、直接说一句话 —— 也得认
	var from_text := BjBrainLlm.parse_say("  就这点？  ")
	assert_eq(str(from_text["say"]), "就这点？")
	assert_true(BjBrainLlm.parse_say("").has("error"))
	assert_eq(str(BjBrainLlm.parse_say("一".repeat(80))["say"]).length(), BjBrainLlm.MAX_SAY)


# ---------------------------------------------------------------- 提示词

func test_system_prompt_describes_a_duel() -> void:
	var prompt := BjBrainLlm.build_system_prompt("")
	assert_contains(prompt, "单挑")
	assert_contains(prompt, "没有庄家")
	assert_contains(prompt, "一样的注")
	assert_contains(prompt, "1.5 倍")
	assert_contains(prompt, "不超过 25 个字")
	# 它是牌桌上的一个人，不是助手
	assert_false(prompt.contains("作为 AI"))
	assert_false(prompt.contains("我可以帮您"))
	# 单挑的关键优势要明确告诉它
	assert_contains(prompt, "对方先行动")
	assert_contains(BjBrainLlm.build_system_prompt("你现在手气很差。"), "你现在手气很差。")


func test_turn_prompt_has_the_duel_state() -> void:
	# 你 ♠10 ♠6 = 16；它 ♥9 ♣10 = 19（♣10 是它的暗牌）
	var machine := _machine_with("S10 H9 S6 C10")
	machine.player_action("STAND")
	var view := BjGame.view_of(machine, "你有点忌惮对面。", "（第一局）")
	var prompt := BjBrainLlm.build_turn_prompt(view, ["HIT", "STAND"], "你有点忌惮对面。")

	assert_contains(prompt, "本局注额：%d token" % Machine.MIN_BET)
	assert_contains(prompt, "你的手牌：♥9 ♣10", "它自己的两张牌（含暗牌）要看得到")
	assert_contains(prompt, "对方的牌：♠10 ♠6 合计 16 点", "单挑里你的牌是全公开的")
	assert_contains(prompt, "你现在领先 3 点")
	assert_contains(prompt, "牌靴里还剩")
	assert_contains(prompt, "【你可以做的】HIT / STAND")
	assert_contains(prompt, '"action": "HIT"')
	assert_contains(prompt, "你有点忌惮对面。")
	# 庄家已经拆了，提示词里不许再出现
	assert_false(prompt.contains("庄家"))
	assert_false(prompt.contains("发牌员"))
	assert_false(prompt.contains("明牌"))


func test_turn_prompt_tells_it_when_it_is_behind() -> void:
	var machine := _machine_with("S10 H9 S6 C10")
	machine.player_action("STAND")
	var view := BjGame.view_of(machine, "", "")
	view["opponent_total"] = 12      # 假装它现在只有 12
	assert_contains(BjBrainLlm.build_turn_prompt(view, ["HIT", "STAND"], ""), "你现在落后")

	var tied := BjGame.view_of(machine, "", "")
	tied["opponent_total"] = int(tied["player_total"])
	assert_contains(BjBrainLlm.build_turn_prompt(tied, ["HIT", "STAND"], ""), "打平")


func test_turn_prompt_marks_player_states() -> void:
	var machine := _machine_with("S10 H9 S6 C10")
	var view := BjGame.view_of(machine, "", "")
	var soft_view := view.duplicate()
	soft_view["opponent_soft"] = true
	assert_contains(BjBrainLlm.build_turn_prompt(soft_view, ["HIT"], ""), "软牌")
	var bust_view := view.duplicate()
	bust_view["player_bust"] = true
	assert_contains(BjBrainLlm.build_turn_prompt(bust_view, ["HIT"], ""), "对方已经爆牌了")
	var bj_view := view.duplicate()
	bj_view["player_blackjack"] = true
	assert_contains(BjBrainLlm.build_turn_prompt(bj_view, ["HIT"], ""), "Blackjack")


func test_turn_prompt_reports_hi_lo_count() -> void:
	var machine := _machine_with("S10 H9 S6 C10")
	var view := BjGame.view_of(machine, "", "")
	view["running_count"] = 4
	assert_contains(BjBrainLlm.build_turn_prompt(view, ["HIT"], ""), "大牌偏多")
	view["running_count"] = -4
	assert_contains(BjBrainLlm.build_turn_prompt(view, ["HIT"], ""), "小牌偏多")
	view["running_count"] = 0
	assert_contains(BjBrainLlm.build_turn_prompt(view, ["HIT"], ""), "均衡")


func test_stake_prompt_has_no_cards() -> void:
	# 注额是对方定的、它只能跟 —— 所以这里只让它说话，不让它算数
	var view := {
		"hand_no": 3, "stake": 25_000_000, "opponent_chips": 90_000_000,
		"player_chips": 110_000_000, "last_outcome": "你赢了 500万 token",
		"persona_desc": "你现在赢着钱。",
	}
	var prompt := BjBrainLlm.build_stake_prompt(view, "你现在赢着钱。")
	assert_contains(prompt, "【下一局要下注了】第 3 局")
	assert_contains(prompt, "对方定的注额：25000000 token")
	assert_contains(prompt, "你赢了 500万 token")
	assert_contains(prompt, '"say"')
	assert_false(prompt.contains("♠"))
	assert_false(prompt.contains("♥"))
	assert_false(prompt.contains("手牌"))
	# 提示词里给模型看**原始整数**，人类单位只留在 UI 层
	assert_false(prompt.contains("2500万"))


func test_prompt_uses_raw_numbers_not_abbreviated() -> void:
	var view := {
		"hand_no": 1, "stake": 100_000_000, "opponent_chips": 100_000_000,
		"player_chips": 100_000_000, "last_outcome": "（第一局）", "persona_desc": "",
	}
	var prompt := BjBrainLlm.build_stake_prompt(view, "")
	assert_contains(prompt, "100000000")
	assert_false(prompt.contains("1亿"), "提示词里不该出现亿/万的缩写")
