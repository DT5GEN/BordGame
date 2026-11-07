extends RefCounted
## Строит 3D-долину по карте: клетки, деревья, цветы, скалы, мосты, вода.

const M = preload("res://scripts/world/map_gen.gd")
const Models = preload("res://scripts/world/models.gd")

const BOTTOM := -1.4
const CHUNK := 8

static func tile_color(tt: int, x: int, z: int, rng: RandomNumberGenerator) -> Color:
	var c: Color
	match tt:
		M.GRASS: c = Color(0.45, 0.72, 0.32)
		M.FOREST: c = Color(0.30, 0.52, 0.24)
		M.HILL: c = Color(0.58, 0.76, 0.38)
		M.SAND: c = Color(0.88, 0.80, 0.58)
		M.WATER: c = Color(0.20, 0.30, 0.30)
		M.BRIDGE: c = Color(0.20, 0.30, 0.30)
		M.ROCK: c = Color(0.50, 0.47, 0.43)
		M.SHRINE: c = Color(0.74, 0.72, 0.66)
		M.PATH: c = Color(0.68, 0.58, 0.42)
		_: c = Color.MAGENTA
	var checker := 0.035 if (x + z) % 2 == 0 else -0.01
	var v := rng.randf_range(-0.03, 0.03)
	return Color(clampf(c.r + checker + v, 0, 1), clampf(c.g + checker + v, 0, 1), clampf(c.b + checker * 0.5 + v * 0.5, 0, 1))

static func build(map, parent: Node3D) -> Dictionary:
	var info := {"tile_ref": {}, "decor_ref": {}, "bridge_nodes": {}, "foliage_mat": null, "water_mat": null}
	var rng := RandomNumberGenerator.new()
	rng.seed = map.rng.seed + 77
	var groups := {}
	for z in map.h:
		for x in map.w:
			var p := Vector2i(x, z)
			var tt: int = map.get_t(p)
			var topy: float = map.height(p)
			var key := tt
			if tt == M.BRIDGE:
				key = M.WATER
				topy = -0.6
			# куски 8×8 клеток — камера рисует только то, что видно
			key = key * 100000 + (z / CHUNK) * 1000 + (x / CHUNK)
			if not groups.has(key):
				groups[key] = []
			groups[key].append([p, tile_color(tt, x, z, rng), topy])
	var boxm := BoxMesh.new()
	boxm.size = Vector3.ONE
	var tile_mat := StandardMaterial3D.new()
	tile_mat.vertex_color_use_as_albedo = true
	tile_mat.vertex_color_is_srgb = true
	tile_mat.roughness = 0.95
	for key in groups:
		var arr: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = boxm
		mm.instance_count = arr.size()
		for i in arr.size():
			var e: Array = arr[i]
			var pp: Vector2i = e[0]
			var topy: float = e[2]
			var hgt := topy - BOTTOM
			var tr := Transform3D(Basis.from_scale(Vector3(1.0, hgt, 1.0)), Vector3(pp.x, (topy + BOTTOM) * 0.5, pp.y))
			mm.set_instance_transform(i, tr)
			mm.set_instance_color(i, e[1])
			info["tile_ref"][pp] = [mm, i, e[1]]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = tile_mat
		parent.add_child(mmi)
	_trees(map, parent, rng, info)
	_decor(map, parent, rng, info)
	for b in map.bridges:
		var bp: Vector2i = b
		var bn := Models.bridge_tile()
		bn.position = Vector3(bp.x, map.height(bp), bp.y)
		parent.add_child(bn)
		info["bridge_nodes"][bp] = bn
	# Вода вокруг и в реках
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(map.w + 90, map.h + 90)
	pm.subdivide_width = 90
	pm.subdivide_depth = 90
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	water.material_override = wm
	water.position = Vector3(map.w * 0.5 - 0.5, -0.22, map.h * 0.5 - 0.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(water)
	info["water_mat"] = wm
	return info

static func _mm(mesh: Mesh, items: Array, mat: Material, parent: Node3D, shadows := true, info: Dictionary = {}) -> void:
	if items.is_empty():
		return
	# делим на куски по клеткам, чтобы невидимое не рисовалось
	var chunks := {}
	for it in items:
		var key := 0
		if it.size() > 2:
			var tp: Vector2i = it[2]
			key = (tp.y / CHUNK) * 1000 + (tp.x / CHUNK)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(it)
	for key in chunks:
		_mm_one(mesh, chunks[key], mat, parent, shadows, info)

static func _mm_one(mesh: Mesh, items: Array, mat: Material, parent: Node3D, shadows: bool, info: Dictionary) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
		if items[i].size() > 2 and info.has("decor_ref"):
			var tp: Vector2i = items[i][2]
			if not info["decor_ref"].has(tp):
				info["decor_ref"][tp] = []
			info["decor_ref"][tp].append([mm, i, items[i][1]])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)

static func _trees(map, parent: Node3D, rng: RandomNumberGenerator, info: Dictionary) -> void:
	var trunks: Array = []
	var pines: Array = []
	var rounds: Array = []
	var busy := {}
	for o in map.objects:
		busy[o["pos"]] = true
	for s in map.starts:
		busy[s] = true
	for z in map.h:
		for x in map.w:
			var p := Vector2i(x, z)
			var tt: int = map.get_t(p)
			var n := 0
			if tt == M.FOREST:
				n = 2 if rng.randf() < 0.7 else 3
			elif tt == M.GRASS and rng.randf() < 0.03 and z > 3:
				n = 1
			elif tt == M.HILL and rng.randf() < 0.06:
				n = 1
			if busy.has(p):
				n = 0
			var a0 := rng.randf() * TAU
			for k in n:
				var a := a0 + k * TAU / maxf(1.0, n) + rng.randf_range(-0.4, 0.4)
				var rr := rng.randf_range(0.26, 0.36)
				var off := Vector3(cos(a) * rr, 0, sin(a) * rr)
				var base := Vector3(x, map.height(p), z) + off
				var s := rng.randf_range(0.75, 1.15)
				trunks.append([Transform3D(Basis.from_scale(Vector3(s, s, s)), base + Vector3(0, 0.15 * s, 0)), Color("6b4a2c"), p])
				var g := Color(rng.randf_range(0.16, 0.26), rng.randf_range(0.42, 0.58), rng.randf_range(0.18, 0.26))
				if rng.randf() < 0.55:
					pines.append([Transform3D(Basis.from_scale(Vector3(s, s, s)), base + Vector3(0, 0.45 * s, 0)), g, p])
					pines.append([Transform3D(Basis.from_scale(Vector3(s * 0.75, s * 0.8, s * 0.75)), base + Vector3(0, 0.75 * s, 0)), g.lightened(0.08), p])
				else:
					var g2 := Color(rng.randf_range(0.30, 0.45), rng.randf_range(0.55, 0.70), rng.randf_range(0.20, 0.30))
					rounds.append([Transform3D(Basis.from_scale(Vector3(s, s * 0.9, s)), base + Vector3(0, 0.58 * s, 0)), g2, p])
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/foliage.gdshader")
	info["foliage_mat"] = fm
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.vertex_color_use_as_albedo = true
	trunk_mat.vertex_color_is_srgb = true
	_mm(Models.cyl(0.045, 0.065, 0.32, 6), trunks, trunk_mat, parent, true, info)
	_mm(Models.cyl(0.0, 0.3, 0.55, 7), pines, fm, parent, true, info)
	var blob := SphereMesh.new()
	blob.radius = 0.3
	blob.height = 0.6
	blob.radial_segments = 8
	blob.rings = 5
	_mm(blob, rounds, fm, parent, true, info)

static func _decor(map, parent: Node3D, rng: RandomNumberGenerator, info: Dictionary) -> void:
	var flowers: Array = []
	var tufts: Array = []
	var boulders: Array = []
	var fcols := [Color("fff6e0"), Color("ffd84a"), Color("ff8fb8"), Color("8fb8ff"), Color("ff6a4a")]
	for z in map.h:
		for x in map.w:
			var p := Vector2i(x, z)
			var tt: int = map.get_t(p)
			var y: float = map.height(p)
			if tt == M.GRASS or tt == M.HILL:
				if rng.randf() < 0.35:
					var c: Color = fcols[rng.randi() % fcols.size()]
					for k in rng.randi_range(1, 3):
						var off := Vector3(rng.randf_range(-0.42, 0.42), 0.03, rng.randf_range(-0.42, 0.42))
						flowers.append([Transform3D(Basis(), Vector3(x, y, z) + off), c, p])
				if rng.randf() < 0.5:
					for k in rng.randi_range(1, 3):
						var off := Vector3(rng.randf_range(-0.42, 0.42), 0.05, rng.randf_range(-0.42, 0.42))
						var g := Color(rng.randf_range(0.3, 0.42), rng.randf_range(0.6, 0.75), rng.randf_range(0.22, 0.3))
						tufts.append([Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU), Vector3(x, y, z) + off), g, p])
			elif tt == M.ROCK:
				var low: bool = y < 0.5
				for k in (rng.randi_range(2, 3) if low else rng.randi_range(1, 2)):
					var off := Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.05, 0.1), rng.randf_range(-0.25, 0.25))
					var s := rng.randf_range(0.8, 1.3) if low else rng.randf_range(0.6, 1.1)
					var b := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s))
					var gc := rng.randf_range(0.42, 0.55)
					boulders.append([Transform3D(b, Vector3(x, y, z) + off), Color(gc, gc * 0.97, gc * 0.92), p])
	var vm := StandardMaterial3D.new()
	vm.vertex_color_use_as_albedo = true
	vm.vertex_color_is_srgb = true
	vm.roughness = 1.0
	var fl := SphereMesh.new()
	fl.radius = 0.035
	fl.height = 0.06
	fl.radial_segments = 6
	fl.rings = 3
	_mm(fl, flowers, vm, parent, false, info)
	_mm(Models.cyl(0.0, 0.035, 0.12, 4), tufts, vm, parent, false, info)
	var bm := SphereMesh.new()
	bm.radius = 0.3
	bm.height = 0.6
	bm.radial_segments = 6
	bm.rings = 3
	_mm(bm, boulders, vm, parent, true, info)
