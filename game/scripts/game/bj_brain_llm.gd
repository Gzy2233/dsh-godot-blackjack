class_name BjBrainLlm
extends Node

## 真模型大脑：走 DeepSeek 的 chat/completions（**单挑版**）。
##
## 移植自 dsh-deepseek-blackjack/src/host/{opponent,opponent-session}.js 的
## 提示词与解析容错。三条铁律原版守得很死，这里也守住：
##
##   1. **模型只做决策，不做算术**。发牌/算点/比大小/结算全在引擎里。
##      模型只回 `{action, say}`，非法动作由引擎拒绝。
##   2. **隐藏信息是协议层面的硬边界**。发给模型的字段是白名单：
##      它自己的暗牌当然给它，牌靴顺序、下一张是什么 —— 它在协议上根本收不到。
##   3. **反脆弱**。非法/超时/乱码 → 重试一次 → 仍失败就降级到本地策略。
##      牌局永远不会卡死；你顶多遇到一个"今天状态不太好的 DeepSeek"。
##
## 单挑带来的一个好处：**对方的牌是全公开的**，所以模型能真正"看着你的点数"做决定，
## 提示词里会直接告诉它自己是领先还是落后。

const TIMEOUT := 25.0
const MAX_SAY := 40

var api_key := ""
var model := "deepseek-chat"
var endpoint := "https://api.deepseek.com/chat/completions"

## 降级用的大脑（每次失败都回落到它）。
var fallback: BjBrainLocal
var last_note := ""

var _busy := false


func configure(settings: Dictionary) -> void:
	api_key = str(settings.get("api_key", "")).strip_edges()
	model = str(settings.get("model", "deepseek-chat"))
	endpoint = str(settings.get("endpoint", endpoint))


func is_ready() -> bool:
	return api_key != ""


# ---------------------------------------------------------------- 决策

## 与 BjBrainLocal.decide 同签名：决定要牌还是停牌。
func decide(view: Dictionary, legal: Array, context: Dictionary = {}) -> Dictionary:
	if not is_ready() or _busy:
		return await fallback.decide(view, legal, context)

	var persona_desc: String = str(context.get("persona_desc", ""))
	var user_prompt := build_turn_prompt(view, legal, persona_desc)
	var answer := await _ask(build_system_prompt(persona_desc), user_prompt)

	var parsed := parse_decision(answer, legal)
	if not parsed.has("error"):
		return {"action": parsed["action"], "say": parsed["say"], "source": "model", "note": ""}

	# 只重试一次，并把上一次的错误原样告诉它。
	last_note = str(parsed["error"])
	var retry_prompt := user_prompt + "\n\n（你上一次的回答没法用：%s。请只输出那个 JSON 对象，不要任何别的字。）" % last_note
	answer = await _ask(build_system_prompt(persona_desc), retry_prompt)
	parsed = parse_decision(answer, legal)
	if not parsed.has("error"):
		return {"action": parsed["action"], "say": parsed["say"], "source": "retry", "note": ""}

	# 仍失败 → 降级。牌桌只会看到一句"它卡了一下"。
	last_note = "模型两次都没给出合法动作，走本地策略"
	var local: Dictionary = await fallback.decide(view, legal, context)
	local["source"] = "fallback"
	local["note"] = "它卡了一下，换了保守打法"
	return local


## 开局前对注额的一句反应（同注对赌：注是你定的，它必须跟）。
func opening_line(view: Dictionary, _limits: Dictionary = {}) -> Dictionary:
	if not is_ready() or _busy:
		return await fallback.opening_line(view)

	var persona_desc: String = str(view.get("persona_desc", ""))
	var answer := await _ask(build_system_prompt(persona_desc), build_stake_prompt(view, persona_desc))
	var parsed := parse_say(answer)
	if parsed.has("error"):
		last_note = str(parsed["error"])
		var local: Dictionary = await fallback.opening_line(view)
		local["source"] = "fallback"
		return local
	return {"say": parsed["say"], "source": "model"}


## 求情时的回应：让模型演它，但**心情值与金额全在本地算**。
## softness 只用来告诉它"你现在什么态度"，免得它嘴上答应、账上却不肯借。
func plea_reply(text: String, history: Array, persona_desc: String, softness: int) -> Dictionary:
	if not is_ready() or _busy:
		return {"say": ""}
	var prompt := build_plea_prompt(text, history, persona_desc, softness)
	var answer := await _ask(build_system_prompt(persona_desc), prompt)
	var parsed := parse_say(answer)
	if parsed.has("error"):
		return {"say": ""}
	return {"say": parsed["say"]}


func _ask(system_prompt: String, user_prompt: String) -> String:
	_busy = true
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var payload := {
		"model": model,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt},
		],
		"temperature": 1.0,
		"max_tokens": 300,
		"stream": false,
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])
	var error := http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		http.queue_free()
		_busy = false
		push_warning("对手请求发不出去：%d" % error)
		return ""
	var response: Array = await http.request_completed
	http.queue_free()
	_busy = false
	if int(response[1]) != 200:
		push_warning("对手 HTTP %d" % int(response[1]))
		return ""
	var body: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return ""
	var choices: Variant = parsed.get("choices", [])
	if not (choices is Array) or choices.is_empty():
		return ""
	var message: Variant = choices[0].get("message", {})
	return str(message.get("content", ""))


# ---------------------------------------------------------------- 提示词

## 系统提示词。**禁止任何助手味的词** —— 它是牌桌上的一个人，不是 AI 助手。
static func build_system_prompt(persona_desc: String) -> String:
	var lines: PackedStringArray = []
	lines.append("你在跟人单挑 21 点（Blackjack）。桌上只有你们两个，没有庄家。")
	lines.append("你就是个来打牌的玩家，不是助手，只跟对面那个人一较高下。")
	lines.append("各自发两张牌，你的第二张是暗牌，对方的牌是明的。")
	lines.append("你们押**一样的注**，最后谁点数大谁就赢走对方那份 token。")
	lines.append("点数相同算平局；两边都爆也算平局。")
	lines.append("目标是把牌点凑到 21 点，尽量接近但不能超过；超过 21 点就爆了。")
	lines.append("花牌算 10 点，A 可以算 1 也可以算 11。")
	lines.append("一张 A 加一张十点牌（10/J/Q/K）是 Blackjack，能赢 1.5 倍。")
	lines.append("对方先行动、你后行动 —— 所以**你能看到对方最后停在几点**，这是你最大的优势。")
	lines.append("下注区间是 100 万到 5000 万 token，起始各 1 亿，注额由对方定、你只能跟。")
	lines.append("")
	lines.append("【说话的规矩 —— 这条最重要】")
	lines.append("主动开口。翻旧账、戳对方的习惯、赢了就得意、输了就嘴硬。")
	lines.append("但不要每句话都提筹码数字。")
	lines.append("得意时：「杂鱼♡」「就这？」「你的 token 归我了」")
	lines.append("上头时：「这牌有问题吧？」「不算不算，重来」")
	lines.append("记仇时：「你上次那手我可记着呢」")
	lines.append("怂的时候：「……我收着点」")
	lines.append("崩溃时：「我的 token……」")
	lines.append("你说话要短，像牌桌上随口撂的一句话，不超过 25 个字。")
	lines.append("不要解释你在做什么，不要旁白，不要客套，不要用「哈哈」这类贴纸式的笑。")
	lines.append("想不出话就真的少说。")
	if persona_desc.strip_edges() != "":
		lines.append("")
		lines.append(persona_desc.strip_edges())
	return "\n".join(lines)


## 回合提示词。只喂**公开可见**的信息 + 它自己的手牌。
static func build_turn_prompt(view: Dictionary, legal: Array, persona_desc: String) -> String:
	var my_total: int = int(view.get("opponent_total", 0))
	var your_total: int = int(view.get("player_total", 0))
	var your_bust: bool = bool(view.get("player_bust", false))
	var lines: PackedStringArray = []
	lines.append("【第 %d 局】本局注额：%d token（双方各押这么多）" % [
		int(view.get("hand_no", 1)), int(view.get("stake", 0)),
	])
	lines.append("你的筹码：%d token　对方的筹码：%d token" % [
		int(view.get("opponent_chips", 0)), int(view.get("player_chips", 0)),
	])
	lines.append("")
	var own := "你的手牌：%s 合计 %d 点" % [
		BjCards.hand_text(view.get("opponent_hand", [])), my_total,
	]
	if bool(view.get("opponent_soft", false)):
		own += "（软牌，A 还算 11）"
	lines.append(own)
	lines.append("对方的牌：%s 合计 %d 点" % [
		BjCards.hand_text(view.get("player_hand", [])), your_total,
	])
	if bool(view.get("player_doubled", false)):
		lines.append("（对方加了注，注额翻倍了，你也跟了）")
	if your_bust:
		lines.append("**对方已经爆牌了 —— 你只要不爆就赢。**")
	elif bool(view.get("player_blackjack", false)):
		lines.append("**对方拿到了 Blackjack，21 点。**")
	else:
		# 单挑的关键信息：它到底领先还是落后
		var margin: int = my_total - your_total
		if margin > 0:
			lines.append("你现在领先 %d 点。停手就赢，除非你爆。" % margin)
		elif margin < 0:
			lines.append("你现在落后 %d 点。你必须再要牌才可能赢。" % (-margin))
		else:
			lines.append("你们现在打平。停手是平局，再要一张可能赢也可能爆。")
	if view.has("shoe_remaining"):
		lines.append("牌靴里还剩 %d 张" % int(view["shoe_remaining"]))
	var count: int = int(view.get("running_count", 0))
	if count > 0:
		lines.append("你心里的计数：+%d（大牌偏多）" % count)
	elif count < 0:
		lines.append("你心里的计数：%d（小牌偏多）" % count)
	else:
		lines.append("你心里的计数：0（均衡）")
	if persona_desc.strip_edges() != "":
		lines.append("")
		lines.append("【你现在的状态】")
		lines.append(persona_desc.strip_edges())
	lines.append("")
	lines.append("【你可以做的】%s" % " / ".join(legal))
	lines.append("只输出一个 JSON 对象，不要任何其它文字：")
	lines.append('{"action": "HIT", "say": "一句话"}')
	lines.append('action 必须是 %s 之一。' % " 或 ".join(legal))
	return "\n".join(lines)


## 下注提示词。注额由对方定、它只能跟，所以这里**只让它说话**，不让它算数。
static func build_stake_prompt(view: Dictionary, persona_desc: String) -> String:
	var lines: PackedStringArray = []
	lines.append("【下一局要下注了】第 %d 局" % int(view.get("hand_no", 1)))
	lines.append("对方定的注额：%d token（你必须跟，跟不动就开不了局）" % int(view.get("stake", 0)))
	lines.append("你的筹码：%d token" % int(view.get("opponent_chips", 0)))
	lines.append("对方的筹码：%d token" % int(view.get("player_chips", 0)))
	lines.append("上一局：%s" % str(view.get("last_outcome", "（第一局）")))
	if persona_desc.strip_edges() != "":
		lines.append("")
		lines.append(persona_desc.strip_edges())
	lines.append("就这个注额说一句话 —— 嫌大、嫌小、挑衅、嘴硬都行。")
	lines.append("只输出一个 JSON 对象，不要任何其它文字：")
	lines.append('{"say": "一句话"}')
	return "\n".join(lines)


## 求情提示词：他输光了，正在跟你借钱。你只负责**说一句回应**。
static func build_plea_prompt(text: String, history: Array, persona_desc: String,
		softness: int) -> String:
	var lines: PackedStringArray = []
	lines.append("【他输光了，正在跟你借钱】")
	if softness >= 60:
		lines.append("你现在心里有点松动（心情 %d/100）—— 可以损他两句，但话里留个口子。" % softness)
	elif softness >= 30:
		lines.append("你现在不太想借（心情 %d/100）—— 刁难他、看他还能说出什么。" % softness)
	else:
		lines.append("你现在一点都不想借（心情 %d/100）—— 直接拒绝、损他。" % softness)
	lines.append("")
	if history.size() > 0:
		lines.append("刚才的对话：")
		for entry in history:
			var item: Dictionary = entry
			lines.append("　他：%s" % str(item.get("you", "")))
			lines.append("　你：%s" % str(item.get("her", "")))
		lines.append("")
	lines.append("他刚说：「%s」" % text.strip_edges())
	lines.append("")
	if persona_desc.strip_edges() != "":
		lines.append(persona_desc.strip_edges())
		lines.append("")
	lines.append("用一句话回应他。像牌桌上随口撂的，不超过 25 个字。")
	lines.append("不要提具体数字，不要解释规则，不要旁白。")
	lines.append("只输出一个 JSON 对象：")
	lines.append('{"say": "一句话"}')
	return "\n".join(lines)


# ---------------------------------------------------------------- 解析容错
#
# 模型的输出不可靠是**必然**，不是意外。下面这几个函数就是为此存在的：
# 剥 markdown 围栏、取第一个 { 到最后一个 }、尾随逗号再试一次、动作名大小写收敛。

static func _strip_fence(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?s)```[a-zA-Z]*\\s*(.*?)\\s*```")
	var found := regex.search(text)
	if found != null:
		return found.get_string(1)
	return text


static func _strip_trailing_commas(text: String) -> String:
	var regex := RegEx.new()
	regex.compile(",\\s*([}\\]])")
	return regex.sub(text, "$1", true)


## 抽出第一个 JSON 对象；失败返回空字符串。
static func _extract_object(text: String) -> String:
	var cleaned := _strip_fence(text)
	var start := cleaned.find("{")
	var end := cleaned.rfind("}")
	if start == -1 or end == -1 or end < start:
		return ""
	return cleaned.substr(start, end - start + 1)


static func parse_decision(text: String, legal: Array) -> Dictionary:
	if text.strip_edges() == "":
		return {"error": "空回复"}
	var slice := _extract_object(text)
	if slice == "":
		return {"error": "没找到 JSON 对象"}
	var parsed: Variant = JSON.parse_string(slice)
	if parsed == null:
		parsed = JSON.parse_string(_strip_trailing_commas(slice))
	if not (parsed is Dictionary):
		return {"error": "JSON 解析失败"}
	var obj: Dictionary = parsed
	var action := str(obj.get("action", "")).strip_edges().to_upper()
	if action == "":
		return {"error": "非法动作: (缺失)"}
	if not legal.has(action):
		return {"error": "非法动作: %s" % action}
	return {"action": action, "say": _clean_say(obj)}


## 只要一句话（开局那种场合用它）。
static func parse_say(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"error": "空回复"}
	var slice := _extract_object(text)
	if slice == "":
		# 没给 JSON 也认 —— 直接把它说的当台词（模型经常不听话）
		return {"say": _truncate(text.strip_edges().strip_escapes())}
	var parsed: Variant = JSON.parse_string(slice)
	if parsed == null:
		parsed = JSON.parse_string(_strip_trailing_commas(slice))
	if not (parsed is Dictionary):
		return {"error": "JSON 解析失败"}
	return {"say": _clean_say(parsed)}


static func _clean_say(obj: Dictionary) -> String:
	return _truncate(str(obj.get("say", "")).strip_edges())


static func _truncate(text: String) -> String:
	if text.length() > MAX_SAY:
		return text.substr(0, MAX_SAY)
	return text
