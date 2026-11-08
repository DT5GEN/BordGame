extends Node3D
## Короткая заставка между главами кампании под озвучку voice/story<N>.mp3.
## kind 0: Лето→Осень, 1: Осень→Зима, 2: Зима→Битва с драконом.
## Субтитры берутся из voice/story<N>.json: "lines" (тексты фраз) и "starts" (время начала каждой).
## Если "lines" нет — показываем только название главы.

signal finished

const Models = preload("res://scripts/world/models.gd")

const TITLES := ["Лето уходит…", "Приходит зима…", "Пещера дракона"]
const GROUND := [[Color("5c9a3c"), Color("b8742a")], [Color("b8742a"), Color("e8eef6")], [Color("e8eef6"), Color("3a2a2a")]]
const SKY := [[Color("7fc4ee"), Color("e0a060")], [Color("e0a060"), Color("a8c0dc")], [Color("a8c0dc"), Color("3a1410")]]

var kind := 0
var cam: Camera3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var ground_mat: StandardMaterial3D
var gate: Node3D
var dragon: Node3D
var fire: OmniLight3D
var parts: GPUParticles3D
var sub_lbl: Label
var title_lbl: Label
var fade: ColorRect
var lines: Array = []
var starts: Array = []
var length := 30.0
var t := 0.0
var _done := false
var _shake := 0.0

func _ready() -> void:
	var tm: Dictionary = Settings.voice_timing("story%d" % (kind + 1))
	lines = tm.get("lines", [])
	starts = tm.get("starts", [])
	length = float(tm.get("end", 30.0)) + 1.5
	_build()
	var l: float = Settings.play_voice("story%d" % (kind + 1))
	if l > 0.0:
		length = maxf(length, l + 1.5)

func _build() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	var sk := Sky.new()
	sk.sky_material = sky_mat
	env.sky = sk
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_density = 0.01
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	ground_mat = StandardMaterial3D.new()
	ground.material_override = ground_mat
	add_child(ground)
	gate = Models.mountain_gate()
	gate.position = Vector3(0, 0, -18)
	add_child(gate)
	# холмы и кусты по сторонам — просто чтобы было что проплывать мимо
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + kind
	for i in 40:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = rng.randf_range(0.5, 1.4)
		s.height = s.radius * 1.6
		m.mesh = s
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("3c7a30")
		m.material_override = mat
		m.position = Vector3(rng.randf_range(-14, 14), s.radius * 0.5, rng.randf_range(-16, 8))
		if absf(m.position.x) < 2.0:
			m.position.x += 4.0 * signf(m.position.x + 0.01)
		m.set_meta("bush", mat)
		add_child(m)
	# частицы: листья/снег/искры
	parts = GPUParticles3D.new()
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(14, 0.5, 14)
	pmat.gravity = Vector3(0.6, -1.2 if kind != 2 else 1.5, 0.0)
	pmat.initial_velocity_min = 0.2
	pmat.initial_velocity_max = 0.8
	pmat.angular_velocity_min = -120.0
	pmat.angular_velocity_max = 120.0
	parts.process_material = pmat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.25, 0.25) if kind != 1 else Vector2(0.1, 0.1)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = [Color("d9822b"), Color("ffffff"), Color("ff8a2a")][kind]
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if kind == 2:
		qmat.emission_enabled = true
		qmat.emission = qmat.albedo_color
	qm.material = qmat
	parts.draw_pass_1 = qm
	parts.amount = 220
	parts.lifetime = 6.0
	parts.preprocess = 6.0
	parts.position = Vector3(0, 7.0 if kind != 2 else 0.2, -4)
	parts.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	add_child(parts)
	if kind == 2:
		dragon = Models.dragon()
		dragon.position = Vector3(0, -5.0, -11)
		dragon.scale = Vector3.ONE * 1.6
		add_child(dragon)
		fire = OmniLight3D.new()
		fire.light_color = Color("ff5a1a")
		fire.omni_range = 30.0
		fire.light_energy = 0.0
		fire.position = Vector3(0, 3, -9)
		add_child(fire)
	cam = Camera3D.new()
	cam.fov = 60
	cam.current = true
	add_child(cam)
	# интерфейс
	var ui := CanvasLayer.new()
	add_child(ui)
	title_lbl = Label.new()
	title_lbl.text = TITLES[kind]
	title_lbl.add_theme_font_size_override("font_size", 52)
	title_lbl.add_theme_color_override("font_color", Color("fff4d8"))
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title_lbl.add_theme_constant_override("outline_size", 10)
	title_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_lbl.position.y = 48
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ui.add_child(title_lbl)
	sub_lbl = Label.new()
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 30)
	sub_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub_lbl.add_theme_constant_override("outline_size", 8)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sub_lbl.offset_top = -170
	sub_lbl.offset_bottom = -30
	sub_lbl.offset_left = 80
	sub_lbl.offset_right = -80
	ui.add_child(sub_lbl)
	var skip := Button.new()
	skip.text = "Пропустить ▶"
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.position = Vector2(-190, 14)
	skip.pressed.connect(_finish)
	ui.add_child(skip)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)

func _process(dt: float) -> void:
	t += dt
	var k := clampf(t / length, 0.0, 1.0)
	var ks := smoothstep(0.0, 1.0, k)
	var g: Array = GROUND[kind]
	var sk: Array = SKY[kind]
	ground_mat.albedo_color = (g[0] as Color).lerp(g[1], ks)
	var sc: Color = (sk[0] as Color).lerp(sk[1], ks)
	sky_mat.sky_top_color = sc
	sky_mat.sky_horizon_color = sc.lightened(0.25)
	sky_mat.ground_horizon_color = sc.lightened(0.1)
	sky_mat.ground_bottom_color = sc.darkened(0.4)
	env.fog_light_color = sc
	# камера: медленный подлёт к горе
	var z := lerpf(10.0, -3.0, ks)
	var h := lerpf(3.2, 2.0, ks)
	cam.position = Vector3(sin(t * 0.25) * 1.2, h, z)
	if kind == 2:
		# последняя треть: гора трескается, дракон поднимается
		var r := clampf((k - 0.45) / 0.55, 0.0, 1.0)
		dragon.position.y = lerpf(-5.0, 0.0, smoothstep(0.0, 1.0, r))
		fire.light_energy = r * 5.0 + (randf() * 1.2 if r > 0.2 else 0.0)
		if r > 0.55 and int(t * 3.0) % 5 == 0:
			_shake = 0.18
		var jaw := dragon.get_node_or_null("Body/Neck/Head/Jaw")
		if jaw:
			jaw.rotation.x = r * 0.5 * (0.5 + 0.5 * sin(t * 6.0))
	_shake = maxf(0.0, _shake - dt * 0.5)
	cam.position += Vector3(randf() - 0.5, randf() - 0.5, 0) * _shake
	cam.look_at(Vector3(0, 3.0 if kind != 2 else 2.5 + k * 1.2, -18))
	# кусты желтеют / белеют вместе с сезоном
	for c in get_children():
		if c is MeshInstance3D and c.has_meta("bush"):
			var mat: StandardMaterial3D = c.get_meta("bush")
			var from: Color = [Color("3c7a30"), Color("b8742a"), Color("e8eef6")][kind]
			var to: Color = [Color("c8821e"), Color("e8eef6"), Color("3a2a2a")][kind]
			mat.albedo_color = from.lerp(to, ks)
	# субтитры
	var idx := -1
	for i in starts.size():
		if t >= float(starts[i]):
			idx = i
	sub_lbl.text = String(lines[idx]) if idx >= 0 and idx < lines.size() else ""
	# затемнение в начале и конце
	var a := 1.0 - clampf(t / 0.8, 0.0, 1.0)
	a = maxf(a, clampf((t - (length - 1.0)) / 1.0, 0.0, 1.0))
	fade.color.a = a
	if t >= length and not _done:
		_finish()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e.keycode == KEY_ESCAPE or e.keycode == KEY_SPACE):
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	Settings.stop_voice()
	finished.emit()
