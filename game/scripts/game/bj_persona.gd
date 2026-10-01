class_name BjPersona
extends RefCounted

## 鲸鱼娘的人格：不是预设角色，是**从战绩里养出来的四个标量**。
##
## 移植自 dsh-deepseek-blackjack/src/host/persona.js。
##
##   tilt       上头（输钱驱动的烦躁）
##   respect    忌惮（你打得稳）
##   confidence 底气（胜率 EWMA）
##   grudge     记仇（你赢得"不光彩"）
##
## 这四个标量驱动的只有三件事：语气档位、下注胆量、表情脸。
## 注意几个原版的真实阈值差异（不要"顺手统一"，那是行为变化）：
##   - mood() 的得意阈值是 net_chips > 0，而 describe() 的散文阈值是 > 200
##   - mood() 的记仇阈值是 grudge > 0.5，而 describe() 的回忆阈值是 > 0.4

const HAND_LIMIT := 8
const SUMMARY_LIMIT := 300


static func clamp01(value: float) -> float:
	return min(1.0, max(0.0, value))


## 空字典按"全新对手"处理。
## 为什么要有它：大脑可能在任何人格被喂进来之前就开口说话
## （本地大脑 new 出来直接问它"你现在什么情绪"），缺字段不该炸。
static func ensure(persona: Dictionary) -> Dictionary:
	if persona.is_empty():
		return empty()
	return persona


## 新对手 = 一张白纸。
static func empty() -> Dictionary:
	return {
		"hands_played": 0,
		"wins": 0,
		"losses": 0,
		"pushes": 0,
		"net_chips": 0,
		"player_busts": 0,
		"player_doubles": 0,
		"player_blackjacks": 0,
		"tilt": 0.0,
		"respect": 0.0,
		"confidence": 0.5,
		"grudge": 0.0,
		"player_profile": {"aggressive": false, "conservative": false, "chases": false},
		"recent": [],
		"summary": "",
	}


## 一局之后人格怎么变。传入 result（outcome + 展示字段），返回**新的**人格。
static func absorb(persona: Dictionary, result: Dictionary) -> Dictionary:
	var next: Dictionary = persona.duplicate(true)
	var opp_delta: int = int(result.get("opponent_delta", 0))
	var player_delta: int = int(result.get("player_delta", 0))
	var player_bet: int = int(result.get("player_bet", 0))
	var player_bust: bool = bool(result.get("player_bust", false))
	var player_doubled: bool = bool(result.get("player_doubled", false))
	var player_blackjack: bool = bool(result.get("player_blackjack", false))

	# 1. 计数器
	next["hands_played"] = int(next["hands_played"]) + 1
	if opp_delta > 0:
		next["wins"] = int(next["wins"]) + 1
	elif opp_delta < 0:
		next["losses"] = int(next["losses"]) + 1
	else:
		next["pushes"] = int(next["pushes"]) + 1
	next["net_chips"] = int(next["net_chips"]) + opp_delta
	if player_bust:
		next["player_busts"] = int(next["player_busts"]) + 1
	if player_doubled:
		next["player_doubles"] = int(next["player_doubles"]) + 1
	if player_blackjack:
		next["player_blackjacks"] = int(next["player_blackjacks"]) + 1

	# 2. tilt：只由自己的盈亏驱动。平局不动。
	var loss_pressure := clamp01(float(-opp_delta) / 300.0)
	var win_relief := clamp01(float(opp_delta) / 300.0)
	next["tilt"] = clamp01(float(next["tilt"]) + loss_pressure * 0.35 - win_relief * 0.5)

	# 3. confidence：胜率的 EWMA（70% 旧 / 30% 新，故意迟钝，
	#    否则前三局就能把人格推到极端）。
	var games: int = int(next["wins"]) + int(next["losses"]) + int(next["pushes"])
	var raw_confidence := 0.5 if games == 0 else float(next["wins"]) / float(games)
	next["confidence"] = clamp01(float(next["confidence"]) * 0.7 + raw_confidence * 0.3)

	# 4. respect：你的强度（85/15 EWMA）。
	var player_strength := clamp01(float(player_delta) / 400.0)
	if player_blackjack:
		player_strength += 0.3
	if player_bust:
		player_strength -= 0.25
	next["respect"] = clamp01(float(next["respect"]) * 0.85 + clamp01(player_strength) * 0.15)

	# 5. grudge：不是 EWMA，是二值触发。
	#    判定是"你净赢超过自己那一注" —— 普通赢一注不算（会衰减 0.05），
	#    只有黑杰克的 1.5 倍赔付才算"赢得不光彩"。
	if player_delta > player_bet:
		next["grudge"] = clamp01(float(next["grudge"]) + 0.12)
	else:
		next["grudge"] = clamp01(float(next["grudge"]) - 0.05)

	# 6. 对玩家的画像（前 6 局不投票，样本太少）
	if int(next["hands_played"]) >= 6:
		var played := float(next["hands_played"])
		var profile: Dictionary = next["player_profile"]
		profile["aggressive"] = float(next["player_doubles"]) / played > 0.3
		profile["conservative"] = float(next["player_busts"]) / played < 0.15
		profile["chases"] = int(next["player_doubles"]) >= 3 and float(next["tilt"]) > 0.3

	# 7. 记忆碎片：最近 8 局原文，更早的压成一段 300 字以内的尾巴。
	var recent: Array = next["recent"]
	recent.append(describe_hand(result))
	if recent.size() > HAND_LIMIT:
		var dropped: String = recent.pop_front()
		var summary: String = str(next["summary"])
		var parts: PackedStringArray = []
		if summary != "":
			parts.append(summary)
		if dropped != "":
			parts.append(dropped)
		summary = "；".join(parts)
		if summary.length() > SUMMARY_LIMIT:
			summary = summary.substr(summary.length() - SUMMARY_LIMIT)
		next["summary"] = summary

	return next


## 一局的人话摘要，如 `第3局 对方18点/我20点，我赢（对方加了注）`。
static func describe_hand(result: Dictionary) -> String:
	var winner := str(result.get("winner", ""))
	var who := "打平"
	match winner:
		"PLAYER":
			who = "对方"
		"OPPONENT":
			who = "我"
	var base := "第%s局 对方%s点/我%s点，%s" % [
		str(result.get("hand_no", "?")),
		str(result.get("player_total", 0)),
		str(result.get("opponent_total", 0)),
		"打平" if who == "打平" else who + "赢",
	]
	if bool(result.get("player_doubled", false)):
		base += "（对方加了注）"
	return base


## 人格 → 表情档位。**只有这六个 id**（shocked 走 cue，不从这里出）。
static func mood(persona_in: Dictionary) -> String:
	var persona := ensure(persona_in)
	var tilt := float(persona["tilt"])
	var confidence := float(persona["confidence"])
	var net := int(persona["net_chips"])
	var grudge := float(persona["grudge"])
	var respect := float(persona["respect"])
	if tilt > 0.6:
		return "tilted"
	if confidence > 0.7 and net > 0:
		return "smug"
	if grudge > 0.5:
		return "grudge"
	if respect > 0.65:
		return "wary"
	if net < -300:
		return "shaken"
	return "calm"


## 表情 id → 鲸鱼娘素材的脸（多对一是故意的：记仇与上头都画成烦躁）。
static func face_for(mood_id: String, phase: String, thinking: bool) -> String:
	if thinking or phase == "OPPONENT_TURN":
		return "thinking"
	match mood_id:
		"smug":
			return "smug"
		"tilted", "grudge":
			return "panic"
		"wary":
			return "thinking"
		"shaken":
			return "sad"
		"shocked":
			return "shocked"
		_:
			return "idle"


## 人格 → 一段人话。注入提示词用（本地大脑也会拿它当语气选择依据）。
static func describe(persona_in: Dictionary) -> String:
	var persona := ensure(persona_in)
	var lines: PackedStringArray = []
	var tilt := float(persona["tilt"])
	var confidence := float(persona["confidence"])
	var net := int(persona["net_chips"])
	var grudge := float(persona["grudge"])
	var respect := float(persona["respect"])
	var recent: Array = persona["recent"]
	var summary := str(persona["summary"])
	var profile: Dictionary = persona["player_profile"]

	if tilt > 0.6:
		lines.append("你现在手气很差，心里有点烦躁，说话变得又急又冲，有时候会不管不顾地加注想一把捞回来。")
	elif confidence > 0.7 and net > 200:
		lines.append("你现在赢着钱，心情不错，有点得意，说话带点挑衅，也敢下大注。")
	elif grudge > 0.5:
		lines.append("你有点记恨对面——你觉得它赢得不光彩。你盯着它，想在接下来的牌里赢回来。")
	elif respect > 0.65:
		lines.append("你有点忌惮对面，它打得比你想的稳。所以你收着点，说话也少了。")
	elif net < -300:
		lines.append("你输了不少，心里发虚，下注变得保守，话也少了。")
	else:
		lines.append("你心情平稳，就是个来打牌的普通牌客。")

	var observations: PackedStringArray = []
	if bool(profile["aggressive"]):
		observations.append("对面爱加注，胆子不小")
	if bool(profile["conservative"]):
		observations.append("对面在 16 点附近很保守，不太敢要牌")
	if bool(profile["chases"]):
		observations.append("对面输了钱之后会变得更激进")
	if observations.size() > 0:
		lines.append("你对对面的观察：%s。" % "；".join(observations))

	if grudge > 0.4 and recent.size() > 0:
		var tail: Array = recent.slice(max(0, recent.size() - 2))
		lines.append("你还记得：%s。" % "；".join(tail))
	if summary != "":
		lines.append("更早的事你还记得个大概：%s" % summary)
	return "\n".join(lines)


## UI / 战绩面板用的摘要。
static func stats(persona_in: Dictionary) -> Dictionary:
	var persona := ensure(persona_in)
	return {
		"hands": int(persona["hands_played"]),
		"wins": int(persona["wins"]),
		"losses": int(persona["losses"]),
		"pushes": int(persona["pushes"]),
		"net_chips": int(persona["net_chips"]),
		"mood": mood(persona),
		"tilt": float(persona["tilt"]),
		"respect": float(persona["respect"]),
		"confidence": float(persona["confidence"]),
		"grudge": float(persona["grudge"]),
	}


## 下注胆量：人格 → 倍率。**只有这一个公式**，没有离散的倍率表。
## confidence 撑 ±0.4，tilt 最多扣 0.4，grudge 最多加 0.3。
## respect 与 net_chips 对下注没有任何数值影响（只通过散文影响模型）。
static func bet_multiplier(persona_in: Dictionary) -> float:
	var persona := ensure(persona_in)
	return 1.0 \
		+ (float(persona["confidence"]) - 0.5) * 0.8 \
		- float(persona["tilt"]) * 0.4 \
		+ float(persona["grudge"]) * 0.3
