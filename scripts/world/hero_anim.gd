extends Node3D
## Анимация героя: дыхание на месте и шаг при ходьбе.

var walking := false
var posing := false
var _t := 0.0
var _body: Node3D
var _legs: Array = []
var _arms: Array = []

func _ready() -> void:
	_t = randf() * 10.0
	_body = get_node("Body")
	_legs = [_body.get_node("LegL"), _body.get_node("LegR")]
	_arms = [_body.get_node("ArmL"), _body.get_node("ArmR")]

func _process(delta: float) -> void:
	_t += delta
	if walking:
		var s := sin(_t * 15.0)
		_body.position.y = absf(s) * 0.06
		_legs[0].rotation.x = s * 0.7
		_legs[1].rotation.x = -s * 0.7
		_arms[0].rotation.x = -s * 0.6
		_arms[1].rotation.x = s * 0.6
	elif posing:
		_body.position.y = sin(_t * 4.0) * 0.015
	else:
		_body.position.y = sin(_t * 2.4) * 0.012
		for l in _legs:
			l.rotation.x = lerpf(l.rotation.x, 0.0, minf(delta * 10.0, 1.0))
		_arms[0].rotation.x = lerpf(_arms[0].rotation.x, 0.0, minf(delta * 10.0, 1.0))
		_arms[1].rotation.x = lerpf(_arms[1].rotation.x, 0.0, minf(delta * 10.0, 1.0))
		_arms[0].rotation.z = -0.08 - sin(_t * 2.4) * 0.03
		_arms[1].rotation.z = 0.08 + sin(_t * 2.4) * 0.03
