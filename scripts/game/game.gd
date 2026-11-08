extends Node3D
## Главный контроллер партии: карта, игроки, ходы, туман войны, день/ночь, ловушки, бои.

signal exit_to_menu
signal restart_game
signal cmd_done(seq: int)
signal next_chapter(cfg: Dictionary)

const MapGen = preload("res://scripts/world/map_gen.gd")
const Models = preload("res://scripts/world/models.gd")
const Builder = preload("res://scripts/world/world_builder.gd")
const Camp = preload("res://scripts/game/campaign.gd")
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
var team_mode := false
var map_code := 0
var game_die := "D6"
var units: Array = []
var pending_summon := -1
var summon_targets := {}
var fp_yaw := 0.0
var fp_pitch := -0.35
var settings_panel
var _in_fight := false
var entities: Node3D
var shrine_node: Node3D
var hud
var papyrus
var _time_shown := 8.0

# --- сеть (все клиенты считают одну партию по общему зерну и одинаковому списку действий)
var net := false
var my_seat := -1
var replaying := false
var _q: Array = []
var _flow := false
var _echo_wait := false
var _last_seq := 0
var _offline := {}
var _caught := true
var _seat_of := {}
var v_explored := {}
var v_discovered := {}
var _net_over_banner: Label = null
var _status_cb := Callable()
const EMOTES := ["Я тут!", "Быстрее!", "Жду вас", "Ура!", "Помогите!", "Спасибо", "Смотри!", "Мне пора"]
var _chaining := false      # переходим на следующую карту: связь с сервером не рвём

# --- кампания «Времена года»
var camp := false
var chapter := 0
var camp_data: Dictionary = {}
var season_d: Dictionary = Camp.season(0)
var _camp_ready := false    # итоги раунда показаны, можно идти дальше
var _camp_scores: Array = []
var _camp_wins: Array = []
var _camp_win_ids: Array = []
var _snow := false
# --- босс (глава Camp.BOSS)
var boss := false
var boss_hp := 0
var boss_max := 0
var boss_dmg: Array = []
var boss_node: Node3D
var boss_tele: Array = []	   # клетки, куда дракон ударит в конце круга
var boss_tele_kind := ""
var boss_tele_node: Node3D
var boss_killer := -1
var boss_defeated := false
const BOSS_POWER := 4
const BOSS_HIT := 3

var _press := false
var _press_pos := Vector2.ZERO
var _dragging := false
var _touches := {}
var _pinch_d := 0.0
var _rot := false
var _rot_moved := 0.0
var _press_t := 0
var _two_mid := Vector2.ZERO
const YAW_LIMIT := 0.6
const PITCH_MIN := 0.55
const PITCH_MAX := 1.25

# ================================================================= СОЗДАНИЕ
func _ready() -> void:
	rng.randomize()
	net = cfg.get("net", false)
	my_seat = int(cfg.get("my_seat", -1))
	replaying = cfg.get("replay", false)
	_caught = not replaying or Net.caught
	camp_data = cfg.get("camp", {})
	camp = not camp_data.is_empty()
	chapter = int(camp_data.get("chapter", 0)) if camp else 0
	season_d = Camp.season(chapter if camp else 0)
	var sz: Vector2i = cfg.get("size", Vector2i(28, 64))
	map = MapGen.new()
	map_code = int(cfg.get("seed", 0))
	if map_code <= 0:
		map_code = rng.randi_range(10000, 99999)
	if camp:
		if not camp_data.has("base"):
			camp_data["base"] = map_code
		map_code = int(camp_data["base"]) + chapter * 1111
	if net:
		rng.seed = map_code * 7919 + 17   # у всех клиентов одинаковая «случайность»
		for i in cfg["players"].size():
			_seat_of[int(cfg["players"][i]["cid"])] = i
	boss = camp and chapter == Camp.BOSS
	if boss:
		map.arena = true
		sz = Vector2i(17, 21)
	if camp:
		map.season = chapter
		map.hard = float(season_d["hard"])
		map.wolf_share = float(season_d["wolf"])
	map.generate(sz.x, sz.y, map_code, cfg["players"].size())
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
	if camp:
		# каждая следующая карта жёстче: ночь наступает раньше, тьма ползёт быстрее
		hours_per_round *= 1.0 + 0.12 * chapter
		dark_speed += chapter
	if boss:
		hours_per_round = 0.25	 # в пещере ночи нет: время поджимает дракон, а не закат
		boss_max = 8 + 4 * players.size()
		boss_hp = boss_max
		boss_dmg.resize(players.size())
		boss_dmg.fill(0)
	hud = HUD.new()
	hud.game = self
	add_child(hud)
	papyrus = Papyrus.new()
	add_child(papyrus)
	settings_panel = SettingsPanel.new()
	add_child(settings_panel)
	settings_panel.view_changed.connect(func(first): _set_view(first, false))
	hud.settings_requested.connect(func(): settings_panel.open(players[viewer()].name))
	hud.view_toggle_requested.connect(func(): _set_view(not view_first, true))
	hud.roll_requested.connect(func(_d): _cmd({"k": "roll"}))
	hud.end_turn_requested.connect(func(): _cmd({"k": "end"}))
	hud.trap_card_chosen.connect(start_trap_mode)
	hud.summon_chosen.connect(start_summon_mode)
	hud.reroll_requested.connect(func(): _cmd({"k": "reroll"}))
	hud.item_used.connect(func(i): _cmd({"k": "item", "i": i}))
	hud.pass_ready.connect(_turn_start_effects)
	hud.help_requested.connect(func(): papyrus.open())
	hud.focus_requested.connect(_focus_current)
	hud.cancel_mode.connect(_cancel_trap_mode)
	hud.menu_requested.connect(func(): exit_to_menu.emit())
	hud.restart_requested.connect(func(): restart_game.emit())
	hud.battle_event.connect(_on_battle_event)
	_set_time_visual(hour)
	_roll_weather()
	cam_target = players[viewer()].node.position + Vector3(0, 0, 6)
	if cfg.get("show_rules", false):
		papyrus.open()
	if net:
		_last_seq = int(cfg.get("start_seq", 0))
		Net.act.connect(_on_net_act)
		Net.emote.connect(_on_emote)
		Net.caught_up.connect(_on_caught_up)
		_status_cb = func(t): hud.toast(t, Style.GOLD, 2.5)
		Net.status.connect(_status_cb)
		hud.skip_requested.connect(func(): Net.send_act({"k": "skip"}))
		for e in Net.acts_log:       # действия, которые пришли, пока мы переходили на эту карту
			_on_net_act(e)
		_flow = true
		if camp and not replaying:
			await hud.show_story(Camp.INTRO[chapter][0], Camp.INTRO[chapter][1], "В путь!")
		await begin_turn()
		_flow = false
	else:
		if camp:
			await hud.show_story(Camp.INTRO[chapter][0], Camp.INTRO[chapter][1], "В путь!")
		begin_turn()

func _exit_tree() -> void:
	if net:
		if Net.act.is_connected(_on_net_act):
			Net.act.disconnect(_on_net_act)
		if _status_cb.is_valid() and Net.status.is_connected(_status_cb):
			Net.status.disconnect(_status_cb)
		if Net.emote.is_connected(_on_emote):
			Net.emote.disconnect(_on_emote)
		if _chaining:
			return
		Engine.time_scale = 1.0
		if game_over:
			Net.leave()
		else:
			Net.pause()      # вышли в меню посреди игры: ключ комнаты оставляем, можно вернуться
		DB.restore_own_balance()

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
			"boss":
				n = Models.dragon()
				boss_node = n
		n.position = map.world_pos(p)
		if d["type"] == "campfire":
			n.position += Vector3(0.5, 0, 0.5)
		entities.add_child(n)
		d["node"] = n
		if d["type"] == "boss":
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					objects[p + Vector2i(dx, dz)] = d
			continue
		objects[p] = d
	shrine_node = Models.mountain_gate()
	shrine_node.position = map.world_pos(map.shrine)
	entities.add_child(shrine_node)
	shrine_node.visible = not boss

func _setup_players() -> void:
	var list: Array = cfg["players"]
	game_die = cfg.get("die", "D6")
	if not DB.dice.has(game_die):
		game_die = "D6"
	team_mode = cfg.get("team_mode", false)
	var team_n := [0, 0]
	if team_mode:
		for pc in list:
			team_n[int(pc.get("team", 0))] += 1
		if team_n[0] == 0 or team_n[1] == 0:
			team_mode = false
	if net:
		v_explored = _initial_explored()
	var team_explored := [_initial_explored(), _initial_explored()]
	var team_discovered := [{}, {}]
	var used := {}
	for i in list.size():
		var pc: Dictionary = list[i]
		var pr: Dictionary = DB.heroes[pc["hero"]]
		var node: Node3D = Models.hero(pr)
		var team := int(pc.get("team", 0)) if team_mode else -1
		var start: Vector2i = map.starts[i] if not team_mode else _team_start(team, used)
		used[start] = true
		# баланс: меньшая команда сильнее
		var kb := 1.0
		if team_mode and team_n[team] < team_n[1 - team]:
			kb = float(team_n[1 - team]) / float(team_n[team])
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
		tag.modulate = (DB.TEAM_COLORS[team] if team_mode else DB.PLAYER_COLORS[i]).lightened(0.3)
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
		var ab_id: String = DB.ability(int(pc.get("ability", i))) ["id"]
		var hand: Array = []
		for k in (5 if ab_id == "trapper" else 3):
			hand.append(DB.random_trap(rng))
		var hp_max := int(round(MAX_HP * kb)) + (6 if ab_id == "tough" else 0)
		var start_items: Array = ["potion"]
		if ab_id == "beast":
			start_items.append("meat")
		if pc.get("boost", false):
			start_items.append("potion")   # «Благословение сезона» тому, кто отстаёт в кампании
			hand.append(DB.random_trap(rng))
		players.append({
			"idx": i, "name": pc["name"], "slot": pc.get("slot", i), "hero": pc["hero"], "color": DB.PLAYER_COLORS[i],
			"hp": hp_max, "max_hp": hp_max, "dmg_mult": kb, "step_mult": 1.0 + (kb - 1.0) * 0.5,
			"ability": ab_id, "summons": [rng.randi_range(0, DB.summons.size() - 1)], "bonus_done": false,
			"rerolled": false, "moved": false, "block_summon": 0, "now_block_summon": false,
			"team": team, "wolves": 0, "bear": false, "bear_round": -1, "tamed": 0,
			"pos": start, "shards": 0, "hand": hand, "items": start_items,
			"dot": 0, "skip_move": 0, "slow": 0, "skip_turn": 0, "block_traps": 0, "vuln": 0,
			"now_skip_move": false, "now_slow": 0, "now_block_traps": false, "now_vuln": false,
			"marks": {}, "campfire": start, "warm_round": -1, "pet": pc.get("pet", false), "reports": [],
			"discovered": team_discovered[team] if team_mode else {}, "explored": team_explored[team] if team_mode else _initial_explored(), "die": game_die, "node": node, "lantern": lantern, "trail": [],
		})

func _team_start(team: int, used: Dictionary) -> Vector2i:
	var ax := int(map.w * (0.3 if team == 0 else 0.7))
	for off in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(-1, 2),
			Vector2i(2, 1), Vector2i(-2, 1), Vector2i(2, 2), Vector2i(-2, 2), Vector2i(0, 0), Vector2i(1, 0)]:
		var t: Vector2i = Vector2i(ax, 0) + off
		if map.inb(t) and map.passable(t) and not used.has(t):
			return t
	return Vector2i(ax, 1)

# ---------- команды
func allies_of(i: int) -> Array:
	if not team_mode:
		return [i]
	var a: Array = []
	for j in players.size():
		if players[j].team == players[i].team:
			a.append(j)
	return a

func is_enemy(i: int, j: int) -> bool:
	if i == j:
		return false
	return not team_mode or players[i].team != players[j].team

func _enemy_at(t: Vector2i, me: int) -> int:
	for j in players.size():
		if is_enemy(me, j) and players[j].pos == t:
			return j
	return -1

func team_shards(p: Dictionary) -> int:
	if not team_mode:
		return p.shards
	var n := 0
	for q in players:
		if q.team == p.team:
			n += q.shards
	return n

func team_name(team: int) -> String:
	return ["Красные", "Синие"][team]

func team_sees(t: Vector2i, who := -1) -> bool:
	var w: int = cur if who < 0 else who
	for j in allies_of(w):
		if can_see(players[j], t):
			return true
	return false

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
	if season_d["precip"] == "snow":
		_snow = true
		rain.amount = 900
		rain.lifetime = 4.0
		rain.direction = Vector3(0.3, -1, 0)
		rain.spread = 14.0
		rain.initial_velocity_min = 1.2
		rain.initial_velocity_max = 2.4
		rain.gravity = Vector3(0, -0.8, 0)
		var sm := Models.box(Vector3(0.05, 0.05, 0.05))
		var snm := StandardMaterial3D.new()
		snm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		snm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		snm.albedo_color = Color(1, 1, 1, 0.9)
		sm.material = snm
		rain.mesh = sm

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 220.0
	add_child(cam)
	cam.make_current()

# ================================================================= КАМЕРА И ВВОД
func _process(delta: float) -> void:
	if _press and not _dragging and Time.get_ticks_msec() - _press_t > 550:
		_press = false
		_on_long_press(_press_pos)
	if net:
		Engine.time_scale = 4.0 if _q.size() > 8 else 1.0
		_pump()
		if follow != null and is_instance_valid(follow) and not follow.visible and my_seat >= 0:
			follow = players[my_seat].node
	if follow != null and is_instance_valid(follow):
		cam_goal = follow.position
	cam_target = cam_target.lerp(cam_goal, 1.0 - exp(-delta * 4.0))
	if view_first and not _in_fight and not game_over:
		var n: Node3D = players[viewer()].node
		var head := n.position + Vector3(0, 0.95, 0)
		var dir := Vector3(sin(fp_yaw) * cos(fp_pitch), sin(fp_pitch), cos(fp_yaw) * cos(fp_pitch))
		cam.position = cam.position.lerp(head - dir * 0.1, 1.0 - exp(-delta * 10.0))
		cam.look_at(cam.position + dir, Vector3.UP)
		cam.fov = lerpf(cam.fov, 72.0, minf(delta * 6.0, 1.0))
	else:
		var off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), -cos(cam_yaw) * cos(cam_pitch)) * cam_dist
		cam.position = cam_target + off
		cam.look_at(cam_target + Vector3(0, 0.4, 0), Vector3.UP)
		cam.fov = lerpf(cam.fov, 50.0, minf(delta * 6.0, 1.0))
	if rain.emitting:
		rain.position = cam_target + Vector3(0, 9, 3)
	if info.get("foliage_mat"):
		var fm: ShaderMaterial = info["foliage_mat"]
		var w: float = fm.get_shader_parameter("wind") if fm.get_shader_parameter("wind") != null else 0.3
		fm.set_shader_parameter("wind", lerpf(w, wind, minf(delta, 1.0)))

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		if _touches.size() == 2:
			var ps := _touches.values()
			_pinch_d = (ps[0] as Vector2).distance_to(ps[1])
			_two_mid = ((ps[0] as Vector2) + (ps[1] as Vector2)) * 0.5
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
			var mid := ((ps[0] as Vector2) + (ps[1] as Vector2)) * 0.5
			_tilt(mid - _two_mid)
			_two_mid = mid
			_press = false
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = true
				_dragging = false
				_press_pos = e.position
				_press_t = Time.get_ticks_msec()
			else:
				if _press and not _dragging:
					_on_click(e.position)
				_press = false
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_rot = true
				_rot_moved = 0.0
			else:
				_rot = false
				if _rot_moved < 8.0:
					_on_long_press(e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom(1.1)
	elif e is InputEventMouseMotion and _rot:
		_rot_moved += e.relative.length()
		_tilt(e.relative)
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
			KEY_Q: _tilt(Vector2(50, 0))
			KEY_E: _tilt(Vector2(-50, 0))
			KEY_SPACE: _focus_current()

func _set_view(first: bool, save: bool) -> void:
	view_first = first
	if first:
		fp_yaw = players[viewer()].node.rotation.y
		fp_pitch = -0.35
	if save:
		Settings.set_pref(players[viewer()].name, "view", "first" if first else "third")
	refresh_view()
	hud.refresh()

## Немного повернуть/наклонить камеру (не на 360°, а чуть-чуть в стороны).
func _tilt(rel: Vector2) -> void:
	if view_first or _in_fight:
		return
	cam_yaw = clampf(cam_yaw - rel.x * 0.004, -YAW_LIMIT, YAW_LIMIT)
	cam_pitch = clampf(cam_pitch + rel.y * 0.003, PITCH_MIN, PITCH_MAX)

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
	follow = players[viewer()].node
	var tw := create_tween()
	tw.tween_property(self, "cam_yaw", 0.0, 0.4)
	tw.parallel().tween_property(self, "cam_pitch", deg_to_rad(50.0), 0.4)

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
	if net and (cur != my_seat or _echo_wait):
		_tile_hint(t)
		return
	if mode == "trap":
		if trap_targets.has(t):
			_cmd({"k": "trap", "h": pending_card, "t": [t.x, t.y]})
		return
	if mode == "summon":
		if summon_targets.has(t):
			_cmd({"k": "summon", "h": pending_summon, "t": [t.x, t.y]})
		return
	if rolled and reach.has(t):
		_cmd({"k": "walk", "t": [t.x, t.y]})
	else:
		_tile_hint(t)

func _tile_hint(t: Vector2i) -> void:
	var tt: int = map.get_t(t)
	if not _vx().has(t):
		hud.toast("Неизведанная земля. Подойди ближе, чтобы разглядеть.", Style.PARCH, 2.0)
		return
	var txt: String = MapGen.NAMES[tt]
	var c: int = map.cost(t)
	var lv: int = map.level(t)
	if c < 50:
		txt += " — шаг стоит %d" % c
		if lv > 0:
			txt += ", подняться сюда +1 за этаж (с холма видно на %d дальше)" % lv
	else:
		txt += " — не пройти"
	var o = objects.get(t)
	if o != null and _object_visible(o, players[viewer()]):
		match o["type"]:
			"beast":
				txt += ". Здесь %s (сила %d)" % [DB.beasts[o["kind"]]["name"], int(DB.beasts[o["kind"]]["power"])]
				if o["kind"] in ["wolf", "bear"]:
					txt += ". Подойди вплотную: правый клик или долгое нажатие — приручить"
			"chest": txt += ". Сундук"
			"shard": txt += ". Осколок!"
			"event": txt += ". Загадочный камень"
			"campfire": txt += ". Костёр — точка возрождения"
	if not rolled and (not net or cur == my_seat):
		txt += "   (сначала брось кубик)"
	hud.toast(txt, Style.PARCH, 2.0)

# ================================================================= СЕТЬ
const DEFAULT_BATTLE := {"blocked": false, "bonus": -1, "roll": 1, "total": 1}

## Команда игрока из интерфейса. По сети уходит на сервер и выполняется у всех одновременно, в одном порядке.
func _cmd(a: Dictionary) -> void:
	if not net:
		await _exec(a)
		return
	if cur != my_seat or _echo_wait or game_over or replaying:
		return
	_echo_wait = true
	Net.send_act(a)

func _exec(a: Dictionary) -> void:
	match str(a.get("k", "")):
		"roll":
			await roll(game_die)
		"reroll":
			await reroll()
		"end":
			await end_turn()
		"item":
			use_item(int(a["i"]))
		"trap":
			_place_trap(Vector2i(int(a["t"][0]), int(a["t"][1])), int(a["h"]))
		"summon":
			_place_summon(Vector2i(int(a["t"][0]), int(a["t"][1])), int(a["h"]))
		"walk":
			var t := Vector2i(int(a["t"][0]), int(a["t"][1]))
			if rolled and reach.has(t) and not busy:
				await _walk(_path_to(t))
		"press":
			await _long_press_tile(Vector2i(int(a["t"][0]), int(a["t"][1])))
		"skip":
			busy = false
			await end_turn()

func send_emote(i: int) -> void:
	Net.send({"t": "emote", "e": i})

func _on_emote(cid: int, e: int) -> void:
	if not _seat_of.has(cid) or e < 0 or e >= EMOTES.size():
		return
	var q: Dictionary = players[int(_seat_of[cid])]
	_float_text(q.node, EMOTES[e], q.color.lightened(0.3))
	if hud:
		hud.toast("%s: %s" % [q.name, EMOTES[e]], q.color.lightened(0.35), 2.5)

func _on_net_act(m: Dictionary) -> void:
	var seq := int(m.get("seq", 0))
	if seq <= _last_seq:
		return           # после переподключения сервер присылает всё заново
	_last_seq = seq
	_q.append(m)

func _on_caught_up() -> void:
	_caught = true

func _sys_act(m: Dictionary) -> bool:
	var a: Dictionary = m["a"]
	if str(a.get("k", "")) != "presence":
		return false
	var seat: int = _seat_of.get(int(a["cid"]), -1)
	if seat >= 0:
		if bool(a["online"]):
			_offline.erase(seat)
		else:
			_offline[seat] = true
		_update_offline_banner()
	return true

func _update_offline_banner() -> void:
	if not _offline.has(cur) or game_over:
		hud.set_offline(-1)
	else:
		hud.set_offline(cur)

## Раздаёт полученные действия по порядку, когда предыдущее закончилось.
func _pump() -> void:
	if _flow or _q.is_empty():
		if replaying and _caught and _q.is_empty() and not _flow:
			replaying = false
			hud.refresh()
		return
	var m: Dictionary = _q[0]
	var a: Dictionary = m["a"]
	var k := str(a.get("k", ""))
	if k == "presence":
		_q.pop_front()
		_sys_act(m)
		return
	if k == "next":
		if not game_over:
			_q.pop_front()   # лишнее «дальше» (нажали двое сразу) — не нужно
			return
		if not _camp_ready:
			return           # у нас ещё идёт ролик победы — ждём
		_q.pop_front()
		_advance(int(m.get("seq", 0)))
		return
	if k == "res":
		_q.pop_front()      # лишний ответ без вопроса — выбрасываем, чтобы не застрять
		return
	_q.pop_front()
	var seat: int = _seat_of.get(int(m.get("cid", -1)), -1)
	if seat == my_seat:
		_echo_wait = false
	if k == "skip":
		if not _offline.has(cur) or game_over:
			return
	elif seat != cur or game_over:
		return
	_flow = true
	await _exec(a)
	_flow = false
	if _echo_wait and seat == my_seat:
		_echo_wait = false
	cmd_done.emit(int(m.get("seq", 0)))

## Короткий «отпечаток» партии — для проверки, что у всех клиентов всё совпало.
func state_digest() -> String:
	var parts: Array = ["r%d" % round_no, "c%d" % cur, "h%.1f" % hour, "rng%d" % rng.state]
	for q in players:
		parts.append("%s:%d,%d:hp%d:s%d:t%d:i%d:w%d" % [q.name, q.pos.x, q.pos.y, q.hp, q.shards, q.hand.size(), q.items.size(), q.wolves])
	parts.append("u%d" % units.size())
	parts.append("tr%d" % traps.size())
	parts.append("o%d" % objects.size())
	return "|".join(parts)

## Решение игрока посреди хода (бой, выбор, бонусные карты).
## Тот, чей это ход, решает у себя на экране и отправляет ответ; остальные ждут его и видят то же самое.
func _ask(seat: int, kind: String, ui: Callable, wait_text: String, default: Variant, battle_fx := false) -> Variant:
	if not net:
		return await ui.call()
	var live := seat == my_seat and not replaying and not _res_ready()
	if live:
		var r = await ui.call()
		Net.send_act({"k": "res", "id": kind, "v": r})
	elif wait_text != "" and not _res_ready():
		hud.show_wait(wait_text)
	var v = await _wait_res(seat, default)
	if not live:
		hud.hide_wait()
		if battle_fx and typeof(v) == TYPE_DICTIONARY:
			await hud.replay_battle(v)
	return v

func _res_ready() -> bool:
	for m in _q:
		var k := str(m["a"].get("k", ""))
		if k == "res":
			return true
		if k != "presence":
			return false
	return false

func _wait_res(seat: int, default: Variant) -> Variant:
	while true:
		if not _q.is_empty():
			var m: Dictionary = _q[0]
			var k := str(m["a"].get("k", ""))
			if k == "res":
				_q.pop_front()
				return m["a"].get("v")
			if k == "presence":
				_q.pop_front()
				_sys_act(m)
				continue
		if _offline.has(seat) or game_over:
			return default
		await get_tree().process_frame
	return default

# ================================================================= ХОДЫ
func current() -> Dictionary:
	return players[cur]

func viewer() -> int:
	return my_seat if net and my_seat >= 0 else cur

func is_passive() -> bool:
	return net and (cur != my_seat or replaying)

func begin_turn() -> void:
	var p: Dictionary = players[cur]
	var V := viewer()
	rolled = false
	steps_left = 0
	mode = "move"
	p.rerolled = false
	p.moved = false
	_clear_highlight()
	follow = p.node
	var pr: Dictionary = Settings.pref(players[V].name)
	if not net or turn_count_started() == 0:
		view_first = pr["view"] == "first"
		Settings.set_music_enabled(pr["music"])
	fp_yaw = players[V].node.rotation.y
	fp_pitch = -0.35
	refresh_view()
	if net:
		_update_offline_banner()
	if net and not p.node.visible:
		follow = players[V].node
	_update_shrine_sockets()
	hud.set_phase("wait")
	hud.refresh()
	var reports: Array = p.reports.duplicate()
	p.reports.clear()
	if net:
		if cur == my_seat and not replaying:
			for r in reports:
				hud.toast(r, Style.GOLD, 4.0)
		await _turn_start_effects()
	elif players.size() > 1:
		hud.show_pass(p, reports)
	else:
		for r in reports:
			hud.toast(r, Style.GOLD, 4.0)
		_turn_start_effects()

var _turns_begun := 0
func turn_count_started() -> int:
	var n := _turns_begun
	_turns_begun += 1
	return n

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
	p.now_block_summon = p.block_summon > 0
	if p.block_summon > 0:
		p.block_summon -= 1
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
		await end_turn()
		return
	await _units_act(cur)
	if game_over:
		return
	if p.hp <= 0:
		await _respawn(p)
	if not p.bonus_done:
		p.bonus_done = true
		await _bonus_cards(p)
	hud.set_phase("roll")
	hud.refresh()

func roll(die: String) -> void:
	if rolled or busy or game_over:
		return
	var p: Dictionary = players[cur]
	die = game_die  # кубик выбран в меню и общий для всех до конца партии
	p.die = die
	var res := _compute_roll(p, die)
	var face: int = res[0]
	var steps: int = res[1]
	var notes: Array = res[2]
	busy = true
	hud.set_phase("busy")
	await hud.animate_roll(die, face, steps, " ".join(notes))
	busy = false
	rolled = true
	steps_left = steps
	hud.set_phase("act")
	_recalc()
	hud.refresh()

func can_reroll() -> bool:
	var p: Dictionary = players[cur]
	return rolled and p.ability == "lucky" and not p.rerolled and not p.moved and not busy

## Везунчик: раз за ход перебросить кубик, пока не сделал ни шага.
func reroll() -> void:
	if not can_reroll():
		return
	var p: Dictionary = players[cur]
	p.rerolled = true
	rolled = false
	_clear_highlight()
	var res := _compute_roll(p, p.die)
	busy = true
	hud.set_phase("busy")
	await hud.animate_roll(p.die, res[0], res[1], "Переброс! " + " ".join(res[2]))
	busy = false
	rolled = true
	steps_left = res[1]
	hud.set_phase("act")
	_recalc()
	hud.refresh()

func _compute_roll(p: Dictionary, die: String) -> Array:
	var faces: Array = DB.die_faces(die)
	var i := rng.randi_range(0, faces.size() - 1)
	var face := i + 1
	var steps := int(round(int(faces[i]) * float(p.step_mult)))
	var notes: Array = []
	if p.ability == "feet":
		steps += 1
		notes.append("Быстрые ноги: +1")
	var pigs := 0
	for u in units:
		if u["sid"] == "pig" and is_enemy(cur, u["owner"]) and _cheb(u["pos"], p.pos) <= 2:
			pigs += 1
	if pigs > 0:
		steps = maxi(0, steps - mini(pigs, 2))
		notes.append("Свинья мешает идти: −%d" % mini(pigs, 2))
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
	return [face, steps, notes]

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
		await _advance_round()
		if game_over:
			return
	await begin_turn()

func _advance_round() -> void:
	round_no += 1
	if boss:
		await _boss_turn()
		if game_over:
			return
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
	var wc: Array = season_d["weather"]
	var chance: float = wc[0] if hour < 17.0 else wc[1]
	var raining := rng.randf() < chance
	rain.emitting = raining
	wind = rng.randf_range(0.15, 0.5) + (0.6 if raining else 0.0)
	if raining:
		weather = "Снегопад" if _snow else "Дождь"
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
	var tint: Color = season_d["sky_tint"]
	var tk: float = season_d["tint_k"]
	sun.light_color = ((a[3] as Color).lerp(b[3], k)).lerp((a[3] as Color).lerp(b[3], k) * tint, tk)
	sun.light_energy = lerpf(a[4], b[4], k)
	var sky_t: Color = (a[5] as Color).lerp(b[5], k)
	var sky_h: Color = (a[6] as Color).lerp(b[6], k)
	sky_mat.sky_top_color = sky_t.lerp(sky_t * tint, tk)
	sky_mat.sky_horizon_color = sky_h.lerp(sky_h * tint, tk)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = sky_mat.sky_top_color.darkened(0.5)
	env.ambient_light_energy = lerpf(a[7], b[7], k)
	var nt := lerpf(a[8], b[8], k)
	env.fog_light_color = sky_mat.sky_horizon_color
	env.fog_density = 0.004 + nt * 0.016 + float(season_d["fog"])
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
	if boss:
		return 40	  # в пещере светло от пламени: видно всю арену
	var tt: int = map.get_t(p.pos)
	var r := 3
	if tt == MapGen.HILL:
		r = 4
	elif tt == MapGen.HILL2:
		r = 5
	elif tt == MapGen.FOREST:
		r = 2
	if night:
		r -= 1
	if p.items.has("torch"):
		r += 1
	if p.ability == "eye":
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

## Что клиент рисует: у каждого игрока по сети своя «карта знаний».
func _vx() -> Dictionary:
	return v_explored if net else players[cur].explored

func _vd() -> Dictionary:
	return v_discovered if net else players[cur].discovered

func _object_visible(o: Dictionary, p: Dictionary) -> bool:
	var pos: Vector2i = o["pos"]
	var ex: Dictionary = p.explored
	var di: Dictionary = p.discovered
	if net and p.idx == viewer():
		ex = v_explored
		di = v_discovered
	match o["type"]:
		"campfire", "chest", "event":
			return ex.has(pos)
	return di.has(pos) or team_sees(pos, p.idx)

## Туман войны: видимое — ярко, разведанное — тусклее, рядом с обзором — дымка с силуэтами, дальше — тьма.
func refresh_view() -> void:
	var V := viewer()
	var p: Dictionary = players[V]
	var r := vision(p)
	var vx: Dictionary = _vx()
	var vd: Dictionary = _vd()
	if net:
		# «логические» знания ходящего — одинаковые у всех клиентов
		var pc: Dictionary = players[cur]
		for j in allies_of(cur):
			var qc: Dictionary = players[j]
			var rc := vision(qc)
			for dz in range(-rc, rc + 1):
				for dx in range(-rc, rc + 1):
					var ec: Vector2i = qc.pos + Vector2i(dx, dz)
					if map.inb(ec):
						pc.explored[ec] = true
		for t in objects:
			if objects[t]["type"] in ["beast", "shard"] and team_sees(t, cur):
				pc.discovered[t] = true
		if pc.ability == "seeker":
			_seeker(pc, pc.explored, pc.discovered, false)
	var viewers: Array = []
	for j in allies_of(V):
		var q: Dictionary = players[j]
		var rq := vision(q)
		viewers.append([q.pos, rq])
		for dz in range(-rq, rq + 1):
			for dx in range(-rq, rq + 1):
				var e: Vector2i = q.pos + Vector2i(dx, dz)
				if map.inb(e):
					vx[e] = true
	var refs: Dictionary = info["tile_ref"]
	var decor: Dictionary = info["decor_ref"]
	var fog_items: Array = []
	for t in refs:
		var tp: Vector2i = t
		var ref: Array = refs[t]
		var base: Color = ref[2]
		# насколько клетка дальше границы обзора ближайшего союзника (0 и меньше — видно)
		var margin := 9999
		for vw in viewers:
			var vp: Vector2i = vw[0]
			margin = mini(margin, maxi(absi(tp.x - vp.x), absi(tp.y - vp.y)) - int(vw[1]))
		var k := 1.0
		if margin > 0:
			if vx.has(tp):
				k = 0.6
			else:
				k = 0.4
				fog_items.append([tp, FOG_HAZE if margin <= 2 else FOG_DARK])
		var dark: bool = night and tp.y <= dark_row
		var c := _tint(base, k, dark)
		(ref[0] as MultiMesh).set_instance_color(ref[1], c)
		if decor.has(tp):
			for dr in decor[tp]:
				(dr[0] as MultiMesh).set_instance_color(dr[1], _tint(dr[2], k, dark))
	_set_fog(fog_items)
	for bt in info["bridge_nodes"]:
		var bd := maxi(absi(bt.x - p.pos.x), absi(bt.y - p.pos.y))
		info["bridge_nodes"][bt].visible = vx.has(bt) or bd <= r + 2
	if p.ability == "seeker":
		_seeker(p, vx, vd, true)
	for t in objects:
		var o: Dictionary = objects[t]
		if o["type"] in ["beast", "shard"] and team_sees(t, V):
			vd[t] = true
		o["node"].visible = _object_visible(o, p)
	for i in players.size():
		var q2: Dictionary = players[i]
		var vis: bool = i == V or not is_enemy(V, i) or team_sees(q2.pos, V) or p.marks.has(i)
		q2.node.visible = vis and not (i == V and view_first)
		q2.node.get_node("Ring").visible = i == cur
	for tr in traps:
		tr["node"].visible = not is_enemy(V, tr["owner"])
	for u in units:
		u["node"].visible = not is_enemy(V, u["owner"]) or team_sees(u["pos"], V)
	_update_lights()

## Чутьё на кристаллы: осколки рядом отмечаются на карте.
func _seeker(pl: Dictionary, ex: Dictionary, di: Dictionary, say: bool) -> void:
	var r := vision(pl)
	for t in objects:
		if objects[t]["type"] == "shard" and _cheb(t, pl.pos) <= r + 3 and not ex.has(t):
			ex[t] = true
			di[t] = true
			if say and not pl.get("seeker_told", {}).has(t):
				var told: Dictionary = pl.get("seeker_told", {})
				told[t] = true
				pl["seeker_told"] = told
				hud.toast("Чутьё на кристаллы: рядом сияет осколок!", Style.TEAL, 2.5)

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
		s.material_override = Models.mat(Color("7fe3ff"), 2.0) if team_shards(p) > i else Models.mat(Color("333333"))

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
			var step_c: int = map.move_cost(c, n)
			if step_c >= 50:
				continue
			var nd: int = dist[c] + step_c
			if nd > steps_left:
				continue
			if dist.has(n) and dist[n] <= nd:
				continue
			dist[n] = nd
			prev[n] = c
			var o = objects.get(n)
			var blocked := false
			if o != null and o["type"] in ["beast", "chest", "event", "boss"]:
				blocked = true
			var opp := _enemy_at(n, cur)
			if opp >= 0 and team_sees(n):
				blocked = true
			var un = _unit_at(n)
			if un != null and is_enemy(cur, un["owner"]) and not _untouchable(un) and team_sees(n):
				blocked = true
			if map.get_t(n) == MapGen.SHRINE and team_shards(p) < 3:
				blocked = true
			if blocked:
				targets[n] = true
			else:
				targets.erase(n)
				open.append(n)
	dist.erase(p.pos)
	# на клетке союзника (и своего зверя) можно пройти, но не остановиться
	for t in dist.keys():
		var u2 = _unit_at(t)
		if u2 != null and not (is_enemy(cur, u2["owner"]) and not _untouchable(u2)):
			dist.erase(t)
			continue
		for j in players.size():
			if j != cur and not is_enemy(cur, j) and players[j].pos == t:
				dist.erase(t)
				break
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
			var ob = objects.get(t)
			if ob != null and ob["type"] in ["chest", "event"]:
				col = Color(1.0, 0.8, 0.2, 0.65)
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
	p.moved = true
	follow = p.node
	for step in path:
		var tile: Vector2i = step
		var c: int = map.move_cost(p.pos, tile)
		var o = objects.get(tile)
		if o != null and o["type"] in ["chest", "event"]:
			# к сундукам и камням подходим вплотную, а не наступаем на них
			_face(p, tile)
			steps_left -= c
			p.node.set("walking", false)
			await _use_object(p, tile, o)
			break
		if o != null and o["type"] == "beast":
			_face(p, tile)
			steps_left -= c
			await _fight_beast(p, tile, o)
			break
		if o != null and o["type"] == "boss":
			_face(p, tile)
			steps_left -= c
			await _fight_boss(p, o)
			break
		var eu = _unit_at(tile)
		if eu != null and is_enemy(cur, eu["owner"]) and not _untouchable(eu):
			_face(p, tile)
			steps_left -= c
			await _fight_unit(p, eu)
			break
		var opp := _enemy_at(tile, cur)
		if opp >= 0:
			_face(p, tile)
			steps_left -= c
			players[opp].node.visible = true
			await _duel(p, players[opp])
			break
		if map.get_t(tile) == MapGen.SHRINE:
			if team_shards(p) >= 3:
				await _move_hero(p, tile)
				p.pos = tile
				p.node.walking = false
				_victory(p)
				return
			hud.toast("Ворота горы запечатаны. Нужно 3 осколка, у %s %d." % ["команды" if team_mode else "тебя", team_shards(p)], Style.GOLD, 3.0)
			break
		var from: Vector2i = p.pos
		await _move_hero(p, tile)
		p.pos = tile
		p.trail.append(from)
		if p.trail.size() > 20:
			p.trail.pop_front()
		steps_left -= c
		refresh_view()
		if await _bear_guard(p):
			break
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
	if o != null and o["type"] == "shard":
		await _use_object(p, tile, o)
	var cf := _campfire_near(tile)
	if cf.x >= 0:
		p.campfire = tile
		if p.warm_round != round_no:
			p.warm_round = round_no
			p.hp = mini(p.max_hp, p.hp + 3)
			_float_text(p.node, "+3 HP", Style.GREEN)
			hud.toast("Костёр согрел тебя: +3 HP. Здесь ты очнёшься, если лишишься сил.", Color("ffb070"), 3.0)
	var hit: Array = []
	for tr in traps:
		if tr["pos"] == tile and is_enemy(cur, tr["owner"]):
			hit.append(tr)
	for tr in hit:
		await _trigger_trap(tr, p)
		stop = true
	return stop

## Костёр стоит на стыке 4 клеток; греются на любой из них.
func _campfire_near(tile: Vector2i) -> Vector2i:
	for c in map.campfires:
		var d: Vector2i = tile - c
		if d.x >= 0 and d.x <= 1 and d.y >= 0 and d.y <= 1:
			return c
	return Vector2i(-1, -1)

## Сундук, камень «?» или осколок. Возвращает true, если ход нужно остановить.
func _use_object(p: Dictionary, tile: Vector2i, o: Dictionary) -> bool:
	var stop := false
	if true:
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
	if r < 0.14:
		var si := rng.randi_range(0, DB.summons.size() - 1)
		p.summons.append(si)
		return "карта призыва «%s»" % DB.summons[si]["name"]
	if r < 0.5:
		var c := DB.random_trap(rng)
		p.hand.append(c)
		return "карта ловушки «%s»" % DB.traps[c]["name"]
	var keys := ["potion", "potion", "boots", "torch", "meat", "meat", "meat"]
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
				if net and p.idx == viewer():
					v_discovered[best] = true
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
			p.hp = mini(p.max_hp, p.hp + 6)
			_float_text(p.node, "+6 HP", Style.GREEN)
		"honey":
			p.hp = p.max_hp
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
func trap_cost(card: int) -> int:
	var c := DB.trap_price(card)
	if players[cur].ability == "trapper":
		c = maxi(1, c - 1)
	return c

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
	var price := trap_cost(card)
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

func _place_trap(t: Vector2i, h: int) -> void:
	var p: Dictionary = players[cur]
	if h < 0 or h >= p.hand.size() or _cheb(t, p.pos) > 1 or steps_left < trap_cost(p.hand[h]):
		return
	var card: int = p.hand[h]
	p.hand.remove_at(h)
	steps_left -= trap_cost(card)
	p.moved = true
	var n := Models.trap_marker()
	n.position = map.world_pos(t)
	entities.add_child(n)
	traps.append({"owner": cur, "pos": t, "card": card, "node": n})
	if not net or cur == my_seat:
		hud.toast("Ловушка «%s» спрятана. Её видишь только ты." % DB.traps[card]["name"], Color("e0a0ff"), 3.0)
	elif is_enemy(viewer(), cur):
		n.visible = false
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
	var dmg := int(round(int(fx.get("dmg", 0)) * float(owner.dmg_mult)))
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
		p.block_summon += 1
		lines.append("в следующий ход нельзя призывать животных")
	if fx.has("vuln"):
		p.vuln += int(fx["vuln"])
		lines.append("атаки по тебе сильнее на 1")
	if fx.has("heal_owner"):
		owner.hp = mini(owner.max_hp, owner.hp + int(fx["heal_owner"]))
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
	var res: Dictionary = await _ask(cur, "battle", func(): return await hud.battle(p.name, def["name"], info, "Чтобы победить, нужно набрать %d или больше" % power, false, p.color, p.ability == "agile"), "%s сражается с существом: %s…" % [p.name, def["name"]], DEFAULT_BATTLE, true)
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
		o["hits"] -= int(round(float(p.dmg_mult))) + int(p.wolves)
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
		elif o["kind"] == "bear":
			p.items.append("honey")
			hud.toast("Медведь ушёл в чащу и оставил банку мёда!", Style.GOLD, 3.0)
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
	var r: Dictionary = await _ask(cur, "battle", func(): return await hud.battle(p.name, q.name, "Потом %s сам бросит кубик" % q.name + (" (+1, он в лесу)" if forest else ""), "Побеждает тот, у кого больше", true, p.color, p.ability == "agile"), "%s нападает на героя %s…" % [p.name, q.name], DEFAULT_BATTLE, true)
	var a := int(r["total"])
	var d: int = int(await _ask(q.idx, "extra", func(): return await hud.extra_roll(q.name, q.color, 1 if forest else 0), "%s защищается — бросает кубик…" % q.name, 1))
	var res := "Ничья: %d против %d. Оба −1 HP" % [a, d]
	if a > d:
		res = "%s побеждает: %d против %d!" % [p.name, a, d]
	elif d > a:
		res = "%s отбивается: %d против %d. −2 HP" % [q.name, d, a]
	await hud.battle_finish(res, a > d)
	_end_fight()
	if a > d and _has_unit(cur, "bear"):
		p.items.append("honey")
		hud.toast("Легендарный медведь доволен победой: банка мёда!", Style.GOLD, 3.0)
	if a > d:
		var dmg := int(round(2 * float(p.dmg_mult))) + 2 * int(p.wolves) + (1 if q.vuln > 0 else 0)
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
		_damage(p, int(round(2 * float(q.dmg_mult))) + 2 * int(q.wolves))
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


# ================================================================= БОСС
func _boss_tile(t: Vector2i) -> bool:
	return absi(t.x - map.boss_pos.x) <= 1 and absi(t.y - map.boss_pos.y) <= 1

func _boss_phase2() -> bool:
	return boss_hp * 2 <= boss_max

func _fight_boss(p: Dictionary, o: Dictionary) -> void:
	_stop_walk(p)
	boss_node.rotation.y = 0.0
	_begin_fight(p.node, boss_node)
	var info := "Здоровье: %d из %d • Урон: %d" % [boss_hp, boss_max, BOSS_HIT + (1 if _boss_phase2() else 0)]
	var res: Dictionary = await _ask(cur, "battle", func(): return await hud.battle(p.name, "Огненный дракон", info, "Чтобы попасть, нужно набрать %d или больше" % BOSS_POWER, false, p.color, p.ability == "agile"), "%s бьёт дракона…" % p.name, DEFAULT_BATTLE, true)
	var total := int(res["total"])
	var win: bool = total >= BOSS_POWER
	var dmg := 0
	if win:
		dmg = maxi(1, int(round(float(p.dmg_mult)))) + int(p.wolves) + (1 if total >= BOSS_POWER + 3 else 0)
		dmg = mini(dmg, boss_hp)
	await hud.battle_finish(("Попал! Дракон теряет %d." % dmg) if win else "Мимо... %d против %d. Дракон огрызается." % [total, BOSS_POWER], win)
	_end_fight()
	if win:
		boss_hp -= dmg
		boss_dmg[p.idx] += dmg
		_float_text(boss_node, "−%d" % dmg, Style.GOLD)
		var tw := create_tween()
		tw.tween_property(boss_node, "position:x", boss_node.position.x + 0.12, 0.05)
		tw.tween_property(boss_node, "position:x", boss_node.position.x - 0.12, 0.1)
		tw.tween_property(boss_node, "position:x", boss_node.position.x, 0.05)
		hud.refresh()
		if boss_hp <= 0:
			boss_killer = p.idx
			boss_defeated = true
			await _boss_end()
			return
		if _boss_phase2() and boss_hp + dmg > boss_max / 2:
			hud.big_banner("Дракон в ярости!", "Теперь он бьёт сильнее и по двум местам")
	else:
		var d2 := BOSS_HIT + (1 if _boss_phase2() else 0) + (1 if p.now_vuln or p.vuln > 0 else 0)
		_damage(p, d2)
		hud.toast("Дракон огрызнулся: −%d HP" % d2, Style.RED, 3.0)

## В конце круга дракон бьёт по клеткам, отмеченным заранее, и выбирает новые.
func _boss_turn() -> void:
	busy = true
	hud.set_phase("busy")
	var dmg := BOSS_HIT + (1 if _boss_phase2() else 0)
	if not boss_tele.is_empty():
		follow = null
		cam_goal = boss_node.position + Vector3(0, 0.5, 3.0)
		await get_tree().create_timer(0.5).timeout
		await _boss_strike(dmg)
	_boss_clear_tele()
	if boss_defeated or game_over:
		busy = false
		return
	if round_no > Camp.BOSS_ROUNDS:
		await _boss_end()
		busy = false
		return
	_boss_plan()
	if round_no == Camp.BOSS_ROUNDS:
		hud.toast("Последний круг! Если дракон устоит, он улетит.", Style.RED, 4.0)
	else:
		hud.toast("Круг %d из %d • Дракон готовит: %s" % [round_no, Camp.BOSS_ROUNDS, boss_tele_kind], Color("ff8a5a"), 3.5)
	follow = players[0].node
	busy = false

func _boss_plan() -> void:
	boss_tele.clear()
	var kinds := ["Огненное дыхание", "Удар хвостом", "Огненный дождь"]
	boss_tele_kind = kinds[rng.randi_range(0, kinds.size() - 1)]
	var c: Vector2i = map.boss_pos
	match boss_tele_kind:
		"Огненное дыхание":
			var cols: Array = []
			var who: int = rng.randi_range(0, players.size() - 1)
			cols.append(players[who].pos.x)
			if _boss_phase2():
				cols.append(clampi(players[(who + 1) % players.size()].pos.x, 1, map.w - 2))
			for x in cols:
				for dx in (range(-0, 1) if not _boss_phase2() else range(-0, 1)):
					for z in range(c.y + 2, map.h - 1):
						var t := Vector2i(int(x) + dx, z)
						if map.passable(t) and not boss_tele.has(t):
							boss_tele.append(t)
		"Удар хвостом":
			for z in range(c.y - 3, c.y + 4):
				for x in range(c.x - 3, c.x + 4):
					var t := Vector2i(x, z)
					if map.inb(t) and map.passable(t) and not _boss_tile(t) and maxi(absi(x - c.x), absi(z - c.y)) <= (2 if not _boss_phase2() else 3):
						boss_tele.append(t)
		_:
			var n := 7 + (4 if _boss_phase2() else 0) + players.size()
			var tries := 0
			while boss_tele.size() < n and tries < 200:
				tries += 1
				var t := Vector2i(rng.randi_range(1, map.w - 2), rng.randi_range(c.y + 2, map.h - 2))
				if map.passable(t) and not boss_tele.has(t):
					boss_tele.append(t)
	_boss_show_tele()
	# дракон поворачивает голову и набирает воздух
	if boss_node:
		var tw := create_tween()
		tw.tween_property(boss_node, "scale", Vector3.ONE * 1.06, 0.3)
		tw.tween_property(boss_node, "scale", Vector3.ONE, 0.3)

func _boss_show_tele() -> void:
	if boss_tele_node != null and is_instance_valid(boss_tele_node):
		boss_tele_node.queue_free()
	boss_tele_node = Node3D.new()
	add_child(boss_tele_node)
	for t in boss_tele:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.92, 0.92)
		q.orientation = PlaneMesh.FACE_Y
		m.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.18, 0.05, 0.5)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = false
		m.material_override = mat
		m.position = map.world_pos(t) + Vector3(0, 0.06, 0)
		boss_tele_node.add_child(m)
	var tw := boss_tele_node.create_tween().set_loops()
	tw.tween_property(boss_tele_node, "position:y", 0.03, 0.4)
	tw.tween_property(boss_tele_node, "position:y", 0.0, 0.4)

func _boss_clear_tele() -> void:
	if boss_tele_node != null and is_instance_valid(boss_tele_node):
		boss_tele_node.queue_free()
	boss_tele_node = null
	boss_tele.clear()

func _boss_strike(dmg: int) -> void:
	Settings.play("night", 0.0)
	var jaw := boss_node.get_node_or_null("Body/Neck/Head/Jaw")
	var glow: OmniLight3D = boss_node.get_node_or_null("Glow")
	if jaw:
		var tj := create_tween()
		tj.tween_property(jaw, "rotation:x", 0.6, 0.2)
		tj.tween_interval(0.6)
		tj.tween_property(jaw, "rotation:x", 0.0, 0.3)
	if glow:
		var tg := create_tween()
		tg.tween_property(glow, "light_energy", 6.0, 0.2)
		tg.tween_property(glow, "light_energy", 1.4, 0.8)
	for t in boss_tele:
		var f := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 1.0, 0.7)
		f.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.45, 0.1, 0.85)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.05)
		mat.emission_energy_multiplier = 2.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.material_override = mat
		f.position = map.world_pos(t) + Vector3(0, 0.1, 0)
		f.scale = Vector3(1, 0.05, 1)
		add_child(f)
		var tw := create_tween()
		tw.tween_property(f, "scale:y", 1.4, 0.25)
		tw.parallel().tween_property(f, "position:y", f.position.y + 0.6, 0.25)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.tween_callback(f.queue_free)
	await get_tree().create_timer(0.7).timeout
	var any := false
	for q in players:
		if q.hp > 0 and boss_tele.has(q.pos):
			any = true
			var d: int = dmg + (1 if q.now_vuln or q.vuln > 0 else 0)
			_damage(q, d)
			hud.toast("%s обожжён: −%d HP" % [q.name, d], Style.RED, 2.5)
	if not any:
		hud.toast("Все увернулись!", Style.GREEN, 2.0)
	await get_tree().create_timer(0.6).timeout
	for q in players:
		if q.hp <= 0:
			await _respawn(q)

## Конец боя: дракон повержен или улетел.
func _boss_end() -> void:
	game_over = true
	_clear_highlight()
	_boss_clear_tele()
	hud.set_phase("over")
	follow = null
	cam_goal = boss_node.position + Vector3(0, 1.0, 0)
	var tw0 := create_tween()
	tw0.tween_property(self, "cam_pitch", deg_to_rad(28.0), 1.0)
	tw0.parallel().tween_property(self, "cam_dist", 8.0, 1.0)
	if boss_defeated:
		Settings.play("victory", 0.0)
		var tw := create_tween()
		tw.tween_property(boss_node, "rotation:z", 0.5, 1.4).set_trans(Tween.TRANS_BOUNCE)
		tw.parallel().tween_property(boss_node, "position:y", boss_node.position.y - 0.35, 1.4)
		var glow: OmniLight3D = boss_node.get_node_or_null("Glow")
		if glow:
			tw.parallel().tween_property(glow, "light_energy", 0.0, 2.0)
		await get_tree().create_timer(2.6).timeout
	else:
		var tw2 := create_tween()
		tw2.tween_property(boss_node, "position:y", boss_node.position.y + 6.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await get_tree().create_timer(2.4).timeout
	_boss_finish()

## Очки главы: больше всех урона — 3, остальные, кто бил, — 1, последний удар даёт ещё 1.
func _boss_finish() -> void:
	var prev: Array = camp_data.get("scores", [])
	var best := 0
	for v in boss_dmg:
		best = maxi(best, int(v))
	var top_ids: Array = []
	var pts: Array = []
	var hit_count := 0
	for q in players:
		if int(boss_dmg[q.idx]) > 0:
			hit_count += 1
	for q in players:
		var pt := 0
		if boss_defeated:
			if best > 0 and int(boss_dmg[q.idx]) == best:
				pt = 3
				top_ids.append(q.idx)
			elif int(boss_dmg[q.idx]) > 0:
				pt = 1
			if q.idx == boss_killer:
				pt += 1
		pts.append(pt)
	var scores: Array = []
	for q in players:
		scores.append((int(prev[q.idx]) if q.idx < prev.size() else 0) + pts[q.idx])
	_camp_scores = scores
	var wins: Array = camp_data.get("wins", []).duplicate()
	wins.append(top_ids)
	_camp_wins = wins
	_camp_win_ids = top_ids
	var got: Array = []
	if boss_defeated:
		for i in top_ids:
			got.append({"who": players[i].name, "id": "dragon_bravest"})
		if boss_killer >= 0:
			got.append({"who": players[boss_killer].name, "id": "dragon_slayer"})
		if hit_count == players.size() and players.size() > 1:
			for q in players:
				got.append({"who": q.name, "id": "dragon_team"})
	var champ := 0
	for v in scores:
		champ = maxi(champ, int(v))
	for q in players:
		if int(scores[q.idx]) == champ:
			got.append({"who": q.name, "id": "campaign_leader"})
	for e in got:
		if not net or players[my_seat].name == e["who"]:
			Camp.grant(str(e["who"]), str(e["id"]))
	_camp_ready = true
	var rows: Array = []
	for q in players:
		rows.append({"name": q.name, "color": DB.TEAM_COLORS[q.team] if team_mode else q.color, "pts": pts[q.idx], "total": scores[q.idx],
			"win": top_ids.has(q.idx), "team": q.team, "dmg": int(boss_dmg[q.idx])})
	var names: Array = []
	for q in players:
		if int(scores[q.idx]) == champ:
			names.append(q.name)
	var wtxt := "Дракон повержен! Больше всех урона: %s" % ", ".join(top_ids.map(func(i): return players[i].name)) if boss_defeated else "Дракон улетел. Победить его не удалось"
	hud.show_round_result({
		"chapter": chapter, "final": true, "winner": wtxt, "wcol": Color("ff9a4a") if boss_defeated else Color("b0b0b0"), "rows": rows, "ach": got,
		"story": Camp.AFTER[3] if boss_defeated else Camp.AFTER_FAIL, "next_name": "",
		"team_mode": team_mode, "code": map_code, "champion": "Победитель кампании: %s (%d очк.)" % [", ".join(names), champ],
	})

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
	await hud.alert("%s без сил..." % p.name, "Герой очнётся у последнего костра. Потерян один осколок и одна карта.", Style.RED)
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
	var idx: int = p.idx
	if _player_at(cf, idx) >= 0:
		for d in DIRS:
			if map.passable(cf + d) and _player_at(cf + d, idx) < 0:
				cf = cf + d
				break
	p.hp = int(p.max_hp * 0.6)
	p.pos = cf
	p.trail.clear()
	p.node.position = map.world_pos(cf)
	refresh_view()

# ================================================================= ПРИЗЫВЫ
func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _unit_at(t: Vector2i):
	for u in units:
		if u["pos"] == t:
			return u
	return null

func _has_unit(owner: int, sid: String) -> bool:
	for u in units:
		if u["owner"] == owner and u["sid"] == sid:
			return true
	return false

## Хомячок прячется, попугай летает — героем их не достать.
func _untouchable(u: Dictionary) -> bool:
	return u["sid"] in ["hamster", "parrot"]

func summon_cost(si: int) -> int:
	var c := int(DB.summons[si].get("cost", 4))
	if players[cur].ability == "beast":
		c = maxi(1, c - 1)
	return c

func _tile_free_for_unit(t: Vector2i) -> bool:
	if not map.passable(t) or map.get_t(t) == MapGen.SHRINE:
		return false
	var o = objects.get(t)
	if o != null and o["type"] != "campfire":
		return false
	if _unit_at(t) != null:
		return false
	for q in players:
		if q.pos == t:
			return false
	return true

func start_summon_mode(hand_idx: int) -> void:
	if busy or game_over:
		return
	var p: Dictionary = players[cur]
	if p.now_block_summon:
		hud.toast("«Глушитель»: в этот ход призывать нельзя", Style.RED, 3.0)
		return
	if not rolled:
		hud.toast("Сначала брось кубик: призыв стоит шагов", Style.GOLD)
		return
	var si: int = p.summons[hand_idx]
	var cost := summon_cost(si)
	if steps_left < cost:
		hud.toast("Нужно %d шагов, а осталось %d" % [cost, steps_left], Style.RED)
		return
	pending_summon = hand_idx
	mode = "summon"
	summon_targets.clear()
	var items: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t: Vector2i = p.pos + Vector2i(dx, dz)
			if t != p.pos and _tile_free_for_unit(t):
				summon_targets[t] = true
				items.append([t, Color(0.3, 1.0, 0.5, 0.6)])
	_set_highlight(items)
	hud.set_phase("trap")
	hud.toast("Нажми на зелёную клетку рядом, чтобы призвать: %s" % DB.summons[si]["name"], Style.GREEN, 3.0)

func _place_summon(t: Vector2i, h: int) -> void:
	var p: Dictionary = players[cur]
	if h < 0 or h >= p.summons.size() or _cheb(t, p.pos) > 1 or t == p.pos or steps_left < summon_cost(p.summons[h]):
		return
	var si: int = p.summons[h]
	p.summons.remove_at(h)
	steps_left -= summon_cost(si)
	p.moved = true
	_spawn_unit(cur, si, t)
	mode = "move"
	hud.set_phase("act")
	_recalc()
	hud.refresh()

func _spawn_unit(owner: int, si: int, t: Vector2i) -> void:
	var def: Dictionary = DB.summons[si]
	var sid: String = def["id"]
	var n := Models.summon_model(sid)
	n.position = map.world_pos(t)
	entities.add_child(n)
	var tag := Label3D.new()
	tag.font = Style.font_bold
	tag.font_size = 34
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.pixel_size = 0.004
	tag.position = Vector3(0, 0.9, 0)
	tag.modulate = players[owner].color.lightened(0.35)
	n.add_child(tag)
	var u := {"owner": owner, "sid": sid, "idx": si, "pos": t, "hp": int(def["hp"]), "max_hp": int(def["hp"]),
		"dmg": int(def.get("dmg", 1)), "node": n, "tag": tag, "life": 5, "name": def["name"]}
	units.append(u)
	_update_unit_tag(u)
	if sid == "wolf":
		players[owner].wolves += 1
	n.scale = n.scale * 0.1
	var tw := create_tween()
	tw.tween_property(n, "scale", n.scale * 10.0, 0.35).set_trans(Tween.TRANS_BACK)
	Settings.play("magic")
	_float_text(n, "Призыв!", Style.GREEN)
	refresh_view()

func _update_unit_tag(u: Dictionary) -> void:
	u["tag"].text = "%s %d HP" % [u["name"], u["hp"]]

func _remove_unit(u: Dictionary, why: String) -> void:
	units.erase(u)
	if u["sid"] == "wolf":
		players[u["owner"]].wolves = maxi(0, players[u["owner"]].wolves - 1)
	var n: Node3D = u["node"]
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(n.queue_free)
	if why != "":
		hud.toast(why, Style.GOLD, 3.0)

func _nearest_enemy(u: Dictionary, max_d: int) -> int:
	var best := -1
	var bd := 9999
	for j in players.size():
		if not is_enemy(u["owner"], j):
			continue
		var d := _cheb(players[j].pos, u["pos"])
		if d <= max_d and d < bd:
			bd = d
			best = j
	return best

func _unit_move(u: Dictionary, target: Vector2i, max_steps: int, stop_d: int, away := false) -> void:
	for k in max_steps:
		var d0 := _cheb(u["pos"], target)
		if not away and d0 <= stop_d:
			return
		var best := Vector2i(-999, -999)
		var bd := d0
		for dd in DIRS:
			var nt: Vector2i = u["pos"] + dd
			if not _tile_free_for_unit(nt) or map.move_cost(u["pos"], nt) >= 50:
				continue
			var nd := _cheb(nt, target)
			if (not away and nd < bd) or (away and nd > bd):
				bd = nd
				best = nt
		if best.x == -999:
			return
		var n: Node3D = u["node"]
		var a := n.position
		var b: Vector3 = map.world_pos(best)
		var dv: Vector2i = best - u["pos"]
		n.rotation.y = atan2(float(dv.x), float(dv.y))
		u["pos"] = best
		var tw := create_tween()
		tw.tween_method(func(kk: float): n.position = a.lerp(b, kk) + Vector3(0, sin(kk * PI) * 0.12, 0), 0.0, 1.0, 0.2)
		await tw.finished

func _unit_hit(u: Dictionary, victim_i: int, dmg: int, verb: String) -> void:
	var v: Dictionary = players[victim_i]
	var n: Node3D = u["node"]
	var home := n.position
	var to: Vector3 = v.node.position
	n.rotation.y = atan2(to.x - home.x, to.z - home.z)
	var tw := create_tween()
	tw.tween_property(n, "position", home.lerp(to, 0.4), 0.12)
	tw.tween_property(n, "position", home, 0.18)
	await tw.finished
	Settings.play("hit")
	_damage(v, dmg)
	var owner: Dictionary = players[u["owner"]]
	v.reports.append("%s игрока %s %s тебя (−%d HP)." % [u["name"], owner.name, verb, dmg])
	hud.toast("%s %s героя %s: −%d HP" % [u["name"], verb, v.name, dmg], owner.color.lightened(0.3), 2.5)
	if v.hp <= 0 and victim_i != cur:
		await _respawn(v)

## Призванные звери действуют сами в начале хода хозяина.
func _units_act(owner: int) -> void:
	var mine: Array = []
	for u in units:
		if u["owner"] == owner:
			mine.append(u)
	if mine.is_empty():
		return
	var p: Dictionary = players[owner]
	for u in mine:
		if not units.has(u):
			continue
		var sid: String = u["sid"]
		match sid:
			"dog", "cat", "bear":
				var rng_d: int = {"dog": 7, "cat": 5, "bear": 8}[sid]
				var steps: int = {"dog": 3, "cat": 2, "bear": 1}[sid]
				var e := _nearest_enemy(u, rng_d)
				if e >= 0:
					await _unit_move(u, players[e].pos, steps, 1)
					if _cheb(u["pos"], players[e].pos) <= 1:
						await _unit_hit(u, e, u["dmg"], "укусил" if sid != "bear" else "ударил")
				elif _cheb(u["pos"], p.pos) > 2:
					await _unit_move(u, p.pos, steps, 1)
			"parrot":
				var e2 := _nearest_enemy(u, 6)
				if e2 >= 0:
					await _unit_move(u, players[e2].pos, 2, 2)
					if _cheb(u["pos"], players[e2].pos) <= 2:
						await _unit_hit(u, e2, u["dmg"], "клюнул")
				elif _cheb(u["pos"], p.pos) > 2:
					await _unit_move(u, p.pos, 2, 1)
			"hamster":
				var e3 := _nearest_enemy(u, 3)
				if e3 >= 0:
					await _unit_hit(u, e3, u["dmg"], "куснул")
			"fox":
				var e4 := _nearest_enemy(u, 4)
				if e4 >= 0:
					await _unit_move(u, players[e4].pos, 2, 1)
					if _cheb(u["pos"], players[e4].pos) <= 1:
						await _unit_hit(u, e4, u["dmg"], "цапнула")
						await _unit_move(u, players[e4].pos, 2, 0, true)
			"pig":
				if _cheb(u["pos"], p.pos) > 3:
					await _unit_move(u, p.pos, 2, 2)
			"cow":
				if _cheb(u["pos"], p.pos) > 1:
					await _unit_move(u, p.pos, 2, 1)
				if _cheb(u["pos"], p.pos) <= 2 and p.hp < p.max_hp:
					p.hp = mini(p.max_hp, p.hp + 1)
					_float_text(p.node, "+1 HP", Style.GREEN)
					hud.toast("Корова подлечила хозяина: +1 HP", Style.GREEN, 2.0)
			"chicken":
				var e5 := _nearest_enemy(u, 4)
				if e5 >= 0:
					await _unit_hit(u, e5, u["dmg"], "попала яйцом в")
				elif _cheb(u["pos"], p.pos) <= 1 and p.hp < p.max_hp:
					p.hp = mini(p.max_hp, p.hp + 2)
					_float_text(p.node, "+2 HP", Style.GREEN)
				else:
					await _unit_move(u, p.pos, 2, 1)
			"wolf":
				if _cheb(u["pos"], p.pos) > 1:
					await _unit_move(u, p.pos, 3, 1)
		u["life"] -= 1
		if u["life"] <= 0 and units.has(u):
			_remove_unit(u, "%s убежал домой — призыв закончился." % u["name"])
	refresh_view()
	hud.refresh()

func _fight_unit(p: Dictionary, u: Dictionary) -> void:
	_stop_walk(p)
	var n: Node3D = u["node"]
	_begin_fight(p.node, n)
	var owner: Dictionary = players[u["owner"]]
	var res: Dictionary = await _ask(cur, "battle", func(): return await hud.battle(p.name, "%s (%s)" % [u["name"], owner.name], "Здоровье: %d • Сила 3" % u["hp"], "Чтобы ударить, нужно набрать 3 или больше", false, p.color, p.ability == "agile"), "%s бьёт призванного зверя…" % p.name, DEFAULT_BATTLE, true)
	var win: bool = int(res["total"]) >= 3
	var txt := ""
	var dmg := int(round(2 * float(p.dmg_mult))) + 2 * int(p.wolves)
	if win:
		txt = "Удар! %s теряет %d HP." % [u["name"], dmg]
	else:
		txt = "Промах... %s кусает в ответ: −%d HP" % [u["name"], maxi(1, u["dmg"])]
	await hud.battle_finish(txt, win)
	_end_fight()
	if win:
		u["hp"] -= dmg
		_float_text(n, "−%d" % dmg, Style.RED)
		if u["hp"] <= 0:
			owner.reports.append("Героя %s прогнал твоего зверя: %s." % [p.name, u["name"]])
			_remove_unit(u, "%s убегает!" % u["name"])
		else:
			_update_unit_tag(u)
	else:
		_damage(p, maxi(1, u["dmg"]))

# ================================================================= БОНУСНЫЕ КАРТЫ
func _bonus_card(p: Dictionary) -> Dictionary:
	var r := rng.randf()
	if r < 0.35:
		var c := DB.random_trap(rng)
		return {"kind": "trap", "id": c, "title": DB.traps[c]["name"], "text": DB.traps[c]["text"]}
	if r < 0.62:
		var si := rng.randi_range(0, DB.summons.size() - 1)
		return {"kind": "summon", "id": si, "title": DB.summons[si]["name"], "text": DB.summons[si]["text"]}
	var keys := ["potion", "potion", "boots", "torch", "meat", "meat", "honey"]
	var k: String = keys[rng.randi() % keys.size()]
	return {"kind": "item", "id": k, "title": DB.items[k]["name"], "text": DB.items[k]["text"]}

## Первый ход: 5 карт рубашкой вверх, открыть можно 2.
func _bonus_cards(p: Dictionary) -> void:
	var cards: Array = []
	for k in 5:
		cards.append(_bonus_card(p))
	var chosen_raw: Array = await _ask(p.idx, "bonus", func(): return await hud.bonus_pick(p.name, cards), "%s открывает бонусные карты…" % p.name, [0, 1])
	var chosen: Array = []
	for ci0 in chosen_raw:
		chosen.append(int(ci0))
	var got: Array = []
	for ci in chosen:
		var c: Dictionary = cards[ci]
		match c["kind"]:
			"trap":
				p.hand.append(c["id"])
			"summon":
				p.summons.append(c["id"])
			"item":
				p.items.append(c["id"])
		got.append(c["title"])
	if not got.is_empty():
		hud.toast("Бонусные карты: " + ", ".join(got), Style.GOLD, 3.5)
	hud.refresh()

# ================================================================= ПРИРУЧЕНИЕ
func _on_long_press(sp: Vector2) -> void:
	if busy or game_over or mode != "move":
		return
	var t := _pick(sp)
	if not map.inb(t):
		return
	if net and (cur != my_seat or _echo_wait):
		return
	var o = objects.get(t)
	var p: Dictionary = players[cur]
	if o == null or o["type"] != "beast" or not _object_visible(o, p):
		return
	if net:
		if absi(t.x - p.pos.x) + absi(t.y - p.pos.y) != 1:
			hud.toast("Подойди к зверю вплотную, чтобы приручить или атаковать.", Style.GOLD, 2.5)
			return
		_cmd({"k": "press", "t": [t.x, t.y]})
		return
	await _long_press_tile(t)

func _long_press_tile(t: Vector2i) -> void:
	var o = objects.get(t)
	var p: Dictionary = players[cur]
	if o == null or o["type"] != "beast":
		return
	var d: Vector2i = t - p.pos
	var def: Dictionary = DB.beasts[o["kind"]]
	if absi(d.x) + absi(d.y) != 1:
		hud.toast("Подойди к зверю вплотную, чтобы приручить или атаковать.", Style.GOLD, 2.5)
		return
	var opts: Array = []
	var cost: int = map.move_cost(p.pos, t)
	opts.append(["Атаковать (%d шаг.)" % cost, rolled and steps_left >= cost])
	var tame_txt := "Этого зверя не приручить"
	var can_tame := false
	match o["kind"]:
		"wolf":
			var need := 2 if p.wolves == 0 and p.ability != "beast" else 1
			tame_txt = "Приручить — %d мяса (есть %d)" % [need, p.items.count("meat")]
			can_tame = p.items.count("meat") >= need
		"bear":
			if p.bear:
				tame_txt = "У тебя уже есть медведь"
			else:
				tame_txt = "Приручить — 1 банка мёда (есть %d)" % p.items.count("honey")
				can_tame = p.items.count("honey") >= 1
	opts.append([tame_txt, can_tame])
	busy = true
	var choice: int = int(await _ask(cur, "choice", func(): return await hud.choice(def["name"], opts), "%s решает, что делать со зверем…" % p.name, -1))
	busy = false
	if choice == 0:
		steps_left -= cost
		_face(p, t)
		busy = true
		hud.set_phase("busy")
		await _fight_beast(p, t, o)
		busy = false
		if p.hp <= 0:
			await _respawn(p)
		hud.set_phase("act")
		refresh_view()
		_recalc()
		hud.refresh()
	elif choice == 1:
		_tame(p, t, o)

func _tame(p: Dictionary, t: Vector2i, o: Dictionary) -> void:
	var kind: String = o["kind"]
	if kind == "wolf":
		var need := 2 if p.wolves == 0 and p.ability != "beast" else 1
		for k in need:
			p.items.erase("meat")
	else:
		p.items.erase("honey")
	objects.erase(t)
	var n: Node3D = o["node"]
	n.get_parent().remove_child(n)
	p.node.add_child(n)
	n.scale = Vector3.ONE * (0.75 if kind == "wolf" else 0.85)
	n.set("_base_scale", n.scale)
	n.rotation = Vector3.ZERO
	var wolf_spots := [Vector3(-0.5, 0, -0.35), Vector3(0.5, 0, -0.35), Vector3(0, 0, -0.65), Vector3(-0.65, 0, 0.1), Vector3(0.65, 0, 0.1)]
	if kind == "wolf":
		n.name = "Wolf%d" % p.wolves
		n.position = wolf_spots[mini(p.wolves, wolf_spots.size() - 1)]
		p.wolves += 1
	else:
		n.name = "BearPet"
		n.position = Vector3(-0.35, 0, -0.75)
		p.bear = true
	Settings.play("magic")
	_float_text(p.node, "Приручён!", Style.GREEN)
	if kind == "wolf":
		hud.toast("Волк теперь твой! Каждый волк добавляет +2 к урону. Волков: %d" % p.wolves, Style.GREEN, 3.5)
	else:
		hud.toast("Медведь теперь твой! Он охраняет тебя на 3 клетки и сам бросается на врагов.", Style.GREEN, 4.0)
	_recalc()
	hud.refresh()

## Ручной медведь врага бросается на героя, если тот подошёл ближе 3 клеток (раз за круг).
func _bear_guard(p: Dictionary) -> bool:
	for j in players.size():
		var q: Dictionary = players[j]
		if not q.bear or not is_enemy(cur, j) or q.bear_round == round_no:
			continue
		var d := maxi(absi(q.pos.x - p.pos.x), absi(q.pos.y - p.pos.y))
		if d > 3:
			continue
		q.bear_round = round_no
		_stop_walk(p)
		q.node.visible = true
		var bn: Node3D = q.node.get_node_or_null("BearPet")
		if bn:
			var home := bn.position
			var to_local: Vector3 = q.node.to_local(p.node.global_position)
			var tw := create_tween()
			tw.tween_property(bn, "position", home.lerp(to_local, 0.85), 0.35)
			tw.tween_interval(0.3)
			tw.tween_property(bn, "position", home, 0.4)
		Settings.play("hit")
		var dmg := int(round(3 * float(q.dmg_mult)))
		_damage(p, dmg)
		q.reports.append("Твой медведь прогнал героя %s (−%d HP)!" % [p.name, dmg])
		await hud.alert("Медведь-защитник!", "Ручной медведь игрока %s бросился на тебя: −%d HP.\nОн охраняет хозяина на 3 клетки вокруг." % [q.name, dmg], Color("c08a5a"))
		return true
	return false

# ================================================================= ФИНАЛ
func _victory(p: Dictionary) -> void:
	game_over = true
	_clear_highlight()
	DB.last_winner_slot = p.slot
	hud.set_phase("over")
	_stop_walk(p)
	follow = null
	view_first = false
	cam_goal = shrine_node.position + Vector3(0, 1.0, -0.6)
	var tw := create_tween()
	tw.tween_property(self, "cam_yaw", 0.45, 1.0)
	tw.parallel().tween_property(self, "cam_pitch", deg_to_rad(22.0), 1.0)
	tw.parallel().tween_property(self, "cam_dist", 6.5, 1.0)
	await get_tree().create_timer(1.1).timeout
	var voice_len: float = Settings.play_voice("finale")
	var fl := ["Осколки вернулись на свои места…", "Гора открывает свою тайну…", "Сердце Долины нашло своего героя!"]
	var ft: Dictionary = Settings.voice_timing("finale")
	var fs: Array = ft.get("starts", [0.0, 3.0, 5.6]) if voice_len > 0.0 else [0.0, 3.0, 5.6]
	var fend: float = float(ft.get("end", 8.5)) if voice_len > 0.0 else 8.5
	for i in 3:
		var t0: float = float(fs[i])
		var t1: float = float(fs[i + 1]) if i < 2 else fend + 0.6
		get_tree().create_timer(t0).timeout.connect(hud.subtitle.bind(fl[i], maxf(1.0, t1 - t0 - 0.7)))
	var t_start := Time.get_ticks_msec()
	# кристаллы летят в гнёзда
	for i in 3:
		var sock: MeshInstance3D = shrine_node.get_node("Socket%d" % i)
		var c := Models.shard()
		c.scale = Vector3.ONE * 0.5
		add_child(c)
		c.global_position = p.node.global_position + Vector3(0, 0.8, 0)
		var tw2 := create_tween()
		tw2.tween_property(c, "global_position", sock.global_position + Vector3(0, -0.25, -0.05), 0.7).set_trans(Tween.TRANS_SINE)
		await tw2.finished
		c.queue_free()
		sock.material_override = Models.mat(Color("7fe3ff"), 3.0)
		Settings.play("shard", 0.0)
		await get_tree().create_timer(0.25).timeout
	# гора дрожит, створки разъезжаются
	Settings.play("night", 0.0)
	var base := shrine_node.position
	var shake := create_tween()
	for k in 10:
		shake.tween_property(shrine_node, "position", base + Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.03, 0.03)), 0.06)
	shake.tween_property(shrine_node, "position", base, 0.06)
	await shake.finished
	var sl: Node3D = shrine_node.get_node("SlabL")
	var sr: Node3D = shrine_node.get_node("SlabR")
	var inner: OmniLight3D = shrine_node.get_node("Inner")
	var tr3: Node3D = shrine_node.get_node("Treasure")
	var tw3 := create_tween()
	tw3.tween_property(sl, "position:x", -0.78, 1.6).set_trans(Tween.TRANS_SINE)
	tw3.parallel().tween_property(sr, "position:x", 0.78, 1.6).set_trans(Tween.TRANS_SINE)
	tw3.parallel().tween_property(inner, "light_energy", 4.0, 1.6)
	await tw3.finished
	tr3.visible = true
	tr3.scale = Vector3.ONE * 0.2
	var tw4 := create_tween()
	tw4.tween_property(tr3, "scale", Vector3.ONE, 0.6)
	tw4.parallel().tween_property(tr3, "position", Vector3(0, 0.6, -0.2), 1.2).set_trans(Tween.TRANS_BACK)
	tw4.parallel().tween_property(tr3, "rotation:y", TAU, 2.0)
	Settings.play("victory", 0.0)
	var elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
	await get_tree().create_timer(maxf(2.6, fend + 1.0 - elapsed)).timeout
	if camp:
		_camp_finish(p)
	else:
		hud.show_victory(p)




# ================================================================= КАМПАНИЯ
func _win_ids(p: Dictionary) -> Array:
	var ids: Array = []
	for q in players:
		if q.idx == p.idx or (team_mode and q.team == p.team):
			ids.append(q.idx)
	return ids

## Подводит итоги раунда: очки, ачивки, сюжет — и показывает экран итогов.
func _camp_finish(p: Dictionary) -> void:
	_camp_win_ids = _win_ids(p)
	var prev: Array = camp_data.get("scores", [])
	var pts: Array = []
	var scores: Array = []
	for q in players:
		var pt: int = Camp.WIN_POINTS if _camp_win_ids.has(q.idx) else mini(int(q.shards), Camp.SHARD_POINTS_MAX)
		pts.append(pt)
		scores.append((int(prev[q.idx]) if q.idx < prev.size() else 0) + pt)
	_camp_scores = scores
	var wins: Array = camp_data.get("wins", []).duplicate()
	wins.append(_camp_win_ids)
	_camp_wins = wins
	var final: bool = chapter >= Camp.CHAPTERS - 1
	# ачивки
	var got: Array = []
	for i in _camp_win_ids:
		var ids: Array = [["summer_hero", "autumn_hero", "winter_conqueror"][chapter]]
		if chapter == Camp.COUNT - 1:
			var every := true
			for w in wins:
				if not (w as Array).has(i):
					every = false
			if every:
				ids.append("all_seasons")
		for id in ids:
			got.append({"who": players[i].name, "id": id})
	if final:
		var best := -1
		for v in scores:
			best = maxi(best, int(v))
		for q in players:
			if int(scores[q.idx]) == best and not got.any(func(e): return e["who"] == q.name and e["id"] == "campaign_leader"):
				got.append({"who": q.name, "id": "campaign_leader"})
	for e in got:
		if not net or players[my_seat].name == e["who"]:
			Camp.grant(str(e["who"]), str(e["id"]))
	_camp_ready = true
	var wtxt := "Победитель раунда: %s" % p.name
	var wcol: Color = p.color
	if team_mode:
		var names: Array = []
		for q in players:
			if q.team == p.team:
				names.append(q.name)
		wtxt = "Победила команда «%s»: %s" % [team_name(p.team), ", ".join(names)]
		wcol = DB.TEAM_COLORS[p.team]
	var rows: Array = []
	for q in players:
		rows.append({"name": q.name, "color": DB.TEAM_COLORS[q.team] if team_mode else q.color, "pts": pts[q.idx], "total": scores[q.idx],
			"win": _camp_win_ids.has(q.idx), "team": q.team})
	hud.show_round_result({
		"chapter": chapter, "final": final, "winner": wtxt, "wcol": wcol, "rows": rows, "ach": got,
		"story": Camp.AFTER[chapter], "next_name": Camp.season(chapter + 1)["name"] if not final else "",
		"team_mode": team_mode, "code": map_code,
	})

## Кнопка «Дальше». По сети её нажимает хозяин, и «дальше» идёт всем одновременно через сервер.
func request_next() -> void:
	if not _camp_ready:
		return
	if net:
		Net.send_act({"k": "next"})
	else:
		_advance(0)

func _advance(seq: int) -> void:
	if chapter >= Camp.CHAPTERS - 1:
		return
	_camp_ready = false
	var c: Dictionary = cfg.duplicate(true)
	c["show_rules"] = false
	var cd: Dictionary = camp_data.duplicate(true)
	cd["chapter"] = chapter + 1
	cd["scores"] = _camp_scores.duplicate()
	cd["wins"] = _camp_wins.duplicate(true)
	c["camp"] = cd
	var low := 1 << 30
	var high := -1
	for v in _camp_scores:
		low = mini(low, int(v))
		high = maxi(high, int(v))
	for i in players.size():
		var pc: Dictionary = c["players"][i]
		pc["pet"] = _camp_win_ids.has(i)
		pc["boost"] = low < high and int(_camp_scores[i]) == low
	if net:
		c["start_seq"] = seq
		c["replay"] = replaying
		_chaining = true
	next_chapter.emit(c)
