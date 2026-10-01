class_name BjLines
extends RefCounted

## 两套台词。
##
## **演出台词**（DEFAULT_LINES）：预写、零成本、可以夸张 —— 移植自
## dsh-deepseek-blackjack/src/host/emotes.js，**逐字照搬，不许改写**。
## 它由结算事件触发，是角色的"情绪反应"，像格斗游戏的胜利台词。
##
## **打牌台词**（TABLE_TALK / MOOD_TALK）：原版由 DeepSeek 实时生成
## （`say` 字段）。本地大脑不会说话，但牌桌不能变成哑巴 ——
## 所以这里按**牌面局势**索引补了一套，接真模型时自动让位给模型。
##
## 两套必须分开的理由（见 docs/两套台词机制.md）：
## 结算演出要求零延迟，实时打牌要求"真的看得见你的牌"。混在一起会两头不讨好。


## 演出台词库。12 类，全部来自原版。
const DEFAULT_LINES := {
	"player_wins": [
		"我的 token……",
		"呜……我的 token 飞走了……",
		"这局不算，我刚才分心了",
		"你等着，我马上赢回来",
		"……我的 token 啊",
		"哼，运气好而已",
	],
	"player_wins_big": [
		"我的 token！！！",
		"不……那可是我攒了好久的 token……",
		"你、你怎么能这样……",
		"这把不算！这把绝对不算！",
		"呜哇——我的 token 全没了……",
	],
	"opponent_wins": [
		"杂鱼♡",
		"就这？",
		"token 我收下了～",
		"谢谢惠顾～",
		"杂鱼就是杂鱼",
		"哎，又赢了，好无聊",
		"你的 token 归我了",
	],
	"opponent_wins_big": [
		"杂鱼♡ 杂鱼♡ 杂鱼♡",
		"哇——好多 token！谢谢款待～",
		"就这点水平也敢下这么大注？",
		"你的 token 真好赚啊～",
		"菜就多练，别送 token 了",
	],
	"player_bust": [
		"爆了爆了！",
		"哈哈哈哈，贪心了吧",
		"杂鱼♡ 连 21 点都算不明白",
		"哎哟，这张牌你也要？",
		"谢谢你的 token～",
	],
	"opponent_bust": [
		"啊……爆了",
		"……我看错了",
		"这牌有问题吧？",
		"唔，失误失误",
		"不算不算，重来",
	],
	"push": [
		"……平了",
		"算你走运",
		"哼，便宜你了",
		"这局白打了",
	],
	"player_blackjack": [
		"Blackjack？！",
		"你运气也太好了吧……",
		"呜……赔率还这么高……",
		"不行，这局我不服",
	],
	"opponent_blackjack": [
		"Blackjack！杂鱼♡",
		"看到没？这才叫打牌",
		"哇哦～我运气来了",
		"你的 token 保不住了～",
	],
	"player_double": [
		"哦？还敢加注？",
		"胆子不小嘛",
		"那我就看你怎么办",
		"加注？我陪你",
	],
	"idle": [
		"再来一局？",
		"这次我认真了",
		"你还有多少 token？",
		"别磨蹭，快点下注",
		"……",
	],
	# 原版有这张表但**从来没有任何代码引用它** —— 死表。
	# 这里靠 BjMachine.BIG_BET 的相对阈值把它接上：它赢一点点时的小得意。
	"opponent_wins_small": [
		"小赚一点～",
		"收下了",
		"谢谢～",
		"嗯，还行",
	],
	# ---- 以下为本地大脑新增：真模型接上后这些是兜底 ----
	"player_blackjack_shock": [
		"Blackjack？！你……",
		"等等，这牌不对吧？！",
		"呜哇——你也太顺了",
		"不可能，绝对不可能",
	],
}

## 按情绪索引的兜底台词（原版 TAUNT_TEMPLATES，未接线的那套）。
const TAUNT_TEMPLATES := {
	"smug": ["就这？", "你还敢跟？", "这局我稳了", "再加点？", "杂鱼♡"],
	"tilted": ["这牌有问题吧", "你别得意", "我要赢回来", "手气真背"],
	"wary": ["……我收着点", "你这人不好对付", "我看不透你"],
	"shaken": ["我的 token……", "你怎么老赢", "这局我认了"],
	"calm": ["你想清楚再说", "我等着", "要牌还是停？", "你犹豫什么"],
}

## 局势台词：本地大脑"看得见牌"的那部分。
## 单挑里你的两张牌都是明的，所以它真的知道自己是领先还是落后。
const TABLE_TALK := {
	"my_turn_strong": [
		"我够了，你看着办",
		"这手我不用再要了",
		"你猜我几点？",
		"稳了，这局稳了",
	],
	"my_turn_weak": [
		"……还得再要一张",
		"这牌也太烂了",
		"牌靴你是不是针对我",
		"再来一张，凑合着打",
	],
	"my_turn_mid": [
		"再赌一张",
		"风险我认了",
		"这时候不能怂",
		"我看牌靴的",
	],
	"i_ahead": [
		"我现在比你大",
		"你得追我了",
		"这局我拿捏着",
	],
	"i_behind": [
		"得追啊",
		"你这点数……难办了",
		"不能停，停了就输",
	],
	"you_busted": [
		"爆了爆了！",
		"白送的局",
		"谢谢你的 token～",
	],
	"your_scary": [
		"你那明牌……有点东西",
		"哼，大牌了不起？",
		"你这牌面挺唬人",
	],
	"your_weak": [
		"你那牌，我不怕",
		"就这明牌还敢跟？",
		"你这局悬了",
	],
	"i_hit": [
		"要一张",
		"再来",
		"给我张小的",
	],
	"i_stand": [
		"我不要了",
		"行了，就这些",
		"你请",
	],
	"count_high": [
		"剩下的牌里大牌多，我心里有数",
		"这靴子的牌我数着呢",
		"好牌要来了",
	],
	"count_low": [
		"这靴子没什么大牌了",
		"小牌都发完了",
		"牌靴不太妙啊",
	],
	"betting": [
		"押多少？我看着呢",
		"你敢押大我就敢跟",
		"来，这局押多点",
		"别抠门啊",
		"我筹码还多着呢",
	],
	"bet_big": [
		"押这么大？我喜欢",
		"想吓我？我跟",
		"你这么有底气？",
		"行啊，那我就陪你玩大的",
	],
	"bet_small": [
		"就押这点？",
		"这么小气啊",
		"怕了？",
		"你这注额，我都懒得认真",
	],
}

## 情绪台词：同一个局势下，不同人格说出不同味道。
const MOOD_TALK := {
	"smug": [
		"杂鱼♡",
		"这局我拿定了",
		"要不要再押大点？",
		"你的 token 我先记账上了",
		"谢谢惠顾～",
		"就这水平也敢坐我对面",
	],
	"tilted": [
		"这牌绝对有问题",
		"再来！我不信邪",
		"你敢不敢押大点",
		"我今天手气背到家了",
		"不算不算，重来",
	],
	"grudge": [
		"你上次那手我可记着呢",
		"这次我要赢回来",
		"赢得不光彩，你心里清楚",
		"别得意，账我记着",
	],
	"wary": [
		"……我收着点",
		"你这人不好对付",
		"我看不透你",
		"先稳一手",
	],
	"shaken": [
		"我的 token……",
		"你怎么老赢",
		"这局我认了",
		"……不玩了不玩了",
	],
	"calm": [
		"你想清楚再说",
		"我等着",
		"要牌还是停？",
		"你犹豫什么",
	],
}


## 台词选择器：均匀随机 + **同一条不连续出现两次**。
## 原版上限 8 次尝试，这里保留同样的语义（池子小于 2 时直接给）。
class Picker extends RefCounted:
	var _last: Dictionary = {}
	var _rng: RandomNumberGenerator

	func _init(rng: RandomNumberGenerator = null) -> void:
		_rng = rng
		if _rng == null:
			_rng = RandomNumberGenerator.new()
			_rng.randomize()

	func pick(pool: Array, key: String) -> String:
		if pool.is_empty():
			return ""
		if pool.size() == 1:
			_last[key] = pool[0]
			return pool[0]
		var previous: String = _last.get(key, "")
		var chosen: String = ""
		for _attempt in range(8):
			var candidate: String = pool[_rng.randi_range(0, pool.size() - 1)]
			if candidate != previous:
				chosen = candidate
				break
		if chosen == "":
			chosen = pool[_rng.randi_range(0, pool.size() - 1)]
		_last[key] = chosen
		return chosen


## 取一条局势台词。35% 的概率走情绪池，让同一局势下人格有存在感。
static func talk_for(situation: String, mood_id: String, picker: Picker) -> String:
	if picker == null:
		return ""
	if MOOD_TALK.has(mood_id) and picker._rng.randf() < 0.35:
		return picker.pick(MOOD_TALK[mood_id], "mood:" + mood_id)
	if TABLE_TALK.has(situation):
		return picker.pick(TABLE_TALK[situation], "talk:" + situation)
	return picker.pick(DEFAULT_LINES["idle"], "idle")
