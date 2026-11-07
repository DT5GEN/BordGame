extends Control
## Игра по сети: создать комнату, войти по коду, собрать игроков и начать.

signal start_requested(cfg: Dictionary)
signal closed

const SIZES := [["Малая", Vector2i(18, 38)], ["Средняя", Vector2i(24, 50)], ["Большая", Vector2i(36, 96)]]

var server_edit: LineEdit
var name_edit: LineEdit
var code_edit: LineEdit
var status: Label
var panel_enter: VBoxContainer
var panel_room: VBoxContainer
var room_title: Label
var players_box: VBoxContainer
var host_box: VBoxContainer
var size_btns: Array = []
var die_btns := {}
var team_cb: CheckBox
var start_btn: Button
var hero := 0
var ability := 0
var team := 0
var hero_btn: Button
var ab_btn: Button
var team_btn: Button
var size_idx := 1
var die := "D6"
var team_mode := false
var rejoin_btn: Button

func _ready() -> void:
	theme = Style.theme
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.03, 0.05, 0.94)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Style.sb(Style.GLASS_DARK, Style.GOLD, 2, 18, 18))
	pc.custom_minimum_size = Vector2(860, 0)
	center.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var t := Style.label("Игра по сети", 40, Style.GOLD, Style.font_title)
	v.add_child(t)
	var sh := HBoxContainer.new()
	v.add_child(sh)
	sh.add_child(Style.label("Сервер:", 20, Style.PARCH, Style.font_bold))
	server_edit = LineEdit.new()
	server_edit.placeholder_text = "например 12.34.56.78:7777"
	server_edit.custom_minimum_size = Vector2(380, 0)
	server_edit.add_theme_font_size_override("font_size", 20)
	sh.add_child(server_edit)
	status = Style.label("", 18, Style.TEAL, Style.font_bold)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 800
	v.add_child(status)
	_build_enter(v)
	_build_room(v)
	var bh := HBoxContainer.new()
	v.add_child(bh)
	var back := Style.button("Назад", 20, 140)
	back.pressed.connect(close)
	bh.add_child(back)

func _build_enter(parent: VBoxContainer) -> void:
	panel_enter = VBoxContainer.new()
	panel_enter.add_theme_constant_override("separation", 10)
	parent.add_child(panel_enter)
	var h1 := HBoxContainer.new()
	h1.add_theme_constant_override("separation", 10)
	panel_enter.add_child(h1)
	h1.add_child(Style.label("Твоё имя:", 20, Style.PARCH, Style.font_bold))
	name_edit = LineEdit.new()
	name_edit.max_length = 14
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.add_theme_font_size_override("font_size", 20)
	h1.add_child(name_edit)
	hero_btn = Style.button("", 18, 220)
	hero_btn.pressed.connect(func():
		hero = (hero + 1) % DB.heroes.size()
		_upd_profile())
	h1.add_child(hero_btn)
	ab_btn = Style.button("", 18, 260)
	ab_btn.pressed.connect(func():
		ability = (ability + 1) % DB.ABILITIES.size()
		_upd_profile())
	h1.add_child(ab_btn)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	panel_enter.add_child(h2)
	var mk := Style.button("Создать комнату", 24, 260)
	mk.add_theme_stylebox_override("normal", Style.sb(Color("2f5a3a"), Style.GOLD, 2, 12, 10))
	mk.pressed.connect(_create)
	h2.add_child(mk)
	h2.add_child(Style.label("или код:", 20, Style.PARCH, Style.font_bold))
	code_edit = LineEdit.new()
	code_edit.max_length = 4
	code_edit.placeholder_text = "ABCD"
	code_edit.custom_minimum_size = Vector2(120, 0)
	code_edit.add_theme_font_size_override("font_size", 26)
	code_edit.text_changed.connect(func(tx): 
		var up: String = tx.to_upper()
		if up != tx:
			var cp := code_edit.caret_column
			code_edit.text = up
			code_edit.caret_column = cp)
	h2.add_child(code_edit)
	var jn := Style.button("Войти", 24, 140)
	jn.pressed.connect(_join)
	h2.add_child(jn)
	rejoin_btn = Style.button("Вернуться в начатую игру", 20, 300)
	rejoin_btn.pressed.connect(func():
		_set_status("Возвращаюсь в игру…")
		Net.rejoin())
	panel_enter.add_child(rejoin_btn)

func _build_room(parent: VBoxContainer) -> void:
	panel_room = VBoxContainer.new()
	panel_room.add_theme_constant_override("separation", 8)
	panel_room.visible = false
	parent.add_child(panel_room)
	room_title = Style.label("", 34, Style.GOLD, Style.font_title)
	panel_room.add_child(room_title)
	panel_room.add_child(Style.label("Скажи друзьям этот код: они нажимают «Войти» и вводят его.", 18, Color(Style.PARCH, 0.8)))
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 4)
	panel_room.add_child(players_box)
	var me := HBoxContainer.new()
	me.add_theme_constant_override("separation", 10)
	panel_room.add_child(me)
	me.add_child(Style.label("Я:", 18, Style.PARCH, Style.font_bold))
	var hb := Style.button("", 17, 200)
	hb.pressed.connect(func():
		hero = (hero + 1) % DB.heroes.size()
		_upd_profile())
	me.add_child(hb)
	var ab2 := Style.button("", 17, 250)
	ab2.pressed.connect(func():
		ability = (ability + 1) % DB.ABILITIES.size()
		_upd_profile())
	me.add_child(ab2)
	team_btn = Style.button("", 17, 150)
	team_btn.pressed.connect(func():
		team = 1 - team
		_upd_profile())
	me.add_child(team_btn)
	hero_btn.set_meta("room_btn", hb)
	ab_btn.set_meta("room_btn", ab2)
	host_box = VBoxContainer.new()
	host_box.add_theme_constant_override("separation", 6)
	panel_room.add_child(host_box)
	var sz := HBoxContainer.new()
	sz.add_theme_constant_override("separation", 8)
	host_box.add_child(sz)
	sz.add_child(Style.label("Карта:", 18, Style.PARCH, Style.font_bold))
	for i in SIZES.size():
		var b := Style.button(SIZES[i][0], 17)
		b.toggle_mode = true
		b.pressed.connect(func():
			size_idx = i
			_push_cfg())
		sz.add_child(b)
		size_btns.append(b)
	sz.add_child(Style.label("  Кубик:", 18, Style.PARCH, Style.font_bold))
	for d in DB.dice_order:
		var b2 := Style.button(d, 17)
		b2.toggle_mode = true
		b2.pressed.connect(func():
			die = d
			_push_cfg())
		sz.add_child(b2)
		die_btns[d] = b2
	team_cb = CheckBox.new()
	team_cb.text = "Командная игра (Красные против Синих)"
	team_cb.add_theme_font_size_override("font_size", 18)
	team_cb.toggled.connect(func(on):
		team_mode = on
		_push_cfg())
	host_box.add_child(team_cb)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	panel_room.add_child(bh)
	start_btn = Style.button("Начать игру!", 30, 260)
	start_btn.add_theme_font_override("font", Style.font_title)
	start_btn.add_theme_stylebox_override("normal", Style.sb(Color("8a3b1f"), Style.GOLD, 3, 16, 12))
	start_btn.pressed.connect(func(): Net.start_game())
	bh.add_child(start_btn)
	var lv := Style.button("Выйти из комнаты", 19)
	lv.pressed.connect(func():
		Net.leave()
		_show_enter())
	bh.add_child(lv)

# ------------------------------------------------------------------ открытие
func open() -> void:
	visible = true
	move_to_front()
	server_edit.text = Net.saved_url()
	if name_edit.text == "":
		name_edit.text = str(Settings.get_meta("net_name", ""))
	_connect_signals()
	rejoin_btn.visible = not Net.saved_session().is_empty()
	if Net.room != "" and Net.state == "open":
		_show_room()
	else:
		_show_enter()
	_upd_profile()
	_set_status("")

func close() -> void:
	visible = false
	closed.emit()

func _connect_signals() -> void:
	if not Net.lobby.is_connected(_on_lobby):
		Net.lobby.connect(_on_lobby)
		Net.started.connect(_on_started)
		Net.error.connect(_on_error)
		Net.status.connect(_set_status)

func _exit_tree() -> void:
	if Net.lobby.is_connected(_on_lobby):
		Net.lobby.disconnect(_on_lobby)
		Net.started.disconnect(_on_started)
		Net.error.disconnect(_on_error)
		Net.status.disconnect(_set_status)

func _set_status(t: String) -> void:
	status.text = t

func _show_enter() -> void:
	panel_enter.visible = true
	panel_room.visible = false

func _show_room() -> void:
	panel_enter.visible = false
	panel_room.visible = true

func _profile() -> Dictionary:
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = DB.heroes[hero]["name"]
	return {"name": nm, "hero": hero, "ability": ability, "team": team}

func _upd_profile() -> void:
	var hn: String = DB.heroes[hero]["name"]
	var an: String = DB.ABILITIES[ability]["name"]
	for b in [hero_btn, hero_btn.get_meta("room_btn")]:
		b.text = "Герой: " + hn
	for b2 in [ab_btn, ab_btn.get_meta("room_btn")]:
		b2.text = "Способность: " + an
	team_btn.text = "Команда: " + ["Красные", "Синие"][team]
	if panel_room.visible and Net.state == "open":
		Net.set_profile(_profile())

func _cfg() -> Dictionary:
	return {"size_idx": size_idx, "die": die, "team_mode": team_mode, "balance": DB.balance_dict()}

func _push_cfg() -> void:
	if Net.host:
		Net.set_cfg(_cfg())

func _go_url() -> String:
	var u := Net.normalize(server_edit.text)
	if u == "":
		_set_status("Впиши адрес сервера (его даёт тот, кто его запустил).")
		return ""
	Net.save_url(server_edit.text.strip_edges())
	return u

func _create() -> void:
	var u := _go_url()
	if u == "":
		return
	Settings.set_meta("net_name", name_edit.text)
	_set_status("Создаю комнату…")
	Net.create_room(u, _profile(), _cfg())

func _join() -> void:
	var u := _go_url()
	if u == "":
		return
	var code := code_edit.text.strip_edges().to_upper()
	if code.length() != 4:
		_set_status("Код комнаты — 4 буквы.")
		return
	Settings.set_meta("net_name", name_edit.text)
	_set_status("Вхожу в комнату %s…" % code)
	Net.join_room(u, code, _profile())

func _on_error(t: String) -> void:
	_set_status("⚠ " + t)
	if Net.state != "open" or Net.room == "":
		_show_enter()

# ------------------------------------------------------------------ комната
func _on_lobby(d: Dictionary) -> void:
	if not visible:
		return
	_show_room()
	room_title.text = "Комната: %s" % d["room"]
	var cfg: Dictionary = d.get("cfg", {})
	if not Net.host:
		size_idx = int(cfg.get("size_idx", size_idx))
		die = str(cfg.get("die", die))
		team_mode = bool(cfg.get("team_mode", team_mode))
		team_cb.set_pressed_no_signal(team_mode)
	for i in size_btns.size():
		size_btns[i].set_pressed_no_signal(i == size_idx)
		size_btns[i].disabled = not Net.host
	for k in die_btns:
		die_btns[k].set_pressed_no_signal(k == die)
		die_btns[k].disabled = not Net.host
	team_cb.disabled = not Net.host
	team_btn.visible = team_mode
	for c in players_box.get_children():
		c.queue_free()
	var host_id := int(d.get("host", -1))
	for pl in d["players"]:
		var l := Style.label("%s%s — %s, %s%s" % ["★ " if int(pl["cid"]) == host_id else "", pl["name"], DB.heroes[int(pl["hero"])]["name"], DB.ABILITIES[int(pl["ability"])]["name"], (", " + ["Красные", "Синие"][int(pl["team"])]) if team_mode else ""], 20, Style.PARCH if pl["online"] else Color(Style.PARCH, 0.4), Style.font_bold)
		players_box.add_child(l)
	start_btn.visible = Net.host
	start_btn.disabled = d["players"].size() < 2
	start_btn.text = "Начать игру!" if d["players"].size() >= 2 else "Ждём друзей…"
	host_box.visible = true
	if Net.host and cfg.is_empty():
		_push_cfg()

func _on_started(d: Dictionary) -> void:
	visible = false
	var cfg0: Dictionary = d.get("cfg", {})
	if cfg0.has("balance"):
		DB.use_balance(cfg0["balance"])
	var list: Array = []
	var my := -1
	for i in d["seats"].size():
		var s: Dictionary = d["seats"][i]
		if int(s["cid"]) == Net.cid:
			my = i
		list.append({"name": s["name"], "hero": int(s["hero"]), "pet": false, "slot": i, "team": int(s["team"]), "ability": int(s["ability"]), "cid": int(s["cid"])})
	var cfg := {"players": list, "size": SIZES[clampi(int(cfg0.get("size_idx", 1)), 0, SIZES.size() - 1)][1],
		"show_rules": false, "team_mode": bool(cfg0.get("team_mode", false)), "die": str(cfg0.get("die", "D6")),
		"seed": int(d["seed"]), "net": true, "my_seat": my, "replay": bool(d.get("replay", false))}
	start_requested.emit(cfg)
