class_name BjVoice
extends Node

## 鲸鱼娘的配音。**一个声线**，没有第二种。
##
## 三级查找，逐级降级：
##   1. **烤好的素材** `assets/voice/<音色>/<hash>.mp3`
##      —— 固定台词（183 条）用 `tools/bake_voice.py` 一次烤好，永远命中；
##   2. **运行时合成缓存** `user://voice_cache/<hash>.mp3`
##      —— 接了真模型之后它现编的句子是无限的，烤不完。第一次说某句话时
##      后台拉 `tools/tts_one.py`（同一个神经音色）现烤一份存下来，
##      以后同一句直接命中。**这就是"两种声线"的根治办法**：
##      以前没素材的句子会掉回 Windows 自带的 SAPI（机器人声），现在不会了；
##   3. 实在合成不出来（没装 edge-tts / 没网）→ **静音**。
##      不再回落到系统 TTS：宁可这句不响，也不要突然换一个人说话。
##      （想要旧行为可以在设置里打开 `tts_fallback`。）
##
## 哈希必须和 tools/*.py 一致：sha256(utf-8 原文) 的十六进制前 16 位。

const VOICE_ROOT := "res://assets/voice/"
const MANIFEST_NAME := "manifest.json"
const CACHE_DIR := "user://voice_cache/"
const TTS_SCRIPT := "res://tools/tts_one.py"

## 合成超时（毫秒）：超过就放弃这一句，别让声音迟到太久
const SYNTH_TIMEOUT_MS := 6000

## 系统 TTS 兜底（默认关：宁可静音也不换声线）
const TTS_PREFERRED := ["xiaoxiao", "xiaoyi", "huihui", "yaoyao", "kangkang", "chinese", "zh"]
const TTS_PITCH := 1.12
const TTS_RATE := 1.0
const TTS_VOLUME := 85

const VOICE_LABELS := {
	"xiaoyi": "小鱼（活泼）",
	"xiaoxiao": "晓晓（温柔）",
	"xiaobei": "小北（东北腔）",
}

var voice_id := "xiaoyi"
var enabled := false
## 没配音时是否回落到系统 TTS（默认否 —— 那正是"两种声线"的来源）
var system_fallback := false
## 是否允许运行时现烤（需要本机有 python + edge-tts）
var runtime_synth := true
## python 解释器（空 = 自动找）
var python_path := ""

var _player: AudioStreamPlayer
var _cache := {}
var _available: Array[String] = []
var _pending := {}          # hash -> {path, started, text}
var _resolved_python := ""  # 探测到的解释器（空 = 还没找到 / 找不到）
var _python_checked := false
var _jobs_dir := "user://tts_jobs/"
var _job_seq := 0
var _tts_voice := ""
var _tts_checked := false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -2.0
	add_child(_player)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(_jobs_dir)
	_scan_voices()
	set_process(true)


## 扫描 assets/voice/ 下有哪些音色可用（有 manifest.json 才算数）。
func _scan_voices() -> void:
	_available.clear()
	var dir := DirAccess.open(VOICE_ROOT)
	if dir == null:
		return
	for folder in dir.get_directories():
		if FileAccess.file_exists("%s%s/%s" % [VOICE_ROOT, folder, MANIFEST_NAME]):
			_available.append(str(folder))
	_available.sort()
	if not _available.is_empty() and not _available.has(voice_id):
		voice_id = _available[0]


func available_voices() -> Array[String]:
	return _available.duplicate()


func has_clips() -> bool:
	return not _available.is_empty()


func label_for(id: String) -> String:
	if VOICE_LABELS.has(id):
		return str(VOICE_LABELS[id])
	return id


## 换音色（会清缓存）。
func set_voice(id: String) -> void:
	if id == voice_id:
		return
	voice_id = id
	_cache.clear()


## 素材里（烤好的 + 已缓存的）有没有这一句。
func has_clip(text: String) -> bool:
	if text.strip_edges() == "":
		return false
	return FileAccess.file_exists(_clip_path(text)) or _baked_exists(text)


func _baked_exists(text: String) -> bool:
	if _available.is_empty():
		return false
	return ResourceLoader.exists("%s%s/%s.mp3" % [VOICE_ROOT, voice_id, _hash(text)])


func _clip_path(text: String) -> String:
	return "%s%s.mp3" % [CACHE_DIR, _hash(text)]


## 播放这一句。返回 false 表示"现在还没有声音"（调用方可以决定要不要兜底）。
##
## 没有素材时会**顺手起一个后台合成任务**，下次同一句就直接能播了。
func speak(text: String) -> bool:
	if text.strip_edges() == "":
		return false
	# 1) 烤好的素材
	if _baked_exists(text):
		var path := "%s%s/%s.mp3" % [VOICE_ROOT, voice_id, _hash(text)]
		if not _cache.has(path):
			_cache[path] = load(path)
		var baked = _cache[path]
		if baked != null:
			_play(baked)
			return true
	# 2) 运行时缓存
	var cached_path := _clip_path(text)
	var abs_path := ProjectSettings.globalize_path(cached_path)
	if FileAccess.file_exists(cached_path):
		if not _cache.has(abs_path):
			var stream := _load_mp3(abs_path)
			_cache[abs_path] = stream
		var stream_cached = _cache[abs_path]
		if stream_cached != null:
			_play(stream_cached)
			return true
	# 3) 都没有 → 起个后台任务现烤（不阻塞这一帧）
	_request_synth(text)
	return false


func _play(stream: AudioStream) -> void:
	_player.stream = stream
	_player.play()


## 用 AudioStreamMP3 直接吃磁盘上的 mp3（不走资源系统，所以 user:// 里新生成的文件能立刻播）。
func _load_mp3(absolute_path: String) -> AudioStream:
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	if data.size() < 512:
		return null
	var stream := AudioStreamMP3.new()
	stream.data = data
	return stream


# ---------------------------------------------------------------- 运行时现烤

## 起一个后台合成任务（同一句只起一次）。
func _request_synth(text: String) -> void:
	if not runtime_synth:
		return
	var key := _hash(text)
	if _pending.has(key):
		return
	var python := _resolve_python()
	if python == "":
		return
	# 台词写进文件再传路径：台词里有引号/换行/♡，走命令行迟早翻车
	_job_seq += 1
	var job_path := "%stts_job_%d.txt" % [_jobs_dir, _job_seq]
	var file := FileAccess.open(job_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()
	var script_path := ProjectSettings.globalize_path(TTS_SCRIPT)
	var cache_abs := ProjectSettings.globalize_path(CACHE_DIR)
	var pid := OS.create_process(python, [script_path, ProjectSettings.globalize_path(job_path),
		cache_abs, voice_id])
	if pid <= 0:
		_resolved_python = ""
		_python_checked = false
		return
	_pending[key] = {
		"path": _clip_path(text),
		"started": Time.get_ticks_msec(),
		"text": text,
		"job": job_path,
	}


## 每帧看看后台烤好了没；烤好了就补播（超过超时时间就放弃这一句）。
func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for key in _pending.keys():
		var job: Dictionary = _pending[key]
		if FileAccess.file_exists(str(job["path"])):
			var stream := _load_mp3(ProjectSettings.globalize_path(str(job["path"])))
			_pending.erase(key)
			_drop_job_file(str(job.get("job", "")))
			if stream != null:
				_play(stream)
			continue
		if now - int(job["started"]) > SYNTH_TIMEOUT_MS:
			_pending.erase(key)
			_drop_job_file(str(job.get("job", "")))


## 临时文本文件没用了就删掉（它只是用来把台词安全地递给 python）。
func _drop_job_file(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 找到能用的 python 解释器（结果缓存，失败会重新探测）。
func _resolve_python() -> String:
	if not python_path.strip_edges() == "":
		return python_path.strip_edges()
	if _python_checked:
		return _resolved_python
	_python_checked = true
	for candidate in ["python", "python3", "py"]:
		var pid := OS.create_process(candidate, ["-c", "pass"])
		if pid > 0:
			_resolved_python = candidate
			break
	return _resolved_python


func synth_available() -> bool:
	return runtime_synth and _resolve_python() != ""


func pending_count() -> int:
	return _pending.size()


func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
	if _tts_checked and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()


## 系统 TTS 兜底：挑一个像样的中文音色，别再让默认那个尖嗓子出来。
func system_speak(text: String) -> void:
	if text.strip_edges() == "":
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	if not _tts_checked:
		_tts_checked = true
		_tts_voice = _pick_system_voice()
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, _tts_voice, TTS_VOLUME, TTS_PITCH, TTS_RATE)


func _pick_system_voice() -> String:
	var voices := DisplayServer.tts_get_voices()
	if voices.is_empty():
		return ""
	for want in TTS_PREFERRED:
		for voice in voices:
			var id := str(voice.get("id", ""))
			if id.to_lower().contains(want):
				return id
	# 找不到中文音色就用第一个，总比没有强
	return str(voices[0].get("id", ""))


func system_voice_name() -> String:
	if not _tts_checked:
		_tts_checked = true
		_tts_voice = _pick_system_voice()
	return _tts_voice


## 和 tools/bake_voice.py 一致的哈希。
func _hash(text: String) -> String:
	return text.sha256_text().substr(0, 16)
