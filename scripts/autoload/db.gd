extends Node
## Все данные игры: карты из data/cards.json + герои.

var traps: Array = []
var summons: Array = []
var dice: Dictionary = {}
var dice_order: Array = ["D6", "D8", "D10", "D12", "D20"]
var trap_cost: Dictionary = {}
var beasts: Dictionary = {}
var items: Dictionary = {}

## Кто победил в прошлой партии (индекс слота) — получает питомца.
var last_winner_slot: int = -1
## Настройки последней партии (чтобы «Ещё партия» сохраняла игроков).
var last_config: Dictionary = {}

const PLAYER_COLORS: Array = [
	Color("e8483f"), Color("3d8bff"), Color("3fbf5f"), Color("f2c12e"), Color("a45ee5"),
	Color("ff8a2a"), Color("2fd0c8"), Color("ff6fb5"), Color("9be04a"), Color("c9c9c9"),
]
const TEAM_COLORS: Array = [Color("e8483f"), Color("3d8bff")]

## 10 героев — подростки-приключенцы. Свои персонажи, «в духе» любимых игр.
var heroes: Array = [
	{"name": "Тимур", "title": "Тренер в кепке", "style": "cap", "skin": "f3c9a5", "hair": "3a2a20",
		"top": "2f6fd6", "top2": "f4f4f4", "pants": "34406e", "hat": "d93a3a", "acc": ["backpack"], "acc_col": "2e9e57"},
	{"name": "Ая", "title": "Лесная следопытка", "style": "hood", "skin": "f1c7a0", "hair": "7a4a2a",
		"top": "7a5a3a", "top2": "c9a46a", "pants": "4a3a2a", "hat": "4f7a3a", "acc": ["cape"], "acc_col": "3f6430"},
	{"name": "Мира", "title": "Искательница кристаллов", "style": "ponytail", "skin": "f6d3b5", "hair": "f0c14b",
		"top": "8c4fd1", "top2": "f2e6ff", "pants": "3b2d5c", "hat": "", "acc": ["goggles"], "acc_col": "5fd3f3"},
	{"name": "Данияр", "title": "Юный страж", "style": "headband", "skin": "d9a77c", "hair": "1e1a18",
		"top": "a3adc2", "top2": "3d5bd9", "pants": "2d3550", "hat": "d33a2c", "acc": ["scarf"], "acc_col": "3d5bd9"},
	{"name": "Лея", "title": "Девочка-ветер", "style": "buns", "skin": "f5d1b8", "hair": "2bb3b3",
		"top": "f4f1e8", "top2": "2bb3b3", "pants": "2a6f6f", "hat": "", "acc": ["scarf"], "acc_col": "f4f1e8"},
	{"name": "Макс", "title": "Мастер огня", "style": "spiky", "skin": "f0c29b", "hair": "ff7a1a",
		"top": "c0392b", "top2": "2b2b2b", "pants": "2b2b2b", "hat": "", "acc": ["scarf"], "acc_col": "f1c40f"},
	{"name": "Ника", "title": "Тихая лучница", "style": "long", "skin": "f3cfb0", "hair": "5a2f1a",
		"top": "2e7d4f", "top2": "c9a46a", "pants": "3a3a2a", "hat": "", "acc": ["cape"], "acc_col": "1e4d33"},
	{"name": "Егор", "title": "Исследователь", "style": "explorer", "skin": "f2c8a2", "hair": "8a5a32",
		"top": "c8b07a", "top2": "6b4f2a", "pants": "5a4a32", "hat": "a8824f", "acc": ["bag"], "acc_col": "6b4f2a"},
	{"name": "Алиса", "title": "Ловкая разведчица", "style": "bob", "skin": "f7d6bd", "hair": "1a1a1a",
		"top": "f2c12e", "top2": "333333", "pants": "333333", "hat": "", "acc": ["backpack"], "acc_col": "e8483f"},
	{"name": "Арсен", "title": "Ученик мага", "style": "wizard", "skin": "e9b892", "hair": "d8d8e8",
		"top": "2a2f6b", "top2": "f1c40f", "pants": "1f2350", "hat": "3b4bc9", "acc": [], "acc_col": "f1c40f"},
]

## Способности на выбор при старте.
const ABILITIES: Array = [
	{"id": "eye", "name": "Зоркий глаз", "text": "+1 к обзору: видишь соперников, зверей и осколки дальше"},
	{"id": "feet", "name": "Быстрые ноги", "text": "+1 шаг каждый ход"},
	{"id": "tough", "name": "Крепкий", "text": "+6 к здоровью"},
	{"id": "trapper", "name": "Мастер ловушек", "text": "Ловушки на 1 шаг дешевле и 2 лишние карты ловушек на старте"},
	{"id": "beast", "name": "Друг зверей", "text": "Волк приручается за 1 мясо, призывы на 1 шаг дешевле, на старте мясо"},
	{"id": "agile", "name": "Ловкач", "text": "В бою легче поймать щитом атаку, а блок даёт +3 вместо +2"},
	{"id": "seeker", "name": "Чутьё на кристаллы", "text": "Осколки видно на 3 клетки дальше"},
	{"id": "lucky", "name": "Везунчик", "text": "Раз за ход можно перебросить кубик, пока не сделал шаг"},
]

func ability(i: int) -> Dictionary:
	return ABILITIES[posmod(i, ABILITIES.size())]

func summon_idx(id: String) -> int:
	for i in summons.size():
		if summons[i]["id"] == id:
			return i
	return 0

func _ready() -> void:
	load_cards()

func load_cards() -> void:
	var f := FileAccess.open("res://data/cards.json", FileAccess.READ)
	if f == null:
		push_error("Не найден data/cards.json")
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		push_error("Ошибка в data/cards.json")
		return
	traps = d["traps"]
	summons = d["summons"]
	dice = d["dice"]
	trap_cost = d["trap_cost"]
	beasts = d["beasts"]
	items = d["items"]
	base_traps = traps.duplicate(true)
	base_beasts = beasts.duplicate(true)
	_apply_overrides()

func die_faces(die: String) -> Array:
	return dice[die]["faces"]

func die_range_text(die: String) -> String:
	var f: Array = die_faces(die)
	var lo := 999
	var hi := 0
	for v in f:
		lo = mini(lo, int(v))
		hi = maxi(hi, int(v))
	return "%d–%d" % [lo, hi]

func die_avg(die: String) -> float:
	var f: Array = die_faces(die)
	var s := 0.0
	for v in f:
		s += float(v)
	return s / f.size()

func trap_price(card_idx: int) -> int:
	var c: Dictionary = traps[card_idx]
	if c.has("cost"):
		return int(c["cost"])
	return int(trap_cost.get(c["type"], 3))

# ================================================================ РЕДАКТОР БАЛАНСА
## Изменения из редактора хранятся отдельно, исходные карты сына не трогаются.
const OVERRIDE_PATH := "user://cards_override.json"
var base_traps: Array = []
var base_beasts: Dictionary = {}

## Какие числа можно менять и в каких пределах (насколько вверх/вниз от исходного и абсолютный предел).
const FX_LIMITS := {
	"dmg": {"name": "Урон", "min": 0, "max": 5, "delta": 2, "w": 1.0},
	"dot": {"name": "Урон в следующий ход", "min": 0, "max": 2, "delta": 1, "w": 1.0},
	"slow": {"name": "Минус шагов в следующий ход", "min": 0, "max": 3, "delta": 1, "w": 0.7},
	"back": {"name": "Отбросить назад на клеток", "min": 1, "max": 3, "delta": 1, "w": 0.7},
	"heal_owner": {"name": "Лечение хозяина", "min": 0, "max": 3, "delta": 1, "w": 0.8},
	"mark": {"name": "Хозяин видит жертву, ходов", "min": 1, "max": 3, "delta": 1, "w": 0.5},
	"vuln": {"name": "Атаки сильнее, ходов", "min": 1, "max": 3, "delta": 1, "w": 1.0},
}
const FX_FIXED_POWER := {"skip_move": 2.0, "skip_turn": 3.0, "steal_card": 1.5, "lose_card": 1.5,
	"swap_card": 1.0, "teleport": 2.0, "block_traps": 1.0, "block_summon": 1.0}
const BEAST_LIMITS := {
	"power": {"name": "Сила (сколько выбросить)", "min": 2, "max": 6, "delta": 1},
	"dmg": {"name": "Урон по герою", "min": 1, "max": 4, "delta": 1},
	"hits": {"name": "Сколько ударов выдержит", "min": 1, "max": 3, "delta": 1},
}

## Значения храним как float (как их читает JSON), чтобы сравнение с исходником было честным.
func set_fx(i: int, key: String, v: int) -> void:
	var lim := fx_limits(i, key)
	traps[i]["fx"][key] = float(clampi(v, lim.x, lim.y))
	save_overrides()

func set_beast(kind: String, key: String, v: int) -> void:
	var lim := beast_limits(kind, key)
	beasts[kind][key] = float(clampi(v, lim.x, lim.y))
	save_overrides()

func fx_power(fx: Dictionary) -> float:
	var pw := 0.0
	for k in fx:
		if FX_LIMITS.has(k):
			pw += float(fx[k]) * float(FX_LIMITS[k]["w"])
		elif FX_FIXED_POWER.has(k):
			pw += float(FX_FIXED_POWER[k])
	return pw

## Цена растёт вместе с силой карты — так «карта-бог» становится слишком дорогой.
func auto_cost(i: int) -> int:
	var base: Dictionary = base_traps[i]
	var cur: Dictionary = traps[i]
	var bc := int(trap_cost.get(base["type"], 3))
	var diff := fx_power(cur["fx"]) - fx_power(base["fx"])
	return clampi(bc + int(round(diff * 0.8)), 1, 7)

func fx_limits(i: int, key: String) -> Vector2i:
	var lim: Dictionary = FX_LIMITS[key]
	var orig := int(base_traps[i]["fx"].get(key, 0))
	return Vector2i(maxi(int(lim["min"]), orig - int(lim["delta"])), mini(int(lim["max"]), orig + int(lim["delta"])))

func beast_limits(kind: String, key: String) -> Vector2i:
	var lim: Dictionary = BEAST_LIMITS[key]
	var orig := int(base_beasts[kind][key])
	return Vector2i(maxi(int(lim["min"]), orig - int(lim["delta"])), mini(int(lim["max"]), orig + int(lim["delta"])))

## Описание карты по её числам (для изменённых карт).
func fx_text(fx: Dictionary) -> String:
	var parts: Array = []
	if int(fx.get("dmg", 0)) > 0:
		parts.append("%d урона" % int(fx["dmg"]))
	if int(fx.get("dot", 0)) > 0:
		parts.append("ещё %d в следующий ход" % int(fx["dot"]))
	if fx.has("skip_move"):
		parts.append("нельзя двигаться следующий ход")
	if int(fx.get("slow", 0)) > 0:
		parts.append("−%d клетки в следующий ход" % int(fx["slow"]))
	if fx.has("back"):
		parts.append("назад на %d клетки" % int(fx["back"]))
	if fx.has("skip_turn"):
		parts.append("пропуск хода")
	if int(fx.get("heal_owner", 0)) > 0:
		parts.append("владелец +%d HP" % int(fx["heal_owner"]))
	if fx.has("steal_card"):
		parts.append("владелец забирает карту")
	if fx.has("lose_card"):
		parts.append("потеря случайной карты")
	if fx.has("swap_card"):
		parts.append("замена карты")
	if fx.has("mark"):
		parts.append("владелец видит игрока %d хода" % int(fx["mark"]))
	if fx.has("vuln"):
		parts.append("атаки сильнее %d хода" % int(fx["vuln"]))
	if fx.has("teleport"):
		parts.append("перенос в случайное место")
	if fx.has("block_traps"):
		parts.append("нельзя ставить ловушки")
	if fx.has("block_summon"):
		parts.append("нельзя призывать")
	var t := ", ".join(parts)
	return t.left(1).to_upper() + t.substr(1) if t != "" else "Без эффекта"

func _apply_overrides() -> void:
	if not FileAccess.file_exists(OVERRIDE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(OVERRIDE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	var ot: Dictionary = d.get("traps", {})
	for k in ot:
		var i := int(k)
		if i < 0 or i >= traps.size():
			continue
		var o: Dictionary = ot[k]
		var c: Dictionary = traps[i]
		if o.has("name"):
			c["name"] = str(o["name"]).left(30)
		for fk in o.get("fx", {}):
			if FX_LIMITS.has(fk) and c["fx"].has(fk):
				var lim := fx_limits(i, fk)
				c["fx"][fk] = float(clampi(int(o["fx"][fk]), lim.x, lim.y))
		c["text"] = fx_text(c["fx"]) if c["fx"] != base_traps[i]["fx"] else base_traps[i]["text"]
		c["cost"] = auto_cost(i)
	var ob: Dictionary = d.get("beasts", {})
	for kind in ob:
		if not beasts.has(kind):
			continue
		for bk in ob[kind]:
			if BEAST_LIMITS.has(bk):
				var lim := beast_limits(kind, bk)
				beasts[kind][bk] = float(clampi(int(ob[kind][bk]), lim.x, lim.y))

func save_overrides() -> void:
	var ot := {}
	for i in traps.size():
		var c: Dictionary = traps[i]
		var b: Dictionary = base_traps[i]
		if c["name"] != b["name"] or c["fx"] != b["fx"]:
			ot[str(i)] = {"name": c["name"], "fx": c["fx"]}
		c["text"] = fx_text(c["fx"]) if c["fx"] != b["fx"] else b["text"]
		if c["fx"] != b["fx"]:
			c["cost"] = auto_cost(i)
		else:
			c.erase("cost")
	var ob := {}
	for kind in beasts:
		var diff := {}
		for bk in BEAST_LIMITS:
			if int(beasts[kind][bk]) != int(base_beasts[kind][bk]):
				diff[bk] = int(beasts[kind][bk])
		if not diff.is_empty():
			ob[kind] = diff
	var f := FileAccess.open(OVERRIDE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"traps": ot, "beasts": ob}, "  "))

func reset_trap(i: int) -> void:
	traps[i] = base_traps[i].duplicate(true)
	save_overrides()

func reset_beast(kind: String) -> void:
	beasts[kind] = base_beasts[kind].duplicate(true)
	save_overrides()

func reset_all() -> void:
	traps = base_traps.duplicate(true)
	beasts = base_beasts.duplicate(true)
	save_overrides()

func random_trap(rng: RandomNumberGenerator) -> int:
	# Редкие попадаются реже
	while true:
		var i := rng.randi_range(0, traps.size() - 1)
		if traps[i]["type"] != "Редкая" or rng.randf() < 0.35:
			return i
	return 0
