class_name BjWhaleView
extends Control

## 鲸鱼娘立绘：六个情绪的 sprite sheet，整数倍放大。
##
## 素材契约（与原版一致，见 assets/whale/manifest.json）：
##   每帧 48×57，同一情绪的所有帧**横向排开**、无间隙；
##   sad 是唯一的 4 帧动画（5fps），其余都是单帧。
##
## 情绪 id 与含义：
##   idle 平常 / thinking 思考 / smug 得意嘲讽 / panic 慌张 /
##   sad 垂头丧气 / shocked 震惊难过 / angry 发怒（彩蛋）/
##   black 黑化（彩蛋第三次）
## angry / black 都是**可选素材**：缺了会回落到 idle，但抖动、红光、音效照旧。

## 被戳了（彩蛋：点它会生气）。没有 angry 素材时表情会回落到 idle，
## 但抖动和音效照样有 —— 素材没到也不影响彩蛋能玩。
signal poked

const DIR := "res://assets/whale/"
const DEFAULT_FRAMES := 48
const DEFAULT_HEIGHT := 57

## 缺素材时的兜底（manifest 损坏也不该崩）。
const FALLBACK_TIMING := {
	"idle": {"file": "idle.png", "frames": 1, "fps": 6},
	"thinking": {"file": "thinking.png", "frames": 1, "fps": 8},
	"smug": {"file": "smug.png", "frames": 1, "fps": 6},
	"panic": {"file": "panic.png", "frames": 1, "fps": 12},
	"sad": {"file": "sad.png", "frames": 4, "fps": 5},
	"shocked": {"file": "shocked.png", "frames": 1, "fps": 6},
	"angry": {"file": "angry.png", "frames": 4, "fps": 8},
	"black": {"file": "black.png", "frames": 4, "fps": 10},
}

var scale_factor := 3
var face := "idle"
var thinking_bob := false

var _textures: Dictionary = {}
var _timing: Dictionary = {}
var _frame := 0
var _frame_time := 0.0
var _bob_time := 0.0
var _base_x := 0.0
var _shake_until := 0
var _shake_time := 0.0
var _shake_strength := 0.0


func _ready() -> void:
	# 彩蛋要点得到它 → 必须吃鼠标事件
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_load_assets()
	set_face("idle")
	set_process(true)


func _on_gui_input(event: InputEvent) -> void:
	if not ((event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed):
		return
	accept_event()
	poked.emit()


## 生气发抖（彩蛋用）。抖动期间由它自己接管 position.x。
func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time = 0.0
	_shake_until = Time.get_ticks_msec() + int(duration * 1000.0)


func _load_assets() -> void:
	var manifest_timing: Dictionary = {}
	if FileAccess.file_exists(DIR + "manifest.json"):
		var file := FileAccess.open(DIR + "manifest.json", FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary and parsed.has("emotions"):
				manifest_timing = parsed["emotions"]
				if parsed.has("scale"):
					scale_factor = int(parsed["scale"])
	_timing = {}
	for key in FALLBACK_TIMING.keys():
		var entry: Dictionary = FALLBACK_TIMING[key].duplicate()
		if manifest_timing.has(key):
			var manifest_entry: Dictionary = manifest_timing[key]
			entry["frames"] = int(manifest_entry.get("frames", entry["frames"]))
			entry["fps"] = int(manifest_entry.get("fps", entry["fps"]))
			if manifest_entry.has("file"):
				entry["file"] = str(manifest_entry["file"])
		_timing[key] = entry
	for key in _timing.keys():
		var path: String = DIR + str(_timing[key]["file"])
		if ResourceLoader.exists(path):
			var texture: Texture2D = load(path)
			if texture != null:
				_textures[key] = texture
	update_size()


func update_size() -> void:
	var height := DEFAULT_HEIGHT * scale_factor
	var width := DEFAULT_FRAMES * scale_factor
	custom_minimum_size = Vector2(width, height)
	size = custom_minimum_size


## 切换表情。
func set_face(new_face: String) -> void:
	if not _timing.has(new_face):
		new_face = "idle"
	face = new_face
	_frame = 0
	_frame_time = 0.0
	queue_redraw()


func set_thinking_bob(value: bool) -> void:
	thinking_bob = value


func _process(delta: float) -> void:
	var timing: Dictionary = _timing.get(face, FALLBACK_TIMING["idle"])
	var frames: int = int(timing["frames"])
	var fps: float = float(timing["fps"])
	if frames > 1:
		_frame_time += delta
		var frame_duration := 1.0 / maxf(fps, 0.001)
		while _frame_time >= frame_duration:
			_frame_time -= frame_duration
			_frame = (_frame + 1) % frames
			queue_redraw()
	if thinking_bob:
		# 思考时上下浮 2px（原版是 900ms steps(2) 的方波）
		_bob_time += delta
		var half := 0.45
		var phase := int(_bob_time / half) % 2
		position.y = _base_y - (2.0 if phase == 1 else 0.0)
	# 生气发抖优先于一切水平位移
	if Time.get_ticks_msec() < _shake_until:
		_shake_time += delta
		position.x = _base_x + sin(_shake_time * 62.0) * _shake_strength
	elif position.x != _base_x:
		position.x = _base_x


var _base_y := 0.0


## 布局时记录基准 y，浮动动画相对它做偏移。
func set_base_position(new_position: Vector2) -> void:
	_base_y = new_position.y
	_base_x = new_position.x
	position = new_position


func _draw() -> void:
	var timing: Dictionary = _timing.get(face, FALLBACK_TIMING["idle"])
	var frames: int = int(timing["frames"])
	var texture: Texture2D = _textures.get(face, _textures.get("idle", null))
	var frame_w := DEFAULT_FRAMES
	if texture != null:
		frame_w = int(float(texture.get_width()) / float(maxi(1, frames)))
	var source := Rect2(_frame * frame_w, 0, frame_w, DEFAULT_HEIGHT)
	var target := Rect2(Vector2.ZERO, Vector2(frame_w * scale_factor, DEFAULT_HEIGHT * scale_factor))
	if texture == null:
		# 素材缺失时的占位（应该不会发生，但别让牌桌开天窗）
		draw_rect(target, Color("#3d6fd6"))
		draw_string(BjTheme.font(), Vector2(8, 24), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		return
	draw_texture_rect_region(texture, target, source)
