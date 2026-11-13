class_name SnowMountain
extends Node3D
## The world of SNOW: one 360-degree alpine massif (course massif_v4).
##
## The summit is the highest point of the world and the mountain falls away from
## it in every direction: eight aretes with side spurs, bowls between them, cliff
## bands, couloirs, cornices, ravines and forests, ending on valley floors that
## surround the whole massif. There is no main course and no preferred axis.
##
## GEOGRAPHY: `world/massif_v4.bin` (baked by tools/build_massif.py) holds the
## large-scale height field over +-16 km and four masks (valley floor, cliffs,
## forest, cornices). `height_at()` samples it (bicubic) and adds what is too fine
## to bake: cliff bands (terracing where the cliff mask says so), cornice lips,
## wind-drift kickers and small relief. It is the single source of truth for
## rendering, collision, physics, camera, audio, tumbles and tests.
##
## STREAMING: the world is cut into 640 m tiles grouped in 3.2 km blocks.
##   L0  8 m grid, render triangles == collision triangles, trees and rocks with
##       colliders: the 3x3 tiles around the rider (whatever way it travels).
##   L1  32 m grid within 3.6 km; L2 128 m grid elsewhere. Each block is ONE mesh
##       merged from its tiles' L1/L2 pieces with holes where L0 tiles are shown.
##   Far trees (no colliders) on L1 tiles within ~1.9 km; beyond that the terrain
##       shader paints forest stands. A coarse horizon ring closes the world.
## Tiles and blocks are generated on WorkerThreadPool threads and swapped in on
## the main thread; skirts hide cracks between resolutions. `ensure_ready()`
## builds collision synchronously if the rider ever outruns the streamer.
## Mountain map: north = -Z, east = +X, south = +Z, west = -X.
const COURSE_ID := "massif_v4"
const WORLD_FILE := "res://world/massif_v4.bin"
const STEP := 8.0
const TILE := 640.0
const L0_CELLS := 80
const L1_CELLS := 20
const L2_CELLS := 5
const BLOCK := 5                       # tiles per block side
const L1_RADIUS := 3600.0
const SCENERY_RADIUS := 1500.0
const TREE_NEAR_RANGE := 420.0          # per 320 m batch centre: trees within ~190 m are always detailed
const TREE_FAR_RANGE := 2100.0
const ROCK_RANGE := 1400.0
const MAX_TASKS := 6
## A descent is complete on a valley floor at least this far below the summit.
const FINISH_DROP := 1500.0
const FACES := ["North", "North-east", "East", "South-east", "South", "South-west", "West", "North-west"]
enum { MASK_FINISH, MASK_CLIFF, MASK_FOREST, MASK_CORNICE }

# ------------------------------------------------------------------ world data
static var world_ready := false
static var map_n := 0
static var mask_n := 0
static var extent := 0.0
static var h_lo := 0.0
static var h_scale := 1.0
static var map_step := 1.0
static var mask_ratio := 2.0
static var heights := PackedByteArray()
static var masks := PackedByteArray()
static var summit := Vector3.ZERO
static var apex := Vector2.ZERO        # summit tip, on the 8 m grid
static var _spawn := Vector3.INF
static var _relief: FastNoiseLite = _make_noise(4117, 1.0 / 115.0, 2)
static var _drift: FastNoiseLite = _make_noise(5521, 1.0 / 95.0, 1)
static var _clump: FastNoiseLite = _make_noise(907, 1.0 / 150.0, 2)
static var _rock_noise: FastNoiseLite = _make_noise(311, 1.0 / 85.0, 1)
static var _far_noise: FastNoiseLite = _make_ridged(8402, 1.0 / 5200.0)

static func _make_noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = frequency
	return n

static func _make_ridged(noise_seed: int, frequency: float) -> FastNoiseLite:
	var n := _make_noise(noise_seed, frequency, 3)
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	return n

static func load_world() -> void:
	if world_ready:
		return
	var f := FileAccess.open(WORLD_FILE, FileAccess.READ)
	if f == null:
		push_error("SNOW world file missing: " + WORLD_FILE)
		return
	var raw_size := f.get_32()
	var raw := f.get_buffer(f.get_length() - 4).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	map_n = raw.decode_u32(8)
	mask_n = raw.decode_u32(12)
	extent = raw.decode_float(16)
	h_lo = raw.decode_float(20)
	h_scale = raw.decode_float(24)
	summit = Vector3(raw.decode_float(28), raw.decode_float(36), raw.decode_float(32))
	map_step = 2.0 * extent / (map_n - 1)
	mask_ratio = float(map_n) / mask_n
	heights = raw.slice(40, 40 + map_n * map_n * 2)
	masks = raw.slice(40 + map_n * map_n * 2)
	apex = Vector2(snappedf(summit.x + extent, STEP) - extent, snappedf(summit.z + extent, STEP) - extent)
	world_ready = true

static func band(v: float, lo: float, hi: float, feather: float) -> float:
	return smoothstep(lo - feather, lo, v) * (1.0 - smoothstep(hi, hi + feather, v))

# ------------------------------------------------------------------ sampling
static func _cubic(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)))

static func _row(o: int, t: float) -> float:
	return _cubic(heights.decode_u16(o), heights.decode_u16(o + 2), heights.decode_u16(o + 4), heights.decode_u16(o + 6), t)

## Baked large-scale height (bicubic).
static func macro(x: float, z: float) -> float:
	if not world_ready:
		load_world()
	var fx := clampf((x + extent) / map_step, 1.0, map_n - 3.001)
	var fz := clampf((z + extent) / map_step, 1.0, map_n - 3.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var stride := map_n * 2
	var o := ((iz - 1) * map_n + ix - 1) * 2
	return h_lo + h_scale * _cubic(_row(o, tx), _row(o + stride, tx), _row(o + stride * 2, tx), _row(o + stride * 3, tx), fz - iz)

## Baked mask 0..1 (bilinear).
static func mask(x: float, z: float, channel: int) -> float:
	if not world_ready:
		load_world()
	var fx := clampf(((x + extent) / map_step - 0.5) / mask_ratio, 0.0, mask_n - 1.001)
	var fz := clampf(((z + extent) / map_step - 0.5) / mask_ratio, 0.0, mask_n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var o := channel * mask_n * mask_n + iz * mask_n + ix
	var a := lerpf(masks[o], masks[o + 1], tx)
	var b := lerpf(masks[o + mask_n], masks[o + mask_n + 1], tx)
	return lerpf(a, b, tz) / 255.0

## Ground height (m). Pure function of position: identical on every thread.
static func height_at(x: float, z: float) -> float:
	var h := macro(x, z)
	# The very top is finer than the bake can hold: a ~4 m top falling away at a
	# steady 0.42 grade in every direction, so a push-off rolls straight onto
	# the face it was aimed at, and the camera sees down every side.
	# The tip sits exactly on an 8 m collision-grid vertex, so every triangle
	# around it slopes outward: a push-off in ANY direction rolls downhill.
	var sx := x - apex.x
	var sz := z - apex.y
	var r2 := sx * sx + sz * sz
	if r2 < 6400.0:
		var cone := summit.y + 2.0 - 0.42 * (sqrt(r2 + 16.0) - 4.0)
		h = lerpf(cone, h, smoothstep(40.0, 80.0, sqrt(r2)))
	var grade := Vector2(macro(x + 6.0, z) - h, macro(x, z + 6.0) - h).length() / 6.0
	# Cliff bands are carved in the bake (so the bake's pit fill guarantees no
	# band ever encloses a hollow); the cliff mask marks them for rock and colour.
	var c := mask(x, z, MASK_CLIFF)
	# Cornice lips on the lee of high crests.
	var cornice := mask(x, z, MASK_CORNICE)
	if cornice > 0.3:
		h += smoothstep(0.35, 0.65, cornice) * 4.5
	# Wind-drift rollers on open snow: broad enough (30-50 m) for the 8 m mesh to
	# carry them faithfully, steep enough to launch a fast rider. They (and the
	# small relief) fade on gentle ground so they never dig closed pockets where
	# a stopped rider could not get out.
	var drained := smoothstep(0.2, 0.4, grade)
	var forest := mask(x, z, MASK_FOREST)
	var open := (1.0 - c) * (1.0 - forest) * drained
	if open > 0.05:
		h += smoothstep(0.25, 0.8, _drift.get_noise_2d(x, z)) * 3.6 * open
	h += _relief.get_noise_2d(x, z) * (0.6 + 2.0 * drained)
	return h

static func normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x - 1, z) - height_at(x + 1, z), 2, height_at(x, z - 1) - height_at(x, z + 1)).normalized()

## Snow surface under the board: x = soft powder, y = wind-scoured ice. The terrain
## shader paints the same values, so what the rider SEES is what it FEELS.
static func surface_at(x: float, z: float) -> Vector2:
	var h := height_at(x, z)
	var curvature := h - 0.25 * (height_at(x - STEP, z) + height_at(x + STEP, z) + height_at(x, z - STEP) + height_at(x, z + STEP))
	return surface_from(x, z, normal_at(x, z).y, curvature)

static func surface_from(x: float, z: float, normal_y: float, curvature: float) -> Vector2:
	var patch := 0.5 + 0.5 * sin(x / 53.0 + sin(z / 71.0) * 2.0) * sin(z / 97.0 + x / 140.0)
	var forest := mask(x, z, MASK_FOREST)
	var exposed := 1.0 - forest
	var steep := 1.0 - normal_y
	var ice := clampf(smoothstep(0.07, 0.24, steep) * 0.65 + smoothstep(0.15, 1.0, curvature) * 0.7 + (patch - 0.62) * 1.3 * exposed, 0.0, 1.0)
	var powder := clampf(forest * 0.55 + smoothstep(0.15, 1.0, -curvature) * 0.65 + (0.42 - patch) * 0.9, 0.0, 1.0) * (1.0 - ice)
	return Vector2(powder, ice)

static func forest_amount(x: float, z: float) -> float:
	return mask(x, z, MASK_FOREST)

static func cliff_amount(x: float, z: float) -> float:
	return mask(x, z, MASK_CLIFF)

## Tree density 0..1: forest belts below the treeline (by face), in clumps.
static func tree_density(x: float, z: float) -> float:
	var clump := smoothstep(-0.2, 0.3, _clump.get_noise_2d(x, z))
	return clampf(mask(x, z, MASK_FOREST) * (0.45 + 0.65 * clump), 0.0, 1.0)

## Rocks gather into gardens and moraines, most below cliffs and high up.
static func rock_density(x: float, z: float, h: float) -> float:
	var altitude := smoothstep(summit.y - 2600.0, summit.y - 800.0, h)
	var amount := 0.1 + 0.5 * mask(x, z, MASK_CLIFF) + 0.25 * altitude
	return amount * smoothstep(0.05, 0.45, _rock_noise.get_noise_2d(x, z))

## 0..1: how much this spot is valley floor at the base of the mountain.
static func valley_floor(x: float, z: float) -> float:
	return mask(x, z, MASK_FINISH)

## The descent is complete here: a real valley floor, well below the summit.
## (Callers also require the rider to be grounded, upright and riding.)
static func at_bottom(p: Vector3) -> bool:
	return valley_floor(p.x, p.z) > 0.5 and p.y < summit.y - FINISH_DROP

## Compass face of a point as seen from the summit ("North", "South-west", ...).
static func face_name(x: float, z: float) -> String:
	var az := atan2(x - summit.x, -(z - summit.z))
	return FACES[posmod(int(round(az / (PI / 4.0))), 8)]

## Region name for presentation (audio exposure, records): face and altitude.
static func region(x: float, z: float) -> String:
	var h := height_at(x, z)
	if h > summit.y - 260.0:
		return "Summit"
	if valley_floor(x, z) > 0.5:
		return face_name(x, z) + " valley"
	return face_name(x, z) + " face"

## The highest point of the world, where every run begins: the summit tip,
## exactly on a collision-grid vertex so the ground falls away on every side.
static func spawn_point() -> Vector3:
	if _spawn != Vector3.INF:
		return _spawn
	if not world_ready:
		load_world()
	_spawn = Vector3(apex.x, height_at(apex.x, apex.y), apex.y)
	return _spawn

static func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x + extent) / TILE)), int(floor((p.z + extent) / TILE)))

static func tile_origin(t: Vector2i) -> Vector2:
	return Vector2(-extent + t.x * TILE, -extent + t.y * TILE)

static func tiles_per_side() -> int:
	return int(round(2.0 * extent / TILE))

# ------------------------------------------------------------------ node state
var terrain_material: ShaderMaterial
var tree_material: ShaderMaterial
var rock_material: ShaderMaterial
var horizon_material: ShaderMaterial
var tree_variants: Array = []      # [near mesh, far mesh]
var rock_variants: Array = []      # [mesh, unit points]
var atmosphere: SnowAtmosphere
var focus: Node3D                  # the rider (streaming follows it)
var tree_count := 0
var rock_count := 0
var outcrop_count := 0
## Solid hazards (trees, boulders, outcrops) per loaded L0 tile: Vector4(x, y, z, radius).
var hazard_buckets: Dictionary = {}
var tree_buckets: Dictionary = {}
var l0 := {}          # tile -> {"mesh", "body", "nodes": [], "visible": bool}
var far := {}         # tile -> Array of nodes (far trees)
var blocks := {}      # block -> {"node": MeshInstance3D, "comp": PackedByteArray}
var block_cache := {} # block -> {} tile LOD arrays, written only by that block's task
var pending := {}     # "kind:key" -> task id
var task_info := {}   # task id -> [kind, key, extra]
var results := {}     # task id -> Dictionary
var mutex := Mutex.new()
var planting: Array = []   # [tile, scenery] waiting to be planted
var last_tile := Vector2i(-9999, -9999)
var plan_timer := 0.0
## max_frame_ms: the longest main-thread streaming work in one ordinary frame
## (synchronous builds for teleports/startup are counted separately).
var stream_stats := {"l0_built": 0, "blocks_built": 0, "sync_builds": 0, "max_frame_ms": 0.0}

func _ready() -> void:
	load_world()
	atmosphere = SnowAtmosphere.new()
	add_child(atmosphere)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("res://shaders/terrain.gdshader")
	atmosphere.lit_materials.append(terrain_material)
	atmosphere.apply()
	tree_material = ShaderMaterial.new()
	tree_material.shader = preload("res://shaders/tree.gdshader")
	rock_material = ShaderMaterial.new()
	rock_material.shader = preload("res://shaders/rock.gdshader")
	horizon_material = ShaderMaterial.new()
	horizon_material.shader = preload("res://shaders/backdrop.gdshader")
	for v in [[11, 10.5, 2.9, 9, 0.55, 0.8], [23, 12.5, 2.5, 11, 0.7, 0.95], [37, 8.6, 3.2, 8, 0.45, 0.65], [41, 11.5, 3.0, 10, 0.85, 1.0]]:
		tree_variants.append([SnowMeshes.conifer(v[0], v[1], v[2], v[3], v[4], v[5]), SnowMeshes.conifer_far(v[1], v[2] * 0.95, v[5])])
	for rock_seed in [3, 9, 17, 29]:
		rock_variants.append(SnowMeshes.boulder(rock_seed, 1))
	var n := tiles_per_side() / BLOCK
	for bz in n:
		for bx in n:
			block_cache[Vector2i(bx, bz)] = {}
	build_horizon()
	var start := spawn_point()
	var t0 := Time.get_ticks_msec()
	prepare(start)
	print("MOUNTAIN ", COURSE_ID, " extent=", extent, " summit=", summit, " spawn=", start, " startup_ms=", Time.get_ticks_msec() - t0, " blocks=", blocks.size())

## Worker tasks must never outlive the mountain (they write into its results).
func _exit_tree() -> void:
	for name in pending.keys():
		WorkerThreadPool.wait_for_task_completion(pending[name])
	pending.clear()

func _process(delta: float) -> void:
	plan_timer -= delta
	var p := focus_point()
	var t := tile_of(p)
	if t != last_tile or plan_timer <= 0.0:
		last_tile = t
		plan_timer = 0.4
		plan(p)
	var t0 := Time.get_ticks_usec()
	poll(4.0)
	plant_next()
	stream_stats["max_frame_ms"] = maxf(stream_stats["max_frame_ms"], (Time.get_ticks_usec() - t0) / 1000.0)
	# Never let the rider stand on terrain without collision.
	if focus != null:
		var here := tile_of(focus.global_position)
		if not l0.has(here):
			ensure_ready(focus.global_position, 0)

func focus_point() -> Vector3:
	if focus != null and focus.is_inside_tree():
		var p := focus.global_position
		if focus is CharacterBody3D:
			p += (focus as CharacterBody3D).velocity * Vector3(1, 0, 1) * 2.5
		return p
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else spawn_point()

## Build everything needed around `p` and wait for it (startup, restarts, test fixtures).
func prepare(p: Vector3) -> void:
	last_tile = tile_of(p)
	plan(p)
	while not pending.is_empty():
		poll(1.0e9, true)
		plan(p)
	plant_all()

## Synchronous collision around `p` (radius in tiles), used when the rider is
## placed somewhere new or would outrun the streamer.
func ensure_ready(p: Vector3, radius := 1) -> void:
	var centre := tile_of(p)
	var missing := false
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t := centre + Vector2i(dx, dz)
			if valid_tile(t) and not l0.has(t):
				missing = true
				var key := "l0:%s" % t
				if pending.has(key):
					complete(key)
				else:
					stream_stats["sync_builds"] += 1
					var data := gen_l0(t)
					apply_l0(t, data)
	if missing:
		for bkey in blocks_near(centre, radius):
			request_block(bkey, true)
		plant_all()
		poll(1.0e9, true)

func valid_tile(t: Vector2i) -> bool:
	var n := tiles_per_side()
	return t.x >= 0 and t.y >= 0 and t.x < n and t.y < n

func blocks_near(t: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var b := Vector2i(floori(float(t.x + dx) / BLOCK), floori(float(t.y + dz) / BLOCK))
			if block_cache.has(b) and not b in out:
				out.append(b)
	return out

# ------------------------------------------------------------------ planning
func plan(p: Vector3) -> void:
	var centre := tile_of(p)
	var want_l0 := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var t := centre + Vector2i(dx, dz)
			if valid_tile(t):
				want_l0[t] = true
	var order: Array = want_l0.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - centre).length_squared() < (b - centre).length_squared())
	for t in order:
		if not l0.has(t):
			submit("l0", t, gen_l0.bind(t))
		else:
			l0[t]["retire"] = false
	# Unload L0 tiles two or more tiles away (hysteresis): first give their block
	# its terrain back, then free the nodes when that block mesh is in place.
	for t in l0.keys():
		if maxi(absi(t.x - centre.x), absi(t.y - centre.y)) >= 3:
			l0[t]["retire"] = true
	# Far trees on tiles within the scenery radius.
	var r := int(ceil(SCENERY_RADIUS / TILE)) + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := centre + Vector2i(dx, dz)
			if not valid_tile(t) or far.has(t) or want_l0.has(t) or l0.has(t):
				continue
			if tile_distance(t, p) < SCENERY_RADIUS:
				submit("far", t, gen_scenery.bind(t))
	for t in far.keys():
		if tile_distance(t, p) > SCENERY_RADIUS + 500.0:
			for node in far[t]:
				node.queue_free()
			far.erase(t)
	# Blocks that free retiring collision tiles first, then the nearest blocks.
	for t in l0.keys():
		if l0[t].get("retire", false):
			request_block(Vector2i(floori(float(t.x) / BLOCK), floori(float(t.y) / BLOCK)))
	var blocks_order: Array = block_cache.keys()
	var here := Vector2(p.x, p.z)
	blocks_order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return block_centre(a).distance_squared_to(here) < block_centre(b).distance_squared_to(here))
	for b in blocks_order:
		request_block(b)

func block_centre(b: Vector2i) -> Vector2:
	return Vector2(-extent + (b.x + 0.5) * BLOCK * TILE, -extent + (b.y + 0.5) * BLOCK * TILE)

func tile_distance(t: Vector2i, p: Vector3) -> float:
	var o := tile_origin(t) + Vector2(TILE, TILE) * 0.5
	return o.distance_to(Vector2(p.x, p.z))

func block_composition(b: Vector2i) -> PackedByteArray:
	var comp := PackedByteArray()
	comp.resize(BLOCK * BLOCK)
	var p := focus_point()
	for j in BLOCK:
		for i in BLOCK:
			var t := Vector2i(b.x * BLOCK + i, b.y * BLOCK + j)
			var lod := 2
			if l0.has(t) and not l0[t].get("retire", false):
				lod = 0
			elif tile_distance(t, p) < L1_RADIUS:
				lod = 1
			comp[j * BLOCK + i] = lod
	return comp

func request_block(b: Vector2i, now := false) -> void:
	var comp := block_composition(b)
	var current: Dictionary = blocks.get(b, {})
	if current.get("comp", PackedByteArray()) == comp and not current.is_empty():
		return
	var key := "block:%s" % b
	if pending.has(key):
		if not now:
			return
		complete(key)
		if blocks.get(b, {}).get("comp", PackedByteArray()) == comp:
			return
	submit("block", b, gen_block.bind(b, comp, block_cache[b]), comp, now)
	if now:
		complete(key)

func submit(kind: String, key: Vector2i, job: Callable, extra = null, force := false) -> void:
	var name := "%s:%s" % [kind, key]
	if pending.has(name):
		return
	if pending.size() >= MAX_TASKS and not force:
		return
	var id := WorkerThreadPool.add_task(func() -> void:
		var out: Dictionary = job.call()
		mutex.lock()
		results[name] = out
		mutex.unlock())
	pending[name] = id
	task_info[name] = [kind, key, extra]

## Apply finished work. `budget_ms` limits main-thread time per frame.
func poll(budget_ms: float, wait := false) -> void:
	var start := Time.get_ticks_usec()
	for name in pending.keys():
		if not pending.has(name):
			continue
		if not wait and not WorkerThreadPool.is_task_completed(pending[name]):
			continue
		complete(name)
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			break

## Wait for one task (exactly once) and apply its result.
func complete(name: String) -> void:
	if not pending.has(name):
		return
	WorkerThreadPool.wait_for_task_completion(pending[name])
	pending.erase(name)
	mutex.lock()
	var data: Dictionary = results.get(name, {})
	results.erase(name)
	mutex.unlock()
	var info: Array = task_info[name]
	task_info.erase(name)
	match info[0]:
		"l0":
			if not l0.has(info[1]):
				apply_l0(info[1], data)
		"far":
			if not far.has(info[1]) and not l0.has(info[1]):
				apply_far(info[1], data)
		"block":
			apply_block(info[1], data, info[2])

# ------------------------------------------------------------------ generation (worker threads)
static func gen_l0(t: Vector2i) -> Dictionary:
	var scenery := gen_scenery(t)
	var data := gen_grid(t, L0_CELLS, 3, scenery)
	data["scenery"] = scenery
	return data

## One tile's terrain grid at `cells` per side. B = border rows for normals,
## curvature and lip detection. With `scenery`, ambient occlusion is baked in and
## collision faces are produced.
static func gen_grid(t: Vector2i, cells: int, b: int, scenery = null) -> Dictionary:
	var o := tile_origin(t)
	var step := TILE / cells
	var gw := cells + 1 + b * 2
	var hs := PackedFloat32Array()
	hs.resize(gw * gw)
	for iz in gw:
		for ix in gw:
			hs[iz * gw + ix] = height_at(o.x + (ix - b) * step, o.y + (iz - b) * step)
	var n := cells + 1
	var ao := PackedFloat32Array()
	ao.resize(n * n)
	ao.fill(1.0)
	if scenery != null:
		for h in scenery["hazards"]:
			var reach: float = h.w * 2.8 + 3.0
			var ix0 := int(floor((h.x - reach - o.x) / step))
			var iz0 := int(floor((h.z - reach - o.y) / step))
			for iz in range(maxi(iz0, 0), mini(iz0 + int(reach * 2.0 / step) + 2, n)):
				for ix in range(maxi(ix0, 0), mini(ix0 + int(reach * 2.0 / step) + 2, n)):
					var d := Vector2(o.x + ix * step - h.x, o.y + iz * step - h.z).length()
					if d < reach:
						ao[iz * n + ix] = minf(ao[iz * n + ix], lerpf(0.68, 1.0, d / reach))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	var lip_reach := maxi(1, int(round(24.0 / step)))
	for iz in n:
		for ix in n:
			var g := (iz + b) * gw + ix + b
			var x := o.x + ix * step
			var z := o.y + iz * step
			var h := hs[g]
			var nrm := Vector3(hs[g - 1] - hs[g + 1], 2.0 * step, hs[g - gw] - hs[g + gw]).normalized()
			var curvature := (h - 0.25 * (hs[g - 1] + hs[g + 1] + hs[g - gw] + hs[g + gw])) * (STEP / step)
			var s := surface_from(x, z, nrm.y, curvature)
			# Lips: ground that breaks over far more sharply than its surroundings
			# (convex in ANY direction) is wind-scoured and darker -- a drop ahead.
			var lr := mini(lip_reach, b)
			var around := 0.25 * (hs[g - lr] + hs[g + lr] + hs[g - gw * lr] + hs[g + gw * lr])
			var lip := smoothstep(3.0, 11.0, h - around)
			var rock := maxf(smoothstep(0.22, 0.42, 1.0 - nrm.y), lip * 0.5)
			var i := iz * n + ix
			vertices[i] = Vector3(x, h, z)
			normals[i] = nrm
			colors[i] = Color(s.x, s.y, rock, ao[i] * (1.0 - clampf(-curvature * 0.08, 0.0, 0.18)))
			uvs[i] = Vector2(tree_density(x, z), mask(x, z, MASK_CLIFF))
	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var k := 0
	for iz in cells:
		for ix in cells:
			var a := iz * n + ix
			indices[k] = a; indices[k + 1] = a + 1; indices[k + 2] = a + n
			indices[k + 3] = a + 1; indices[k + 4] = a + n + 1; indices[k + 5] = a + n
			k += 6
	var faces := PackedVector3Array()
	if scenery != null:
		faces.resize(indices.size())
		for i in indices.size():
			faces[i] = vertices[indices[i]]
	add_skirts(vertices, normals, colors, uvs, indices, n, step * 1.5 + 4.0)
	return {"v": vertices, "n": normals, "c": colors, "uv": uvs, "i": indices, "faces": faces}

## Vertical curtains under every tile edge hide cracks between resolutions.
static func add_skirts(v: PackedVector3Array, nm: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, idx: PackedInt32Array, n: int, depth: float) -> void:
	var edges := [[0, 1], [n * (n - 1), 1], [0, n], [n - 1, n]]
	for e in edges:
		var start: int = e[0]
		var stride: int = e[1]
		var base := v.size()
		for i in n:
			var src := start + i * stride
			v.append(v[src] - Vector3(0, depth, 0))
			nm.append(nm[src])
			c.append(c[src])
			uv.append(uv[src])
		for i in n - 1:
			var a := start + i * stride
			var bb := start + (i + 1) * stride
			var a2 := base + i
			var b2 := base + i + 1
			# Both windings, so the curtain shows from either side.
			idx.append_array(PackedInt32Array([a, bb, a2, bb, b2, a2, a, a2, bb, bb, a2, b2]))

## One block (5x5 tiles) merged into a single mesh: L1 or L2 pieces per tile and
## holes where L0 tiles are shown. Pieces are cached per block.
static func gen_block(b: Vector2i, comp: PackedByteArray, cache: Dictionary) -> Dictionary:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in BLOCK:
		for i in BLOCK:
			var lod := comp[j * BLOCK + i]
			if lod == 0:
				continue
			var t := Vector2i(b.x * BLOCK + i, b.y * BLOCK + j)
			var key := "%d,%d,%d" % [t.x, t.y, lod]
			if not cache.has(key):
				cache[key] = gen_grid(t, L1_CELLS if lod == 1 else L2_CELLS, 1)
			var piece: Dictionary = cache[key]
			var offset := v.size()
			v.append_array(piece["v"])
			nm.append_array(piece["n"])
			c.append_array(piece["c"])
			uv.append_array(piece["uv"])
			var pi: PackedInt32Array = piece["i"]
			var start := idx.size()
			idx.append_array(pi)
			for k in range(start, idx.size()):
				idx[k] += offset
	return {"v": v, "n": nm, "c": c, "uv": uv, "i": idx}

## Deterministic scenery for one tile (its own seed: identical whenever and in
## whatever order tiles stream in). Hazard spacing is checked within the tile,
## and nothing is planted within 6 m of a tile edge, so order never matters.
static func gen_scenery(t: Vector2i) -> Dictionary:
	var o := tile_origin(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = 74021 + t.x * 92821 + t.y * 6113
	var looks := RandomNumberGenerator.new()
	looks.seed = 99173 + t.x * 7919 + t.y * 104729
	var spawn := spawn_point()
	var trees := PackedVector4Array()
	var tree_looks := PackedColorArray()     # r variant, g yaw, b stretch, a unused
	var tree_custom := PackedColorArray()
	var rocks: Array = []                    # [variant, Basis, scale Vector3, at Vector3, custom Color, outcrop]
	var hazards := PackedVector4Array()
	for i in 1400:
		var x := o.x + rng.randf_range(6.0, TILE - 6.0)
		var z := o.y + rng.randf_range(6.0, TILE - 6.0)
		var roll := rng.randf()
		var size_roll := rng.randf()
		if roll > tree_density(x, z):
			continue
		if Vector2(x - spawn.x, z - spawn.z).length() < 260.0:
			continue
		if normal_at(x, z).y < 0.83:
			continue
		var h := height_at(x, z)
		# Stunted near the treeline, tall low down.
		var grown := smoothstep(summit.y - 1700.0, summit.y - 2900.0, h)
		var s := lerpf(0.45, 1.0, grown) + size_roll * lerpf(0.4, 1.1, grown)
		trees.append(Vector4(x, h, z, s))
		tree_looks.append(Color(looks.randi() % 4, looks.randf() * TAU, looks.randf_range(0.92, 1.12), 0))
		tree_custom.append(Color(looks.randf_range(0.75, 1.15), looks.randf(), looks.randf(), 0))
		hazards.append(Vector4(x, h, z, SnowMeshes.TRUNK_RADIUS * s))
	var tree_hazards := hazards.size()
	for i in 260:
		var x := o.x + rng.randf_range(6.0, TILE - 6.0)
		var z := o.y + rng.randf_range(6.0, TILE - 6.0)
		var roll := rng.randf()
		var size_roll := rng.randf()
		var spin := rng.randf() * TAU
		var h := height_at(x, z)
		if roll > rock_density(x, z, h):
			continue
		if Vector2(x - spawn.x, z - spawn.z).length() < 120.0 or normal_at(x, z).y < 0.75:
			continue
		var s := 1.2 + pow(size_roll, 2.2) * 5.5 * (1.0 + 0.6 * mask(x, z, MASK_CLIFF))
		var at := Vector3(x, h + s * 0.2, z)
		# Boulders never touch or pinch: there is always a rideable gap.
		var clear := true
		for other in hazards:
			if Vector2(other.x - x, other.z - z).length() < s * 1.8 + 3.5 + other.w:
				clear = false
				break
		if not clear:
			continue
		rocks.append([looks.randi() % 4, Basis.from_euler(Vector3(0.15, spin, 0.1)), Vector3(s * 1.3, s, s), at, Color(looks.randf(), looks.randf(), 0, 0), false])
		# Unit boulders reach ~1.4 from their centre; record the real footprint.
		hazards.append(Vector4(at.x, at.y, at.z, s * 1.3 * 1.4))
	# Craggy outcrops break up cliff risers and steep walls so they read as stone.
	for i in 200:
		var x := o.x + rng.randf_range(6.0, TILE - 6.0)
		var z := o.y + rng.randf_range(6.0, TILE - 6.0)
		var nrm := normal_at(x, z)
		var s := rng.randf_range(3.5, 9.0)
		var sx := rng.randf_range(1.0, 1.8)
		var sy := rng.randf_range(0.5, 0.9)
		var sz := rng.randf_range(0.8, 1.3)
		var yaw := rng.randf() * TAU
		var variant := rng.randi() % 4
		if nrm.y > 0.62:
			continue
		var up := nrm.lerp(Vector3.UP, 0.35).normalized()
		var basis := Basis(Vector3.UP, yaw)
		var axis := Vector3.UP.cross(up)
		if axis.length() > 0.001:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(up)) * basis
		var at := Vector3(x, height_at(x, z), z) - nrm * s * 0.25
		rocks.append([variant, basis, Vector3(s * sx, s * sy, s * sz), at, Color(rng.randf(), rng.randf(), 0, 0), true])
		hazards.append(Vector4(at.x, at.y, at.z, s * maxf(sx, sz) * 1.4))
	return {"trees": trees, "tree_looks": tree_looks, "tree_custom": tree_custom, "rocks": rocks, "hazards": hazards, "tree_hazards": tree_hazards}

# ------------------------------------------------------------------ applying (main thread)
func arrays_mesh(data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["v"]
	arrays[Mesh.ARRAY_NORMAL] = data["n"]
	arrays[Mesh.ARRAY_COLOR] = data["c"]
	arrays[Mesh.ARRAY_TEX_UV] = data["uv"]
	arrays[Mesh.ARRAY_INDEX] = data["i"]
	var mesh := ArrayMesh.new()
	if (data["v"] as PackedVector3Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func apply_l0(t: Vector2i, data: Dictionary) -> void:
	if far.has(t):
		for node in far[t]:
			node.queue_free()
		far.erase(t)
	var nodes: Array = []
	var surface := MeshInstance3D.new()
	surface.mesh = arrays_mesh(data)
	surface.material_override = terrain_material
	surface.visible = false              # shown when its block has made the hole
	add_child(surface)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(data["faces"])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	nodes.append(body)
	l0[t] = {"mesh": surface, "nodes": nodes}
	# Trees and rocks follow on a later frame (the tile is still far ahead), so a
	# tile never costs one long frame. Fixtures and startup plant at once.
	planting.append([t, data["scenery"]])
	stream_stats["l0_built"] += 1

## Plant one step of one tile's scenery per call (main thread): its trees on one
## frame, its rocks on the next, so no single frame does it all.
func plant_next() -> void:
	while not planting.is_empty():
		var job: Array = planting[0]
		var t: Vector2i = job[0]
		if not l0.has(t) or l0[t].get("planted", false):
			planting.pop_front()
			continue
		var stage: int = l0[t].get("stage", 0)
		l0[t]["nodes"].append_array(plant(t, job[1], true, stage))
		l0[t]["stage"] = stage + 1
		if stage >= 1:
			l0[t]["planted"] = true
			planting.pop_front()
		return

func plant_all() -> void:
	while not planting.is_empty():
		plant_next()

func apply_far(t: Vector2i, data: Dictionary) -> void:
	far[t] = plant(t, data, false)

## Trees (and, near the rider, rocks) for a tile. With `solid`, colliders and
## hazard records are made too.
func plant(t: Vector2i, scenery: Dictionary, solid: bool, stage := -1) -> Array:
	var nodes: Array = []
	if solid and stage == 1:
		return plant_rocks(t, scenery)
	# Level of detail is chosen per batch by its distance to the camera, so the
	# trees are batched per 320 m quarter of the tile (near meshes: 4 variants;
	# far: one shared simple mesh). A whole-tile batch would show far trees
	# right next to the rider whenever the tile's centre was far away.
	var near_x: Array = []
	var near_c: Array = []
	var far_x: Array = [[], [], [], []]
	var far_c: Array = [[], [], [], []]
	for q in 4:
		near_x.append([[], [], [], []])
		near_c.append([[], [], [], []])
	var origin := tile_origin(t)
	var trees: PackedVector4Array = scenery["trees"]
	var looks: PackedColorArray = scenery["tree_looks"]
	var custom: PackedColorArray = scenery["tree_custom"]
	var tree_body: StaticBody3D = null
	if solid:
		tree_body = StaticBody3D.new()
		tree_body.collision_layer = 2
		tree_body.set_meta("hazard", "tree")
	for i in trees.size():
		var tr := trees[i]
		var s := tr.w
		var variant := int(looks[i].r)
		var xf := Transform3D(Basis(Vector3.UP, looks[i].g).scaled(Vector3(s, s * looks[i].b, s)), Vector3(tr.x, tr.y - 0.3, tr.z))
		var quarter := (1 if tr.x - origin.x >= TILE * 0.5 else 0) + (2 if tr.z - origin.y >= TILE * 0.5 else 0)
		near_x[quarter][variant].append(xf)
		near_c[quarter][variant].append(custom[i])
		far_x[quarter].append(xf)
		far_c[quarter].append(custom[i])
		if solid:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = SnowMeshes.TRUNK_RADIUS * s
			cylinder.height = SnowMeshes.TRUNK_SOLID_HEIGHT * s
			var collision := CollisionShape3D.new()
			collision.shape = cylinder
			collision.position = Vector3(tr.x, tr.y, tr.z) + Vector3.UP * (SnowMeshes.TRUNK_SOLID_HEIGHT * 0.5 * s - 0.3)
			tree_body.add_child(collision)
	for q in 4:
		if solid:
			for v in 4:
				var xs: Array[Transform3D] = []
				xs.assign(near_x[q][v])
				var cs: Array[Color] = []
				cs.assign(near_c[q][v])
				nodes.append(batch(tree_variants[v][0], xs, cs, tree_material, 0.0, TREE_NEAR_RANGE))
		var fx: Array[Transform3D] = []
		fx.assign(far_x[q])
		var fc: Array[Color] = []
		fc.assign(far_c[q])
		nodes.append(batch(tree_variants[0][1], fx, fc, tree_material, TREE_NEAR_RANGE if solid else 0.0, TREE_FAR_RANGE, false))
	if solid:
		if tree_body.get_child_count() > 0:
			add_child(tree_body)
			nodes.append(tree_body)
		else:
			tree_body.free()
		tree_count += trees.size()
		if stage == -1:
			nodes.append_array(plant_rocks(t, scenery))
	return nodes.filter(func(node): return node != null)

## Rocks and outcrops (visuals + convex colliders) and the tile's hazard records.
func plant_rocks(t: Vector2i, scenery: Dictionary) -> Array:
	var nodes: Array = []
	var stones := StaticBody3D.new()
	stones.collision_layer = 2
	stones.set_meta("hazard", "rock")
	var rx: Array = [[], [], [], []]
	var rc: Array = [[], [], [], []]
	for r in scenery["rocks"]:
		var variant: int = r[0]
		var basis: Basis = r[1]
		var scale_vec: Vector3 = r[2]
		var at: Vector3 = r[3]
		rx[variant].append(Transform3D(basis.scaled_local(scale_vec), at))
		rc[variant].append(r[4])
		var points := PackedVector3Array()
		for p in rock_variants[variant][1]:
			points.append(p * scale_vec)
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		var collision := CollisionShape3D.new()
		collision.shape = hull
		collision.transform = Transform3D(basis, at)
		stones.add_child(collision)
		if r[5]:
			outcrop_count += 1
		else:
			rock_count += 1
	if stones.get_child_count() > 0:
		add_child(stones)
		nodes.append(stones)
	else:
		stones.free()
	for v in 4:
		var xs: Array[Transform3D] = []
		xs.assign(rx[v])
		var cs: Array[Color] = []
		cs.assign(rc[v])
		nodes.append(batch(rock_variants[v][0], xs, cs, rock_material, 0.0, ROCK_RANGE))
	var hz: PackedVector4Array = scenery["hazards"]
	hazard_buckets[t] = hz
	tree_buckets[t] = hz.slice(0, scenery["tree_hazards"])
	return nodes.filter(func(node): return node != null)

func batch(mesh: Mesh, transforms: Array[Transform3D], custom: Array[Color], mat: Material, range_begin: float, range_end: float, shadows := true) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	# Compatibility renderer multiplies vertex COLOR by the instance colour; keep it white.
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		multi.set_instance_custom_data(i, custom[i])
		multi.set_instance_color(i, Color.WHITE)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = mat
	instance.visibility_range_begin = range_begin
	instance.visibility_range_end = range_end
	instance.visibility_range_end_margin = 40.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func apply_block(b: Vector2i, data: Dictionary, comp: PackedByteArray) -> void:
	var entry: Dictionary = blocks.get(b, {})
	var node: MeshInstance3D = entry.get("node", null)
	if node == null:
		node = MeshInstance3D.new()
		node.material_override = terrain_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	node.mesh = arrays_mesh(data)
	blocks[b] = {"node": node, "comp": comp}
	stream_stats["blocks_built"] += 1
	# Show L0 tiles exactly where this block now has holes; retire the rest.
	for j in BLOCK:
		for i in BLOCK:
			var t := Vector2i(b.x * BLOCK + i, b.y * BLOCK + j)
			if not l0.has(t):
				continue
			if comp[j * BLOCK + i] == 0:
				(l0[t]["mesh"] as MeshInstance3D).visible = true
			elif l0[t].get("retire", false):
				unload_l0(t)

func unload_l0(t: Vector2i) -> void:
	var entry: Dictionary = l0[t]
	(entry["mesh"] as Node).queue_free()
	for node in entry["nodes"]:
		if is_instance_valid(node):
			node.queue_free()
	l0.erase(t)
	hazard_buckets.erase(t)
	tree_buckets.erase(t)

## Distant ranges beyond the baked area: one coarse ring, no collision.
func build_horizon() -> void:
	const STEP_H := 2000.0
	const OUT := 48000.0
	var n := int(OUT * 2.0 / STEP_H) + 1
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for iz in n:
		for ix in n:
			var x := -OUT + ix * STEP_H
			var z := -OUT + iz * STEP_H
			var edge := maxf(absf(x), absf(z))
			var inner := macro(clampf(x, -extent, extent), clampf(z, -extent, extent)) - 45.0
			var far_h := 1100.0 + 2300.0 * (_far_noise.get_noise_2d(x, z) * 0.5 + 0.5)
			verts[iz * n + ix] = Vector3(x, lerpf(inner, far_h, smoothstep(extent, extent + 9000.0, edge)), z)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for iz in n:
		for ix in n:
			var l := verts[iz * n + maxi(ix - 1, 0)]
			var rr := verts[iz * n + mini(ix + 1, n - 1)]
			var u := verts[maxi(iz - 1, 0) * n + ix]
			var d := verts[mini(iz + 1, n - 1) * n + ix]
			normals[iz * n + ix] = (d - u).cross(rr - l).normalized()
	var indices := PackedInt32Array()
	for iz in n - 1:
		for ix in n - 1:
			var x0 := -OUT + ix * STEP_H
			var z0 := -OUT + iz * STEP_H
			if x0 >= -extent and x0 + STEP_H <= extent and z0 >= -extent and z0 + STEP_H <= extent:
				continue
			var a := iz * n + ix
			indices.append_array(PackedInt32Array([a, a + 1, a + n, a + 1, a + n + 1, a + n]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "Horizon"
	instance.mesh = mesh
	instance.material_override = horizon_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

# ------------------------------------------------------------------ queries
func tiles_around(at: Vector3, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := tile_of(at - Vector3(radius, 0, radius))
	var b := tile_of(at + Vector3(radius, 0, radius))
	for tz in range(a.y, b.y + 1):
		for tx in range(a.x, b.x + 1):
			out.append(Vector2i(tx, tz))
	return out

## Solid hazards (trees, boulders, outcrops) within `radius` metres horizontally
## (loaded near the rider only).
func hazards_near(at: Vector3, radius: float, trees_only := false) -> Array[Vector4]:
	var found: Array[Vector4] = []
	var source := tree_buckets if trees_only else hazard_buckets
	for t in tiles_around(at, radius):
		if not source.has(t):
			continue
		for h in source[t]:
			if Vector2(h.x - at.x, h.z - at.z).length() <= radius + h.w:
				found.append(h)
	return found

func all_hazards() -> Array[Vector4]:
	var found: Array[Vector4] = []
	for key in hazard_buckets:
		for h in hazard_buckets[key]:
			found.append(h)
	return found
