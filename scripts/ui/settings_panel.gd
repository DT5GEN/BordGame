extends CanvasLayer
## Окно настроек: громкость музыки и звуков, папка с треками, личные настройки игрока.

signal view_changed(first: bool)

var root: Control
var panel: PanelContainer
var track_lbl: Label
var folder_edit: LineEdit
var count_lbl: Label
var player_box: VBoxContainer
var music_cb: CheckBox
var view_btn: Button
var player_name := ""
var dialog: FileDialog

func _ready() -> void:
	layer = 25
	visible = false
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.sb(Color(0.1, 0.07, 0.05, 0.97), Style.GOLD, 3, 18, 22))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size.x = 640
	panel.add_child(v)
	var h0 := HBoxContainer.new()
	v.add_child(h0)
	var t := Style.label("Настройки", 40, Style.GOLD, Style.font_title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h0.add_child(t)
	var x := Style.button("Закрыть", 20)
	x.pressed.connect(close)
	h0.add_child(x)
	v.add_child(_slider_row("Музыка", Settings.music_vol, func(val):
		Settings.music_vol = val
		Settings.apply_volumes()
		Settings.save()))
	v.add_child(_slider_row("Звуки", Settings.sfx_vol, func(val):
		Settings.sfx_vol = val
		Settings.apply_volumes()
		Settings.play("click", 0.0)
		Settings.save()))
	var th := HBoxContainer.new()
	v.add_child(th)
	th.add_child(Style.label("Сейчас играет:", 20, Color(Style.PARCH, 0.7)))
	track_lbl = Style.label("", 20, Style.TEAL, Style.font_bold)
	track_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_lbl.clip_text = true
	th.add_child(track_lbl)
	var nb := Style.button("Следующий трек", 19)
	nb.pressed.connect(func(): Settings.next_track())
	th.add_child(nb)
	var sh := CheckBox.new()
	sh.text = "Перемешивать треки"
	sh.button_pressed = Settings.shuffle
	sh.add_theme_font_size_override("font_size", 19)
	sh.toggled.connect(func(on):
		Settings.shuffle = on
		Settings.save())
	v.add_child(sh)
	var eco := CheckBox.new()
	eco.text = "Экономия заряда и нагрева (30 кадров в секунду)"
	eco.button_pressed = Settings.eco
	eco.add_theme_font_size_override("font_size", 19)
	eco.toggled.connect(func(on):
		Settings.eco = on
		Settings.apply_video()
		Settings.save())
	v.add_child(eco)
	v.add_child(Style.label("Папка с музыкой (mp3, ogg, wav):", 20, Style.PARCH, Style.font_bold))
	var fh := HBoxContainer.new()
	v.add_child(fh)
	folder_edit = LineEdit.new()
	folder_edit.placeholder_text = "Своя папка с треками (не обязательно)"
	folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_edit.text_submitted.connect(func(tx): _set_folder(tx))
	fh.add_child(folder_edit)
	var bb := Style.button("Обзор…", 19)
	bb.pressed.connect(_browse)
	fh.add_child(bb)
	var ab := Style.button("Применить", 19)
	ab.pressed.connect(func(): _set_folder(folder_edit.text))
	fh.add_child(ab)
	count_lbl = Style.label("", 18, Color(Style.PARCH, 0.7))
	count_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	count_lbl.custom_minimum_size.x = 620
	v.add_child(count_lbl)
	player_box = VBoxContainer.new()
	v.add_child(player_box)
	player_box.add_child(HSeparator.new())
	var pl := Style.label("", 24, Style.GOLD, Style.font_title)
	pl.name = "PlayerTitle"
	player_box.add_child(pl)
	music_cb = CheckBox.new()
	music_cb.text = "Музыка в мои ходы"
	music_cb.add_theme_font_size_override("font_size", 20)
	music_cb.toggled.connect(func(on):
		if player_name != "":
			Settings.set_pref(player_name, "music", on)
			Settings.set_music_enabled(on))
	player_box.add_child(music_cb)
	view_btn = Style.button("", 20)
	view_btn.pressed.connect(func():
		var first: bool = Settings.pref(player_name)["view"] != "first"
		Settings.set_pref(player_name, "view", "first" if first else "third")
		_update_player()
		view_changed.emit(first))
	player_box.add_child(view_btn)
	Settings.track_changed.connect(func(_n): _update_track())
	dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "Папка с музыкой"
	dialog.dir_selected.connect(func(d):
		folder_edit.text = d
		_set_folder(d))
	add_child(dialog)

func _slider_row(title: String, val: float, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := Style.label(title, 22, Style.PARCH, Style.font_bold)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(380, 36)
	s.add_theme_stylebox_override("slider", Style.sb(Color(0.25, 0.18, 0.1), Color(Style.GOLD, 0.6), 1, 6, 4))
	s.add_theme_stylebox_override("grabber_area", Style.sb(Color(Style.GOLD, 0.8), Style.GOLD, 1, 6, 4))
	s.add_theme_stylebox_override("grabber_area_highlight", Style.sb(Style.GOLD, Style.GOLD, 1, 6, 4))
	h.add_child(s)
	var pct := Style.label("%d%%" % int(val * 100), 20, Style.GOLD, Style.font_bold)
	pct.custom_minimum_size.x = 60
	h.add_child(pct)
	s.value_changed.connect(func(v):
		pct.text = "%d%%" % int(v * 100)
		cb.call(v))
	return h

func _browse() -> void:
	dialog.popup_centered(Vector2i(800, 500))

func _set_folder(path: String) -> void:
	Settings.music_folder = path.strip_edges()
	Settings.save()
	Settings.rebuild_playlist()
	Settings.next_track()
	_update_track()

func _update_track() -> void:
	track_lbl.text = Settings.current_track if Settings.current_track != "" else "—"
	var n := Settings.playlist.size()
	if n == 0:
		count_lbl.text = "Треков пока нет. Положите файлы в папку music внутри игры или укажите свою папку."
	else:
		count_lbl.text = "Найдено треков: %d" % n

func _update_player() -> void:
	player_box.visible = player_name != ""
	if player_name == "":
		return
	var pr: Dictionary = Settings.pref(player_name)
	(player_box.get_node("PlayerTitle") as Label).text = "Личные настройки: %s" % player_name
	music_cb.set_pressed_no_signal(pr["music"])
	view_btn.text = "Вид: " + ("от первого лица" if pr["view"] == "first" else "от третьего лица") + " (сменить)"

func open(pname: String = "") -> void:
	player_name = pname
	folder_edit.text = Settings.music_folder
	_update_track()
	_update_player()
	visible = true

func close() -> void:
	visible = false
