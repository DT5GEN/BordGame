extends Node3D
## Анимация героя: дыхание, моргание, взгляд, шаг с покачиванием, эмоции на лице, прыжок радости, отдача от удара.
## Игра управляет полями walking / posing и вызывает emote("happy" | "hurt" | "angry" | "sad" | "wow" | "cheer").

var walking := false
var posing := false

var _t := 0.0
var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _legs: Array = []
var _arms: Array = []
var _eyes: Array = []
var _brows: Array = []
var _mouth: Node3D
var _walk_k := 0.0          # 0 — стоим, 1 — идём (плавный переход)
var _blink_in := 2.0
var _blink := 0.0
var _look_in := 3.0
var _look := 0.0
var _look_goal := 0.0
var _emo := "neutral"
var _emo_left := 0.0
var _act := ""              # "cheer" | "hurt" | ""
var _act_t := 0.0
var _pop := 0.0             # всплеск масштаба головы при смене эмоции

const FACES := {
	"neutral": {"eyes": "open", "brow_y": 0.0, "brow_r": 0.0, "mouth": "Smile", "eye_s": 1.0},
	"happy": {"eyes": "happy", "brow_y": 0.012, "brow_r": -0.12, "mouth": "Open", "eye_s": 1.0},
	"cheer": {"eyes": "happy", "brow_y": 0.016, "brow_r": -0.15, "mouth": "Open", "eye_s": 1.0},
	"hurt": {"eyes": "shut", "brow_y": -0.006, "brow_r": 0.45, "mouth": "Oh", "eye_s": 1.0},
	"angry": {"eyes": "open", "brow_y": -0.02, "brow_r": 0.42, "mouth": "Flat", "eye_s": 0.82},
	"sad": {"eyes": "open", "brow_y": 0.004, "brow_r": -0.42, "mouth": "Frown", "eye_s": 0.9},
	"wow": {"eyes": "open", "brow_y": 0.024, "brow_r": -0.05, "mouth": "Oh", "eye_s": 1.15},
}

func _ready() -> void:
	_t = randf() * 10.0
	_blink_in = randf_range(1.0, 4.0)
	_body = get_node("Body")
	_torso = _body.get_node_or_null("Torso")
	_head = _body.get_node_or_null("Head")
	_legs = [_body.get_node("LegL"), _body.get_node("LegR")]
	_arms = [_body.get_node("ArmL"), _body.get_node("ArmR")]
	if _head and _head.has_node("Face"):
		var f: Node3D = _head.get_node("Face")
		_eyes = [f.get_node("EyeL"), f.get_node("EyeR")]
		_brows = [f.get_node("BrowL"), f.get_node("BrowR")]
		_mouth = f.get_node("Mouth")
		for b in _brows:
			b.set_meta("y0", b.position.y)
	_apply_face()

## Показать эмоцию на secs секунд, потом лицо вернётся к спокойной улыбке.
func emote(kind: String, secs: float = 1.6) -> void:
	if not FACES.has(kind):
		return
	_emo = kind
	_emo_left = secs
	_pop = 1.0
	if kind == "cheer":
		_act = "cheer"
		_act_t = 0.0
	elif kind == "hurt":
		_act = "hurt"
		_act_t = 0.0
	_apply_face()

func _apply_face() -> void:
	if _mouth == null:
		return
	var f: Dictionary = FACES[_emo]
	for c in _mouth.get_children():
		c.visible = c.name == f["mouth"]
	for i in 2:
		var e: Node3D = _eyes[i]
		e.get_node("Open").visible = f["eyes"] == "open"
		e.get_node("Happy").visible = f["eyes"] == "happy"
		e.get_node("Shut").visible = f["eyes"] == "shut"
		var side := -1.0 if i == 0 else 1.0
		var b: Node3D = _brows[i]
		b.position.y = float(b.get_meta("y0")) + float(f["brow_y"])
		b.rotation.z = float(f["brow_r"]) * side

func _process(delta: float) -> void:
	_t += delta
	var d10 := minf(delta * 10.0, 1.0)
	_walk_k = move_toward(_walk_k, 1.0 if walking else 0.0, delta * 7.0)
	# --- эмоция гаснет
	if _emo != "neutral":
		_emo_left -= delta
		if _emo_left <= 0.0:
			_emo = "neutral"
			_apply_face()
	_pop = maxf(0.0, _pop - delta * 5.0)
	# --- моргание и взгляд
	if _mouth != null:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink = 0.13
			_blink_in = randf_range(2.2, 5.0)
		_blink = maxf(0.0, _blink - delta)
		var es := float(FACES[_emo]["eye_s"])
		var lid := 0.1 if _blink > 0.0 else es
		_look_in -= delta
		if _look_in <= 0.0:
			_look_goal = [0.0, 0.0, -0.014, 0.014][randi() % 4]
			_look_in = randf_range(1.5, 4.0)
		_look = lerpf(_look, _look_goal if _walk_k < 0.5 else 0.0, minf(delta * 8.0, 1.0))
		for e in _eyes:
			var op: Node3D = e.get_node("Open")
			op.scale.y = lerpf(op.scale.y, lid, minf(delta * 30.0, 1.0))
			op.get_node("Pupil").position.x = _look
	# --- тело
	var s := sin(_t * 13.0)
	var c2 := absf(s)
	var breath := sin(_t * 2.4)
	var y := lerpf(breath * 0.01, c2 * 0.075, _walk_k)
	var lean := lerpf(0.0, 0.16, _walk_k)
	var sq := 1.0 + lerpf(breath * 0.012, (c2 - 0.5) * 0.05, _walk_k)
	var jump := 0.0
	if _act == "cheer":
		_act_t += delta
		var ph := _act_t / 0.42
		jump = absf(sin(ph * PI)) * 0.26
		if _act_t > 0.84:
			_act = ""
	elif _act == "hurt":
		_act_t += delta
		lean = -0.35 * maxf(0.0, 1.0 - _act_t / 0.45)
		if _act_t > 0.45:
			_act = ""
	_body.position.y = y + jump
	_body.rotation.x = lerpf(_body.rotation.x, lean, d10)
	_body.rotation.z = lerpf(_body.rotation.z, s * 0.05 * _walk_k, d10)
	_body.scale = Vector3(2.0 - sq, sq, 2.0 - sq)
	if _head:
		var hp := 1.0 + _pop * 0.1
		_head.scale = Vector3(hp, hp, hp)
		_head.rotation.x = lerpf(_head.rotation.x, -lean * 0.6 + (0.0 if _walk_k > 0.5 else sin(_t * 1.3) * 0.03), d10)
		_head.rotation.z = lerpf(_head.rotation.z, (0.0 if _walk_k > 0.5 else sin(_t * 0.9) * 0.04), d10)
		_head.rotation.y = lerpf(_head.rotation.y, _look * 9.0, minf(delta * 4.0, 1.0))
	var leg_a := s * 0.85 * _walk_k
	_legs[0].rotation.x = leg_a
	_legs[1].rotation.x = -leg_a
	if _act == "cheer":
		# руки вверх
		for i in 2:
			var side := 1.0 if i == 0 else -1.0
			_arms[i].rotation.x = lerpf(_arms[i].rotation.x, 0.0, d10)
			_arms[i].rotation.z = lerpf(_arms[i].rotation.z, 2.5 * side, minf(delta * 16.0, 1.0))
	elif not posing:
		_arms[0].rotation.x = lerpf(_arms[0].rotation.x, -s * 0.75 * _walk_k, d10 * 1.5)
		_arms[1].rotation.x = lerpf(_arms[1].rotation.x, s * 0.75 * _walk_k, d10 * 1.5)
		_arms[0].rotation.z = lerpf(_arms[0].rotation.z, 0.1 + breath * 0.035, d10)
		_arms[1].rotation.z = lerpf(_arms[1].rotation.z, -0.1 - breath * 0.035, d10)
