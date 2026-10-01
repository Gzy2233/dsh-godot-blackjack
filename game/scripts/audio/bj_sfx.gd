class_name BjSfx
extends Node

## 音效：**全部由代码合成 PCM**，项目里一个音频文件都没有。
##
## 移植自 dsh-deepseek-blackjack/src/client/sound.js（那边是 WebAudio 合成）。
## 13 个音色、频点、时长、增益**逐一照搬**，所以听感与原版一致。
##
## 合成方式（与原版同一套）：
##   tone(freq, dur, type, gain, delay, sweep_to)  —— 振荡器 + 6ms 起音 + 指数衰减
##   noise(dur, gain, filter_freq, q, delay)       —— 白噪声 + 带通 + 线性衰减
## 6ms 的极短起音是"干脆的像素味"的来源，别改成慢起音。

const SR := 22050
## 主音量（原版 master gain 0.35）。
const MASTER := 0.35
const VOICES := 10

var enabled := true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
## 最后真正播出去的音效名（调试 / 单测用：验证"音效有没有被延后"）
var last_played := ""


func _ready() -> void:
	_build_streams()
	for i in range(VOICES):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)


func names() -> Array:
	_ensure_streams()
	return _streams.keys()


## 取某个音效的波形（单测用，也可以拿它把音效烘成 .wav）。
func stream_for(sound_name: String) -> AudioStreamWAV:
	_ensure_streams()
	return _streams.get(sound_name, null)


## 懒加载：不在场景树里也能用（单测直接 new 出来就能验证波形）。
func _ensure_streams() -> void:
	if _streams.is_empty():
		_build_streams()


## 播一个音效。未知名字返回 false（**永远不抛异常**：一个音效不该能打断牌局）。
func play(sound_name: String) -> bool:
	_ensure_streams()
	if not enabled or not _streams.has(sound_name):
		return false
	if _players.is_empty():
		return false
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sound_name]
	player.volume_db = linear_to_db(MASTER)
	player.play()
	last_played = sound_name
	return true


func _build_streams() -> void:
	# 音色表：与原版 sound.js 的 SFX 表一一对应
	_streams["deal"] = _noise(0.055, 0.5, 2600.0, 0.8)
	_streams["flip"] = _noise(0.04, 0.45, 3400.0, 1.2)
	_streams["chip"] = _mix([
		_tone_spec(1180.0, 0.045, "square", 0.22),
		_tone_spec(1560.0, 0.05, "square", 0.16, 0.035),
	])
	_streams["hit"] = _mix([
		_noise_spec(0.05, 0.45, 2800.0, 1.0),
		_tone_spec(620.0, 0.05, "triangle", 0.18),
	])
	_streams["stand"] = _tone(420.0, 0.07, "triangle", 0.2)
	_streams["double"] = _mix([
		_tone_spec(560.0, 0.07, "square", 0.2),
		_tone_spec(840.0, 0.09, "square", 0.2, 0.07),
		_noise_spec(0.06, 0.35, 2000.0, 1.0, 0.02),
	])
	_streams["bust"] = _tone(380.0, 0.34, "sawtooth", 0.26, 0.0, 70.0)
	_streams["win"] = _mix([
		_tone_spec(523.0, 0.09, "square", 0.22),
		_tone_spec(659.0, 0.09, "square", 0.22, 0.09),
		_tone_spec(784.0, 0.16, "square", 0.24, 0.18),
	])
	_streams["lose"] = _mix([
		_tone_spec(392.0, 0.12, "triangle", 0.22),
		_tone_spec(262.0, 0.22, "triangle", 0.22, 0.12),
	])
	_streams["push"] = _tone(494.0, 0.14, "triangle", 0.18)
	_streams["blackjack"] = _mix([
		_tone_spec(523.0, 0.1, "square", 0.22),
		_tone_spec(659.0, 0.1, "square", 0.22, 0.075),
		_tone_spec(784.0, 0.1, "square", 0.22, 0.15),
		_tone_spec(1047.0, 0.1, "square", 0.22, 0.225),
	])
	_streams["talk"] = _tone(900.0, 0.03, "sine", 0.12)
	_streams["click"] = _tone(700.0, 0.025, "square", 0.12)

	# ---------------------------------------------------------------- 情境音效
	# 用户要求"各种情况尽量都要有音效"：以前下注额上调、新纪录、全押、
	# 轮到你了、好感涨跌、借钱到账……全都在复用 chip / click，
	# 听感上等于没有反馈。这里给每种情境一条自己的音色。
	#
	# 全部是**代码合成的**（和上面 13 条一样），不引入任何音频文件。

	# 下注额上调：上行三音琶音，明亮、有"涨"的方向感
	_streams["level_up"] = _mix([
		_tone_spec(660.0, 0.10, "square", 0.20),
		_tone_spec(880.0, 0.10, "square", 0.20, 0.09),
		_tone_spec(1320.0, 0.24, "square", 0.24, 0.18),
	])
	# 新纪录：比升级更华丽的四音号角 + 一点亮片
	_streams["record"] = _mix([
		_tone_spec(523.0, 0.12, "square", 0.22),
		_tone_spec(659.0, 0.12, "square", 0.22, 0.10),
		_tone_spec(784.0, 0.12, "square", 0.22, 0.20),
		_tone_spec(1047.0, 0.40, "square", 0.26, 0.30),
		_noise_spec(0.30, 0.10, 5200.0, 1.4, 0.30),
	])
	# 一把梭：低频冲击 + 上行扫频，像把筹码全推出去
	_streams["all_in"] = _mix([
		_noise_spec(0.38, 0.45, 900.0, 0.6),
		_tone_spec(300.0, 0.34, "square", 0.24, 0.0, 1200.0),
		_tone_spec(110.0, 0.50, "sine", 0.40, 0.06, 60.0),
	])
	# 轮到你了：清脆的两音提示（先手轮换之后尤其需要，不然不知道轮到自己了）
	_streams["turn"] = _mix([
		_tone_spec(1046.0, 0.09, "sine", 0.28),
		_tone_spec(1568.0, 0.15, "sine", 0.20, 0.08),
	])
	# 好感涨：往上两个音
	_streams["favor_up"] = _mix([
		_tone_spec(700.0, 0.08, "sine", 0.26),
		_tone_spec(1050.0, 0.13, "sine", 0.20, 0.07),
	])
	# 好感跌：往下两个音（和 favor_up 明显是一对反义）
	_streams["favor_down"] = _mix([
		_tone_spec(600.0, 0.09, "sine", 0.26),
		_tone_spec(380.0, 0.17, "sine", 0.22, 0.08),
	])
	# 钱到手：三枚金币的叮当（借钱到账 / 她回去搬钱）
	_streams["coins"] = _mix([
		_tone_spec(1568.0, 0.05, "square", 0.16),
		_tone_spec(2093.0, 0.05, "square", 0.14, 0.06),
		_tone_spec(1760.0, 0.07, "square", 0.14, 0.12),
		_noise_spec(0.05, 0.12, 6000.0, 1.5),
	])
	# 警告：两下低频短促提示（"下一档你就付不起了"）
	_streams["warn"] = _mix([
		_tone_spec(220.0, 0.15, "square", 0.28),
		_tone_spec(220.0, 0.22, "square", 0.24, 0.22),
	])
	# 面板开：短促上扬的 whoosh
	_streams["panel_open"] = _mix([
		_noise_spec(0.16, 0.26, 1400.0, 1.0),
		_tone_spec(500.0, 0.16, "sine", 0.14, 0.0, 1100.0),
	])
	# 面板关：同一族的下降版
	_streams["panel_close"] = _mix([
		_noise_spec(0.14, 0.22, 1000.0, 1.0),
		_tone_spec(900.0, 0.14, "sine", 0.12, 0.0, 420.0),
	])
	# CG 浮现：长一点的戏剧性 whoosh（压在主题音效下面当底）
	_streams["cg_open"] = _mix([
		_noise_spec(0.55, 0.26, 700.0, 0.7),
		_tone_spec(70.0, 0.60, "sine", 0.30, 0.0, 180.0),
	])
	# 五小龙 / 六小龙：比黑杰克更长更亮的号角（这是这套魔改里最爽的一下）
	_streams["charlie"] = _mix([
		_tone_spec(659.0, 0.10, "square", 0.20),
		_tone_spec(784.0, 0.10, "square", 0.20, 0.085),
		_tone_spec(988.0, 0.10, "square", 0.22, 0.17),
		_tone_spec(1319.0, 0.14, "square", 0.24, 0.255),
		_tone_spec(1568.0, 0.44, "square", 0.26, 0.40),
		_noise_spec(0.22, 0.10, 6200.0, 1.6, 0.40),
	])
	# 抓它爆牌：短促得意的两音（比黑杰克轻，比普通赢重）
	_streams["bust_bonus"] = _mix([
		_tone_spec(880.0, 0.08, "square", 0.20),
		_tone_spec(1175.0, 0.16, "square", 0.22, 0.07),
	])
	# 彩蛋：黑化充能的低频轰鸣（越升越高、越响，然后接一击）
	_streams["charge"] = _mix([
		_tone_spec(58.0, 1.15, "sawtooth", 0.30, 0.0, 150.0),
		_noise_spec(1.15, 0.16, 180.0, 0.6),
	])
	# 彩蛋：砸下来那一击（低频冲击 + 宽噪声 + 尾巴）
	_streams["impact"] = _mix([
		_tone_spec(120.0, 0.55, "square", 0.55, 0.0, 32.0),
		_tone_spec(66.0, 0.75, "sine", 0.45, 0.0, 26.0),
		_noise_spec(0.34, 0.65, 380.0, 0.5),
		_noise_spec(0.55, 0.25, 120.0, 0.9, 0.10),
	])


func _tone_spec(freq: float, dur: float, type: String, gain: float,
		delay: float = 0.0, sweep_to: float = 0.0) -> Dictionary:
	return {"kind": "tone", "freq": freq, "dur": dur, "type": type,
		"gain": gain, "delay": delay, "sweep_to": sweep_to}


func _noise_spec(dur: float, gain: float, filter_freq: float, q: float,
		delay: float = 0.0) -> Dictionary:
	return {"kind": "noise", "dur": dur, "gain": gain,
		"filter_freq": filter_freq, "q": q, "delay": delay}


func _tone(freq: float, dur: float, type: String, gain: float,
		delay: float = 0.0, sweep_to: float = 0.0) -> AudioStreamWAV:
	return _mix([_tone_spec(freq, dur, type, gain, delay, sweep_to)])


func _noise(dur: float, gain: float, filter_freq: float, q: float) -> AudioStreamWAV:
	return _mix([_noise_spec(dur, gain, filter_freq, q)])


## 把若干音色叠到一条缓冲里，再转成 AudioStreamWAV。
func _mix(specs: Array) -> AudioStreamWAV:
	var total := 0.0
	for spec in specs:
		total = max(total, float(spec["delay"]) + float(spec["dur"]))
	var count := int(ceil(total * SR)) + 8
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	for spec in specs:
		if spec["kind"] == "tone":
			_render_tone(buffer, spec)
		else:
			_render_noise(buffer, spec)
	return _encode(buffer)


## 小数部分（GDScript 没有 frac()）。
static func _frac(value: float) -> float:
	return value - floor(value)


## 振荡器 + 包络。sweep_to 非 0 时频率指数滑向它（爆牌的下滑音就靠这个）。
func _render_tone(buffer: PackedFloat32Array, spec: Dictionary) -> void:
	var freq: float = spec["freq"]
	var dur: float = spec["dur"]
	var gain: float = spec["gain"]
	var delay: float = spec["delay"]
	var sweep_to: float = spec["sweep_to"]
	var wave: String = spec["type"]
	var start := int(delay * SR)
	var samples := int(dur * SR)
	var phase := 0.0
	for i in range(samples):
		var index := start + i
		if index >= buffer.size():
			break
		var t := float(i) / float(SR)
		var ratio := t / dur
		var current := freq
		if sweep_to > 0.0:
			# 指数扫频（WebAudio 的 exponentialRamp 也是指数）
			current = freq * pow(sweep_to / freq, ratio)
		phase += TAU * current / float(SR)
		var value := 0.0
		match wave:
			"square":
				value = 1.0 if sin(phase) >= 0.0 else -1.0
			"triangle":
				value = 4.0 * absf(_frac(phase / TAU) - 0.5) - 1.0
			"sawtooth":
				value = 2.0 * _frac(phase / TAU) - 1.0
			_:
				value = sin(phase)
		buffer[index] += value * _envelope(t, dur, gain)


## 白噪声 + 带通。线性衰减 = "刷"的一下。
func _render_noise(buffer: PackedFloat32Array, spec: Dictionary) -> void:
	var dur: float = spec["dur"]
	var gain: float = spec["gain"]
	var delay: float = spec["delay"]
	var filter_freq: float = spec["filter_freq"]
	var q: float = spec["q"]
	var start := int(delay * SR)
	var samples := int(dur * SR)
	# 状态变量滤波器（带通输出）
	var f := 2.0 * sin(PI * minf(float(filter_freq), float(SR) * 0.45) / float(SR))
	var damp: float = 1.0 / maxf(float(q), 0.05)
	var low := 0.0
	var band := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	for i in range(samples):
		var index := start + i
		if index >= buffer.size():
			break
		var noise := rng.randf_range(-1.0, 1.0)
		var high: float = noise - low - damp * band
		band += f * high
		low += f * band
		var t := float(i) / float(SR)
		buffer[index] += band * _envelope(t, dur, gain) * (1.0 - t / dur)


## 6ms 起音 + 指数衰减到千分之一。
func _envelope(t: float, dur: float, gain: float) -> float:
	var env := exp(-9.21 * (t / max(dur, 0.0001)))
	var attack := 0.006
	if t < attack:
		env *= t / attack
	return env * gain


func _encode(buffer: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buffer.size() * 2)
	for i in range(buffer.size()):
		var value := clampf(buffer[i] * 0.85, -1.0, 1.0)
		var sample := int(value * 32767.0)
		bytes.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.set_format(AudioStreamWAV.FORMAT_16_BITS)
	stream.set_mix_rate(SR)
	stream.set_stereo(false)
	stream.set_data(bytes)
	return stream
