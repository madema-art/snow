class_name SnowMountain
extends Node3D
## All units metres. Real topography, no checkpoint or coordinate death barriers.
const LENGTH := 9360.0
const DISTANCE_SCALE := 1.2
const WIDTH := 1200.0
const STEP := 8.0
const FINISH := 9180.0
const COURSE_ID := "massif_v2"
const CHUNK := 200.0
const TREE_NEAR_RANGE := 420.0
const TREE_FAR_RANGE := 2600.0
const ROCK_RANGE := 1600.0
var terrain_material: ShaderMaterial
var tree_material: ShaderMaterial
var rock_material: ShaderMaterial
var tree_variants: Array = []      # [near mesh, far mesh, scale-free height]
var rock_variants: Array = []      # [mesh, unit points]
var tree_count := 0
var rock_count := 0
var outcrop_count := 0
## Every solid hazard as Vector4(x, y, z, radius), bucketed per 200 m chunk for
## cheap neighbourhood queries (audio whooshes, tests, AO baking).
var hazard_buckets: Dictionary = {}
var tree_buckets: Dictionary = {}
var atmosphere: SnowAtmosphere

static func band(v: float, lo: float, hi: float, feather: float) -> float:
	return smoothstep(lo - feather, lo, v) * (1.0 - smoothstep(hi, hi + feather, v))

static func height_at(x: float, distance: float) -> float:
	var z := distance / DISTANCE_SCALE
	# No speed cap or time padding: over 3.1 km of vertical descent to the finish.
	var h := 3300.0 - 0.34 * distance
	h += 8.0 * sin(z / 240.0) + 2.0 * sin(z / 64.0)
	h += 0.00019 * x * x + 4.0 * sin(x / 110.0) * sin(z / 180.0)
	# Broad summit, then a transverse gorge with BOTH west/east snow shoulders.
	var spur := exp(-pow((x - 120.0) / 22.0, 4.0))
	var gorge_z := z - 24.0 * sin(x / 85.0)
	var gorge := lerpf(band(gorge_z, 1480, 1570, 18), band(gorge_z, 1494, 1514, 8), spur)
	h -= 100.0 * band(x, -215, 215, 35) * gorge
	# A real snow lip on the narrow rock spur supports a difficult ollie shortcut.
	h += 6.0 * exp(-pow((gorge_z - 1479.0) / 14.0, 2.0)) * exp(-pow((x - 120.0) / 25.0, 4.0))
	# Cliff region's tilted rock buttress. Routes around both ends and a narrow chute.
	var buttress := band(x, -70, 330, 55) * (1.0 - exp(-pow((x - 120.0) / 19.0, 4.0)))
	h += 58.0 * buttress * exp(-pow((z - 2310.0) / 72.0, 4.0))
	# Forest rolls, allowing broad corridors rather than a marked single track.
	h += 5.0 * sin(x / 65.0 + z / 145.0) * band(z, 2900, 4600, 240)
	# A broken left-side escarpment demands a traverse before dropping to lower forest.
	h -= 85.0 * band(x, -470, 85, 30) * band(z - 18.0*sin(x/95.0), 4220, 4310, 16)
	# Broken mountain: large gullies, spines and natural launches, blending into final bowl.
	var broken := band(z, 4750, 6370, 200)
	h += broken * (12.0 * sin(x / 72.0 + z / 125.0) + 4.0 * sin(z / 43.0))
	h -= 92.0 * band(x, -120, 235, 24) * band(z - 22.0*sin(x/75.0), 5440, 5520, 16)
	h -= 85.0 * band(x, -170, 490, 25) * band(z - 18.0*sin(x/90.0), 6270, 6340, 16)
	# These ramps are optional faster lines; a cautious rider can ride around them.
	for ramp in [Vector2(-80, 1150), Vector2(210, 3320), Vector2(-270, 5070), Vector2(290, 5920), Vector2(0, 6970)]:
		h += 5.0 * exp(-pow((z - ramp.y) / 22.0, 2.0)) * exp(-pow((x - ramp.x) / 36.0, 4.0))
	# Visible perimeter cornices plunge into real lower slopes. No fatal X threshold.
	h -= maxf(0.0, absf(x) - 520.0) * 1.8
	return h

static func normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x - 1, z) - height_at(x + 1, z), 2, height_at(x, z - 1) - height_at(x, z + 1)).normalized()

## Snow surface character under the board: x = soft powder, y = wind-scoured ice.
## Powder collects in sheltered forest and gully bottoms; ice forms on exposed,
## steep, convex ground. The terrain shader paints the same values (vertex colour),
## so what the rider SEES is what the board FEELS and HEARS.
static func surface_at(x: float, distance: float) -> Vector2:
	var h := height_at(x, distance)
	var curvature := h - 0.25 * (height_at(x - STEP, distance) + height_at(x + STEP, distance) + height_at(x, distance - STEP) + height_at(x, distance + STEP))
	return surface_from(x, distance, normal_at(x, distance).y, curvature)

static func surface_from(x: float, distance: float, normal_y: float, curvature: float) -> Vector2:
	var z := distance / DISTANCE_SCALE
	var patch := 0.5 + 0.5 * sin(x / 53.0 + sin(z / 71.0) * 2.0) * sin(z / 97.0 + x / 140.0)
	var forest := band(z, 2800, 4700, 250)
	var exposed := 1.0 - forest
	var steep := 1.0 - normal_y
	var ice := clampf(smoothstep(0.07, 0.24, steep) * 0.65 + smoothstep(0.15, 1.0, curvature) * 0.7 + (patch - 0.62) * 1.3 * exposed, 0.0, 1.0)
	var powder := clampf(forest * 0.55 + smoothstep(0.15, 1.0, -curvature) * 0.65 + (0.42 - patch) * 0.9, 0.0, 1.0) * (1.0 - ice)
	return Vector2(powder, ice)

static func region(distance: float) -> String:
	var z := distance / DISTANCE_SCALE
	if z < 1100: return "Summit"
	if z < 2800: return "Cliffs"
	if z < 4700: return "Forest"
	if z < 6500: return "Broken Mountain"
	return "Final Descent"

func _ready() -> void:
	atmosphere = SnowAtmosphere.new()
	add_child(atmosphere)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("res://shaders/terrain.gdshader")
	tree_material = ShaderMaterial.new()
	tree_material.shader = preload("res://shaders/tree.gdshader")
	rock_material = ShaderMaterial.new()
	rock_material.shader = preload("res://shaders/rock.gdshader")
	# Tree variants: [seed, height, width, tiers, droop, snow]. Heights are per unit scale.
	for v in [[11, 10.5, 2.9, 9, 0.55, 0.8], [23, 12.5, 2.5, 11, 0.7, 0.95], [37, 8.6, 3.2, 8, 0.45, 0.65], [41, 11.5, 3.0, 10, 0.85, 1.0]]:
		tree_variants.append([SnowMeshes.conifer(v[0], v[1], v[2], v[3], v[4], v[5]), SnowMeshes.conifer_far(v[1], v[2] * 0.95, v[5])])
	for seed in [3, 9, 17, 29]:
		rock_variants.append(SnowMeshes.boulder(seed, 1))
	var starts: Array[float] = []
	for start in range(-200, 9600, 200):
		starts.append(float(start))
	for start in starts:
		make_scenery(start)
	for start in starts:
		make_outcrops(start)
	for start in starts:
		make_chunk(start)
	make_finish()
	add_child(SnowBackdrop.new())
	print("MOUNTAIN ", COURSE_ID, " length=", LENGTH, " width=", WIDTH, " trees=", tree_count, " rocks=", rock_count, " outcrops=", outcrop_count)

static func bucket(z: float) -> int:
	return int(floor(z / CHUNK))

func add_hazard(at: Vector3, radius: float, is_tree: bool) -> void:
	var key := bucket(at.z)
	if not hazard_buckets.has(key):
		hazard_buckets[key] = PackedVector4Array()
	hazard_buckets[key].append(Vector4(at.x, at.y, at.z, radius))
	if is_tree:
		if not tree_buckets.has(key):
			tree_buckets[key] = PackedVector4Array()
		tree_buckets[key].append(Vector4(at.x, at.y, at.z, radius))

## Solid hazards (trees, boulders, outcrops) within `radius` metres horizontally.
func hazards_near(at: Vector3, radius: float, trees_only := false) -> Array[Vector4]:
	var found: Array[Vector4] = []
	var source := tree_buckets if trees_only else hazard_buckets
	for key in range(bucket(at.z - radius), bucket(at.z + radius) + 1):
		if not source.has(key):
			continue
		for h in source[key]:
			if Vector2(h.x - at.x, h.z - at.z).length() <= radius + h.w:
				found.append(h)
	return found

func all_hazards() -> Array[Vector4]:
	var found: Array[Vector4] = []
	for key in hazard_buckets:
		for h in hazard_buckets[key]:
			found.append(h)
	return found

func make_chunk(start: float) -> void:
	# Indexed grid computes each height once (with a border for normals, curvature
	# and lip detection); rendered and collision triangles are identical.
	const NX := 150
	const NZ := 25
	const B := 3
	var gw := NX + 1 + B * 2
	var gh := NZ + 1 + B * 2
	var heights := PackedFloat32Array()
	heights.resize(gw * gh)
	for iz in gh:
		for ix in gw:
			heights[iz * gw + ix] = height_at(-WIDTH * 0.5 + (ix - B) * STEP, start + (iz - B) * STEP)
	# Ambient occlusion pooled around trunks and boulders (baked into vertex alpha).
	var ao := PackedFloat32Array()
	ao.resize((NX + 1) * (NZ + 1))
	ao.fill(1.0)
	for h in hazards_near(Vector3(0, 0, start + CHUNK * 0.5), CHUNK * 0.5 + 12.0):
		var reach := h.w * 2.8 + 3.0
		var ix0 := int(floor((h.x - reach + WIDTH * 0.5) / STEP))
		var iz0 := int(floor((h.z - reach - start) / STEP))
		for iz in range(maxi(iz0, 0), mini(iz0 + int(reach * 2.0 / STEP) + 2, NZ + 1)):
			for ix in range(maxi(ix0, 0), mini(ix0 + int(reach * 2.0 / STEP) + 2, NX + 1)):
				var d := Vector2(-WIDTH * 0.5 + ix * STEP - h.x, start + iz * STEP - h.z).length()
				if d < reach:
					ao[iz * (NX + 1) + ix] = minf(ao[iz * (NX + 1) + ix], lerpf(0.68, 1.0, d / reach))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize((NX + 1) * (NZ + 1))
	normals.resize(vertices.size())
	colors.resize(vertices.size())
	for iz in NZ + 1:
		for ix in NX + 1:
			var g := (iz + B) * gw + ix + B
			var x := -WIDTH * 0.5 + ix * STEP
			var z := start + iz * STEP
			var h := heights[g]
			var n := Vector3(heights[g - 1] - heights[g + 1], 2.0 * STEP, heights[g - gw] - heights[g + gw]).normalized()
			var curvature := h - 0.25 * (heights[g - 1] + heights[g + 1] + heights[g - gw] + heights[g + gw])
			var s := surface_from(x, z, n.y, curvature)
			# Lips: snow that falls away far faster than the grade ahead is wind-scoured
			# and darker, telegraphing a drop long before the rider reaches it.
			var drop := h - heights[g + gw * B] - 0.34 * STEP * B
			var side_drop := maxf(h - heights[g - B], h - heights[g + B]) - 2.5
			var lip := smoothstep(5.0, 14.0, maxf(drop, side_drop))
			var rock := maxf(smoothstep(0.22, 0.42, 1.0 - n.y), lip * 0.5)
			var occlusion := ao[iz * (NX + 1) + ix] * (1.0 - clampf(-curvature * 0.08, 0.0, 0.18))
			var i := iz * (NX + 1) + ix
			vertices[i] = Vector3(x, h, z)
			normals[i] = n
			colors[i] = Color(s.x, s.y, rock, occlusion)
	for iz in NZ:
		for ix in NX:
			var a := iz * (NX + 1) + ix
			indices.append_array(PackedInt32Array([a, a + 1, a + NX + 1, a + 1, a + NX + 2, a + NX + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	surface.material_override = terrain_material
	add_child(surface)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)

func batch(mesh: Mesh, transforms: Array[Transform3D], custom: Array[Color], mat: Material, range_begin: float, range_end: float, shadows := true) -> void:
	if transforms.is_empty(): return
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

func make_scenery(start: float) -> void:
	# Hazard layout uses the same seeded sequence as pass 2 so route knowledge holds;
	# a second generator only decides looks (variant, yaw, snow load).
	var rng := RandomNumberGenerator.new()
	rng.seed = 74021 + int(start) * 13
	var looks := RandomNumberGenerator.new()
	looks.seed = 99173 + int(start) * 7
	var tree_near: Array = [[], [], [], []]
	var tree_custom: Array = [[], [], [], []]
	var rocks: Array = [[], [], [], []]
	var rock_custom: Array = [[], [], [], []]
	var trees := StaticBody3D.new()
	trees.name = "Trees%d" % int(start)
	trees.collision_layer = 2
	trees.set_meta("hazard", "tree")
	var stones := StaticBody3D.new()
	stones.name = "Rocks%d" % int(start)
	stones.collision_layer = 2
	stones.set_meta("hazard", "rock")
	var geo_start := start / DISTANCE_SCALE
	var forest := geo_start >= 2800 and geo_start < 4700
	var count := 280 if forest else (40 if geo_start > 1000 else 4)
	var planted: Array[Vector4] = []
	for i in count:
		var z := rng.randf_range(start, start + 200)
		var x := rng.randf_range(-495, 495)
		if absf(x-120) < 25 and z > 1430*DISTANCE_SCALE and z < 1600*DISTANCE_SCALE: continue
		var lane_a := -180.0 + 95.0 * sin((z / DISTANCE_SCALE - 2800) / 300.0)
		var lane_b := 260.0 + 65.0 * sin(z / DISTANCE_SCALE / 180.0)
		# Two winding forest corridors. Neither is a straight central protected lane.
		if forest and (absf(x - lane_a) < 20 or absf(x - lane_b) < 15): continue
		if normal_at(x, z).y < 0.83 or z < 150 or z > FINISH - 150: continue
		var s := rng.randf_range(1, 2.1) if forest else rng.randf_range(0.8, 1.5)
		planted.append(Vector4(x, height_at(x, z), z, s))
	# Final-descent valley: timbered flanks frame an open, fast centre bowl.
	if geo_start >= 6500:
		var valley := RandomNumberGenerator.new()
		valley.seed = 5150 + int(start)
		for i in 70:
			var z := valley.randf_range(start, start + 200)
			var side := -1.0 if valley.randf() < 0.5 else 1.0
			var x := side * valley.randf_range(330, 505)
			if normal_at(x, z).y < 0.83 or z < 150 or z > FINISH - 40: continue
			planted.append(Vector4(x, height_at(x, z), z, valley.randf_range(0.9, 1.8)))
	for t in planted:
		var at := Vector3(t.x, t.y, t.z)
		var s := t.w
		var variant := looks.randi() % 4
		var yaw := looks.randf() * TAU
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * looks.randf_range(0.92, 1.12), s)), at - Vector3.UP * 0.3)
		tree_near[variant].append(xf)
		tree_custom[variant].append(Color(looks.randf_range(0.75, 1.15), looks.randf(), looks.randf(), 0))
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = SnowMeshes.TRUNK_RADIUS * s
		cylinder.height = SnowMeshes.TRUNK_SOLID_HEIGHT * s
		collision.shape = cylinder
		collision.position = at + Vector3.UP * (SnowMeshes.TRUNK_SOLID_HEIGHT * 0.5 * s - 0.3)
		trees.add_child(collision)
		add_hazard(at, cylinder.radius, true)
		tree_count += 1
	for i in (28 if geo_start > 1100 and geo_start < 6500 else 7):
		var z := rng.randf_range(start, start + 200)
		var x := rng.randf_range(-490, 490)
		if absf(x-120) < 40 and z > 1430*DISTANCE_SCALE and z < 1600*DISTANCE_SCALE: continue
		if normal_at(x, z).y < 0.75 or z < 180 or z > FINISH - 120: continue
		var s := rng.randf_range(1.3, 4.0)
		if geo_start > 1100 and geo_start < 2800: s *= 2.5
		var scale_vec := Vector3(s * 1.3, s, s)
		var rotation_basis := Basis.from_euler(Vector3(0.15, rng.randf() * TAU, 0.1))
		var at := Vector3(x, height_at(x, z) + s * 0.2, z)
		add_rock(stones, rocks, rock_custom, looks.randi() % 4, rotation_basis, scale_vec, at, looks)
	if trees.get_child_count() > 0: add_child(trees)
	else: trees.free()
	if stones.get_child_count() > 0: add_child(stones)
	else: stones.free()
	for v in 4:
		var xs: Array[Transform3D] = []
		xs.assign(tree_near[v])
		var cs: Array[Color] = []
		cs.assign(tree_custom[v])
		batch(tree_variants[v][0], xs, cs, tree_material, 0.0, TREE_NEAR_RANGE)
		batch(tree_variants[v][1], xs, cs, tree_material, TREE_NEAR_RANGE, TREE_FAR_RANGE, false)
		var rx: Array[Transform3D] = []
		rx.assign(rocks[v])
		var rc: Array[Color] = []
		rc.assign(rock_custom[v])
		batch(rock_variants[v][0], rx, rc, rock_material, 0.0, ROCK_RANGE)

## One faceted rock: identical vertices for the visual instance and the convex hull.
func add_rock(stones: StaticBody3D, rocks: Array, custom: Array, variant: int, rotation_basis: Basis, scale_vec: Vector3, at: Vector3, looks: RandomNumberGenerator) -> void:
	rocks[variant].append(Transform3D(rotation_basis.scaled_local(scale_vec), at))
	custom[variant].append(Color(looks.randf(), looks.randf(), 0, 0))
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	var radius := 0.0
	for p in rock_variants[variant][1]:
		points.append(p * scale_vec)
		radius = maxf(radius, Vector2(p.x * scale_vec.x, p.z * scale_vec.z).length())
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(rotation_basis, at)
	stones.add_child(collision)
	add_hazard(at, radius * 0.85, false)
	rock_count += 1

## Craggy outcrops break up steep gorge walls, buttress faces and escarpments so
## cliffs read as stone from far away. Each is a solid convex rock.
func make_outcrops(start: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33091 + int(start) * 11
	var stones := StaticBody3D.new()
	stones.name = "Outcrops%d" % int(start)
	stones.collision_layer = 2
	stones.set_meta("hazard", "rock")
	var rocks: Array = [[], [], [], []]
	var custom: Array = [[], [], [], []]
	for i in 160:
		var x := rng.randf_range(-590, 590)
		var z := rng.randf_range(start, start + CHUNK)
		var n := normal_at(x, z)
		if n.y > 0.62 or z < 60 or z > FINISH - 100:
			continue
		var s := rng.randf_range(3.5, 9.0)
		var up := n.lerp(Vector3.UP, 0.35).normalized()
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		var axis := Vector3.UP.cross(up)
		if axis.length() > 0.001:
			basis = Basis(axis.normalized(), Vector3.UP.angle_to(up)) * basis
		var scale_vec := Vector3(s * rng.randf_range(1.0, 1.8), s * rng.randf_range(0.5, 0.9), s * rng.randf_range(0.8, 1.3))
		var at := Vector3(x, height_at(x, z), z) - n * s * 0.25
		add_rock(stones, rocks, custom, rng.randi() % 4, basis, scale_vec, at, rng)
		outcrop_count += 1
	if stones.get_child_count() > 0: add_child(stones)
	else: stones.free()
	for v in 4:
		var rx: Array[Transform3D] = []
		rx.assign(rocks[v])
		var rc: Array[Color] = []
		rc.assign(custom[v])
		batch(rock_variants[v][0], rx, rc, rock_material, 0.0, ROCK_RANGE)

func material(color: Color, rough := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat

func box(at: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.rotation = rot
	add_child(node)
	return node

func post(at: Vector3, radius: float, height: float, mat: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.9
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = mat
	node.position = at + Vector3.UP * height * 0.5
	add_child(node)

## Natural valley finish: timber gate with a banner, pennant lines funnelling the
## last 250 m, a timing hut and a snow-level line. Visible from far up the bowl.
## Decorative only (no colliders): the gate stands outside the |x|<50 finish span.
func make_finish() -> void:
	var timber := material(Color("5a3f2b"))
	var dark_timber := material(Color("3a281c"))
	var banner := material(Color("e2552a"), 0.7)
	var cloth := material(Color("f2efe6"), 0.8)
	var snow_roof := material(Color("eef2f6"), 0.8)
	var h0 := height_at(0, FINISH)
	for x in [-56.0, 56.0]:
		var h := height_at(x, FINISH)
		for dx in [-1.6, 1.6]:
			post(Vector3(x + dx, h - 1.0, FINISH), 0.45, 19.0, timber)
		for y in [4.0, 9.0, 14.0]:
			box(Vector3(x, h + y, FINISH), Vector3(3.6, 0.35, 0.35), dark_timber, Vector3(0, 0, 0.5))
	# Cross beam and banner spanning the gate.
	box(Vector3(0, h0 + 17.5, FINISH), Vector3(118, 0.9, 0.9), timber)
	box(Vector3(0, h0 + 14.2, FINISH), Vector3(60, 5.2, 0.25), banner)
	box(Vector3(0, h0 + 14.2, FINISH + 0.05), Vector3(57, 4.4, 0.2), cloth)
	var sign := Label3D.new()
	sign.text = "FINISH"
	sign.font_size = 160
	sign.outline_size = 0
	sign.modulate = Color("c8431f")
	sign.pixel_size = 0.03
	sign.position = Vector3(0, h0 + 14.2, FINISH - 0.2)
	sign.rotation.y = PI
	add_child(sign)
	# Snow-level finish line.
	for i in 24:
		var x := -57.5 + i * 5
		box(Vector3(x, height_at(x, FINISH) + 0.03, FINISH), Vector3(5, 0.06, 1.2), banner if i % 2 == 0 else cloth)
	# Pennant lines funnel the final approach (outside the riding span).
	for z in range(int(FINISH - 260), int(FINISH), 20):
		for x in [-70.0, 70.0]:
			var h := height_at(x, z)
			post(Vector3(x, h - 0.5, z), 0.12, 4.0, dark_timber)
			box(Vector3(x, h + 2.8, z + 10.0), Vector3(0.05, 0.05, 20.0), dark_timber)
			for k in 4:
				box(Vector3(x, h + 2.45, z + 2.5 + k * 5.0), Vector3(0.05, 0.7, 0.9), banner if k % 2 == 0 else cloth, Vector3(0, 0, 0))
	# Timing hut beside the gate.
	var hx := -95.0
	var hh := height_at(hx, FINISH + 18)
	box(Vector3(hx, hh + 2.0, FINISH + 18), Vector3(8, 4.5, 6), timber)
	box(Vector3(hx, hh + 4.9, FINISH + 18), Vector3(9.4, 0.5, 7.4), snow_roof, Vector3(0, 0, 0.25))
	box(Vector3(hx + 4.05, hh + 2.2, FINISH + 18), Vector3(0.1, 1.2, 3.0), material(Color("f7c56b"), 0.3))
