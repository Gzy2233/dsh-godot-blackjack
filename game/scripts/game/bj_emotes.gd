class_name BjEmotes
extends RefCounted

## 结算演出：把一局的 outcome 翻成"情绪 + 台词 + 特效"。
##
## 移植自 dsh-deepseek-blackjack/src/host/emotes.js，并修掉两个原版问题：
##   1. `bigThreshold = 150` 是亿级筹码改造前的遗留值 —— 每一注都算"大"，
##      于是 player_wins / opponent_wins / opponent_wins_small 三张表几乎永远
##      触发不到，全被 *_big 抢走。这里改成相对下注区间（BjMachine.BIG_BET）。
##   2. 原版算出来的 fx 从来没被渲染层用上（前端根本没写 data-fx 属性），
##      所有特效都是死代码。这里 fx 由 UI 真的执行。

const KIND_EMOTE := "emote"
const KIND_PLAY := "play"


static func _base() -> Dictionary:
	return {"mood": "calm", "bubble": "", "fx": [], "priority": 1, "kind": KIND_EMOTE}


## 一局的演出。first-match-wins 的瀑布，顺序是原版定死的（别顺手排）。
static func cue_for_hand(outcome: Dictionary, picker: BjLines.Picker, lines: Dictionary = BjLines.DEFAULT_LINES) -> Dictionary:
	var cue := _base()
	var player_delta: int = int(outcome.get("player_delta", 0))
	var opponent_delta: int = int(outcome.get("opponent_delta", 0))
	var player_won := player_delta > 0
	var opponent_won := opponent_delta > 0

	# 1. 平局
	if str(outcome.get("winner", "")) == "PUSH":
		cue["bubble"] = picker.pick(lines["push"], "push")
		cue["fx"] = ["push_glow"]
		return cue

	# 2. 你拿到黑杰克（优先级最高，排在对手黑杰克之前）
	if bool(outcome.get("player_blackjack", false)):
		cue["mood"] = "shocked"
		cue["bubble"] = picker.pick(lines["player_blackjack"], "player_blackjack")
		cue["fx"] = ["bj_burst", "tokens_fly_to_player"]
		cue["priority"] = 3
		return cue

	# 3. 它自己拿到黑杰克
	if bool(outcome.get("opponent_blackjack", false)):
		cue["mood"] = "smug"
		cue["bubble"] = picker.pick(lines["opponent_blackjack"], "opponent_blackjack")
		cue["fx"] = ["bj_burst", "tokens_fly_to_opponent"]
		cue["priority"] = 3
		return cue

	# 4. 你爆了，它赢了
	if bool(outcome.get("player_bust", false)) and opponent_won:
		cue["mood"] = "smug"
		cue["bubble"] = picker.pick(lines["player_bust"], "player_bust")
		cue["fx"] = ["bust_flash", "tokens_fly_to_opponent"]
		cue["priority"] = 2
		return cue

	# 5. 它爆了，你赢了
	if bool(outcome.get("opponent_bust", false)) and player_won:
		cue["mood"] = "shaken"
		cue["bubble"] = picker.pick(lines["opponent_bust"], "opponent_bust")
		cue["fx"] = ["bust_flash", "tokens_fly_to_player"]
		cue["priority"] = 2
		return cue

	# 6. 它赢钱
	if opponent_won and not player_won:
		cue["mood"] = "smug"
		if opponent_delta >= BjMachine.BIG_BET:
			cue["bubble"] = picker.pick(lines["opponent_wins_big"], "opponent_wins_big")
			cue["fx"] = ["tokens_fly_to_opponent", "screen_shake"]
			cue["priority"] = 3
		elif opponent_delta <= BjMachine.MIN_BET:
			# 小赚：原版这张表是死的，现在真的会说话了。
			cue["bubble"] = picker.pick(lines["opponent_wins_small"], "opponent_wins_small")
			cue["fx"] = ["tokens_fly_to_opponent"]
			cue["priority"] = 1
		else:
			cue["bubble"] = picker.pick(lines["opponent_wins"], "opponent_wins")
			cue["fx"] = ["tokens_fly_to_opponent"]
			cue["priority"] = 2
		return cue

	# 7. 你赢钱
	if player_won and not opponent_won:
		cue["mood"] = "sad"
		if player_delta >= BjMachine.BIG_BET:
			cue["bubble"] = picker.pick(lines["player_wins_big"], "player_wins_big")
			cue["fx"] = ["tokens_fly_to_player", "screen_shake"]
			cue["priority"] = 3
		else:
			cue["bubble"] = picker.pick(lines["player_wins"], "player_wins")
			cue["fx"] = ["tokens_fly_to_player"]
			cue["priority"] = 2
		return cue

	# 8. 罕见：两边都没赢钱
	cue["bubble"] = picker.pick(lines["idle"], "idle")
	return cue


## 玩家加注被接受时立刻触发（不等结算）。
static func cue_for_player_double(picker: BjLines.Picker, lines: Dictionary = BjLines.DEFAULT_LINES) -> Dictionary:
	var cue := _base()
	cue["mood"] = "wary"
	cue["bubble"] = picker.pick(lines["player_double"], "player_double")
	return cue


## 空闲（还没开局 / 等你下注）。
static func cue_for_idle(picker: BjLines.Picker, lines: Dictionary = BjLines.DEFAULT_LINES) -> Dictionary:
	var cue := _base()
	cue["bubble"] = picker.pick(lines["idle"], "idle")
	cue["priority"] = 0
	return cue


## "正在思考" + 可选一句打牌台词。
static func cue_for_thinking(bubble: String = "") -> Dictionary:
	var cue := _base()
	cue["mood"] = "calm"
	cue["bubble"] = bubble
	if bubble != "":
		cue["kind"] = KIND_PLAY
	return cue
