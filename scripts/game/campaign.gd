extends RefCounted
## Кампания «Времена года»: три карты подряд — Лето, Осень, Зима. Данные сезонов, сюжет, очки, ачивки.

const COUNT := 3
const PATH := "user://campaign.json"

## Всё, что отличает сезон: цвета клеток, воды, неба и зверей. hard — сложность раунда.
const SEASONS := [
	{
		"id": "summer", "name": "Лето", "place": "Долина Лета", "hard": 1.0,
		"tiles": {},
		"water_deep": Color(0.07, 0.26, 0.46), "water_shallow": Color(0.18, 0.48, 0.66),
		"sky_tint": Color(1, 1, 1), "tint_k": 0.0, "fog": 0.0,
		"weather": [0.18, 0.35], "precip": "rain",
		"wolf": 0.55,
	},
	{
		"id": "autumn", "name": "Осень", "place": "Золотой Лес", "hard": 1.2,
		"tiles": {
			0: Color(0.68, 0.62, 0.26), 1: Color(0.64, 0.30, 0.14), 2: Color(0.78, 0.58, 0.24),
			9: Color(0.84, 0.50, 0.22), 3: Color(0.80, 0.68, 0.48), 6: Color(0.46, 0.42, 0.40),
			8: Color(0.62, 0.48, 0.34),
		},
		"water_deep": Color(0.10, 0.22, 0.34), "water_shallow": Color(0.26, 0.42, 0.52),
		"sky_tint": Color(1.0, 0.84, 0.66), "tint_k": 0.28, "fog": 0.003,
		"weather": [0.32, 0.5], "precip": "rain",
		"wolf": 0.45,
	},
	{
		"id": "winter", "name": "Зима", "place": "Ледяной Перевал", "hard": 1.45,
		"tiles": {
			0: Color(0.80, 0.86, 0.93), 1: Color(0.58, 0.70, 0.72), 2: Color(0.86, 0.91, 0.97),
			9: Color(0.92, 0.95, 1.0), 3: Color(0.82, 0.88, 0.94), 6: Color(0.52, 0.55, 0.62),
			8: Color(0.72, 0.75, 0.82), 7: Color(0.78, 0.80, 0.86),
		},
		"water_deep": Color(0.30, 0.50, 0.68), "water_shallow": Color(0.66, 0.84, 0.94),
		"sky_tint": Color(0.78, 0.88, 1.0), "tint_k": 0.4, "fog": 0.006,
		"weather": [0.55, 0.75], "precip": "snow",
		"wolf": 0.85,
	},
]

## Сюжет. intro — перед раундом, after — после победы в раунде.
const INTRO := [
	["Лето. Долина просыпается",
	"Старый свиток говорит: в Долине спрятаны Осколки Сердца. Кто соберёт три и принесёт их к Горе, тот откроет её тайну и получит магию.\n\nСолнце высоко, реки полны воды. Лето — самое мирное время. Но Гора уже ждёт…"],
	["Осень. Золотой Лес",
	"Печать на Горе снята, и магия вышла наружу. Но вместе с ней что-то проснулось: листья стали цвета огня, а по ночам из-под земли слышен глухой гул.\n\nНужны новые Осколки: Гора даёт силу только тем, кто доказал, что достоин её. Лес изменился. Звери стали злее, а дожди — чаще."],
	["Зима. Ледяной Перевал",
	"Реки замёрзли. Метель закрыла тропы, и тьма приходит всё раньше. Осколки лежат глубоко в снегах, а звери голодны и опасны.\n\nЭто самый трудный путь. Тот, кто пройдёт его, узнает, что скрыто под Горой."],
]

const AFTER := [
	["Лето позади",
	"Ворота в Горе открылись, и Сердце Долины нашло своего героя. Но когда створки разошлись, из глубины пахнуло холодом.\n\nНа камнях проступили новые знаки. Лето кончилось, и впереди Золотой Лес."],
	["Осень позади",
	"Второе Сердце звучит громче первого. Земля под ногами едва заметно дрожит, а с вершины Горы сходит снег, хотя до зимы ещё далеко.\n\nПуть ведёт на Ледяной Перевал. Берегите тепло."],
	["Зима позади… но это ещё не конец",
	"Последние Осколки встали на места, и Гора ответила. Лёд на вершине треснул, в склоне открылась тёмная пещера, оттуда пахнуло жаром.\n\nИ все услышали рёв. Такой, от которого дрожат стёкла…\n\nПродолжение следует."],
]

## Ачивки: id → [название, описание]
const ACH := {
	"summer_hero": ["Герой лета", "Выиграл первый раунд кампании"],
	"autumn_hero": ["Герой осени", "Выиграл второй раунд кампании"],
	"winter_conqueror": ["Покоритель зимы", "Выиграл третий, самый трудный раунд"],
	"all_seasons": ["Хозяин времён года", "Выиграл все три раунда подряд"],
	"campaign_leader": ["Лидер кампании", "Набрал больше всех очков за три раунда"],
}

const WIN_POINTS := 3
const SHARD_POINTS_MAX := 2

static func season(chapter: int) -> Dictionary:
	return SEASONS[clampi(chapter, 0, COUNT - 1)]

## Цвет клетки в этом сезоне (если сезон его не меняет — исходный).
static func tile_base(chapter: int, tt: int, orig: Color) -> Color:
	var t: Dictionary = season(chapter)["tiles"]
	return t.get(tt, orig)

## Очки за раунд: победитель 3, остальные — по найденным осколкам (но не больше 2).
static func round_points(winner_ids: Array, players: Array) -> Array:
	var res: Array = []
	for q in players:
		if winner_ids.has(q.slot):
			res.append(WIN_POINTS)
		else:
			res.append(mini(int(q.shards), SHARD_POINTS_MAX))
	return res

# ------------------------------------------------------------------ ачивки на диске
static func load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}

## Записывает ачивку игроку. Возвращает true, если она новая.
static func grant(player_name: String, id: String) -> bool:
	var all := load_all()
	var mine: Array = all.get(player_name, [])
	if mine.has(id):
		return false
	mine.append(id)
	all[player_name] = mine
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all))
	return true
