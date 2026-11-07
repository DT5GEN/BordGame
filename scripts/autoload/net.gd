extends Node
## Связь с сервером-комнатой по WebSocket. Игру сервер не считает:
## он только раздаёт всем действия игроков в одном порядке.

signal lobby(data: Dictionary)
signal started(data: Dictionary)
signal act(msg: Dictionary)
signal error(text: String)
signal status(text: String)
signal closed
signal caught_up

const DEFAULT_PORT := 7777
const SESSION_PATH := "user://net_session.json"
const URL_PATH := "user://net_server.json"

var ws: WebSocketPeer = null
var state := "off"          # off / connecting / open
var url := ""
var room := ""
var cid := 0
var token := ""
var host := false
var lobby_data: Dictionary = {}
var start_data: Dictionary = {}
var in_game := false
var _first: Dictionary = {}
var _ping := 0.0
var _retry := 0.0
var _joined := false
var acts_log: Array = []     # все действия партии по порядку: нужны, чтобы следующая карта кампании ничего не пропустила
var caught := false          # сервер уже прислал всю историю
var _log_last := 0

# ------------------------------------------------------------------ адрес сервера
static func normalize(u: String) -> String:
	u = u.strip_edges()
	if u == "":
		return ""
	if not u.begins_with("ws://") and not u.begins_with("wss://"):
		u = "ws://" + u
	var rest := u.substr(u.find("://") + 3)
	if not ":" in rest and not u.begins_with("wss://"):
		u += ":%d" % DEFAULT_PORT
	return u

func saved_url() -> String:
	if FileAccess.file_exists(URL_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(URL_PATH))
		if typeof(d) == TYPE_DICTIONARY and str(d.get("url", "")) != "":
			return str(d["url"])
	if FileAccess.file_exists("res://data/server.json"):
		var d2 = JSON.parse_string(FileAccess.get_file_as_string("res://data/server.json"))
		if typeof(d2) == TYPE_DICTIONARY:
			return str(d2.get("url", ""))
	return ""

func save_url(u: String) -> void:
	var f := FileAccess.open(URL_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"url": u}))

# ------------------------------------------------------------------ соединение
func connect_and(u: String, first_msg: Dictionary) -> void:
	disconnect_now()
	url = normalize(u)
	_first = first_msg
	_joined = false
	state = "connecting"
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	var err := ws.connect_to_url(url)
	if err != OK:
		state = "off"
		error.emit("Не получилось подключиться по адресу «%s»" % url)
		return
	status.emit("Подключаюсь к серверу…")

func create_room(u: String, profile: Dictionary, cfg: Dictionary) -> void:
	var m := profile.duplicate()
	m["t"] = "create"
	m["cfg"] = cfg
	connect_and(u, m)

func join_room(u: String, code: String, profile: Dictionary) -> void:
	var m := profile.duplicate()
	m["t"] = "join"
	m["room"] = code.strip_edges().to_upper()
	connect_and(u, m)

func rejoin() -> bool:
	var s := saved_session()
	if s.is_empty():
		return false
	connect_and(str(s["url"]), {"t": "rejoin", "room": s["room"], "token": s["token"]})
	return true

func saved_session() -> Dictionary:
	if FileAccess.file_exists(SESSION_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
		if typeof(d) == TYPE_DICTIONARY and d.has("room") and d.has("token") and d.has("url"):
			return d
	return {}

func clear_session() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))

func _save_session() -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"url": url, "room": room, "token": token}))

func disconnect_now() -> void:
	if ws != null:
		if state == "open":
			ws.send_text('{"t":"leave"}')
		ws.close()
	ws = null
	state = "off"
	_joined = false

## Выйти из комнаты насовсем.
func leave() -> void:
	disconnect_now()
	in_game = false
	acts_log = []
	_log_last = 0
	caught = false
	room = ""
	lobby_data = {}
	start_data = {}
	clear_session()

func is_connected_ok() -> bool:
	return state == "open"

func send(m: Dictionary) -> void:
	if ws != null and state == "open":
		ws.send_text(JSON.stringify(m))

func send_act(a: Dictionary) -> void:
	send({"t": "act", "a": a})

func set_profile(p: Dictionary) -> void:
	var m := p.duplicate()
	m["t"] = "profile"
	send(m)

func set_cfg(cfg: Dictionary) -> void:
	send({"t": "cfg", "cfg": cfg})

func start_game() -> void:
	send({"t": "start"})

# ------------------------------------------------------------------ приём
func _process(delta: float) -> void:
	if ws == null:
		if in_game and _retry > 0.0:
			_retry -= delta
			if _retry <= 0.0:
				_retry = 3.0
				if saved_session().is_empty():
					_retry = 0.0
				else:
					rejoin()
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if state != "open":
			state = "open"
			if not _first.is_empty():
				send(_first)
		while ws.get_available_packet_count() > 0:
			_handle(ws.get_packet().get_string_from_utf8())
		_ping += delta
		if _ping > 15.0:
			_ping = 0.0
			send({"t": "ping"})
	elif st == WebSocketPeer.STATE_CLOSED:
		var was := state
		ws = null
		state = "off"
		if in_game:
			_retry = 1.5
			status.emit("Связь потеряна. Пробую вернуться…")
		elif was != "off":
			if not _joined:
				error.emit("Нет связи с сервером. Проверь адрес и что сервер запущен.")
			closed.emit()

func _handle(txt: String) -> void:
	var m = JSON.parse_string(txt)
	if typeof(m) != TYPE_DICTIONARY:
		return
	match str(m.get("t", "")):
		"joined":
			_joined = true
			room = str(m["room"])
			cid = int(m["cid"])
			token = str(m["token"])
			_save_session()
			status.emit("Комната %s" % room)
		"lobby":
			lobby_data = m
			host = int(m.get("host", -1)) == cid
			lobby.emit(m)
		"start":
			if in_game:
				return          # после переподключения: игра уже идёт, повтор не нужен
			start_data = m
			in_game = true
			acts_log = []
			_log_last = 0
			caught = false
			started.emit(m)
		"act":
			_log_act(m)
			act.emit(m)
		"batch":
			for e in m.get("acts", []):
				_log_act(e)
				act.emit(e)
		"caught_up":
			caught = true
			caught_up.emit()
		"err":
			var txt2 := str(m.get("msg", "Ошибка"))
			if txt2.begins_with("Не удалось вернуться") or txt2.begins_with("Такой комнаты нет"):
				if in_game:
					in_game = false
				clear_session()
			error.emit(txt2)

func _log_act(m: Dictionary) -> void:
	var seq := int(m.get("seq", 0))
	if seq > _log_last:
		_log_last = seq
		acts_log.append(m)
