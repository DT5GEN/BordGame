extends Node3D
## Главный контроллер партии: карта, игроки, ходы, туман войны, день/ночь, ловушки, бои.

signal exit_to_menu
signal restart_game

const MapGen = preload("res://scripts/world/map_gen.gd")
const Models = preload("res://scripts/world/models.gd")
const Builder = preload("res://scripts/world/world_builder.gd")
const HUD = preload("res://scripts/ui/hud.gd")
const Papyrus = preload("res://scripts/ui/papyrus.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

const MAX_HP := 20
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var cfg: Dictionary = {}
var map
var info: Dictionary = {}
var rng := RandomNumberGenerator.new()
var players: Array = []
var cur := 0
var round_no := 1
var hour := 8.0
var hours_per_round := 1.5
var night := false
var dark_row := -1
var dark_speed := 1
var traps: Array = []
var objects := {}
var steps_left := 0
var rolled := false
var busy := false
var mode := "move"
var pending_card := -1
var trap_targets := {}
var reach := {}
var prev := {}
var targets := {}
var game_over := false
var weather := "Ясно"
var wind := 0.3
var n_shards_total := 0

var cam: Camera3D
var cam_target := Vector3.ZERO
var cam_goal := Vector3.ZERO
var cam_dist := 8.5
var cam_pitch := deg_to_rad(50.0)
var cam_yaw := 0.0
var follow: Node3D = null
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var darkness: MeshInstance3D
var rain: CPUParticles3D
var hl_mm: MultiMesh
var fog_mm: MultiMesh
var haze_mm: MultiMesh
var view_first := false
var fp_yaw := 0.0
var fp_pitch := -0.35
var settings_panel
var _in_fight := false
var entities: Node3D
var shrine_node: Node3D
var hud
var papyrus
var _time_shown := 8.0

var _press := false
var _press_pos := Vector2.ZERO
var _dragging := false
var _touches := {}
var _pinch_d := 0.0

# ================================================================= СОЗДАНИЕ
func _ready() -> void:
	rng.randomize()
	var sz: Vector2i = cfg.get("size", Vector2i(28, 64))
	map = MapGen.new()
	map.generate(sz.x, sz.y, cfg.get("seed", rng.randi()), cfg["players"].size())
	_setup_env()
	var tiles := Node3D.new()
	tiles.name = "Tiles"
	add_child(tiles)
	info = Builder.build(map, tiles)
	entities = Node3D.new()
	entities.name = "Entities"
	add_child(entities)
	_spawn_objects()
	_setup_players()
	_setup_highlight()
	_setup_fog()
	_setup_darkness_and_rain()
	_setup_camera()
	var expected: float = map.h * 1.35 / 5.5
	hours_per_round = 13.0 / maxf(1.0, expected * 0.6)
	dark_speed = maxi(1, int(round(map.h / 35.0)))
	hud = HUD.new()
	hud.game = self
	add_child(hud)
	papyrus = Papyrus.new()
	add_child(papyrus)
	settings_panel = SettingsPanel.new()
	add_child(settings_panel)
	settings_panel.view_changed.connect(func(first): _set_view(first, false))
	hud.settings_requested.connect(func(): settings_panel.open(players[cur].name))
	hud.view_toggle_requested.connect(func(): _set_view(not view_first, true))
	hud.roll_requested.connect(roll)
	hud.end_turn_requested.connect(end_turn)
	hud.trap_card_chosen.connect(start_trap_mode)
	hud.item_used.connect(use_item)
	hud.pass_ready.connect(_turn_start_effects)
	hud.help_requested.connect(func(): papyrus.open())
	hud.focus_requested.connect(_focus_current)
	hud.cancel_mode.connect(_cancel_trap_mode)
	hud.menu_requested.connect(func(): exit_to_menu.emit())
	hud.restart_requested.connect(func(): restart_game.emit())
	hud.battle_event.connect(_on_battle_event)
	_set_time_visual(hour)
	_roll_weather()
	cam_target = players[0].node.position + Vector3(0, 0, 6)
	begin_turn()
	if cfg.get("show_rules", false):
		papyrus.open()

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.ambient_light_sky_contribution = 0.7
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_energy = 0.6
	env.fog_sky_affect = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 26.0
	sun.shadow_bias = 0.04
	add_child(sun)

func _spawn_objects() -> void:
	for o in map.objects:
		var d: Dictionary = o.duplicate()
		var p: Vector2i = d["pos"]
		var n: Node3D
		match d["type"]:
			"campfire":
				n = Models.campfire()
				n.get_node("Light").set_meta("base", 1.6)
			"shard":
				n = Models.shard()
				n_shards_total += 1
			"chest":
				n = Models.chest()
				n.rotation.y = rng.randf_range(-0.5, 0.5)
				if d["content"] == "shard":
					n_shards_total += 1
			"beast":
				n = Models.beast(d["kind"])
				n.rotation.y = rng.randf() * TAU
				d["hits"] = int(DB.beasts[d["kind"]]["hits"])
				if d["shard"]:
					n_shards_total += 1
					var sh := Models.shard()
					sh.scale = Vector3.ONE * 0.6
					sh.position = Vector3(0.3, 0, 0.25)
					n.add_child(sh)
			"event":
				n = Models.event_stone()
		n.position = map.world_pos(p)
		entities.add_child(n)
		d["node"] = n
		objects[p] = d
	shrine_node = Models.shrine()
	shrine_node.position = map.world_pos(map.shrine)
	shrine_node.rotation.y = PI
	entities.add_child(shrine_node)

func _setup_players() -> void:
	var list: Array = cfg["players"]
	for i in list.size():
		var pc: Dictionary = list[i]
		var pr: Dictionary = DB.heroes[pc["hero"]]
		var node: Node3D = Models.hero(pr)
		var start: Vector2i = map.starts[i]
		node.position = map.world_pos(start)
		node.rotation.y = 0.0
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3
		tm.outer_radius = 0.38
		ring.mesh = tm
		ring.material_override = Models.mat(DB.PLAYER_COLORS[i], 1.2)
		ring.scale = Vector3(1, 0.25, 1)
		ring.position.y = 0.02
		ring.name = "Ring"
		node.add_child(ring)
		var lantern := OmniLight3D.new()
		lantern.light_color = Color("ffc070")
		lantern.omni_range = 3.2
		lantern.light_energy = 0.0
		lantern.visible = false
		lantern.shadow_enabled = false
		lantern.position = Vector3(0, 1.0, 0.2)
		node.add_child(lantern)
		var tag := Label3D.new()
		tag.text = pc["name"]
		tag.font = Style.font_bold
		tag.font_size = 44
		tag.outline_size = 12
		tag.modulate = DB.PLAYER_COLORS[i].lightened(0.3)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.pixel_size = 0.004
		tag.position = Vector3(0, 1.35, 0)
		node.add_child(tag)
		if pc.get("pet", false):
			var pet := Models.pet_fox()
			pet.position = Vector3(0.38, 0, -0.22)
			node.add_child(pet)
		entities.add_child(node)
		var hand: Array = []
		for k in 3:
			hand.append(DB.random_trap(rng))
		players.append({
			"name": pc["name"], "slot": pc.get("slot", i), "hero": pc["hero"], "color": DB.PLAYER_COLORS[i],
			"hp": MAX_HP, "pos": start, "shards": 0, "hand": hand, "items": ["potion"],
			"dot": 0, "skip_move": 0, "slow": 0, "skip_turn": 0, "block_traps": 0, "vuln": 0,
			"now_skip_move": false, "now_slow": 0, "now_block_traps": false, "now_vuln": false,
			"marks": {}, "campfire": start, "pet": pc.get("pet", false), "reports": [],
			"discovered": {}, "explored": _initial_explored(), "die": "D6", "node": node, "lantern": lantern, "trail": [],
		})

func _initial_explored() -> Dictionary:
	# Святилище все знают: это цель на юге
	var e := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t: Vector2i = map.shrine + Vector2i(dx, dz)
			if map.inb(t):
				e[t] = true
	return e

func _setup_highlight() -> void:
	hl_mm = MultiMesh.new()
	hl_mm.transform_format = MultiMesh.TRANSFORM_3D
	hl_mm.use_colors = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.86, 0.86)
	hl_mm.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = hl_mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _setup_darkness_and_rain() -> void:
	darkness = MeshInstance3D.new()
	darkness.mesh = Models.box(Vector3.ONE)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.06, 0.02, 0.1, 0.72)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.emission_enabled = true
	dm.emission = Color(0.35, 0.1, 0.5)
	dm.emission_energy_multiplier = 0.5
	darkness.material_override = dm
	darkness.visible = false
	darkness.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(darkness)
	rain = CPUParticles3D.new()
	rain.amount = 400
	rain.lifetime = 0.8
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(14, 0.5, 14)
	rain.direction = Vector3(0.15, -1, 0)
	rain.spread = 3.0
	rain.initial_velocity_min = 14.0
	rain.initial_velocity_max = 16.0
	rain.gravity = Vector3(0, -15, 0)
	var dm2 := Models.box(Vector3(0.012, 0.35, 0.012))
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
	dm2.material = rm
	rain.mesh = dm2
	rain.emitting = false
	add_child(rain)

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 220.0
	add_child(cam)
	cam.make_current()

# ================================================================= КАМЕРА И ВВОД
func _process(delta: float) -> void:
	if follow != null and is_instance_valid(follow):
		cam_goal = follow.position
	cam_target = cam_target.lerp(cam_goal, 1.0 - exp(-delta * 4.0))
	if view_first and not _in_fight and not game_over:
		var n: Node3D = players[cur].node
		var head := n.position + Vector3(0, 0.95, 0)
		var dir := Vector3(sin(fp_yaw) * cos(fp_pitch), sin(fp_pitch), cos(fp_yaw) * cos(fp_pitch))
		cam.position = cam.position.lerp(head - dir * 0.1, 1.0 - exp(-delta * 10.0))
		cam.look_at(cam.position + dir, Vector3.UP)
		cam.fov = lerpf(cam.fov, 72.0, delta * 6.0)
	else:
		var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), -cos(cam_yaw) * cos(cam_pitch)) * cam_dist
		cam.position = cam_target + off
		cam.look_at(cam_target + Vector3(0, 0.4, 0), Vector3.UP)
		cam.fov = lerpf(cam.fov, 50.0, delta * 6.0)
	if rain.emitting:
		rain.position = cam_target + Vector3(0, 9, 3)
	if info.get("foliage_mat"):
		var fm: ShaderMaterial = info["foliage_mat"]
		var w: float = fm.get_shader_parameter("wind") if fm.get_shader_parameter("wind") != null else 0.3
		fm.set_shader_parameter("wind", lerpf(w, wind, delta))

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		if _touches.size() == 2:
			var ps := _touches.values()
			_pinch_d = (ps[0] as Vector2).distance_to(ps[1])
			_press = false
		return
	if e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() == 2:
			var ps := _touches.values()
			var d := (ps[0] as Vector2).distance_to(ps[1])
			if _pinch_d > 0.0:
				_zoom(_pinch_d / d)
			_pinch_d = d
			_press = false
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = true
				_dragging = false
				_press_pos = e.position
			else:
				if _press and not _dragging:
					_on_click(e.position)
				_press = false
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom(1.1)
	elif e is InputEventMouseMotion and _press:
		if not _dragging and e.position.distance_to(_press_pos) > 14.0:
			_dragging = true
			follow = null
		if _dragging:
			if view_first and not _in_fight:
				fp_yaw -= e.relative.x * 0.006
				fp_pitch = clampf(fp_pitch - e.relative.y * 0.004, -1.2, 0.35)
			else:
				_pan(e.relative)
	elif e is InputEventMagnifyGesture:
		_zoom(1.0 / e.factor)
	elif e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_Q: cam_yaw -= 0.2
			KEY_E: cam_yaw += 0.2
			KEY_SPACE: _focus_current()

func _set_view(first: bool, save: bool) -> void:
	view_first = first
	if first:
		fp_yaw = players[cur].node.rotation.y
		fp_pitch = -0.35
	if save:
		Settings.set_pref(players[cur].name, "view", "first" if first else "third")
	refresh_view()
	hud.refresh()

func _zoom(f: float) -> void:
	cam_dist = clampf(cam_dist * f, 4.0, 28.0)

func _pan(rel: Vector2) -> void:
	var right := cam.global_basis.x
	right.y = 0
	right = right.normalized()
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var k := cam_dist * 0.0022
	cam_goal += (-right * rel.x + fwd * rel.y) * k
	cam_goal.x = clampf(cam_goal.x, -2, map.w + 1)
	cam_goal.z = clampf(cam_goal.z, -4, map.h + 2)

func _focus_current() -> void:
	follow = players[cur].node

func _pick(sp: Vector2) -> Vector2i:
	var from := cam.project_ray_origin(sp)
	var dir := cam.project_ray_normal(sp)
	if absf(dir.y) < 0.001:
		return Vector2i(-1, -1)
	var yh := 0.0
	var tile := Vector2i(-1, -1)
	for i in 3:
		var tt := (yh - from.y) / dir.y
		var p := from + dir * tt
		tile = Vector2i(int(round(p.x)), int(round(p.z)))
		if not map.inb(tile):
			return tile
		yh = map.height(tile)
	return tile

func _on_click(sp: Vector2) -> void:
	if busy or game_over:
		return
	var t := _pick(sp)
	if not map.inb(t):
		return
	if mode == "trap":
		if trap_targets.has(t):
			_place_trap(t)
		return
	if rolled and reach.has(t):
		_walk(_path_to(t))
	else:
		_tile_hint(t)

func _tile_hint(t: Vector2i) -> void:
	var tt: int = map.get_t(t)
	if not players[cur].explored.has(t):
		hud.toast("Неизведанная земля. Подойди ближе, чтобы разглядеть.", Style.PARCH, 2.0)
		return
	var txt: String = MapGen.NAMES[tt]
	var c: int = map.cost(t)
	if c < 50:
		txt += " — шаг стоит %d" % c
	else:
		txt += " — не пройти"
	var o = objects.get(t)
	if o != null and _object_visible(o, players[cur]):
		match o["type"]:
			"beast": txt += ". Здесь %s (сила %d)" % [DB.beasts[o["kind"]]["name"], int(DB.beasts[o["kind"]]["power"])]
			"chest": txt += ". Сундук"
			"shard": txt += ". Осколок!"
			"event": txt += ". Загадочный камень"
			"campfire": txt += ". Костёр — точка возрождения"
	if not rolled:
		txt += "   (сначала брось кубик)"
	hud.toast(txt, Style.PARCH, 2.0)

# ================================================================= ХОДЫ
func current() -> Dictionary:
	return players[cur]

func begin_turn() -> void:
	var p: Dictionary = players[cur]
	rolled = false
	steps_left = 0
	mode = "move"
	_clear_highlight()
	follow = p.node
	var pr: Dictionary = Settings.pref(p.name)
	view_first = pr["view"] == "first"
	fp_yaw = p.node.rotation.y
	fp_pitch = -0.35
	Settings.set_music_enabled(pr["music"])
	refresh_view()
	_update_shrine_sockets()
	hud.set_phase("wait")
	hud.refresh()
	var reports: Array = p.reports.duplicate()
	p.reports.clear()
	if players.size() > 1:
		hud.show_pass(p, reports)
	else:
		for r in reports:
			hud.toast(r, Style.GOLD, 4.0)
		_turn_start_effects()

func _turn_start_effects() -> void:
	var p: Dictionary = players[cur]
	p.now_skip_move = p.skip_move > 0
	if p.skip_move > 0:
		p.skip_move -= 1
	p.now_slow = p.slow
	p.slow = 0
	p.now_block_traps = p.block_traps > 0
	if p.block_traps > 0:
		p.block_traps -= 1
	p.now_vuln = p.vuln > 0
	if p.vuln > 0:
		p.vuln -= 1
	if p.dot > 0:
		p.dot -= 1
		_damage(p, 1)
		hud.toast("Ожог от ловушки: −1 HP", Style.RED)
	if night and p.pos.y <= dark_row:
		_damage(p, 2)
		hud.toast("Тьма обжигает! −2 HP. Беги на юг!", Color("c58cff"))
	if p.hp <= 0:
		await _respawn(p)
	if p.skip_turn > 0:
		p.skip_turn -= 1
		hud.toast("Ловушка времени: этот ход пропущен", Style.RED, 2.5)
		await get_tree().create_timer(1.6).timeout
		end_turn()
		return
	hud.set_phase("roll")
	hud.refresh()

func roll(die: String) -> void:
	if rolled or busy or game_over:
		return
	var p: Dictionary = players[cur]
	p.die = die
	var faces: Array = DB.die_faces(die)
	var i := rng.randi_range(0, faces.size() - 1)
	var face := i + 1
	var steps := int(faces[i])
	var notes: Array = []
	if die == "D20" and face == 20:
		notes.append("Критическая удача! Находка: " + _give_loot(p))
	elif die == "D20" and face == 1:
		notes.append("Ой, споткнулся...")
	if p.now_slow > 0:
		steps = maxi(0, steps - p.now_slow)
		notes.append("Ловушка замедлила: −%d" % p.now_slow)
	if p.now_skip_move:
		steps = 0
		notes.append("Ты застрял в ловушке и не можешь идти")
	busy = true
	hud.set_phase("busy")
	await hud.animate_roll(die, face, steps, " ".join(notes))
	busy = false
	rolled = true
	steps_left = steps
	hud.set_phase("act")
	_recalc()
	hud.refresh()

func end_turn() -> void:
	if busy or game_over:
		return
	var p: Dictionary = players[cur]
	for k in p.marks.keys():
		p.marks[k] -= 1
		if p.marks[k] <= 0:
			p.marks.erase(k)
	mode = "move"
	_clear_highlight()
	cur = (cur + 1) % players.size()
	if cur == 0:
		_advance_round()
	begin_turn()

func _advance_round() -> void:
	round_no += 1
	hour = minf(hour + hours_per_round, 28.0)
	if not night and hour >= 21.0:
		night = true
		dark_row = dark_speed - 1
		hud.big_banner("Наступила ночь", "С севера ползёт Тьма. Не отставай!")
	elif night:
		var limit: int = map.gorge.x - 2
		if dark_row < limit:
			dark_row = mini(dark_row + dark_speed, limit)
			if dark_row == limit:
				hud.toast("Тьма остановилась у гор. Дальше ей не пройти!", Color("c58cff"), 4.0)
	elif hour >= 18.5 and hour - hours_per_round < 18.5:
		hud.big_banner("Вечереет", "Обзор становится меньше, звери злее")
	_roll_weather()
	_update_darkness()
	var tw := create_tween()
	tw.tween_method(_set_time_visual, _time_shown, minf(hour, 24.0), 2.0)

func _roll_weather() -> void:
	var chance := 0.18 if hour < 17.0 else 0.35
	var raining := rng.randf() < chance
	rain.emitting = raining
	wind = rng.randf_range(0.15, 0.5) + (0.6 if raining else 0.0)
	if raining:
		weather = "Дождь"
	elif wind > 0.4:
		weather = "Ветрено"
	else:
		weather = "Ясно"

func time_name() -> String:
	if night:
		return "Глубокая ночь" if hour >= 24.0 else "Ночь"
	if hour < 11.0:
		return "Утро"
	if hour < 17.0:
		return "День"
	return "Вечер"

func clock_text() -> String:
	var hh := int(fmod(hour, 24.0))
	var mm := int((hour - floor(hour)) * 60.0) / 10 * 10
	return "%02d:%02d" % [hh, mm]

# ================================================================= ВРЕМЯ СУТОК
const TIME_KEYS := [
	# hour, elev, yaw, sun color, energy, sky top, sky horizon, ambient, night
	[8.0, 28.0, 80.0, Color(1.0, 0.9, 0.78), 0.85, Color(0.30, 0.52, 0.86), Color(0.70, 0.78, 0.86), 0.42, 0.0],
	[12.0, 55.0, 25.0, Color(1.0, 0.97, 0.92), 0.95, Color(0.25, 0.48, 0.88), Color(0.64, 0.75, 0.88), 0.45, 0.0],
	[16.0, 36.0, -45.0, Color(1.0, 0.88, 0.72), 0.9, Color(0.28, 0.46, 0.80), Color(0.78, 0.72, 0.66), 0.4, 0.0],
	[19.0, 12.0, -80.0, Color(1.0, 0.72, 0.5), 0.7, Color(0.28, 0.3, 0.52), Color(0.8, 0.56, 0.46), 0.34, 0.35],
	[21.0, 35.0, 30.0, Color(0.55, 0.62, 1.0), 0.32, Color(0.04, 0.05, 0.14), Color(0.12, 0.12, 0.26), 0.24, 0.85],
	[24.0, 45.0, 10.0, Color(0.5, 0.58, 1.0), 0.28, Color(0.02, 0.03, 0.09), Color(0.08, 0.08, 0.2), 0.2, 1.0],
]

func _set_time_visual(hv: float) -> void:
	_time_shown = hv
	var hh := clampf(hv, 8.0, 24.0)
	var a: Array = TIME_KEYS[0]
	var b: Array = TIME_KEYS[0]
	var k := 0.0
	for i in TIME_KEYS.size() - 1:
		if hh >= TIME_KEYS[i][0] and hh <= TIME_KEYS[i + 1][0]:
			a = TIME_KEYS[i]
			b = TIME_KEYS[i + 1]
			k = (hh - a[0]) / (b[0] - a[0])
			break
	var elev := lerpf(a[1], b[1], k)
	var yaw := lerpf(a[2], b[2], k)
	sun.rotation_degrees = Vector3(-elev, yaw, 0)
	sun.light_color = (a[3] as Color).lerp(b[3], k)
	sun.light_energy = lerpf(a[4], b[4], k)
	sky_mat.sky_top_color = (a[5] as Color).lerp(b[5], k)
	sky_mat.sky_horizon_color = (a[6] as Color).lerp(b[6], k)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = sky_mat.sky_top_color.darkened(0.5)
	env.ambient_light_energy = lerpf(a[7], b[7], k)
	var nt := lerpf(a[8], b[8], k)
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_density = 0.004 + nt * 0.016
	if info.get("water_mat"):
		(info["water_mat"] as ShaderMaterial).set_shader_parameter("darkness", nt)
	for p in players:
		p.lantern.light_energy = nt * 1.6
	_update_lights()
	for o in objects.values():
		if o["type"] == "campfire":
			var l: OmniLight3D = o["node"].get_node("Light")
			l.set_meta("base", 1.4 + nt * 1.6)

## Источники света дороги для старого рендерера: включаем только те, что рядом с текущим героем.
func _update_lights() -> void:
	if players.is_empty():
		return
	var p: Dictionary = players[cur]
	var nt := clampf((_time_shown - 18.0) / 3.0, 0.0, 1.0)
	for i in players.size():
		var q: Dictionary = players[i]
		q.lantern.visible = nt > 0.05 and i == cur
	for o in objects.values():
		if o["type"] == "campfire":
			var l: OmniLight3D = o["node"].get_node("Light")
			var pos: Vector2i = o["pos"]
			var d: int = maxi(absi(pos.x - p.pos.x), absi(pos.y - p.pos.y))
			l.visible = d <= 9 and p.explored.has(pos)

func _update_darkness() -> void:
	if dark_row < 0:
		darkness.visible = false
		return
	darkness.visible = true
	var depth := float(dark_row + 1 + 12)
	var cz := float(dark_row) + 0.5 - depth * 0.5
	var tw := create_tween()
	tw.tween_property(darkness, "position", Vector3(map.w * 0.5 - 0.5, 1.0, cz), 2.0)
	tw.parallel().tween_property(darkness, "scale", Vector3(map.w + 30, 4.0, depth), 2.0)

# ================================================================= ВИДИМОСТЬ
func vision(p: Dictionary) -> int:
	var tt: int = map.get_t(p.pos)
	var r := 3
	if tt == MapGen.HILL:
		r = 4
	elif tt == MapGen.FOREST:
		r = 2
	if night:
		r -= 1
	if p.items.has("torch"):
		r += 1
	if p.pet:
		r += 1
	return maxi(1, r)

func can_see(p: Dictionary, t: Vector2i) -> bool:
	var d := maxi(absi(t.x - p.pos.x), absi(t.y - p.pos.y))
	var r := vision(p)
	if map.get_t(t) == MapGen.FOREST:
		r -= 1
	return d <= r

func _object_visible(o: Dictionary, p: Dictionary) -> bool:
	var pos: Vector2i = o["pos"]
	match o["type"]:
		"campfire", "chest", "event":
			return p.explored.has(pos)
	return p.discovered.has(pos) or can_see(p, pos)

## Туман войны: видимое — ярко, разведанное — тусклее, рядом с обзором — дымка с силуэтами, дальше — тьма.
func refresh_view() -> void:
	var p: Dictionary = players[cur]
	var r := vision(p)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var e: Vector2i = p.pos + Vector2i(dx, dz)
			if map.inb(e):
				p.explored[e] = true
	var refs: Dictionary = info["tile_ref"]
	var decor: Dictionary = info["decor_ref"]
	var fog_items: Array = []
	for t in refs:
		var tp: Vector2i = t
		var ref: Array = refs[t]
		var base: Color = ref[2]
		var d := maxi(absi(tp.x - p.pos.x), absi(tp.y - p.pos.y))
		var k := 1.0
		if d > r:
			if p.explored.has(tp):
				k = 0.6
			else:
				k = 0.4
				fog_items.append([tp, FOG_HAZE if d <= r + 2 else FOG_DARK])
		var dark: bool = night and tp.y <= dark_row
		var c := _tint(base, k, dark)
		(ref[0] as MultiMesh).set_instance_color(ref[1], c)
		if decor.has(tp):
			for dr in decor[tp]:
				(dr[0] as MultiMesh).set_instance_color(dr[1], _tint(dr[2], k, dark))
	_set_fog(fog_items)
	for bt in info["bridge_nodes"]:
		var bd := maxi(absi(bt.x - p.pos.x), absi(bt.y - p.pos.y))
		info["bridge_nodes"][bt].visible = p.explored.has(bt) or bd <= r + 2
	for t in objects:
		var o: Dictionary = objects[t]
		if o["type"] in ["beast", "shard"] and can_see(p, t):
			p.discovered[t] = true
		o["node"].visible = _object_visible(o, p)
	for i in players.size():
		var q: Dictionary = players[i]
		var vis: bool = i == cur or can_see(p, q.pos) or p.marks.has(i)
		q.node.visible = vis and not (i == cur and view_first)
		q.node.get_node("Ring").visible = i == cur
	for tr in traps:
		tr["node"].visible = tr["owner"] == cur
	_update_lights()

func _tint(base: Color, k: float, dark: bool) -> Color:
	var c := base * k
	if dark:
		c = c * 0.35 + Color(0.12, 0.03, 0.18) * 0.65
	c.a = 1.0
	return c

const FOG_HAZE := Color(0.06, 0.07, 0.1, 0.62)
const FOG_DARK := Color(0.02, 0.025, 0.04, 1.0)

func _setup_fog() -> void:
	# тьма — непрозрачная (дёшево), дымка — полупрозрачная (только узкое кольцо у края обзора)
	fog_mm = _fog_layer(false)
	haze_mm = _fog_layer(true)

func _fog_layer(transparent: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 3.4, 1.0)
	mm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm

func _set_fog(items: Array) -> void:
	var dark: Array = []
	var haze: Array = []
	for it in items:
		if it[1] == FOG_DARK:
			dark.append(it[0])
		else:
			haze.append(it[0])
	_fill_fog(fog_mm, dark, FOG_DARK)
	_fill_fog(haze_mm, haze, FOG_HAZE)

func _fill_fog(mm: MultiMesh, tiles: Array, col: Color) -> void:
	mm.instance_count = tiles.size()
	for i in tiles.size():
		var t: Vector2i = tiles[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(t.x, 1.0, t.y)))
		mm.set_instance_color(i, col)

func _update_shrine_sockets() -> void:
	var p: Dictionary = players[cur]
	for i in 3:
		var s: MeshInstance3D = shrine_node.get_node("Socket%d" % i)
		s.material_override = Models.mat(Color("7fe3ff"), 2.0) if p.shards > i else Models.mat(Color("333333"))

# ================================================================= ПЕРЕМЕЩЕНИЕ
func _player_at(t: Vector2i, except: int) -> int:
	for i in players.size():
		if i != except and players[i].pos == t:
			return i
	return -1

func _recalc() -> void:
	reach.clear()
	prev.clear()
	targets.clear()
	var p: Dictionary = players[cur]
	if steps_left <= 0 or game_over:
		_clear_highlight()
		return
	var dist := {p.pos: 0}
	var open: Array = [p.pos]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var c: Vector2i = open.pop_at(bi)
		if targets.has(c):
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if not map.passable(n):
				continue
			var nd: int = dist[c] + map.cost(n)
			if nd > steps_left:
				continue
			if dist.has(n) and dist[n] <= nd:
				continue
			dist[n] = nd
			prev[n] = c
			var o = objects.get(n)
			var blocked := false
			if o != null and o["type"] == "beast":
				blocked = true
			var opp := _player_at(n, cur)
			if opp >= 0 and can_see(p, n):
				blocked = true
			if map.get_t(n) == MapGen.SHRINE and p.shards < 3:
				blocked = true
			if blocked:
				targets[n] = true
			else:
				targets.erase(n)
				open.append(n)
	dist.erase(p.pos)
	reach = dist
	_show_reach()

func _path_to(t: Vector2i) -> Array:
	var path: Array = []
	var c := t
	var start: Vector2i = players[cur].pos
	while c != start:
		path.push_front(c)
		c = prev[c]
	return path

func _show_reach() -> void:
	var items: Array = []
	for t in reach:
		var col := Color(0.25, 0.8, 1.0, 0.55)
		if targets.has(t):
			col = Color(1.0, 0.25, 0.2, 0.65)
		items.append([t, col])
	_set_highlight(items)

func _set_highlight(items: Array) -> void:
	hl_mm.instance_count = items.size()
	for i in items.size():
		var t: Vector2i = items[i][0]
		hl_mm.set_instance_transform(i, Transform3D(Basis(), map.world_pos(t) + Vector3(0, 0.035, 0)))
		hl_mm.set_instance_color(i, items[i][1])

func _clear_highlight() -> void:
	hl_mm.instance_count = 0

func _face(p: Dictionary, t: Vector2i) -> void:
	var d: Vector2i = t - p.pos
	if d != Vector2i.ZERO:
		p.node.rotation.y = atan2(float(d.x), float(d.y))
		if view_first:
			fp_yaw = p.node.rotation.y

func _move_hero(p: Dictionary, t: Vector2i, dur := 0.24) -> void:
	var n: Node3D = p.node
	n.set("walking", true)
	_face(p, t)
	var a := n.position
	var b: Vector3 = map.world_pos(t)
	var tw := create_tween()
	tw.tween_method(func(k: float): n.position = a.lerp(b, k) + Vector3(0, sin(k * PI) * 0.16, 0), 0.0, 1.0, dur)
	await tw.finished

func _walk(path: Array) -> void:
	busy = true
	hud.set_phase("busy")
	_clear_highlight()
	var p: Dictionary = players[cur]
	follow = p.node
	for step in path:
		var tile: Vector2i = step
		var c: int = map.cost(tile)
		var o = objects.get(tile)
		if o != null and o["type"] == "beast":
			_face(p, tile)
			steps_left -= c
			await _fight_beast(p, tile, o)
			break
		var opp := _player_at(tile, cur)
		if opp >= 0:
			_face(p, tile)
			steps_left -= c
			players[opp].node.visible = true
			await _duel(p, players[opp])
			break
		if map.get_t(tile) == MapGen.SHRINE:
			if p.shards >= 3:
				await _move_hero(p, tile)
				p.pos = tile
				p.node.walking = false
				_victory(p)
				return
			hud.toast("Святилище запечатано. Нужно 3 осколка, у тебя %d." % p.shards, Style.GOLD, 3.0)
			break
		var from: Vector2i = p.pos
		await _move_hero(p, tile)
		p.pos = tile
		p.trail.append(from)
		if p.trail.size() > 20:
			p.trail.pop_front()
		steps_left -= c
		refresh_view()
		var stop: bool = await _on_enter(p, tile)
		if stop or p.hp <= 0 or game_over:
			break
	p.node.walking = false
	if p.hp <= 0:
		await _respawn(p)
	for i in players.size():
		if i != cur and players[i].hp <= 0:
			await _respawn(players[i])
	busy = false
	if game_over:
		return
	hud.set_phase("act")
	refresh_view()
	_recalc()
	hud.refresh()

func _on_enter(p: Dictionary, tile: Vector2i) -> bool:
	var stop := false
	var o = objects.get(tile)
	if o != null:
		match o["type"]:
			"shard":
				Settings.play("shard")
				p.shards += 1
				_remove_object(tile)
				_float_text(p.node, "+1 осколок", Style.TEAL)
				hud.toast("Ты нашёл осколок! Теперь у тебя %d из 3." % p.shards, Style.TEAL, 3.0)
				_update_shrine_sockets()
			"chest":
				Settings.play("chest")
				var lid: Node3D = o["node"].get_node("Lid")
				var tw := create_tween()
				tw.tween_property(lid, "rotation:x", -1.9, 0.4)
				objects.erase(tile)
				if o["content"] == "shard":
					p.shards += 1
					Settings.play("shard")
					_float_text(p.node, "+1 осколок", Style.TEAL)
					hud.toast("В сундуке сиял осколок! У тебя %d из 3." % p.shards, Style.TEAL, 3.0)
					_update_shrine_sockets()
				else:
					var what := _give_loot(p)
					_float_text(p.node, what, Style.GOLD)
					hud.toast("Сундук открыт: " + what, Style.GOLD, 3.0)
				var n: Node3D = o["node"]
				var tw2 := create_tween()
				tw2.tween_interval(1.5)
				tw2.tween_property(n, "scale", Vector3.ONE * 0.01, 0.5)
				tw2.tween_callback(n.queue_free)
			"event":
				_remove_object(tile)
				await _event(p)
				stop = true
			"campfire":
				p.campfire = tile
				hud.toast("Костёр согрел тебя: +3 HP. Здесь ты очнёшься, если лишишься сил.", Color("ffb070"), 3.0)
				p.hp = mini(MAX_HP, p.hp + 3)
	var hit: Array = []
	for tr in traps:
		if tr["pos"] == tile and tr["owner"] != cur:
			hit.append(tr)
	for tr in hit:
		await _trigger_trap(tr, p)
		stop = true
	return stop

func _remove_object(t: Vector2i) -> void:
	var o: Dictionary = objects[t]
	objects.erase(t)
	var n: Node3D = o["node"]
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.35)
	tw.tween_callback(n.queue_free)

# ================================================================= ДОБЫЧА И СОБЫТИЯ
func _give_loot(p: Dictionary) -> String:
	var r := rng.randf()
	if r < 0.45:
		var c := DB.random_trap(rng)
		p.hand.append(c)
		return "карта ловушки «%s»" % DB.traps[c]["name"]
	var keys := ["potion", "potion", "boots", "torch"]
	if rng.randf() < 0.08:
		keys = ["honey"]
	var k: String = keys[rng.randi() % keys.size()]
	if k == "torch" and p.items.has("torch"):
		k = "potion"
	p.items.append(k)
	return DB.items[k]["name"]

func _event(p: Dictionary) -> void:
	_stop_walk(p)
	Settings.play("magic")
	var r := rng.randi_range(0, 4)
	match r:
		0:
			p.items.append("potion")
			await hud.alert("Старый странник", "Седой путник улыбнулся и протянул тебе зелье лечения.", Style.GOLD)
		1:
			var a := DB.random_trap(rng)
			var b := DB.random_trap(rng)
			p.hand.append(a)
			p.hand.append(b)
			await hud.alert("Тайник", "Под камнем спрятаны две карты ловушек: «%s» и «%s»." % [DB.traps[a]["name"], DB.traps[b]["name"]], Style.GOLD)
		2:
			steps_left += 3
			await hud.alert("Попутный ветер", "Ветер подхватил тебя: +3 шага в этот ход!", Style.TEAL)
		3:
			var best := Vector2i(-1, -1)
			var bd := 9999
			for t in objects:
				var o: Dictionary = objects[t]
				var has_shard: bool = o["type"] == "shard" or (o["type"] == "chest" and o.get("content", "") == "shard") or (o["type"] == "beast" and o.get("shard", false))
				if has_shard and not p.discovered.has(t):
					var d: int = absi(t.x - p.pos.x) + absi(t.y - p.pos.y)
					if d < bd:
						bd = d
						best = t
			if best.x >= 0:
				p.discovered[best] = true
				var dir := _dir_name(best - p.pos)
				await hud.alert("Шёпот духа", "Дух долины шепчет: осколок ждёт тебя %s, примерно в %d клетках. Он теперь отмечен для тебя." % [dir, bd], Color("c58cff"))
			else:
				p.items.append("potion")
				await hud.alert("Шёпот духа", "Духи молчат, но оставили тебе зелье.", Color("c58cff"))
		4:
			_damage(p, 1)
			await hud.alert("Скользкий камень", "Ты поскользнулся на мокром камне: −1 HP.", Style.RED)
	refresh_view()

func _dir_name(d: Vector2i) -> String:
	var ns := ""
	var ew := ""
	if d.y > 1:
		ns = "на юге"
	elif d.y < -1:
		ns = "на севере"
	if d.x > 1:
		ew = "на востоке"
	elif d.x < -1:
		ew = "на западе"
	if ns != "" and ew != "":
		return ns + " и " + ew
	if ns + ew == "":
		return "совсем рядом"
	return ns + ew

func use_item(idx: int) -> void:
	if busy or game_over:
		return
	var p: Dictionary = players[cur]
	if idx < 0 or idx >= p.items.size():
		return
	var k: String = p.items[idx]
	match k:
		"potion":
			p.hp = mini(MAX_HP, p.hp + 6)
			_float_text(p.node, "+6 HP", Style.GREEN)
		"honey":
			p.hp = MAX_HP
			_float_text(p.node, "Полное здоровье!", Style.GREEN)
		"boots":
			if not rolled:
				hud.toast("Сначала брось кубик, потом надевай сапоги", Style.GOLD)
				return
			steps_left += 3
			_float_text(p.node, "+3 шага", Style.TEAL)
			_recalc()
		_:
			hud.toast("Этот предмет работает сам", Style.GOLD)
			return
	p.items.remove_at(idx)
	hud.refresh()

# ================================================================= ЛОВУШКИ
func start_trap_mode(hand_idx: int) -> void:
	if busy or game_over:
		return
	var p: Dictionary = players[cur]
	if p.now_block_traps:
		hud.toast("«Потеря равновесия»: в этот ход ставить ловушки нельзя", Style.RED, 3.0)
		return
	if not rolled:
		hud.toast("Сначала брось кубик: ловушка стоит шагов", Style.GOLD)
		return
	var card: int = p.hand[hand_idx]
	var price := DB.trap_price(card)
	if steps_left < price:
		hud.toast("Нужно %d шага, а осталось %d" % [price, steps_left], Style.RED)
		return
	pending_card = hand_idx
	mode = "trap"
	trap_targets.clear()
	var items: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t: Vector2i = p.pos + Vector2i(dx, dz)
			if map.passable(t) and map.get_t(t) != MapGen.SHRINE and not objects.has(t) and _player_at(t, cur) < 0:
				trap_targets[t] = true
				items.append([t, Color(0.75, 0.2, 1.0, 0.6)])
	_set_highlight(items)
	hud.set_phase("trap")
	hud.toast("Нажми на подсвеченную клетку рядом с героем, чтобы спрятать «%s»" % DB.traps[card]["name"], Color("e0a0ff"), 3.0)

func _cancel_trap_mode() -> void:
	mode = "move"
	hud.set_phase("act")
	_recalc()

func _place_trap(t: Vector2i) -> void:
	var p: Dictionary = players[cur]
	var card: int = p.hand[pending_card]
	p.hand.remove_at(pending_card)
	steps_left -= DB.trap_price(card)
	var n := Models.trap_marker()
	n.position = map.world_pos(t)
	entities.add_child(n)
	traps.append({"owner": cur, "pos": t, "card": card, "node": n})
	hud.toast("Ловушка «%s» спрятана. Её видишь только ты." % DB.traps[card]["name"], Color("e0a0ff"), 3.0)
	mode = "move"
	hud.set_phase("act")
	_recalc()
	hud.refresh()

func _trigger_trap(tr: Dictionary, p: Dictionary) -> void:
	_stop_walk(p)
	Settings.play("trap")
	traps.erase(tr)
	var n: Node3D = tr["node"]
	n.visible = true
	n.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 1.6, 0.2)
	tw.tween_interval(1.4)
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.3)
	tw.tween_callback(n.queue_free)
	var card: Dictionary = DB.traps[tr["card"]]
	var fx: Dictionary = card["fx"]
	var owner: Dictionary = players[tr["owner"]]
	var lines: Array = []
	var dmg := int(fx.get("dmg", 0))
	if dmg > 0:
		_damage(p, dmg)
		lines.append("−%d HP" % dmg)
	if fx.has("dot"):
		p.dot += int(fx["dot"])
		lines.append("в следующий ход ещё −1 HP")
	if fx.has("skip_move"):
		p.skip_move += int(fx["skip_move"])
		lines.append("в следующий ход не сможешь идти")
	if fx.has("slow"):
		p.slow += int(fx["slow"])
		lines.append("в следующий ход на %d шага меньше" % int(fx["slow"]))
	if fx.has("skip_turn"):
		p.skip_turn += 1
		lines.append("следующий ход пропущен")
	if fx.has("block_traps"):
		p.block_traps += 1
		lines.append("в следующий ход нельзя ставить ловушки")
	if fx.has("block_summon"):
		lines.append("в следующий ход нельзя призывать животных")
	if fx.has("vuln"):
		p.vuln += int(fx["vuln"])
		lines.append("атаки по тебе сильнее на 1")
	if fx.has("heal_owner"):
		owner.hp = mini(MAX_HP, owner.hp + int(fx["heal_owner"]))
		lines.append("%s получает +%d HP" % [owner.name, int(fx["heal_owner"])])
	if fx.has("steal_card") and not p.hand.is_empty():
		var c: int = p.hand.pop_at(rng.randi_range(0, p.hand.size() - 1))
		owner.hand.append(c)
		lines.append("%s забирает твою карту «%s»" % [owner.name, DB.traps[c]["name"]])
	if fx.has("lose_card") and not p.hand.is_empty():
		var c2: int = p.hand.pop_at(rng.randi_range(0, p.hand.size() - 1))
		lines.append("карта «%s» потеряна" % DB.traps[c2]["name"])
	if fx.has("swap_card") and not p.hand.is_empty():
		var j := rng.randi_range(0, p.hand.size() - 1)
		p.hand[j] = DB.random_trap(rng)
		lines.append("одна карта превратилась в «%s»" % DB.traps[p.hand[j]]["name"])
	if fx.has("back"):
		lines.append("отбрасывает назад на %d клетки" % int(fx["back"]))
	if fx.has("teleport"):
		lines.append("тебя затягивает и выбрасывает в другом месте долины!")
	if fx.has("mark"):
		owner.marks[cur] = int(fx["mark"]) + 1
		lines.append("%s будет видеть тебя %d хода" % [owner.name, int(fx["mark"])])
	await hud.alert("Ловушка «%s»!" % card["name"], "Её спрятал(а) %s.\n%s" % [owner.name, "\n".join(lines)], owner.color)
	if fx.has("back"):
		for i in int(fx["back"]):
			if p.trail.is_empty():
				break
			var b: Vector2i = p.trail.pop_back()
			await _move_hero(p, b, 0.18)
			p.pos = b
		p.node.walking = false
	if fx.has("teleport"):
		var dest := Vector2i(-1, -1)
		for attempt in 60:
			var c := Vector2i(rng.randi_range(0, map.w - 1), clampi(p.pos.y + rng.randi_range(-6, 6), 0, map.h - 1))
			if map.passable(c) and map.get_t(c) != MapGen.SHRINE and not objects.has(c) and _player_at(c, cur) < 0:
				dest = c
				break
		if dest.x >= 0:
			var nn: Node3D = p.node
			var tw3 := create_tween()
			tw3.tween_property(nn, "scale", Vector3.ONE * 0.01, 0.3)
			await tw3.finished
			p.pos = dest
			nn.position = map.world_pos(dest)
			p.trail.clear()
			var tw4 := create_tween()
			tw4.tween_property(nn, "scale", Vector3.ONE, 0.3)
			await tw4.finished
	owner.reports.append("Твоя ловушка «%s» поймала героя %s!" % [card["name"], p.name])
	refresh_view()

# ================================================================= БОИ
func _fight_beast(p: Dictionary, tile: Vector2i, o: Dictionary) -> void:
	var def: Dictionary = DB.beasts[o["kind"]]
	var power := int(def["power"])
	var n: Node3D = o["node"]
	_stop_walk(p)
	n.look_at(Vector3(p.node.position.x, n.position.y, p.node.position.z), Vector3.UP)
	n.rotate_y(PI)
	_begin_fight(p.node, n)
	var info := "Сила: %d • Урон: %d" % [power, int(def["dmg"])]
	if int(o["hits"]) > 1:
		info += " • Нужно ударов: %d" % int(o["hits"])
	var res: Dictionary = await hud.battle(p.name, def["name"], info, "Чтобы победить, нужно набрать %d или больше" % power, false, p.color)
	var win: bool = int(res["total"]) >= power
	var txt := ""
	if win:
		txt = "Победа! %d против силы %d." % [int(res["total"]), power]
	else:
		var dmg0 := int(def["dmg"]) + (1 if p.now_vuln or p.vuln > 0 else 0)
		txt = "Поражение... %d против силы %d. −%d HP" % [int(res["total"]), power, dmg0]
	await hud.battle_finish(txt, win)
	_end_fight()
	if win:
		o["hits"] -= 1
		if o["hits"] > 0:
			var tw := create_tween()
			tw.tween_property(n, "position:x", n.position.x + 0.1, 0.05)
			tw.tween_property(n, "position:x", n.position.x - 0.1, 0.1)
			tw.tween_property(n, "position:x", n.position.x, 0.05)
			hud.toast("%s дал трещину! Ещё один удар — и он рассыплется." % def["name"], Style.GOLD, 3.0)
			return
		_remove_object(tile)
		if o.get("shard", false):
			p.shards += 1
			Settings.play("shard")
			_float_text(p.node, "+1 осколок", Style.TEAL)
			hud.toast("%s повержен и оставил осколок! У тебя %d из 3." % [def["name"], p.shards], Style.TEAL, 3.0)
			_update_shrine_sockets()
		else:
			var what := _give_loot(p)
			hud.toast("%s убежал. Добыча: %s" % [def["name"], what], Style.GOLD, 3.0)
	else:
		var dmg := int(def["dmg"]) + (1 if p.now_vuln or p.vuln > 0 else 0)
		_damage(p, dmg)
		hud.toast("%s оказался сильнее: −%d HP" % [def["name"], dmg], Style.RED, 3.0)

func _duel(p: Dictionary, q: Dictionary) -> void:
	_stop_walk(p)
	_face_node(q.node, p.node.position)
	_begin_fight(p.node, q.node)
	var forest: bool = map.get_t(q.pos) == MapGen.FOREST
	var r: Dictionary = await hud.battle(p.name, q.name, "Соперник бросит кубик сам" + (" (+1, он в лесу)" if forest else ""), "Побеждает тот, у кого больше", true, p.color)
	var a := int(r["total"])
	var d := rng.randi_range(1, 6) + (1 if forest else 0)
	var res := "Ничья: %d против %d. Оба −1 HP" % [a, d]
	if a > d:
		res = "%s побеждает: %d против %d!" % [p.name, a, d]
	elif d > a:
		res = "%s отбивается: %d против %d. −2 HP" % [q.name, d, a]
	await hud.battle_finish(res, a > d)
	_end_fight()
	if a > d:
		var dmg := 2 + (1 if q.vuln > 0 else 0)
		_damage(q, dmg)
		if q.shards > 0:
			q.shards -= 1
			p.shards += 1
			hud.toast("%s отбирает осколок у %s!" % [p.name, q.name], Style.TEAL, 3.0)
			q.reports.append("%s напал(а) и отобрал(а) у тебя осколок (−%d HP)." % [p.name, dmg])
			_update_shrine_sockets()
		elif not q.hand.is_empty():
			var c: int = q.hand.pop_at(rng.randi_range(0, q.hand.size() - 1))
			p.hand.append(c)
			hud.toast("%s забирает карту «%s»" % [p.name, DB.traps[c]["name"]], Style.GOLD, 3.0)
			q.reports.append("%s напал(а) и забрал(а) у тебя карту (−%d HP)." % [p.name, dmg])
		else:
			q.reports.append("%s напал(а) на тебя (−%d HP)." % [p.name, dmg])
	elif d > a:
		_damage(p, 2)
		q.reports.append("%s напал(а), но ты отбился!" % p.name)
	else:
		_damage(p, 1)
		_damage(q, 1)
		q.reports.append("%s напал(а) — ничья, оба −1 HP." % p.name)

func _stop_walk(p: Dictionary) -> void:
	p.node.set("walking", false)

func _face_node(n: Node3D, target: Vector3) -> void:
	var d := target - n.position
	if Vector2(d.x, d.z).length() > 0.01:
		n.rotation.y = atan2(d.x, d.z)

# --- анимация схватки
var _fight_a: Node3D
var _fight_b: Node3D
var _fight_cam := 8.5
var _fight_yaw := 0.0

func _begin_fight(a: Node3D, b: Node3D) -> void:
	_fight_a = a
	_fight_b = b
	_fight_cam = cam_dist
	_in_fight = true
	a.visible = true
	a.set("posing", true)
	follow = null
	# камера сбоку под углом к линии боя, чтобы видно было обоих
	var d := b.position - a.position
	var line := Vector2(d.x, d.z).normalized()
	if line == Vector2.ZERO:
		line = Vector2(0, 1)
	var f := line.rotated(deg_to_rad(65.0))
	_fight_yaw = cam_yaw
	var target_yaw := atan2(-f.x, f.y)
	while target_yaw - cam_yaw > PI:
		target_yaw -= TAU
	while target_yaw - cam_yaw < -PI:
		target_yaw += TAU
	var tw := create_tween()
	tw.tween_property(self, "cam_yaw", target_yaw, 0.5)
	cam_goal = (a.position + b.position) * 0.5 - Vector3(f.x, 0, f.y) * 1.3
	cam_dist = 4.8

func _end_fight() -> void:
	cam_dist = _fight_cam
	var tw := create_tween()
	tw.tween_property(self, "cam_yaw", _fight_yaw, 0.5)
	if _fight_a:
		_fight_a.set("posing", false)
		var al: Node3D = _fight_a.get_node_or_null("Body/ArmL")
		var ar: Node3D = _fight_a.get_node_or_null("Body/ArmR")
		if al:
			al.rotation = Vector3.ZERO
		if ar:
			ar.rotation = Vector3.ZERO
	follow = players[cur].node
	_in_fight = false
	refresh_view()
	_fight_a = null
	_fight_b = null

func _on_battle_event(kind: String) -> void:
	if _fight_a == null or _fight_b == null:
		return
	var a := _fight_a
	var b := _fight_b
	match kind:
		"enemy_attack":
			var home := b.position
			var tw := create_tween()
			tw.tween_property(b, "position", home.lerp(a.position, 0.35), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(b, "position", home, 0.35)
		"block":
			Settings.play("block")
			var arm: Node3D = a.get_node_or_null("Body/ArmL")
			if arm:
				var tw2 := create_tween()
				tw2.tween_property(arm, "rotation", Vector3(-1.4, 0, -0.6), 0.1)
				tw2.tween_interval(0.4)
				tw2.tween_property(arm, "rotation", Vector3.ZERO, 0.2)
			_float_text(a, "Блок!", Style.GREEN)
		"hit":
			Settings.play("hit")
			var home2 := a.position
			var back := home2 + (home2 - b.position).normalized() * 0.15
			var tw3 := create_tween()
			tw3.tween_property(a, "position", back, 0.08)
			tw3.tween_property(a, "position", home2, 0.2)
			_float_text(a, "Ай!", Style.RED)
		"hero_attack":
			Settings.play("hit", 0.15)
			var arm2: Node3D = a.get_node_or_null("Body/ArmR")
			var home3 := a.position
			var tw4 := create_tween()
			tw4.tween_property(a, "position", home3.lerp(b.position, 0.3), 0.15)
			if arm2:
				tw4.parallel().tween_property(arm2, "rotation", Vector3(-2.4, 0, 0), 0.15)
			tw4.tween_property(a, "position", home3, 0.25)
			if arm2:
				tw4.parallel().tween_property(arm2, "rotation", Vector3.ZERO, 0.25)

func _damage(p: Dictionary, n: int) -> void:
	p.hp = maxi(0, p.hp - n)
	_float_text(p.node, "−%d" % n, Style.RED)
	if hud:
		hud.refresh()

func _float_text(node: Node3D, txt: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font = Style.font_bold
	l.font_size = 56
	l.outline_size = 14
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.004
	l.position = node.position + Vector3(0, 1.6, 0)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y + 0.8, 1.4)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.tween_callback(l.queue_free)

func _respawn(p: Dictionary) -> void:
	_stop_walk(p)
	await hud.alert("%s без сил..." % p.name, "Герой очнётся у последнего костра с 12 HP. Потерян один осколок и одна карта.", Style.RED)
	if p.shards > 0:
		p.shards -= 1
		var drop: Vector2i = p.pos
		if objects.has(drop) or map.get_t(drop) in [MapGen.BRIDGE, MapGen.SHRINE]:
			drop = map.find_free(p.pos)
		if drop.x >= 0 and not objects.has(drop):
			var n := Models.shard()
			n.position = map.world_pos(drop)
			entities.add_child(n)
			objects[drop] = {"type": "shard", "pos": drop, "node": n}
	if not p.hand.is_empty():
		p.hand.pop_back()
	var cf: Vector2i = p.campfire
	if night and cf.y <= dark_row:
		cf = Vector2i(-1, -1)
		for c in map.campfires:
			var cc: Vector2i = c
			if cc.y > dark_row:
				cf = cc
				break
		if cf.x < 0:
			cf = map.shrine + Vector2i(0, -2)
	var idx := players.find(p)
	if _player_at(cf, idx) >= 0:
		for d in DIRS:
			if map.passable(cf + d) and _player_at(cf + d, idx) < 0:
				cf = cf + d
				break
	p.hp = 12
	p.pos = cf
	p.trail.clear()
	p.node.position = map.world_pos(cf)
	refresh_view()

func _victory(p: Dictionary) -> void:
	game_over = true
	_clear_highlight()
	DB.last_winner_slot = p.slot
	var portal: MeshInstance3D = shrine_node.get_node("Portal")
	var tw := create_tween()
	tw.tween_property(portal, "scale", Vector3(2.2, 1, 3.0), 0.8)
	cam_dist = 6.0
	follow = p.node
	hud.show_victory(p)
