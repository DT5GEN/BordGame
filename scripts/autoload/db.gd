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
	Color("e8483f"), Color("3d8bff"), Color("3fbf5f"),
	Color("f2c12e"), Color("a45ee5"), Color("ff8a2a"),
]

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
	var tp: String = traps[card_idx]["type"]
	return int(trap_cost.get(tp, 3))

func random_trap(rng: RandomNumberGenerator) -> int:
	# Редкие попадаются реже
	while true:
		var i := rng.randi_range(0, traps.size() - 1)
		if traps[i]["type"] != "Редкая" or rng.randf() < 0.35:
			return i
	return 0
