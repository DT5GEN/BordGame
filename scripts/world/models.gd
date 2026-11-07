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
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = Vector3(0.175 * side, 0.54, 0)
		body.add_child(arm)
		add(arm, capsule(0.047, 0.24), top, Vector3(0, -0.1, 0))
		add(arm, sphere(0.048, 10), skin, Vector3(0, -0.225, 0))
		if side > 0:
			# палка-меч
			add(arm, cyl(0.018, 0.022, 0.42, 6), Color("8a5a2b"), Vector3(0, -0.24, 0.17), Vector3.ONE, Vector3(1.5, 0, 0))
			add(arm, box(Vector3(0.1, 0.025, 0.03)), Color("5a3a1a"), Vector3(0, -0.235, 0.02))
		else:
			# деревянный щит
			add(arm, cyl(0.11, 0.11, 0.03, 14), Color("8a5a2b"), Vector3(-0.045, -0.16, 0.02), Vector3.ONE, Vector3(0, 0, 1.5708))
			add(arm, cyl(0.035, 0.035, 0.04, 8), Color("c9c9c9"), Vector3(-0.065, -0.16, 0.02), Vector3.ONE, Vector3(0, 0, 1.5708))
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
				add(root, cyl(0.0, 0.02, 0.12, 5), Color("f4ecd8"), Vector3(0.07 * side, 0.26, 0.42), Vector3.ONE, Vector3(-1.1, 0, 0))
				add(root, sphere(0.02, 6), Color("ff5a3a"), Vector3(0.05 * side, 0.36, 0.385), Vector3.ONE, Vector3.ZERO, 2.0)
				for fz in [-0.14, 0.14]:
					add(root, cyl(0.035, 0.035, 0.16, 6), b.darkened(0.3), Vector3(0.1 * side, 0.08, fz))
			add(root, box(Vector3(0.04, 0.12, 0.3)), Color("3a2a1e"), Vector3(0, 0.47, 0.0))
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
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = 2.2
	l.light_energy = 1.4
	l.position = Vector3(0, 0.5, 0)
	root.add_child(l)
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

static func shrine() -> Node3D:
	var root := Node3D.new()
	var st := Color("b9b4a8")
	add(root, cyl(0.5, 0.56, 0.12, 16), st, Vector3(0, 0.06, 0))
	for side in [-1, 1]:
		add(root, box(Vector3(0.18, 1.3, 0.2)), st, Vector3(0.42 * side, 0.75, 0))
		add(root, box(Vector3(0.24, 0.1, 0.26)), st.darkened(0.1), Vector3(0.42 * side, 0.12, 0))
	add(root, box(Vector3(1.14, 0.2, 0.28)), st.darkened(0.05), Vector3(0, 1.48, 0))
	var portal := add(root, cyl(0.34, 0.34, 0.04, 24), Color("9a55f0"), Vector3(0, 0.78, 0), Vector3(1, 1, 1.6), Vector3(1.57, 0, 0), 0.9)
	portal.name = "Portal"
	for i in 3:
		var s := add(root, sphere(0.06, 8), Color("333333"), Vector3(-0.2 + i * 0.2, 1.48, 0.15))
		s.name = "Socket%d" % i
	var l := OmniLight3D.new()
	l.light_color = Color("c58cff")
	l.omni_range = 5.0
	l.light_energy = 2.0
	l.position = Vector3(0, 0.9, 0.4)
	root.add_child(l)
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
