class_name BjProfile
extends RefCounted

## 战绩 / 人格 / 设置 的持久化。
##
## 移植自 dsh-deepseek-blackjack/src/host/memory.js，落点从
## `~/.dsh/blackjack/profile.json` 改成 Godot 的 `user://blackjack/`。
##
## 两条硬规则（原版刻意做的，别省）：
##   1. **原子写**：先写临时文件再改名。写一半崩掉不会损坏档案。
##   2. **存档失败绝不打断牌局**：记忆丢了比打断你打牌好。

const DIR := "user://blackjack"
const PROFILE_FILE := "user://blackjack/profile.json"
const SETTINGS_FILE := "user://blackjack/settings.json"
const VERSION := 3

## v1 存档的筹码是"几百"的量级，低于这个 floor 就判定为需要迁移。
## 跟着当前第一档最小注走，调经济时不用改这里。
const MIGRATION_CHIP_FLOOR := BjMachine.MIN_BET


static func default_profile() -> Dictionary:
	return {
		"version": VERSION,
		"player_chips": BjMachine.STARTING_CHIPS,
		"opponent_chips": BjMachine.STARTING_CHIPS,
		"hand_no": 0,
		"persona": {},
		# 欠鲸鱼娘的债（求情借来的钱）。赢的钱一半先还它，还完为止。
		"debt": 0,
		# 借过几次钱：每次借钱都会让下次求情的起点更低（越借越难借）
		"loans_taken": 0,
		# **历史最高筹码**。这是长期目标：涨注迟早把你赶下桌，
		# 所以"我这辈子最多拿到过多少"才是跨局、跨重开都值得追的数字。
		# 因此 reset_progress()（重开/清档）**不会**清掉它。
		"best_chips": BjMachine.STARTING_CHIPS,
		"totals": {
			"hands": 0, "player_wins": 0, "opponent_wins": 0,
			"pushes": 0, "player_net": 0,
		},
		"updated_at": 0,
	}


static func default_settings() -> Dictionary:
	return {
		"sound": true,
		"voice": false,
		"voice_id": "xiaoyi",
		# 运行时现烤缺失台词（需要本机有 python + edge-tts）；关掉就只有烤好的那批
		"voice_online": true,
		# 缺配音时是否回落到 Windows 系统 TTS。**默认关** —— 那正是"两种声线"的来源
		"voice_fallback": false,
		"python_path": "",
		"bgm": true,
		"bgm_volume": 0.45,
		"background": true,
		"whale_scale": 3,
		# —— 下面四项留空/关闭时游戏走本地大脑，填了才连真模型 ——
		"use_llm": false,
		"api_key": "",
		"model": "deepseek-chat",
		"endpoint": "https://api.deepseek.com/chat/completions",
		# 规则说明看过没有（第一次进游戏自动弹一次）
		"seen_rules": false,
	}


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


## 原子写：临时文件 → rename。返回是否成功。
static func _write_atomic(path: String, text: String) -> bool:
	_ensure_dir()
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("存档打不开临时文件：%s" % path)
		return false
	file.store_string(text)
	file.close()
	var error := DirAccess.rename_absolute(tmp, path)
	if error != OK:
		push_warning("存档改名失败（%d）：%s" % [error, path])
		return false
	return true


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


## 读档案。任何失败都回落到默认值 —— 旧存档绝不能把游戏卡在启动时。
static func load_profile() -> Dictionary:
	var parsed := _read_json(PROFILE_FILE)
	var profile := default_profile()
	if parsed.is_empty():
		return profile
	for key in parsed.keys():
		profile[key] = parsed[key]
	var totals: Dictionary = profile["totals"]
	var defaults: Dictionary = default_profile()["totals"]
	for key in defaults.keys():
		if not totals.has(key):
			totals[key] = defaults[key]
	profile["totals"] = totals

	# 旧存档迁移：**经济重定标**。
	#
	#   v1 → v2：v1 的筹码是"几百"的量级，不迁移连一局都开不了。
	#   v2 → v3：整体调小经济（开局 1 亿 → 2000 万，第一档最小注 100 万 → 20 万）。
	#            旧档的筹码在新经济里是天文数字（10 亿 = 500 局本金），
	#            所以筹码、局号、最高纪录一起归零重新起跑。
	#
	# 迁移**只重置"钱"和"钱的记忆"，不动胜负场次与人格倾向** ——
	# 它记得你怎么打，但不记得你有多少钱。
	# （净收益/净筹码都是旧尺度，不重置的话战绩面板会显示"净 +1500 万"
	#   这种在新经济里不可能出现的数字，人格的心情加成也会被旧数字顶满。）
	if int(profile.get("version", 1)) < VERSION:
		var player_chips := int(profile.get("player_chips", 0))
		var opponent_chips := int(profile.get("opponent_chips", 0))
		var tiny_save := player_chips < MIGRATION_CHIP_FLOOR \
			or opponent_chips < MIGRATION_CHIP_FLOOR
		var old_economy := int(profile.get("version", 1)) < 3
		if tiny_save or old_economy:
			profile["player_chips"] = BjMachine.STARTING_CHIPS
			profile["opponent_chips"] = BjMachine.STARTING_CHIPS
			profile["hand_no"] = 0
			profile["best_chips"] = BjMachine.STARTING_CHIPS
		if old_economy:
			# 复用上面已经声明过的 totals，别再来一次 var（重复声明 = 解析错误，
			# 会把 BjProfile 连带整条依赖链全部打挂）
			totals["player_net"] = 0
			profile["totals"] = totals
			var persona: Dictionary = profile.get("persona", {})
			persona["net_chips"] = 0
			profile["persona"] = persona
		profile["migrated_from"] = int(profile.get("version", 1))
		profile["version"] = VERSION
	return profile


static func save_profile(profile: Dictionary) -> bool:
	var next := profile.duplicate(true)
	next["updated_at"] = int(Time.get_unix_time_from_system())
	return _write_atomic(PROFILE_FILE, JSON.stringify(next, "  "))


static func load_settings() -> Dictionary:
	var parsed := _read_json(SETTINGS_FILE)
	var settings := default_settings()
	for key in parsed.keys():
		settings[key] = parsed[key]
	return settings


static func save_settings(settings: Dictionary) -> bool:
	return _write_atomic(SETTINGS_FILE, JSON.stringify(settings, "  "))


static func profile_path() -> String:
	return ProjectSettings.globalize_path(PROFILE_FILE)
