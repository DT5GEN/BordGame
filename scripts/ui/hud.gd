extends CanvasLayer
## Интерфейс партии: карточка героя, время суток, кубики, кнопки, всплывающие окна.

signal roll_requested(die: String)
signal end_turn_requested
signal trap_card_chosen(idx: int)
signal item_used(idx: int)
signal pass_ready
signal help_requested
signal focus_requested
signal cancel_mode
signal menu_requested
signal restart_requested
signal _alert_closed

var game
var phase := "wait"
var fast := false
var selected_die := "D6"

var root: Control
var hero_panel: PanelContainer
var name_lbl: Label
var title_lbl: Label
var hp_bar: ProgressBar
var hp_lbl: Label
var shard_lbl: Label
var info_lbl: Label
var status_lbl: Label
var dot: Panel
var time_lbl: Label
var bottom: PanelContainer
var roll_box: HBoxContainer
var act_box: HBoxContainer
var trap_box: HBoxContainer
var dice_btns := {}
var steps_lbl: Label
var trap_btn: Button
var bag_btn: Button
var toasts: VBoxContainer
var roll_lbl: Label
var roll_sub: Label
var overlay_pass: ColorRect
var popup: PanelContainer
var popup_box: VBoxContainer
var alert_panel: PanelContainer
var banner: VBoxContainer

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Style.theme
	add_child(root)
	_build_hero_panel()
	_build_top()
	_build_bottom()
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-330, 70)
	toasts.custom_minimum_size = Vector2(660, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(toasts)
	roll_lbl = Style.outlined(Style.label("", 150, Style.GOLD, Style.font_title), 16)
	roll_lbl.set_anchors_preset(Control.PRESET_CENTER)
	roll_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roll_lbl.custom_minimum_size = Vector2(800, 200)
	roll_lbl.position = Vector2(-400, -170)
	roll_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_lbl.visible = false
	root.add_child(roll_lbl)
	roll_sub = Style.outlined(Style.label("", 34, Style.PARCH, Style.font_bold), 10)
	roll_sub.set_anchors_preset(Control.PRESET_CENTER)
	roll_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roll_sub.custom_minimum_size = Vector2(900, 100)
	roll_sub.position = Vector2(-450, 30)
	roll_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_sub.visible = false
	root.add_child(roll_sub)
	banner = VBoxContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.custom_minimum_size = Vector2(1000, 200)
	banner.position = Vector2(-500, -200)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.visible = false
	root.add_child(banner)
	_build_pass()
	popup = PanelContainer.new()
	popup.visible = false
	root.add_child(popup)
	alert_panel = PanelContainer.new()
	alert_panel.visible = false
	root.add_child(alert_panel)

# ------------------------------------------------------------ построение
func _build_hero_panel() -> void:
	hero_panel = PanelContainer.new()
	hero_panel.position = Vector2(12, 12)
	hero_panel.custom_minimum_size = Vector2(330, 0)
	root.add_child(hero_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	hero_panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	dot = Panel.new()
	dot.custom_minimum_size = Vector2(22, 22)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	name_lbl = Style.label("", 28, Style.PARCH, Style.font_title)
	h.add_child(name_lbl)
	title_lbl = Style.label("", 17, Color(Style.PARCH, 0.7))
	v.add_child(title_lbl)
	var hh := HBoxContainer.new()
	v.add_child(hh)
	hh.add_child(Style.label("HP", 20, Style.RED, Style.font_bold))
	hp_bar = ProgressBar.new()
	hp_bar.max_value = 20
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(190, 22)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(hp_bar)
	hp_lbl = Style.label("20/20", 20, Style.PARCH, Style.font_bold)
	hh.add_child(hp_lbl)
	shard_lbl = Style.label("", 22, Style.TEAL, Style.font_bold)
	v.add_child(shard_lbl)
	info_lbl = Style.label("", 17, Color(Style.PARCH, 0.85))
	v.add_child(info_lbl)
	status_lbl = Style.label("", 17, Color("ffb070"))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.custom_minimum_size.x = 300
	v.add_child(status_lbl)

func _build_top() -> void:
	var tp := PanelContainer.new()
	tp.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tp.position = Vector2(-210, 10)
	tp.custom_minimum_size = Vector2(420, 0)
	tp.add_theme_stylebox_override("panel", Style.sb(Style.WOOD, Style.GOLD, 2, 20, 8))
	root.add_child(tp)
	time_lbl = Style.label("", 22, Style.PARCH, Style.font_bold)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tp.add_child(time_lbl)
	var right := HBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-330, 12)
	right.custom_minimum_size = Vector2(318, 0)
	right.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(right)
	var fb := Style.button("К герою", 20)
	fb.pressed.connect(func(): focus_requested.emit())
	right.add_child(fb)
	var hb := Style.button("?", 28, 56)
	hb.add_theme_font_override("font", Style.font_title)
	hb.tooltip_text = "Свиток с правилами"
	hb.pressed.connect(func(): help_requested.emit())
	right.add_child(hb)
	var mb := Style.button("Меню", 20)
	mb.pressed.connect(_confirm_menu)
	right.add_child(mb)

func _build_bottom() -> void:
	bottom = PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 12
	root.add_child(bottom)
	var stack := VBoxContainer.new()
	bottom.add_child(stack)
	roll_box = HBoxContainer.new()
	roll_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(roll_box)
	roll_box.add_child(Style.label("Кубик:", 22, Style.GOLD, Style.font_bold))
	for d in DB.dice_order:
		var b := Style.button("%s\n%s" % [d, DB.die_range_text(d)], 18, 84)
		b.toggle_mode = true
		b.tooltip_text = DB.dice[d]["label"]
		b.pressed.connect(_select_die.bind(d))
		roll_box.add_child(b)
		dice_btns[d] = b
	var rb := Style.button("Бросить!", 30, 170)
	rb.add_theme_font_override("font", Style.font_title)
	rb.add_theme_stylebox_override("normal", Style.sb(Color("8a3b1f"), Style.GOLD, 3, 14, 12))
	rb.add_theme_stylebox_override("hover", Style.sb(Color("a84a28"), Color.WHITE, 3, 14, 12))
	rb.pressed.connect(func(): roll_requested.emit(selected_die))
	roll_box.add_child(rb)
	act_box = HBoxContainer.new()
	act_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(act_box)
	steps_lbl = Style.label("", 30, Style.TEAL, Style.font_title)
	steps_lbl.custom_minimum_size.x = 170
	act_box.add_child(steps_lbl)
	trap_btn = Style.button("Ловушки", 22)
	trap_btn.pressed.connect(_show_traps)
	act_box.add_child(trap_btn)
	bag_btn = Style.button("Сумка", 22)
	bag_btn.pressed.connect(_show_bag)
	act_box.add_child(bag_btn)
	var eb := Style.button("Закончить ход", 24)
	eb.add_theme_stylebox_override("normal", Style.sb(Color("2f5a3a"), Style.GOLD, 2, 12, 10))
	eb.add_theme_stylebox_override("hover", Style.sb(Color("3d7049"), Color.WHITE, 2, 12, 10))
	eb.pressed.connect(func(): end_turn_requested.emit())
	act_box.add_child(eb)
	trap_box = HBoxContainer.new()
	trap_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(trap_box)
	trap_box.add_child(Style.label("Выбери клетку для ловушки", 22, Color("e0a0ff"), Style.font_bold))
	var cb := Style.button("Отмена", 22)
	cb.pressed.connect(func(): cancel_mode.emit())
	trap_box.add_child(cb)
	_select_die("D6")

func _build_pass() -> void:
	overlay_pass = ColorRect.new()
	overlay_pass.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_pass.color = Color(0.06, 0.04, 0.03, 1.0)
	overlay_pass.visible = false
	root.add_child(overlay_pass)

# ------------------------------------------------------------ обновление
func _select_die(d: String) -> void:
	selected_die = d
	for k in dice_btns:
		dice_btns[k].button_pressed = k == d

func set_phase(ph: String) -> void:
	phase = ph
	roll_box.visible = ph == "roll"
	act_box.visible = ph == "act"
	trap_box.visible = ph == "trap"
	bottom.visible = ph in ["roll", "act", "trap"]
	if ph == "roll" and game:
		_select_die(game.current().die)
	_close_popup()
	refresh()

func refresh() -> void:
	if game == null or game.players.is_empty():
		return
	var p: Dictionary = game.current()
	var pr: Dictionary = DB.heroes[p.hero]
	name_lbl.text = p.name
	title_lbl.text = pr["title"] + (" • с питомцем" if p.pet else "")
	dot.add_theme_stylebox_override("panel", Style.sb(p.color, Color.WHITE, 2, 11, 0))
	hp_bar.value = p.hp
	hp_lbl.text = "%d/20" % p.hp
	var gems := ""
	for i in 3:
		gems += "◆ " if p.shards > i else "◇ "
	if p.shards > 3:
		gems += "+%d" % (p.shards - 3)
	shard_lbl.text = "Осколки: " + gems
	var rows: int = game.map.shrine.y - p.pos.y
	info_lbl.text = "Ловушек: %d • Предметов: %d • До святилища: %d" % [p.hand.size(), p.items.size(), rows]
	var st: Array = []
	if p.now_skip_move:
		st.append("застрял")
	if p.now_slow > 0:
		st.append("замедлен −%d" % p.now_slow)
	if p.now_block_traps:
		st.append("без ловушек")
	if p.vuln > 0 or p.now_vuln:
		st.append("помечен охотником")
	if p.dot > 0:
		st.append("горит")
	if game.night and p.pos.y <= game.dark_row:
		st.append("в ТЬМЕ!")
	status_lbl.text = ", ".join(st)
	status_lbl.visible = not st.is_empty()
	var w: String = game.weather
	time_lbl.text = "Раунд %d  •  %s  %s  •  %s" % [game.round_no, game.clock_text(), game.time_name(), w]
	steps_lbl.text = "Шагов: %d" % game.steps_left
	trap_btn.text = "Ловушки (%d)" % p.hand.size()
	bag_btn.text = "Сумка (%d)" % p.items.size()

# ------------------------------------------------------------ сообщения
func toast(text: String, col: Color = Style.PARCH, dur: float = 3.0) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Style.sb(Color(0.08, 0.05, 0.03, 0.85), Color(col, 0.6), 2, 12, 8))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Style.label(text, 21, col, Style.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc.add_child(l)
	toasts.add_child(pc)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var tw := pc.create_tween()
	tw.tween_interval(dur)
	tw.tween_property(pc, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pc.queue_free)

func big_banner(title: String, sub: String) -> void:
	for c in banner.get_children():
		c.queue_free()
	var t := Style.outlined(Style.label(title, 84, Style.GOLD, Style.font_title), 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(t)
	var s := Style.outlined(Style.label(sub, 30, Style.PARCH, Style.font_bold), 10)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(s)
	banner.visible = true
	banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.4)
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): banner.visible = false)

func animate_roll(die: String, face: int, steps: int, note: String) -> void:
	if fast:
		await get_tree().process_frame
		return
	roll_lbl.visible = true
	roll_sub.visible = false
	var faces: Array = DB.die_faces(die)
	for i in 14:
		roll_lbl.text = "%s: %d" % [die, randi_range(1, faces.size())]
		roll_lbl.scale = Vector2.ONE
		await get_tree().create_timer(0.045 + i * 0.006).timeout
	roll_lbl.text = "%s: %d" % [die, face]
	roll_lbl.pivot_offset = roll_lbl.size * 0.5
	var tw := create_tween()
	tw.tween_property(roll_lbl, "scale", Vector2.ONE * 1.25, 0.12)
	tw.tween_property(roll_lbl, "scale", Vector2.ONE, 0.15)
	roll_sub.text = "Шагов в этот ход: %d" % steps + ("\n" + note if note != "" else "")
	roll_sub.visible = true
	await get_tree().create_timer(1.4 if note == "" else 2.4).timeout
	roll_lbl.visible = false
	roll_sub.visible = false

func _place_center(pc: Control, w: float) -> void:
	pc.custom_minimum_size = Vector2(w, 0)
	pc.reset_size()
	await get_tree().process_frame
	var vs := root.get_viewport_rect().size
	pc.position = (vs - pc.size) * 0.5

func alert(title: String, text: String, col: Color = Style.GOLD) -> void:
	for c in alert_panel.get_children():
		c.queue_free()
	alert_panel.add_theme_stylebox_override("panel", Style.sb(Color(0.1, 0.07, 0.05, 0.96), col, 3, 18, 22))
	var v := VBoxContainer.new()
	alert_panel.add_child(v)
	var t := Style.label(title, 38, col, Style.font_title)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var l := Style.label(text, 24, Style.PARCH)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var b := Style.button("Понятно", 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): _alert_closed.emit())
	v.add_child(b)
	alert_panel.visible = true
	alert_panel.modulate.a = 0.0
	_place_center(alert_panel, 620)
	if fast:
		print("ALERT: ", title, " | ", text.replace("\n", " / "))
		await get_tree().process_frame
		alert_panel.visible = false
		return
	var tw := create_tween()
	tw.tween_property(alert_panel, "modulate:a", 1.0, 0.2)
	await _alert_closed
	alert_panel.visible = false

func show_duel(a_name: String, a_roll: int, b_name: String, b_val: int, win: bool, result: String, pvp := false) -> void:
	for c in alert_panel.get_children():
		c.queue_free()
	alert_panel.add_theme_stylebox_override("panel", Style.sb(Color(0.1, 0.07, 0.05, 0.96), Style.RED, 3, 18, 22))
	var v := VBoxContainer.new()
	alert_panel.add_child(v)
	var t := Style.label("Схватка!", 44, Style.RED, Style.font_title)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 40)
	v.add_child(h)
	var a_box := VBoxContainer.new()
	h.add_child(a_box)
	a_box.add_child(Style.label(a_name, 24, Style.PARCH, Style.font_bold))
	var a_num := Style.label("?", 80, Style.GOLD, Style.font_title)
	a_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a_box.add_child(a_num)
	h.add_child(Style.label("против", 24, Color(Style.PARCH, 0.6)))
	var b_box := VBoxContainer.new()
	h.add_child(b_box)
	b_box.add_child(Style.label(b_name, 24, Style.PARCH, Style.font_bold))
	var b_num := Style.label("?" if pvp else str(b_val), 80, Style.RED, Style.font_title)
	b_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_box.add_child(b_num)
	var res := Style.label(" ", 26, Style.PARCH, Style.font_bold)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(res)
	var b := Style.button("Дальше", 24)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.disabled = true
	b.pressed.connect(func(): _alert_closed.emit())
	v.add_child(b)
	alert_panel.visible = true
	_place_center(alert_panel, 640)
	if fast:
		print("DUEL: %s %d vs %s %d -> %s" % [a_name, a_roll, b_name, b_val, result])
		await get_tree().process_frame
		alert_panel.visible = false
		return
	for i in 10:
		a_num.text = str(randi_range(1, 6))
		if pvp:
			b_num.text = str(randi_range(1, 6))
		await get_tree().create_timer(0.06).timeout
	a_num.text = str(a_roll)
	b_num.text = str(b_val)
	if pvp:
		res.text = result
		res.add_theme_color_override("font_color", Style.GREEN if win else Style.RED)
	else:
		res.text = ("Победа! " if win else "Поражение... ") + result
		res.add_theme_color_override("font_color", Style.GREEN if win else Style.RED)
	b.disabled = false
	await _alert_closed
	alert_panel.visible = false

# ------------------------------------------------------------ передача телефона
func show_pass(p: Dictionary, reports: Array) -> void:
	for c in overlay_pass.get_children():
		c.queue_free()
	var col: Color = p.color
	overlay_pass.color = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 1.0)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_pass.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var a := Style.label("Передай телефон", 30, Color(Style.PARCH, 0.7), Style.font_bold)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var n := Style.outlined(Style.label(p.name, 96, col.lightened(0.2), Style.font_title), 12)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var t := Style.label(DB.heroes[p.hero]["title"], 26, Style.PARCH)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := Style.label("Остальные — не подглядывайте!", 22, Color(Style.GOLD, 0.8))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	if not reports.is_empty():
		var rp := PanelContainer.new()
		rp.add_theme_stylebox_override("panel", Style.sb(Color(0, 0, 0, 0.4), Color(Style.GOLD, 0.5), 2, 14, 14))
		v.add_child(rp)
		var rv := VBoxContainer.new()
		rp.add_child(rv)
		rv.add_child(Style.label("Пока тебя не было:", 22, Style.GOLD, Style.font_bold))
		for r in reports:
			var rl := Style.label("• " + str(r), 21, Style.PARCH)
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size.x = 600
			rv.add_child(rl)
	var b := Style.button("Я готов!", 34, 260)
	b.add_theme_font_override("font", Style.font_title)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		overlay_pass.visible = false
		pass_ready.emit())
	v.add_child(b)
	overlay_pass.visible = true

# ------------------------------------------------------------ списки
func _open_popup(title: String) -> VBoxContainer:
	for c in popup.get_children():
		c.queue_free()
	popup.add_theme_stylebox_override("panel", Style.sb(Color(0.1, 0.07, 0.05, 0.97), Style.GOLD, 3, 18, 16))
	var v := VBoxContainer.new()
	popup.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Style.label(title, 32, Style.GOLD, Style.font_title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var x := Style.button("Закрыть", 20)
	x.pressed.connect(_close_popup)
	h.add_child(x)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 380)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	popup.visible = true
	_place_center(popup, 680)
	return list

func _close_popup() -> void:
	if popup:
		popup.visible = false

func _show_traps() -> void:
	var p: Dictionary = game.current()
	var list := _open_popup("Мои ловушки")
	if p.hand.is_empty():
		list.add_child(Style.label("Карт нет. Ищи их в сундуках и тайниках!", 22))
	var cols := {"Атака": Color("ff8a7a"), "Передвижение": Color("8ad0ff"), "Особая": Color("e0a0ff"), "Редкая": Color("ffd76a")}
	for i in p.hand.size():
		var card: Dictionary = DB.traps[p.hand[i]]
		var price := DB.trap_price(p.hand[i])
		var b := Style.button("%s  [%s]\n%s   •   цена: %d шага" % [card["name"], card["type"], card["text"], price], 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", cols.get(card["type"], Style.PARCH))
		b.disabled = game.steps_left < price or not game.rolled
		b.pressed.connect(func():
			_close_popup()
			trap_card_chosen.emit(i))
		list.add_child(b)
	if not game.rolled:
		list.add_child(Style.label("Сначала брось кубик — ловушки стоят шагов.", 19, Style.GOLD))

func _show_bag() -> void:
	var p: Dictionary = game.current()
	var list := _open_popup("Сумка")
	if p.items.is_empty():
		list.add_child(Style.label("Пусто. Загляни в сундуки!", 22))
	for i in p.items.size():
		var it: Dictionary = DB.items[p.items[i]]
		var b := Style.button("%s — %s" % [it["name"], it["text"]], 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not it["use"]
		b.pressed.connect(func():
			_close_popup()
			item_used.emit(i))
		list.add_child(b)

func _confirm_menu() -> void:
	var list := _open_popup("Выйти в меню?")
	list.add_child(Style.label("Партия не сохранится.", 22))
	var b := Style.button("Да, в меню", 24)
	b.pressed.connect(func(): menu_requested.emit())
	list.add_child(b)

func show_victory(p: Dictionary) -> void:
	set_phase("over")
	var ov := ColorRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.color = Color(0, 0, 0, 0.0)
	root.add_child(ov)
	var tw := create_tween()
	tw.tween_property(ov, "color:a", 0.55, 1.0)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)
	var t := Style.outlined(Style.label("Печать снята!", 90, Style.GOLD, Style.font_title), 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var n := Style.outlined(Style.label("Победитель: %s" % p.name, 46, p.color.lightened(0.3), Style.font_title), 12)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var s := Style.outlined(Style.label("В следующей партии с победителем пойдёт питомец — огненный лисёнок Искорка (+1 к обзору).", 24, Style.PARCH), 8)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.custom_minimum_size.x = 800
	v.add_child(s)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var b1 := Style.button("Ещё партия", 28, 240)
	b1.pressed.connect(func(): restart_requested.emit())
	h.add_child(b1)
	var b2 := Style.button("В меню", 28, 200)
	b2.pressed.connect(func(): menu_requested.emit())
	h.add_child(b2)
	var conf := CPUParticles2D.new()
	conf.position = Vector2(root.get_viewport_rect().size.x * 0.5, -20)
	conf.amount = 160
	conf.lifetime = 4.0
	conf.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	conf.emission_rect_extents = Vector2(700, 10)
	conf.direction = Vector2(0, 1)
	conf.spread = 30
	conf.gravity = Vector2(0, 120)
	conf.initial_velocity_min = 60
	conf.initial_velocity_max = 180
	conf.scale_amount_min = 4
	conf.scale_amount_max = 9
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("ffd76a"), Color("7fe3ff"), Color("ff8fb8"), Color("6fd07a")])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	conf.color_initial_ramp = g
	ov.add_child(conf)
