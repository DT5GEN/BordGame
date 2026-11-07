extends Node
## Шрифты, тема интерфейса и маленькие помощники для создания UI из кода.

const GOLD := Color("e8c36a")
const PARCH := Color("f3e3bf")
const INK := Color("3b2a1a")
const WOOD := Color(0.14, 0.09, 0.06, 0.9)
const WOOD_LIGHT := Color("6b4a2c")
const GLASS := Color(0.08, 0.055, 0.035, 0.62)
const GLASS_DARK := Color(0.08, 0.055, 0.035, 0.84)
const RED := Color("e05a4f")
const GREEN := Color("6fd07a")
const TEAL := Color("7fe3ff")

var font_ui: Font
var font_bold: Font
var font_title: Font
var font_paper: Font
var font_script: Font
var theme: Theme

func _ready() -> void:
	var nunito: FontFile = load("res://fonts/Nunito.ttf")
	var ts := TextServerManager.get_primary_interface()
	var regular := FontVariation.new()
	regular.base_font = nunito
	regular.variation_opentype = {ts.name_to_tag("wght"): 600}
	font_ui = regular
	var bold := FontVariation.new()
	bold.base_font = nunito
	bold.variation_opentype = {ts.name_to_tag("wght"): 850}
	font_bold = bold
	font_title = load("res://fonts/Philosopher-Bold.ttf")
	font_paper = load("res://fonts/PTSerif-Regular.ttf")
	font_script = load("res://fonts/MarckScript-Regular.ttf")
	theme = _make_theme()
	get_tree().root.theme = theme

func sb(bg: Color, border: Color = GOLD, bw: int = 2, radius: int = 14, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.anti_aliasing = true
	return s

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_ui
	t.default_font_size = 22
	# Кнопки
	var n := sb(Color("5a3c22"), Color(GOLD, 0.8), 2, 12, 10)
	var hv := sb(Color("75502e"), GOLD, 2, 12, 10)
	var pr := sb(Color("3e2915"), GOLD, 2, 12, 10)
	var ds := sb(Color(0.25, 0.22, 0.2, 0.8), Color(0.5, 0.45, 0.4, 0.6), 2, 12, 10)
	var fc := sb(Color("75502e"), Color.WHITE, 2, 12, 10)
	t.set_stylebox("normal", "Button", n)
	t.set_stylebox("hover", "Button", hv)
	t.set_stylebox("pressed", "Button", pr)
	t.set_stylebox("disabled", "Button", ds)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PARCH)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.7, 0.66, 0.6, 0.6))
	t.set_font("font", "Button", font_bold)
	# Панели
	t.set_stylebox("panel", "PanelContainer", sb(GLASS))
	t.set_stylebox("panel", "Panel", sb(WOOD))
	# Поля ввода
	var le := sb(Color(0.08, 0.05, 0.03, 0.9), Color(GOLD, 0.5), 2, 10, 8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", sb(Color(0.1, 0.06, 0.04, 0.95), GOLD, 2, 10, 8))
	t.set_color("font_color", "LineEdit", PARCH)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("font_color", "Label", PARCH)
	t.set_font("font", "Label", font_ui)
	# Полоса здоровья
	t.set_stylebox("background", "ProgressBar", sb(Color(0.1, 0.05, 0.04, 0.9), Color(GOLD, 0.5), 2, 8, 0))
	t.set_stylebox("fill", "ProgressBar", sb(RED, Color(1, 0.7, 0.6, 0.6), 1, 8, 0))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	# Прокрутка
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# Чекбокс
	t.set_color("font_color", "CheckBox", PARCH)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", GOLD)
	return t

func label(text: String, size: int = 22, color: Color = PARCH, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	return l

func outlined(l: Label, outline: int = 6, col: Color = Color(0, 0, 0, 0.75)) -> Label:
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", col)
	return l

func button(text: String, size: int = 22, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.focus_mode = Control.FOCUS_NONE
	return b
