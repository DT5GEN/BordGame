extends Control
## Главное меню: число игроков 1–6, имена, выбор из 10 героев, питомец, размер карты.

signal start_requested(cfg: Dictionary)
signal intro_requested

const Models = preload("res://scripts/world/models.gd")
const Papyrus = preload("res://scripts/ui/papyrus.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const CardEditor = preload("res://scripts/menu/card_editor.gd")
const NetLobby = preload("res://scripts/menu/net_lobby.gd")

const SIZES := [
	["Малая", Vector2i(18, 38), "≈10 мин"],
	["Средняя", Vector2i(24, 50), "≈15–20 мин"],
	["Большая", Vector2i(36, 96), "долгое приключение"],
]

var slots: Array = []
var count := 2
var team_mode := false
var team_cb: CheckBox
var team_info: Label
var selected := 0
var size_idx := 1
var die := "D6"
var die_btns := {}
var rows_box: VBoxContainer
var count_lbl: Label
var size_btns: Array = []
var rules_cb: CheckBox
var camp_cb: CheckBox
var preview_root: Node3D
var preview_hero: Node3D
var preview_name: Label
var preview_title: Label
var ability_lbl: Label
var ability_txt: Label
var code_edit: LineEdit
var papyrus
var settings_panel
var card_editor
var net_lobby

func _ready() -> void:
	theme = Style.theme
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	var used := []
	for i in 10:
		var h := (i * 3) % DB.heroes.size()
		slots.append({"name": DB.heroes[h]["name"], "hero": h, "pet": false, "team": i % 2, "ability": i % DB.ABILITIES.size()})
	var lc: Dictionary = DB.last_config
	if not lc.is_empty():
		var lp: Array = lc["players"]
		count = lp.size()
		for i in lp.size():
			slots[i] = {"name": lp[i]["name"], "hero": lp[i]["hero"], "pet": i == DB.last_winner_slot, "team": int(lp[i].get("team", i % 2)), "ability": int(lp[i].get("ability", i % DB.ABILITIES.size()))}
		team_mode = lc.get("team_mode", false)
		die = lc.get("die", "D6")
		for i in SIZES.size():
			if SIZES[i][1] == lc["size"]:
				size_idx = i
	_build()
	papyrus = Papyrus.new()
	add_child(papyrus)
	settings_panel = SettingsPanel.new()
	add_child(settings_panel)
	card_editor = CardEditor.new()
	add_child(card_editor)
	net_lobby = NetLobby.new()
	net_lobby.start_requested.connect(func(c): start_requested.emit(c))
	add_child(net_lobby)
	_refresh()

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.10, 0.16, 0.22);
	vec3 mid = vec3(0.20, 0.30, 0.22);
	vec3 bot = vec3(0.09, 0.06, 0.04);
	vec3 c = mix(top, mid, smoothstep(0.0, 0.6, uv.y));
	c = mix(c, bot, smoothstep(0.55, 1.0, uv.y));
	float v = 1.0 - distance(uv, vec2(0.7, 0.45)) * 0.9;
	c *= 0.7 + 0.5 * v;
	float star = step(0.997, fract(sin(dot(floor(uv * vec2(320.0, 180.0)), vec2(12.9898, 78.233))) * 43758.5453)) * (1.0 - uv.y * 1.6);
	c += vec3(star) * (0.6 + 0.4 * sin(TIME * 2.0 + uv.x * 40.0));
	COLOR = vec4(c, 1.0);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	bg.material = sm
	add_child(bg)
	# Превью героя
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	svc.anchor_left = 0.6
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	preview_root = Node3D.new()
	sv.add_child(preview_root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 2.6)
	cam.fov = 38
	preview_root.add_child(cam)
	cam.look_at(Vector3(0, 0.55, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	preview_root.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 1.2, 1.5)
	fill.light_color = Color("ffc890")
	fill.light_energy = 0.8
	fill.omni_range = 5
	preview_root.add_child(fill)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	preview_root.add_child(we)
	Models.add(preview_root, Models.cyl(0.6, 0.65, 0.2, 24), Color("5fa04a"), Vector3(0, -0.1, 0))
	Models.add(preview_root, Models.cyl(0.66, 0.7, 0.12, 24), Color("7a5a3a"), Vector3(0, -0.22, 0))
	for i in 7:
		var a := i * TAU / 7.0
		Models.add(preview_root, Models.sphere(0.04, 6), [Color("ffd84a"), Color("ff8fb8"), Color("fff6e0")][i % 3], Vector3(cos(a) * 0.48, 0.02, sin(a) * 0.48))
	var pinfo := VBoxContainer.new()
	pinfo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pinfo.anchor_left = 0.68
	pinfo.anchor_top = 1.0
	pinfo.offset_top = -210
	pinfo.offset_bottom = -30
	pinfo.offset_right = -8
	pinfo.alignment = BoxContainer.ALIGNMENT_CENTER
	pinfo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pinfo)
	preview_name = Style.outlined(Style.label("", 44, Style.GOLD, Style.font_title), 10)
	preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pinfo.add_child(preview_name)
	preview_title = Style.outlined(Style.label("", 24, Style.PARCH), 6)
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pinfo.add_child(preview_title)
	# выбор способности для выбранного игрока
	var ah := HBoxContainer.new()
	ah.alignment = BoxContainer.ALIGNMENT_CENTER
	pinfo.add_child(ah)
	var al := Style.glass_button(Style.button("◀", 20, 44))
	al.pressed.connect(func(): _cycle_ability(-1))
	ah.add_child(al)
	ability_lbl = Style.outlined(Style.label("", 24, Style.TEAL, Style.font_title), 6)
	ability_lbl.custom_minimum_size.x = 250
	ability_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ah.add_child(ability_lbl)
	var ar := Style.glass_button(Style.button("▶", 20, 44))
	ar.pressed.connect(func(): _cycle_ability(1))
	ah.add_child(ar)
	ability_txt = Style.outlined(Style.label("", 16, Style.PARCH), 5)
	ability_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ability_txt.custom_minimum_size.x = 380
	pinfo.add_child(ability_txt)
	# Левая панель
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 20)
	panel.custom_minimum_size = Vector2(640, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := Style.outlined(Style.label("Осколки Долины", 56, Style.GOLD, Style.font_title), 8)
	v.add_child(t)
	v.add_child(Style.label("Пошаговое приключение на одном телефоне • прототип 0.1", 18, Color(Style.PARCH, 0.7)))
	var ch := HBoxContainer.new()
	v.add_child(ch)
	ch.add_child(Style.label("Игроков:", 24, Style.PARCH, Style.font_bold))
	var minus := Style.button("−", 26, 48)
	minus.pressed.connect(func(): _set_count(count - 1))
	ch.add_child(minus)
	count_lbl = Style.label("2", 30, Style.GOLD, Style.font_title)
	count_lbl.custom_minimum_size.x = 30
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch.add_child(count_lbl)
	var plus := Style.button("+", 26, 48)
	plus.pressed.connect(func(): _set_count(count + 1))
	ch.add_child(plus)
	var sp := Control.new()
	sp.custom_minimum_size.x = 20
	ch.add_child(sp)
	ch.add_child(Style.label("Карта:", 24, Style.PARCH, Style.font_bold))
	for i in SIZES.size():
		var b := Style.button(SIZES[i][0], 19)
		b.toggle_mode = true
		b.tooltip_text = "%d×%d, %s" % [SIZES[i][1].x, SIZES[i][1].y, SIZES[i][2]]
		b.pressed.connect(func(): _choose_size(i))
		ch.add_child(b)
		size_btns.append(b)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "код карты"
	code_edit.tooltip_text = "Введи код, чтобы сыграть ту же карту ещё раз. Пусто — новая карта"
	code_edit.max_length = 6
	code_edit.custom_minimum_size.x = 120
	code_edit.add_theme_font_size_override("font_size", 18)
	ch.add_child(code_edit)
	# кубик партии — один на всех и до конца игры
	var dh := HBoxContainer.new()
	v.add_child(dh)
	dh.add_child(Style.label("Кубик партии:", 22, Style.PARCH, Style.font_bold))
	for d in DB.dice_order:
		var b := Style.button("%s  %s" % [d, DB.die_range_text(d)], 17)
		b.toggle_mode = true
		b.tooltip_text = "%s: %s шагов, %s. Один кубик для всех до конца партии" % [d, DB.die_range_text(d), DB.dice[d]["label"]]
		b.pressed.connect(func():
			die = d
			_refresh())
		dh.add_child(b)
		die_btns[d] = b
	team_cb = CheckBox.new()
	team_cb.text = "Командная игра: Красные против Синих"
	team_cb.button_pressed = team_mode
	team_cb.add_theme_font_size_override("font_size", 19)
	team_cb.toggled.connect(func(on):
		team_mode = on
		_refresh())
	v.add_child(team_cb)
	camp_cb = CheckBox.new()
	camp_cb.text = "Кампания: Лето, Осень, Зима (3 карты и сюжет)"
	camp_cb.button_pressed = DB.last_config.has("camp")
	camp_cb.add_theme_font_size_override("font_size", 19)
	v.add_child(camp_cb)
	var rs := ScrollContainer.new()
	rs.custom_minimum_size = Vector2(0, 250)
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(rs)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 6)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(rows_box)
	rules_cb = CheckBox.new()
	rules_cb.text = "Показать свиток с правилами в начале"
	rules_cb.button_pressed = DB.last_config.is_empty()
	rules_cb.add_theme_font_size_override("font_size", 19)
	v.add_child(rules_cb)
	var bh := HBoxContainer.new()
	v.add_child(bh)
	var go := Style.button("В путь!", 34, 210)
	go.add_theme_font_override("font", Style.font_title)
	go.add_theme_stylebox_override("normal", Style.sb(Color("8a3b1f"), Style.GOLD, 3, 16, 12))
	go.add_theme_stylebox_override("hover", Style.sb(Color("a84a28"), Color.WHITE, 3, 16, 12))
	go.pressed.connect(_start)
	bh.add_child(go)
	var rb := Style.button("Правила", 19)
	rb.pressed.connect(func(): papyrus.open())
	bh.add_child(rb)
	var ib := Style.button("История", 19)
	ib.pressed.connect(func(): intro_requested.emit())
	bh.add_child(ib)
	var eb := Style.button("Редактор карт", 19)
	eb.pressed.connect(func(): card_editor.open())
	bh.add_child(eb)
	var nb := Style.button("По сети", 19)
	nb.pressed.connect(func(): net_lobby.open())
	bh.add_child(nb)
	var sbn := Style.button("Настройки", 19)
	sbn.pressed.connect(func(): settings_panel.open())
	bh.add_child(sbn)

func _set_count(n: int) -> void:
	count = clampi(n, 1, 10)
	selected = mini(selected, count - 1)
	_refresh()

func _choose_size(i: int) -> void:
	size_idx = i
	_refresh()

func _refresh() -> void:
	count_lbl.text = str(count)
	for i in size_btns.size():
		size_btns[i].button_pressed = i == size_idx
	for d in die_btns:
		die_btns[d].button_pressed = d == die
	for c in rows_box.get_children():
		c.queue_free()
	for i in count:
		rows_box.add_child(_make_row(i))
	_update_preview()

func _make_row(i: int) -> Control:
	var s: Dictionary = slots[i]
	var pc := PanelContainer.new()
	var col: Color = DB.PLAYER_COLORS[i]
	pc.add_theme_stylebox_override("panel", Style.sb(Color(0.2, 0.13, 0.08, 0.9) if i == selected else Color(0.1, 0.07, 0.05, 0.7), col if i == selected else Color(col, 0.35), 2, 12, 6))
	pc.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_select(i))
	var h := HBoxContainer.new()
	pc.add_child(h)
	var d := Panel.new()
	d.custom_minimum_size = Vector2(18, 18)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.add_theme_stylebox_override("panel", Style.sb(col, Color.WHITE, 2, 9, 0))
	h.add_child(d)
	var le := LineEdit.new()
	le.text = s["name"]
	le.max_length = 14
	le.custom_minimum_size.x = 150
	le.placeholder_text = "Имя героя"
	le.text_changed.connect(func(tx): slots[i]["name"] = tx)
	le.focus_entered.connect(func(): _select(i, false))
	h.add_child(le)
	var l := Style.button("◀", 20, 40)
	l.pressed.connect(func(): _cycle(i, -1))
	h.add_child(l)
	var hl := Style.label(DB.heroes[s["hero"]]["title"], 17, Style.PARCH)
	hl.custom_minimum_size.x = 190
	hl.clip_text = true
	hl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(hl)
	var r := Style.button("▶", 20, 40)
	r.pressed.connect(func(): _cycle(i, 1))
	h.add_child(r)
	if team_mode:
		var tb := Style.button(["Красные", "Синие"][s["team"]], 17, 96)
		var tc: Color = DB.TEAM_COLORS[s["team"]]
		tb.add_theme_stylebox_override("normal", Style.sb(tc.darkened(0.35), tc, 2, 10, 6))
		tb.add_theme_stylebox_override("hover", Style.sb(tc.darkened(0.15), Color.WHITE, 2, 10, 6))
		tb.pressed.connect(func():
			slots[i]["team"] = 1 - int(slots[i]["team"])
			_refresh())
		h.add_child(tb)
	var pet := CheckBox.new()
	pet.text = "Питомец"
	pet.button_pressed = s["pet"]
	pet.tooltip_text = "Питомец достаётся победителю прошлой партии (+1 к обзору)"
	pet.add_theme_font_size_override("font_size", 17)
	pet.toggled.connect(func(on): slots[i]["pet"] = on)
	h.add_child(pet)
	return pc

func _select(i: int, rebuild := true) -> void:
	if selected == i:
		return
	selected = i
	if rebuild:
		_refresh()
	else:
		_update_preview()

func _cycle(i: int, d: int) -> void:
	var s: Dictionary = slots[i]
	var old_name: String = DB.heroes[s["hero"]]["name"]
	s["hero"] = posmod(s["hero"] + d, DB.heroes.size())
	if s["name"] == old_name or s["name"] == "":
		s["name"] = DB.heroes[s["hero"]]["name"]
	selected = i
	_refresh()

func _update_preview() -> void:
	if preview_hero:
		preview_hero.queue_free()
	var s: Dictionary = slots[selected]
	var pr: Dictionary = DB.heroes[s["hero"]]
	preview_hero = Models.hero(pr)
	preview_root.add_child(preview_hero)
	if s["pet"]:
		var pet := Models.pet_fox()
		pet.position = Vector3(0.42, 0, 0.1)
		preview_hero.add_child(pet)
	preview_name.text = s["name"] if s["name"] != "" else pr["name"]
	preview_title.text = pr["title"]
	var ab: Dictionary = DB.ability(int(s["ability"]))
	ability_lbl.text = ab["name"]
	ability_txt.text = ab["text"]

func _process(delta: float) -> void:
	if preview_hero:
		preview_hero.rotation.y += delta * 0.7

func _cycle_ability(d: int) -> void:
	slots[selected]["ability"] = posmod(int(slots[selected]["ability"]) + d, DB.ABILITIES.size())
	_update_preview()

func _start() -> void:
	var list: Array = []
	for i in count:
		var s: Dictionary = slots[i]
		var nm: String = s["name"].strip_edges()
		if nm == "":
			nm = "Игрок %d" % (i + 1)
		list.append({"name": nm, "hero": s["hero"], "pet": s["pet"], "slot": i, "team": int(s["team"]), "ability": int(s["ability"])})
	var tm := team_mode
	if tm:
		var n0 := 0
		for e in list:
			if e["team"] == 0:
				n0 += 1
		if n0 == 0 or n0 == list.size():
			tm = false
	var cfg := {"players": list, "size": SIZES[size_idx][1], "show_rules": rules_cb.button_pressed, "team_mode": tm, "die": die}
	if code_edit.text.strip_edges().is_valid_int():
		cfg["seed"] = int(code_edit.text.strip_edges())
	if camp_cb.button_pressed:
		cfg["camp"] = {"chapter": 0, "scores": [], "wins": []}
	DB.last_config = cfg
	start_requested.emit(cfg)
