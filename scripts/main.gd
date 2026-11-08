extends Node
## Переключает меню и партию. Флаг «-- --autotest» прогоняет демо и делает скриншоты.

const Menu = preload("res://scripts/menu/main_menu.gd")
const Game = preload("res://scripts/game/game.gd")
const Intro = preload("res://scripts/intro/intro.gd")
const Camp = preload("res://scripts/game/campaign.gd")
const Transition = preload("res://scripts/intro/transition.gd")

var current: Node

func _ready() -> void:
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest.call_deferred()
	elif "--bench" in OS.get_cmdline_user_args():
		_bench.call_deferred()
	elif "--simtest" in OS.get_cmdline_user_args():
		_simtest.call_deferred()
	elif "--musictest" in OS.get_cmdline_user_args():
		await _wait(0.5)
		print("PLAYLIST ", Settings.playlist.size(), " now=", Settings.current_track, " playing=", Settings.music.playing)
		print("VOICE intro=", Settings.voice_timing("intro").get("starts", []), " finale_len=", Settings.play_voice("finale"), " traps=", DB.traps.size(), " beasts=", DB.beasts.keys())
		for t in Settings.playlist:
			print("  ", t["name"])
		get_tree().quit()
	elif "--editortest" in OS.get_cmdline_user_args():
		show_menu()
		await _wait(1.0)
		await _shot("ed_menu")
		current.card_editor.open()
		DB.set_fx(0, "dmg", 4)
		current.card_editor._rebuild()
		await _wait(0.8)
		await _shot("ed_trap")
		print("EDIT: trap0 dmg=", DB.traps[0]["fx"]["dmg"], " cost=", DB.trap_price(0), " text=", DB.traps[0]["text"])
		DB.set_fx(0, "dmg", 99)
		print("CLAMP: dmg=", DB.traps[0]["fx"]["dmg"])
		current.card_editor.sel_kind = "beast"
		current.card_editor.sel_beast = "bear"
		DB.set_beast("bear", "power", 1)
		current.card_editor._rebuild()
		await _wait(0.8)
		await _shot("ed_beast")
		print("BEAST: bear power=", DB.beasts["bear"]["power"])
		DB.load_cards()
		print("RELOAD: trap0 dmg=", DB.traps[0]["fx"]["dmg"], " cost=", DB.trap_price(0), " bear=", DB.beasts["bear"]["power"])
		DB.reset_all()
		DB.load_cards()
		print("RESET: trap0 dmg=", DB.traps[0]["fx"]["dmg"], " cost=", DB.trap_price(0), " text=", DB.traps[0]["text"])
		get_tree().quit()
	elif "--qtetest" in OS.get_cmdline_user_args():
		start_game({"players": [{"name": "А", "hero": 0, "pet": false, "slot": 0}], "size": Vector2i(18, 38), "show_rules": false})
		var g = current
		await _wait(1.0)
		for tries in 3:
			var res := [null]
			var f := func(): res[0] = await g.hud.battle("А", "Волк", "", "", false)
			f.call()
			while g.hud.current_qte == null:
				await get_tree().process_frame
			var q = g.hud.current_qte
			while not q.started:
				await get_tree().process_frame
			q.press()
			for k in 30:
				await get_tree().process_frame
			var rb = _find_button(g.hud.alert_panel, "Бросить кубик!")
			var t0 := Time.get_ticks_msec()
			while rb == null and Time.get_ticks_msec() - t0 < 3000:
				await get_tree().process_frame
				rb = _find_button(g.hud.alert_panel, "Бросить кубик!")
			print("QTE try ", tries, ": roll button appeared=", rb != null)
			if rb:
				rb.pressed.emit()
			while res[0] == null:
				await get_tree().process_frame
			print("   result=", res[0])
		get_tree().quit()
	elif "--herotest" in OS.get_cmdline_user_args():
		show_menu()
		await _wait(2.6)
		await _shot("hero_menu")
		start_game({"players": [{"name": "А", "hero": 0, "pet": false, "slot": 0}], "size": Vector2i(18, 38), "show_rules": false, "die": "D12"})
		await _wait(2.0)
		current.hud.overlay_pass.visible = false
		current.hud.alert_panel.visible = false
		current.hud.set_phase("roll")
		await _wait(0.5)
		await _shot("hero_roll")
		get_tree().quit()
	elif "--menutest" in OS.get_cmdline_user_args():
		show_menu()
		await _wait(1.0)
		var all: Array = []
		_collect_buttons(current, "Питомец", all)
		print("PET checkboxes: ", all.size())
		if all.size() > 1:
			all[1].button_pressed = true   # питомец второму игроку, выбран первый
		await _wait(0.6)
		print("PET selected=", current.selected, " has_fox=", current.preview_hero.get_child_count())
		await _shot("menu")
		get_tree().quit()
	elif "--bosstest" in OS.get_cmdline_user_args():
		_bosstest.call_deferred()
	elif "--cuttest" in OS.get_cmdline_user_args():
		_cuttest.call_deferred()
	elif "--introtest" in OS.get_cmdline_user_args():
		_introtest.call_deferred()
	elif "--camptest" in OS.get_cmdline_user_args():
		_camptest.call_deferred()
	elif "--nettest" in OS.get_cmdline_user_args():
		_nettest.call_deferred()
	elif "--lobbytest" in OS.get_cmdline_user_args():
		_lobbytest.call_deferred()
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
	g.next_chapter.connect(_chapter_cut, CONNECT_DEFERRED)
	_switch(g)

## Между главами кампании — заставка с озвучкой (в тестах и при возврате в игру по сети пропускается).
func _chapter_cut(cfg: Dictionary) -> void:
	var ch := int(cfg.get("camp", {}).get("chapter", 0))
	var quick: bool = cfg.get("replay", false) or "--camptest" in OS.get_cmdline_user_args() or "--nettest" in OS.get_cmdline_user_args() or OS.has_environment("NO_CUT")
	if ch < 1 or quick:
		start_game(cfg)
		return
	var tr := Transition.new()
	tr.kind = clampi(ch - 1, 0, 2)
	tr.finished.connect(start_game.bind(cfg), CONNECT_DEFERRED)
	_switch(tr)

func _restart() -> void:
	if current != null and current.get("net") == true:
		show_menu()
		return
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
	await _shot("03a_bonus")
	var qs: Array = []
	_collect_buttons(g.hud.alert_panel, "?", qs)
	if qs.size() >= 2:
		qs[1].pressed.emit()
		await _wait(0.4)
		qs[3].pressed.emit()
	await _wait(3.0)
	await _shot("03b_bonus_open")
	var db = _find_button(g.hud.alert_panel, "Забрать карты")
	if db:
		db.pressed.emit()
	await _wait(1.0)
	# призыв: собака рядом с героем
	g.players[0].summons.append(DB.summon_idx("dog"))
	g.players[0].summons.append(DB.summon_idx("cow"))
	g._spawn_unit(0, DB.summon_idx("dog"), g.players[0].pos + Vector2i(1, 0))
	g._spawn_unit(0, DB.summon_idx("cow"), g.players[0].pos + Vector2i(-1, 0))
	await _wait(1.2)
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
	DB.set_meta("fast", true)
	var games := 4
	for gi in games:
		if "--unitonly" in OS.get_cmdline_user_args() and gi != 3:
			continue
		var n: int = [1, 3, 6, 4][gi]
		var list: Array = []
		for i in n:
			list.append({"name": "Бот%d" % (i + 1), "hero": i, "pet": i == 0, "slot": i, "team": 0 if i < 3 else 1, "ability": (i + gi) % 8})
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
			if "--unitonly" in OS.get_cmdline_user_args():
				break
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
				if not p.summons.is_empty() and g.steps_left >= g.summon_cost(p.summons[0]) and randf() < 0.5:
					g.start_summon_mode(0)
					if g.mode == "summon" and not g.summon_targets.is_empty():
						g._place_summon(g.summon_targets.keys()[0], g.pending_summon)
					elif g.mode == "summon":
						g._cancel_trap_mode()
				if g.can_reroll() and randf() < 0.3:
					await g.reroll()
				if not p.hand.is_empty() and g.steps_left >= 4 and randf() < 0.4:
					g.start_trap_mode(0)
					if g.mode == "trap" and not g.trap_targets.is_empty():
						g._place_trap(g.trap_targets.keys()[0], g.pending_card)
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

func _cuttest() -> void:
	for kd in 3:
		var tr := Transition.new()
		tr.kind = kd
		_switch(tr)
		for i in 4:
			await _wait(tr.length / 4.0 if i > 0 else 1.0)
			await _shot("cut%d_%d" % [kd, i])
	get_tree().quit()

func _introtest() -> void:
	show_intro()
	var it = current
	var marks := [3.0, 10.0, 17.0, 22.0, 25.0, 33.0, 38.0, 43.0]
	var t := 0.0
	for i in marks.size():
		await _wait(marks[i] - t)
		t = marks[i]
		await _shot("intro_%02d" % i)
		print("INTRO t=", t, " sub=", it.sub_lbl.text.left(40))
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
	# призывы: каждый зверь рядом с врагом
	var e = g.players[3]
	for sid in ["dog", "cat", "parrot", "hamster", "fox", "chicken", "bear", "cow", "pig", "wolf"]:
		var spot: Vector2i = e.pos + Vector2i(2, 0)
		for dd in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(2, 2), Vector2i(-2, 2), Vector2i(1, 2)]:
			if g._tile_free_for_unit(e.pos + dd):
				spot = e.pos + dd
				break
		var hp0b = e.hp
		g._spawn_unit(0, DB.summon_idx(sid), spot)
		await g._units_act(0)
		print("UNIT ", sid, ": units=", g.units.size(), " enemy hp ", hp0b, " -> ", e.hp, " wolves0=", g.players[0].wolves)
		for u in g.units.duplicate():
			g._remove_unit(u, "")
	# бой героя с призывом врага
	g._spawn_unit(3, DB.summon_idx("dog"), g.players[0].pos + Vector2i(1, 0))
	var u0 = g.units[0]
	g.cur = 0
	await g._fight_unit(g.players[0], u0)
	print("FIGHTUNIT: unit hp=", u0["hp"], " alive=", g.units.has(u0))
	for u in g.units.duplicate():
		g._remove_unit(u, "")
	g.cur = cur_backup

func _collect_buttons(n: Node, txt: String, out: Array) -> void:
	for c in n.get_children():
		if c is Button and c.text == txt:
			out.append(c)
		_collect_buttons(c, txt, out)


# ------------------------------------------------------------ проверка сети: два клиента на одном сервере
func _nettest() -> void:
	var args := OS.get_cmdline_user_args()
	DB.set_meta("fast", not "--real" in args)
	var role := "host" if "--host" in args else "guest"
	var port := "7777"
	var limit := 120
	var kill_at := 0
	var win_at: Array = []
	var tag := ""
	for a in args:
		if a.begins_with("--port="):
			port = a.substr(7)
		if a.begins_with("--secs="):
			limit = int(a.substr(7))
		if a.begins_with("--kill-at="):
			kill_at = int(a.substr(10))
		if a.begins_with("--tag="):
			tag = a.substr(6)
		if a.begins_with("--winat="):
			for x in a.substr(8).split(","):
				win_at.append(int(x))
	var url := "ws://127.0.0.1:" + port
	var camp_on: bool = "--camp" in args
	var hooked := [null]
	var code_file := "/tmp/nettest_code_" + port
	var log_path := "/tmp/nettest_%s%s_%s.log" % [role, tag, port]
	var logf := FileAccess.open(log_path, FileAccess.WRITE)
	var lobby_ok := [false]
	Net.error.connect(func(t): print("NETERR ", t))
	Net.lobby.connect(func(d):
		print("LOBBY ", d["room"], " players=", d["players"].size())
		if role == "host" and d["players"].size() >= 2 and not lobby_ok[0]:
			lobby_ok[0] = true
			Net.start_game())
	Net.started.connect(func(d):
		var list: Array = []
		var my := -1
		for i in d["seats"].size():
			var sd: Dictionary = d["seats"][i]
			if int(sd["cid"]) == Net.cid:
				my = i
			list.append({"name": sd["name"], "hero": int(sd["hero"]), "pet": false, "slot": i, "team": 0, "ability": int(sd["ability"]), "cid": int(sd["cid"])})
		var cfg := {"players": list, "size": Vector2i(18, 38), "show_rules": false, "team_mode": false, "die": "D6", "seed": int(d["seed"]), "net": true, "my_seat": my}
		cfg["replay"] = bool(d.get("replay", false))
		print("START seat=", my, " seed=", d["seed"], " replay=", cfg["replay"])
		if camp_on:
			cfg["camp"] = {"chapter": 0, "scores": [], "wins": []}
		start_game(cfg)
		if "--beast" in args:
			_force_beasts(current))
	if "--rejoin" in args:
		Net.rejoin()
	elif role == "host":
		Net.create_room(url, {"name": "Хост", "hero": 0, "ability": 0}, {"size_idx": 0, "die": "D6", "team_mode": false, "balance": {}})
		while Net.room == "":
			await get_tree().process_frame
		var cf := FileAccess.open(code_file, FileAccess.WRITE)
		cf.store_string(Net.room)
		cf.close()
	else:
		var t0 := Time.get_ticks_msec()
		while not FileAccess.file_exists(code_file) and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(0.5).timeout
		var code := FileAccess.get_file_as_string(code_file).strip_edges()
		Net.join_room(url, code, {"name": "Гость", "hero": 3, "ability": 2})
	var t_start := Time.get_ticks_msec()
	var rnd := RandomNumberGenerator.new()
	rnd.randomize()
	while Time.get_ticks_msec() - t_start < limit * 1000:
		await get_tree().create_timer(0.15).timeout
		if kill_at > 0 and Time.get_ticks_msec() - t_start > kill_at * 1000:
			print("KILL")
			OS.kill(OS.get_process_id())
		var g = current
		if g != null and g.get("net") and g != hooked[0] and g.get("hud") != null:
			# каждая новая карта кампании: подключаем проверку «у всех одно и то же»
			hooked[0] = g
			logf.store_line("CHAPTER %d season=%s code=%d" % [g.chapter, g.season_d["name"], g.map_code])
			g.cmd_done.connect(func(seq):
				logf.store_line("SYNC %d %s" % [seq, g.state_digest()])
				logf.flush()
				var thr: int = win_at[g.chapter] if g.chapter < win_at.size() else -1
				if thr > 0 and seq == thr and not g.game_over:
					g.players[0].shards = 3
					g._victory(g.players[0]))
		if g == null or not g.get("net") or g.get("hud") == null or g.game_over:
			if g != null and g.get("game_over") == true:
				if g.get("camp") and g.chapter < 3:
					if g._camp_ready and role == "host" and not g.get_meta("asked", false):
						g.set_meta("asked", true)
						logf.store_line("NEXT scores=%s" % [g._camp_scores])
						g.request_next()
					continue
				break
			continue
		if "--real" in args:
			_real_ui_bot(g)
		if g.cur != g.my_seat or g._echo_wait or g._flow or not g._q.is_empty() or g.busy:
			continue
		if g.hud.phase == "roll":
			g.hud.roll_requested.emit("D6")
		elif g.hud.phase == "trap":
			if g.mode == "trap" and not g.trap_targets.is_empty():
				var tt: Vector2i = g.trap_targets.keys()[0]
				g._cmd({"k": "trap", "h": g.pending_card, "t": [tt.x, tt.y]})
			elif g.mode == "summon" and not g.summon_targets.is_empty():
				var st: Vector2i = g.summon_targets.keys()[0]
				g._cmd({"k": "summon", "h": g.pending_summon, "t": [st.x, st.y]})
			else:
				g._cancel_trap_mode()
		elif g.hud.phase == "act":
			var best := Vector2i(-1, -1)
			var p: Dictionary = g.players[g.cur]
			var roll_dice := rnd.randf()
			if g.rolled and g.steps_left >= 3 and roll_dice < 0.3 and not p.hand.is_empty() and not p.now_block_traps:
				g.start_trap_mode(0)
				continue
			if g.rolled and g.steps_left >= 4 and roll_dice > 0.8 and not p.summons.is_empty() and not p.now_block_summon:
				g.start_summon_mode(0)
				continue
			for t in g.reach:
				if best.x < 0 or t.y > best.y:
					best = t
			if g.rolled and best.x >= 0 and best.y > p.pos.y and g.steps_left > 0:
				if "--beast" in args:
					for bt in g.targets:
						if g.objects.has(bt) and g.objects[bt]["type"] in ["beast", "boss"] and g.reach.has(bt):
							best = bt
				g._cmd({"k": "walk", "t": [best.x, best.y]})
			else:
				g.hud.end_turn_requested.emit()
	print("NETTEST DONE role=", role, " turns=", current.get("round_no"))
	logf.close()
	get_tree().quit()


func _lobbytest() -> void:
	show_menu()
	await _wait(1.5)
	await _shot("net_menu")
	var lb = current.net_lobby
	lb.open()
	lb.server_edit.text = "127.0.0.1:7793"
	lb.name_edit.text = "Саша"
	await _wait(0.5)
	await _shot("net_enter")
	lb._create()
	await _wait(3.5)
	await _shot("net_room")
	get_tree().quit()


## Проверка живого интерфейса: «нажимает» окна и кнопки, как это делал бы игрок.
func _real_ui_bot(g) -> void:
	var h = g.hud
	if h.current_qte != null and is_instance_valid(h.current_qte) and h.current_qte.started and not h.current_qte.finished:
		h.current_qte.press()
	var rb := _find_button(h.alert_panel, "Бросить кубик!")
	if rb != null and h.alert_panel.visible and not rb.disabled:
		rb.pressed.emit()
	var rb2 := _find_button_prefix(h.alert_panel, "Бросить кубик (")
	if rb2 != null and h.alert_panel.visible and not rb2.disabled:
		rb2.pressed.emit()
	if h.alert_panel.visible and h.alert_closable and g.cur == g.my_seat and not g.replaying:
		h._alert_closed.emit()
	var cards: Array = []
	_collect_buttons(h.alert_panel, "?", cards)
	if cards.size() >= 5 and h.alert_panel.visible:
		for i in 2:
			cards[i].pressed.emit()
	var take := _find_button(h.alert_panel, "Забрать карты")
	if take != null and take.visible and h.alert_panel.visible:
		take.pressed.emit()

func _find_button_prefix(n: Node, pre: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text.begins_with(pre):
			return c
		var r = _find_button_prefix(c, pre)
		if r:
			return r
	return null

## Проверка боя по сети: ставим зверей прямо перед героями (одинаково у всех клиентов).
func _force_beasts(g) -> void:
	var beasts: Array = []
	for t in g.objects:
		if g.objects[t]["type"] == "beast" and g.objects[t]["kind"] not in ["wolf", "bear"]:
			beasts.append(t)
	for i in mini(2, g.players.size()):
		if i >= beasts.size():
			break
		var old: Vector2i = beasts[i]
		var o: Dictionary = g.objects[old]
		var np: Vector2i = g.players[i].pos + Vector2i(0, 1)
		g.objects.erase(old)
		o["pos"] = np
		(o["node"] as Node3D).position = g.map.world_pos(np)
		g.objects[np] = o


## Проверка кампании без сети: три главы подряд, скриншоты сезонов и экранов итогов.
func _camptest() -> void:
	var list: Array = []
	for i in 3:
		list.append({"name": "Бот%d" % (i + 1), "hero": i, "pet": false, "slot": i, "team": 0, "ability": i})
	var cfg: Dictionary = {"players": list, "size": Vector2i(24, 50), "show_rules": false, "seed": 777, "team_mode": false,
		"camp": {"chapter": 0, "scores": [], "wins": []}}
	DB.last_config = cfg
	start_game(cfg)
	var winners := [0, 1, 2]
	for ch in 3:
		await _wait(1.5)
		var g = current
		print("CAMP chapter=", g.chapter, " season=", g.season_d["name"], " map_code=", g.map_code, " beasts=", g.objects.values().filter(func(o): return o["type"] == "beast").size(), " hours/round=", g.hours_per_round, " dark_speed=", g.dark_speed)
		for i in g.players.size():
			print("  ", g.players[i].name, " pet=", g.players[i].pet, " potions=", g.players[i].items.count("potion"), " hand=", g.players[i].hand.size())
		await _shot("c%d_story" % (ch + 1))
		g.hud._story_closed.emit()
		await _wait(1.0)
		g.hud.overlay_pass.visible = false
		g.cam_dist = 13.0
		g.cam_pitch = deg_to_rad(42.0)
		g.cam_target = g.players[0].node.position + Vector3(0, 0, 5)
		g.cam_goal = g.cam_target
		g.follow = null
		if ch == 2:
			g.rain.emitting = true
		await _wait(1.6)
		await _shot("c%d_map" % (ch + 1))
		# быстрая победа выбранного игрока
		Engine.time_scale = 6.0
		var w: Dictionary = g.players[winners[ch]]
		w.shards = 3
		g.players[(winners[ch] + 1) % 3].shards = 1
		g._victory(w)
		var guard := 0
		while not g._camp_ready and guard < 900:
			await get_tree().process_frame
			guard += 1
		Engine.time_scale = 1.0
		await _wait(1.0)
		await _shot("c%d_result" % (ch + 1))
		var wb := _find_button(g, "Что дальше?")
		if wb:
			wb.pressed.emit()
			await _wait(0.4)
			await _shot("c%d_result2" % (ch + 1))
		print("CAMP result: scores=", g._camp_scores, " wins=", g._camp_wins)
		if ch < 2:
			g.request_next()
	print("CAMP ach=", load("res://scripts/game/campaign.gd").load_all())
	print("CAMPTEST DONE")
	get_tree().quit()


func _bosstest() -> void:
	var lose := OS.get_environment("BOSS_LOSE") == "1"
	var list: Array = []
	for i in 3:
		list.append({"name": "Бот%d" % (i + 1), "hero": i, "pet": false, "slot": i, "team": 0, "ability": i})
	var cfg: Dictionary = {"players": list, "size": Vector2i(24, 50), "show_rules": false, "seed": 777, "team_mode": false,
		"camp": {"chapter": 3, "scores": [5, 7, 4], "wins": [[0], [1], [1]]}}
	start_game(cfg)
	await _wait(1.5)
	var g = current
	print("BOSS hp=", g.boss_hp, "/", g.boss_max, " map=", g.map.w, "x", g.map.h, " starts=", g.map.starts, " boss_pos=", g.map.boss_pos)
	await _shot("b_story")
	g.hud._story_closed.emit()
	await _wait(1.0)
	g.hud.overlay_pass.visible = false
	g.hud.fast = true
	g.cam_dist = 14.0
	g.cam_pitch = deg_to_rad(48.0)
	g.cam_target = g.map.world_pos(Vector2i(8, 11))
	g.cam_goal = g.cam_target
	g.cam_dist = 17.0
	g.follow = null
	await _wait(1.5)
	await _shot("b_arena")
	var bp: Vector2i = g.map.boss_pos
	for k in 3:
		g.rng.seed = 100 + k
		g.boss_tele_kind = ""
		g._boss_plan()
		print("BOSS plan ", g.boss_tele_kind, " tiles=", g.boss_tele.size())
		await _wait(0.6)
		await _shot("b_tele%d" % k)
		await g._boss_turn()
		await _wait(0.4)
	Engine.time_scale = 5.0
	var guard := 0
	while not g.game_over and guard < 400:
		guard += 1
		var q: Dictionary = g.players[guard % 3]
		q.hp = q.max_hp
		q.pos = bp + Vector2i(0, 2)
		if lose:
			g.round_no = Camp.BOSS_ROUNDS
			await g._advance_round()
			continue
		await g._fight_boss(q, g.objects[bp])
	Engine.time_scale = 1.0
	print("BOSS end defeated=", g.boss_defeated, " killer=", g.boss_killer, " dmg=", g.boss_dmg, " iters=", guard)
	var gg := 0
	while not g._camp_ready and gg < 900:
		await get_tree().process_frame
		gg += 1
	await _wait(1.0)
	await _shot("b_result")
	var wb := _find_button(g, "Что дальше?")
	if wb:
		wb.pressed.emit()
		await _wait(0.4)
		await _shot("b_result2")
	print("BOSS scores=", g._camp_scores, " ach=", load("res://scripts/game/campaign.gd").load_all())
	print("BOSSTEST DONE")
	get_tree().quit()
