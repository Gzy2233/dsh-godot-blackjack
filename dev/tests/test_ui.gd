@tool
class_name BjTestUi
extends McpTestSuite

## 牌桌视图的接线自检。
##
## 为什么需要这一套：场景脚本（BjTableView）**单测抓不到解析错误、也抓不到"信号漏接"**
## ——它只在真跑游戏时才暴露。而我就在一次改动里误删过
## `game.bankrupt.connect(_on_bankrupt)`，结果**玩家输光后既不出 CG 也不弹选择页**
## （用户报的"什么都不触发"）。这条测试把那类事故钉死在这里。


func suite_name() -> String:
	return "ui"


## 造一个真的牌桌视图（会跑完整的 _ready：建 UI、连信号、读存档）。
func _view() -> BjTableView:
	var view := BjTableView.new()
	Engine.get_main_loop().root.add_child(view)
	track(view)
	return view


func test_view_wires_every_game_signal() -> void:
	# 少接任何一个，对应的表现都会"静默失效"：
	# 少了 bankrupt → 输光不出 CG；少了 settled → 不结算；少了 action_events → 不发音效…
	var view := _view()
	assert_true(view.game != null, "视图里应该有一个 game 节点")
	for signal_name in ["state_changed", "hand_dealt", "action_events", "cues_changed",
			"thinking_changed", "settled", "notice", "bankrupt", "opponent_bankrupt",
			"plea_changed", "loan_granted"]:
		var links := view.game.get_signal_connection_list(signal_name)
		assert_gt(links.size(), 0, "game.%s 没有接到视图上（表现会静默失效）" % signal_name)


func test_whale_click_is_wired() -> void:
	var view := _view()
	assert_gt(view.whale.poked.get_connections().size(), 0, "点鲸鱼娘的彩蛋没接上")


func test_modal_panels_cover_the_whole_screen() -> void:
	# 遮罩如果是 0×0，鼠标会穿透到背后的按钮上（用户报过）
	var view := _view()
	# 先把锚点归零再改尺寸，否则引擎会警告"锚点会覆盖 size"（视图自己也是这么做的）
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1280, 760)
	view._layout()
	for overlay in [view.settings_panel, view.stats_panel, view.bankrupt_panel, view.cg_layer]:
		var item := overlay as Control
		assert_eq(item.size, Vector2(1280, 760),
			"%s 应该铺满整屏，否则挡不住点击" % item.name)


func test_rules_text_actually_renders() -> void:
	# `RULES_TEXT % [...]` 的参数顺序错了不会报解析错误，
	# 只在运行时抛 "String formatting error"，然后整段规则页变成空字符串。
	# 这条断言把它变成测试失败。
	var view := _view()
	var text := view.rules_text()
	assert_gt(text.length(), 200, "规则正文没渲染出来（% 参数顺序大概错了）")
	assert_false(text.contains("%s"), "正文里还留着没替换的占位符：%s" % text.substr(0, 60))
	assert_false(text.contains("%d"), "正文里还留着没替换的占位符")
	# 三条魔改倍率都要写进去
	for needle in ["抓它爆牌", "五小龙", "六小龙"]:
		assert_true(text.contains(needle), "规则页缺了「%s」" % needle)


func test_bankrupt_panel_never_shows_without_a_page() -> void:
	# "遮罩亮着却一页都没有" = 整张桌子被一层点不到东西的黑幕锁死
	var view := _view()
	view._switch_bankrupt_page(null)
	assert_false(view.bankrupt_panel.visible, "关掉所有页时遮罩也该收起来")
	for page in [view.bankrupt_page, view.plea_page, view.win_page, view.dead_page]:
		view._switch_bankrupt_page(page)
		assert_true(view.bankrupt_panel.visible, "有页显示时遮罩必须在")
		var visible_pages := 0
		for other in [view.bankrupt_page, view.plea_page, view.win_page, view.dead_page]:
			if other.visible:
				visible_pages += 1
		assert_eq(visible_pages, 1, "同一时刻只能有一页可见")


## 顶栏元素**不许互相压住**。
##
## 这条是被用户逼出来的：下注挤进局号那一行时压住了"你 X token"，
## 「规则」按钮又被右上角战绩框盖住。数字最长的情况（10 亿级、三位数局号）
## 最容易露馅，所以这里直接按最长文本算一遍矩形，两两查重叠。
func test_top_bar_elements_do_not_overlap() -> void:
	var view := _view()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1280, 760)
	view._layout()
	# 最长情形：第 999 局 + 三个 10 亿级数字
	var machine := view.game.machine
	machine.hand_no = 998
	machine.player_chips = 1_000_000_000
	machine.opponent_chips = 1_000_000_000
	view._refresh()

	var items := {
		"局号": view.hand_label,
		"下注": view.stake_label,
		"玩家筹码": view.player_pill,
		"对手筹码": view.opp_pill,
		"战绩框": view.stats_box,
		"规则按钮": view.rules_button,
		"战绩按钮": view.menu_button,
		"设置按钮": view.settings_button,
	}
	var names: Array = items.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a := _rect_of(items[names[i]])
			var b := _rect_of(items[names[j]])
			var hit := a.position.x < b.end.x and b.position.x < a.end.x \
				and a.position.y < b.end.y and b.position.y < a.end.y
			assert_false(hit, "顶栏「%s」和「%s」叠在一起了：%s / %s" % [
				names[i], names[j], str(a), str(b)])
	# 按钮必须整排落在窗口内
	assert_true(view.settings_button.position.x + view.settings_button.size.x <= 1280.0,
		"最右边的按钮超出窗口")
	# **战绩框的内容不许显示到框外面**。
	# Godot 不允许 Control 的 size 小于内容最小尺寸 —— 内容比框宽时它不会自动裁剪，
	# 而是整个撑到框外（"DeepSeek 在线"显示在框外就是这么来的）。
	# 兜底是 `stats_box.clip_contents = true`：打开之后即使内容更宽，
	# 也只是被框裁掉，不会画到框外。所以这里断言的是"装得下 **或** 有裁剪"。
	var stats_box := view.stats_box
	var rows := stats_box.get_node_or_null("Rows") as Control
	if rows != null and not stats_box.clip_contents:
		var box_right := stats_box.position.x + stats_box.size.x
		for i in range(rows.get_child_count()):
			var row := rows.get_child(i) as Control
			if row == null:
				continue
			for j in range(row.get_child_count()):
				var cell := row.get_child(j) as Label
				if cell == null or not cell.visible:
					continue
				var right := stats_box.position.x + rows.position.x + row.position.x \
					+ cell.position.x + cell.size.x
				assert_true(right <= box_right,
					"战绩框里的「%s」右边界 %d 超出框 %d —— 会显示在框外面" % [
						cell.text, int(right), int(box_right)])
	# 反过来也要防止"靠裁剪遮丑"：框本身得留够宽度，不然文字会被裁得看不清
	assert_true(stats_box.size.x >= 370.0,
		"战绩框太窄（%d）—— 最坏情况下内容会被裁掉而不是正常显示" % int(stats_box.size.x))


## 点数标签**永远不许变空**。
##
## 用户的原话："他不是先消失后再出现，是滚动向上的"。
## 早期的实现是"牌还在飞的时候先清空、落位后再显示" —— 看起来就是数字先没了再冒出来。
## 这条断言把它钉死：牌还在动的时候，标签必须留着上一个值（或至少不是空串）。
func test_point_labels_never_go_blank_mid_hand() -> void:
	var view := _view()
	var machine := view.game.machine
	machine.player_chips = 20_000_000
	machine.opponent_chips = 20_000_000
	machine.start_hand(machine.min_stake())
	view._refresh()

	var texts: Array = []
	# 你要一张牌（牌会飞 0.26 秒，期间点数不该被清空）
	machine.player_action("HIT")
	view._refresh_hands(false)
	view._refresh()
	texts.append(view.player_total.text)
	texts.append(view.opp_total.text)
	view._refresh_player_total()
	view._refresh_opp_total()
	texts.append(view.player_total.text)
	texts.append(view.opp_total.text)
	for text in texts:
		assert_true(str(text).strip_edges() != "",
			"点数标签变空了（就是「先消失后再出现」）—— 应该留着上一个值")
		assert_true(str(text).contains("点") or str(text) == "—",
			"点数标签的文字不对劲：%s" % str(text))


func _rect_of(node: Control) -> Rect2:
	return Rect2(node.position, node.size)
