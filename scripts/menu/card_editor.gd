extends CanvasLayer
## Редактор баланса: автор игры немного подкручивает ловушки и зверей.
## Числа меняются только в пределах, цена ловушки растёт вместе с её силой.

const TYPE_COLORS := {"Атака": Color("ff8a7a"), "Передвижение": Color("8ad0ff"), "Особая": Color("e0a0ff"), "Редкая": Color("ffd76a")}

var root: Control
var list: VBoxContainer
var detail: VBoxContainer
var sel_kind := "trap"   # trap / beast
var sel_trap := 0
var sel_beast := "wolf"

func _ready() -> void:
	layer = 26
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.sb(Style.GLASS_DARK, Style.GOLD, 2, 18, 16))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Style.label("Редактор карт", 36, Style.GOLD, Style.font_title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var ra := Style.button("Вернуть всё как было", 18)
	ra.pressed.connect(func():
		DB.reset_all()
		_rebuild())
	h.add_child(ra)
	var cl := Style.button("Закрыть", 18)
	cl.pressed.connect(func(): visible = false)
	h.add_child(cl)
	var hint := Style.label("Меняй баланс понемногу: числа ходят в разумных пределах, а чем сильнее ловушка — тем больше шагов она стоит.", 16, Color(Style.PARCH, 0.75))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 1100
	v.add_child(hint)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	v.add_child(body)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(380, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", Style.sb(Color(0, 0, 0, 0.3), Color(Style.GOLD, 0.35), 1, 14, 16))
	dp.custom_minimum_size = Vector2(700, 520)
	body.add_child(dp)
	detail = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 10)
	dp.add_child(detail)

func open() -> void:
	visible = true
	_rebuild()

func _rebuild() -> void:
	_build_list()
	_build_detail()

func _build_list() -> void:
	for c in list.get_children():
		c.free()
	list.add_child(Style.label("Ловушки", 22, Style.GOLD, Style.font_title))
	for i in DB.traps.size():
		var c: Dictionary = DB.traps[i]
		var changed: bool = c["name"] != DB.base_traps[i]["name"] or c["fx"] != DB.base_traps[i]["fx"]
		var b := Style.button("%s%s" % ["✎ " if changed else "", c["name"]], 17, 350)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", TYPE_COLORS.get(c["type"], Style.PARCH))
		if sel_kind == "trap" and sel_trap == i:
			b.add_theme_stylebox_override("normal", Style.sb(Color("75502e"), Style.GOLD, 2, 10, 8))
		b.pressed.connect(func():
			sel_kind = "trap"
			sel_trap = i
			_rebuild())
		list.add_child(b)
	list.add_child(Style.label("Звери", 22, Style.GOLD, Style.font_title))
	for kind in DB.beasts:
		var bd: Dictionary = DB.beasts[kind]
		var changed2: bool = bd != DB.base_beasts[kind]
		var b2 := Style.button("%s%s" % ["✎ " if changed2 else "", bd["name"]], 17, 350)
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if sel_kind == "beast" and sel_beast == kind:
			b2.add_theme_stylebox_override("normal", Style.sb(Color("75502e"), Style.GOLD, 2, 10, 8))
		b2.pressed.connect(func():
			sel_kind = "beast"
			sel_beast = kind
			_rebuild())
		list.add_child(b2)

func _row(title: String, value: int, orig: int, lim: Vector2i, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Style.label(title, 20, Style.PARCH, Style.font_bold)
	l.custom_minimum_size.x = 320
	h.add_child(l)
	var m := Style.button("−", 22, 46)
	m.disabled = value <= lim.x
	m.pressed.connect(func(): cb.call(value - 1))
	h.add_child(m)
	var vl := Style.label(str(value), 28, Style.GOLD, Style.font_title)
	vl.custom_minimum_size.x = 40
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(vl)
	var p := Style.button("+", 22, 46)
	p.disabled = value >= lim.y
	p.pressed.connect(func(): cb.call(value + 1))
	h.add_child(p)
	var o := Style.label("было %d  •  можно %d–%d" % [orig, lim.x, lim.y], 16, Color(Style.PARCH, 0.6))
	h.add_child(o)
	return h

func _build_detail() -> void:
	for c in detail.get_children():
		c.free()
	if sel_kind == "trap":
		_trap_detail()
	else:
		_beast_detail()

func _trap_detail() -> void:
	var i := sel_trap
	var c: Dictionary = DB.traps[i]
	var b: Dictionary = DB.base_traps[i]
	var nh := HBoxContainer.new()
	detail.add_child(nh)
	var ne := LineEdit.new()
	ne.text = c["name"]
	ne.max_length = 30
	ne.custom_minimum_size.x = 420
	ne.add_theme_font_size_override("font_size", 24)
	ne.text_changed.connect(func(tx):
		c["name"] = tx if tx.strip_edges() != "" else b["name"]
		DB.save_overrides())
	ne.text_submitted.connect(func(_t): _build_list())
	ne.focus_exited.connect(_build_list)
	nh.add_child(ne)
	var tl := Style.label("  " + c["type"], 20, TYPE_COLORS.get(c["type"], Style.PARCH), Style.font_bold)
	nh.add_child(tl)
	var desc := Style.label("Что делает: " + c["text"], 19, Style.PARCH)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 660
	detail.add_child(desc)
	detail.add_child(HSeparator.new())
	var any := false
	for k in c["fx"]:
		if DB.FX_LIMITS.has(k):
			any = true
			var lim := DB.fx_limits(i, k)
			detail.add_child(_row(DB.FX_LIMITS[k]["name"], int(c["fx"][k]), int(b["fx"][k]), lim, func(nv):
				DB.set_fx(i, k, nv)
				_rebuild()))
		else:
			var fl := Style.label("Особый эффект (не меняется): " + _fixed_name(k), 18, Color("e0a0ff"))
			detail.add_child(fl)
	if not any:
		detail.add_child(Style.label("У этой карты только особый эффект — её числа не настраиваются.", 18, Color(Style.PARCH, 0.7)))
	detail.add_child(HSeparator.new())
	var price := DB.trap_price(i)
	var base_price := int(DB.trap_cost.get(b["type"], 3))
	var pl := Style.label("Цена: %d шаг. (было %d) — считается сама по силе карты" % [price, base_price], 20, Style.TEAL if price == base_price else Style.GOLD, Style.font_bold)
	detail.add_child(pl)
	var ph := HBoxContainer.new()
	detail.add_child(ph)
	ph.add_child(Style.label("Сила карты:", 18, Style.PARCH))
	var bar := ProgressBar.new()
	bar.max_value = 8.0
	bar.value = DB.fx_power(c["fx"])
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(320, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(bar)
	ph.add_child(Style.label("%.1f (было %.1f)" % [DB.fx_power(c["fx"]), DB.fx_power(b["fx"])], 18, Color(Style.PARCH, 0.75)))
	var rb := Style.button("Вернуть эту карту как было", 18)
	rb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rb.pressed.connect(func():
		DB.reset_trap(i)
		_rebuild())
	detail.add_child(rb)

func _beast_detail() -> void:
	var kind := sel_beast
	var bd: Dictionary = DB.beasts[kind]
	var bb: Dictionary = DB.base_beasts[kind]
	detail.add_child(Style.label(bd["name"], 30, Style.GOLD, Style.font_title))
	var info := Style.label("Чтобы победить зверя, нужно набрать в бою его силу или больше. Проиграл — получаешь его урон.", 18, Color(Style.PARCH, 0.8))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 660
	detail.add_child(info)
	detail.add_child(HSeparator.new())
	for k in DB.BEAST_LIMITS:
		var lim := DB.beast_limits(kind, k)
		detail.add_child(_row(DB.BEAST_LIMITS[k]["name"], int(bd[k]), int(bb[k]), lim, func(nv):
			DB.set_beast(kind, k, nv)
			_rebuild()))
	var rb := Style.button("Вернуть этого зверя как было", 18)
	rb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rb.pressed.connect(func():
		DB.reset_beast(kind)
		_rebuild())
	detail.add_child(rb)

func _fixed_name(k: String) -> String:
	match k:
		"skip_move": return "нельзя двигаться следующий ход"
		"skip_turn": return "пропуск хода"
		"steal_card": return "владелец забирает карту"
		"lose_card": return "потеря карты"
		"swap_card": return "замена карты"
		"teleport": return "перенос в случайное место"
		"block_traps": return "нельзя ставить ловушки"
		"block_summon": return "нельзя призывать"
	return k
