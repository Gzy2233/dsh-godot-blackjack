class_name BjTableView
extends Control

## 摊牌要**先演完**（翻暗牌 → 出点数 → 结果条）CG 才允许盖上来。
## 不然一把梭输光，玩家连自己几张牌都没看见就进 CG 了（用户报的时序 bug）。
const SHOWDOWN_HOLD := 1.9

## 翻暗牌之后隔多久才报它的点数（翻牌动画 0.42s + 一点点余量）
const TOTAL_REVEAL_DELAY := BjCardView.FLIP_TIME + 0.10

var _opp_hole_hidden := true
var _opp_total_seq := 0
var _player_total_seq := 0
## 摊牌演出还没结束吗（时间戳判断，不会卡死）。
var _showdown_until_msec := 0

## 战败 CG 素材目录（`<kind>.png`）。放进去就生效，没有就跳过。
const CG_DIR := "res://assets/cg/"

## 三张 CG：什么时候播、她说哪句。
## 台词是用户定的（标点按它其他台词的风格规范过：`，，`→`，`、`。。。`→`……`）。
const CG_TABLE := {
	# 你输光（筹码低于底注）—— 她一边踩着你一边"好心"提借钱，接着就弹求情/重开
	"lose_all": {
		"title": "你输光了",
		"line": "杂鱼，要不我借你点，代价吗……",
	},
	# 你认输（在输光面板上选了重新开始，或者求情求到一半放弃）
	"give_up": {
		"title": "你认输了",
		"line": "杂鱼就是杂鱼，赢不过我",
	},
	# 你把它打光（它付不起底注）
	"you_win": {
		"title": "你赢了",
		"line": "我的token……哭",
	},
	# 彩蛋：戳它三次
	"poked": {
		"title": "你被干掉了",
		"line": "你因为手贱，被鲸鱼娘干掉了",
		"voice": "叫你手贱",     # 字幕是旁白，念出来的这句是它说的
	},
}

## 彩蛋：戳鲸鱼娘。**三次机会，一次比一次凶**，第三次直接被干掉。
const POKE_LINES: Array[String] = [
	"别点我。",
	"我说了，别点我。",
	"……你手是不是不想要了。",
]
const POKE_MAX := 3

var _poke_count := 0
var _poking := false

## 牌桌视图。**只做渲染与转发点击，不做任何规则判断。**
##
## 布局（逻辑分辨率 1280×760，可按窗口拉伸）：
##   顶栏（局号 / 双方 token / 战绩）
##   ├ 绿呢毯：底池 → 它对家区（鲸鱼娘 + 气泡 + 它的牌）
##   ├ 你的区域（你的牌 + 下注）
##   └ 动作栏（下注 / 要牌停牌加注 / 摊牌）
##
## 原版 client 的节奏常量（DEAL_STEP 320ms 等）在这里原样保留。

const DEAL_STEP := 0.32
const HIT_PAUSE := 0.55  # 与 BjGame 的节奏保持一致

var game: BjGame
var sfx: BjSfx
var voice: BjVoice
var bgm: BjBgm

var stage: Control
var pot_label: Label
var opponent_row: Control
var player_row: Control

var hand_label: Label
## 当前下注区间（局号下面一行，常驻）
var stake_label: Label
var player_pill: Label
var opp_pill: Label
## 历史最高筹码（右上角常驻）
var best_label: Label
## 中央横幅：黑杰克 / 新纪录
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var _banner_tween: Tween
var stats_box: Panel
var stats_title: Label
var brain_label: Label
var win_label: Label
var loss_label: Label
var push_label: Label
var net_label: Label
var debt_label: Label
var settings_button: Button
var menu_button: Button
var rules_button: Button
var rules_panel: Control
var rules_scroll: ScrollContainer
var settings_scroll: ScrollContainer
var settings_footer: HBoxContainer
var settings_help: Label

# ---- 输光之后：求情借钱 / 重新开始 ----
var bankrupt_panel: Control
var bankrupt_page: Panel
var plea_page: Panel
var win_page: Panel
var dead_page: Panel
var plea_whale: BjWhaleView
var plea_bubble: BjBubble
var plea_softness_label: Label
var plea_softness_bar: ProgressBar
var plea_info_label: Label
var plea_input: LineEdit
var plea_send_button: Button
var plea_log: Label
var plea_verdict_label: Label
var plea_debt_label: Label
var plea_buttons: Array[Button] = []
var plea_continue_button: Button
var plea_restart_button: Button
var _plea_busy := false

var whale: BjWhaleView
var bubble: BjBubble
var opp_hand: BjHandView
var opp_total: Label
var opp_bet_label: Label

var player_tag: Label
var player_hand: BjHandView
var player_total: Label
var player_bet_label: Label
var player_chip_stack: BjChipStack
var opp_chip_stack: BjChipStack

var action_bar: HBoxContainer
var bet_label: Label
var chip_buttons: HBoxContainer
var all_in_button: Button

# ---- 战败 CG（图放在 assets/cg/ 里，没有就跳过不挡流程）----
var cg_layer: Control
var cg_backdrop: ColorRect
var cg_image: TextureRect
var cg_caption: Label
var cg_title: Label
var cg_hint: Label
var cg_button: Button
var _cg_after := Callable()
var _cg_kind := ""
var _cg_tween: Tween
var _cg_revealing := false

## CG 浮现节奏（秒）。整体 ~2 秒，够慢够有仪式感，但不至于让人等得烦。
const CG_FADE_BACKDROP := 0.30
const CG_FADE_IMAGE := 1.10
const CG_PUSH_SCALE := 1.06      ## 从 1.06 缓慢推到 1.0，画面像"压过来"
const CG_FADE_TITLE := 0.45
const CG_FADE_LINE := 0.55
const CG_FADE_HINT := 0.35
var current_bet_label: Label
var deal_button: Button
var hit_button: Button
var stand_button: Button
var double_button: Button
var result_label: Label
var waiting_label: Label

var toast: Label
var settings_panel: Control
var stats_panel: Control

var felt_rect := Rect2()
var player_rect := Rect2()
var action_rect := Rect2()
var _stage_home := Vector2.ZERO
var _hand_shown := -1

# 特效状态（原版算出来却没人执行的那几个 fx，这里真的画出来）
var _flash := 0.0
var _burst := 0.0
var _glow := 0.0
## 彩蛋用：整屏压暗 / 整屏白闪
var _dark := 0.0
var _white := 0.0
var _talk_blip := 0


## 统一的"换页"入口：先把四页全藏起来，再显示要的那页。
## 这样永远不会出现"遮罩亮着、却一页都没有"的死状态 ——
## 那会让整张桌子被一层点不到任何东西的遮罩锁死（用户报的"卡死"）。
func _switch_bankrupt_page(page: Panel) -> void:
	for item in [bankrupt_page, plea_page, win_page, dead_page]:
		if item != null:
			item.visible = item == page
	bankrupt_panel.visible = page != null
	if page != null:
		_refresh_action_bar(game.machine.phase())


## 自愈：每帧检查有没有"死状态"，有就直接解开。
## 宁可少弹一个面板，也不能让玩家卡在一层点不到东西的遮罩后面。
func _process(_delta: float) -> void:
	if bankrupt_panel.visible and bankrupt_page != null \
			and not (bankrupt_page.visible or plea_page.visible
				or win_page.visible or dead_page.visible):
		bankrupt_panel.visible = false
		_refresh_action_bar(game.machine.phase())
	if cg_layer != null and cg_layer.visible and _cg_revealing \
			and (_cg_tween == null or not _cg_tween.is_valid()):
		# 浮现动画没了但标志还留着 → 点击会被当成"跳过动画"，于是永远翻不了页
		_cg_revealing = false


func _ready() -> void:
	# 必须用 set_anchors_and_offsets_preset：只设 anchors 的话根节点会停在 0×0，
	# 整个布局会按 (0,0) 算出来挤成一团。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	sfx = BjSfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

	voice = BjVoice.new()
	voice.name = "Voice"
	add_child(voice)

	bgm = BjBgm.new()
	bgm.name = "Bgm"
	add_child(bgm)

	game = BjGame.new()
	game.name = "Game"
	add_child(game)

	# 窗口标题：`project.godot` 里的 config/name 保持 "21"（它是存档目录名，
	# 改了会让老玩家的进度"消失"），标题单独在这里设成好看的那个。
	get_window().title = "鲸鱼娘 21 点"

	_build()
	game.state_changed.connect(_refresh)
	game.hand_dealt.connect(_on_hand_dealt)
	game.action_events.connect(_on_action_events)
	game.cues_changed.connect(_on_cue)
	game.thinking_changed.connect(_on_thinking)
	game.settled.connect(_on_settled)
	game.notice.connect(_on_notice)
	# ⚠️ 这一行曾经在改动中被误删 → 玩家输光后既不出 CG 也不弹选择页（用户报的"什么都不触发"）。
	# tests/test_ui.gd 里有一条"所有信号都接到视图上"的断言专门盯住它。
	game.bankrupt.connect(_on_bankrupt)
	game.opponent_bankrupt.connect(_on_opponent_bankrupt)
	game.plea_changed.connect(_on_plea_changed)
	game.loan_granted.connect(_on_loan_granted)
	game.new_record.connect(_on_new_record)
	# 任何弹窗一显一隐，都重算牌桌按钮的可用状态（不用在每个显隐分支里手动调用）
	for overlay in [settings_panel, stats_panel, bankrupt_panel, rules_panel, cg_layer]:
		if overlay is CanvasItem:
			(overlay as CanvasItem).visibility_changed.connect(_sync_modal_buttons)
	sfx.enabled = bool(game.settings.get("sound", true))
	voice.set_voice(str(game.settings.get("voice_id", "xiaoyi")))
	voice.runtime_synth = bool(game.settings.get("voice_online", true))
	voice.system_fallback = bool(game.settings.get("voice_fallback", false))
	voice.python_path = str(game.settings.get("python_path", ""))
	bgm.apply(game.settings)
	whale.scale_factor = int(game.settings.get("whale_scale", 3))
	whale.poked.connect(_on_whale_poked)
	whale.update_size()
	_layout()
	_load_background()
	# 开局先把已有的那句空闲台词喂给视图（game 在视图连信号之前就已经有 cue 了）
	_on_cue(game.cue)
	_refresh()
	# 第一次玩：自动把规则摊开（之后从顶栏「规则」随时看）
	if not bool(game.settings.get("seen_rules", false)):
		_open_rules.call_deferred()


# ---------------------------------------------------------------- 构建

## 战绩面板里的一个数字 + 单位（胜/负/平用同一个排版）。
func _stat_number(row: HBoxContainer, color: Color, suffix: String) -> Label:
	var value := BjTheme.label("0", 15, color)
	row.add_child(value)
	row.add_child(BjTheme.label(suffix, 10, BjTheme.TEXT_DIM))
	return value


func _build() -> void:
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	# ---- 顶栏 ----
	hand_label = BjTheme.label("第 1 局", 19, BjTheme.ACCENT)
	hand_label.name = "HandLabel"
	add_child(hand_label)
	# 下注单独一行放在局号下面：挤成一行会压到「你 X token」上（用户报的遮挡）
	stake_label = BjTheme.label("", 13, BjTheme.TEXT_DIM)
	stake_label.name = "StakeLabel"
	add_child(stake_label)
	player_pill = BjTheme.label("", 18)
	add_child(player_pill)
	opp_pill = BjTheme.label("", 18)
	add_child(opp_pill)
	# ---- 右上角战绩面板 ----
	stats_box = Panel.new()
	stats_box.add_theme_stylebox_override("panel",
		BjTheme.panel_style(BjTheme.PANEL, BjTheme.PANEL_LINE, 2))
	# **裁剪**：Godot 不允许 Control 的 size 小于内容最小尺寸，
	# 内容一旦比框宽，框不裁剪、而是整个撑到框外（"DeepSeek 在线"就是这么跑出去的）。
	# 打开 clip_contents，最坏情况也只是内容被框裁掉，绝不会画到框外面。
	stats_box.clip_contents = true
	add_child(stats_box)
	var stats_rows := VBoxContainer.new()
	stats_rows.name = "Rows"
	stats_rows.add_theme_constant_override("separation", 0)
	stats_box.add_child(stats_rows)

	# 第 1 行：标题 + 对手大脑标识
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	stats_rows.add_child(title_row)
	stats_title = BjTheme.label("它的战绩", 11, BjTheme.TEXT_DIM)
	title_row.add_child(stats_title)
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_spacer)
	brain_label = BjTheme.label("本地 AI", 11, BjTheme.TEXT_DIM)
	title_row.add_child(brain_label)

	# 第 2 行：胜 / 负 / 平（数字各自着色）+ 净收益 + 欠款
	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 4)
	stats_rows.add_child(record_row)
	win_label = _stat_number(record_row, BjTheme.WIN, "胜")
	record_row.add_child(BjTheme.label("·", 12, BjTheme.TEXT_DIM))
	loss_label = _stat_number(record_row, BjTheme.DANGER, "负")
	record_row.add_child(BjTheme.label("·", 12, BjTheme.TEXT_DIM))
	push_label = _stat_number(record_row, BjTheme.TEXT_DIM, "平")
	var money_spacer := Control.new()
	money_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_row.add_child(money_spacer)
	net_label = BjTheme.label("净 ±0", 13, BjTheme.TEXT_DIM)
	record_row.add_child(net_label)
	var debt_gap := Control.new()
	debt_gap.custom_minimum_size = Vector2(12, 0)
	record_row.add_child(debt_gap)
	debt_label = BjTheme.label("", 12, BjTheme.ACCENT)
	record_row.add_child(debt_label)
	debt_label.visible = false
	var best_gap := Control.new()
	best_gap.custom_minimum_size = Vector2(12, 0)
	record_row.add_child(best_gap)
	# 历史最高筹码：长期目标，一直在右上角盯着你
	best_label = BjTheme.label("", 12, BjTheme.TEXT_DIM)
	record_row.add_child(best_label)

	settings_button = BjTheme.make_button("设置", "toggle")
	settings_button.pressed.connect(_toggle_settings)
	add_child(settings_button)
	menu_button = BjTheme.make_button("战绩", "toggle")
	menu_button.pressed.connect(_toggle_stats)
	add_child(menu_button)
	rules_button = BjTheme.make_button("规则", "toggle")
	rules_button.pressed.connect(_toggle_rules)
	add_child(rules_button)

	# ---- 中央横幅（黑杰克 / 新纪录）----
	# 不放进 stage：那是会被震屏的容器，横幅跟着抖就糊了。
	banner_box = VBoxContainer.new()
	banner_box.name = "Banner"
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.add_theme_constant_override("separation", 2)
	banner_box.visible = false
	add_child(banner_box)
	banner_title = BjTheme.label("", 54, BjTheme.ACCENT)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_title)
	banner_sub = BjTheme.label("", 20, BjTheme.TEXT)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_sub)

	# ---- 底池（单挑：双方各押同额，赢家拿走对方那份）----
	pot_label = BjTheme.label("", 17, BjTheme.ACCENT)
	pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(pot_label)

	# ---- 对手 ----
	opponent_row = Control.new()
	opponent_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(opponent_row)
	whale = BjWhaleView.new()
	opponent_row.add_child(whale)
	bubble = BjBubble.new()
	bubble.blipped.connect(_on_bubble_blip)
	opponent_row.add_child(bubble)
	opp_hand = BjHandView.new()
	opponent_row.add_child(opp_hand)
	opp_total = BjTheme.label("—", 17, BjTheme.TEXT_DIM)
	opponent_row.add_child(opp_total)
	opp_bet_label = BjTheme.label("", 15, BjTheme.TEXT_DIM)
	opponent_row.add_child(opp_bet_label)
	opp_chip_stack = BjChipStack.new()
	opponent_row.add_child(opp_chip_stack)

	# ---- 玩家 ----
	# 玩家行在绿呢毯**外面**（深色条），所以挂在根节点上、按 player_rect 定位，
	# 不能放进 stage（stage 会被震屏偏移）。
	player_row = Control.new()
	player_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(player_row)
	player_tag = BjTheme.label("你", 14, BjTheme.ACCENT)
	player_row.add_child(player_tag)
	player_hand = BjHandView.new()
	player_row.add_child(player_hand)
	player_total = BjTheme.label("—", 18, BjTheme.TEXT_DIM)
	player_row.add_child(player_total)
	player_bet_label = BjTheme.label("", 15, BjTheme.TEXT_DIM)
	player_row.add_child(player_bet_label)
	player_chip_stack = BjChipStack.new()
	player_row.add_child(player_chip_stack)

	# ---- 动作栏 ----
	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 10)
	action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(action_bar)

	bet_label = BjTheme.label("下注", 16, BjTheme.TEXT_DIM)
	action_bar.add_child(bet_label)
	chip_buttons = HBoxContainer.new()
	chip_buttons.add_theme_constant_override("separation", 6)
	action_bar.add_child(chip_buttons)
	all_in_button = BjTheme.make_button("ALL IN", "accent")
	all_in_button.pressed.connect(_on_all_in)
	action_bar.add_child(all_in_button)
	current_bet_label = BjTheme.label("", 17, BjTheme.ACCENT)
	action_bar.add_child(current_bet_label)
	deal_button = BjTheme.make_button("发牌", "primary")
	deal_button.pressed.connect(_on_deal)
	action_bar.add_child(deal_button)
	hit_button = BjTheme.make_button("要牌", "primary")
	hit_button.pressed.connect(func() -> void: _send_action("HIT"))
	action_bar.add_child(hit_button)
	stand_button = BjTheme.make_button("停牌")
	stand_button.pressed.connect(func() -> void: _send_action("STAND"))
	action_bar.add_child(stand_button)
	double_button = BjTheme.make_button("加注 ×2（它跟）", "accent")
	double_button.pressed.connect(func() -> void: _send_action("DOUBLE"))
	action_bar.add_child(double_button)
	result_label = BjTheme.label("", 20)
	action_bar.add_child(result_label)
	# 「再来一局」按钮已删除：结算之后下注栏本来就回来了，直接按"发牌"就是下一局。
	# 它既没用（点了看不出变化），又是卡死的疑点 —— 用户让删就删干净。
	waiting_label = BjTheme.label("", 16, BjTheme.TEXT_DIM)
	action_bar.add_child(waiting_label)

	# ---- 提示条 ----
	toast = BjTheme.label("", 16, BjTheme.ACCENT)
	toast.modulate.a = 0.0
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast)

	_build_settings()
	_build_rules()
	_build_stats_panel()
	_build_bankrupt()
	_build_dead_page()   # 彩蛋被干掉那页（挂在同一个遮罩面板上）
	_build_cg()          # 最后加 → 盖在所有面板之上


	# ---- 第三页：你把它打光了（它输光时的选择页）----
	win_page = Panel.new()
	win_page.add_theme_stylebox_override("panel",
		BjTheme.panel_style(BjTheme.PANEL, BjTheme.WIN, 3))
	win_page.visible = false
	bankrupt_panel.add_child(win_page)
	var win_box := VBoxContainer.new()
	win_box.name = "Box"
	win_box.add_theme_constant_override("separation", 12)
	win_page.add_child(win_box)
	win_box.add_child(BjTheme.label("你把它打光了！", 28, BjTheme.WIN))
	var win_body := BjTheme.label("", 16, BjTheme.TEXT)
	win_body.name = "Body"
	win_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	win_body.custom_minimum_size = Vector2(520, 104)
	win_box.add_child(win_body)
	var win_row := HBoxContainer.new()
	win_row.name = "Choices"
	win_row.add_theme_constant_override("separation", 12)
	win_box.add_child(win_row)
	var again := BjTheme.make_button("再来一局（它再掏 1 亿）", "primary")
	again.name = "AgainButton"
	again.pressed.connect(_on_win_continue)
	win_row.add_child(again)
	var win_stats := BjTheme.make_button("先看看战绩", "accent")
	win_stats.name = "StatsButton"
	win_stats.pressed.connect(_on_win_stats)
	win_row.add_child(win_stats)
	var win_hint := BjTheme.label(
		"它的筹码就停在 0 —— 要不要让它再掏一笔出来接着打，由你决定。",
		13, BjTheme.TEXT_DIM)
	win_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	win_hint.custom_minimum_size = Vector2(520, 52)
	win_box.add_child(win_hint)


## 它输光了：**把"它又要变回 1 亿"变成玩家的选择**，而不是 CG 之后自动到账 ——
## 自动到账会让玩家觉得"我刚赢的又被抹了"（用户报的问题）。
func _show_win_page() -> void:
	_switch_bankrupt_page(win_page)
	var body := win_page.get_node_or_null("Box/Body") as Label
	if body != null:
		body.text = "它手上只剩 %s token，连 %s 的最小注都付不起了。\n这一场你赢了 —— 它的筹码归零，就摆在那儿。" % [
			BjTokens.format(game.machine.opponent_chips),
			BjTokens.format(game.machine.min_stake()),
		]
	var again := win_page.get_node_or_null("Box/Choices/AgainButton") as Button
	if again != null:
		again.focus_mode = Control.FOCUS_ALL
		again.call_deferred("grab_focus")


func _on_win_continue() -> void:
	_switch_bankrupt_page(null)
	sfx.play("coins")          # 她回去搬钱的声音
	game.opponent_buy_in()
	game.next_hand()


func _on_win_stats() -> void:
	_switch_bankrupt_page(null)
	_toggle_stats()


## 彩蛋被干掉之后：**只能完全重开一把** —— 玩家已经"死"了，
## 所以没有"继续"这个选项，牌桌也不接受任何操作。
## 规则说明页。
##
## 为什么要有：这套规则**不是普通 21 点** —— 没有庄家、对注制、每 10 局涨注、
## 输光可以靠嘴借钱、戳它三次会被干掉。不写清楚，玩家只会觉得"这游戏在坑我"。
## 首次进游戏自动弹一次（存档里记 `seen_rules`），之后从顶栏「规则」随时看。
func _build_rules() -> void:
	rules_panel = Control.new()
	rules_panel.name = "RulesPanel"
	rules_panel.visible = false
	rules_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rules_panel)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	rules_panel.add_child(backdrop)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel",
		BjTheme.panel_style(BjTheme.PANEL, BjTheme.ACCENT, 3))
	rules_panel.add_child(panel)

	var title := BjTheme.label("怎么玩", 24, BjTheme.ACCENT)
	title.name = "Title"
	panel.add_child(title)

	rules_scroll = ScrollContainer.new()
	rules_scroll.name = "Scroll"
	rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(rules_scroll)

	var body := RichTextLabel.new()
	body.name = "Body"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	# ⚠️ 必须给死宽度：`fit_content` 会让它按"当前宽度"算最小高度，
	# 而 ScrollContainer 又按最小尺寸摆它 —— 两者互相等，宽度会塌成 1px，
	# 于是每个字一行、高度变成一万七千多（正文整页空白）。
	body.custom_minimum_size = Vector2(RULES_BODY_WIDTH, 0)
	body.size_flags_horizontal = Control.SIZE_FILL
	body.add_theme_font_override("normal_font", BjTheme.font())
	body.add_theme_font_override("bold_font", BjTheme.font())
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_font_size_override("bold_font_size", 15)
	body.add_theme_constant_override("line_separation", 5)
	body.text = rules_text()
	rules_scroll.add_child(body)

	var close := BjTheme.make_button("知道了，开打", "primary")
	close.name = "CloseButton"
	close.pressed.connect(_close_rules)
	panel.add_child(close)


## 规则正文的排版宽度（比滚动区窄一点，给滚动条留位置）
const RULES_BODY_WIDTH := 686.0

## 规则正文（BBcode）。改规则时**顺手改这里** —— 它是玩家唯一能读到的说明书。
const RULES_TEXT := """[b][color=#e8b84b]这不是普通 21 点：没有庄家，你和她对赌。[/color][/b]

[color=#8fa3c8]① 对注制[/color]
每一局你和她押[b]完全相同[/b]的注额（你定注，她必跟）。赢家拿走对方押的那一份，
所以[b]你赢的每一分都是她输的[/b]，反过来也一样。

[color=#8fa3c8]② 比点数[/color]
牌面凑到 21 点最理想，[b]超过 21 直接爆[/b]（爆了必输，不管她多少点）。
开局两张就是 21 点 = [b]黑杰克，赔 1.5 倍[/b] —— 屏幕中央会有专属播报。
同点算平局，谁都不拿。

[color=#8fa3c8]③ 你能做的事[/color]
[b]要牌[/b] 再来一张 · [b]停牌[/b] 就这样比 · [b]加注[/b] 只在前两张，
注额翻倍（双方都得跟得起） · [b]全押[/b] 把能押的全押上。

[color=#e8b84b]③'' 额外倍率（魔改，只加给你）[/color]
这三条是**只给玩家**的加成，专门为了爽：
[color=#7ee081]· 抓它爆牌[/color] —— 它爆了、你没爆 → [b]×%s[/b]（下注 100 拿 220）
[color=#7ee081]· 五小龙[/color] —— 手里 %d 张牌还没爆（≤21）→ [b]×%s[/b]
[color=#7ee081]· 六小龙[/color] —— %d 张还没爆 → [b]×%s[/b]（第 5 张时你还能继续要，搏一把）
[b]取最大值，不叠乘[/b]：六小龙 &gt; 五小龙 &gt; 抓爆 &gt; 普通赢。
龙到手时屏幕中央会当场报喜，摊牌后的结果条会写明这把吃的是哪条倍率。
它（对方）不享受这三条 —— 所以这套规则整体是偏你的。

[color=#8fa3c8]③' 先手是轮流的[/color]
[b]第 1 局你先做决定，第 2 局它先，交替下去。[/b]
它先手的那些局，它的暗牌**开局就是明的** —— 它得先做决定，不能拿暗牌算；
反过来你因此能看清它的全部牌，这是那一局你的信息红利。

[color=#8fa3c8]④ 下注会涨（重点）[/color]
[b]每 %d 局升一档[/b]，最小注 %s 起，第 %d 局涨到 %s 封顶（顶档），
最大注 = 最小注 × %d。当前区间和"还有几局升档"一直显示在左上角那一行，
升级时会弹横幅提醒。
顶档的 %s 是半副身家 —— 撑不住就会输光，所以[b]见好就收也是一种打法[/b]。

[color=#8fa3c8]⑤ 全押按钮什么时候出现[/color]
只有[b]「最大注超过你手上的钱」[/b]时才出现（最大注 = 最小注 × 5）。
够钱的时候不给你全押，免得一把梭把自己送走。

[color=#8fa3c8]⑥ 输光了怎么办[/color]
她会问你：[b]求情借钱[/b] 还是 [b]重新开始[/b]。
求情是[b]自由对话，三次机会[/b]，借多少看她当时的心情 —— 装可怜 / 吹捧 / 激将 /
谈条件，各吃哪一套看她是什么脾气。
[b]说错话会掉好感[/b]，好感掉光她就彻底不想听了，这一局只能重开。
而且[b]借过一次，下次就更难借[/b]。

[color=#8fa3c8]⑦ 她输光了呢[/color]
你赢下这一场，她的筹码清零。她会回去搬钱，接着陪你打。

[color=#8fa3c8]⑧ 右上角那串数字[/color]
[color=#e8b84b]最高 X[/color] 是你[b]历史最高的筹码纪录[/b]，跨重开都保留 ——
破了会弹「新纪录！」。这是长期目标：涨注迟早把你赶下桌，纪录才值得冲。

[color=#8fa3c8]⑨ 快捷键[/color]
空格 发牌 · H 要牌 · S 停牌 · D 加注 · A 全押 · 1/2/3 选注额 · Esc 关闭面板

[color=#6b7a99]最后：她不喜欢被戳。连着点她三次试试 —— 后果自负。[/color]"""


## 规则正文的数字**全部从常量现算**，不在文案里写死 ——
## 否则调一次经济，说明书就变成骗人的（我就干过：改成每 2 局升档，
## 规则页还写着"每 10 局"，玩家照着说明书算就全错了）。
func rules_text() -> String:
	var steps := BjMachine.STAKE_MIN_STEPS
	var cap_hand := (steps.size() - 1) * BjMachine.STAKE_HANDS_PER_LEVEL
	# ⚠️ 参数顺序必须与正文里 % 占位符出现的顺序**完全一致**
	# （③'' 段在 ④ 段之前，所以倍率的 5 个参数要排在前面）。
	# 顺序错了不会报解析错误，而是运行时 "String formatting error: a number is required"
	# 然后整段规则页变成空字符串 —— 编辑器日志里才有。
	return RULES_TEXT % [
		# ③'' 魔改倍率
		_trim_mult(BjMachine.BUST_BONUS),
		BjMachine.CHARLIE_CARDS_5,
		_trim_mult(BjMachine.CHARLIE_5_MULT),
		BjMachine.CHARLIE_CARDS_6,
		_trim_mult(BjMachine.CHARLIE_6_MULT),
		# ④ 下注阶梯
		BjMachine.STAKE_HANDS_PER_LEVEL,
		BjTokens.format(int(steps[0])),
		cap_hand,
		BjTokens.format(int(steps[-1])),
		BjMachine.MAX_STAKE_MULTIPLIER,
		BjTokens.format(int(steps[-1])),
	]


func _toggle_rules() -> void:
	if rules_panel.visible:
		_close_rules()
		return
	_open_rules()


func _open_rules() -> void:
	rules_panel.visible = true
	# 回到顶部：RichTextLabel 排版完会把滚动位置带偏，不改的话一打开就停在中间
	if rules_scroll != null:
		rules_scroll.scroll_vertical = 0
		rules_scroll.set_deferred("scroll_vertical", 0)
	if not bool(game.settings.get("seen_rules", false)):
		game.settings["seen_rules"] = true
		BjProfile.save_settings(game.settings)
	_refresh_action_bar(game.machine.phase())


func _close_rules() -> void:
	rules_panel.visible = false
	_refresh_action_bar(game.machine.phase())


func _build_dead_page() -> void:
	dead_page = Panel.new()
	dead_page.add_theme_stylebox_override("panel",
		BjTheme.panel_style(BjTheme.PANEL, BjTheme.DANGER, 3))
	dead_page.visible = false
	bankrupt_panel.add_child(dead_page)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	dead_page.add_child(box)
	box.add_child(BjTheme.label("你被干掉了", 30, BjTheme.DANGER))
	var body := BjTheme.label(
		"手贱是要付出代价的。\n它把你从这张牌桌上抹掉了 —— 筹码、战绩、它对你的记忆，一起归零。",
		16, BjTheme.TEXT)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 96)
	box.add_child(body)
	var again := BjTheme.make_button("完全重开一把", "primary")
	again.name = "DeadRestartButton"
	again.pressed.connect(_on_dead_restart)
	box.add_child(again)
	var hint := BjTheme.label("（没有别的选项 —— 你已经死了）", 13, BjTheme.TEXT_DIM)
	hint.name = "Hint"
	box.add_child(hint)


func _show_dead_page() -> void:
	_switch_bankrupt_page(dead_page)
	var body := dead_page.get_node_or_null("Box/Body") as Label
	if body != null:
		body.text = "手贱是要付出代价的。\n它把你从这张牌桌上抹掉了 —— 当前这一局作废，完全重开。"
	var again := dead_page.get_node_or_null("Box/DeadRestartButton") as Button
	if again != null:
		again.focus_mode = Control.FOCUS_ALL   # 让键盘/手柄也能确认
		again.call_deferred("grab_focus")


func _on_dead_restart() -> void:
	_switch_bankrupt_page(null)
	game.restart_game()


func _build_settings() -> void:
	settings_panel = Control.new()
	settings_panel.visible = false
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(settings_panel)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.62)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(backdrop)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", BjTheme.panel_style(BjTheme.PANEL, BjTheme.ACCENT, 3))
	settings_panel.add_child(panel)

	# 设置项**会越长越多**，所以放进 ScrollContainer：
	# 之前面板固定 500 高、内容却涨到 664，最后几行（API Key / 模型名 / 按钮）
	# 直接溢出到面板外面（用户报的显示 bug）。现在内容再长也只会滚动，不会破版。
	settings_scroll = ScrollContainer.new()
	settings_scroll.name = "Scroll"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(settings_scroll)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(box)

	var title := BjTheme.label("设置", 22, BjTheme.ACCENT)
	box.add_child(title)

	var sound_button := BjTheme.make_button("", "toggle")
	sound_button.name = "SoundButton"
	sound_button.pressed.connect(_toggle_sound)
	box.add_child(sound_button)

	var voice_button := BjTheme.make_button("", "toggle")
	voice_button.name = "VoiceButton"
	voice_button.pressed.connect(_toggle_voice)
	box.add_child(voice_button)
	var voice_style := BjTheme.make_button("", "toggle")
	voice_style.name = "VoiceStyleButton"
	voice_style.pressed.connect(_cycle_voice_style)
	box.add_child(voice_style)
	var voice_online := BjTheme.make_button("", "toggle")
	voice_online.name = "VoiceOnlineButton"
	voice_online.pressed.connect(_toggle_voice_online)
	box.add_child(voice_online)
	var bgm_button := BjTheme.make_button("", "toggle")
	bgm_button.name = "BgmButton"
	bgm_button.pressed.connect(_toggle_bgm)
	box.add_child(bgm_button)
	var bg_button := BjTheme.make_button("", "toggle")
	bg_button.name = "BackgroundButton"
	bg_button.pressed.connect(_toggle_background)
	box.add_child(bg_button)

	var whale_button := BjTheme.make_button("", "toggle")
	whale_button.name = "WhaleButton"
	whale_button.pressed.connect(_cycle_whale_scale)
	box.add_child(whale_button)

	box.add_child(BjTheme.label("── 对手大脑 ──", 15, BjTheme.TEXT_DIM))
	var llm_button := BjTheme.make_button("", "toggle")
	llm_button.name = "LlmButton"
	llm_button.pressed.connect(_toggle_llm)
	box.add_child(llm_button)

	# 插件启动时的提示：key 由 DSH 宿主注入，这里**不用填**
	var dsh_note := BjTheme.label("", 14, BjTheme.WIN)
	dsh_note.name = "DshNote"
	box.add_child(dsh_note)

	box.add_child(BjTheme.label("DeepSeek API Key（留空则只用本地大脑）", 14, BjTheme.TEXT_DIM))
	var key_edit := LineEdit.new()
	key_edit.name = "KeyEdit"
	key_edit.secret = true
	key_edit.placeholder_text = "sk-..."
	key_edit.add_theme_font_override("font", BjTheme.font())
	key_edit.add_theme_font_size_override("font_size", 15)
	box.add_child(key_edit)

	box.add_child(BjTheme.label("模型名", 14, BjTheme.TEXT_DIM))
	var model_edit := LineEdit.new()
	model_edit.name = "ModelEdit"
	model_edit.add_theme_font_override("font", BjTheme.font())
	model_edit.add_theme_font_size_override("font_size", 15)
	box.add_child(model_edit)

	var row := HBoxContainer.new()
	settings_footer = row
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# 挂在**面板**上而不是全屏遮罩上 —— 否则坐标基准是屏幕，按钮会跑到面板左边去
	panel.add_child(row)
	var save_button := BjTheme.make_button("保存并关闭", "primary")
	save_button.pressed.connect(_save_settings)
	row.add_child(save_button)
	var reset_button := BjTheme.make_button("清空战绩与人格", "accent")
	reset_button.pressed.connect(_reset_progress)
	row.add_child(reset_button)
	var close_button := BjTheme.make_button("取消")
	close_button.pressed.connect(func() -> void: settings_panel.visible = false)
	row.add_child(close_button)

	settings_help = BjTheme.label(
		"快捷键：空格 发牌 / H 要牌 / S 停牌 / D 加注 / A 全押 / 1·2·3 选注额 / Esc 关闭面板", 14, BjTheme.TEXT_DIM)
	panel.add_child(settings_help)


## 输光之后的选择：低头求它借钱（三轮自由对话）或者重新开始。
## 战败 CG：`assets/cg/player_defeat.png`（你输光）/ `assets/cg/whale_defeat.png`（它输光）。
## 素材不存在就直接跳过、不挡流程 —— 你也可以只放一张。
func _build_cg() -> void:
	cg_layer = Control.new()
	cg_layer.visible = false
	cg_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	cg_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 关键：这层是 MOUSE_FILTER_STOP，**鼠标点击会被它吃掉、到不了 _unhandled_input**。
	# 所以"点一下继续"必须挂在这里的 gui_input 上 ——
	# 否则玩家只能精准点中"继续"按钮，其余地方点了没反应（用户报的"按钮按不了"）。
	cg_layer.gui_input.connect(_on_cg_gui_input)
	add_child(cg_layer)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.97)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cg_layer.add_child(backdrop)
	cg_backdrop = backdrop

	cg_image = TextureRect.new()
	cg_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cg_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cg_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cg_layer.add_child(cg_image)

	cg_caption = BjTheme.label("", 26, BjTheme.ACCENT)
	cg_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cg_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cg_layer.add_child(cg_caption)
	cg_title = BjTheme.label("", 17, BjTheme.TEXT_DIM)
	cg_title.name = "Title"
	cg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cg_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cg_layer.add_child(cg_title)
	cg_hint = BjTheme.label("点一下 / 按任意键 继续", 15, BjTheme.TEXT_DIM)
	cg_hint.name = "Hint"
	cg_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cg_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cg_layer.add_child(cg_hint)
	# 字幕是压在 CG 上的 —— 给文字加一圈深色描边，
	# 这样不管底图是亮是暗都读得清，也不用改动画师的图。
	var outline := Color(0.02, 0.03, 0.06, 0.92)
	for pair in [[cg_title, 5], [cg_caption, 7], [cg_hint, 4]]:
		var label: Label = pair[0]
		label.add_theme_constant_override("outline_size", int(pair[1]))
		label.add_theme_color_override("font_outline_color", outline)
	cg_button = BjTheme.make_button("继续", "primary")
	cg_button.name = "ContinueButton"
	cg_button.pressed.connect(_dismiss_cg)
	cg_layer.add_child(cg_button)


## 播一张 CG。素材不存在就直接执行 after（不阻塞流程）。
func _show_cg(kind: String, after: Callable) -> void:
	var entry: Dictionary = CG_TABLE.get(kind, {})
	if entry.is_empty():
		after.call()
		return
	var path := "%s%s.png" % [CG_DIR, kind]
	if not ResourceLoader.exists(path):
		after.call()
		return
	var texture: Texture2D = load(path)
	if texture == null:
		after.call()
		return
	cg_image.texture = texture
	cg_title.text = str(entry["title"])
	cg_caption.text = str(entry["line"])
	_cg_after = after
	_cg_kind = kind
	cg_layer.visible = true
	voice.stop()
	# 浮现本身给一声戏剧性 whoosh，主题音效**错开 0.35 秒**叠上去
	sfx.play("cg_open")
	_schedule_sfx("blackjack" if kind == "you_win" else "bust", 0.35)
	# 字幕用 line；念出来的可以是另一句（voice），为空则完全不说话
	var spoken := str(entry.get("voice", entry["line"]))
	_start_cg_reveal(spoken)


## 让 CG **缓慢浮现**：黑场先盖上来 → 画面淡入并轻微推进 → 标题 → 她的台词 → 提示。
## 台词浮现的那一刻才开口念，声音和字幕是对齐的。
func _start_cg_reveal(line: String) -> void:
	_cg_revealing = true
	cg_backdrop.modulate.a = 0.0
	cg_image.modulate.a = 0.0
	cg_image.scale = Vector2(CG_PUSH_SCALE, CG_PUSH_SCALE)
	cg_title.modulate.a = 0.0
	cg_caption.modulate.a = 0.0
	cg_hint.modulate.a = 0.0
	cg_button.modulate.a = 0.0
	if _cg_tween != null and _cg_tween.is_valid():
		_cg_tween.kill()

	_cg_tween = create_tween()
	# 第一段：黑场 + 画面同时淡入，画面从 1.06 缓慢推回 1.0
	_cg_tween.set_parallel(true)
	_cg_tween.tween_property(cg_backdrop, "modulate:a", 1.0, CG_FADE_BACKDROP)
	_cg_tween.tween_property(cg_image, "modulate:a", 1.0, CG_FADE_IMAGE)
	_cg_tween.tween_property(cg_image, "scale", Vector2.ONE, CG_FADE_IMAGE + 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 之后按顺序：标题 → 台词（开口）→ 提示与按钮
	_cg_tween.set_parallel(false)
	_cg_tween.tween_interval(0.30)
	_cg_tween.tween_property(cg_title, "modulate:a", 1.0, CG_FADE_TITLE)
	_cg_tween.tween_property(cg_caption, "modulate:a", 1.0, CG_FADE_LINE)
	_cg_tween.tween_callback(func() -> void:
		if line != "":
			_speak(line))
	_cg_tween.tween_interval(0.15)
	_cg_tween.tween_property(cg_hint, "modulate:a", 1.0, CG_FADE_HINT)
	_cg_tween.tween_property(cg_button, "modulate:a", 1.0, CG_FADE_HINT)
	_cg_tween.tween_callback(func() -> void: _cg_revealing = false)


## 跳过浮现动画：直接落到终态（点一下先跳过、再点一下才翻页）。
func _finish_cg_reveal(line: String) -> void:
	if _cg_tween != null and _cg_tween.is_valid():
		_cg_tween.kill()
	_cg_revealing = false
	cg_backdrop.modulate.a = 1.0
	cg_image.modulate.a = 1.0
	cg_image.scale = Vector2.ONE
	cg_title.modulate.a = 1.0
	cg_caption.modulate.a = 1.0
	cg_hint.modulate.a = 1.0
	cg_button.modulate.a = 1.0
	if line != "":
		_speak(line)


## CG 层上的任意点击都算"继续"（因为点击到不了 _unhandled_input）。
func _on_cg_gui_input(event: InputEvent) -> void:
	if not cg_layer.visible:
		return
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		cg_layer.accept_event()
		_dismiss_cg()


func _dismiss_cg() -> void:
	if not cg_layer.visible:
		return
	# 还在浮现 → 第一次点只跳过动画
	if _cg_revealing:
		var entry: Dictionary = CG_TABLE.get(_cg_kind, {})
		_finish_cg_reveal(str(entry.get("line", "")))
		return
	cg_layer.visible = false
	var after := _cg_after
	_cg_after = Callable()
	if after.is_valid():
		after.call()


func _build_bankrupt() -> void:
	bankrupt_panel = Control.new()
	bankrupt_panel.visible = false
	bankrupt_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bankrupt_panel)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.68)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	bankrupt_panel.add_child(backdrop)

	# ---- 第一页：你输光了，二选一 ----
	bankrupt_page = Panel.new()
	bankrupt_page.add_theme_stylebox_override("panel",
		BjTheme.panel_style(BjTheme.PANEL, BjTheme.DANGER, 3))
	bankrupt_panel.add_child(bankrupt_page)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	bankrupt_page.add_child(box)
	box.add_child(BjTheme.label("你输光了", 28, BjTheme.DANGER))
	var body := BjTheme.label("", 16, BjTheme.TEXT)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 110)
	box.add_child(body)
	var row := HBoxContainer.new()
	row.name = "Choices"
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var borrow := BjTheme.make_button("向鲸鱼娘求情借钱", "primary")
	borrow.name = "BorrowButton"
	borrow.pressed.connect(_on_start_plea)
	row.add_child(borrow)
	var restart := BjTheme.make_button("重新开始", "accent")
	restart.name = "RestartButton"
	restart.pressed.connect(_on_restart)
	row.add_child(restart)
	var hint := BjTheme.label(
		"借钱要从**它自己的筹码**里出，而且它要利息；重新开始会清空战绩，它会把你忘干净。",
		13, BjTheme.TEXT_DIM)
	hint.name = "Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 60)
	box.add_child(hint)

	# ---- 第二页：求情小游戏 ----
	plea_page = Panel.new()
	plea_page.add_theme_stylebox_override("panel",
		BjTheme.panel_style(BjTheme.PANEL, BjTheme.ACCENT, 3))
	plea_page.visible = false
	bankrupt_panel.add_child(plea_page)

	plea_whale = BjWhaleView.new()
	plea_page.add_child(plea_whale)
	# 缩放必须在 add_child **之后**设：_ready() 会照 manifest 的 scale 覆盖一次
	plea_whale.scale_factor = 2
	plea_whale.update_size()
	plea_bubble = BjBubble.new()
	plea_page.add_child(plea_bubble)

	plea_softness_label = BjTheme.label("心软度", 15, BjTheme.TEXT_DIM)
	plea_page.add_child(plea_softness_label)
	plea_softness_bar = ProgressBar.new()
	plea_softness_bar.max_value = BjPlea.MAX_SOFTNESS
	plea_softness_bar.show_percentage = false
	plea_softness_bar.add_theme_stylebox_override("background",
		BjTheme.panel_style(BjTheme.INK, BjTheme.PANEL_LINE, 2))
	plea_softness_bar.add_theme_stylebox_override("fill",
		BjTheme.panel_style(BjTheme.ACCENT, BjTheme.ACCENT_DARK, 0))
	plea_page.add_child(plea_softness_bar)

	plea_info_label = BjTheme.label("", 13, BjTheme.TEXT_DIM)
	plea_page.add_child(plea_info_label)

	# 自由输入：三轮，说你想说的
	plea_input = LineEdit.new()
	plea_input.placeholder_text = "跟它说点什么……（回车发送）"
	plea_input.max_length = 60
	plea_input.add_theme_font_override("font", BjTheme.font())
	plea_input.add_theme_font_size_override("font_size", 15)
	plea_input.add_theme_stylebox_override("normal",
		BjTheme.panel_style(BjTheme.INK, BjTheme.PANEL_LINE, 2))
	plea_input.add_theme_stylebox_override("focus",
		BjTheme.panel_style(BjTheme.INK, BjTheme.ACCENT, 2))
	plea_input.text_submitted.connect(func(_text: String) -> void: _on_send_plea())
	plea_page.add_child(plea_input)
	plea_send_button = BjTheme.make_button("说", "primary")
	plea_send_button.pressed.connect(_on_send_plea)
	plea_page.add_child(plea_send_button)

	# 四个"快速说"模板：点一下填进输入框（还能改），不是直接发送
	for intent in BjPlea.QUICK_FILL.keys():
		var button := BjTheme.make_button("", "chip")
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_quick_fill.bind(str(intent)))
		plea_page.add_child(button)
		plea_buttons.append(button)

	plea_log = BjTheme.label("", 14, BjTheme.TEXT)
	plea_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plea_log.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	plea_page.add_child(plea_log)

	plea_verdict_label = BjTheme.label("", 19, BjTheme.TEXT)
	plea_verdict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plea_page.add_child(plea_verdict_label)

	plea_debt_label = BjTheme.label("", 14, BjTheme.ACCENT)
	plea_page.add_child(plea_debt_label)

	plea_continue_button = BjTheme.make_button("收下钱，继续", "primary")
	plea_continue_button.pressed.connect(_on_loan_continue)
	plea_page.add_child(plea_continue_button)
	plea_restart_button = BjTheme.make_button("算了，重新开始", "accent")
	plea_restart_button.pressed.connect(_on_restart)
	plea_page.add_child(plea_restart_button)


func _build_stats_panel() -> void:
	stats_panel = Control.new()
	stats_panel.visible = false
	stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(stats_panel)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	stats_panel.add_child(backdrop)
	var panel := Panel.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", BjTheme.panel_style(BjTheme.PANEL, BjTheme.PANEL_LINE, 3))
	stats_panel.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(BjTheme.label("战绩与它眼里的你", 22, BjTheme.ACCENT))
	var body := BjTheme.label("", 16, BjTheme.TEXT)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	var close_button := BjTheme.make_button("关闭", "primary")
	close_button.pressed.connect(func() -> void: stats_panel.visible = false)
	box.add_child(close_button)


# ---------------------------------------------------------------- 布局

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if stage != null and whale != null:
			_layout()


func _layout() -> void:
	var width := size.x
	var height := size.y
	if width < 320.0 or height < 240.0:
		# 尺寸还没同步（第一帧之前的兜底）：用视口尺寸。
		var viewport_size := get_viewport_rect().size
		width = viewport_size.x
		height = viewport_size.y
	var top_h := top_bar_height()
	var action_h := 78.0
	var player_h := 200.0
	felt_rect = Rect2(0, top_h, width, maxf(200.0, height - top_h - action_h - player_h))
	player_rect = Rect2(0, felt_rect.end.y, width, player_h)
	action_rect = Rect2(0, player_rect.end.y, width, action_h)

	stage.position = felt_rect.position
	stage.size = felt_rect.size
	_stage_home = stage.position

	# 顶栏
	# 顶栏排成两行，互不重叠（尺寸按 Label 的**实际**高度算，不要按字号估）：
	#   第 1 行（y 4~38）  第 N 局 | 你 X token | 鲸鱼娘 X token
	#   第 2 行（y 38~64） 下注 X ~ Y · 还有几局升档
	# 顶栏总高 68（top_bar_height），两行加起来必须 ≤ 68。
	hand_label.position = Vector2(24, 4)
	player_pill.position = Vector2(200, 4)
	# 对手筹码栏往左收：右边要留给战绩框。
	# 战绩框的内容在最坏组合下要 354px（10 位数筹码 + 欠款 + 三位数局号），
	# 只靠裁剪的话那几个字会被切掉 —— 所以要给它**真的够宽**，而不是靠裁。
	# 380 这个位置是按最坏文本算过的：「鲸鱼娘 10亿 token」宽 190，右边界 570，
	# 和框的 580 留 10px；再往右就会被右下角的断言抓到重叠（试过 400，被它拦下）。
	opp_pill.position = Vector2(380, 4)
	stake_label.position = Vector2(24, 38)
	# 右上角：战绩框 + 三个按钮**排成一排不重叠**。
	# 之前「规则」按钮落在战绩框底下，被压住了（用户报的遮挡）。
	#
	# ⚠️ 宽度必须放得下内容的**最小宽度**：Godot 不允许 `size` 小于
	# `get_combined_minimum_size()`，一旦内容（两行标签 + 分隔）算出来比框宽，
	# 框不会裁剪，而是**整个内容撑到框外面**（"DeepSeek 在线"显示在框外就是这么来的）。
	# 内容最小宽约 282 + 左右各 8 的边距 = 298，所以这里给 310。
	# 左边是空的（筹码文字到 570 就结束了），往左加宽不会挤到别人。
	stats_box.position = Vector2(width - 700, 9)
	stats_box.size = Vector2(390, 48)
	var stats_rows := stats_box.get_node_or_null("Rows") as VBoxContainer
	if stats_rows != null:
		stats_rows.position = Vector2(8, 6)
		stats_rows.size = Vector2(390 - 16, 36)
	rules_button.position = Vector2(width - 292, 16)
	menu_button.position = Vector2(width - 204, 16)
	settings_button.position = Vector2(width - 116, 16)

	# 底池：单挑的全部经济学都写在这一行上
	pot_label.position = Vector2(0, 6)
	pot_label.size = Vector2(felt_rect.size.x, 24)

	# 对家区（没有庄家了，它一个人占满上半张桌子）
	var whale_w := 48.0 * float(whale.scale_factor)
	var whale_h := 57.0 * float(whale.scale_factor)
	var hand_w := 560.0
	var block_w := whale_w + 60.0 + hand_w
	var block_x := maxf(24.0, (felt_rect.size.x - block_w) / 2.0)
	var top := 44.0
	opponent_row.position = Vector2(0, top)
	opponent_row.size = Vector2(felt_rect.size.x, felt_rect.size.y - top)
	whale.set_base_position(Vector2(block_x, 0))
	bubble.position = Vector2(block_x - 30.0, whale_h + 6.0)
	bubble.size = Vector2(maxf(260.0, whale_w + 90.0), 60.0)
	opp_hand.max_width = hand_w
	opp_hand.position = Vector2(block_x + whale_w + 60.0, 10)
	opp_hand.size = Vector2(hand_w, BjCardView.CARD_SIZE.y + 8)
	# 点数 / 跟注 / 筹码堆都压在它的牌下面，且要在气泡上沿之上
	opp_total.position = Vector2(block_x + whale_w + 60.0, 130)
	opp_bet_label.position = Vector2(block_x + whale_w + 60.0, 156)
	# 筹码堆靠右放：气泡在鲸鱼娘下方、宽度能到 260，靠左会被压住
	opp_chip_stack.position = Vector2(block_x + whale_w + 60.0 + hand_w - 40.0, 156)

	# 你的区域
	player_row.position = player_rect.position
	player_row.size = Vector2(width, player_h)
	player_tag.position = Vector2(24, 10)
	player_chip_stack.position = Vector2(24, 38)
	player_hand.max_width = 700.0
	player_hand.position = Vector2((width - player_hand.max_width) / 2.0, 56)
	player_hand.size = Vector2(player_hand.max_width, BjCardView.CARD_SIZE.y + 8)
	player_total.position = Vector2(width / 2.0 - 150, 12)
	player_bet_label.position = Vector2(width / 2.0 + 40, 12)

	# 动作栏
	action_bar.position = Vector2(24, action_rect.position.y + 18)
	action_bar.size = Vector2(width - 48, 44)
	toast.position = Vector2(0, action_rect.position.y - 34)
	toast.size = Vector2(width, 24)

	# 弹窗遮罩：**锚点归零 + 显式给尺寸**。
	# 之前只调了 set_anchors_preset(FULL_RECT)，但那时父节点尺寸还是 0，
	# 整层实际是 0×0 —— 鼠标直接穿透到背后的下注 / 发牌 / 再来一局按钮上（用户报的问题）。
	# 保留 FULL_RECT 锚点又显式设 size 会被引擎覆盖并报警告，所以先把锚点归零。
	for overlay in [settings_panel, stats_panel, bankrupt_panel, rules_panel, cg_layer]:
		var item := overlay as Control
		if item == null:
			continue
		item.set_anchors_preset(Control.PRESET_TOP_LEFT)
		item.position = Vector2.ZERO
		item.size = Vector2(width, height)

	# 规则页
	var rules_box := rules_panel.get_node_or_null("Panel") as Panel
	if rules_box != null:
		var rules_h := minf(660.0, height - 80.0)
		rules_box.position = Vector2(width / 2.0 - 380.0, (height - rules_h) / 2.0)
		rules_box.size = Vector2(760, rules_h)
		var rules_title := rules_box.get_node_or_null("Title") as Label
		if rules_title != null:
			rules_title.position = Vector2(28, 18)
			rules_title.size = Vector2(700, 30)
		if rules_scroll != null:
			rules_scroll.position = Vector2(24, 58)
			rules_scroll.size = Vector2(712, rules_h - 130.0)
		var rules_close := rules_box.get_node_or_null("CloseButton") as Button
		if rules_close != null:
			rules_close.position = Vector2(260, rules_h - 58.0)
			rules_close.size = Vector2(240, 42)

	# 弹窗
	var panel := settings_panel.get_node_or_null("Panel") as Panel
	if panel != null:
		# 面板高度按屏幕留边自适应：中间是可滚动的设置项，底部按钮固定在面板里
		var panel_h := minf(700.0, height - 60.0)
		panel.position = Vector2(width / 2.0 - 250.0, (height - panel_h) / 2.0)
		panel.size = Vector2(500, panel_h)
		if settings_scroll != null:
			settings_scroll.position = Vector2(16, 14)
			settings_scroll.size = Vector2(468, panel_h - 130.0)
		if settings_footer != null:
			# 三个按钮**居中**摆在面板底部（之前是靠左贴着边，看着像位置错了）
			settings_footer.position = Vector2(16, panel_h - 106.0)
			settings_footer.size = Vector2(468, 42)
		if settings_help != null:
			settings_help.position = Vector2(16, panel_h - 56.0)
			settings_help.size = Vector2(468, 22)
	var stats_panel_node := stats_panel.get_node_or_null("Panel") as Panel
	if stats_panel_node != null:
		stats_panel_node.position = Vector2(width / 2.0 - 260.0, height / 2.0 - 200.0)
		stats_panel_node.size = Vector2(520, 400)
		var box := stats_panel_node.get_node_or_null("Box") as VBoxContainer
		if box != null:
			box.position = Vector2(18, 16)
			box.size = Vector2(484, 368)
			var body := box.get_node_or_null("Body") as Label
			if body != null:
				body.custom_minimum_size = Vector2(484, 240)

	# 战败 CG：整屏铺满（保持比例），标题在上、她的台词压在下沿
	cg_image.position = Vector2(0, 0)
	cg_image.size = Vector2(width, height)
	# 缓慢推进要绕中心缩放，不然画面会往右下角"滑"
	cg_image.pivot_offset = Vector2(width / 2.0, height / 2.0)
	cg_title.position = Vector2(0, 42)
	cg_title.size = Vector2(width, 24)
	cg_caption.position = Vector2(0, height - 132)
	cg_caption.size = Vector2(width, 40)
	cg_hint.position = Vector2(0, height - 88)
	cg_hint.size = Vector2(width, 24)
	cg_button.position = Vector2(width / 2.0 - 90.0, height - 58)
	cg_button.size = Vector2(180, 42)

	# 输光弹窗
	var bankrupt_page_node := bankrupt_page
	bankrupt_page_node.position = Vector2(width / 2.0 - 290.0, height / 2.0 - 170.0)
	bankrupt_page_node.size = Vector2(580, 340)
	var bankrupt_box := bankrupt_page_node.get_node_or_null("Box") as VBoxContainer
	if bankrupt_box != null:
		bankrupt_box.position = Vector2(22, 20)
		bankrupt_box.size = Vector2(536, 300)
	win_page.position = bankrupt_page_node.position
	win_page.size = bankrupt_page_node.size
	var win_box := win_page.get_node_or_null("Box") as VBoxContainer
	if win_box != null:
		win_box.position = Vector2(22, 20)
		win_box.size = Vector2(536, 300)
	dead_page.position = Vector2(width / 2.0 - 290.0, height / 2.0 - 150.0)
	dead_page.size = Vector2(580, 300)
	var dead_box := dead_page.get_node_or_null("Box") as VBoxContainer
	if dead_box != null:
		dead_box.position = Vector2(24, 26)
		dead_box.size = Vector2(532, 250)

	plea_page.position = Vector2(width / 2.0 - 320.0, height / 2.0 - 282.0)
	plea_page.size = Vector2(640, 564)
	var whale_scale := float(plea_whale.scale_factor)
	plea_whale.set_base_position(Vector2(26, 22))
	plea_bubble.position = Vector2(26, 22 + 57.0 * whale_scale + 8.0)
	plea_bubble.size = Vector2(400, 60)
	plea_softness_label.position = Vector2(452, 26)
	plea_softness_bar.position = Vector2(452, 52)
	plea_softness_bar.size = Vector2(160, 18)
	plea_info_label.position = Vector2(452, 76)
	plea_info_label.size = Vector2(164, 84)
	plea_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plea_input.position = Vector2(26, 244)
	plea_input.size = Vector2(468, 40)
	plea_send_button.position = Vector2(506, 244)
	plea_send_button.size = Vector2(108, 40)
	for i in range(plea_buttons.size()):
		plea_buttons[i].position = Vector2(26 + float(i) * 148.0, 296.0)
		plea_buttons[i].size = Vector2(140, 34)
	plea_log.position = Vector2(26, 342)
	plea_log.size = Vector2(588, 112)
	plea_verdict_label.position = Vector2(26, 458)
	plea_verdict_label.size = Vector2(588, 52)
	plea_debt_label.position = Vector2(26, 512)
	plea_continue_button.position = Vector2(26, 536)
	plea_continue_button.size = Vector2(240, 40)
	plea_restart_button.position = Vector2(286, 536)
	plea_restart_button.size = Vector2(240, 40)

	# 中央横幅（横幅在 stage 之外，所以按整屏居中算）
	banner_box.position = Vector2(0, height / 2.0 - 90.0)
	banner_box.size = Vector2(width, 120)
	banner_box.pivot_offset = Vector2(width / 2.0, 60.0)
	queue_redraw()


# ---------------------------------------------------------------- 刷新

func _refresh() -> void:
	var machine := game.machine
	var phase := machine.phase()
	var in_hand := machine.has_hand() and phase != BjMachine.PHASE_SETTLE
	hand_label.text = "第 %d 局" % (machine.hand_no if in_hand else machine.hand_no + 1)
	# 用 max_stake()（**实际能押的上限**）而不是单纯的档位上限：
	# 档位越往后，档位上限会超过你的身家，直接写出来就是骗人。
	# 这个数也正是"ALL IN 什么时候出现"的判据。
	#
	# 后面再挂一句**进度 / 预警**：20 局就封顶，玩家需要知道
	# "还有几局涨"以及"下一档我付不付得起" —— 后者就是被赶下桌的那一刻。
	var level := machine.stake_level()
	var max_level := BjMachine.STAKE_MIN_STEPS.size() - 1
	var floor_bet := machine.min_stake()
	var ceiling := machine.max_stake()
	var next_min := 0
	if level < max_level:
		next_min = int(BjMachine.STAKE_MIN_STEPS[level + 1])
	# "你正在被涨注赶下牌桌"的两态：连底注都付不起 / 付不起下一档。
	# 这两种都要**报一声警**，但只在刚进入这个状态时响一次（不然每帧都响）。
	var in_danger := machine.player_chips < floor_bet \
		or (level < max_level and machine.player_chips < next_min)
	if in_danger and not _warned_about_stake:
		sfx.play("warn")
	_warned_about_stake = in_danger
	if machine.player_chips < floor_bet:
		# 连底注都付不起了（下一局就会被请去求情/重开）
		stake_label.text = "下注至少 %s，你只剩 %s —— 付不起底注了" % [
			BjTokens.format(floor_bet), BjTokens.format(machine.player_chips),
		]
		stake_label.modulate = BjTheme.DANGER
	elif level >= max_level:
		stake_label.text = "下注 %s ~ %s　·　已到顶档" % [
			BjTokens.format(floor_bet), BjTokens.format(ceiling),
		]
		stake_label.modulate = BjTheme.TEXT_DIM
	elif machine.player_chips < next_min:
		stake_label.text = "下注 %s ~ %s　·　下一档最小注 %s，你只剩 %s" % [
			BjTokens.format(floor_bet), BjTokens.format(ceiling),
			BjTokens.format(next_min), BjTokens.format(machine.player_chips),
		]
		stake_label.modulate = BjTheme.DANGER
	else:
		@warning_ignore("integer_division")
		var left := BjMachine.STAKE_HANDS_PER_LEVEL \
			- (machine.hand_no % BjMachine.STAKE_HANDS_PER_LEVEL)
		stake_label.text = "下注 %s ~ %s　·　%d 局后升到 %s" % [
			BjTokens.format(floor_bet), BjTokens.format(ceiling),
			left, BjTokens.format(next_min),
		]
		stake_label.modulate = BjTheme.TEXT_DIM
	_announce_stake_up()
	# 筹码数字**滚**出来，不是直接跳（强化得失感知）
	_roll_to(player_pill, machine.player_chips, "你 %s token")
	_roll_to(opp_pill, machine.opponent_chips, "鲸鱼娘 %s token")
	var st := game.stats()
	win_label.text = str(int(st["wins"]))
	loss_label.text = str(int(st["losses"]))
	push_label.text = str(int(st["pushes"]))
	best_label.text = "最高 %s" % BjTokens.format(game.best_chips())
	var net := int(st["net_chips"])
	net_label.text = "净 %s" % BjTokens.format_delta(net)
	if net > 0:
		net_label.modulate = BjTheme.WIN
	elif net < 0:
		net_label.modulate = BjTheme.DANGER
	else:
		net_label.modulate = BjTheme.TEXT_DIM
	debt_label.visible = game.debt > 0
	debt_label.text = "欠它 %s" % BjTokens.format(game.debt)
	# 状态框右上角那个小标：**已自动连接 DSH** 是插件启动时的状态 ——
	# 意思是"key 由 DSH 宿主注入，你不用填"。手动填 key 时仍然显示 DeepSeek 在线。
	if game.auto_connected():
		brain_label.text = "已自动连接 DSH"
		brain_label.modulate = BjTheme.WIN
	elif game.using_llm():
		brain_label.text = "DeepSeek 在线"
		brain_label.modulate = BjTheme.OPP
	else:
		brain_label.text = "本地 AI"
		brain_label.modulate = BjTheme.TEXT_DIM

	# 手牌先刷新（它会记下"动画还要多久"），点数才知道要等到什么时候
	_refresh_hands(false)
	_refresh_opp_total()
	if machine.has_hand():
		var amount := machine.stake()
		pot_label.text = "本局注额 %s token（双方各押 %s，赢家拿走对方那份）" % [
			BjTokens.format(amount), BjTokens.format(amount),
		]
		opp_bet_label.text = "它跟注 %s token" % BjTokens.format(amount)
		player_bet_label.text = "你押 %s token%s" % [
			BjTokens.format(amount),
			"　· 已加注（它也跟了）" if machine.state["player"]["doubled"] else "",
		]
		opp_chip_stack.set_amount(amount)
		player_chip_stack.set_amount(amount)
	else:
		pot_label.text = "本局注额 %s token（你定注，它跟注）" % BjTokens.format(game.pending_bet)
		opp_bet_label.text = ""
		player_bet_label.text = ""
		opp_chip_stack.set_amount(0)
		player_chip_stack.set_amount(0)
	_refresh_player_total()

	# **轮到你了** → 一声清脆提示。
	# 先手轮换之后，它先手的局里你不知道什么时候轮到自己，光看按钮变亮太容易被忽略。
	if phase == BjMachine.PHASE_PLAYER_TURN and _last_phase != BjMachine.PHASE_PLAYER_TURN:
		sfx.play("turn")
	_last_phase = phase
	_refresh_action_bar(phase)
	_refresh_settings_widgets()
	queue_redraw()


## 它的点数。**要等牌动完再出现**：
##   - 摊牌翻开暗牌时等翻牌动画走完（不然像它偷看牌）；
##   - 它要牌时等新牌飞到位（不然点数先于牌冒出来）。
func _refresh_opp_total() -> void:
	var machine := game.machine
	if not machine.has_hand():
		opp_total.text = "—"
		opp_total.modulate = BjTheme.TEXT_DIM
		return
	var hole_hidden := machine.opponent_hole_hidden()
	var just_revealed := _opp_hole_hidden and not hole_hidden
	_opp_hole_hidden = hole_hidden
	var wait := opp_hand.anim_remaining()
	if just_revealed:
		wait = maxf(wait, TOTAL_REVEAL_DELAY)
	_opp_total_seq += 1
	var seq := _opp_total_seq
	if wait <= 0.02:
		_apply_opp_total(hole_hidden)
		return
	# 牌还在动：**数字原地不动**（保留上一个值），等牌落位再往上滚。
	# 早先这里会先清空再显示，用户直接指出"是先消失后再出现"——
	# 他要的是"数字一直在，然后往上滚"（像里程表）。
	await get_tree().create_timer(wait).timeout
	if seq != _opp_total_seq or not is_inside_tree():
		return
	_apply_opp_total(machine.opponent_hole_hidden())


## 你的点数。**数字全程在，只在牌落位那一刻往上滚**。
##
##   - 牌还在半空时：保留旧值不动（不清空 ✗ —— "先消失再出现"就是这么来的）
##   - 牌落位后：从旧值滚到新值（只往上，像里程表）
##   - 一局结束时：快速滚回 0，下一局再从 0 往上滚
func _refresh_player_total() -> void:
	if not game.machine.has_hand():
		player_total.text = "—"
		player_total.modulate = BjTheme.TEXT_DIM
		return
	_player_total_seq += 1
	var seq := _player_total_seq
	var wait := player_hand.anim_remaining()
	if wait <= 0.02:
		_apply_player_total()
		return
	await get_tree().create_timer(wait).timeout
	if seq != _player_total_seq or not is_inside_tree():
		return
	_apply_player_total()


func _apply_player_total() -> void:
	var hand := game.machine.player_hand()
	var busted := BjHand.is_bust(hand)
	var suffix := ""
	if BjHand.is_blackjack(hand):
		suffix = " · 黑杰克"
	elif busted:
		suffix = " · 爆牌"
	_roll_points(player_total, _shown_player_total, BjHand.value(hand), suffix,
		BjTheme.DANGER if busted else Color.WHITE)


func _apply_opp_total(hole_hidden: bool) -> void:
	var machine := game.machine
	if hole_hidden:
		# 暗牌还没翻：**把看得见的那几张直接报出来**（+ 一个"还有暗牌"的记号）。
		# 玩家不该被迫做心算 —— 这是公开信息，藏着只是让人算得累。
		# 后缀只写" + ?"：数字那部分已经带"点"了，写"点 + ?"会变成"6 点 点 + ?"
		_roll_points(opp_total, _shown_opp_total, _opp_visible_total(), " + ?",
			BjTheme.TEXT_DIM)
		return
	var busted := BjHand.is_bust(machine.opponent_hand())
	_roll_points(opp_total, _shown_opp_total, BjHand.value(machine.opponent_hand()),
		" · 爆牌" if busted else "", BjTheme.WIN if busted else Color.WHITE)


## 点数滚动：**数字一直挂在屏幕上**，从旧值一格一格滚到新值。
##
## 用户的要求很明确："他不是先消失后再出现，是**滚动向上的**"。
## 所以这里的原则是：
##   - 任何时候都不清空文字（清空 = "先消失"）；
##   - 每一帧都写一个真实的中间值，看起来就是数字在往上跳（里程表）；
##   - 每帧都写回 `_shown_*`，所以中途被打断也能从当前值接着滚，不会跳。
## `duration` 默认 0.45 秒；一局结束滚回 0 时用更短的 0.2 秒（那只是个复位）。
func _roll_points(label: Label, from: int, to: int, suffix: String, color: Color,
		duration: float = POINT_ROLL_TIME) -> void:
	if label == null:
		return
	var key := label.get_instance_id()
	var old: Tween = _point_tweens.get(key)
	if old != null and old.is_valid():
		old.kill()
	label.modulate = color
	if from == to or from < 0:
		label.text = "%d 点%s" % [to, suffix]
		_set_shown_points(key, to)
		return
	var tween := create_tween()
	_point_tweens[key] = tween
	tween.tween_method(func(value: float) -> void:
		var current := int(round(value))
		# 滚动中也带上后缀：否则她的" + ?"会跟着滚动一闪一闪的
		label.text = "%d 点%s" % [current, suffix]
		_set_shown_points(key, current),
		float(from), float(to), duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		label.text = "%d 点%s" % [to, suffix]
		_set_shown_points(key, to))


## 把"现在显示到几点"记回去（用标签 id 当键，双方各存一份）。
func _set_shown_points(key: int, value: int) -> void:
	if key == player_total.get_instance_id():
		_shown_player_total = value
	elif key == opp_total.get_instance_id():
		_shown_opp_total = value


## 它**看得见**的那几张牌的点数（跳过暗牌）。
func _opp_visible_total() -> int:
	var hand := game.machine.opponent_hand()
	var shown: Array = []
	for i in range(hand.size()):
		if i == 1 and game.machine.opponent_hole_hidden():
			continue
		shown.append(hand[i])
	return BjHand.value(shown)


func _refresh_hands(animate: bool) -> void:
	var machine := game.machine
	if not machine.has_hand():
		opp_hand.clear()
		player_hand.clear()
		_hand_shown = -1
		return
	var is_new := machine.hand_no != _hand_shown
	if is_new:
		# 新的一局：把上一局的点数**快速滚回 0**（0.2 秒），下一局再从 0 往上滚。
		# 关键是"滚回去"而不是"清空"—— 清空就是用户说的"先消失"。
		_roll_points(player_total, _shown_player_total, 0, "", BjTheme.TEXT_DIM, 0.2)
		_roll_points(opp_total, _shown_opp_total, 0, " + ?", BjTheme.TEXT_DIM, 0.2)
		_shown_player_total = 0
		_shown_opp_total = 0
		opp_hand.clear()
		player_hand.clear()
		_hand_shown = machine.hand_no
	# 发牌顺序：你明、它明、你明、它暗 —— 它第二张是暗牌，摊牌时才翻。
	#
	# **错峰只用于开局那 4 张**：后续补牌（要牌/加倍/它抽牌）必须**立刻飞出来**。
	# 之前错峰按"牌在手上的索引"算，于是你要的第 3 张牌会先干等 0.64×2 秒
	# 才动 —— 牌迟迟不出现、音效和点数被一起拖后（用户报的"特效慢半拍"根因）。
	var stagger := DEAL_STEP * 2.0 if is_new else 0.0
	var opp_start := DEAL_STEP if (animate and is_new) else 0.0
	opp_hand.set_cards(
		machine.opponent_hand(),
		[false, machine.opponent_hole_hidden()],
		0, stagger, opp_start)
	player_hand.set_cards(
		machine.player_hand(), [], 0, stagger, 0.0)


func _refresh_action_bar(phase: String) -> void:
	var machine := game.machine
	var actions := game.legal_actions()
	var betting := not machine.has_hand() or phase == BjMachine.PHASE_SETTLE
	var busy := game.acting

	bet_label.visible = betting
	chip_buttons.visible = betting
	# ALL IN 只在"最大注已经超过你拿得出的钱"时出现（用户定的规则）
	all_in_button.visible = betting and game.shows_all_in()
	current_bet_label.visible = betting
	deal_button.visible = betting
	result_label.visible = phase == BjMachine.PHASE_SETTLE
	hit_button.visible = not betting
	stand_button.visible = not betting
	double_button.visible = not betting and actions.has("DOUBLE")
	# "她正在想…"要在**它的回合**也显示：先手轮换之后，它先手的局里
	# 你还没轮到，如果只按 `acting` 判断，那段时间屏幕上是没有任何反馈的。
	var waiting := busy or phase == BjMachine.PHASE_OPPONENT_TURN
	waiting_label.visible = waiting

	if betting:
		_rebuild_chip_buttons()
		current_bet_label.text = "当前 %s token%s" % [
			BjTokens.format(game.pending_bet),
			"　（已全押）" if game.is_all_in() else "",
		]
		deal_button.disabled = (not game.can_deal()) or _modal_open()
		all_in_button.text = "已全押 %s" % BjTokens.format(game.all_in_stake()) \
			if game.is_all_in() else "ALL IN %s" % BjTokens.format(game.all_in_stake())
		all_in_button.disabled = game.is_all_in() or _modal_open()
	if not betting:
		hit_button.disabled = (not actions.has("HIT")) or _modal_open()
		stand_button.disabled = (not actions.has("STAND")) or _modal_open()
		double_button.disabled = (not actions.has("DOUBLE")) or _modal_open()
	# 弹窗挡着 / 摊牌还没演完时，牌桌上的按钮全部置灰 —— 提示框才是唯一能操作的东西
	var modal := _modal_open() or _showing_down()
	for child in chip_buttons.get_children():
		if child is Button:
			child.disabled = modal
	if modal:
		deal_button.disabled = true
	if waiting:
		if game.thinking:
			waiting_label.text = "鲸鱼娘正在想…"
		else:
			waiting_label.text = "正在发牌…"
	if phase == BjMachine.PHASE_SETTLE:
		var outcome := machine.outcome()
		var delta: int = int(outcome.get("player_delta", 0))
		# 魔改倍率：把"这一把为什么赢这么多"写在结果条上
		var bonus := str(outcome.get("bonus", ""))
		var mult := float(outcome.get("bonus_mult", 0.0))
		var bonus_text := ""
		if bonus != "" and mult > 1.0:
			bonus_text = "　【%s ×%s】" % [bonus, _trim_mult(mult)]
		if delta > 0:
			result_label.text = "你赢了 %s token（从它手里）%s" % [
				BjTokens.format(delta), bonus_text,
			]
			result_label.modulate = BjTheme.WIN
		elif delta < 0:
			result_label.text = "你输了 %s token（进了它口袋）" % BjTokens.format(-delta)
			result_label.modulate = BjTheme.DANGER
		else:
			result_label.text = "平局，谁也没拿到"
			result_label.modulate = BjTheme.TEXT_DIM


## 倍率显示成 "1.2" / "2" / "2.5"（不要 "2.0" 这种多余的零）。
func _trim_mult(mult: float) -> String:
	if absf(mult - roundf(mult)) < 0.001:
		return str(int(roundf(mult)))
	return String.num(mult, 1)


## 五小龙 / 六小龙：摸到的**当场**报喜（倍数要等摊牌才结算）。
##
## 第 5 张故意提示"还能搏 2.5"，因为引擎那边**不会**自动停牌 ——
## 不告诉玩家的话，他会以为游戏卡住了（明明 5 张了还能继续要牌）。
func _announce_charlie(cards: int, total: int) -> void:
	if cards >= BjMachine.CHARLIE_CARDS_6:
		show_banner("六小龙！", "%d 张 %d 点不爆　·　停牌就是 ×%s" % [
			cards, total, _trim_mult(BjMachine.CHARLIE_6_MULT),
		], BjTheme.WIN, 2.0)
	else:
		show_banner("五小龙！", "%d 张 %d 点不爆　·　停牌 ×%s；再要一张搏 ×%s，爆了就全没" % [
			cards, total,
			_trim_mult(BjMachine.CHARLIE_5_MULT),
			_trim_mult(BjMachine.CHARLIE_6_MULT),
		], BjTheme.ACCENT, 2.4)
	sfx.play("charlie")
	_pulse("_set_glow", 1.0, 0.6, 6)
	_pulse("_set_burst", 1.0, 0.5, 8)


func _rebuild_chip_buttons() -> void:
	for child in chip_buttons.get_children():
		child.queue_free()
	var modal := _modal_open()
	for option in game.bet_options():
		var button := BjTheme.make_button(BjTokens.format(option), "chip")
		button.disabled = modal
		button.pressed.connect(_on_chip.bind(option))
		chip_buttons.add_child(button)


func _refresh_settings_widgets() -> void:
	var panel := settings_panel.get_node_or_null("Panel") as Panel
	if panel == null:
		return
	var box := panel.get_node_or_null("Scroll/Box") as VBoxContainer
	if box == null:
		box = panel.get_node_or_null("Box") as VBoxContainer
	if box == null:
		return
	var sound_button := box.get_node_or_null("SoundButton") as Button
	if sound_button != null:
		sound_button.text = "音效：%s" % ("开" if bool(game.settings.get("sound", true)) else "关")
	var voice_button := box.get_node_or_null("VoiceButton") as Button
	if voice_button != null:
		voice_button.text = "语音：%s" % ("开" if bool(game.settings.get("voice", false)) else "关")
		voice_button.disabled = not (voice.has_clips()
			or DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH))
	var style_button := box.get_node_or_null("VoiceStyleButton") as Button
	if style_button != null:
		var ids := voice.available_voices()
		style_button.visible = ids.size() > 0
		if ids.size() > 0:
			var index: int = maxi(0, ids.find(str(game.settings.get("voice_id", voice.voice_id))))
			style_button.text = "配音：%s（%d/%d）" % [
				voice.label_for(ids[index]), index + 1, ids.size(),
			]
		style_button.disabled = not bool(game.settings.get("voice", false))
	var online_button := box.get_node_or_null("VoiceOnlineButton") as Button
	if online_button != null:
		var wants := bool(game.settings.get("voice_online", true))
		var can := voice.synth_available()
		if not wants:
			online_button.text = "在线配音：关（只播烤好的台词）"
		elif can:
			online_button.text = "在线配音：开（现编台词现烤）"
		else:
			online_button.text = "在线配音：不可用（缺 python/edge-tts）"
		online_button.disabled = not bool(game.settings.get("voice", false)) or (wants and not can)
	var bgm_button := box.get_node_or_null("BgmButton") as Button
	if bgm_button != null:
		bgm_button.visible = bgm.has_track()
		bgm_button.text = "BGM：%s（%s）" % [
			"开" if bool(game.settings.get("bgm", true)) else "关", bgm.track_name(),
		]
	var bg_button := box.get_node_or_null("BackgroundButton") as Button
	if bg_button != null:
		bg_button.visible = ResourceLoader.exists(BACKGROUND_PATH)
		bg_button.text = "桌布：%s" % (
			"图片" if bool(game.settings.get("background", true)) else "程序化绿呢毯")
	var whale_button := box.get_node_or_null("WhaleButton") as Button
	if whale_button != null:
		whale_button.text = "鲸鱼娘大小：%d 倍" % int(game.settings.get("whale_scale", 3))
	var llm_button := box.get_node_or_null("LlmButton") as Button
	if llm_button != null:
		llm_button.text = "对手大脑：%s" % ("DeepSeek API" if bool(game.settings.get("use_llm", false)) else "本地 AI")
	# 插件启动 → 告诉玩家"你不用填 key"，并把手填入口的说明改成"仅在需要覆盖时用"
	var dsh_note := box.get_node_or_null("DshNote") as Label
	if dsh_note != null:
		if game.auto_connected():
			dsh_note.text = "✔ 已自动连接 DSH（凭据由插件注入，下面的 Key 留空即可）"
			dsh_note.visible = true
		else:
			dsh_note.visible = false
	var key_edit := box.get_node_or_null("KeyEdit") as LineEdit
	if key_edit != null and not key_edit.has_focus():
		key_edit.text = str(game.settings.get("api_key", ""))
	var model_edit := box.get_node_or_null("ModelEdit") as LineEdit
	if model_edit != null and not model_edit.has_focus():
		model_edit.text = str(game.settings.get("model", "deepseek-chat"))


# ---------------------------------------------------------------- 信号

func _on_hand_dealt(_events: Array) -> void:
	_refresh_hands(true)
	_refresh()
	# 4 张牌：你明、它明、你明、它暗
	for i in range(4):
		_schedule_sfx("deal", DEAL_STEP * float(i))
	_announce_blackjack()


## 拿到黑杰克 → 横幅 + 特效 + 播报 1.5 倍奖励（用户要的"专属反馈"）。
## 等牌落位再报：字比牌先出现就白做了。
func _announce_blackjack() -> void:
	var machine := game.machine
	if not machine.has_hand() or not BjHand.is_blackjack(machine.player_hand()):
		return
	if _bj_hand_announced == machine.hand_no:
		return
	_bj_hand_announced = machine.hand_no
	var wait := player_hand.anim_remaining() + 0.12
	if wait > 0.02:
		await get_tree().create_timer(wait).timeout
	if not is_inside_tree():
		return
	show_banner("BLACKJACK！", "1.5 倍筹码奖励　·　本局 %s token" % [
		BjTokens.format(machine.stake()),
	], BjTheme.ACCENT, 1.6)
	sfx.play("blackjack")
	_pulse("_set_burst", 1.0, 0.55, 6)
	_pulse("_set_glow", 1.0, 0.5, 4)
	_fly_tokens(true)


## 破纪录 → 横幅（等筹码滚动先跑完，两个动画别叠在一起）。
func _on_new_record(best: int, previous: int) -> void:
	await get_tree().create_timer(ROLL_TIME + 0.15).timeout
	if not is_inside_tree():
		return
	show_banner("新纪录！", "历史最高 %s token（上一次 %s）" % [
		BjTokens.format(best), BjTokens.format(previous),
	], BjTheme.WIN, 1.5)
	sfx.play("record")
	_pulse("_set_glow", 1.0, 0.6, 6)


## 涨注提醒：档位一变就弹横幅把"新的底注上限"念出来。
## 不提醒的话玩家只会觉得"怎么突然变贵了"，而不知道这是**每 N 局一档**的规则。
func _announce_stake_up() -> void:
	var level := game.machine.stake_level()
	if _stake_level_shown < 0:
		_stake_level_shown = level      # 首次不弹（那不是"涨"）
		return
	if level <= _stake_level_shown:
		return
	var previous: int = int(BjMachine.STAKE_MIN_STEPS[clampi(
		_stake_level_shown, 0, BjMachine.STAKE_MIN_STEPS.size() - 1)])
	_stake_level_shown = level
	show_banner("下注额上调！", "第 %d 档　最小注 %s → %s　·　最大注 %s token" % [
		level + 1,
		BjTokens.format(previous),
		BjTokens.format(game.machine.min_stake()),
		BjTokens.format(game.machine.min_stake() * BjMachine.MAX_STAKE_MULTIPLIER),
	], BjTheme.ACCENT, 2.0)
	sfx.play("level_up")


func _on_action_events(events: Array) -> void:
	var sound := ""
	for event in events:
		match str(event.get("type", "")):
			"HIT":
				sound = "hit"
			"STAND":
				sound = "stand"
			"DOUBLE":
				sound = "double"
			"BUST":
				sound = "bust"
			"CHARLIE":
				# 五小龙/六小龙：当场报喜（自己的音效，比黑杰克更长更亮）
				_announce_charlie(int(event.get("cards", 0)), int(event.get("total", 0)))
			"SETTLE":
				sound = _settle_sound_name(event)
	# **先把新牌摆上**：这一步会记下"动画还要多久"，
	# 音效才知道该等到什么时候 —— 不然牌还在半空音效就响了（用户报的问题）。
	_refresh_hands(false)
	_refresh()
	if sound != "":
		_delayed_sfx(sound, _longest_anim())


## 手上（双方）还有多久才动完。
func _longest_anim() -> float:
	return maxf(player_hand.anim_remaining(), opp_hand.anim_remaining())


## 延迟播放音效，让它和"牌到位 + 点数出现"同一时刻发生。
func _delayed_sfx(sound_name: String, delay: float) -> void:
	if delay <= 0.02:
		sfx.play(sound_name)
		return
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():
		sfx.play(sound_name)


## 摊牌该响哪个音（只算名字，播放在 _on_action_events 里统一延后）。
func _settle_sound_name(outcome: Dictionary) -> String:
	if bool(outcome.get("player_blackjack", false)) or bool(outcome.get("opponent_blackjack", false)):
		return "blackjack"
	var delta: int = int(outcome.get("player_delta", 0))
	# 魔改倍率单独给音：赢的时候要能听出"这把是抓爆还是普通赢"
	if delta > 0 and str(outcome.get("bonus", "")) == "抓它爆牌":
		return "bust_bonus"
	if delta > 0:
		return "win"
	elif delta < 0:
		return "lose"
	return "push"


## 当前该画哪张脸。
##
## 关键设计：**表情由人格（战绩养出来的四个标量）决定**，不是由这句话的情绪决定 ——
## 所以它会随着赢输一路变脸（赢麻了得意、连输开始烦躁、被你压着就收敛）。
## 例外只有一个：演出台词带来的强情绪优先（尤其"震惊"，人格瀑布永远给不出它）。
func _current_face() -> String:
	var mood := str(game.cue.get("mood", "calm"))
	if str(game.cue.get("kind", "emote")) == "play" or mood == "calm":
		mood = BjPersona.mood(game.persona)
	return BjPersona.face_for(mood, game.machine.phase(), game.thinking)


func _on_cue(cue: Dictionary) -> void:
	var phase := game.machine.phase()
	# 彩蛋进行中别把生气脸冲掉（但台词气泡该更新还是更新）
	if not _poking:
		whale.set_face(_current_face())
	whale.set_thinking_bob(game.thinking)
	bubble.set_text(str(cue.get("bubble", "")), str(cue.get("kind", "emote")))
	if str(cue.get("note", "")) != "":
		_on_notice(str(cue["note"]))
	if game.settings.get("voice", false):
		_speak(str(cue.get("bubble", "")))
	var fx: Array = cue.get("fx", [])
	if not fx.is_empty():
		_play_fx(fx)
	_refresh_action_bar(phase)


func _on_thinking(value: bool) -> void:
	whale.set_thinking_bob(value)
	whale.set_face(_current_face())
	_refresh_action_bar(game.machine.phase())


func _on_settled(_outcome: Dictionary) -> void:
	_refresh_hands(false)
	_refresh()


func _on_notice(message: String) -> void:
	toast.text = message
	toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(toast, "modulate:a", 0.0, 0.6)


# ---------------------------------------------------------------- 输光：求情 / 重新开始

func _on_bankrupt() -> void:
	# 让摊牌先演完（翻暗牌 → 点数 → 结果条），CG 再缓慢浮现
	await _hold_for_showdown()
	if not is_inside_tree():
		return
	_show_cg("lose_all", _show_bankrupt_page)


## 摊牌演出还没结束吗（时间戳判断，卡不死）。
func _showing_down() -> bool:
	return Time.get_ticks_msec() < _showdown_until_msec


## 摊牌期间先别让玩家把这一局翻过去（等它演完再放 CG）。
##
## 用**时间戳**记，不用布尔标志 —— 布尔标志一旦因为协程被打断而卡住，
## 就会永久锁死整张桌子（用户报的"点一下直接卡死"）。时间戳最多锁 SHOWDOWN_HOLD 秒。
func _hold_for_showdown() -> void:
	_showdown_until_msec = Time.get_ticks_msec() + int(SHOWDOWN_HOLD * 1000.0)
	await get_tree().create_timer(SHOWDOWN_HOLD).timeout
	if is_inside_tree():
		_refresh_action_bar(game.machine.phase())


func _show_bankrupt_page() -> void:
	_switch_bankrupt_page(bankrupt_page)
	var body := bankrupt_page.get_node_or_null("Box/Body") as Label
	if body != null:
		body.text = "你只剩 %s token，连 %s 的最小注都付不起了。\n它手上还有 %s token。" % [
			BjTokens.format(game.machine.player_chips),
			BjTokens.format(game.machine.min_stake()),
			BjTokens.format(game.machine.opponent_chips),
		]
	var borrow := bankrupt_page.get_node_or_null("Box/Choices/BorrowButton") as Button
	if borrow != null:
		var can := game.can_borrow()
		borrow.disabled = not can
		borrow.text = "向鲸鱼娘求情借钱" if can else "它也没钱了，借不出来"
	var hint := bankrupt_page.get_node_or_null("Box/Hint") as Label
	if hint != null:
		if game.can_borrow():
			hint.text = "借它 %s，欠条按 %.2f 倍算；赢的钱一半先还它。\n重新开始：清空战绩，而且它会把你这号人忘得干干净净。" % [
				BjTokens.format(game.borrowable()), BjPlea.BASE_INTEREST,
			]
		else:
			hint.text = "它自己也快见底了，借不出来。\n重新开始：清空战绩，而且它会把你这号人忘得干干净净。"


## 它输光了：庆祝 CG（素材不存在就只弹提示）。同样先让摊牌演完。
## **补钱放在 CG 之后**：先让玩家看到它归零、看到 CG，再看到它搬钱回来。
func _on_opponent_bankrupt() -> void:
	await _hold_for_showdown()
	if not is_inside_tree():
		return
	_show_cg("you_win", _show_win_page)


## 彩蛋：戳鲸鱼娘。三次机会，一次比一次凶；第三次直接"被干掉"。
func _on_whale_poked() -> void:
	if _poking or cg_layer.visible or bankrupt_panel.visible:
		return
	_poking = true
	_poke_count += 1
	var level: int = mini(_poke_count, POKE_MAX)
	var line: String = POKE_LINES[level - 1]
	# 一次比一次凶：发声 → 抖得更狠 → 红光更强 → 屏幕也晃
	var shake_strength := 4.0 + 7.0 * float(level - 1)
	var shake_time := 0.30 + 0.18 * float(level - 1)
	var flash := 0.30 + 0.22 * float(level - 1)
	whale.set_face("angry")
	whale.shake(shake_strength, shake_time)
	bubble.set_text(line, "emote")
	sfx.play("bust" if level >= POKE_MAX else "talk")
	_speak(line)
	_pulse("_set_flash", flash, shake_time, 4 + level)
	if level >= 2:
		_schedule_shake_step(Vector2(-6.0 * float(level), 4.0), 0.0)
		_schedule_shake_step(Vector2(6.0 * float(level), -4.0), 0.08)
		_schedule_shake_step(Vector2(-4.0 * float(level), 3.0), 0.16)
		_schedule_shake_step(Vector2.ZERO, 0.24)

	if level >= POKE_MAX:
		# 第三次：缓慢黑化 → 重力一击 → 战败 CG
		await _blacken_and_strike()
		return

	await get_tree().create_timer(1.5).timeout
	if is_inside_tree():
		whale.set_face(_current_face())
	_poking = false


## 第三次：**缓慢黑化** → 重力一击（特效 + 音效）→ 战败 CG。
##
## 节奏是刻意的：先让它"越涨越满"（1.25 秒的黑化充能 + 世界变暗 + 低频轰鸣），
## 再一击砸下来（白闪 + 满屏震 + 冲击波 + 重击音），最后才放 CG。
func _blacken_and_strike() -> void:
	# 1) 充能
	whale.set_face("black")
	# 立绘本身也压一层冷紫，让"黑化"在 48×57 的小图上也能一眼看出来
	whale.modulate = Color(0.72, 0.62, 0.95, 1.0)
	sfx.play("charge")
	_pulse("_set_dark", 0.85, 1.25, 10)
	whale.shake(9.0, 1.25)
	await get_tree().create_timer(1.25).timeout
	if not is_inside_tree():
		return
	# 2) 一击
	sfx.play("impact")
	whale.shake(26.0, 0.55)
	_pulse("_set_white", 1.0, 0.20, 3)
	_pulse("_set_burst", 1.0, 0.5, 6)
	_pulse("_set_flash", 0.9, 0.35, 5)
	_schedule_shake_step(Vector2(-22, 14), 0.0)
	_schedule_shake_step(Vector2(20, -12), 0.05)
	_schedule_shake_step(Vector2(-14, 8), 0.11)
	_schedule_shake_step(Vector2(9, -5), 0.17)
	_schedule_shake_step(Vector2.ZERO, 0.24)
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	# 3) 收黑 + 战败 CG
	_poking = false
	_set_dark(0.55)
	_show_cg("poked", _after_poked)


## 被干掉之后：世界恢复，计数归零（彩蛋而已，不真扣你筹码）。
## 被干掉之后：世界恢复，但**只能完全重开**（用户定的规则：人已经死了）。
func _after_poked() -> void:
	_poke_count = 0
	_set_dark(0.0)
	_set_white(0.0)
	_set_flash(0.0)
	whale.modulate = Color.WHITE
	whale.set_face("sad")
	_show_dead_page()


func _on_plea_changed(state: Dictionary) -> void:
	if state.is_empty():
		_switch_bankrupt_page(null)
		return
	_switch_bankrupt_page(plea_page)

	var softness := int(state["softness"])
	var finished := bool(state["finished"])
	var agreed := bool(state["agreed"])

	plea_softness_bar.value = softness
	plea_softness_label.text = "心情值 %d / 100" % softness
	var loans := int(state.get("loans_taken", 0))
	plea_info_label.text = "还剩 %d 次说话机会\n借出上限 %s\n%s（心情越高，它给的越多）" % [
		BjPlea.ROUNDS - int(state["round"]),
		BjTokens.format(game.borrowable()),
		# 借过钱就明说：起点已经被压低，这是"越借越难借"的可视化
		"你借过 %d 次，它记得\n" % loans if loans > 0 else "",
	]

	# 它刚才那句回应 + 表情
	var lines: Array = state["lines"]
	if lines.is_empty():
		plea_bubble.set_text("……说吧，你想干嘛？", "emote")
	else:
		var last: Dictionary = lines[lines.size() - 1]
		# 好感涨/跌各有一声：求情小游戏里这是唯一的即时反馈，
		# 光看进度条动一下太容易被漏掉
		var delta := int(last["delta"])
		if delta > 0:
			sfx.play("favor_up")
		elif delta < 0:
			sfx.play("favor_down")
		plea_bubble.set_text(str(last["her"]), "emote")
		var mood := str(last["mood"])
		if delta < 0:
			mood = "tilted" if mood != "smug" else "smug"
		plea_whale.set_face(BjPersona.face_for(mood, "PLAYER_TURN", false))

	# 对话记录（只留最近几条）
	var log_lines: PackedStringArray = []
	var start_index: int = maxi(0, lines.size() - 3)
	for i in range(start_index, lines.size()):
		var entry: Dictionary = lines[i]
		log_lines.append("你：%s" % str(entry["you"]))
		log_lines.append("它：%s　（%s）" % [str(entry["her"]), str(entry["label"])])
	plea_log.text = "\n".join(log_lines)

	# 快速说模板
	for i in range(plea_buttons.size()):
		var intent: String = str(BjPlea.QUICK_FILL.keys()[i])
		plea_buttons[i].text = str(BjPlea.INTENT_LABELS[intent])
		plea_buttons[i].disabled = finished
	plea_input.editable = not finished
	plea_input.visible = not finished
	plea_send_button.visible = not finished

	if finished:
		var amount := int(state.get("amount", 0))
		var failed := bool(state.get("failed", false))
		if agreed:
			plea_verdict_label.text = "它答应了：「%s」" % str(state.get("verdict", ""))
			plea_verdict_label.modulate = BjTheme.WIN
			plea_debt_label.text = "放款 %s token　·　你现在一共欠它 %s token" % [
				BjTokens.format(amount), BjTokens.format(game.debt),
			]
		elif failed:
			# 心情值被扣到底：**她不想听了** —— 这一局彻底结束，只能重开
			plea_verdict_label.text = "它不想听了：「%s」" % str(state.get("verdict", ""))
			plea_verdict_label.modulate = BjTheme.DANGER
			plea_debt_label.text = "心情值掉到 %d —— 你把最后一句话也说没了。只能重开。" % softness
		else:
			plea_verdict_label.text = "它拒绝了：「%s」" % str(state.get("verdict", ""))
			plea_verdict_label.modulate = BjTheme.DANGER
			plea_debt_label.text = "心情值 %d，它一分都不想给 —— 只能重新开始了。" % softness
		plea_continue_button.visible = agreed
		plea_restart_button.text = "算了，重新开始" if agreed else "重新开始（清空战绩）"
	else:
		plea_verdict_label.text = "说你想说的 —— 它吃哪一套，看它现在什么脾气。"
		plea_verdict_label.modulate = BjTheme.TEXT_DIM
		plea_debt_label.text = ""
		plea_continue_button.visible = false
		plea_restart_button.text = "放弃，重新开始"


func _on_loan_granted(terms: Dictionary) -> void:
	sfx.play("coins")
	_on_notice("它借给你 %s token（欠 %s）" % [
		BjTokens.format(int(terms["amount"])), BjTokens.format(int(terms["debt"])),
	])


func _on_start_plea() -> void:
	game.start_plea()
	if plea_input != null:
		plea_input.grab_focus()


## 点"快速说"只是把模板填进输入框 —— 你还能改，再回车发出去。
func _on_quick_fill(intent: String) -> void:
	if plea_input == null:
		return
	plea_input.text = str(BjPlea.QUICK_FILL[intent])
	plea_input.caret_column = plea_input.text.length()
	plea_input.grab_focus()


func _on_send_plea() -> void:
	if plea_input == null or plea_input.text.strip_edges() == "":
		return
	if _plea_busy:
		return
	# 接了真模型时它要想一两秒 —— 期间锁住输入，免得连发
	_plea_busy = true
	plea_input.editable = false
	plea_send_button.disabled = true
	plea_bubble.set_text("……", "emote")
	var text := plea_input.text
	plea_input.text = ""
	await game.say_plea(text)
	_plea_busy = false
	if plea_send_button != null:
		plea_send_button.disabled = false
	if plea_input != null:
		plea_input.editable = plea_page.visible and not bool(game.plea_state.get("finished", true))
		if plea_input.editable:
			plea_input.grab_focus()


func _on_loan_continue() -> void:
	game.close_plea()


func _on_restart() -> void:
	# 选"重新开始"就是认输 —— 先挨它一句嘲讽，再清档
	_show_cg("give_up", game.restart_game)


func _on_bubble_blip() -> void:
	_talk_blip += 1
	if _talk_blip % 3 == 0:
		sfx.play("talk")


# ---------------------------------------------------------------- 输入

func _on_deal() -> void:
	# 摊牌还没演完就先别开下一局（不然玩家会把点数/结果看漏）
	if _showing_down() or _modal_open():
		return
	sfx.play("click")
	await game.deal()


func _send_action(action: String) -> void:
	await game.player_action(action)


func _on_chip(amount: int) -> void:
	sfx.play("chip")
	game.set_bet(amount)


## 一把梭。**点了还能改**（换个筹码面额就取消全押），
## 真正下注是"发牌"那一下 —— 所以误点不会直接把你送走。
func _on_all_in() -> void:
	sfx.play("all_in")
	game.set_bet_all_in()


## 当前有弹窗挡着吗（设置 / 战绩 / 输光 / 求情 / 赢了 / 被干掉 / CG）。
## 有弹窗时：牌桌上的按钮一律禁用 + 键盘快捷键一概不响应。
func _modal_open() -> bool:
	return settings_panel.visible or stats_panel.visible or bankrupt_panel.visible \
		or rules_panel.visible or (cg_layer != null and cg_layer.visible)


## 弹窗显隐后重算牌桌按钮（挂在各遮罩的 visibility_changed 上）。
## 顺便给设置/战绩/规则这三个"面板"配开合音效 —— CG 另有自己的音效，
## 所以按 `_modal_open()` 判断而不是无脑播。
func _sync_modal_buttons() -> void:
	_refresh_action_bar(game.machine.phase())
	if settings_panel.visible or stats_panel.visible or rules_panel.visible:
		sfx.play("panel_open")
	elif cg_layer == null or not cg_layer.visible:
		sfx.play("panel_close")


func _unhandled_input(event: InputEvent) -> void:
	# 战败 CG 最优先：点一下或按任意键翻过去
	if cg_layer != null and cg_layer.visible:
		get_viewport().set_input_as_handled()
		var pressed := false
		if event is InputEventKey:
			pressed = event.pressed and not event.echo
		elif event is InputEventMouseButton:
			pressed = event.pressed
		elif event is InputEventScreenTouch:
			pressed = event.pressed
		if pressed:
			_dismiss_cg()
		return
	if event.is_action_pressed("bj_settings"):
		get_viewport().set_input_as_handled()
		if settings_panel.visible:
			settings_panel.visible = false
		elif rules_panel.visible:
			_close_rules()
		else:
			_toggle_settings()
		return
	if settings_panel.visible or stats_panel.visible or bankrupt_panel.visible \
			or rules_panel.visible or dead_page.visible:
		# 有弹窗时只认 Esc（上面处理过了）—— 否则空格/A 这些会打到背后的牌桌上，
		# 玩家能在"借钱 or 重开"的提示框上把下一局发出去（用户报的问题）。
		return
	if event.is_action_pressed("bj_deal"):
		get_viewport().set_input_as_handled()
		if game.can_deal():
			_on_deal()
	elif event.is_action_pressed("bj_hit"):
		get_viewport().set_input_as_handled()
		_send_action("HIT")
	elif event.is_action_pressed("bj_stand"):
		get_viewport().set_input_as_handled()
		_send_action("STAND")
	elif event.is_action_pressed("bj_double"):
		get_viewport().set_input_as_handled()
		_send_action("DOUBLE")
	elif event.is_action_pressed("bj_all_in"):
		get_viewport().set_input_as_handled()
		if game.can_all_in():
			_on_all_in()
	elif game.machine.phase() == BjMachine.PHASE_SETTLE \
			or not game.machine.has_hand():
		# 1/2/3 选下注面额（只在能下注的时候响应）
		for i in range(1, 4):
			if event.is_action_pressed("bj_bet_%d" % i):
				get_viewport().set_input_as_handled()
				var options := game.bet_options()
				if i <= options.size():
					game.set_bet(int(options[i - 1]))
					sfx.play("chip")
				return


# ---------------------------------------------------------------- 面板

func _toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	stats_panel.visible = false
	_refresh_settings_widgets()


func _toggle_stats() -> void:
	stats_panel.visible = not stats_panel.visible
	settings_panel.visible = false
	if stats_panel.visible:
		var st := game.stats()
		var body := stats_panel.get_node_or_null("Panel/Box/Body") as Label
		if body != null:
			body.text = "%d 局　%d胜 %d负 %d平\n净收益：%s token（%s）\n历史最高：%s token%s\n下注档位：第 %d / %d 档\n\n当前情绪：%s\n上头 %.2f　忌惮 %.2f　底气 %.2f　记仇 %.2f\n\n它眼里的你：\n%s" % [
				int(st["hands"]), int(st["wins"]), int(st["losses"]), int(st["pushes"]),
				BjTokens.format(int(st["net_chips"])),
				BjTokens.format_exact(int(st["net_chips"])),
				BjTokens.format(game.best_chips()),
				_record_gap_text(),
				game.machine.stake_level() + 1,
				BjMachine.STAKE_MIN_STEPS.size(),
				str(st["mood"]), float(st["tilt"]), float(st["respect"]),
				float(st["confidence"]), float(st["grudge"]),
				BjPersona.describe(game.persona),
			]

## 战绩面板里那句"离纪录还差多少" ——
## 空着的话玩家根本不知道自己离目标有多远，"最高筹码"就只是个装饰。
func _record_gap_text() -> String:
	var best := game.best_chips()
	var now := game.machine.player_chips
	if now > best:
		return "（正在刷新纪录）"
	if now == best:
		return "（你就是纪录）"
	return "（还差 %s）" % BjTokens.format(best - now)


func _toggle_sound() -> void:
	game.settings["sound"] = not bool(game.settings.get("sound", true))
	sfx.enabled = bool(game.settings["sound"])
	sfx.play("chip")
	game.apply_settings(game.settings)


func _toggle_voice() -> void:
	game.settings["voice"] = not bool(game.settings.get("voice", false))
	if bool(game.settings["voice"]):
		_speak("要来一局吗？")
	game.apply_settings(game.settings)


func _toggle_bgm() -> void:
	game.settings["bgm"] = not bool(game.settings.get("bgm", true))
	bgm.apply(game.settings)
	game.apply_settings(game.settings)


## 开关"运行时现烤"（缺素材的台词要不要就地合成，保证一个声线）。
func _toggle_voice_online() -> void:
	game.settings["voice_online"] = not bool(game.settings.get("voice_online", true))
	voice.runtime_synth = bool(game.settings["voice_online"])
	game.apply_settings(game.settings)


## 背景图 / 程序化绿呢毯 切换（没放背景图时这个按钮不显示）。
func _toggle_background() -> void:
	game.settings["background"] = not bool(game.settings.get("background", true))
	_load_background()
	game.apply_settings(game.settings)


## 在可用的配音音色之间轮换（assets/voice/ 下有 manifest 的才算数）。
func _cycle_voice_style() -> void:
	var ids := voice.available_voices()
	if ids.is_empty():
		return
	var current: int = maxi(0, ids.find(str(game.settings.get("voice_id", voice.voice_id))))
	var next: String = ids[(current + 1) % ids.size()]
	game.settings["voice_id"] = next
	voice.set_voice(next)
	game.apply_settings(game.settings)
	if bool(game.settings.get("voice", false)):
		_speak("要来一局吗？")


func _cycle_whale_scale() -> void:
	var scale_value := int(game.settings.get("whale_scale", 3))
	scale_value = 4 if scale_value >= 4 else scale_value + 1
	game.settings["whale_scale"] = scale_value
	whale.scale_factor = scale_value
	whale.update_size()
	game.apply_settings(game.settings)
	_layout()


func _toggle_llm() -> void:
	game.settings["use_llm"] = not bool(game.settings.get("use_llm", false))
	game.apply_settings(game.settings)


func _save_settings() -> void:
	var panel := settings_panel.get_node_or_null("Panel") as Panel
	if panel != null:
		var key_edit := panel.get_node_or_null("Scroll/Box/KeyEdit") as LineEdit
		if key_edit == null:
			key_edit = panel.get_node_or_null("Box/KeyEdit") as LineEdit
		if key_edit != null:
			game.settings["api_key"] = key_edit.text.strip_edges()
		var model_edit := panel.get_node_or_null("Scroll/Box/ModelEdit") as LineEdit
		if model_edit == null:
			model_edit = panel.get_node_or_null("Box/ModelEdit") as LineEdit
		if model_edit != null and model_edit.text.strip_edges() != "":
			game.settings["model"] = model_edit.text.strip_edges()
	game.apply_settings(game.settings)
	settings_panel.visible = false
	_on_notice("设置已保存（存档位置：%s）" % BjProfile.profile_path())


func _reset_progress() -> void:
	game.reset_progress()
	settings_panel.visible = false
	_on_notice("战绩与人格已清空，筹码各补回 1 亿")


## 说话：**一个声线** —— 烤好的素材 / 运行时现烤缓存，都没有就静音。
func _speak(text: String) -> void:
	if text.strip_edges() == "" or not bool(game.settings.get("voice", false)):
		return
	if voice.speak(text):
		return
	# 只有玩家显式打开兜底时才用系统 TTS（默认关：宁可这句不响，也不换人说话）
	if voice.system_fallback:
		voice.system_speak(text)


# ---------------------------------------------------------------- 特效

func _schedule_sfx(sound_name: String, delay: float) -> void:
	if delay <= 0.0:
		sfx.play(sound_name)
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void: sfx.play(sound_name))


func _play_fx(fx: Array) -> void:
	for effect in fx:
		match str(effect):
			"screen_shake":
				_shake()
			"bust_flash":
				_pulse("_set_flash", 0.55, 0.42, 6)
			"bj_burst":
				_pulse("_set_burst", 1.0, 0.6, 6)
			"push_glow":
				_pulse("_set_glow", 0.5, 0.5, 5)
			"tokens_fly_to_player":
				_fly_tokens(true)
			"tokens_fly_to_opponent":
				_fly_tokens(false)


## 闪光类特效：亮度衰减**分步量化**，保持像素动画的颗粒感
## （这几个 fx 原本是 CSS steps()，在原版里全是死代码；这里真的画出来）。
func _pulse(method: String, peak: float, duration: float, steps: int) -> void:
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void:
		call(method, round(value * float(steps)) / float(steps))
	, peak, 0.0, duration)


func _set_flash(value: float) -> void:
	_flash = value
	queue_redraw()


func _set_burst(value: float) -> void:
	_burst = value
	queue_redraw()


func _set_glow(value: float) -> void:
	_glow = value
	queue_redraw()


## 彩蛋：整屏压暗（黑化充能）
func _set_dark(value: float) -> void:
	_dark = value
	queue_redraw()


## 彩蛋：整屏白闪（砸下来那一击）
func _set_white(value: float) -> void:
	_white = value
	queue_redraw()


# ---------------------------------------------------------------- 数字滚动 / 中央横幅

## 数字滚动时长。**0.75 秒**：比"一闪而过"慢得多，能看清在涨还是在跌。
## （原来 0.55 秒，在经济调小之后太短 —— 一局只动 1~5%，
##   滚起来跟没滚一样，用户直接说"没做出来"。）
const ROLL_TIME := 0.75
## 每个标签当前"滚到哪了"。用它当下一段的起点，中途被打断也不会跳。
var _roll_values: Dictionary = {}
var _roll_tweens: Dictionary = {}
## 每个标签上一次的**目标值**：只有目标真的变了才滚 + 飘字，
## 否则 `_refresh` 每次重入都会重播一遍动画（飘字刷屏）。
var _roll_targets: Dictionary = {}
## 点数滚动（双方各一条）+ 当前显示到几点
const POINT_ROLL_TIME := 0.45
var _point_tweens: Dictionary = {}
var _shown_player_total := 0
var _shown_opp_total := 0
## 已经播报过黑杰克的局号（同一局只报一次）
var _bj_hand_announced := -1
## 上一次刷新时的阶段（用来判断"刚轮到你"并给一声提示音）
var _last_phase := ""
## 是否已经就"付不起下一档"报过警（避免每帧都响）
var _warned_about_stake := false
## 上一次显示的下注档位（用来判断"涨档"并弹提醒）；-1 = 还没初始化
var _stake_level_shown := -1

## 把标签里的筹码数字从当前值**滚**到目标值。
##
## 之前是 `label.text = ...` 直接赋值：输 5000 万和输 100 万在视觉上没区别，
## 数字一闪就过去了。滚动把"得失"变成一段可以看见的过程 —— 尤其是大额时
## 数字一路往下掉的那半秒，比任何结算文字都更能让人心疼。
func _roll_to(label: Label, target: int, template: String) -> void:
	if label == null:
		return
	var key := label.get_instance_id()
	# `_refresh` 一局里会被调用很多次（每次 state_changed），所以必须区分
	# "目标真的变了"（要滚 + 飘字）和"同一次变化又被刷新了一遍"（什么都别做，
	# 否则动画会重播、飘字会刷屏）。
	var previous_target: int = int(_roll_targets.get(key, target))
	var target_changed := target != previous_target
	var from: int = int(_roll_values.get(key, target))
	_roll_targets[key] = target
	_roll_values[key] = target
	var old: Tween = _roll_tweens.get(key)
	if from == target:
		if old == null or not old.is_valid():
			label.text = template % BjTokens.format(target)
		return
	if old != null and old.is_valid():
		old.kill()
	var tween := create_tween()
	_roll_tweens[key] = tween
	# 滚动期间给标签染上方向色（涨绿跌红），滚完回白 ——
	# 光看数字在小额时不够醒目，颜色才是"一眼看出输赢"的那一下。
	label.modulate = BjTheme.WIN if target > from else BjTheme.DANGER
	var color_tween := create_tween()
	color_tween.tween_property(label, "modulate", Color.WHITE, ROLL_TIME + 0.35)
	tween.tween_method(func(value: float) -> void:
		var current := int(round(value))
		_roll_values[key] = current
		label.text = template % BjTokens.format(current),
		float(from), float(target), ROLL_TIME)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		_roll_values[key] = target
		label.text = template % BjTokens.format(target))
	if target_changed:
		_pop_delta(label, target - previous_target)


## 筹码变动时在标签旁边飘一个 "+X / −X"，往上浮再淡出。
##
## 这是"得失感知"的最后一块：滚动告诉你**变成多少**，
## 这个飘字告诉你**这一下赢/输了多少** —— 小额度时尤其需要它。
func _pop_delta(anchor: Label, delta: int) -> void:
	if anchor == null or delta == 0:
		return
	var gain := delta > 0
	var popup := BjTheme.label(
		"%s%s" % ["+" if gain else "−", BjTokens.format(absi(delta))], 18,
		BjTheme.WIN if gain else BjTheme.DANGER)
	popup.name = "DeltaPop"
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.position = anchor.position + Vector2(anchor.size.x + 6.0, 2.0)
	add_child(popup)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 34.0, 1.0)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.7).set_delay(0.45)
	tween.chain().tween_callback(popup.queue_free)


## 中央横幅：黑杰克、新纪录这种"这一下很关键"的瞬间。
## 从 0.8 倍弹到 1 倍 + 淡入，停一下就淡出；`MOUSE_FILTER_IGNORE` 所以不挡操作。
func show_banner(title: String, subtitle: String, color: Color, hold: float = 1.2) -> void:
	if banner_box == null:
		return
	banner_title.text = title
	banner_title.add_theme_color_override("font_color", color)
	banner_sub.text = subtitle
	banner_sub.visible = subtitle != ""
	banner_box.visible = true
	banner_box.modulate = Color(1, 1, 1, 0)
	banner_box.scale = Vector2(0.82, 0.82)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner_box, "modulate:a", 1.0, 0.20)
	_banner_tween.tween_property(banner_box, "scale", Vector2.ONE, 0.38)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.set_parallel(false)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(banner_box, "modulate:a", 0.0, 0.45)
	_banner_tween.tween_callback(func() -> void: banner_box.visible = false)


## 震屏：4 步方波（原版是 240ms steps(4)）。
func _shake() -> void:
	var offsets := [Vector2(-4, 2), Vector2(4, -2), Vector2(-2, -2), Vector2.ZERO]
	for i in range(offsets.size()):
		_schedule_shake_step(offsets[i], 0.06 * float(i))


func _schedule_shake_step(offset: Vector2, delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void: stage.position = _stage_home + offset)


## 筹码飞向赢家。
func _fly_tokens(to_player: bool) -> void:
	var colors := BjTheme.chip_colors(BjMachine.MIN_BET * 5)
	var texture := BjGlyphs.chip_texture(colors[0], colors[1])
	var from := Vector2(felt_rect.size.x / 2.0, 250.0) if to_player else Vector2(felt_rect.size.x / 2.0, 430.0)
	var target := Vector2(felt_rect.size.x / 2.0 + 300.0, 520.0) if to_player else Vector2(felt_rect.size.x / 2.0 - 300.0, 120.0)
	for i in range(5):
		var chip := TextureRect.new()
		chip.texture = texture
		chip.custom_minimum_size = Vector2(32, 32)
		chip.size = Vector2(32, 32)
		chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		chip.position = from + Vector2(float(i) * 8.0 - 16.0, 0)
		stage.add_child(chip)
		var tween := create_tween()
		tween.tween_interval(0.05 * float(i))
		tween.tween_property(chip, "position", target, 0.45).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(chip, "modulate:a", 0.0, 0.2)
		tween.tween_callback(chip.queue_free)


# ---------------------------------------------------------------- 绘制

## 背景图：把文件丢进 assets/background/ 就自动用上（file_name 见下）。
##
## 设计要求（给画图的人/模型看的）：
##   - 整张按**整个窗口**构图（1280×760），上下两条会被顶栏与玩家栏挡住，
##     所以真正露出来的是中间那条 1280×414 的横带；
##   - 中间要**空、暗、干净**（牌面和点数都压在这里），装饰都推到四周；
##   - 别放牌、别放筹码、别放人物 —— 那些游戏自己画。
const BACKGROUND_PATH := "res://assets/background/table.png"
const BACKGROUND_SCRIM := 0.22   ## 压一层很淡的暗色，保证牌面与文字压得住

var background: Texture2D = null


func _load_background() -> void:
	background = null
	if bool(game.settings.get("background", true)) and ResourceLoader.exists(BACKGROUND_PATH):
		var texture: Texture2D = load(BACKGROUND_PATH)
		if texture != null:
			background = texture
	queue_redraw()


func top_bar_height() -> float:
	return 68.0


## 有背景图：**按"铺满并居中裁切"画**（不拉伸变形），上下会被后画的不透明条挡住。
func _draw_background() -> void:
	var texture_size := background.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		_draw_felt()
		return
	var cover := maxf(size.x / texture_size.x, size.y / texture_size.y)
	var draw_size := texture_size * cover
	var offset := (size - draw_size) / 2.0
	draw_texture_rect(background, Rect2(offset, draw_size), false)
	# 上下做暗角，让视线落在中间那条横带上
	var shade := Color(0, 0, 0, 0.35)
	draw_rect(Rect2(0, 0, size.x, felt_rect.position.y + 40.0), shade)
	draw_rect(Rect2(0, felt_rect.end.y - 40.0, size.x, size.y - felt_rect.end.y + 40.0), shade)
	draw_rect(felt_rect, Color(0, 0, 0, BACKGROUND_SCRIM))
	# 呢毯上下沿的金/木色收边保留，牌桌才有"边界"
	draw_rect(Rect2(felt_rect.position.x, felt_rect.position.y, felt_rect.size.x, 3), BjTheme.FELT_LINE)
	draw_rect(Rect2(felt_rect.position.x, felt_rect.end.y - 3, felt_rect.size.x, 3), BjTheme.RAIL)


## 没有背景图：程序化绿呢毯（竖向渐变 + 每 4 像素一条暗扫描线）。
func _draw_felt() -> void:
	draw_rect(felt_rect, BjTheme.FELT_2)
	var bands := 24
	for i in range(bands):
		var t := float(i) / float(bands)
		var color := BjTheme.FELT_1.lerp(BjTheme.FELT_2, t)
		draw_rect(Rect2(felt_rect.position.x, felt_rect.position.y + felt_rect.size.y * t,
			felt_rect.size.x, felt_rect.size.y / float(bands) + 1.0), color)
	var y := felt_rect.position.y
	while y < felt_rect.end.y:
		draw_rect(Rect2(felt_rect.position.x, y, felt_rect.size.x, 1), Color(0, 0, 0, 0.06))
		y += 4.0
	draw_rect(Rect2(felt_rect.position.x, felt_rect.position.y, felt_rect.size.x, 3), BjTheme.FELT_LINE)
	draw_rect(Rect2(felt_rect.position.x, felt_rect.end.y - 3, felt_rect.size.x, 3), BjTheme.RAIL)


func _draw() -> void:
	if background != null:
		_draw_background()
	else:
		_draw_felt()

	# 顶栏 / 玩家行 / 动作栏（不透明，盖住背景的上下两条）
	draw_rect(Rect2(0, 0, size.x, top_bar_height()), BjTheme.INK)
	draw_rect(Rect2(0, top_bar_height() - 3.0, size.x, 3), BjTheme.ACCENT)
	draw_rect(player_rect, BjTheme.INK)
	draw_rect(Rect2(player_rect.position.x, player_rect.position.y, size.x, 3), BjTheme.ACCENT)
	draw_rect(action_rect, BjTheme.PANEL)
	draw_rect(Rect2(action_rect.position.x, action_rect.position.y, size.x, 3), BjTheme.PANEL_LINE)

	# fx 叠加
	if _flash > 0.0:
		draw_rect(felt_rect, Color(BjTheme.DANGER.r, BjTheme.DANGER.g, BjTheme.DANGER.b, _flash))
	if _glow > 0.0:
		draw_rect(felt_rect, Color(1, 1, 1, _glow * 0.25))
	if _burst > 0.0:
		var grow := 26.0 * _burst
		var rect := Rect2(60, felt_rect.position.y + 120, felt_rect.size.x - 120, felt_rect.size.y - 160)
		draw_rect(rect.grow(grow), Color(BjTheme.ACCENT.r, BjTheme.ACCENT.g, BjTheme.ACCENT.b, _burst * 0.8), false, 4.0)
	# 彩蛋：黑化时整个世界压暗（盖全屏，不只是牌桌）
	if _dark > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.0, 0.07, clampf(_dark, 0.0, 1.0) * 0.88))
	# 彩蛋：砸下来的那一击，整屏白闪
	if _white > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, clampf(_white, 0.0, 1.0)))
