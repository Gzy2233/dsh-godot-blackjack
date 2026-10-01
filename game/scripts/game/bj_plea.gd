class_name BjPlea
extends RefCounted

## 输光之后跟鲸鱼娘**自由对话**求情 —— 三轮打字，然后她按心情掷一个金额。
##
## 为什么做成自由对话：这是全局唯一一个轮到它居高临下、你要求它的时刻。
## 平时都是它嘴炮你；输光这一刻主动权在它手里，而它肯不肯借、借多少，
## 完全取决于你把它养成了什么脾气 —— 以及你这三句话说得怎么样。
##
## 分工（和整局游戏的哲学一致：**模型只说话，代码算账**）：
##   - **算账**在本地：心情值怎么动、掷多少钱、利息多少，全部是纯函数，
##     单测能一行行钉死。模型（或关键词识别）只负责"她这句话说得像不像她"。
##   - **说话**可以交给真模型（填了 API Key 时）；没填就用关键词判意图 + 预写台词。
##
## 规则：
##   - **心情值** 0..100，起点由人格决定（它忌惮你 / 有底气 / 赢着钱 → 高；
##     记仇 / 上头 / 自己也紧 → 低）
##   - **三次说话机会**。每句先判"你想干嘛"（装可怜 / 吹捧 / 激将 / 谈条件 /
##     骂它 / 威胁），再看**它现在的脾气**吃不吃这一套
##   - 三次说完，她掷一个金额：**心情越高，掷出高额的概率越大**；
##     掷得太低（觉得给这点没意义）就直接拒绝

const ROUNDS := 3
const THRESHOLD := 60
const MIN_SOFTNESS := 5
const MAX_SOFTNESS := 100

## 单次说话的基准分（乘上 affinity 与随机浮动）
const PLEA_BASE := 22
## 骂它 / 威胁它的惩罚
const INSULT_PENALTY := 18
const THREAT_PENALTY := 26

## "这话有没有用"的分水岭：affinity 高于它才加分，低于它**扣分**。
## 之前是"只要不是骂它就至少 +1"，等于说什么都不亏 —— 玩家可以乱按三轮。
## 现在说错话要付代价：她不吃这套的时候，你的心情值会往下掉。
const AFFINITY_PIVOT := 0.85
## 完全没说到点上（认不出意图）也要小扣一点，逼玩家真的动脑子
const NONE_PENALTY := 2

## 每借过一次钱，下次求情的起点就更低 —— **越借越难借**。
## 借钱是救命的，但也是要还的：她记得你上次还没还完。
const LOAN_HISTORY_PENALTY := 16

## 借出上限：最多这么多，且必须给它自己留够底注
const MAX_LOAN := 20_000_000
## 最低会给的额度（低于这个数她干脆拒绝）
const MIN_LOAN := 1_000_000
## 基础利息；每谈一次"还钱条件"再 +0.25
const BASE_INTEREST := 1.5
const DEAL_INTEREST := 0.25

## 意图 id
const INTENT_BEG := "beg"
const INTENT_FLATTER := "flatter"
const INTENT_TAUNT := "taunt"
const INTENT_DEAL := "deal"
const INTENT_INSULT := "insult"
const INTENT_THREAT := "threat"
const INTENT_NONE := "none"

const INTENT_LABELS := {
	"beg": "装可怜",
	"flatter": "吹捧它",
	"taunt": "激将",
	"deal": "谈条件",
	"insult": "骂它",
	"threat": "威胁它",
	"none": "没说到点上",
}

## 关键词判意图（本地大脑用；真模型走提示词，不用这套）。
##
## ⚠️ 这里全是**子串匹配**，所以词要挑"不会被别的意思顺带命中"的：
## 曾经侮辱词里有 `"就这"`，于是 `"就这样吧"` 被判成骂它、一次扣 20 分。
const INTENT_KEYWORDS := {
	"beg": ["求", "拜托", "可怜", "帮我", "行行好", "没钱", "输光", "惨", "穷", "救"],
	"flatter": ["厉害", "佩服", "服你", "高手", "牛", "学不", "打得好", "你强", "了不起"],
	"taunt": ["敢不", "不敢", "怕了", "赢回来", "翻本", "输回来", "怂", "没胆"],
	"deal": ["还你", "还钱", "利息", "双倍", "条件", "欠条", "保证", "一定还", "高利"],
	"insult": ["杂鱼", "废物", "垃圾", "菜", "笨", "蠢"],
	"threat": ["不还", "赖账", "跑路", "报复", "等着", "砸"],
}

## 四个"快速说"的模板（点一下填进输入框）
const QUICK_FILL := {
	"beg": "……我连底注都付不起了，行行好",
	"flatter": "你打得比我想的稳多了，我服",
	"taunt": "怎么？怕我翻了本把你赢回来？",
	"deal": "算我借的，双倍还你，欠条现在就写",
}

## 她的回应：按意图分"有效/无效"两档
const REPLY_GOOD := {
	"beg": ["……行吧，看你可怜", "杂鱼♡ 跪得倒是挺标准", "就这一次，记住"],
	"flatter": ["哼，你终于说了句实话", "知道就好♡", "算你有眼光"],
	"taunt": ["你说什么？！借就借！", "我等着看你输光", "别激我……好吧你激到我了"],
	"deal": ["欠条拿来", "利息我可不客气", "双倍？我记下了"],
}
const REPLY_BAD := {
	"beg": ["关我什么事", "杂鱼就该没钱", "自己去打工吧"],
	"flatter": ["少来这套", "你以为我会信？", "拍马屁没用"],
	"taunt": ["激将法？我可不傻", "你越急我越不借", "省省吧"],
	"deal": ["你拿什么还？", "欠条不值钱", "我不做亏本买卖"],
}
const REPLY_INSULT := [
	"你、你说什么？！", "输了钱还嘴硬？", "……我记住你了。", "杂鱼♡ 你自己听听你在说什么",
]
const REPLY_THREAT := [
	"威胁我？", "你拿什么跟我横？", "……你以为我会怕？",
]
const REPLY_NONE := [
	"……你到底想说什么？", "说重点。", "别绕了，说人话。",
]

const VERDICT_YES := [
	"行，拿去。输了别哭。",
	"记住了 —— 你欠我的♡",
	"……别让我后悔。",
]
## 心情值被扣到底：**不是"不借"，是"我不听了"** —— 只能重开
const VERDICT_ANGRY := [
	"够了。我不想再听你说一个字。",
	"我把话收回来 —— 一个 token 都没有，滚下桌。",
	"你连求人都不会，还打什么牌？",
	"……我后悔刚才没直接把你扔出去。",
]
const VERDICT_NO := [
	"没钱就别上桌。",
	"杂鱼♡ 下次记得带钱。",
	"我不借给输光的人。",
]


## 心情值起点：完全由"它现在是什么脾气"决定。纯函数，单测直接钉数值。
##
## `loans_taken` = 你已经跟它借过几次钱：**每借过一次，起点就往下压一截**。
## 所以同一个存档里，借钱这条路会一次比一次难走 —— 逼你迟早靠牌技而不是靠嘴。
static func initial_softness(persona: Dictionary, her_chips: int, loans_taken: int = 0) -> int:
	var p := BjPersona.ensure(persona)
	var score := 25.0
	score += float(p["respect"]) * 25.0     # 忌惮你 → 愿意留你在这张桌上
	score += float(p["confidence"]) * 20.0  # 有底气 → 出手大方
	score += clampf(float(p["net_chips"]) / 8.0e7, 0.0, 1.0) * 15.0  # 赢着钱 → 心情好（按 4 倍身家归一）
	score -= float(p["grudge"]) * 40.0      # 记仇 → 就是不救你
	score -= float(p["tilt"]) * 20.0        # 上头 → 没耐心听你废话
	score -= float(maxi(0, loans_taken)) * float(LOAN_HISTORY_PENALTY)
	var spare_ratio := clampf(float(maxi(0, her_chips)) / float(BjMachine.STARTING_CHIPS), 0.0, 1.5)
	score *= clampf(0.5 + spare_ratio * 0.5, 0.5, 1.25)
	return clampi(int(round(score)), MIN_SOFTNESS, MAX_SOFTNESS)


## 某种话术对"现在这个它"的效力。
static func affinity(intent: String, persona: Dictionary) -> float:
	var p := BjPersona.ensure(persona)
	var mood := BjPersona.mood(p)
	var respect := float(p["respect"])
	var confidence := float(p["confidence"])
	var grudge := float(p["grudge"])
	var tilt := float(p["tilt"])
	match intent:
		INTENT_BEG:
			var base := 1.2 if confidence > 0.5 else 0.7
			if mood == "smug":
				base += 0.3
			if grudge > 0.5:
				base -= 0.3
			return clampf(base, 0.2, 1.6)
		INTENT_FLATTER:
			var base := 1.3 if mood == "smug" else 0.6
			if grudge > 0.6:
				base = 0.3
			elif respect > 0.6:
				base += 0.2
			return clampf(base, 0.2, 1.6)
		INTENT_TAUNT:
			var base := 1.4 if (tilt > 0.5 or grudge > 0.6) else 0.5
			if respect > 0.7:
				base = 0.4
			return clampf(base, 0.2, 1.6)
		_:
			return 1.0


## 判意图：数关键词命中数，取最多的那个。认不出来就是 none。
##
## **骂它/威胁它优先判**：一句话里常常同时含正面词和负面词
## （"不借我就**不还**你钱"里既有"不还"也有"还"），
## 这种时候必须按负面算，否则嘴硬反而涨心情值。
static func intent_of(text: String) -> String:
	var lower := text.strip_edges()
	if lower == "":
		return INTENT_NONE
	for intent in [INTENT_THREAT, INTENT_INSULT]:
		for word in INTENT_KEYWORDS[intent]:
			if lower.contains(word):
				return intent
	var best := INTENT_NONE
	var best_hits := 0
	for intent in INTENT_KEYWORDS.keys():
		if intent == INTENT_THREAT or intent == INTENT_INSULT:
			continue
		var hits := 0
		for word in INTENT_KEYWORDS[intent]:
			if lower.contains(word):
				hits += 1
		if hits > best_hits:
			best_hits = hits
			best = intent
	return best


## 开局：建一份求情状态。
static func start(persona: Dictionary, her_chips: int, loans_taken: int = 0) -> Dictionary:
	return {
		"round": 0,
		"softness": initial_softness(persona, her_chips, loans_taken),
		"loans_taken": maxi(0, loans_taken),
		"interest": BASE_INTEREST,
		"used": [],
		"lines": [],
		"finished": false,
		"agreed": false,
		"failed": false,
		"her_chips": her_chips,
		"last_reply": "",
		"last_intent": INTENT_NONE,
	}


## 现在能借出多少：从它筹码里出，但必须给它自己留够底注。
static func loan_amount(her_chips: int) -> int:
	var spare := her_chips - BjMachine.MIN_BET * 2
	if spare <= 0:
		return 0
	return mini(spare, MAX_LOAN)


static func can_lend(her_chips: int) -> bool:
	return loan_amount(her_chips) >= MIN_LOAN


## 说一句话。返回新的状态（不改入参），里面带上她的回应与心情变化。
static func say(state: Dictionary, text: String, persona: Dictionary,
		rng: RandomNumberGenerator, reply_override: String = "") -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	if bool(next["finished"]):
		return next
	var clean := text.strip_edges()
	if clean == "":
		return next
	var intent := intent_of(clean)
	var delta := 0
	var roll := 0.85 + rng.randf() * 0.3
	match intent:
		INTENT_INSULT:
			# 骂它：她本来就不爽的时候更炸
			delta = -int(round(float(INSULT_PENALTY) * (1.0 + float(BjPersona.ensure(persona)["grudge"]))))
		INTENT_THREAT:
			delta = -THREAT_PENALTY
		INTENT_NONE:
			# 没说到点上：小扣。以前是 +1，等于鼓励玩家乱按。
			delta = -NONE_PENALTY
		_:
			# 分水岭在 AFFINITY_PIVOT：她吃这套才加分，不吃就**倒扣**。
			delta = int(round(float(PLEA_BASE) * (affinity(intent, persona) - AFFINITY_PIVOT) * roll))
			if intent == INTENT_DEAL:
				next["interest"] = float(next["interest"]) + DEAL_INTEREST
	next["softness"] = clampi(int(next["softness"]) + delta, MIN_SOFTNESS, MAX_SOFTNESS)
	next["round"] = int(next["round"]) + 1
	var used: Array = next["used"]
	used.append(intent)
	next["used"] = used
	next["last_intent"] = intent

	# 她的回应：真模型给的那句优先，否则按"这套管不管用"从预写台词里挑
	var reply := reply_override.strip_edges()
	if reply == "":
		var pool: Array = []
		match intent:
			INTENT_INSULT:
				pool = REPLY_INSULT
			INTENT_THREAT:
				pool = REPLY_THREAT
			INTENT_NONE:
				pool = REPLY_NONE
			_:
				pool = REPLY_GOOD[intent] if delta > 0 else REPLY_BAD[intent]
		reply = str(pool[rng.randi_range(0, pool.size() - 1)])
	next["last_reply"] = reply
	var lines: Array = next["lines"]
	lines.append({
		"you": clean,
		"her": reply,
		"intent": intent,
		"label": str(INTENT_LABELS[intent]),
		"delta": delta,
		"mood": BjPersona.mood(persona),
	})
	next["lines"] = lines

	# 心情值被扣到底 → 她不想听了：**直接终止对话，宣布彻底失败**（只能重开）
	if int(next["softness"]) <= MIN_SOFTNESS:
		next["finished"] = true
		next["failed"] = true
		next["agreed"] = false
		next["amount"] = 0
		next["verdict"] = VERDICT_ANGRY[rng.randi_range(0, VERDICT_ANGRY.size() - 1)]
		next["lines"] = next["lines"]
		return next

	if int(next["round"]) >= ROUNDS:
		next = _settle(next, rng)
	return next


## 三轮说完：按心情值掷一个金额。
##
## **心情越高，掷出高额的概率越大**：
##   roll = 心情/100 + 随机(-0.3..0.3)，金额在 [MIN_LOAN, 上限] 之间按 roll 插值；
##   roll 太小（她根本不想给）就直接拒绝。
static func _settle(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	var softness := float(next["softness"])
	var spare := float(loan_amount(int(next["her_chips"])))
	var roll := clampf(softness / 100.0 + rng.randf_range(-0.3, 0.3), 0.0, 1.0)
	var amount := 0
	if spare >= float(MIN_LOAN) and roll >= 0.15:
		# 取整到 10 万：金额读起来干净（"借你 340 万"），也不会有零头
		amount = int(round(lerpf(float(MIN_LOAN), spare, roll) / 100_000.0)) * 100_000
	next["finished"] = true
	next["roll"] = roll
	next["amount"] = amount
	next["agreed"] = amount >= BjMachine.MIN_BET
	var pool: Array = VERDICT_YES if bool(next["agreed"]) else VERDICT_NO
	next["verdict"] = str(pool[rng.randi_range(0, pool.size() - 1)])
	if not bool(next["agreed"]):
		next["amount"] = 0
	return next


## 兼容旧调用（等价于 say）。
static func apply(state: Dictionary, text: String, persona: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	return say(state, text, persona, rng)


## 谈成之后：欠多少。
static func deal_terms(state: Dictionary) -> Dictionary:
	var amount := int(state.get("amount", 0))
	var interest := float(state.get("interest", BASE_INTEREST))
	return {
		"amount": amount,
		"interest": interest,
		"debt": int(round(float(amount) * interest)),
	}


## 还债：赢的钱**一半**先还它，还完为止。纯函数，单测直接钉数值。
static func repayment(player_delta: int, debt: int) -> Dictionary:
	if player_delta <= 0 or debt <= 0:
		return {"repay": 0, "left": debt}
	var repay := mini(debt, int(floor(float(player_delta) / 2.0)))
	return {"repay": repay, "left": debt - repay}
