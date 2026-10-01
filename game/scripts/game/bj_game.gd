class_name BjGame
extends Node

## 牌桌编排：一局从下注到摊牌的完整流程（**单挑版**，没有庄家）。
##
## 它负责把"引擎（BjMachine）"、"大脑（本地或真模型）"、"人格"、"演出"、
## "存档"串起来，并发信号给视图 —— 视图只做渲染和转发点击，不做规则。
##
## 经济学：双方各押同样的注，赢家拿走对方那份。所以这里**只**需要一个注额，
## 由你定、它跟；它跟不动就按它的筹码封顶（引擎会拒）。
##
## 原版在这里踩过的坑，这里都堵上了：
##   - 它的回合可能卡住（原版 20 局里出现 2 次整桌冻结）
##     → 回合上限 + 强制停牌保险丝，摊牌之前一定把阶段推出去。
##   - 重复点击导致并发动作 → acting 忙碌锁。
##   - 引擎拒绝它的动作 → 转停牌并记日志，绝不吞掉。

signal state_changed
signal hand_dealt(events: Array)
signal action_events(events: Array)
signal cues_changed(cue: Dictionary)
signal thinking_changed(thinking: bool)
signal settled(outcome: Dictionary)
signal notice(message: String)
## 你付不起底注了 —— 该让它来决定你的下场（求情借钱 / 重新开始）
signal bankrupt
## 它输光了（弹一次庆祝 CG）
signal opponent_bankrupt
## 求情小游戏的状态变了
signal plea_changed(state: Dictionary)
## 它答应借钱了
signal loan_granted(terms: Dictionary)
## 破了历史最高筹码纪录（视图弹「新纪录！」）
signal new_record(best: int, previous: int)

## 它单局最多行动多少次（防死循环的硬上限）。
const OPPONENT_LOOP_CAP := 20

## 视图的动画节奏（必须与 BjTableView 的常量一致，逻辑侧只等这么久）。
const DEAL_STEP := 0.32
const DEAL_ANIM := 0.26
const HIT_PAUSE := 0.55
const SETTLE_PAUSE := 0.5

var machine: BjMachine
var persona: Dictionary = {}
var picker: BjLines.Picker
var profile: Dictionary = {}
var settings: Dictionary = {}

var brain_local: BjBrainLocal
var brain_llm: BjBrainLlm

var pending_bet: int = BjMachine.MIN_BET * 2
var cue: Dictionary = {}
var thinking := false
var acting := false
var last_result: Dictionary = {}
## 欠它的债。赢的钱一半先还，还完为止。
var debt := 0
## 求情小游戏的状态（空字典 = 没在进行）
var plea_state: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	picker = BjLines.Picker.new(_rng)
	machine = BjMachine.new()
	load_state()


func load_state() -> void:
	profile = BjProfile.load_profile()
	settings = BjProfile.load_settings()
	var saved_persona: Variant = profile.get("persona", {})
	if saved_persona is Dictionary and not saved_persona.is_empty():
		persona = saved_persona
	else:
		persona = BjPersona.empty()
	machine.player_chips = int(profile.get("player_chips", BjMachine.STARTING_CHIPS))
	machine.opponent_chips = int(profile.get("opponent_chips", BjMachine.STARTING_CHIPS))
	machine.hand_no = int(profile.get("hand_no", 0))
	debt = int(profile.get("debt", 0))
	# 旧存档没有 best_chips：静默补一条（不弹「新纪录！」，那不是你刚打出来的）
	profile["best_chips"] = maxi(best_chips(), machine.player_chips)
	_clamp_pending_bet()
	pending_bet = machine.min_stake() * 2
	_clamp_pending_bet()

	brain_local = BjBrainLocal.new()
	brain_local.persona = persona
	add_child(brain_local)
	brain_llm = BjBrainLlm.new()
	_read_dsh_env()
	_apply_llm_settings()
	brain_llm.fallback = brain_local
	add_child(brain_llm)

	cue = BjEmotes.cue_for_idle(picker)
	state_changed.emit()
	# 开局就付不起底注（旧存档输光过，或者涨注涨到付不起）→ 直接进"输光"流程
	if machine.player_chips < machine.min_stake():
		bankrupt.emit.call_deferred()


func _clamp_pending_bet() -> void:
	var floor_bet := machine.min_stake()
	pending_bet = clampi(pending_bet, floor_bet, maxi(floor_bet, machine.max_stake()))


## ---------------------------------------------------------------- DSH 自动连接
##
## 作为 **DSH 插件**运行时，宿主会把 DeepSeek 凭据通过**环境变量**注入本进程
## （见 `plugin/lib/index.js` 里 `spawn(..., { env })` 那一段，key 来自
## `~/.dsh/.credentials.yaml`，也就是 DSH 自己正在用的那把）。
##
## 于是玩家**装完插件点一下就能玩，不需要自己填 key**。
##
## 安全边界：
##   - 宿主给的 key **只在内存里用**，绝不写进存档（存档是明文 JSON）、不进日志；
##   - 设置页里手填的 key 仍然有效，只是**优先级更低**（宿主注入的赢）；
##   - 环境变量为空 = 不是从插件启动的 → 一切照旧，回到手动模式。
const ENV_API_KEY := "DEEPSEEK_API_KEY"
const ENV_BASE_URL := "DEEPSEEK_BASE_URL"
const ENV_MODEL := "DEEPSEEK_MODEL"

## 宿主注入的凭据（空 = 不是从插件启动的）
var dsh_key := ""
var dsh_base_url := ""
var dsh_model := ""


## 读宿主注入的环境变量（`_ready` 里调一次）。
func _read_dsh_env() -> void:
	dsh_key = OS.get_environment(ENV_API_KEY).strip_edges()
	dsh_base_url = OS.get_environment(ENV_BASE_URL).strip_edges()
	dsh_model = OS.get_environment(ENV_MODEL).strip_edges()
	if auto_connected():
		print("[blackjack] 已自动连接 DSH（宿主注入了 DeepSeek 凭据，无需手填 key）")


## 是不是由 DSH 插件启动、并且自动连上了。
func auto_connected() -> bool:
	return dsh_key != ""


## 实际生效的 key：宿主注入的优先于玩家手填的。
func effective_api_key() -> String:
	if dsh_key != "":
		return dsh_key
	return str(settings.get("api_key", "")).strip_edges()


## 真模型大脑的配置：宿主注入的凭据**覆盖**存档里的。
func _apply_llm_settings() -> void:
	var llm_settings: Dictionary = settings.duplicate()
	if auto_connected():
		llm_settings["api_key"] = dsh_key
		if dsh_base_url != "":
			llm_settings["endpoint"] = dsh_base_url.rstrip("/") + "/chat/completions"
		if dsh_model != "":
			llm_settings["model"] = dsh_model
	brain_llm.configure(llm_settings)


## 当前用哪个大脑：**自动连接**或玩家自己打开了开关，且 key 可用才走真模型。
func brain() -> Node:
	var want_llm := bool(settings.get("use_llm", false)) or auto_connected()
	if want_llm and brain_llm.is_ready():
		return brain_llm
	return brain_local


func using_llm() -> bool:
	return brain() == brain_llm


func persist() -> void:
	profile["persona"] = persona
	profile["player_chips"] = machine.player_chips
	profile["opponent_chips"] = machine.opponent_chips
	profile["hand_no"] = machine.hand_no
	profile["debt"] = debt
	profile["version"] = BjProfile.VERSION
	BjProfile.save_profile(profile)


## 历史最高筹码（跨局、跨重开都保留 —— 这是长期目标）。
func best_chips() -> int:
	return int(profile.get("best_chips", BjMachine.STARTING_CHIPS))


## 刷新最高筹码：破了纪录就发信号让视图弹提示。
## **只在摊牌后调用**，借钱进来的钱不算纪录（不然"借钱冲纪录"就太廉价了）。
func _update_best_chips() -> void:
	var best := best_chips()
	if machine.player_chips > best:
		profile["best_chips"] = machine.player_chips
		new_record.emit(machine.player_chips, best)


## 设定注额：夹到 [最小注, min(上限, 双方筹码)]。
func set_bet(amount: int) -> void:
	var floor_bet := machine.min_stake()
	pending_bet = clampi(amount, floor_bet, maxi(floor_bet, machine.max_stake()))
	state_changed.emit()


## 可选的筹码面额：跟着下注走 —— 最小注、2 倍、最大注（去重、降到开得起的范围内）。
func bet_options() -> Array:
	var floor_bet := machine.min_stake()
	var high := machine.max_stake()
	var options: Array = []
	for value in [floor_bet, floor_bet * 2, floor_bet * BjMachine.MAX_STAKE_MULTIPLIER]:
		if value <= high and not options.has(value):
			options.append(value)
	if options.is_empty():
		options.append(maxi(1, high))
	return options


## 该不该给"ALL IN"按钮：**最大注已经超过你能拿出来的钱**时出现。
## 这时候下注栏那几个面额也顶不到上限，"一把梭"才是真正的选项。
func shows_all_in() -> bool:
	var floor_bet := machine.min_stake()
	return machine.player_chips < floor_bet * BjMachine.MAX_STAKE_MULTIPLIER \
		and machine.all_in_stake() >= floor_bet


# ---------------------------------------------------------------- ALL IN

## ALL IN 能押多少（双方里更穷的那一边的全部筹码，不受 MAX_BET 限制）。
func all_in_stake() -> int:
	return machine.all_in_stake()


func can_all_in() -> bool:
	if acting:
		return false
	if machine.has_hand() and machine.phase() != BjMachine.PHASE_SETTLE:
		return false
	return machine.can_all_in()


## 现在是不是已经全押了。
func is_all_in() -> bool:
	return can_all_in() and pending_bet >= all_in_stake()


## 一把梭。
func set_bet_all_in() -> void:
	if not can_all_in():
		return
	pending_bet = all_in_stake()
	state_changed.emit()


func can_deal() -> bool:
	if acting:
		return false
	if machine.has_hand() and machine.phase() != BjMachine.PHASE_SETTLE:
		return false
	return machine.validate_stake(pending_bet) == ""


## 送给大脑的视野。**这是隐藏信息的边界**：它的暗牌、牌靴顺序都不在里面。
##
## 故意做成静态函数（参数名不叫 machine，避免遮蔽同名成员变量）：
## 调用点**每轮都必须按当前牌面重新调用它**。曾经的 bug 是把它算一次然后
## 循环里反复用，于是它拿着 20 点还在要牌。返回的牌面一律是深拷贝 ——
## 视野是快照，不是引擎内存的活窗口。
static func view_of(board: BjMachine, persona_desc: String, last_outcome_text: String) -> Dictionary:
	var player_hand := board.player_hand()
	var opponent_hand := board.opponent_hand()
	return {
		"hand_no": board.hand_no + 1,
		"stake": board.stake(),
		"min_bet": board.min_stake(),
		"max_bet": board.max_stake(),
		"stake_level": board.stake_level(),
		"opponent_hand": opponent_hand.duplicate(true),
		"opponent_total": BjHand.value(opponent_hand),
		"opponent_soft": BjHand.has_soft_ace(opponent_hand),
		"opponent_chips": board.opponent_chips,
		"player_hand": player_hand.duplicate(true),
		"player_total": BjHand.value(player_hand),
		"player_bust": board.has_hand() and board.state["player"]["busted"],
		"player_blackjack": BjHand.is_blackjack(player_hand),
		"player_doubled": board.has_hand() and board.state["player"]["doubled"],
		"player_chips": board.player_chips,
		"opponent_up_value": _up_value(opponent_hand),
		# 单挑里你的牌是全公开的（两张都明），所以它的决策依据比原版更足
		"player_up_value": _up_value(player_hand),
		"shoe_remaining": board.shoe.remaining(),
		"running_count": board.running_count,
		"persona_desc": persona_desc,
		"last_outcome": last_outcome_text,
	}


func build_view() -> Dictionary:
	return view_of(machine, BjPersona.describe(persona), _last_outcome_text())


static func _up_value(hand: Array) -> int:
	if hand.is_empty():
		return 10
	return BjCards.rank_value(hand[0]["rank"])


func _last_outcome_text() -> String:
	if last_result.is_empty():
		return "（第一局）"
	var delta: int = int(last_result.get("player_delta", 0))
	if delta > 0:
		return "你赢了 %s token" % BjTokens.format(delta)
	if delta < 0:
		return "你输了 %s token" % BjTokens.format(-delta)
	return "平局"


func legal_actions() -> Array:
	if acting:
		return []
	return machine.legal_actions()


func _set_cue(new_cue: Dictionary) -> void:
	cue = new_cue
	cues_changed.emit(cue)


# ---------------------------------------------------------------- 开局

## 开一局：先让它对注额说一句（真模型这里是发牌前的调用），再发牌。
func deal() -> void:
	if not can_deal():
		return
	acting = true
	state_changed.emit()

	var amount := pending_bet
	var opening_view := {
		"hand_no": machine.hand_no + 1,
		"stake": amount,
		"opponent_chips": machine.opponent_chips,
		"player_chips": machine.player_chips,
		"last_outcome": _last_outcome_text(),
		"persona_desc": BjPersona.describe(persona),
	}
	thinking = true
	thinking_changed.emit(true)
	var opening: Dictionary = await brain().opening_line(opening_view)
	thinking = false
	thinking_changed.emit(false)

	var result := machine.start_hand(amount)
	if not result["ok"]:
		acting = false
		notice.emit(str(result["error"]))
		state_changed.emit()
		return

	last_result = {}
	_set_cue(BjEmotes.cue_for_thinking(str(opening.get("say", ""))))
	hand_dealt.emit(result["events"])
	state_changed.emit()
	# 等发牌动画走完（4 张：3 个间隔 + 一张牌的动画时长）
	await get_tree().create_timer(DEAL_STEP * 3 + DEAL_ANIM).timeout
	acting = false
	state_changed.emit()

	# 先手轮换：它先手的局，发完牌就该它行动（你可能连按钮都还没看到）
	if machine.state.get("first_actor", "") == BjMachine.WHO_OPPONENT:
		notice.emit("本局它先手 —— 它的牌全明，你可以看清了再决定")
	await _advance_turn()


## **把回合交给该行动的一方**。
##
## 先手轮换之后，"你先→它→摊牌"这条固定链子不成立了：
## 它先手的局里，发完牌就是它的回合，它打完才轮到你；
## 你打完如果它已经打完（它先手那种局），就要直接摊牌。
func _advance_turn() -> void:
	if machine.phase() == BjMachine.PHASE_OPPONENT_TURN:
		_begin_opponent_turn()
		await _run_opponent_turn()
	if machine.phase() == BjMachine.PHASE_SETTLE and machine.outcome().is_empty():
		await get_tree().create_timer(SETTLE_PAUSE).timeout
		_finish_hand()


## 轮到它之前**先翻开暗牌**（标准 21 点：庄家先亮牌再补牌）。
## 好处：它在自己回合补的每张牌都是明的，玩家看到的点数就是真实点数。
func _begin_opponent_turn() -> void:
	var reveal := machine.reveal_opponent()
	if not reveal.is_empty():
		action_events.emit(reveal)
		state_changed.emit()


# ---------------------------------------------------------------- 你的行动

func player_action(action: String) -> void:
	if acting:
		notice.emit("上一个动作还在处理中，请稍候")
		return
	if not machine.has_hand():
		notice.emit("这一局还没开始，请先点「发牌」")
		return
	if machine.phase() != BjMachine.PHASE_PLAYER_TURN:
		if machine.phase() == BjMachine.PHASE_SETTLE:
			notice.emit("本局已经结束了，请点「再来一局」")
		else:
			notice.emit("现在不是你的回合（%s），请稍候" % machine.phase())
		return

	acting = true
	if action == "DOUBLE":
		# 加注被接受的瞬间就出反应，不等摊牌
		_set_cue(BjEmotes.cue_for_player_double(picker))
	var result := machine.player_action(action)
	if not result["ok"]:
		acting = false
		notice.emit(str(result["error"]))
		state_changed.emit()
		return
	action_events.emit(result["events"])
	state_changed.emit()
	await get_tree().create_timer(HIT_PAUSE).timeout
	await _advance_turn()
	acting = false
	state_changed.emit()


# ---------------------------------------------------------------- 它的回合 + 摊牌

func _run_opponent_turn() -> void:
	var guard := 0
	while machine.phase() == BjMachine.PHASE_OPPONENT_TURN and guard < OPPONENT_LOOP_CAP:
		guard += 1
		# **每一轮都必须重新构建视野**。
		# 这里曾经把 build_view() 写在循环外面，于是它整局都在按"开局那两张牌"
		# 做决策 —— 拿到 20 点还会继续要牌直到爆。视野必须跟着手牌走。
		var view := build_view()
		thinking = true
		thinking_changed.emit(true)
		var decision: Dictionary = await brain().decide(view, ["HIT", "STAND"], {"persona_desc": view["persona_desc"]})
		thinking = false
		thinking_changed.emit(false)

		var action := str(decision.get("action", "STAND"))
		var result := machine.opponent_action(action)
		if not result["ok"]:
			# 引擎拒绝了它的动作（真模型可能给出非法动作）：转停牌，别把桌子卡住。
			push_warning("它的动作被引擎拒绝：%s，转为停牌" % str(result["error"]))
			result = machine.opponent_action("STAND")
			if not result["ok"]:
				break
		action_events.emit(result["events"])
		var say := str(decision.get("say", ""))
		if say != "":
			var talk := BjEmotes.cue_for_thinking(say)
			if str(decision.get("note", "")) != "":
				talk["note"] = str(decision.get("note", ""))
			_set_cue(talk)
		elif str(decision.get("source", "")) == "fallback":
			var note_cue := BjEmotes.cue_for_thinking("")
			note_cue["note"] = str(decision.get("note", ""))
			_set_cue(note_cue)
		state_changed.emit()
		await get_tree().create_timer(HIT_PAUSE).timeout

	# 保险丝：无论上面怎么退出的，都不能把阶段留在它的回合 ——
	# 那会让 settle() 报「当前阶段不可结算」，而你已经没有按钮可点了。
	if machine.phase() == BjMachine.PHASE_OPPONENT_TURN:
		push_warning("它未能在限定回合内结束，强制停牌以保证结算")
		var forced := machine.opponent_action("STAND")
		if not forced["ok"]:
			notice.emit("它无法结束行动：%s" % str(forced["error"]))
			return
		action_events.emit(forced["events"])

	# 结算交给 _advance_turn()：它先手的局里，它打完还轮到你，
	# 这里直接摊牌就把你那一手跳过去了。


func _finish_hand() -> void:
	var result := machine.settle()
	if not result["ok"]:
		notice.emit(str(result["error"]))
		return
	action_events.emit(result["events"])

	var outcome := machine.outcome()
	last_result = outcome
	_set_cue(BjEmotes.cue_for_hand(outcome, picker))

	persona = BjPersona.absorb(persona, outcome)
	brain_local.persona = persona
	_repay_debt(outcome)

	# 你付不起底注了 —— 不再偷偷给你补钱，改成让**它**来决定你的下场
	if machine.player_chips < machine.min_stake():
		_clamp_pending_bet()
		persist()
		settled.emit(outcome)
		state_changed.emit()
		bankrupt.emit()
		return

	# 它自己也输光了 —— **不要在这里偷偷补钱**：
	# 那样玩家刚把它打光，顶栏立刻又显示 1 亿，赢了跟没赢一样（用户报的问题）。
	# 现在只发信号，让视图先播庆祝 CG，**玩家点掉 CG 之后**才由 opponent_buy_in() 补钱，
	# 因果就看得见了。
	if machine.opponent_chips < machine.min_stake():
		opponent_bankrupt.emit()

	# totals 在原版里建了却从不更新（死字段），这里真的记上
	var totals: Dictionary = profile.get("totals", {})
	totals["hands"] = int(totals.get("hands", 0)) + 1
	if int(outcome["player_delta"]) > 0:
		totals["player_wins"] = int(totals.get("player_wins", 0)) + 1
	elif int(outcome["player_delta"]) < 0:
		totals["opponent_wins"] = int(totals.get("opponent_wins", 0)) + 1
	else:
		totals["pushes"] = int(totals.get("pushes", 0)) + 1
	totals["player_net"] = int(totals.get("player_net", 0)) + int(outcome["player_delta"])
	profile["totals"] = totals

	_update_best_chips()
	_clamp_pending_bet()
	persist()
	settled.emit(outcome)
	state_changed.emit()


## 它输光了之后"回去搬钱"。**由视图在庆祝 CG 播完之后调用** ——
## 这样玩家先看到它归零、看到 CG，再看到它搬钱回来，因果清楚。
func opponent_buy_in() -> void:
	if machine.opponent_chips >= machine.min_stake():
		return
	machine.opponent_chips = BjMachine.STARTING_CHIPS
	notice.emit("它回去搬了 %s token 来，接着打" % BjTokens.format(BjMachine.STARTING_CHIPS))
	persist()
	state_changed.emit()


## 摊牌后回到下注阶段。
##
## **顺手把桌子清空**（`machine.state = {}`）—— 否则"再来一局"点了之后
## 牌和点数还原样摆着，玩家会以为按钮没反应（用户报的"按钮没有用"）。
func next_hand() -> void:
	last_result = {}
	# 兜底：万一庆祝 CG 被跳过 / 玩家用快捷键翻了页，也不能让桌子卡在"它没钱"的状态
	if machine.opponent_chips < machine.min_stake():
		opponent_buy_in()
	machine.state = {}
	_clamp_pending_bet()
	_set_cue(BjEmotes.cue_for_idle(picker))
	state_changed.emit()


# ---------------------------------------------------------------- 输光之后：求情借钱 / 重新开始

## 赢的钱一半先还债，还完为止。保持零和：还出去的钱直接进它口袋。
func _repay_debt(outcome: Dictionary) -> void:
	if debt <= 0:
		return
	var terms := BjPlea.repayment(int(outcome.get("player_delta", 0)), debt)
	var repay := int(terms["repay"])
	if repay <= 0:
		return
	machine.player_chips -= repay
	machine.opponent_chips += repay
	debt = int(terms["left"])
	profile["debt"] = debt
	if debt > 0:
		notice.emit("赢的钱一半先还债：%s（还欠 %s）" % [
			BjTokens.format(repay), BjTokens.format(debt),
		])
	else:
		notice.emit("债还清了（还了 %s token）" % BjTokens.format(repay))


## 它有没有钱借你（要从它自己筹码里出，并且得给它留够底注）。
func can_borrow() -> bool:
	return BjPlea.can_lend(machine.opponent_chips)


func borrowable() -> int:
	return BjPlea.loan_amount(machine.opponent_chips)


## 开始求情。
func start_plea() -> void:
	if not can_borrow():
		notice.emit("它自己也没钱了，借不出来 —— 只能重新开始")
		return
	plea_state = BjPlea.start(persona, machine.opponent_chips, loans_taken())
	plea_changed.emit(plea_state)


## 你已经跟它借过几次钱（越借越难借，也写进存档）。
func loans_taken() -> int:
	return maxi(0, int(profile.get("loans_taken", 0)))


## 跟它说一句话求情（三轮限制）。带 API Key 时**由模型生成它的回应**，
## 但心情值与金额仍然在本地算 —— 模型只负责"说得像不像它"。
func say_plea(text: String) -> void:
	if plea_state.is_empty() or bool(plea_state.get("finished", false)):
		return
	if text.strip_edges() == "":
		return
	var reply := ""
	if using_llm() and brain_llm.is_ready():
		thinking = true
		thinking_changed.emit(true)
		var result: Dictionary = await brain_llm.plea_reply(
			text, plea_state.get("lines", []), BjPersona.describe(persona),
			int(plea_state.get("softness", 0)))
		thinking = false
		thinking_changed.emit(false)
		reply = str(result.get("say", ""))
	plea_state = BjPlea.say(plea_state, text, persona, _rng, reply)
	plea_changed.emit(plea_state)
	if bool(plea_state.get("finished", false)) and bool(plea_state.get("agreed", false)):
		_grant_loan(BjPlea.deal_terms(plea_state))


## 放款：钱从它筹码里出（零和），欠条记进档案。
func _grant_loan(terms: Dictionary) -> void:
	var amount := int(terms.get("amount", 0))
	if amount <= 0:
		return
	machine.opponent_chips -= amount
	machine.player_chips += amount
	debt += int(terms.get("debt", 0))
	profile["debt"] = debt
	# 借过一次就记一次：下次求情的起点会被压低（越借越难借）
	profile["loans_taken"] = loans_taken() + 1
	_clamp_pending_bet()
	persist()
	loan_granted.emit(terms)
	state_changed.emit()


## 关掉求情面板（她拒绝了、或者你放弃了）。
func close_plea() -> void:
	plea_state = {}
	plea_changed.emit(plea_state)
	state_changed.emit()


## 重新开始：**代价是它把你忘干净**（人格与战绩归零，债也一笔勾销）。
func restart_game() -> void:
	plea_state = {}
	reset_progress()
	plea_changed.emit(plea_state)
	notice.emit("重新开始 —— 它已经不认识你了")


## 清空战绩与人格（筹码也重置）。
## **历史最高筹码保留** —— 那是跨局的长期目标，清掉就等于把玩家的追求一起删了。
func reset_progress() -> void:
	var best := best_chips()
	persona = BjPersona.empty()
	brain_local.persona = persona
	profile = BjProfile.default_profile()
	profile["persona"] = persona
	profile["best_chips"] = best
	machine.player_chips = BjMachine.STARTING_CHIPS
	machine.opponent_chips = BjMachine.STARTING_CHIPS
	machine.hand_no = 0
	machine.state = {}
	last_result = {}
	debt = 0
	plea_state = {}
	pending_bet = machine.min_stake() * 2
	_clamp_pending_bet()
	_set_cue(BjEmotes.cue_for_idle(picker))
	persist()
	state_changed.emit()


func apply_settings(new_settings: Dictionary) -> void:
	settings = new_settings
	# 存档里**只写玩家自己填的那份**：宿主注入的 key 绝不落盘
	BjProfile.save_settings(settings)
	_apply_llm_settings()
	state_changed.emit()


func stats() -> Dictionary:
	return BjPersona.stats(persona)
