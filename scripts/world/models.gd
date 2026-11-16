extends RefCounted
## Процедурные low-poly модели: герои, звери, сундуки, кристаллы, костры, святилище.
## Всё собирается из простых фигур, поэтому не нужны сторонние файлы.

const HeroAnim = preload("res://scripts/world/hero_anim.gd")
const Bobber = preload("res://scripts/world/bobber.gd")

static var _mats := {}
static var _toon: Shader
static var _outline: Shader

## Материал модели. Обычный цвет — мультяшный шейдер с обводкой; светящийся или прозрачный — стандартный.
## kind: 0 — с обводкой, 1 — без обводки (мелкие детали лица), 2 — обводка для кубиков.
static func mat(c: Color, emissive: float = 0.0, rough: float = 0.85, kind: int = 0) -> Material:
	var key := "%s|%.2f|%.2f|%d" % [c.to_html(), emissive, rough, kind]
	if _mats.has(key):
		return _mats[key]
	if emissive > 0.0 or c.a < 0.99:
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
	if _toon == null:
		_toon = load("res://shaders/toon.gdshader")
		_outline = load("res://shaders/outline.gdshader")
	var t := ShaderMaterial.new()
	t.shader = _toon
	t.set_shader_parameter("albedo", c)
	if kind != 1:
		var o := ShaderMaterial.new()
		o.shader = _outline
		o.set_shader_parameter("color", Color(c.r * 0.28, c.g * 0.24, c.b * 0.3))
		o.set_shader_parameter("box", 1.0 if kind == 2 else 0.0)
		t.next_pass = o
	_mats[key] = t
	return t

static func add(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, scl: Vector3 = Vector3.ONE,
		rot: Vector3 = Vector3.ZERO, emissive: float = 0.0, outline := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var kind := 0
	if not outline:
		kind = 1
	elif mesh is BoxMesh:
		kind = 2
	mi.material_override = mat(c, emissive, 0.85, kind)
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

## Мелкая деталь без обводки и без тени (глаза, брови, рот).
static func dot(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, scl: Vector3 = Vector3.ONE,
		rot: Vector3 = Vector3.ZERO, emissive: float = 0.0) -> MeshInstance3D:
	var mi := add(parent, mesh, c, pos, scl, rot, emissive, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func sphere(r: float, seg: int = 14, hemi := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * (1.0 if hemi else 2.0)
	m.is_hemisphere = hemi
	m.radial_segments = maxi(seg, 12)
	m.rings = maxi(6, seg / 2)
	return m

static func capsule(r: float, hgt: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(hgt, r * 2.0)
	m.radial_segments = 16
	m.rings = 6
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

static var _arcs := {}

## Изогнутая трубочка в плоскости XY: улыбка, закрытый глаз, бровь дугой. Углы в градусах.
static func arc(r: float, a0: float, a1: float, th: float, seg: int = 10) -> ArrayMesh:
	var key := "%.3f|%.0f|%.0f|%.3f" % [r, a0, a1, th]
	if _arcs.has(key):
		return _arcs[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := 6
	var rows: Array = []
	for i in seg + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / seg))
		var c := Vector3(cos(a) * r, sin(a) * r, 0.0)
		var radial := Vector3(cos(a), sin(a), 0.0)
		# к концам трубочка сужается
		var k := 0.45 + 0.55 * sin(PI * float(i) / seg)
		var row: Array = []
		for j in ring:
			var b := TAU * j / ring
			var nrm := radial * cos(b) + Vector3(0, 0, 1) * sin(b)
			row.append([c + nrm * th * k, nrm])
		rows.append(row)
	for i in seg:
		for j in ring:
			var j2 := (j + 1) % ring
			for v in [rows[i][j], rows[i][j2], rows[i + 1][j], rows[i][j2], rows[i + 1][j2], rows[i + 1][j]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	var m := st.commit()
	_arcs[key] = m
	return m

# ---------------------------------------------------------------- ГЕРОЙ
## Узлы для анимации: Body, Body/LegL, LegR, ArmL, ArmR, Torso, Head; лицо — Head/Face/(EyeL, EyeR, BrowL, BrowR, Mouth).
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
	var shoes := Color("5a3d2b")
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(0.072 * side, 0.27, 0)
		body.add_child(leg)
		add(leg, capsule(0.064, 0.27), pants, Vector3(0, -0.11, 0))
		add(leg, sphere(0.074, 14), shoes, Vector3(0, -0.232, 0.03), Vector3(1.0, 0.62, 1.45))
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 0.27, 0)
	body.add_child(torso)
	add(torso, capsule(0.152, 0.4), top, Vector3(0, 0.175, 0))
	add(torso, cyl(0.156, 0.156, 0.05, 20), top2, Vector3(0, 0.055, 0))
	add(torso, sphere(0.022, 8), Color("f1c40f"), Vector3(0, 0.055, 0.152), Vector3(1.2, 1.2, 0.6), Vector3.ZERO, 0.0, false)
	add(torso, capsule(0.02, 0.27), top2, Vector3(0, 0.185, 0.138), Vector3(1, 1, 0.5), Vector3.ZERO, 0.0, false)
	# воротник
	var collar := TorusMesh.new()
	collar.inner_radius = 0.075
	collar.outer_radius = 0.125
	collar.rings = 20
	collar.ring_segments = 8
	add(torso, collar, top2, Vector3(0, 0.335, 0), Vector3(1, 0.6, 1), Vector3.ZERO, 0.0, false)
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "ArmR" if side < 0 else "ArmL"  # герой смотрит в +Z: его правая рука на стороне −X
		arm.position = Vector3(0.19 * side, 0.555, 0)
		body.add_child(arm)
		add(arm, capsule(0.052, 0.25), top, Vector3(0, -0.1, 0))
		add(arm, cyl(0.056, 0.056, 0.03, 14), top2, Vector3(0, -0.19, 0), Vector3.ONE, Vector3.ZERO, 0.0, false)
		add(arm, sphere(0.056, 14), skin, Vector3(0, -0.238, 0))
		if side < 0:
			# деревянный меч в правой руке
			add(arm, cyl(0.014, 0.026, 0.44, 8), Color("b98248"), Vector3(0, -0.25, 0.2), Vector3(1, 1, 0.55), Vector3(1.5, 0, 0))
			add(arm, capsule(0.018, 0.13), Color("6b4424"), Vector3(0, -0.24, 0.03), Vector3.ONE, Vector3(0, 0, 1.5708))
		else:
			# деревянный щит в левой руке
			add(arm, cyl(0.125, 0.125, 0.03, 20), Color("9a6a36"), Vector3(0.055, -0.17, 0.02), Vector3.ONE, Vector3(0, 0, 1.5708))
			add(arm, cyl(0.128, 0.128, 0.018, 20), Color("d8dde2"), Vector3(0.05, -0.17, 0.02), Vector3.ONE, Vector3(0, 0, 1.5708), 0.0, false)
			add(arm, sphere(0.04, 10), Color("e8c36a"), Vector3(0.075, -0.17, 0.02), Vector3(0.5, 1, 1), Vector3.ZERO, 0.0, false)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.8, 0)
	body.add_child(head)
	add(head, sphere(0.235, 28), skin, Vector3.ZERO, Vector3(1.0, 0.96, 0.98))
	for side in [-1, 1]:
		add(head, sphere(0.045, 10), skin, Vector3(0.225 * side, -0.02, 0.0), Vector3(0.5, 1, 0.8), Vector3.ZERO, 0.0, false)
	_face(head, pr, hair)
	var hr := Node3D.new()
	hr.name = "Hair"
	hr.scale = Vector3.ONE * 1.17
	head.add_child(hr)
	_hair(hr, pr, hair)
	for c in hr.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_accessories(body, pr)
	root.set_script(HeroAnim)
	return root

## Лицо: глаза с веками, брови, румянец и набор ртов под эмоции.
static func _face(head: Node3D, pr: Dictionary, hair: Color) -> void:
	var face := Node3D.new()
	face.name = "Face"
	head.add_child(face)
	var dark := Color("23202f")
	var iris := Color(pr.get("eyes", "5a3b22"))
	var brow_c := hair.darkened(0.35)
	for side in [-1, 1]:
		var eye := Node3D.new()
		eye.name = "EyeL" if side < 0 else "EyeR"
		eye.position = Vector3(0.09 * side, -0.035, 0.196)
		eye.rotation.y = 0.33 * side
		face.add_child(eye)
		var open := Node3D.new()
		open.name = "Open"
		eye.add_child(open)
		dot(open, sphere(0.05, 16), Color("fbfbff"), Vector3.ZERO, Vector3(0.95, 1.2, 0.4))
		var ball := Node3D.new()
		ball.name = "Pupil"
		open.add_child(ball)
		dot(ball, sphere(0.036, 14), iris, Vector3(0, -0.004, 0.012), Vector3(1.0, 1.18, 0.4))
		dot(ball, sphere(0.022, 12), dark, Vector3(0, -0.004, 0.02), Vector3(1.0, 1.15, 0.4))
		dot(ball, sphere(0.012, 8), Color.WHITE, Vector3(0.013, 0.02, 0.028), Vector3(1, 1, 0.5), Vector3.ZERO, 1.6)
		dot(ball, sphere(0.006, 6), Color.WHITE, Vector3(-0.012, -0.018, 0.027), Vector3(1, 1, 0.5), Vector3.ZERO, 1.2)
		# ресничка-контур сверху
		dot(open, arc(0.05, 25.0, 155.0, 0.007), dark, Vector3(0, 0.006, 0.014), Vector3(0.98, 1.2, 1))
		# закрытый глаз: дуга «радости» и черта «ой»
		var happy := dot(eye, arc(0.042, 20.0, 160.0, 0.009), dark, Vector3(0, -0.022, 0.016))
		happy.name = "Happy"
		happy.visible = false
		var shut := dot(eye, capsule(0.009, 0.085), dark, Vector3(0, -0.004, 0.016), Vector3.ONE, Vector3(0, 0, 1.5708 + 0.3 * side))
		shut.name = "Shut"
		shut.visible = false
		var brow := Node3D.new()
		brow.name = "BrowL" if side < 0 else "BrowR"
		brow.position = Vector3(0.09 * side, 0.04, 0.208)
		brow.rotation.y = 0.33 * side
		face.add_child(brow)
		dot(brow, capsule(0.0105, 0.075), brow_c, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, 1.5708))
		dot(face, sphere(0.034, 10), Color("ff9f9f"), Vector3(0.142 * side, -0.098, 0.158), Vector3(1, 0.55, 0.35))
	dot(face, sphere(0.014, 8), Color(pr["skin"]).darkened(0.12), Vector3(0, -0.072, 0.226), Vector3(1, 0.8, 0.6))
	var mouth := Node3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0, -0.128, 0.203)
	face.add_child(mouth)
	var lip := Color("7a3b34")
	var m1 := dot(mouth, arc(0.045, 215.0, 325.0, 0.0085), lip, Vector3(0, 0.036, 0))
	m1.name = "Smile"
	var m2 := Node3D.new()
	m2.name = "Open"
	mouth.add_child(m2)
	dot(m2, sphere(0.04, 14), Color("5a1f24"), Vector3(0, -0.004, -0.006), Vector3(1.05, 0.9, 0.35))
	dot(m2, sphere(0.024, 10), Color("ff7f8a"), Vector3(0, -0.02, 0.0), Vector3(1.1, 0.6, 0.3))
	dot(m2, box(Vector3(0.05, 0.012, 0.006)), Color.WHITE, Vector3(0, 0.02, 0.006))
	var m3 := dot(mouth, arc(0.045, 40.0, 140.0, 0.0085), lip, Vector3(0, -0.05, 0))
	m3.name = "Frown"
	var m4 := dot(mouth, capsule(0.008, 0.06), lip, Vector3.ZERO, Vector3.ONE, Vector3(0, 0, 1.5708))
	m4.name = "Flat"
	var m5 := dot(mouth, sphere(0.02, 10), Color("5a1f24"), Vector3(0, -0.004, -0.002), Vector3(1, 1.15, 0.35))
	m5.name = "Oh"
	for c in mouth.get_children():
		c.visible = c.name == "Smile"

static func _hair_base(head: Node3D, hair: Color) -> void:
	add(head, sphere(0.214, 18, true), hair, Vector3(0, 0.035, -0.005), Vector3(1, 0.95, 1))
	add(head, sphere(0.206, 16), hair, Vector3(0, -0.03, -0.055), Vector3(1.03, 1.0, 0.85))
	_bangs(head, hair)

## Чёлка: три мягких пряди надо лбом.
static func _bangs(head: Node3D, hair: Color) -> void:
	for x in [-0.1, 0.0, 0.1]:
		add(head, sphere(0.08, 12), hair, Vector3(x, 0.1 - absf(x) * 0.25, 0.14 - absf(x) * 0.3), Vector3(1.0, 0.6, 0.62), Vector3(0.35, 0, -x * 2.0), 0.0, false)

static func _hair(head: Node3D, pr: Dictionary, hair: Color) -> void:
	var st: String = pr["style"]
	var hat_col := Color(pr["hat"]) if pr["hat"] != "" else hair
	match st:
		"cap":
			_hair_base(head, hair)
			add(head, sphere(0.226, 18, true), hat_col, Vector3(0, 0.06, -0.005))
			add(head, cyl(0.15, 0.15, 0.022, 20), hat_col.darkened(0.08), Vector3(0, 0.075, 0.13), Vector3(1.0, 1.0, 0.95), Vector3(0.1, 0, 0))
			add(head, sphere(0.05, 8), Color.WHITE, Vector3(0, 0.15, 0.17), Vector3(1, 1, 0.4))
		"hood":
			_bangs(head, hair)
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
				var head: Node3D = body.get_node("Head/Hair")
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
			var c := Color("d39a55")
			var lt := Color("f6e2c4")
			add(root, capsule(0.095, 0.36), c, Vector3(0, 0.2, 0), Vector3.ONE, Vector3(1.5708, 0, 0))
			var head := _node(root, "Head", Vector3(0, 0.33, 0.2))
			add(head, sphere(0.105, 16), c, Vector3.ZERO)
			add(head, sphere(0.055, 12), lt, Vector3(0, -0.03, 0.085), Vector3(1.1, 0.8, 1))
			dot(head, sphere(0.022, 8), eye, Vector3(0, -0.01, 0.135), Vector3(1.2, 0.9, 0.8))
			dot(head, sphere(0.018, 8), Color("ff7f8a"), Vector3(0, -0.06, 0.115), Vector3(1, 1.3, 0.5))
			for side in [-1, 1]:
				add(head, sphere(0.045, 10), c.darkened(0.3), Vector3(0.09 * side, 0.03, -0.01), Vector3(0.5, 1.3, 0.9), Vector3(0, 0, 0.35 * side))
				_eye(head, Vector3(0.042 * side, 0.03, 0.085), 0.022, Color("5a3b22"), side, false)
				for fz in [-0.12, 0.12]:
					add(root, capsule(0.03, 0.17), c.darkened(0.15), Vector3(0.065 * side, 0.085, fz))
			var tail := _node(root, "Tail", Vector3(0, 0.27, -0.19))
			add(tail, capsule(0.022, 0.16), c, Vector3(0, 0.05, -0.03), Vector3.ONE, Vector3(-0.6, 0, 0))
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
			var w := Color("f7f4ea")
			var b := Color("34303a")
			add(root, capsule(0.15, 0.48), w, Vector3(0, 0.31, 0), Vector3.ONE, Vector3(1.5708, 0, 0))
			dot(root, sphere(0.08, 10), b, Vector3(0.1, 0.36, 0.05), Vector3(0.6, 1, 1.3))
			dot(root, sphere(0.07, 10), b, Vector3(-0.11, 0.33, -0.1), Vector3(0.6, 1, 1.2))
			var head := _node(root, "Head", Vector3(0, 0.42, 0.29))
			add(head, sphere(0.11, 16), w, Vector3.ZERO, Vector3(1, 1.05, 1))
			add(head, sphere(0.075, 12), Color("f6a9b8"), Vector3(0, -0.05, 0.07), Vector3(1.2, 0.75, 0.9))
			for side in [-1, 1]:
				dot(head, sphere(0.012, 6), Color("b06a7a"), Vector3(0.03 * side, -0.05, 0.135))
				add(head, cyl(0.0, 0.025, 0.08, 8), Color("f4ecd8"), Vector3(0.065 * side, 0.115, 0.0), Vector3.ONE, Vector3(0, 0, -0.6 * side))
				add(head, sphere(0.04, 8), w, Vector3(0.115 * side, 0.04, -0.01), Vector3(1.2, 0.6, 0.8))
				_eye(head, Vector3(0.048 * side, 0.025, 0.09), 0.022, Color("3a2a20"), side, false)
				for fz in [-0.15, 0.15]:
					add(root, capsule(0.038, 0.22), w.darkened(0.08), Vector3(0.09 * side, 0.11, fz))
					dot(root, sphere(0.04, 8), b, Vector3(0.09 * side, 0.025, fz), Vector3(1, 0.6, 1.1))
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
## Глаз зверя: белок, зрачок, блик и хмурая бровь.
static func _eye(parent: Node3D, pos: Vector3, r: float, iris: Color, side: float, angry := true, glow := 0.0) -> void:
	var e := Node3D.new()
	e.position = pos
	e.rotation.y = 0.35 * side
	parent.add_child(e)
	dot(e, sphere(r, 12), Color("fbfbff") if glow <= 0.0 else iris, Vector3.ZERO, Vector3(1, 1.1, 0.45), Vector3.ZERO, glow)
	if glow <= 0.0:
		dot(e, sphere(r * 0.68, 10), iris, Vector3(0, -r * 0.08, r * 0.2), Vector3(1, 1.1, 0.45))
	dot(e, sphere(r * 0.38, 8), Color("16141f"), Vector3(0, -r * 0.08, r * 0.36), Vector3(0.8, 1.2, 0.45))
	dot(e, sphere(r * 0.22, 6), Color.WHITE, Vector3(r * 0.25, r * 0.3, r * 0.5), Vector3(1, 1, 0.5), Vector3.ZERO, 1.5)
	if angry:
		dot(e, capsule(r * 0.24, r * 2.3), Color("1d1a22"), Vector3(0, r * 0.95, r * 0.3), Vector3.ONE, Vector3(0, 0, 1.5708 + 0.42 * side))

static func _node(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	return n

static func beast(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"wolf":
			var g := Color("8a8f9c")
			var d := Color("5c6070")
			var lt := Color("d9dde6")
			add(root, capsule(0.13, 0.5), g, Vector3(0, 0.31, -0.02), Vector3(1, 1, 1.0), Vector3(1.5708, 0, 0))
			add(root, sphere(0.125, 14), lt, Vector3(0, 0.27, 0.13), Vector3(0.85, 0.8, 0.9), Vector3.ZERO, 0.0, false)
			var head := _node(root, "Head", Vector3(0, 0.45, 0.27))
			add(head, sphere(0.135, 18), g, Vector3.ZERO, Vector3(1.05, 0.95, 1.0))
			add(head, capsule(0.062, 0.2), lt, Vector3(0, -0.04, 0.12), Vector3(1.1, 0.85, 1), Vector3(1.5708, 0, 0))
			add(head, sphere(0.03, 10), Color("1d1a22"), Vector3(0, -0.02, 0.215), Vector3(1.2, 0.9, 1), Vector3.ZERO, 0.0, false)
			for side in [-1, 1]:
				add(head, cyl(0.0, 0.055, 0.15, 10), d, Vector3(0.075 * side, 0.14, -0.02), Vector3(1, 1, 0.6), Vector3(-0.15, 0, -0.25 * side))
				dot(head, cyl(0.0, 0.03, 0.09, 8), Color("e7a9a9"), Vector3(0.075 * side, 0.125, 0.002), Vector3(1, 1, 0.4), Vector3(-0.15, 0, -0.25 * side))
				_eye(head, Vector3(0.062 * side, 0.03, 0.105), 0.03, Color("ffd23a"), side)
				dot(head, cyl(0.0, 0.012, 0.035, 6), Color.WHITE, Vector3(0.03 * side, -0.085, 0.17), Vector3.ONE, Vector3(PI, 0, 0))
				# щёчный пух
				add(head, cyl(0.0, 0.05, 0.1, 8), g, Vector3(0.115 * side, -0.03, 0.0), Vector3(1, 1, 0.6), Vector3(0, 0, -1.9 * side), 0.0, false)
				for fz in [-0.17, 0.15]:
					add(root, capsule(0.04, 0.24), d, Vector3(0.085 * side, 0.12, fz))
					add(root, sphere(0.048, 10), lt, Vector3(0.085 * side, 0.03, fz + 0.015), Vector3(1, 0.6, 1.25), Vector3.ZERO, 0.0, false)
			var tail := _node(root, "Tail", Vector3(0, 0.36, -0.27))
			add(tail, capsule(0.06, 0.32), g, Vector3(0, 0.06, -0.12), Vector3.ONE, Vector3(-1.0, 0, 0))
			add(tail, sphere(0.055, 10), lt, Vector3(0, 0.15, -0.25), Vector3.ONE, Vector3.ZERO, 0.0, false)
		"boar":
			var b := Color("7a543a")
			var dk := b.darkened(0.3)
			add(root, sphere(0.21, 18), b, Vector3(0, 0.29, -0.02), Vector3(1, 0.92, 1.35))
			var head := _node(root, "Head", Vector3(0, 0.3, 0.27))
			add(head, sphere(0.15, 16), b, Vector3.ZERO, Vector3(1.05, 1.0, 1.0))
			add(head, cyl(0.07, 0.085, 0.1, 14), Color("e2a898"), Vector3(0, -0.03, 0.14), Vector3(1.1, 1, 1), Vector3(1.5708, 0, 0))
			for side in [-1, 1]:
				dot(head, sphere(0.014, 6), Color("5a2f2a"), Vector3(0.028 * side, -0.03, 0.192))
				add(head, cyl(0.0, 0.024, 0.14, 8), Color("fff6e0"), Vector3(0.085 * side, -0.035, 0.15), Vector3.ONE, Vector3(0.75, 0, -0.3 * side))
				add(head, cyl(0.0, 0.055, 0.11, 8), dk, Vector3(0.09 * side, 0.13, -0.03), Vector3(1, 1, 0.5), Vector3(-0.3, 0, -0.5 * side))
				_eye(head, Vector3(0.065 * side, 0.05, 0.118), 0.027, Color("ff6a3a"), side)
				for fz in [-0.15, 0.13]:
					add(root, capsule(0.042, 0.18), dk, Vector3(0.105 * side, 0.09, fz))
			for k in 5:
				add(root, cyl(0.0, 0.035, 0.11, 6), Color("3a2a1e"), Vector3(0, 0.49 - k * 0.012, 0.16 - k * 0.09), Vector3(0.6, 1, 1), Vector3(-0.35, 0, 0))
			var tail := _node(root, "Tail", Vector3(0, 0.34, -0.29))
			add(tail, capsule(0.014, 0.12), dk, Vector3(0, 0.03, -0.04), Vector3.ONE, Vector3(-0.9, 0, 0))
		"bear":
			var br := Color("7a4e2e")
			var dk := br.darkened(0.3)
			var lt := Color("d1aa80")
			add(root, sphere(0.3, 20), br, Vector3(0, 0.4, 0), Vector3(1.0, 0.95, 1.35))
			add(root, sphere(0.22, 14), lt, Vector3(0, 0.33, 0.14), Vector3(0.8, 0.75, 0.9), Vector3.ZERO, 0.0, false)
			var head := _node(root, "Head", Vector3(0, 0.6, 0.4))
			add(head, sphere(0.2, 20), br, Vector3.ZERO)
			add(head, sphere(0.095, 14), lt, Vector3(0, -0.05, 0.16), Vector3(1.1, 0.8, 1))
			add(head, sphere(0.036, 10), Color("1d1a2b"), Vector3(0, -0.02, 0.245), Vector3(1.2, 0.85, 0.8), Vector3.ZERO, 0.0, false)
			dot(head, arc(0.035, 215.0, 325.0, 0.007), Color("3a2418"), Vector3(0, -0.045, 0.247))
			for side in [-1, 1]:
				add(head, sphere(0.07, 12), br, Vector3(0.135 * side, 0.16, -0.03))
				dot(head, sphere(0.04, 10), lt, Vector3(0.135 * side, 0.16, 0.012), Vector3(1, 1, 0.5))
				_eye(head, Vector3(0.08 * side, 0.045, 0.162), 0.03, Color("5a3b22"), side)
				for fz in [-0.2, 0.22]:
					add(root, capsule(0.08, 0.34), dk, Vector3(0.17 * side, 0.16, fz))
					add(root, sphere(0.085, 10), dk, Vector3(0.17 * side, 0.04, fz + 0.03), Vector3(1, 0.5, 1.2), Vector3.ZERO, 0.0, false)
			var tail := _node(root, "Tail", Vector3(0, 0.45, -0.4))
			add(tail, sphere(0.06, 10), dk, Vector3.ZERO)
			root.scale = Vector3.ONE * 0.95
		"guardian":
			var st := Color("9aa0aa")
			var st2 := Color("7c8390")
			var moss := Color("6f9a5c")
			var glow := Color("5ff3ff")
			add(root, sphere(0.27, 12), st, Vector3(0, 0.6, 0), Vector3(1.0, 1.1, 0.8))
			add(root, sphere(0.2, 12), st2, Vector3(0, 0.36, 0), Vector3(1.0, 0.8, 0.8))
			add(root, cyl(0.0, 0.07, 0.12, 6), glow, Vector3(0, 0.66, 0.2), Vector3(1, 1, 0.5), Vector3.ZERO, 2.5)
			add(root, cyl(0.07, 0.0, 0.1, 6), glow, Vector3(0, 0.55, 0.2), Vector3(1, 1, 0.5), Vector3.ZERO, 2.5)
			var head := _node(root, "Head", Vector3(0, 0.98, 0.02))
			add(head, sphere(0.17, 12), st, Vector3.ZERO, Vector3(1.05, 0.9, 0.95))
			add(head, sphere(0.175, 12, true), moss, Vector3(0, 0.03, 0), Vector3(1.05, 0.7, 0.98))
			add(head, capsule(0.03, 0.22), st2, Vector3(0, 0.035, 0.13), Vector3.ONE, Vector3(0, 0, 1.5708), 0.0, false)
			for side in [-1, 1]:
				dot(head, sphere(0.032, 10), glow, Vector3(0.065 * side, -0.02, 0.145), Vector3(1.2, 0.55, 0.5), Vector3(0, 0, 0.25 * side), 3.0)
				add(root, sphere(0.13, 12), st2, Vector3(0.3 * side, 0.76, 0))
				dot(root, sphere(0.09, 10, true), moss, Vector3(0.3 * side, 0.82, 0), Vector3(1.3, 0.6, 1.3))
				add(root, capsule(0.085, 0.42), st, Vector3(0.36 * side, 0.52, 0.02), Vector3.ONE, Vector3(0, 0, 0.14 * side))
				add(root, sphere(0.11, 12), st2, Vector3(0.39 * side, 0.3, 0.03))
				add(root, capsule(0.095, 0.3), st2, Vector3(0.13 * side, 0.16, 0))
				add(root, sphere(0.11, 12), st, Vector3(0.13 * side, 0.05, 0.03), Vector3(1, 0.55, 1.25), Vector3.ZERO, 0.0, false)
	root.scale = root.scale * 1.3
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
	add(root, cyl(0.09, 0.25, 0.62, 16), robe, Vector3(0, 0.31, 0))
	add(root, cyl(0.255, 0.255, 0.04, 16), robe.darkened(0.2), Vector3(0, 0.02, 0), Vector3.ONE, Vector3.ZERO, 0.0, false)
	add(root, cyl(0.1, 0.1, 0.05, 14), Color("e8c36a"), Vector3(0, 0.5, 0), Vector3.ONE, Vector3.ZERO, 0.0, false)
	for side in [-1, 1]:
		add(root, capsule(0.045, 0.26), robe.lightened(0.06), Vector3(0.15 * side, 0.46, 0.02), Vector3.ONE, Vector3(0, 0, 0.3 * side))
		add(root, sphere(0.045, 10), skin, Vector3(0.19 * side, 0.34, 0.03))
	var head := _node(root, "Head", Vector3(0, 0.8, 0))
	add(head, sphere(0.17, 20), skin, Vector3.ZERO)
	add(head, sphere(0.185, 18, true), robe.darkened(0.15), Vector3(0, 0.03, -0.01))
	add(head, cyl(0.0, 0.13, 0.36, 12), robe.darkened(0.15), Vector3(0, 0.26, -0.07), Vector3.ONE, Vector3(-0.45, 0, 0))
	dot(head, sphere(0.035, 8), Color("ffe58a"), Vector3(0, 0.41, -0.16), Vector3.ONE, Vector3.ZERO, 2.0)
	for side in [-1, 1]:
		add(head, cyl(0.0, 0.035, 0.17, 8), skin, Vector3(0.19 * side, 0.02, -0.01), Vector3(1, 1, 0.5), Vector3(0, 0, -1.15 * side))
		_eye(head, Vector3(0.062 * side, -0.01, 0.145), 0.032, Color("3fb6e8"), side, false)
		dot(head, sphere(0.024, 8), Color("ffb0b0"), Vector3(0.1 * side, -0.06, 0.125), Vector3(1, 0.55, 0.35))
	dot(head, arc(0.035, 215.0, 325.0, 0.007), Color("7a3b34"), Vector3(0, -0.045, 0.16))
	add(root, cyl(0.016, 0.022, 1.05, 8), Color("7a5430"), Vector3(0.24, 0.52, 0.05))
	add(root, sphere(0.065, 12), Color("8fe8ff"), Vector3(0.24, 1.1, 0.05), Vector3.ONE, Vector3.ZERO, 3.0)
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
	add(root, sphere(0.2, 9), Color("8e8a82"), Vector3(0, 0.26, 0), Vector3(0.85, 1.45, 0.6), Vector3(0, 0.3, 0.05))
	add(root, sphere(0.16, 8), Color("79756e"), Vector3(0.02, 0.06, 0), Vector3(1.3, 0.5, 1.0))
	dot(root, arc(0.07, 0.0, 300.0, 0.012), Color("8fe8ff"), Vector3(0, 0.3, 0.115), Vector3.ONE, Vector3(0, 0.3, 0), 2.2)
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
	var red := Color("c8392c")
	var dark := Color("7a1c22")
	var belly := Color("d9a35a")
	var horn := Color("efe3c4")
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	add(body, sphere(0.9, 20), red, Vector3(0, 1.1, 0), Vector3(1.0, 0.85, 1.35))
	add(body, sphere(0.6, 14), red, Vector3(0, 1.2, 0.75), Vector3(0.9, 0.8, 1.0))
	add(body, sphere(0.72, 16), belly, Vector3(0, 0.82, 0.32), Vector3(0.86, 0.66, 1.15))
	add(body, sphere(0.45, 14), belly, Vector3(0, 1.15, 0.98), Vector3(0.7, 0.8, 0.6), Vector3.ZERO, 0.0, false)
	# шипы вдоль спины
	for i in 6:
		add(body, cyl(0.0, 0.13, 0.34, 4), horn, Vector3(0, 1.85 - i * 0.04, -0.7 + i * 0.28), Vector3.ONE, Vector3(0.25, 0, 0))
	# лапы
	for sx in [-1, 1]:
		for sz in [-0.55, 0.65]:
			add(body, capsule(0.19, 0.75), dark, Vector3(0.62 * sx, 0.4, sz))
			add(body, sphere(0.22, 12), dark, Vector3(0.62 * sx, 0.08, sz + 0.1), Vector3(1, 0.5, 1.3))
			for cl in [-1, 0, 1]:
				dot(body, cyl(0.0, 0.04, 0.12, 6), horn, Vector3(0.62 * sx + cl * 0.1, 0.05, sz + 0.36), Vector3.ONE, Vector3(1.5708, 0, 0))
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
	add(head, sphere(0.36, 18), red, Vector3(0, 0.02, 0.08), Vector3(0.95, 0.75, 1.1))
	add(head, sphere(0.26, 14), red, Vector3(0, -0.04, 0.42), Vector3(0.9, 0.62, 1.1))
	var jaw := add(head, sphere(0.25, 14), dark, Vector3(0, -0.2, 0.32), Vector3(0.9, 0.36, 1.25))
	jaw.name = "Jaw"
	for sx in [-1, 1]:
		add(head, cyl(0.0, 0.09, 0.55, 5), horn, Vector3(0.24 * sx, 0.33, -0.12), Vector3.ONE, Vector3(-0.6, 0, -0.25 * sx))
		add(head, cyl(0.0, 0.04, 0.16, 4), horn, Vector3(0.15 * sx, -0.2, 0.55), Vector3.ONE, Vector3(3.14, 0, 0))
	var eyes := Node3D.new()
	eyes.name = "Eyes"
	head.add_child(eyes)
	for sx in [-1, 1]:
		add(eyes, sphere(0.085, 12), Color("ffd23a"), Vector3(0.25 * sx, 0.1, 0.42), Vector3(0.6, 1, 1), Vector3.ZERO, 3.0)
		dot(eyes, sphere(0.04, 8), Color("1a0f0f"), Vector3(0.29 * sx, 0.1, 0.45), Vector3(0.5, 1.5, 0.6))
		dot(eyes, capsule(0.03, 0.24), Color("3a0d0d"), Vector3(0.26 * sx, 0.2, 0.44), Vector3.ONE, Vector3(1.2, 0, 0))
		dot(head, sphere(0.03, 8), Color("2a0808"), Vector3(0.12 * sx, 0.06, 0.57))
	# крылья: три перепонки веером и косточки между ними
	var memb := Color("9a2a4a")
	for sx in [-1, 1]:
		var wing := Node3D.new()
		wing.name = "WingL" if sx < 0 else "WingR"
		wing.position = Vector3(0.5 * sx, 1.55, 0.05)
		wing.rotation.z = 0.22 * sx
		body.add_child(wing)
		for k in 3:
			var ang: float = (0.55 - k * 0.6) * sx
			var fan := Node3D.new()
			fan.rotation.y = ang
			wing.add_child(fan)
			var ln: float = 1.75 - k * 0.22
			add(fan, sphere(0.5, 14), memb.darkened(k * 0.06), Vector3(ln * 0.5 * sx, 0.0, -0.18), Vector3(ln, 0.05, 0.72))
			add(fan, capsule(0.045, ln), dark, Vector3(ln * 0.5 * sx, 0.03, 0.0), Vector3.ONE, Vector3(0, 0, 1.5708))
			add(fan, cyl(0.0, 0.045, 0.16, 6), horn, Vector3(ln * sx, 0.03, 0.02), Vector3.ONE, Vector3(0, 0, -1.5708 * sx), 0.0, false)
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
