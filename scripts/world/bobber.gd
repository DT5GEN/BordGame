extends Node3D
## Лёгкая «жизнь» для объектов: покачивание, вращение кристалла, мерцание огня.

var spin := false
var flicker := false
var _t := 0.0
var _base_scale := Vector3.ONE

func _ready() -> void:
	_t = randf() * 10.0
	_base_scale = scale

func _process(delta: float) -> void:
	_t += delta
	if spin:
		var p: Node3D = get_node_or_null("Spin")
		if p:
			p.rotation.y += delta * 1.5
			p.position.y = 0.45 + sin(_t * 2.0) * 0.06
	elif flicker:
		var f: Node3D = get_node_or_null("Flame")
		if f:
			var k := 1.0 + sin(_t * 17.0) * 0.08 + sin(_t * 7.3) * 0.06
			f.scale = Vector3(1.0, k, 1.0)
		var l: OmniLight3D = get_node_or_null("Light")
		if l:
			l.light_energy = l.get_meta("base", 1.6) * (0.9 + sin(_t * 13.0) * 0.07 + sin(_t * 5.1) * 0.05)
	else:
		scale = _base_scale * Vector3(1.0, 1.0 + sin(_t * 2.2) * 0.02, 1.0)
