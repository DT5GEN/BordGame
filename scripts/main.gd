extends Node
## Переключает меню и партию. Флаг «-- --autotest» прогоняет демо и делает скриншоты.

const Menu = preload("res://scripts/menu/main_menu.gd")
const Game = preload("res://scripts/game/game.gd")
const Intro = preload("res://scripts/intro/intro.gd")

var current: Node

func _ready() -> void:
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest.call_deferred()
	elif "--bench" in OS.get_cmdline_user_args():
		_bench.call_deferred()
	elif "--simtest" in OS.get_cmdline_user_args():
		_simtest.call_deferred()
	elif "--introtest" in OS.get_cmdline_user_args():
		_introtest.call_deferred()
	else:
		show_intro()

func _switch(n: Node) -> void:
	if current:
		current.queue_free()
	current = n
	add_child(n)

func show_intro() -> void:
	var it := Intro.new()
	it.finished.connect(show_menu, CONNECT_DEFERRED)
	_switch(it)

func show_menu() -> void:
	var m := Menu.new()
	m.start_requested.connect(start_game)
	m.intro_requested.connect(show_intro)
	_switch(m)

func start_game(cfg: Dictionary) -> void:
	var g := Game.new()
	g.cfg = cfg
	g.exit_to_menu.connect(show_menu)
	g.restart_game.connect(_restart)
	_switch(g)

func _restart() -> void:
	var cfg: Dictionary = DB.last_config.duplicate(true)
	cfg["show_rules"] = false
	for p in cfg["players"]:
		p["pet"] = p["slot"] == DB.last_winner_slot
	DB.last_config = cfg
	start_game(cfg)

# ------------------------------------------------------------ автопроверка
var _shot_dir := "user://shots"

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_environment("SHOT_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path(_shot_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join(name + ".png"))
	print("SHOT ", name)

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _autotest() -> void:
	show_menu()
	await _wait(1.5)
	await _shot("01_menu")
	var mn = current
	mn.team_mode = true
	mn.count = 5
	mn._refresh()
	await _wait(1.0)
	await _shot("01b_menu_team")
	var cfg := {"players": [
		{"name": "Тимур", "hero": 0, "pet": true, "slot": 0},
		{"name": "Мира", "hero": 2, "pet": false, "slot": 1},
		{"name": "Макс", "hero": 5, "pet": false, "slot": 2},
	], "size": Vector2i(24, 50), "show_rules": false, "seed": 4242}
	DB.last_config = cfg
	start_game(cfg)
	var g = current
	await _wait(1.0)
	await _shot("02_pass")
	g.hud.overlay_pass.visible = false
	g._turn_start_effects()
	await _wait(1.5)
	await _shot("03_turn_start")
	g.roll("D20")
	await _wait(0.5)
	await _shot("04_roll")
	await _wait(3.0)
	await _shot("05_reach")
	# идём к самой дальней доступной клетке
	var best = null
	for t in g.reach:
		if not g.targets.has(t) and (best == null or t.y > best.y):
			best = t
	if best != null:
		g._walk(g._path_to(best))
		await _wait(4.0)
	await _shot("06_after_walk")
	g._set_view(true, false)
	await _wait(1.5)
	await _shot("06b_first_person")
	g._set_view(false, false)
	Settings.music_folder = "/tmp/claude-0/testmusic"
	Settings.rebuild_playlist()
	Settings.next_track()
	print("MUSIC: tracks=", Settings.playlist.size(), " now=", Settings.current_track)
	g.settings_panel.open("Тимур")
	await _wait(0.8)
	await _shot("06c_settings")
	g.settings_panel.close()
	g.hud._confirm_menu()
	await _wait(0.6)
	await _shot("06d_confirm")
	g.hud.confirm_bar.queue_free()
	Settings.music_folder = ""
	Settings.save()
	g.papyrus.open()
	await _wait(1.0)
	await _shot("07_papyrus")
	g.papyrus.turn(1)
	await _wait(0.8)
	await _shot("08_papyrus_dice")
	g.papyrus.visible = false
	# Ловушка
	if g.steps_left < 2:
		g.steps_left = 4
	g.start_trap_mode(0)
	await _wait(0.5)
	await _shot("09_trap_mode")
	g._cancel_trap_mode()
	# Вечер
	g.hour = 19.0
	g._set_time_visual(19.0)
	g.cam_dist = 14.0
	g.refresh_view()
	g.hud.refresh()
	await _wait(1.5)
	await _shot("10_evening")
	# Ночь и Тьма
	g.hour = 22.0
	g.night = true
	g.dark_row = 6
	g._set_time_visual(22.0)
	g._update_darkness()
	g.rain.emitting = true
	g.refresh_view()
	g.hud.refresh()
	await _wait(2.5)
	await _shot("11_night")
	g.rain.emitting = false
	# обзор карты сверху
	g.hour = 12.0
	g.night = false
	g.dark_row = -1
	g._update_darkness()
	g._set_time_visual(12.0)
	g.follow = null
	g.cam_goal = Vector3(14, 0, 32)
	g.cam_dist = 40.0
	g.cam_pitch = deg_to_rad(62)
	await _wait(2.5)
	await _shot("12_overview")
	# Святилище
	g.cam_goal = g.map.world_pos(g.map.shrine)
	g.cam_dist = 7.0
	g.cam_pitch = deg_to_rad(35)
	await _wait(2.5)
	await _shot("13_shrine")
	# Схватка со зверем
	g.cam_pitch = deg_to_rad(48)
	g.cam_dist = 9.0
	for t in g.objects:
		var o = g.objects[t]
		if o["type"] == "beast" and o["kind"] == "wolf":
			g.follow = null
			g.cam_goal = g.map.world_pos(t)
			g.players[0].discovered[t] = true
			g.refresh_view()
			break
	await _wait(2.0)
	await _shot("14_beast")
	# окно-сообщение (баг с высоким окном)
	g.hud.alert("Ловушка «Колючая яма»!", "Её спрятал(а) Мира.\n−3 HP\nв следующий ход ещё −1 HP", Color("3d8bff"))
	await _wait(1.0)
	await _shot("15a_alert")
	g.hud._alert_closed.emit()
	await _wait(0.3)
	# интерактивный бой с волком
	var wolf_t = null
	for t in g.objects:
		if g.objects[t]["type"] == "beast" and g.objects[t]["kind"] == "boar":
			wolf_t = t
			break
	var hero = g.players[0]
	var adj: Vector2i = wolf_t + Vector2i(0, -1)
	hero.pos = adj
	hero.node.position = g.map.world_pos(adj)
	g.refresh_view()
	g._fight_beast(hero, wolf_t, g.objects[wolf_t])
	await _wait(1.0)
	await _shot("15a2_battle_prep")
	await _wait(1.9)
	await _shot("15b_battle_qte")
	var qte = g.hud.current_qte
	if qte:
		qte.press()
	await _wait(1.6)
	await _shot("15c_battle_roll")
	var rb = _find_button(g.hud.alert_panel, "Бросить кубик!")
	if rb:
		rb.pressed.emit()
	await _wait(2.0)
	await _shot("15d_battle_result")
	for k in 300:
		if g.hud.alert_closable:
			break
		await get_tree().process_frame
	g.hud._alert_closed.emit()
	await _wait(0.5)
	var winner = g.players[0]
	winner.shards = 3
	winner.pos = g.map.shrine + Vector2i(0, -1)
	winner.node.position = g.map.world_pos(winner.pos)
	g.refresh_view()
	g._victory(winner)
	await _wait(4.5)
	await _shot("16a_finale_crystals")
	await _wait(3.5)
	await _shot("16b_finale_open")
	await _wait(4.0)
	await _shot("16_victory")
	print("AUTOTEST DONE")
	get_tree().quit()

# ------------------------------------------------------------ боты играют сами
func _simtest() -> void:
	var games := 4
	for gi in games:
		var n: int = [1, 3, 6, 4][gi]
		var list: Array = []
		for i in n:
			list.append({"name": "Бот%d" % (i + 1), "hero": i, "pet": i == 0, "slot": i, "team": 0 if i < 3 else 1})
		var cfg: Dictionary = {"players": list, "size": [Vector2i(18, 38), Vector2i(24, 50), Vector2i(24, 50), Vector2i(24, 50)][gi], "show_rules": false, "seed": 100 + gi, "team_mode": gi == 3}
		DB.last_config = cfg
		start_game(cfg)
		var g = current
		g.hud.fast = true
		Engine.time_scale = 12.0
		await get_tree().process_frame
		var turns := 0
		if gi == 3:
			await _tame_test(g)
		if gi == 1:
			g.hud.overlay_pass.visible = false
			await g._turn_start_effects()
			await g.roll("D6")
			var tgt = null
			for t in g.reach:
				if not g.targets.has(t) and g._path_to(t).size() >= 2:
					tgt = t
					break
			for card in [0, 18, 10, 14, 26, 21, 14]:
				var mk = load("res://scripts/world/models.gd").trap_marker()
				g.entities.add_child(mk)
				g.traps.append({"owner": 1, "pos": tgt, "card": card, "node": mk})
			g.players[0].hand.append(3)
			print("TRAPTEST walking to ", tgt)
			await g._walk(g._path_to(tgt))
			print("TRAPTEST after: pos=", g.players[0].pos, " hp=", g.players[0].hp, " skip_turn=", g.players[0].skip_turn, " owner_hp=", g.players[1].hp, " owner_hand=", g.players[1].hand.size(), " reports=", g.players[1].reports)
			g.end_turn()
		while not g.game_over and turns < 600:
			if g.hud.overlay_pass.visible:
				g.hud.overlay_pass.visible = false
				await g._turn_start_effects()
				await get_tree().process_frame
				continue
			if g.busy:
				await get_tree().process_frame
				continue
			if g.hud.phase == "roll":
				await g.roll(DB.dice_order[randi() % 5])
				continue
			if g.hud.phase == "act":
				var p: Dictionary = g.current()
				if not p.hand.is_empty() and g.steps_left >= 4 and randf() < 0.4:
					g.start_trap_mode(0)
					if g.mode == "trap" and not g.trap_targets.is_empty():
						g._place_trap(g.trap_targets.keys()[0])
					elif g.mode == "trap":
						g._cancel_trap_mode()
				if p.items.has("potion") and p.hp < 10:
					g.use_item(p.items.find("potion"))
				var best = null
				var bs := -99999.0
				for t in g.reach:
					var sc: float = t.y * 1.0 + randf() * 2.0
					var o = g.objects.get(t)
					if o != null:
						if o["type"] == "shard" or (o["type"] == "chest" and o.get("content") == "shard"):
							sc += 60
						elif o["type"] == "beast" and o.get("shard", false) and p.shards < 3:
							sc += 40
						elif o["type"] in ["chest", "event"]:
							sc += 8
					if g.map.get_t(t) == 7 and p.shards >= 3:
						sc += 1000
					if p.shards < 3 and t.y > g.map.gorge.x - 2:
						sc -= 80
					if sc > bs:
						bs = sc
						best = t
				if best != null:
					await g._walk(g._path_to(best))
				if g.game_over:
					break
				g.end_turn()
				turns += 1
				if turns % 10 == 0:
					print("turn ", turns, " round ", g.round_no, " cur ", g.cur, " phase ", g.hud.phase)
				await get_tree().process_frame
				continue
			if Engine.get_process_frames() % 300 == 0:
				print("idle phase=", g.hud.phase, " busy=", g.busy, " pass=", g.hud.overlay_pass.visible, " alert=", g.hud.alert_panel.visible)
			await get_tree().process_frame
		var shards := []
		for p in g.players:
			shards.append("%s hp=%d sh=%d pos=%s" % [p.name, p.hp, p.shards, p.pos])
		print("GAME %d: players=%d over=%s turns=%d round=%d hour=%.1f dark=%d total_shards=%d | %s" % [gi, n, g.game_over, turns, g.round_no, g.hour, g.dark_row, g.n_shards_total, ", ".join(shards)])
		Engine.time_scale = 1.0
	print("SIMTEST DONE")
	get_tree().quit()

func _find(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).contains("hud.gd") and c is Control and c.has_method("press"):
			return c
		var r = _find(c, cls)
		if r:
			return r
	return null

func _find_button(n: Node, txt: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text == txt:
			return c
		var r = _find_button(c, txt)
		if r:
			return r
	return null

func _bench() -> void:
	Engine.max_fps = 0
	var cfg := {"players": [{"name": "А", "hero": 0, "pet": false, "slot": 0}, {"name": "Б", "hero": 1, "pet": false, "slot": 1}], "size": Vector2i(24, 50), "show_rules": false, "seed": 7}
	start_game(cfg)
	var g = current
	await _wait(1.0)
	g.hud.overlay_pass.visible = false
	g._turn_start_effects()
	for zoom in [8.5, 20.0]:
		g.cam_dist = zoom
		await _wait(3.0)
		var t0 := Time.get_ticks_usec()
		var f0 := Engine.get_process_frames()
		await _wait(4.0)
		var frames := Engine.get_process_frames() - f0
		var dt := (Time.get_ticks_usec() - t0) / 1000000.0
		print("BENCH zoom=%.1f fps=%.1f draw_calls=%d objects=%d prims=%d" % [zoom, frames / dt,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()

func _introtest() -> void:
	show_intro()
	var it = current
	var marks := [2.0, 9.0, 17.0, 20.5, 27.0, 33.0, 40.0, 46.0]
	var t := 0.0
	for i in marks.size():
		await _wait(marks[i] - t)
		t = marks[i]
		await _shot("intro_%02d" % i)
	await _wait(3.0)
	await _shot("intro_end")
	print("INTRO DONE")
	get_tree().quit()

func _tame_test(g) -> void:
	g.hud.overlay_pass.visible = false
	await g._turn_start_effects()
	var p = g.players[3]
	print("TEAM: team_mode=", g.team_mode, " p3 max_hp=", p.max_hp, " dmg=", p.dmg_mult, " step=", p.step_mult, " p0 max_hp=", g.players[0].max_hp)
	var wolf_t = null
	var bear_t = null
	for t in g.objects:
		var o = g.objects[t]
		if o["type"] == "beast" and o["kind"] == "wolf" and wolf_t == null:
			wolf_t = t
		if o["type"] == "beast" and o["kind"] == "bear" and bear_t == null:
			bear_t = t
	var me = g.players[0]
	me.items.append_array(["meat", "meat", "honey"])
	if wolf_t != null:
		me.pos = wolf_t + Vector2i(0, -1)
		me.node.position = g.map.world_pos(me.pos)
		g._tame(me, wolf_t, g.objects[wolf_t])
	if bear_t != null:
		me.pos = bear_t + Vector2i(0, -1)
		me.node.position = g.map.world_pos(me.pos)
		g._tame(me, bear_t, g.objects[bear_t])
	print("TAME: wolves=", me.wolves, " bear=", me.bear, " meat_left=", me.items.count("meat"), " honey_left=", me.items.count("honey"))
	# враг подходит к хозяину медведя
	var cur_backup = g.cur
	g.cur = 3
	var enemy = g.players[3]
	enemy.pos = me.pos + Vector2i(2, 0)
	var hp0 = enemy.hp
	var hit = await g._bear_guard(enemy)
	print("BEARGUARD: triggered=", hit, " enemy hp ", hp0, " -> ", enemy.hp)
	print("ALLY: is_enemy(0,1)=", g.is_enemy(0, 1), " is_enemy(0,3)=", g.is_enemy(0, 3))
	g.cur = cur_backup
