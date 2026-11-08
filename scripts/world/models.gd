extends RefCounted
## Процедурные low-poly модели: герои, звери, сундуки, кристаллы, костры, святилище.
## Всё собирается из простых фигур, поэтому не нужны сторонние файлы.

const HeroAnim = preload("res://scripts/world/hero_anim.gd")
const Bobber = preload("res://scripts/world/bobber.gd")

static var _mats := {}

static func mat(c: Color, emissive: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), emissive, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

static func add(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, scl: Vector3 = Vector3.ONE,
		rot: Vector3 = Vector3.ZERO, emissive: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c, emissive)
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func sphere(r: float, seg: int = 14, hemi := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * (1.0 if hemi else 2.0)
	m.is_hemisphere = hemi
	m.radial_segments = seg
	m.rings = maxi(4, seg / 2)
	return m

static func capsule(r: float, hgt: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(hgt, r * 2.0)
	m.radial_segments = 12
	m.rings = 4
	return m

static func box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m

static func cyl(rt: float, rb: float, hgt: float, seg: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = hgt
	m.radial_segments = seg
	m.rings = 1
	return m

# ---------------------------------------------------------------- ГЕРОЙ
static func hero(pr: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Hero"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var skin := Color(pr["skin"])
	var hair := Color(pr["hair"])
	var top := Color(pr["top"])
	var top2 := Color(pr["top2"])
	var pants := Color(pr["pants"])
	var shoes := Color("4a3426")
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(0.065 * side, 0.27, 0)
		body.add_child(leg)
		add(leg, capsule(0.058, 0.27), pants, Vector3(0, -0.11, 0))
		add(leg, box(Vector3(0.1, 0.065, 0.16)), shoes, Vector3(0, -0.24, 0.025))
	add(body, capsule(0.14, 0.36), top, Vector3(0, 0.43, 0))
	add(body, cyl(0.143, 0.143, 0.045), top2, Vector3(0, 0.33, 0))
	add(body, box(Vector3(0.05, 0.2, 0.02)), top2, Vector3(0, 0.46, 0.135))
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "ArmR" if side < 0 else "ArmL"  # герой смотрит в +Z: его правая рука на стороне −X
		arm.position = Vector3(0.175 * side, 0.54, 0)
		body.add_child(arm)
		add(arm, capsule(0.047, 0.24), top, Vector3(0, -0.1, 0))
		add(arm, sphere(0.048, 10), skin, Vector3(0, -0.225, 0))
		if side < 0:
			# палка-меч в правой руке
			add(arm, cyl(0.018, 0.022, 0.42, 6), Color("8a5a2b"), Vector3(0, -0.24, 0.17), Vector3.ONE, Vector3(1.5, 0, 0))
			add(arm, box(Vector3(0.1, 0.025, 0.03)), Color("5a3a1a"), Vector3(0, -0.235, 0.02))
		else:
			# деревянный щит в левой руке
			add(arm, cyl(0.11, 0.11, 0.03, 14), Color("8a5a2b"), Vector3(0.045, -0.16, 0.02), Vector3.ONE, Vector3(0, 0, 1.5708))
			add(arm, cyl(0.035, 0.035, 0.04, 8), Color("c9c9c9"), Vector3(0.065, -0.16, 0.02), Vector3.ONE, Vector3(0, 0, 1.5708))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.75, 0)
	body.add_child(head)
	add(head, sphere(0.2, 18), skin, Vector3.ZERO)
	for side in [-1, 1]:
		add(head, sphere(0.034, 10), Color("1d1a2b"), Vector3(0.072 * side, -0.015, 0.177), Vector3(1, 1.35, 0.6))
		add(head, sphere(0.012, 6), Color.WHITE, Vector3(0.072 * side + 0.012, 0.008, 0.198), Vector3.ONE, Vector3.ZERO, 1.2)
		add(head, sphere(0.028, 8), Color("f29a9a"), Vector3(0.122 * side, -0.075, 0.158), Vector3(1, 0.5, 0.4))
	add(head, box(Vector3(0.05, 0.012, 0.01)), Color("8a4a3a"), Vector3(0, -0.095, 0.192))
	_hair(head, pr, hair)
	_accessories(body, pr)
	root.set_script(HeroAnim)
	return root

static func _hair_base(head: Node3D, hair: Color) -> void:
	add(head, sphere(0.214, 18, true), hair, Vector3(0, 0.035, -0.005), Vector3(1, 0.95, 1))
	add(head, sphere(0.206, 16), hair, Vector3(0, -0.03, -0.055), Vector3(1.03, 1.0, 0.85))
	add(head, box(Vector3(0.3, 0.06, 0.08)), hair, Vector3(0, 0.085, 0.16), Vector3.ONE, Vector3(0.35, 0, 0))

static func _hair(head: Node3D, pr: Dictionary, hair: Color) -> void:
	var st: String = pr["style"]
	var hat_col := Color(pr["hat"]) if pr["hat"] != "" else hair
	match st:
		"cap":
			_hair_base(head, hair)
			add(head, sphere(0.226, 18, true), hat_col, Vector3(0, 0.06, -0.005))
			add(head, box(Vector3(0.26, 0.025, 0.17)), hat_col, Vector3(0, 0.07, 0.2), Vector3.ONE, Vector3(-0.12, 0, 0))
			add(head, sphere(0.05, 8), Color.WHITE, Vector3(0, 0.15, 0.17), Vector3(1, 1, 0.4))
		"hood":
			add(head, box(Vector3(0.3, 0.06, 0.08)), hair, Vector3(0, 0.09, 0.165), Vector3.ONE, Vector3(0.35, 0, 0))
			add(head, sphere(0.255, 18, true), hat_col, Vector3(0, 0.02, -0.02))
			add(head, sphere(0.245, 16), hat_col, Vector3(0, -0.05, -0.08), Vector3(1.0, 1.0, 0.85))
		"ponytail":
			_hair_base(head, hair)
			add(head, sphere(0.075, 10), hair, Vector3(0, 0.08, -0.22))
			add(head, capsule(0.055, 0.3), hair, Vector3(0, -0.08, -0.27), Vector3.ONE, Vector3(0.35, 0, 0))
		"spiky":
			_hair_base(head, hair)
			var spikes := [Vector3(0, 0.2, 0.05), Vector3(0.12, 0.17, 0), Vector3(-0.12, 0.17, 0),
				Vector3(0.07, 0.18, -0.12), Vector3(-0.07, 0.18, -0.12), Vector3(0, 0.12, -0.2)]
			for s in spikes:
				var sv: Vector3 = s
				var mi := add(head, cyl(0.0, 0.07, 0.2, 6), hair, sv)
				mi.rotation = Vector3(-sv.z * 3.5, 0, sv.x * 4.0)
		"buns":
			_hair_base(head, hair)
			for side in [-1, 1]:
				add(head, sphere(0.085, 10), hair, Vector3(0.13 * side, 0.17, -0.03))
		"explorer":
			_hair_base(head, hair)
			add(head, cyl(0.31, 0.31, 0.025, 20), hat_col, Vector3(0, 0.13, 0))
			add(head, cyl(0.165, 0.19, 0.15, 16), hat_col, Vector3(0, 0.21, 0))
			add(head, cyl(0.192, 0.192, 0.035, 16), Color("4a3020"), Vector3(0, 0.155, 0))
		"wizard":
			_hair_base(head, hair)
			add(head, cyl(0.3, 0.3, 0.025, 20), hat_col, Vector3(0, 0.13, 0))
			add(head, cyl(0.0, 0.2, 0.46, 14), hat_col, Vector3(0, 0.35, -0.03), Vector3.ONE, Vector3(-0.22, 0, 0.08))
			add(head, sphere(0.035, 6), Color("f1c40f"), Vector3(0.06, 0.3, 0.12), Vector3.ONE, Vector3.ZERO, 1.5)
		"headband":
			_hair_base(head, hair)
			for s in [Vector3(0.08, 0.19, -0.02), Vector3(-0.08, 0.19, -0.02), Vector3(0, 0.17, -0.14)]:
				var sv: Vector3 = s
				var mi := add(head, cyl(0.0, 0.07, 0.18, 6), hair, sv)
				mi.rotation = Vector3(-sv.z * 3.0, 0, sv.x * 3.0)
			add(head, cyl(0.212, 0.212, 0.05, 18), hat_col, Vector3(0, 0.06, 0))
			add(head, box(Vector3(0.04, 0.16, 0.02)), hat_col, Vector3(0.04, -0.03, -0.215), Vector3.ONE, Vector3(0.3, 0, 0.3))
		"long":
			_hair_base(head, hair)
			add(head, capsule(0.17, 0.5), hair, Vector3(0, -0.17, -0.1), Vector3(1.05, 1, 0.55))
		"bob":
			_hair_base(head, hair)
			for side in [-1, 1]:
				add(head, sphere(0.12, 10), hair, Vector3(0.15 * side, -0.06, -0.02), Vector3(0.7, 1.2, 1))
		_:
			_hair_base(head, hair)

static func _accessories(body: Node3D, pr: Dictionary) -> void:
	var c := Color(pr["acc_col"])
	for a in pr["acc"]:
		match a:
			"backpack":
				add(body, box(Vector3(0.22, 0.25, 0.11)), c, Vector3(0, 0.45, -0.17))
				add(body, box(Vector3(0.18, 0.08, 0.04)), c.darkened(0.2), Vector3(0, 0.39, -0.235))
			"scarf":
				var tm := TorusMesh.new()
				tm.inner_radius = 0.08
				tm.outer_radius = 0.15
				add(body, tm, c, Vector3(0, 0.6, 0), Vector3(1, 0.8, 1))
				add(body, box(Vector3(0.07, 0.2, 0.03)), c, Vector3(0.06, 0.5, -0.15), Vector3.ONE, Vector3(0.2, 0, 0.1))
			"cape":
				add(body, box(Vector3(0.32, 0.42, 0.03)), c, Vector3(0, 0.4, -0.155), Vector3.ONE, Vector3(0.12, 0, 0))
			"goggles":
				var head: Node3D = body.get_node("Head")
				for side in [-1, 1]:
					add(head, cyl(0.045, 0.045, 0.04, 10), c, Vector3(0.07 * side, 0.12, 0.165), Vector3.ONE, Vector3(1.3, 0, 0), 0.6)
				add(head, cyl(0.213, 0.213, 0.025, 18), Color("3a2a20"), Vector3(0, 0.12, 0))
			"bag":
				add(body, box(Vector3(0.14, 0.14, 0.07)), c, Vector3(0.17, 0.33, 0.04))
				add(body, box(Vector3(0.03, 0.4, 0.02)), c, Vector3(0, 0.47, 0.13), Vector3.ONE, Vector3(0, 0, 0.75))

# ---------------------------------------------------------------- ПИТОМЕЦ
static func pet_fox() -> Node3D:
	var root := Node3D.new()
	var o := Color("ff8a2a")
	var cream := Color("fff1dc")
	add(root, sphere(0.11, 12), o, Vector3(0, 0.13, 0), Vector3(1, 0.9, 1.3))
	add(root, sphere(0.09, 12), o, Vector3(0, 0.24, 0.1))
	add(root, sphere(0.045, 8), cream, Vector3(0, 0.215, 0.18), Vector3(1, 0.8, 1))
	for side in [-1, 1]:
		add(root, cyl(0.0, 0.035, 0.09, 6), o, Vector3(0.05 * side, 0.33, 0.09), Vector3.ONE, Vector3(0, 0, -0.3 * side))
		add(root, sphere(0.018, 6), Color("1d1a2b"), Vector3(0.04 * side, 0.255, 0.18))
	add(root, cyl(0.0, 0.06, 0.22, 8), o, Vector3(0, 0.2, -0.17), Vector3.ONE, Vector3(-1.0, 0, 0))
	add(root, sphere(0.035, 8), cream, Vector3(0, 0.27, -0.26))
	root.set_script(Bobber)
	return root

# ---------------------------------------------------------------- ПРИЗЫВЫ (звери сына)
static func summon_model(id: String) -> Node3D:
	var root := Node3D.new()
	var eye := Color("1d1a2b")
	match id:
		"dog":
			var c := Color("c8924e")
			add(root, box(Vector3(0.18, 0.16, 0.34)), c, Vector3(0, 0.22, 0))
			add(root, box(Vector3(0.16, 0.15, 0.16)), c, Vector3(0, 0.33, 0.2))
			add(root, box(Vector3(0.08, 0.07, 0.08)), Color("f0dcc0"), Vector3(0, 0.3, 0.3))
			add(root, sphere(0.022, 6), eye, Vector3(0, 0.32, 0.345))
			for side in [-1, 1]:
				add(root, box(Vector3(0.05, 0.1, 0.03)), c.darkened(0.3), Vector3(0.07 * side, 0.37, 0.18), Vector3.ONE, Vector3(0, 0, 0.3 * side))
				add(root, sphere(0.018, 6), eye, Vector3(0.045 * side, 0.36, 0.28))
				for fz in [-0.11, 0.11]:
					add(root, cyl(0.025, 0.025, 0.16, 6), c.darkened(0.2), Vector3(0.06 * side, 0.08, fz))
			add(root, cyl(0.015, 0.03, 0.16, 6), c, Vector3(0, 0.3, -0.2), Vector3.ONE, Vector3(-0.8, 0, 0))
		"cat":
			var c := Color("e08a3a")
			add(root, capsule(0.08, 0.3), c, Vector3(0, 0.18, 0), Vector3.ONE, Vector3(1.5708, 0, 0))
			add(root, sphere(0.095, 10), c, Vector3(0, 0.27, 0.15))
			for side in [-1, 1]:
				add(root, cyl(0.0, 0.035, 0.08, 4), c.darkened(0.2), Vector3(0.05 * side, 0.36, 0.14))
				add(root, sphere(0.018, 6), Color("7fe36a"), Vector3(0.035 * side, 0.29, 0.235), Vector3.ONE, Vector3.ZERO, 1.2)
				for fz in [-0.09, 0.09]:
					add(root, cyl(0.02, 0.02, 0.12, 6), c, Vector3(0.05 * side, 0.06, fz))
			add(root, cyl(0.012, 0.02, 0.28, 6), c, Vector3(0, 0.3, -0.2), Vector3.ONE, Vector3(-0.3, 0, 0))
		"parrot":
			var g := Color("2fbf4f")
			var fly := Node3D.new()
			fly.position = Vector3(0, 0.45, 0)
			root.add_child(fly)
			add(fly, sphere(0.09, 10), g, Vector3(0, 0, 0), Vector3(1, 1.2, 1))
			add(fly, sphere(0.065, 10), Color("e8483f"), Vector3(0, 0.12, 0.03))
			add(fly, cyl(0.0, 0.03, 0.07, 6), Color("f2c12e"), Vector3(0, 0.11, 0.1), Vector3.ONE, Vector3(1.5708, 0, 0))
			for side in [-1, 1]:
				add(fly, box(Vector3(0.14, 0.03, 0.09)), Color("3d8bff"), Vector3(0.1 * side, 0.0, -0.01), Vector3.ONE, Vector3(0, 0, 0.4 * side))
				add(fly, sphere(0.014, 6), eye, Vector3(0.035 * side, 0.14, 0.07))
			add(fly, box(Vector3(0.05, 0.02, 0.14)), g.darkened(0.2), Vector3(0, -0.08, -0.1))
		"hamster":
			var c := Color("e8b062")
			add(root, sphere(0.1, 12), c, Vector3(0, 0.1, 0), Vector3(1, 0.85, 1.1))
			add(root, sphere(0.06, 10), Color("fff1dc"), Vector3(0, 0.08, 0.06), Vector3(1, 0.8, 0.9))
			for side in [-1, 1]:
				add(root, sphere(0.03, 6), c.darkened(0.2), Vector3(0.06 * side, 0.18, 0.02))
				add(root, sphere(0.014, 6), eye, Vector3(0.035 * side, 0.13, 0.095))
		"pig":
			var c := Color("f3a0b0")
			add(root, sphere(0.16, 12), c, Vector3(0, 0.2, 0), Vector3(1, 0.9, 1.3))
			add(root, cyl(0.05, 0.05, 0.05, 10), c.darkened(0.15), Vector3(0, 0.22, 0.22), Vector3.ONE, Vector3(1.5708, 0, 0))
			for side in [-1, 1]:
				add(root, cyl(0.0, 0.04, 0.06, 4), c.darkened(0.1), Vector3(0.07 * side, 0.34, 0.12))
				add(root, sphere(0.016, 6), eye, Vector3(0.05 * side, 0.28, 0.18))
				for fz in [-0.1, 0.1]:
					add(root, cyl(0.03, 0.03, 0.1, 6), c.darkened(0.2), Vector3(0.08 * side, 0.05, fz))
		"cow":
			var w := Color("f4f1e8")
			var b := Color("2b2b2b")
			add(root, box(Vector3(0.26, 0.22, 0.42)), w, Vector3(0, 0.3, 0))
			add(root, box(Vector3(0.12, 0.1, 0.02)), b, Vector3(0.1, 0.33, 0.1), Vector3.ONE, Vector3(0, 1.5708, 0))
			add(root, box(Vector3(0.1, 0.08, 0.02)), b, Vector3(-0.131, 0.3, -0.08), Vector3.ONE, Vector3(0, 1.5708, 0))
			add(root, box(Vector3(0.18, 0.17, 0.17)), w, Vector3(0, 0.4, 0.27))
			add(root, box(Vector3(0.14, 0.08, 0.06)), Color("f3a0b0"), Vector3(0, 0.36, 0.36))
			for side in [-1, 1]:
				add(root, cyl(0.0, 0.025, 0.08, 6), Color("f4ecd8"), Vector3(0.07 * side, 0.52, 0.25), Vector3.ONE, Vector3(0, 0, -0.6 * side))
				add(root, sphere(0.018, 6), eye, Vector3(0.05 * side, 0.43, 0.355))
				for fz in [-0.14, 0.14]:
					add(root, cyl(0.035, 0.035, 0.2, 6), w.darkened(0.1), Vector3(0.09 * side, 0.1, fz))
		"chicken":
			var w := Color("fbfbf5")
			add(root, sphere(0.1, 10), w, Vector3(0, 0.16, 0), Vector3(1, 1, 1.2))
			add(root, sphere(0.06, 10), w, Vector3(0, 0.28, 0.07))
			add(root, box(Vector3(0.02, 0.05, 0.06)), Color("e8483f"), Vector3(0, 0.35, 0.07))
			add(root, cyl(0.0, 0.02, 0.05, 5), Color("f2c12e"), Vector3(0, 0.28, 0.14), Vector3.ONE, Vector3(1.5708, 0, 0))
			for side in [-1, 1]:
				add(root, sphere(0.012, 6), eye, Vector3(0.03 * side, 0.3, 0.12))
				add(root, cyl(0.008, 0.008, 0.08, 4), Color("f2a02e"), Vector3(0.04 * side, 0.04, 0))
		"wolf":
			var wv := beast("wolf")
			wv.scale = Vector3.ONE * 0.75
			return wv
		"fox":
			var f := pet_fox()
			f.scale = Vector3.ONE * 1.3
			return f
		"bear":
			var bv := beast("bear")
			bv.scale = Vector3.ONE * 0.85
			return bv
	root.set_script(Bobber)
	return root

# ---------------------------------------------------------------- ЗВЕРИ
static func beast(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"wolf":
			var g := Color("7d808a")
			var d := Color("55575f")
			add(root, box(Vector3(0.24, 0.22, 0.48)), g, Vector3(0, 0.3, 0))
			add(root, box(Vector3(0.2, 0.2, 0.2)), g, Vector3(0, 0.42, 0.28))
			add(root, box(Vector3(0.1, 0.09, 0.14)), d, Vector3(0, 0.38, 0.42))
			for side in [-1, 1]:
				add(root, cyl(0.0, 0.05, 0.12, 4), d, Vector3(0.06 * side, 0.56, 0.26))
				add(root, sphere(0.022, 6), Color("ffd23a"), Vector3(0.055 * side, 0.45, 0.385), Vector3.ONE, Vector3.ZERO, 2.0)
				for fz in [-0.16, 0.16]:
					add(root, cyl(0.035, 0.035, 0.22, 6), d, Vector3(0.08 * side, 0.11, fz))
			add(root, cyl(0.02, 0.06, 0.3, 6), g, Vector3(0, 0.36, -0.32), Vector3.ONE, Vector3(-0.9, 0, 0))
		"boar":
			var b := Color("6b4a33")
			add(root, sphere(0.2, 10), b, Vector3(0, 0.28, 0), Vector3(1, 0.9, 1.4))
			add(root, box(Vector3(0.18, 0.17, 0.17)), b, Vector3(0, 0.3, 0.3))
			add(root, cyl(0.06, 0.06, 0.06, 8), Color("d39a8a"), Vector3(0, 0.28, 0.4), Vector3.ONE, Vector3(1.57, 0, 0))
			for side in [-1, 1]:
				# клыки: основание в морде, остриё наружу и вверх
				add(root, cyl(0.0, 0.022, 0.13, 5), Color("f4ecd8"), Vector3(0.075 * side, 0.27, 0.43), Vector3.ONE, Vector3(0.9, 0, -0.25 * side))
				# уши-треугольники
				add(root, cyl(0.0, 0.045, 0.1, 3), b.darkened(0.2), Vector3(0.07 * side, 0.43, 0.25), Vector3(1, 1, 0.5), Vector3(-0.3, 0, -0.35 * side))
				add(root, sphere(0.02, 6), Color("ff5a3a"), Vector3(0.05 * side, 0.36, 0.385), Vector3.ONE, Vector3.ZERO, 2.0)
				for fz in [-0.14, 0.14]:
					add(root, cyl(0.035, 0.035, 0.16, 6), b.darkened(0.3), Vector3(0.1 * side, 0.08, fz))
			add(root, box(Vector3(0.04, 0.12, 0.3)), Color("3a2a1e"), Vector3(0, 0.47, 0.0))
		"bear":
			var br := Color("6b4428")
			var dk := br.darkened(0.3)
			add(root, sphere(0.3, 14), br, Vector3(0, 0.4, 0), Vector3(1.0, 0.95, 1.35))
			add(root, sphere(0.19, 14), br, Vector3(0, 0.58, 0.4))
			add(root, sphere(0.09, 10), Color("c9a27a"), Vector3(0, 0.53, 0.56), Vector3(1, 0.8, 1))
			add(root, sphere(0.035, 6), Color("1d1a2b"), Vector3(0, 0.56, 0.645))
			for side in [-1, 1]:
				add(root, sphere(0.065, 8), br, Vector3(0.13 * side, 0.74, 0.36))
				add(root, sphere(0.022, 6), Color("1d1a2b"), Vector3(0.075 * side, 0.63, 0.55))
				for fz in [-0.2, 0.22]:
					add(root, cyl(0.075, 0.08, 0.32, 8), dk, Vector3(0.17 * side, 0.15, fz))
			root.scale = Vector3.ONE * 0.95
		"guardian":
			var s := Color("8d8f96")
			var m := Color("6d7f6a")
			add(root, box(Vector3(0.42, 0.48, 0.3)), s, Vector3(0, 0.58, 0))
			add(root, box(Vector3(0.28, 0.24, 0.26)), s, Vector3(0, 0.95, 0.02))
			add(root, box(Vector3(0.3, 0.06, 0.28)), m, Vector3(0, 1.08, 0.02))
			for side in [-1, 1]:
				add(root, box(Vector3(0.14, 0.42, 0.16)), s.darkened(0.1), Vector3(0.3 * side, 0.55, 0), Vector3.ONE, Vector3(0, 0, 0.15 * side))
				add(root, box(Vector3(0.15, 0.32, 0.18)), s.darkened(0.15), Vector3(0.12 * side, 0.17, 0))
				add(root, box(Vector3(0.06, 0.04, 0.02)), Color("5ff3ff"), Vector3(0.07 * side, 0.97, 0.155), Vector3.ONE, Vector3.ZERO, 3.0)
			add(root, sphere(0.07, 8), Color("5ff3ff"), Vector3(0, 0.62, 0.16), Vector3(1, 1, 0.4), Vector3.ZERO, 2.5)
	root.scale = Vector3.ONE * 1.3
	root.set_script(Bobber)
	return root

# ---------------------------------------------------------------- ПРЕДМЕТЫ МИРА
static func shard() -> Node3D:
	var root := Node3D.new()
	var c := Color("7fe3ff")
	var pivot := Node3D.new()
	pivot.name = "Spin"
	pivot.position = Vector3(0, 0.45, 0)
	root.add_child(pivot)
	add(pivot, cyl(0.0, 0.13, 0.28, 6), c, Vector3(0, 0.14, 0), Vector3.ONE, Vector3.ZERO, 1.6)
	add(pivot, cyl(0.13, 0.0, 0.22, 6), c.darkened(0.15), Vector3(0, -0.11, 0), Vector3.ONE, Vector3.ZERO, 1.2)
	add(root, cyl(0.22, 0.26, 0.06, 10), Color("8a8478"), Vector3(0, 0.03, 0))
	add(root, cyl(0.2, 0.2, 0.01, 16), Color(0.5, 0.9, 1.0, 0.35), Vector3(0, 0.065, 0), Vector3.ONE, Vector3.ZERO, 1.5)
	root.set_script(Bobber)
	root.set("spin", true)
	return root

static func chest() -> Node3D:
	var root := Node3D.new()
	var wood := Color("8a5a2b")
	var gold := Color("e8c36a")
	add(root, box(Vector3(0.44, 0.24, 0.3)), wood, Vector3(0, 0.12, 0))
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.24, -0.15)
	root.add_child(lid)
	add(lid, box(Vector3(0.46, 0.1, 0.32)), wood.lightened(0.1), Vector3(0, 0.05, 0.15))
	for x in [-0.15, 0.15]:
		add(lid, box(Vector3(0.05, 0.11, 0.34)), gold, Vector3(x, 0.055, 0.15))
	for x in [-0.15, 0.15]:
		add(root, box(Vector3(0.04, 0.26, 0.32)), gold, Vector3(x, 0.13, 0))
	add(root, box(Vector3(0.08, 0.08, 0.03)), gold, Vector3(0, 0.2, 0.16), Vector3.ONE, Vector3.ZERO, 0.4)
	return root

static func campfire() -> Node3D:
	var root := Node3D.new()
	for i in 3:
		add(root, cyl(0.04, 0.04, 0.42, 6), Color("5a3a22"), Vector3(0, 0.05, 0), Vector3.ONE, Vector3(1.57, i * 1.05, 0))
	for i in 6:
		var a := i * TAU / 6.0
		add(root, sphere(0.06, 6), Color("777068"), Vector3(cos(a) * 0.26, 0.03, sin(a) * 0.26))
	var flame := Node3D.new()
	flame.name = "Flame"
	root.add_child(flame)
	add(flame, cyl(0.0, 0.13, 0.32, 7), Color("ff7a1a"), Vector3(0, 0.22, 0), Vector3.ONE, Vector3.ZERO, 3.0)
	add(flame, cyl(0.0, 0.07, 0.22, 7), Color("ffe066"), Vector3(0, 0.2, 0), Vector3.ONE, Vector3.ZERO, 3.5)
	var l := OmniLight3D.new()
	l.name = "Light"
	l.light_color = Color("ffa04a")
	l.omni_range = 4.5
	l.light_energy = 1.6
	l.position = Vector3(0, 0.6, 0)
	root.add_child(l)
	root.set_script(Bobber)
	root.set("flicker", true)
	return root

## Гора с воротами — цель игры. Ворота смотрят на север (−Z), гора уходит на юг (+Z).
static func mountain_gate() -> Node3D:
	var root := Node3D.new()
	var rock := Color("8a8378")
	var dark := Color("6e685f")
	var snow := Color("eef0f5")
	for sp in [[0.0, 3.2, 2.4, 6.0], [-2.4, 2.6, 1.9, 4.4], [2.5, 2.8, 2.0, 4.8], [-1.1, 4.9, 2.8, 7.2], [1.5, 5.1, 2.6, 6.6], [-3.6, 4.2, 1.8, 3.6], [3.8, 4.4, 1.9, 3.9]]:
		var x: float = sp[0]
		var z: float = sp[1]
		var r: float = sp[2]
		var h: float = sp[3]
		add(root, cyl(0.0, r, h, 7), rock.darkened(randf() * 0.12), Vector3(x, h * 0.5 - 0.35, z), Vector3.ONE, Vector3(0, randf() * TAU, 0))
		add(root, cyl(0.0, r * 0.34, h * 0.34, 7), snow, Vector3(x, h - 0.35 - h * 0.17 + 0.03, z))
	add(root, box(Vector3(3.4, 2.6, 1.2)), dark, Vector3(0, 0.95, 0.85))
	add(root, cyl(0.85, 0.95, 0.1, 16), Color("a39d92"), Vector3(0, 0.05, -0.1))
	for side in [-1, 1]:
		add(root, box(Vector3(0.32, 2.0, 0.42)), Color("9a948a"), Vector3(0.66 * side, 1.0, 0.2))
	add(root, box(Vector3(1.7, 0.34, 0.48)), Color("8f897f"), Vector3(0, 2.1, 0.2))
	var portal := add(root, box(Vector3(1.0, 1.7, 0.05)), Color("9a55f0"), Vector3(0, 0.9, 0.42), Vector3.ONE, Vector3.ZERO, 1.8)
	portal.name = "Portal"
	for side in [-1, 1]:
		var slab := add(root, box(Vector3(0.5, 1.75, 0.16)), Color("7d776d"), Vector3(0.25 * side, 0.9, 0.24))
		slab.name = "SlabL" if side < 0 else "SlabR"
		add(slab, box(Vector3(0.06, 1.2, 0.02)), Color("c58cff"), Vector3(-0.2 * side, 0, -0.09), Vector3.ONE, Vector3.ZERO, 0.8)
	for i in 3:
		var x := -0.45 + i * 0.45
		add(root, cyl(0.12, 0.12, 0.05, 14), Color("e8c36a"), Vector3(x, 2.1, -0.05), Vector3.ONE, Vector3(1.5708, 0, 0), 0.3)
		var sk := add(root, sphere(0.08, 10), Color("333333"), Vector3(x, 2.1, -0.08))
		sk.name = "Socket%d" % i
	var tr := Node3D.new()
	tr.name = "Treasure"
	tr.position = Vector3(0, 0.2, 0.5)
	tr.visible = false
	root.add_child(tr)
	add(tr, cyl(0.0, 0.26, 0.42, 6), Color("ffd76a"), Vector3(0, 0.62, 0), Vector3.ONE, Vector3.ZERO, 2.2)
	add(tr, cyl(0.26, 0.0, 0.34, 6), Color("ff9ad5"), Vector3(0, 0.24, 0), Vector3.ONE, Vector3.ZERO, 1.8)
	var inner := OmniLight3D.new()
	inner.name = "Inner"
	inner.light_color = Color("e0b0ff")
	inner.omni_range = 7.0
	inner.light_energy = 0.0
	inner.position = Vector3(0, 1.2, -0.4)
	root.add_child(inner)
	var l := OmniLight3D.new()
	l.light_color = Color("c58cff")
	l.omni_range = 4.0
	l.light_energy = 1.2
	l.position = Vector3(0, 1.6, -0.8)
	root.add_child(l)
	return root

## Эльф-волшебник для заставки.
static func elf(robe: Color) -> Node3D:
	var root := Node3D.new()
	var skin := Color("f3e2d0")
	add(root, cyl(0.07, 0.24, 0.72, 10), robe, Vector3(0, 0.36, 0))
	add(root, cyl(0.075, 0.075, 0.05, 10), Color("e8c36a"), Vector3(0, 0.55, 0))
	add(root, sphere(0.14, 14), skin, Vector3(0, 0.84, 0))
	add(root, sphere(0.155, 14, true), robe.darkened(0.15), Vector3(0, 0.86, -0.02))
	add(root, cyl(0.0, 0.12, 0.3, 8), robe.darkened(0.15), Vector3(0, 1.06, -0.08), Vector3.ONE, Vector3(-0.5, 0, 0))
	for side in [-1, 1]:
		add(root, cyl(0.0, 0.03, 0.14, 5), skin, Vector3(0.15 * side, 0.86, -0.01), Vector3.ONE, Vector3(0, 0, -1.2 * side))
		add(root, sphere(0.022, 6), Color("4ad0ff"), Vector3(0.05 * side, 0.85, 0.125), Vector3.ONE, Vector3.ZERO, 2.0)
	add(root, cyl(0.016, 0.02, 1.1, 6), Color("6b4a2c"), Vector3(0.22, 0.55, 0.05))
	add(root, sphere(0.06, 10), Color("8fe8ff"), Vector3(0.22, 1.13, 0.05), Vector3.ONE, Vector3.ZERO, 3.0)
	root.set_script(Bobber)
	return root

static func glowing_chest() -> Node3D:
	var root := chest()
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
			pass
	var l := OmniLight3D.new()
	l.name = "Glow"
	l.light_color = Color("ffd76a")
	l.omni_range = 3.0
	l.light_energy = 2.5
	l.position = Vector3(0, 0.5, 0)
	root.add_child(l)
	add(root, sphere(0.18, 12), Color(1.0, 0.85, 0.4, 0.35), Vector3(0, 0.3, 0), Vector3(1.6, 1.0, 1.3), Vector3.ZERO, 2.0)
	return root

static func scroll() -> Node3D:
	var root := Node3D.new()
	add(root, cyl(0.035, 0.035, 0.3, 10), Color("e8d6a8"), Vector3.ZERO, Vector3.ONE, Vector3(0, 0, 1.5708))
	for side in [-1, 1]:
		add(root, cyl(0.045, 0.045, 0.03, 10), Color("6b4520"), Vector3(0.16 * side, 0, 0), Vector3.ONE, Vector3(0, 0, 1.5708))
	add(root, box(Vector3(0.05, 0.08, 0.006)), Color("9a1e1e"), Vector3(0, -0.02, 0.036))
	return root

static func event_stone() -> Node3D:
	var root := Node3D.new()
	add(root, box(Vector3(0.3, 0.5, 0.18)), Color("8e8a82"), Vector3(0, 0.25, 0), Vector3.ONE, Vector3(0, 0.3, 0.05))
	var lb := Label3D.new()
	lb.text = "?"
	lb.font_size = 96
	lb.outline_size = 18
	lb.modulate = Color("ffd76a")
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position = Vector3(0, 0.85, 0)
	lb.pixel_size = 0.004
	root.add_child(lb)
	root.set_script(Bobber)
	return root

static func trap_marker() -> Node3D:
	var root := Node3D.new()
	var c := Color(0.85, 0.15, 0.15, 0.85)
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		add(root, cyl(0.0, 0.05, 0.16, 5), c, Vector3(cos(a) * 0.15, 0.08, sin(a) * 0.15))
	add(root, cyl(0.28, 0.28, 0.015, 16), Color(0.6, 0.05, 0.05, 0.5), Vector3(0, 0.01, 0))
	return root

static func bridge_tile() -> Node3D:
	var root := Node3D.new()
	var wood := Color("9a6a3a")
	for i in 4:
		add(root, box(Vector3(0.92, 0.08, 0.22)), wood.darkened(0.08 * (i % 2)), Vector3(0, -0.04, -0.36 + i * 0.24))
	for side in [-1, 1]:
		add(root, box(Vector3(0.06, 0.06, 1.0)), wood.darkened(0.25), Vector3(0.45 * side, 0.2, 0))
		for zz in [-0.4, 0.4]:
			add(root, box(Vector3(0.07, 0.6, 0.07)), wood.darkened(0.3), Vector3(0.45 * side, -0.1, zz))
	return root

# ---------------------------------------------------------------- ДРАКОН
## Огненный дракон: стоит на 3×3 клетках. Узлы: Body, Neck, Head, Jaw, WingL, WingR, Tail, Eyes, Glow.
static func dragon() -> Node3D:
	var root := Node3D.new()
	root.name = "Dragon"
	var red := Color("8e1f1f")
	var dark := Color("5e1414")
	var belly := Color("d9a35a")
	var horn := Color("efe3c4")
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	add(body, sphere(0.9, 14), red, Vector3(0, 1.1, 0), Vector3(1.0, 0.85, 1.35))
	add(body, sphere(0.7, 12), belly, Vector3(0, 0.85, 0.3), Vector3(0.85, 0.6, 1.1))
	# шипы вдоль спины
	for i in 6:
		add(body, cyl(0.0, 0.13, 0.34, 4), horn, Vector3(0, 1.85 - i * 0.04, -0.7 + i * 0.28), Vector3.ONE, Vector3(0.25, 0, 0))
	# лапы
	for sx in [-1, 1]:
		for sz in [-0.55, 0.65]:
			add(body, cyl(0.17, 0.2, 0.7, 7), dark, Vector3(0.62 * sx, 0.38, sz))
			add(body, box(Vector3(0.32, 0.12, 0.42)), dark, Vector3(0.62 * sx, 0.06, sz + 0.1))
	# шея и голова
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 1.45, 1.05)
	body.add_child(neck)
	add(neck, cyl(0.3, 0.42, 1.1, 8), red, Vector3(0, 0.35, 0.3), Vector3.ONE, Vector3(0.7, 0, 0))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.95, 0.75)
	neck.add_child(head)
	add(head, box(Vector3(0.62, 0.42, 0.78)), red, Vector3(0, 0, 0.18))
	add(head, box(Vector3(0.5, 0.2, 0.5)), dark, Vector3(0, -0.2, 0.3))
	var jaw := add(head, box(Vector3(0.48, 0.12, 0.62)), dark.darkened(0.15), Vector3(0, -0.3, 0.25))
	jaw.name = "Jaw"
	for sx in [-1, 1]:
		add(head, cyl(0.0, 0.09, 0.55, 5), horn, Vector3(0.24 * sx, 0.33, -0.12), Vector3.ONE, Vector3(-0.6, 0, -0.25 * sx))
		add(head, cyl(0.0, 0.04, 0.16, 4), horn, Vector3(0.15 * sx, -0.2, 0.55), Vector3.ONE, Vector3(3.14, 0, 0))
	var eyes := Node3D.new()
	eyes.name = "Eyes"
	head.add_child(eyes)
	for sx in [-1, 1]:
		add(eyes, sphere(0.07, 8), Color("ffd23a"), Vector3(0.23 * sx, 0.1, 0.45), Vector3.ONE, Vector3.ZERO, 4.0)
	# крылья
	for sx in [-1, 1]:
		var wing := Node3D.new()
		wing.name = "WingL" if sx < 0 else "WingR"
		wing.position = Vector3(0.55 * sx, 1.6, 0.1)
		body.add_child(wing)
		add(wing, cyl(0.07, 0.1, 1.9, 5), dark, Vector3(1.0 * sx, 0.2, 0), Vector3.ONE, Vector3(0, 0, 1.2 * sx))
		add(wing, box(Vector3(1.8, 0.04, 1.3)), Color("a02a2a"), Vector3(1.0 * sx, 0.12, -0.3), Vector3.ONE, Vector3(0, 0, 0.18 * sx))
	# хвост
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.9, -1.2)
	body.add_child(tail)
	for i in 5:
		var r := 0.4 - i * 0.065
		add(tail, sphere(r, 8), red.darkened(i * 0.04), Vector3(sin(i * 0.5) * 0.2, 0.0 - i * 0.04, -i * 0.42))
	add(tail, cyl(0.0, 0.14, 0.4, 4), horn, Vector3(0.1, -0.2, -2.2), Vector3.ONE, Vector3(-1.57, 0, 0))
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color("ff7a2a")
	glow.omni_range = 7.0
	glow.light_energy = 1.4
	glow.position = Vector3(0, 1.6, 0.4)
	root.add_child(glow)
	return root
