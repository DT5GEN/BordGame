extends CanvasLayer
## Свиток с правилами при свете свечи. Листается, открывается кнопкой «?».

var root: Control
var paper: Control
var paper_rect: ColorRect
var title: Label
var body: RichTextLabel
var page_lbl: Label
var flame: Control
var glow: TextureRect
var mat: ShaderMaterial
var page := 0
var _t := 0.0
var pages: Array = []

func _ready() -> void:
	layer = 20
	visible = false
	_make_pages()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.0, 0.82)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	root.add_child(dim)
	# Тёплый свет свечи
	glow = TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.65, 0.25, 0.55), Color(1.0, 0.5, 0.15, 0.0)])
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	glow.texture = gt
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(glow)
	paper = Control.new()
	paper.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(paper)
	paper_rect = ColorRect.new()
	paper_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/parchment.gdshader")
	paper_rect.material = mat
	paper_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(paper_rect)
	# Деревянные валики свитка
	for top in [true, false]:
		var rod := Panel.new()
		rod.name = "RodTop" if top else "RodBottom"
		rod.add_theme_stylebox_override("panel", Style.sb(Color("5a3518"), Color("2e1a0a"), 2, 10, 0))
		rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(rod)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_bottom", 34)
	paper.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)
	title = Style.label("", 44, Color("4a2a12"), Style.font_title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = false
	body.scroll_active = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", Style.font_paper)
	body.add_theme_font_override("bold_font", Style.font_title)
	body.add_theme_font_override("italics_font", Style.font_script)
	body.add_theme_font_size_override("normal_font_size", 22)
	body.add_theme_font_size_override("bold_font_size", 23)
	body.add_theme_font_size_override("italics_font_size", 27)
	body.add_theme_color_override("default_color", Style.INK)
	body.add_theme_constant_override("table_h_separation", 18)
	body.add_theme_constant_override("table_v_separation", 4)
	v.add_child(body)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 24)
	v.add_child(nav)
	var bp := _seal_button("◀")
	bp.pressed.connect(func(): turn(-1))
	nav.add_child(bp)
	page_lbl = Style.label("", 22, Color("5a3a1a"), Style.font_title)
	nav.add_child(page_lbl)
	var bn := _seal_button("▶")
	bn.pressed.connect(func(): turn(1))
	nav.add_child(bn)
	var close_b := _seal_button("✕")
	close_b.pressed.connect(close)
	nav.add_child(close_b)
	# Свеча
	flame = Control.new()
	flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flame.draw.connect(_draw_candle)
	root.add_child(flame)
	root.resized.connect(_layout)
	_layout()
	_show_page()

func _seal_button(txt: String) -> Button:
	var b := Style.button(txt, 24, 60)
	b.add_theme_stylebox_override("normal", Style.sb(Color("8e1e1e"), Color("5a0e0e"), 3, 30, 8))
	b.add_theme_stylebox_override("hover", Style.sb(Color("b02a2a"), Color("5a0e0e"), 3, 30, 8))
	b.add_theme_stylebox_override("pressed", Style.sb(Color("6e1414"), Color("5a0e0e"), 3, 30, 8))
	b.add_theme_color_override("font_color", Color("ffe2b0"))
	return b

func _layout() -> void:
	var vs := root.get_viewport_rect().size
	var w := minf(vs.x * 0.72, 900.0)
	var h := vs.y * 0.86
	paper.size = Vector2(w, h)
	paper.position = Vector2((vs.x - w) * 0.5 + 40, (vs.y - h) * 0.5)
	paper.pivot_offset = paper.size * 0.5
	var rt: Panel = paper.get_node("RodTop")
	var rb: Panel = paper.get_node("RodBottom")
	rt.position = Vector2(-26, -14)
	rt.size = Vector2(w + 52, 26)
	rb.position = Vector2(-26, h - 12)
	rb.size = Vector2(w + 52, 26)
	flame.position = Vector2(paper.position.x - 150, vs.y * 0.5 + 40)
	flame.size = Vector2(120, 300)
	glow.size = Vector2(900, 900)
	glow.position = flame.position + Vector2(60, 40) - glow.size * 0.5

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var f := 1.0 + sin(_t * 9.0) * 0.03 + sin(_t * 23.0) * 0.02 + sin(_t * 3.1) * 0.02
	mat.set_shader_parameter("light", f)
	glow.modulate.a = 0.85 + sin(_t * 11.0) * 0.08 + sin(_t * 4.3) * 0.05
	flame.queue_redraw()

func _draw_candle() -> void:
	var c := Vector2(60, 60)
	# огонь
	var k := 1.0 + sin(_t * 14.0) * 0.08 + sin(_t * 31.0) * 0.05
	var sway := sin(_t * 5.0) * 2.5
	var pts := PackedVector2Array()
	for i in 32:
		var a := float(i) / 32.0 * TAU
		var cy := cos(a)
		var x := 26.0 * sin(a) * sin(a * 0.5)
		var y := -cy * (40.0 * k if cy > 0.0 else 12.0)
		pts.append(c + Vector2(x + sway * maxf(0.0, cy), y))
	flame.draw_circle(c + Vector2(0, -8), 46.0 * k, Color(1.0, 0.6, 0.2, 0.18))
	flame.draw_colored_polygon(pts, Color(1.0, 0.62, 0.15))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.55 + Vector2(0, 4))
	flame.draw_colored_polygon(inner, Color(1.0, 0.95, 0.6))
	# фитиль и свеча
	flame.draw_line(c + Vector2(0, 6), c + Vector2(0, 16), Color(0.15, 0.1, 0.05), 3.0)
	flame.draw_rect(Rect2(c.x - 24, c.y + 16, 48, 190), Color("efe2c4"))
	flame.draw_rect(Rect2(c.x - 24, c.y + 16, 14, 190), Color(1, 1, 1, 0.25))
	flame.draw_rect(Rect2(c.x + 12, c.y + 16, 12, 190), Color(0, 0, 0, 0.12))
	flame.draw_circle(Vector2(c.x - 10, c.y + 30), 7.0, Color("f6ecd4"))
	flame.draw_rect(Rect2(c.x - 18, c.y + 26, 10, 26), Color("f6ecd4"))
	# подсвечник
	flame.draw_rect(Rect2(c.x - 50, c.y + 200, 100, 16), Color("8a6a2a"))
	flame.draw_rect(Rect2(c.x - 36, c.y + 192, 72, 10), Color("b08a3a"))

func open() -> void:
	visible = true
	page = 0
	_show_page()
	paper.scale = Vector2(1, 0.05)
	var tw := create_tween()
	tw.tween_property(paper, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(paper, "scale", Vector2(1, 0.05), 0.25)
	tw.tween_callback(func(): visible = false)

func turn(d: int) -> void:
	var np := clampi(page + d, 0, pages.size() - 1)
	if np == page:
		return
	page = np
	var tw := create_tween()
	tw.tween_property(paper, "scale:x", 0.02, 0.15)
	tw.tween_callback(_show_page)
	tw.tween_property(paper, "scale:x", 1.0, 0.18)

func _show_page() -> void:
	if title == null:
		return
	title.text = pages[page][0]
	body.text = pages[page][1]
	body.scroll_to_line(0)
	page_lbl.text = "%d / %d" % [page + 1, pages.size()]

func _make_pages() -> void:
	var dice_rows := ""
	for d in DB.dice_order:
		dice_rows += "[cell][b]%s[/b][/cell][cell]%s шагов[/cell][cell][i]%s[/i][/cell]" % [d, DB.die_range_text(d), DB.dice[d]["label"]]
	pages = [
		["Свиток первый: Цель",
		"[i]Давным-давно эльфы-хранители спрятали в горе Сердце Долины и запечатали ворота. Ключ — три кристалла — они разбили на осколки и развеяли по долине.[/i]\n\n" +
		"[b]Твоя задача:[/b] найти [b]3 осколка[/b] и первым дойти до [b]ворот в горе[/b] на самом юге долины.\n\n" +
		"Осколков в долине [b]больше, чем игроков[/b], но на всех всё равно не хватит. Кто-то найдёт один, кто-то два... Придётся искать дальше, хитрить ловушками или отбирать в схватке.\n\n" +
		"Осколок можно найти:\n• просто лежащим на холме;\n• в сундуке;\n• у [b]Каменного стража[/b] — его нужно победить.\n\n" +
		"[b]Торопись![/b] С каждым кругом солнце клонится к закату, а ночью с севера ползёт [b]Тьма[/b]."],
		["Свиток второй: Кубики",
		"Перед ходом выбери кубик и брось его. Все кубики в среднем дают [b]5–6 шагов[/b], но по-разному: маленький — надёжный, большой — рискованный.\n\n" +
		"[table=3]" + dice_rows + "[/table]\n\n" +
		"На [b]D20[/b] выпало 20? Критическая удача и находка!\n\n" +
		"[b]Цена шага:[/b] равнина, берег, мост и тропа — 1, лес и холм — 2. Через реку — только по мостам, скалы не пройти.\n\n" +
		"Шаги можно потратить и на [b]ловушки[/b]."],
		["Свиток третий: Ловушки и соперники",
		"Ловушки прячутся на клетку рядом с героем. Их видит [b]только хозяин[/b].\n\n" +
		"[b]Цена:[/b] Атака и Передвижение — 2 шага, Особая — 3, Редкая — 4.\n\n" +
		"Наступил на чужую ловушку — она срабатывает, и ты узнаёшь, чья она. А хозяин в начале своего хода прочитает: «Твоя ловушка поймала героя!»\n\n" +
		"[b]Соперников не видно[/b], пока они далеко:\n• на равнине — 3 клетки;\n• с холма — 4;\n• в лесу — 2, а спрятавшегося в лесу видно ещё хуже;\n• ночью — на 1 меньше.\n\n" +
		"Столкнулся с соперником — [b]схватка[/b]: оба бросают кубик. Победитель забирает [b]осколок[/b] или карту."],
		["Свиток четвёртый: Долина",
		"[b]Звери[/b] — волки и кабаны живут в лесах. Победишь (бросок не меньше силы зверя) — получишь добычу.\n\n" +
		"[b]Сундуки[/b] — зелья, факелы, сапоги-скороходы, карты ловушек, а иногда осколок.\n\n" +
		"[b]Камни «?»[/b] — встречи и чудеса: странник, тайник, попутный ветер, шёпот духа.\n\n" +
		"[b]Костры[/b] — греют (+3 HP) и становятся точкой возрождения. Лишился сил — очнёшься у костра, но потеряешь осколок.\n\n" +
		"[b]Время[/b] идёт по кругам: утро → день → вечер → ночь. Бывают дождь и ветер.\n\n" +
		"[b]Победитель[/b] в следующей партии берёт с собой питомца."],
		["Свиток пятый: Звери и команды",
		"[b]Приручение.[/b] Подойди к зверю вплотную и нажми на него [b]правой кнопкой[/b] или [b]долгим нажатием[/b].\n" +
		"• [b]Волк[/b]: первый — 2 мяса, каждый следующий — 1. Идёт следом, +2 к урону.\n" +
		"• [b]Медведь[/b]: 1 банка мёда. Охраняет хозяина на 3 клетки и сам бросается на врагов.\n\n" +
		"[b]Командная игра.[/b] Красные против Синих. Свои не дерутся, ловушки своих не срабатывают, туман войны общий. Осколки общие: команде нужно 3 на всех.\n" +
		"Если команды разного размера, меньшая сильнее: больше здоровья и урона, больше шагов."],
		["Свиток шестой: Призыв зверей",
		"[i]Этих зверей придумал автор игры.[/i] Карты призыва даются на старте, попадаются в сундуках и бонусных картах. Нажми «Призывы», выбери зверя и клетку рядом с героем — это стоит шагов.\n" +
		"Звери действуют сами в начале твоего хода и через 5 ходов убегают домой. Врага можно атаковать, наступив на его зверя (хомячка и попугая не поймать).\n\n" + _summons_text()],
		["Свиток седьмой: Способности и бонусы",
		"[b]Способность[/b] выбирается в меню для каждого героя — у каждого своё преимущество:\n" + _abilities_text() +
		"\n[b]Бонусные карты.[/b] На первом ходу перед тобой 5 карт рубашкой вверх. Открой любые 2 — они твои. Остальные перевернутся, и ты увидишь, что было в них."],
	]

func _abilities_text() -> String:
	var s := ""
	for a in DB.ABILITIES:
		s += "• [b]%s[/b] — %s\n" % [a["name"], a["text"]]
	return s

func _summons_text() -> String:
	var s := ""
	for a in DB.summons:
		s += "• [b]%s[/b] (%d HP, %d шаг.) — %s\n" % [a["name"], int(a["hp"]), int(a.get("cost", 4)), a["text"]]
	return s
