extends Node3D
## Заставка-история: эльфы прячут Сердце Долины в горе, кристаллы разлетаются,
## камера летит над долиной к юному искателю со свитком.
## Если есть voice/intro.(mp3|ogg|wav) — играет озвучку и подгоняет сцены под её длину.

signal finished

const MapGen = preload("res://scripts/world/map_gen.gd")
const Builder = preload("res://scripts/world/world_builder.gd")
const Models = preload("res://scripts/world/models.gd")

const LINES := [
	"Давным-давно, когда горы были молоды, в Долине жили древние хранители — эльфы-волшебники.",
	"Они создали Сердце Долины — сокровище, полное такой магии, что ею можно было бы зажечь звёзды.",
	"Чтобы оно не попало в недобрые руки, хранители спрятали его глубоко в горе и запечатали волшебным замком.",
	"Ключом стали три кристалла. Хранители разбили их на осколки и развеяли по лесам, холмам и рекам.",
	"Прошли века. Говорят, лишь тот, кто соберёт три осколка и дойдёт до горы, сможет открыть замок.",
	"И вот однажды юный искатель нашёл старый свиток… Твоё приключение начинается!",
]
var durs := [7.0, 8.0, 8.5, 8.0, 8.0, 7.0]

var map
var cam: Camera3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var gate: Node3D
var chest: Node3D
var elves: Array = []
var boy: Node3D
var look := Vector3.ZERO
var look_goal := Vector3.ZERO
var ui: CanvasLayer
var sub_lbl: Label
var fade: ColorRect
var _done := false
var _night := 1.0

func _ready() -> void:
	map = MapGen.new()
	map.generate(14, 30, 2024, 1)
	# в заставке ущелья нет: эльфы идут к горе по открытой поляне
	for z in range(map.gorge.x - 2, map.h):
		for x in map.w:
			var t := Vector2i(x, z)
			if map.get_t(t) == MapGen.ROCK or map.get_t(t) == MapGen.PATH or map.get_t(t) == MapGen.FOREST:
				map.set_t(t, MapGen.GRASS)
				map.top[z * map.w + x] = 0.0
	var tiles := Node3D.new()
	add_child(tiles)
	var info: Dictionary = Builder.build(map, tiles)
	(info["water_mat"] as ShaderMaterial).set_shader_parameter("darkness", 0.6)
	_setup_env()
	gate = Models.mountain_gate()
	gate.position = map.world_pos(map.shrine)
	add_child(gate)
	var gz: float = gate.position.z
	var gx: float = gate.position.x
	var robes := [Color("2f4a8a"), Color("4a7a5a"), Color("6a4a8a")]
	for i in 3:
		var e := Models.elf(robes[i])
		e.position = Vector3(gx - 0.8 + i * 0.8, 0, gz - 6.0 - absf(i - 1) * 0.5)
		add_child(e)
		elves.append(e)
	chest = Models.glowing_chest()
	chest.position = Vector3(gx, 0, gz - 5.6)
	add_child(chest)
	boy = Models.hero(DB.heroes[0])
	var start := Vector2i(map.w / 2, 2)
	boy.position = map.world_pos(start)
	boy.rotation.y = 0.0
	add_child(boy)
	var arm_r: Node3D = boy.get_node("Body/ArmR")
	var arm_l: Node3D = boy.get_node("Body/ArmL")
	arm_r.rotation = Vector3(-1.1, 0, 0.35)
	arm_l.rotation = Vector3(-1.1, 0, -0.35)
	boy.set("posing", true)
	var sc := Models.scroll()
	sc.name = "Scroll"
	sc.position = Vector3(0, 0.5, 0.26)
	boy.get_node("Body").add_child(sc)
	cam = Camera3D.new()
	cam.fov = 55
	cam.far = 200
	add_child(cam)
	cam.make_current()
	_build_ui()
	_run()

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.fog_enabled = true
	env.fog_density = 0.01
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 30
	add_child(sun)
	_set_night(1.0)

func _set_night(n: float) -> void:
	_night = n
	var day_top := Color(0.36, 0.56, 0.86)
	var day_hor := Color(0.95, 0.75, 0.6)
	var night_top := Color(0.02, 0.03, 0.1)
	var night_hor := Color(0.1, 0.1, 0.25)
	sky_mat.sky_top_color = day_top.lerp(night_top, n)
	sky_mat.sky_horizon_color = day_hor.lerp(night_hor, n)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = sky_mat.sky_top_color.darkened(0.5)
	env.ambient_light_energy = lerpf(0.5, 0.15, n)
	env.fog_light_color = sky_mat.sky_horizon_color
	sun.light_color = Color(1.0, 0.82, 0.62).lerp(Color(0.55, 0.62, 1.0), n)
	sun.light_energy = lerpf(0.95, 0.35, n)
	sun.rotation_degrees = Vector3(lerpf(-18.0, -40.0, n), lerpf(70.0, 20.0, n), 0)

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 30
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.85)
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size.y = 60
		if not top:
			bar.position.y = -60
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
	sub_lbl = Style.outlined(Style.label("", 30, Style.PARCH, Style.font_title), 10)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub_lbl.custom_minimum_size = Vector2(1080, 0)
	sub_lbl.position = Vector2(-540, -150)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sub_lbl)
	var skip := Style.glass_button(Style.button("Пропустить ▶▶", 20))
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.position = Vector2(-210, 10)
	skip.pressed.connect(_finish)
	root.add_child(skip)
	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_finish()

func _process(delta: float) -> void:
	look = look.lerp(look_goal, 1.0 - exp(-delta * 3.0))
	if cam.global_position.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)
	if chest and chest.visible:
		var g: OmniLight3D = chest.get_node("Glow")
		g.light_energy = 2.2 + sin(Time.get_ticks_msec() * 0.004) * 0.8

func _cam(pos: Vector3, target: Vector3, dur: float, instant := false) -> void:
	look_goal = target
	if instant:
		cam.position = pos
		look = target
		cam.look_at(look, Vector3.UP)
		return
	var tw := create_tween()
	tw.tween_property(cam, "position", pos, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _say(i: int) -> void:
	sub_lbl.text = LINES[i]
	sub_lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(sub_lbl, "modulate:a", 1.0, 0.5)
	tw.tween_interval(maxf(0.5, durs[i] - 1.1))
	tw.tween_property(sub_lbl, "modulate:a", 0.0, 0.5)

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _run() -> void:
	var vl: float = Settings.play_voice("intro")
	if vl > 5.0:
		var total := 0.0
		for d in durs:
			total += d
		for i in durs.size():
			durs[i] = durs[i] * vl / total
	var g := gate.position
	var tw0 := create_tween()
	tw0.tween_property(fade, "color:a", 0.0, 1.2)
	# 1. Ночь, лес, эльфы-хранители
	_cam(Vector3(g.x - 5, 6, g.z - 15), Vector3(g.x, 0.5, g.z - 6), 0, true)
	_cam(Vector3(g.x - 2.5, 2.4, g.z - 9.5), Vector3(g.x, 0.6, g.z - 5.5), durs[0])
	_say(0)
	_walk_elves(g.z - 3.2, durs[0] + durs[1])
	await _wait(durs[0])
	if _done: return
	# 2. Сердце Долины крупным планом
	_say(1)
	_cam(Vector3(g.x + 1.4, 1.3, chest.position.z - 0.6 + 1.8), chest.position + Vector3(0, 0.4, 0.8), durs[1] * 0.8)
	await _wait(durs[1])
	if _done: return
	# 3. Гора открывается, ларец уходит внутрь, ворота закрываются
	_say(2)
	_cam(Vector3(g.x + 0.5, 2.2, g.z - 5.0), Vector3(g.x, 1.1, g.z), durs[2] * 0.4)
	var sl: Node3D = gate.get_node("SlabL")
	var sr: Node3D = gate.get_node("SlabR")
	var inner: OmniLight3D = gate.get_node("Inner")
	var t3 := create_tween()
	t3.tween_property(sl, "position:x", -0.78, 1.5)
	t3.parallel().tween_property(sr, "position:x", 0.78, 1.5)
	t3.parallel().tween_property(inner, "light_energy", 3.0, 1.5)
	t3.tween_property(chest, "position", Vector3(g.x, 0.1, g.z + 0.6), durs[2] * 0.35)
	t3.parallel().tween_property(chest, "scale", Vector3.ONE * 0.4, durs[2] * 0.35)
	for e in elves:
		t3.parallel().tween_property(e, "position:z", g.z - 1.4, durs[2] * 0.35)
	t3.tween_callback(func(): chest.visible = false)
	t3.tween_property(sl, "position:x", -0.25, 1.2)
	t3.parallel().tween_property(sr, "position:x", 0.25, 1.2)
	t3.parallel().tween_property(inner, "light_energy", 0.0, 1.2)
	await _wait(durs[2])
	if _done: return
	# 4. Три кристалла-ключа разлетаются по долине
	_say(3)
	_cam(Vector3(g.x, 2.6, g.z - 3.2), Vector3(g.x, 2.1, g.z), durs[3] * 0.25)
	for i in 3:
		var s: MeshInstance3D = gate.get_node("Socket%d" % i)
		s.material_override = Models.mat(Color("7fe3ff"), 3.0)
	await _wait(durs[3] * 0.35)
	if _done: return
	for i in 3:
		var s: MeshInstance3D = gate.get_node("Socket%d" % i)
		var c := Models.shard()
		c.scale = Vector3.ONE * 0.6
		add_child(c)
		c.global_position = s.global_position + Vector3(0, -0.3, -0.1)
		s.material_override = Models.mat(Color("333333"))
		var dest := Vector3(randf_range(1, map.w - 2), 0.5, randf_range(4, map.h - 10))
		var mid := (c.global_position + dest) * 0.5 + Vector3(0, 6, 0)
		var a := c.global_position
		var tw := create_tween()
		tw.tween_method(func(k: float):
			c.global_position = a.lerp(mid, k).lerp(mid.lerp(dest, k), k), 0.0, 1.0, durs[3] * 0.55)
		tw.tween_callback(c.queue_free)
		Settings.play("shard", 0.1)
	_cam(Vector3(g.x, 7.0, g.z - 6.0), Vector3(g.x, 0, g.z - 14), durs[3] * 0.6)
	await _wait(durs[3] * 0.65)
	if _done: return
	# 5. Прошли века: рассвет, полёт над долиной
	_say(4)
	for e in elves:
		e.visible = false
	var t5 := create_tween()
	t5.tween_method(_set_night, 1.0, 0.0, durs[4] * 0.6)
	_cam(Vector3(g.x, 6.5, 8.0), Vector3(g.x, 0, 0), durs[4])
	await _wait(durs[4])
	if _done: return
	# 6. Юный искатель со свитком
	_say(5)
	var b := boy.position
	_cam(b + Vector3(0.5, 1.15, 1.6), b + Vector3(0, 0.85, 0), durs[5] * 0.6)
	await _wait(durs[5] * 0.75)
	if _done: return
	var sc: Node3D = boy.get_node("Body/Scroll")
	var t6 := create_tween()
	t6.tween_property(sc, "scale", Vector3(1.6, 1.6, 1.6), 0.6)
	fade.color = Color(1, 0.97, 0.88, 0)
	t6.parallel().tween_property(fade, "color:a", 1.0, durs[5] * 0.25)
	await t6.finished
	_finish()

func _walk_elves(target_z: float, dur: float) -> void:
	for e in elves:
		var tw := create_tween()
		tw.tween_property(e, "position:z", target_z - absf(e.position.x - gate.position.x) * 0.3, dur)
	var tc := create_tween()
	tc.tween_property(chest, "position:z", target_z + 0.3, dur)

func _finish() -> void:
	if _done:
		return
	_done = true
	Settings.stop_voice()
	finished.emit()
