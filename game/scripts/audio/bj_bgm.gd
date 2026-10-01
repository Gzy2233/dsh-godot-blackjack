class_name BjBgm
extends Node

## 背景音乐：扫描 `assets/bgm/` 里的第一个音频文件循环播放。
##
## 不写死文件名，是为了换曲子只要丢文件进去 —— 老的那首先删掉就行。
## 音量走设置里的 bgm_volume（默认 0.45，卡牌游戏的 BGM 不该抢人声）。

const BGM_DIR := "res://assets/bgm/"
const EXTENSIONS := ["ogg", "mp3", "wav"]

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
