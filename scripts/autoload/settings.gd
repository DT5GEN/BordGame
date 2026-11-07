extends Node
## Настройки: громкость, музыка (плейлист из папки), звуки, личные настройки каждого игрока.

signal track_changed(name: String)

const PATH := "user://settings.cfg"
const EXTS := ["ogg", "mp3", "wav"]

var music_vol := 0.6
var sfx_vol := 0.8
var music_folder := ""
var shuffle := true
var eco := false
var prefs := {}          # имя игрока -> {"view": "third"/"first", "music": true}

var music: AudioStreamPlayer
var sfx_players: Array = []
var sfx := {}
var playlist: Array = []  # [{name, path, external}]
var track_idx := -1
var music_enabled := true
var current_track := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load()
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	music.finished.connect(next_track)
	add_child(music)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)
	for n in ["dice", "chest", "shard", "trap", "hit", "block", "magic", "victory", "click", "night"]:
		var path := "res://sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			sfx[n] = load(path)
	apply_volumes()
	apply_video()
	rebuild_playlist()
	next_track()

func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	music_vol = cf.get_value("audio", "music_vol", music_vol)
	sfx_vol = cf.get_value("audio", "sfx_vol", sfx_vol)
	music_folder = cf.get_value("audio", "music_folder", music_folder)
	shuffle = cf.get_value("audio", "shuffle", shuffle)
	eco = cf.get_value("video", "eco", eco)
	prefs = cf.get_value("players", "prefs", {})

func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music_vol", music_vol)
	cf.set_value("audio", "sfx_vol", sfx_vol)
	cf.set_value("audio", "music_folder", music_folder)
	cf.set_value("audio", "shuffle", shuffle)
	cf.set_value("video", "eco", eco)
	cf.set_value("players", "prefs", prefs)
	cf.save(PATH)

func apply_volumes() -> void:
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music_vol, 0.0001)))
	AudioServer.set_bus_mute(mi, music_vol <= 0.001 or not music_enabled)
	AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sfx_vol, 0.0001)))
	AudioServer.set_bus_mute(si, sfx_vol <= 0.001)

func apply_video() -> void:
	Engine.max_fps = 30 if eco else 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

func set_music_enabled(on: bool) -> void:
	music_enabled = on
	apply_volumes()

# ------------------------------------------------------------ плейлист
func rebuild_playlist() -> void:
	playlist.clear()
	_scan_res("res://music")
	if music_folder != "":
		_scan_external(music_folder)
	track_idx = -1

func _scan_res(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	var seen := {}
	for f in d.get_files():
		var name: String = f.trim_suffix(".import").trim_suffix(".remap")
		if seen.has(name) or not (name.get_extension().to_lower() in EXTS):
			continue
		seen[name] = true
		playlist.append({"name": name.get_basename(), "path": dir_path.path_join(name), "external": false})

func _scan_external(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension().to_lower() in EXTS:
			playlist.append({"name": f.get_basename(), "path": dir_path.path_join(f), "external": true})

func _load_stream(t: Dictionary) -> AudioStream:
	var path: String = t["path"]
	if not t["external"] and ResourceLoader.exists(path):
		return load(path)
	# файл ещё не импортирован Godot или лежит в своей папке — читаем напрямую
	var real := path
	if path.begins_with("res://"):
		real = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(real):
		return null
	match real.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(real)
		"mp3":
			var m := AudioStreamMP3.new()
			m.data = FileAccess.get_file_as_bytes(real)
			return m
		"wav":
			return AudioStreamWAV.load_from_file(real)
	return null

func next_track() -> void:
	if playlist.is_empty():
		current_track = ""
		track_changed.emit("")
		return
	if shuffle and playlist.size() > 1:
		var n := track_idx
		while n == track_idx:
			n = randi() % playlist.size()
		track_idx = n
	else:
		track_idx = (track_idx + 1) % playlist.size()
	var t: Dictionary = playlist[track_idx]
	var st := _load_stream(t)
	if st == null:
		current_track = ""
		track_changed.emit("")
		return
	if st is AudioStreamOggVorbis or st is AudioStreamMP3:
		st.set("loop", false)
	music.stream = st
	music.play()
	current_track = t["name"]
	track_changed.emit(current_track)

# ------------------------------------------------------------ звуки
func play(name: String, pitch_jitter := 0.06) -> void:
	if not sfx.has(name):
		return
	for p in sfx_players:
		if not p.playing:
			p.stream = sfx[name]
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return

# ------------------------------------------------------------ личные настройки
func pref(player_name: String) -> Dictionary:
	if not prefs.has(player_name):
		prefs[player_name] = {"view": "third", "music": true}
	return prefs[player_name]

func set_pref(player_name: String, key: String, value) -> void:
	pref(player_name)[key] = value
	save()
