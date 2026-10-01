class_name BjBgm
extends Node

## 背景音乐：扫描 `assets/bgm/` 里的第一个音频文件循环播放。
##
## 不写死文件名，是为了换曲子只要丢文件进去 —— 老的那首先删掉就行。
## 音量走设置里的 bgm_volume（默认 0.45，卡牌游戏的 BGM 不该抢人声）。

const BGM_DIR := "res://assets/bgm/"
const EXTENSIONS := ["ogg", "mp3", "wav"]

## 明确的候选路径：**导出后目录扫描不可靠**，必须先按路径找。
##
## 踩过的坑（用户报的"为什么没有背景音乐"）：原来只靠 `DirAccess.get_files()`
## 扫 `assets/bgm/`，在编辑器里一切正常，但**导出版里那个目录常常是空的**
## （pck 里没有 `.import` 文件，目录列表因此不可信）→ 编辑器响得好好的，
## 一导出就静音。所以顺序改成：先按明确路径 `ResourceLoader.exists()`，
## 再退回目录扫描（开发时换了文件名不用改代码）。
const CANDIDATES := [
	"res://assets/bgm/bossa-nova.mp3",
	"res://assets/bgm/theme.mp3",
	"res://assets/bgm/bgm.mp3",
	"res://assets/bgm/bossa-nova.ogg",
	"res://assets/bgm/theme.ogg",
]

var enabled := true
var volume := 0.45

var _player: AudioStreamPlayer
var _track := ""
var _loaded := false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_track = _find_track()


## 返回扫到的曲目路径（可能为空 = 没素材）。
func _find_track() -> String:
	# ① 明确路径优先（导出版唯一可靠的找法）
	for path in CANDIDATES:
		if ResourceLoader.exists(path):
			return path
	# ② 退回目录扫描（开发期换曲子方便）
	var dir := DirAccess.open(BGM_DIR)
	if dir == null:
		return ""
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		var lower := str(file_name).to_lower()
		if lower.ends_with(".import"):
			continue
		for ext in EXTENSIONS:
			if lower.ends_with("." + ext):
				return BGM_DIR + str(file_name)
	return ""


func has_track() -> bool:
	return _track != ""


func track_name() -> String:
	if _track == "":
		return ""
	return _track.get_file().get_basename()


func play() -> void:
	if _player == null or not has_track():
		return
	if not _loaded:
		var stream: AudioStream = load(_track)
		if stream == null:
			return
		# 让素材自己循环：Ogg 与 MP3 都支持
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		_player.stream = stream
		_loaded = true
	_player.volume_db = linear_to_db(clampf(volume, 0.001, 1.0))
	if not _player.playing:
		_player.play()
		# 排障用：导出后如果这行没出现，就是没找到 BGM（而不再是"静音了但不知道为什么"）
		print("[blackjack] BGM: %s（音量 %d%%）" % [track_name(), int(volume * 100)])


func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()


## 按设置刷新（开关 + 音量）。设置是外部传进来的字典。
func apply(settings: Dictionary) -> void:
	enabled = bool(settings.get("bgm", true))
	volume = float(settings.get("bgm_volume", 0.45))
	if enabled:
		play()
	else:
		stop()
