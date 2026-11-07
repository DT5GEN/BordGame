extends RefCounted
## Карта долины: клетки, высоты, объекты. Север (z = 0) — старт, юг — Святилище.

enum { GRASS, FOREST, HILL, SAND, WATER, BRIDGE, ROCK, SHRINE, PATH, HILL2 }

const COST := {GRASS: 1, FOREST: 2, HILL: 1, SAND: 1, WATER: 99, BRIDGE: 1, ROCK: 99, SHRINE: 1, PATH: 1, HILL2: 1}
const NAMES := {GRASS: "Равнина", FOREST: "Лес", HILL: "Холм", HILL2: "Высокий холм", SAND: "Берег", WATER: "Река",
	BRIDGE: "Мост", ROCK: "Скалы", SHRINE: "Ворота в горе", PATH: "Горная тропа"}

var w := 0
var h := 0
var t := PackedInt32Array()
var top := PackedFloat32Array()
var rivers: Array = []
var bridges: Array = []
var gorge := Vector2i()
var shrine := Vector2i()
var starts: Array = []
var campfires: Array = []
var objects: Array = []   # [{type, pos, kind?, content?}]
var rng := RandomNumberGenerator.new()
var _taken := {}

func inb(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func get_t(p: Vector2i) -> int:
	return t[p.y * w + p.x]

func set_t(p: Vector2i, v: int) -> void:
	if inb(p):
		t[p.y * w + p.x] = v

func cost(p: Vector2i) -> int:
	return COST[get_t(p)]

func passable(p: Vector2i) -> bool:
	return inb(p) and cost(p) < 50

## Этаж клетки: равнина 0, холм 1, высокий холм 2.
func level(p: Vector2i) -> int:
	match get_t(p):
		HILL: return 1
		HILL2: return 2
	return 0

## Цена шага с клетки a на соседнюю b. Подъём на этаж +1, по холму и вниз — как обычно.
## Сразу на два этажа (обрыв) не забраться и не спрыгнуть.
func move_cost(a: Vector2i, b: Vector2i) -> int:
	if not passable(b):
		return 99
	var dl := level(b) - level(a) if inb(a) else 0
	if absi(dl) > 1:
		return 99
	return cost(b) + maxi(0, dl)

func height(p: Vector2i) -> float:
	if not inb(p):
		return 0.0
	return top[p.y * w + p.x]

func world_pos(p: Vector2i) -> Vector3:
	return Vector3(p.x, height(p), p.y)

func generate(width: int, height_: int, seed_: int, n_players: int) -> void:
	w = width
	h = height_
	rng.seed = seed_
	t.resize(w * h)
	top.resize(w * h)
	var nf := FastNoiseLite.new()
	nf.seed = rng.randi()
	nf.frequency = 0.11
	var nh := FastNoiseLite.new()
	nh.seed = rng.randi()
	nh.frequency = 0.075
	for z in h:
		for x in w:
			var v := nf.get_noise_2d(x, z)
			var hv := nh.get_noise_2d(x, z)
			var tt := GRASS
			if hv > 0.28:
				tt = HILL
			elif v > 0.12:
				tt = FOREST
			t[z * w + x] = tt
	for z in range(0, 3):
		for x in w:
			t[z * w + x] = GRASS
	for z in range(h - 4, h):
		for x in w:
			t[z * w + x] = GRASS
	# 1–3 реки (на короткой карте не больше двух)
	var nr := rng.randi_range(1, 3 if h >= 40 else 2)
	for i in nr:
		var f := 0.45 if nr == 1 else lerpf(0.24, 0.66, float(i) / float(nr - 1))
		_river(int(h * f) + rng.randi_range(-1, 1))
	_gorge()
	for z in range(4, h - 12):
		for x in w:
			if t[z * w + x] == GRASS and rng.randf() < 0.025:
				t[z * w + x] = ROCK
	shrine = Vector2i(w / 2, h - 2)
	set_t(shrine, SHRINE)
	_ensure_path()
	_high_hills(nh)
	_heights()
	_place_objects(n_players)

func _river(rz: int) -> void:
	var phase := rng.randf() * TAU
	var cols: Array = []
	for x in w:
		var zc := rz + int(round(sin(x * 0.33 + phase) * 1.6 + sin(x * 0.11 + phase * 1.7) * 1.2))
		cols.append(zc)
	for x in w:
		var a: int = cols[x]
		var b: int = cols[x]
		if x > 0:
			a = mini(a, cols[x - 1])
			b = maxi(b, cols[x - 1])
		for zz in range(a, b + 2):
			set_t(Vector2i(x, zz), WATER)
	for x in w:
		for zz in range(rz - 6, rz + 8):
			var p := Vector2i(x, zz)
			if not inb(p) or get_t(p) == WATER:
				continue
			if _near_type(p, WATER):
				set_t(p, SAND)
	var n := rng.randi_range(2, 3) + (1 if w >= 34 else 0)
	for i in n:
		var bx := clampi(int((i + 0.5) * w / n) + rng.randi_range(-2, 2), 1, w - 2)
		var zmin := 9999
		var zmax := -1
		for zz in range(rz - 6, rz + 8):
			var p := Vector2i(bx, zz)
			if inb(p) and get_t(p) == WATER:
				set_t(p, BRIDGE)
				bridges.append(p)
				zmin = mini(zmin, zz)
				zmax = maxi(zmax, zz)
		for zz in [zmin - 1, zmax + 1]:
			var q := Vector2i(bx, zz)
			if inb(q) and not passable(q):
				set_t(q, SAND)
	rivers.append(rz)

func _near_type(p: Vector2i, tt: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = p + d
		if inb(q) and get_t(q) == tt:
			return true
	return false

func _gorge() -> void:
	var z0 := h - 10
	var z1 := h - 7
	gorge = Vector2i(z0, z1)
	for z in range(z0, z1 + 1):
		for x in w:
			set_t(Vector2i(x, z), ROCK)
	for x in w:
		if rng.randf() < 0.45:
			set_t(Vector2i(x, z0 - 1), ROCK)
		if rng.randf() < 0.45:
			set_t(Vector2i(x, z1 + 1), ROCK)
	var npass := rng.randi_range(1, 2) if w >= 20 else 1
	for i in npass:
		var px := rng.randi_range(2, w - 4)
		if npass == 2:
			px = rng.randi_range(2, w / 2 - 3) if i == 0 else rng.randi_range(w / 2 + 1, w - 4)
		var x := px
		for z in range(z0 - 1, z1 + 2):
			set_t(Vector2i(x, z), PATH)
			set_t(Vector2i(x + 1, z), PATH)
			if rng.randf() < 0.35:
				x = clampi(x + (1 if rng.randf() < 0.5 else -1), 1, w - 3)
				set_t(Vector2i(x, z), PATH)
				set_t(Vector2i(x + 1, z), PATH)

func _reachable(a: Vector2i, b: Vector2i) -> bool:
	var seen := {a: true}
	var q: Array = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		if c == b:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if passable(n) and not seen.has(n):
				seen[n] = true
				q.append(n)
	return false

func _ensure_path() -> void:
	var s := Vector2i(w / 2, 1)
	if _reachable(s, shrine):
		return
	for z in range(3, gorge.x - 1):
		for x in w:
			if get_t(Vector2i(x, z)) == ROCK:
				set_t(Vector2i(x, z), GRASS)
	if _reachable(s, shrine):
		return
	for z in range(0, h):
		var p := Vector2i(w / 2, z)
		if not passable(p):
			set_t(p, BRIDGE if get_t(p) == WATER else PATH)

## Вершины больших холмов становятся «вторым этажом». Вокруг всегда обычный холм,
## поэтому подняться можно только по ступенькам.
func _high_hills(nh: FastNoiseLite) -> void:
	var up: Array = []
	for z in range(1, h - 1):
		for x in range(1, w - 1):
			var p := Vector2i(x, z)
			if get_t(p) != HILL or nh.get_noise_2d(x, z) < 0.42:
				continue
			var ok := true
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if get_t(p + Vector2i(dx, dz)) != HILL:
						ok = false
			if ok:
				up.append(p)
	for p in up:
		set_t(p, HILL2)

func _heights() -> void:
	for z in h:
		for x in w:
			var tt := t[z * w + x]
			var y := 0.0
			match tt:
				HILL: y = 0.45
				HILL2: y = 0.9
				SAND: y = -0.07
				WATER: y = -0.6
				BRIDGE: y = 0.04
				ROCK:
					if z >= gorge.x - 1 and z <= gorge.y + 1:
						y = 1.1 + rng.randf() * 0.8
					else:
						y = 0.18 + rng.randf() * 0.15
				SHRINE: y = 0.06
				PATH: y = -0.02
			top[z * w + x] = y

func _free(p: Vector2i, allow_forest := true) -> bool:
	if not passable(p) or _taken.has(p):
		return false
	var tt := get_t(p)
	if tt in [BRIDGE, PATH, SHRINE, WATER, ROCK]:
		return false
	if tt == FOREST and not allow_forest:
		return false
	if _near_type(p, BRIDGE):
		return false
	return true

func find_free(near: Vector2i, allow_forest := true, prefer: int = -1) -> Vector2i:
	if prefer >= 0:
		for r in range(0, 5):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var p := near + Vector2i(dx, dz)
					if inb(p) and get_t(p) == prefer and _free(p):
						return p
	for r in range(0, 12):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var p := near + Vector2i(dx, dz)
				if inb(p) and _free(p, allow_forest):
					return p
	return Vector2i(-1, -1)

const CAMP_TILES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

## Костёр ставится на стык 4 клеток — все 4 должны быть свободной землёй.
func _find_camp(near: Vector2i) -> Vector2i:
	for r in range(0, 12):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var p := near + Vector2i(dx, dz)
				var ok := true
				for d in CAMP_TILES:
					var q: Vector2i = p + d
					if not inb(q) or not _free(q, false) or get_t(q) == HILL or get_t(q) == HILL2:
						ok = false
						break
				if ok:
					return p
	return Vector2i(-1, -1)

func _take(p: Vector2i) -> void:
	_taken[p] = true

func _place_objects(np: int) -> void:
	_taken[shrine] = true
	for i in np:
		var sp := Vector2i(int(round((i + 1.0) * w / (np + 1.0))), 1)
		starts.append(sp)
		_take(sp)
	var camp_rows: Array = [4]
	for r in rivers:
		camp_rows.append(int(r) + 4)
	camp_rows.append(gorge.x - 4)
	for row in camp_rows:
		var cp := _find_camp(Vector2i(w / 2 + rng.randi_range(-3, 3), row))
		if cp.x >= 0:
			campfires.append(cp)
			for d in CAMP_TILES:
				_take(cp + d)
			objects.append({"type": "campfire", "pos": cp})
	# Осколки — больше, чем игроков
	var n_shards := maxi(5, np + 2)
	var z0 := 6
	var z1 := gorge.x - 2
	var band := float(z1 - z0) / n_shards
	var kinds: Array = []
	for i in n_shards:
		kinds.append(["open", "chest", "guardian"][i % 3])
	_shuffle(kinds)
	for i in n_shards:
		var tz := int(z0 + band * (i + 0.5)) + rng.randi_range(-1, 1)
		var half := i % 2
		var tx := rng.randi_range(2, w / 2 - 2) if half == 0 else rng.randi_range(w / 2 + 1, w - 3)
		var kind: String = kinds[i]
		var p := find_free(Vector2i(tx, tz), true, HILL if kind == "open" else -1)
		if p.x < 0:
			continue
		_take(p)
		match kind:
			"open":
				objects.append({"type": "shard", "pos": p})
			"chest":
				objects.append({"type": "chest", "pos": p, "content": "shard"})
			"guardian":
				objects.append({"type": "beast", "pos": p, "kind": "guardian", "shard": true})
	# Сундуки с добычей
	for i in int(w * h / 200.0):
		var p := find_free(Vector2i(rng.randi_range(1, w - 2), rng.randi_range(6, gorge.x - 2)))
		if p.x >= 0:
			_take(p)
			objects.append({"type": "chest", "pos": p, "content": "loot"})
	# Звери в лесах
	for i in int(w * h / 140.0):
		for attempt in 20:
			var p := Vector2i(rng.randi_range(1, w - 2), rng.randi_range(7, gorge.x - 2))
			if get_t(p) == FOREST and _free(p):
				_take(p)
				objects.append({"type": "beast", "pos": p, "kind": "wolf" if rng.randf() < 0.55 else "boar", "shard": false})
				break
	# Медведи — редкие и сильные
	for i in maxi(1, int(w * h / 450.0)):
		for attempt in 40:
			var p := Vector2i(rng.randi_range(1, w - 2), rng.randi_range(int(h * 0.25), gorge.x - 2))
			if get_t(p) == FOREST and _free(p):
				_take(p)
				objects.append({"type": "beast", "pos": p, "kind": "bear", "shard": false})
				break
	# Камни с вопросом — случайные события
	for i in int(w * h / 230.0):
		var p := find_free(Vector2i(rng.randi_range(1, w - 2), rng.randi_range(5, gorge.x - 2)))
		if p.x >= 0:
			_take(p)
			objects.append({"type": "event", "pos": p})

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
