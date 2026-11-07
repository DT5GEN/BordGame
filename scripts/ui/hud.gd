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
signal settings_requested
signal view_toggle_requested
signal summon_chosen(idx: int)
signal reroll_requested
signal _alert_closed
signal battle_event(kind: String)

var game
var phase := "wait"
var fast := false
var selected_die := "D6"

var root: Control
var hero_panel: PanelContainer
var name_lbl: Label
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
var modal: ColorRect
var alert_closable := false
var banner: VBoxContainer
var view_btn: Button
var confirm_bar: PanelContainer
var current_qte = null
var sub_lbl: Label
var summon_btn: Button
var reroll_btn: Button
var ability_lbl: Label

func _ready() -> void:
	layer = 5
	fast = DB.get_meta("fast", false)
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
	modal = ColorRect.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	modal.gui_input.connect(_on_modal_input)
	root.add_child(modal)
	alert_panel = PanelContainer.new()
	alert_panel.visible = false
	root.add_child(alert_panel)

# ------------------------------------------------------------ построение
func _build_hero_panel() -> void:
	hero_panel = PanelContainer.new()
	hero_panel.position = Vector2(10, 10)
	hero_panel.add_theme_stylebox_override("panel", Style.sb(Style.GLASS, Color(Style.GOLD, 0.45), 2, 12, 8))
	root.add_child(hero_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	hero_panel.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	dot = Panel.new()
	dot.custom_minimum_size = Vector2(16, 16)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	name_lbl = Style.label("", 22, Style.PARCH, Style.font_title)
	h.add_child(name_lbl)
	hp_bar = ProgressBar.new()
	hp_bar.max_value = 20
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(130, 14)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hp_bar)
	hp_lbl = Style.label("20/20", 17, Style.PARCH, Style.font_bold)
	h.add_child(hp_lbl)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	v.add_child(h2)
	shard_lbl = Style.label("", 18, Style.TEAL, Style.font_bold)
	h2.add_child(shard_lbl)
	info_lbl = Style.label("", 15, Color(Style.PARCH, 0.85))
	info_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h2.add_child(info_lbl)
	ability_lbl = Style.label("", 14, Color(Style.TEAL, 0.9))
	v.add_child(ability_lbl)
	status_lbl = Style.label("", 15, Color("ffb070"), Style.font_bold)
	v.add_child(status_lbl)

func _build_top() -> void:
	var tp := PanelContainer.new()
	tp.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tp.position = Vector2(-180, 10)
	tp.custom_minimum_size = Vector2(360, 0)
	tp.add_theme_stylebox_override("panel", Style.sb(Style.GLASS, Color(Style.GOLD, 0.45), 2, 18, 6))
	root.add_child(tp)
	time_lbl = Style.label("", 18, Style.PARCH, Style.font_bold)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tp.add_child(time_lbl)
	var rcol := VBoxContainer.new()
	rcol.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rcol.position = Vector2(-372, 12)
	rcol.custom_minimum_size = Vector2(360, 0)
	root.add_child(rcol)
	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	rcol.add_child(right)
	var right2 := HBoxContainer.new()
	right2.alignment = BoxContainer.ALIGNMENT_END
	rcol.add_child(right2)
	view_btn = Style.glass_button(Style.button("Вид: 3-е лицо", 17))
	view_btn.pressed.connect(func(): view_toggle_requested.emit())
	right2.add_child(view_btn)
	var fb := Style.glass_button(Style.button("К герою", 17))
	fb.pressed.connect(func(): focus_requested.emit())
	right2.add_child(fb)
	var sbtn := Style.glass_button(Style.button("Настройки", 18))
	sbtn.pressed.connect(func(): settings_requested.emit())
	right.add_child(sbtn)
	var hb := Style.glass_button(Style.button("?", 26, 50), Style.TEAL)
	hb.add_theme_font_override("font", Style.font_title)
	hb.add_theme_color_override("font_color", Style.TEAL)
	hb.add_theme_color_override("font_hover_color", Color.WHITE)
	hb.tooltip_text = "Свиток с правилами"
	hb.pressed.connect(func(): help_requested.emit())
	right.add_child(hb)
	var mb := Style.glass_button(Style.button("Меню", 18))
	mb.pressed.connect(_confirm_menu)
	right.add_child(mb)

func _build_bottom() -> void:
	bottom = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", Style.sb(Style.GLASS, Color(Style.GOLD, 0.45), 2, 14, 8))
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
	# кубик партии выбран в меню — общий для всех до конца игры
	var gd: String = game.game_die if game else "D6"
	selected_die = gd
	var dl := Style.label("Кубик партии: %s  (%s шагов)" % [gd, DB.die_range_text(gd)], 22, Style.GOLD, Style.font_bold)
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll_box.add_child(dl)
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
	summon_btn = Style.button("Призывы", 22)
	summon_btn.pressed.connect(_show_summons)
	act_box.add_child(summon_btn)
	bag_btn = Style.button("Сумка", 22)
	bag_btn.pressed.connect(_show_bag)
	act_box.add_child(bag_btn)
	reroll_btn = Style.button("Перебросить", 20)
	reroll_btn.tooltip_text = "Везунчик: раз за ход можно перебросить кубик, пока не сделал шаг"
	reroll_btn.add_theme_stylebox_override("normal", Style.sb(Color("2f4f6a"), Style.TEAL, 2, 12, 10))
	reroll_btn.pressed.connect(func(): reroll_requested.emit())
	act_box.add_child(reroll_btn)
	var eb := Style.button("Закончить ход", 24)
	eb.add_theme_stylebox_override("normal", Style.sb(Color("2f5a3a"), Style.GOLD, 2, 12, 10))
	eb.add_theme_stylebox_override("hover", Style.sb(Color("3d7049"), Color.WHITE, 2, 12, 10))
	eb.pressed.connect(func(): end_turn_requested.emit())
	act_box.add_child(eb)
	trap_box = HBoxContainer.new()
	trap_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(trap_box)
	trap_box.add_child(Style.label("Выбери подсвеченную клетку рядом с героем", 22, Color("e0a0ff"), Style.font_bold))
	var cb := Style.button("Отмена", 22)
	cb.pressed.connect(func(): cancel_mode.emit())
	trap_box.add_child(cb)

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
	_close_popup()
	refresh()

func refresh() -> void:
	if game == null or game.players.is_empty():
		return
	var p: Dictionary = game.current()
	name_lbl.text = p.name
	dot.add_theme_stylebox_override("panel", Style.sb(p.color, Color.WHITE, 2, 8, 0))
	hp_bar.max_value = p.max_hp
	hp_bar.value = p.hp
	hp_lbl.text = "%d/%d" % [p.hp, p.max_hp]
	var ts: int = game.team_shards(p)
	var gems := ""
	for i in 3:
		gems += "◆ " if ts > i else "◇ "
	if ts > 3:
		gems += "+%d" % (ts - 3)
	shard_lbl.text = ("%s: " % game.team_name(p.team) if game.team_mode else "") + gems.strip_edges()
	if game.team_mode:
		shard_lbl.add_theme_color_override("font_color", DB.TEAM_COLORS[p.team].lightened(0.35))
	var rows: int = game.map.shrine.y - p.pos.y
	var extra := ""
	if p.wolves > 0:
		extra += " • Волки %d" % p.wolves
	if p.bear:
		extra += " • Медведь"
	info_lbl.text = "Ловушки %d • Сумка %d • До горы %d%s" % [p.hand.size(), p.items.size(), rows, extra]
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
	view_btn.text = "Вид: 1-е лицо" if game.view_first else "Вид: 3-е лицо"
	trap_btn.text = "Ловушки (%d)" % p.hand.size()
	bag_btn.text = "Сумка (%d)" % p.items.size()
	summon_btn.text = "Призывы (%d)" % p.summons.size()
	reroll_btn.visible = game.can_reroll()
	for a in DB.ABILITIES:
		if a["id"] == p.ability:
			ability_lbl.text = "Способность: " + a["name"]

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
	if title.contains("ночь"):
		Settings.play("night", 0.0)
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
	Settings.play("dice", 0.0)
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

func _place_center(pc: Control, w: float, bottom_px: float = -1.0) -> void:
	pc.custom_minimum_size = Vector2(w, 0)
	pc.size = Vector2(w, 0)
	await get_tree().process_frame
	pc.reset_size()
	await get_tree().process_frame
	var vs := root.get_viewport_rect().size
	if pc.size.y > vs.y - 20:
		pc.size.y = vs.y - 20
	if bottom_px >= 0.0:
		pc.position = Vector2((vs.x - pc.size.x) * 0.5, vs.y - pc.size.y - bottom_px)
	else:
		pc.position = (vs - pc.size) * 0.5

func _wrap_label(text: String, size: int, col: Color, w: float, font: Font = null) -> Label:
	var l := Style.label(text, size, col, font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l

func _show_modal(dim: float) -> void:
	modal.color = Color(0, 0, 0, dim)
	modal.visible = true
	modal.move_to_front()
	alert_panel.move_to_front()

func _hide_modal() -> void:
	modal.visible = false
	alert_closable = false

func _on_modal_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and alert_closable:
		_alert_closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if current_qte != null and is_instance_valid(current_qte) and (e.is_action_pressed("ui_accept") or (e is InputEventKey and e.pressed and e.keycode == KEY_SPACE)):
		current_qte.press()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_cancel"):
		if popup.visible:
			_close_popup()
			get_viewport().set_input_as_handled()
		elif alert_panel.visible and alert_closable:
			_alert_closed.emit()
			get_viewport().set_input_as_handled()

## Окно-сообщение. Закрывается кнопкой, тапом мимо окна или Esc.
func alert(title: String, text: String, col: Color = Style.GOLD) -> void:
	if fast:
		print("ALERT: ", title, " | ", text.replace("\n", " / "))
		await get_tree().process_frame
		return
	for c in alert_panel.get_children():
		c.free()
	alert_panel.add_theme_stylebox_override("panel", Style.sb(Style.GLASS_DARK, col, 2, 16, 16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	alert_panel.add_child(v)
	v.add_child(_wrap_label(title, 30, col.lightened(0.2), 480, Style.font_title))
	v.add_child(_wrap_label(text, 20, Style.PARCH, 480))
	var b := Style.button("Понятно", 22, 180)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): _alert_closed.emit())
	v.add_child(b)
	alert_panel.modulate.a = 0.0
	alert_panel.visible = true
	_show_modal(0.35)
	await _place_center(alert_panel, 520)
	alert_closable = true
	var tw := create_tween()
	tw.tween_property(alert_panel, "modulate:a", 1.0, 0.2)
	await _alert_closed
	alert_panel.visible = false
	_hide_modal()

# ------------------------------------------------------------ интерактивный бой
const BW := 520.0
class QTE extends Control:
	## Кольцо пульсирует: сходится и расходится. Нажми, когда оно совпадёт с щитом (станет зелёным).
	signal done(ok: bool)
	const R0 := 38.0
	var tol := 11.0
	const AMP := 52.0
	const PERIOD := 0.8
	const PREP := 1.4
	const LIMIT := 4.0
	var t := 0.0
	var started := false
	var finished := false
	var ok := false

	func _ready() -> void:
		custom_minimum_size = Vector2(190, 190)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func ring_r() -> float:
		if not started:
			return R0 + AMP
		return R0 + AMP * cos(t * TAU / PERIOD)

	func _process(delta: float) -> void:
		if finished:
			return
		t += delta
		queue_redraw()
		if not started:
			if t >= PREP:
				started = true
				t = 0.0
			return
		if t >= LIMIT:
			_finish(false)

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			press()
			accept_event()

	func press() -> void:
		if finished or not started:
			return
		_finish(absf(ring_r() - R0) <= tol)

	func _finish(v: bool) -> void:
		finished = true
		ok = v
		queue_redraw()
		done.emit(v)

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, R0 + tol, Color(0.4, 0.9, 0.5, 0.12))
		draw_arc(c, R0, 0, TAU, 64, Color("e8c36a"), 4.0, true)
		draw_circle(c, R0 - 9, Color("8a5a2b"))
		draw_arc(c, R0 - 9, 0, TAU, 48, Color("5a3a1a"), 4.0, true)
		draw_line(c + Vector2(0, -(R0 - 11)), c + Vector2(0, R0 - 11), Color("6b4520"), 3.0)
		draw_circle(c, 6, Color("c9c9c9"))
		if not started:
			var n := 3 - int(t / PREP * 3.0)
			draw_string(Style.font_title, c + Vector2(-60, -R0 - 30), "Готовься… %d" % maxi(1, n), HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color("e8c36a"))
			draw_arc(c, ring_r(), 0, TAU, 64, Color(1, 0.4, 0.35, 0.5), 4.0, true)
		elif not finished:
			var rr := ring_r()
			var near := absf(rr - R0) <= tol
			draw_arc(c, rr, 0, TAU, 64, Color("6fd07a") if near else Color("ff6a5a"), 6.0, true)
		else:
			draw_arc(c, R0 + 8, 0, TAU, 64, Color("6fd07a") if ok else Color("ff6a5a"), 10.0, true)

## Бой в 2 шага: защита (кольцо) → свой бросок кубика. Возвращает {blocked, bonus, roll, total}.
func battle(hero_name: String, foe_name: String, foe_info: String, need_text: String, pvp: bool, hero_col: Color = Style.GOLD, agile := false) -> Dictionary:
	if fast:
		var bl := randf() < 0.5
		var r := randi_range(1, 6)
		var bn := (3 if agile else 2) if bl else -1
		await get_tree().process_frame
		return {"blocked": bl, "bonus": bn, "roll": r, "total": maxi(1, r + bn)}
	for c in alert_panel.get_children():
		c.free()
	alert_panel.add_theme_stylebox_override("panel", Style.sb(Style.GLASS, Color(Style.RED, 0.7), 2, 16, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	alert_panel.add_child(v)
	var th := HBoxContainer.new()
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_theme_constant_override("separation", 12)
	v.add_child(th)
	th.add_child(Style.outlined(Style.label(hero_name, 26, hero_col.lightened(0.25), Style.font_title), 4))
	th.add_child(Style.label("против", 18, Color(Style.PARCH, 0.6), Style.font_bold))
	th.add_child(Style.outlined(Style.label(foe_name, 26, Color("ff7a6a"), Style.font_title), 4))
	if foe_info != "":
		v.add_child(_wrap_label(foe_info, 16, Color(Style.PARCH, 0.75), BW))
	var hint := _wrap_label("%s атакует! Жми на ЩИТ (или пробел), когда кольцо станет ЗЕЛЁНЫМ" % foe_name, 19, Style.GOLD, BW, Style.font_bold)
	v.add_child(hint)
	var center := CenterContainer.new()
	v.add_child(center)
	var qte := QTE.new()
	if agile:
		qte.tol = 17.0
	center.add_child(qte)
	current_qte = qte
	bottom.visible = false
	alert_panel.visible = true
	alert_panel.modulate.a = 1.0
	_show_modal(0.0)
	await _place_center(alert_panel, BW + 30, 10)
	await get_tree().create_timer(qte.PREP).timeout
	battle_event.emit("enemy_attack")
	var blocked: bool = await qte.done
	current_qte = null
	battle_event.emit("block" if blocked else "hit")
	var bonus := (3 if agile else 2) if blocked else -1
	hint.text = ("Блок! Следующий бросок +%d" % bonus if blocked else "Не успел... Следующий бросок −1")
	hint.add_theme_color_override("font_color", Style.GREEN if blocked else Style.RED)
	await get_tree().create_timer(0.9).timeout
	center.queue_free()
	var num := Style.outlined(Style.label("?", 60, Style.GOLD, Style.font_title), 6)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	v.add_child(_wrap_label(need_text, 16, Color(Style.PARCH, 0.85), BW))
	var rb := Style.button("Бросить кубик!", 24, 240)
	rb.add_theme_font_override("font", Style.font_title)
	rb.add_theme_stylebox_override("normal", Style.sb(Color("8a3b1f"), Style.GOLD, 3, 14, 12))
	rb.add_theme_stylebox_override("hover", Style.sb(Color("a84a28"), Color.WHITE, 3, 14, 12))
	rb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pressed := [false]
	rb.pressed.connect(func(): pressed[0] = true)
	v.add_child(rb)
	await _place_center(alert_panel, BW + 30, 10)
	while not pressed[0]:
		await get_tree().process_frame
	rb.disabled = true
	Settings.play("dice", 0.0)
	for i in 12:
		num.text = str(randi_range(1, 6))
		await get_tree().create_timer(0.05 + i * 0.006).timeout
	var roll := randi_range(1, 6)
	var total := maxi(1, roll + bonus)
	num.text = "%d %s %d = %d" % [roll, "+" if bonus >= 0 else "−", absi(bonus), total]
	battle_event.emit("hero_attack")
	rb.queue_free()
	await get_tree().create_timer(0.6).timeout
	return {"blocked": blocked, "bonus": bonus, "roll": roll, "total": total}

## Второй игрок (защитник) сам бросает кубик на том же телефоне.
func extra_roll(who: String, col: Color, bonus: int) -> int:
	if fast:
		await get_tree().process_frame
		return randi_range(1, 6) + bonus
	var v: VBoxContainer = alert_panel.get_child(0)
	v.add_child(_wrap_label("Теперь защищается %s — передай телефон!" % who, 19, col.lightened(0.3), BW, Style.font_bold))
	var num := Style.outlined(Style.label("?", 52, col.lightened(0.3), Style.font_title), 6)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	var rb := Style.button("Бросить кубик (%s)" % who, 22, 260)
	rb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pressed := [false]
	rb.pressed.connect(func(): pressed[0] = true)
	v.add_child(rb)
	await _place_center(alert_panel, BW + 30, 10)
	while not pressed[0]:
		await get_tree().process_frame
	rb.disabled = true
	Settings.play("dice", 0.0)
	for i in 12:
		num.text = str(randi_range(1, 6))
		await get_tree().create_timer(0.05 + i * 0.006).timeout
	var r := randi_range(1, 6)
	num.text = str(r) if bonus == 0 else "%d + %d = %d" % [r, bonus, r + bonus]
	rb.queue_free()
	await get_tree().create_timer(0.5).timeout
	return r + bonus

## Меню выбора действия (например, «Атаковать / Приручить»). Возвращает индекс или −1.
func choice(title: String, opts: Array) -> int:
	for c in alert_panel.get_children():
		c.free()
	alert_panel.add_theme_stylebox_override("panel", Style.sb(Style.GLASS_DARK, Color(Style.GOLD, 0.7), 2, 16, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	alert_panel.add_child(v)
	v.add_child(_wrap_label(title, 28, Style.GOLD, 420, Style.font_title))
	var res := [-2]
	for i in opts.size():
		var b := Style.button(opts[i][0], 20, 420)
		b.disabled = not opts[i][1]
		b.pressed.connect(func(): res[0] = i)
		v.add_child(b)
	var cb := Style.button("Отмена", 18, 160)
	cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cb.pressed.connect(func(): res[0] = -1)
	v.add_child(cb)
	alert_panel.visible = true
	alert_panel.modulate.a = 1.0
	_show_modal(0.25)
	await _place_center(alert_panel, 460)
	var closer := func(): res[0] = -1
	_alert_closed.connect(closer, CONNECT_ONE_SHOT)
	alert_closable = true
	while res[0] == -2:
		await get_tree().process_frame
	if _alert_closed.is_connected(closer):
		_alert_closed.disconnect(closer)
	alert_panel.visible = false
	_hide_modal()
	return res[0]

## Субтитр внизу экрана (для заставки и финала).
func subtitle(text: String, dur: float) -> void:
	if sub_lbl == null:
		sub_lbl = Style.outlined(Style.label("", 30, Style.PARCH, Style.font_title), 10)
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		sub_lbl.custom_minimum_size = Vector2(1000, 0)
		sub_lbl.position = Vector2(-500, -120)
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(sub_lbl)
	sub_lbl.text = text
	sub_lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(sub_lbl, "modulate:a", 1.0, 0.3)
	tw.tween_interval(dur)
	tw.tween_property(sub_lbl, "modulate:a", 0.0, 0.4)

func battle_finish(result: String, win: bool) -> void:
	if fast:
		print("BATTLE: ", result)
		await get_tree().process_frame
		return
	var v: VBoxContainer = alert_panel.get_child(0)
	v.add_child(_wrap_label(result, 20, Style.GREEN if win else Color("ff7a6a"), BW, Style.font_bold))
	var b := Style.button("Дальше", 22, 180)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): _alert_closed.emit())
	v.add_child(b)
	await _place_center(alert_panel, BW + 30, 10)
	alert_closable = true
	await _alert_closed
	alert_panel.visible = false
	_hide_modal()

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
	if game.team_mode:
		t.text = "Команда: " + game.team_name(p.team)
		t.add_theme_color_override("font_color", DB.TEAM_COLORS[p.team].lightened(0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := Style.label("Остальные — не подглядывайте!   •   Карта № %d" % game.map_code, 22, Color(Style.GOLD, 0.8))
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
	popup.add_theme_stylebox_override("panel", Style.sb(Style.GLASS_DARK, Color(Style.GOLD, 0.6), 2, 16, 14))
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
	sc.custom_minimum_size = Vector2(560, 300)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	popup.visible = true
	popup.move_to_front()
	_place_center(popup, 600)
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
		var price: int = game.trap_cost(p.hand[i])
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

func _show_summons() -> void:
	var p: Dictionary = game.current()
	var list := _open_popup("Призывы зверей")
	if p.summons.is_empty():
		list.add_child(Style.label("Карт призыва нет. Ищи их в сундуках и бонусных картах!", 21))
	for i in p.summons.size():
		var sd: Dictionary = DB.summons[p.summons[i]]
		var cost: int = game.summon_cost(p.summons[i])
		var b := Style.button("%s  (%d HP)\n%s   •   цена: %d шаг." % [sd["name"], int(sd["hp"]), sd["text"], cost], 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 540
		b.add_theme_color_override("font_color", Color("9be07a"))
		b.disabled = game.steps_left < cost or not game.rolled or p.now_block_summon
		b.pressed.connect(func():
			_close_popup()
			summon_chosen.emit(i))
		list.add_child(b)
	if not game.rolled:
		list.add_child(Style.label("Сначала брось кубик — призыв стоит шагов.", 19, Style.GOLD))
	elif p.now_block_summon:
		list.add_child(Style.label("«Глушитель»: в этот ход призывать нельзя.", 19, Style.RED))

const KIND_COL := {"trap": Color("c0392b"), "summon": Color("2e8b57"), "item": Color("b8860b")}
const KIND_NAME := {"trap": "Ловушка", "summon": "Призыв", "item": "Предмет"}

## 5 карт рубашкой вверх: открыть 2, остальные потом переворачиваются.
func bonus_pick(who: String, cards: Array) -> Array:
	if fast:
		await get_tree().process_frame
		return [0, 1]
	for c in alert_panel.get_children():
		c.free()
	alert_panel.add_theme_stylebox_override("panel", Style.sb(Style.GLASS_DARK, Style.GOLD, 2, 18, 18))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	alert_panel.add_child(v)
	v.add_child(_wrap_label("%s, бонусные карты!" % who, 32, Style.GOLD, 860, Style.font_title))
	var hint := _wrap_label("Открой любые 2 из 5 — их заберёшь. Остальные покажем потом.", 20, Style.PARCH, 860)
	v.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var chosen: Array = []
	var slots: Array = []
	for i in cards.size():
		var card := Button.new()
		card.custom_minimum_size = Vector2(150, 210)
		card.focus_mode = Control.FOCUS_NONE
		card.add_theme_stylebox_override("normal", Style.sb(Color("3a2414"), Style.GOLD, 3, 14, 8))
		card.add_theme_stylebox_override("hover", Style.sb(Color("553620"), Color.WHITE, 3, 14, 8))
		card.add_theme_stylebox_override("pressed", Style.sb(Color("553620"), Color.WHITE, 3, 14, 8))
		card.add_theme_stylebox_override("disabled", Style.sb(Color("3a2414"), Color(Style.GOLD, 0.5), 3, 14, 8))
		card.text = "?"
		card.add_theme_font_override("font", Style.font_title)
		card.add_theme_font_size_override("font_size", 80)
		card.add_theme_color_override("font_color", Color(Style.GOLD, 0.8))
		card.pivot_offset = card.custom_minimum_size * 0.5
		row.add_child(card)
		slots.append(card)
		card.pressed.connect(func():
			if chosen.size() >= 2 or chosen.has(i):
				return
			chosen.append(i)
			Settings.play("click", 0.0)
			_flip(card, cards[i], false))
	var done := Style.button("Забрать карты", 26, 260)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.visible = false
	var fin := [false]
	done.pressed.connect(func(): fin[0] = true)
	v.add_child(done)
	alert_panel.visible = true
	alert_panel.modulate.a = 1.0
	_show_modal(0.45)
	await _place_center(alert_panel, 900)
	while chosen.size() < 2:
		await get_tree().process_frame
	await get_tree().create_timer(0.9).timeout
	for i in cards.size():
		if not chosen.has(i):
			slots[i].disabled = true
			_flip(slots[i], cards[i], true)
			await get_tree().create_timer(0.15).timeout
	hint.text = "Твои карты — с золотой рамкой. Тусклые — те, что остались неоткрытыми."
	done.visible = true
	await _place_center(alert_panel, 900)
	while not fin[0]:
		await get_tree().process_frame
	alert_panel.visible = false
	_hide_modal()
	return chosen

func _flip(card: Button, c: Dictionary, missed: bool) -> void:
	var tw := create_tween()
	tw.tween_property(card, "scale:x", 0.02, 0.14)
	tw.tween_callback(func():
		card.text = ""
		var col: Color = KIND_COL[c["kind"]]
		card.add_theme_stylebox_override("normal", Style.sb(col.darkened(0.45), Color(Style.GOLD, 0.35) if missed else Style.GOLD, 2 if missed else 4, 14, 8))
		card.add_theme_stylebox_override("disabled", Style.sb(col.darkened(0.6), Color(Style.GOLD, 0.25), 2, 14, 8))
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 8
		vb.offset_right = -8
		vb.offset_top = 8
		vb.offset_bottom = -8
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vb)
		var k := Style.label(KIND_NAME[c["kind"]], 15, col.lightened(0.5), Style.font_bold)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(k)
		var t := Style.label(c["title"], 19, Style.PARCH, Style.font_title)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 130
		vb.add_child(t)
		var d := Style.label(c["text"], 13, Color(Style.PARCH, 0.85))
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 130
		vb.add_child(d)
		if missed:
			card.modulate = Color(1, 1, 1, 0.55))
	tw.tween_property(card, "scale:x", 1.0, 0.16)

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
	_close_popup()
	if confirm_bar and is_instance_valid(confirm_bar):
		confirm_bar.queue_free()
	confirm_bar = PanelContainer.new()
	confirm_bar.add_theme_stylebox_override("panel", Style.sb(Style.GLASS, Color(Style.GOLD, 0.5), 2, 14, 10))
	root.add_child(confirm_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	confirm_bar.add_child(h)
	var stay := Style.button("Остаться", 22, 150)
	stay.add_theme_stylebox_override("normal", Style.sb(Color("9a2f26"), Color(Style.GOLD, 0.7), 2, 12, 10))
	stay.add_theme_stylebox_override("hover", Style.sb(Color("b8392e"), Color.WHITE, 2, 12, 10))
	stay.pressed.connect(func(): confirm_bar.queue_free())
	h.add_child(stay)
	var l := Style.label("Выйти в меню? Партия не сохранится.", 19, Style.PARCH, Style.font_bold)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var go := Style.button("Выйти", 16, 70)
	go.add_theme_stylebox_override("normal", Style.sb(Color("c9b48a"), Color("8a7450"), 1, 10, 6))
	go.add_theme_stylebox_override("hover", Style.sb(Color("e0cda4"), Color.WHITE, 1, 10, 6))
	go.add_theme_color_override("font_color", Color("3b2a1a"))
	go.add_theme_color_override("font_hover_color", Color("1e140b"))
	go.pressed.connect(func(): menu_requested.emit())
	h.add_child(go)
	confirm_bar.reset_size()
	await get_tree().process_frame
	var vs := root.get_viewport_rect().size
	confirm_bar.position = Vector2((vs.x - confirm_bar.size.x) * 0.5, 74)

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
	var wtxt := "Победитель: %s" % p.name
	var wcol: Color = p.color
	if game.team_mode:
		var names: Array = []
		for q in game.players:
			if q.team == p.team:
				names.append(q.name)
		wtxt = "Победила команда «%s»: %s" % [game.team_name(p.team), ", ".join(names)]
		wcol = DB.TEAM_COLORS[p.team]
	var n := Style.outlined(Style.label(wtxt, 40, wcol.lightened(0.3), Style.font_title), 12)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 900
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var s := Style.outlined(Style.label("В следующей партии с победителем пойдёт питомец — огненный лисёнок Искорка (+1 к обзору).\nКод этой карты: %d — введи его в меню, чтобы сыграть её ещё раз." % game.map_code, 24, Style.PARCH), 8)
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
	Settings.play("victory", 0.0)
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
