extends Node3D
## Пухлые облака вокруг долины: медленно плывут над водой и не закрывают поле.

var map_w := 24.0
var map_h := 50.0
var _clouds: Array = []

func _ready() -> void:
	var Models = load("res://scripts/world/models.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 22:
		var c := Node3D.new()
		# кольцо вокруг карты: слева, справа и за дальним краем
		var side := i % 3
		var x := 0.0
		var z := 0.0
		if side == 0:
			x = -rng.randf_range(7.0, 26.0)
			z = rng.randf_range(-10.0, map_h + 10.0)
		elif side == 1:
			x = map_w + rng.randf_range(7.0, 26.0)
			z = rng.randf_range(-10.0, map_h + 10.0)
		else:
			x = rng.randf_range(-20.0, map_w + 20.0)
			z = -rng.randf_range(8.0, 28.0) if i % 2 == 0 else map_h + rng.randf_range(8.0, 28.0)
		c.position = Vector3(x, rng.randf_range(2.6, 6.5), z)
		var s := rng.randf_range(1.0, 2.2)
		c.scale = Vector3(s, s * 0.8, s)
		for k in rng.randi_range(3, 5):
			var r := rng.randf_range(0.6, 1.1)
			var mi: MeshInstance3D = Models.add(c, Models.sphere(r, 14), Color(0.98, 0.98, 1.0), Vector3((k - 2) * 0.75 + rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.3), rng.randf_range(-0.4, 0.4)), Vector3(1.0, 0.72, 1.0), Vector3.ZERO, 0.0, false)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		_clouds.append([c, rng.randf_range(0.08, 0.2), rng.randf() * 10.0])

func _process(delta: float) -> void:
	for e in _clouds:
		var c: Node3D = e[0]
		c.position.x += float(e[1]) * delta
		if c.position.x > map_w + 30.0:
			c.position.x = -30.0
		e[2] = float(e[2]) + delta
		c.position.y += sin(float(e[2]) * 0.4) * 0.002
