class_name SnowMountain
extends Node3D
## All units metres. Real topography, no checkpoint or coordinate death barriers.
const LENGTH := 9360.0
const DISTANCE_SCALE := 1.2
const WIDTH := 1200.0
const STEP := 8.0
const FINISH := 9180.0
const COURSE_ID := "massif_v2"
var snow_material: ShaderMaterial
var rock_mesh: SphereMesh
var rock_mat: StandardMaterial3D
var tree_count := 0
var rock_count := 0

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

static func region(distance: float) -> String:
	var z := distance / DISTANCE_SCALE
	if z < 1100: return "Summit"
	if z < 2800: return "Cliffs"
	if z < 4700: return "Forest"
	if z < 6500: return "Broken Mountain"
	return "Final Descent"

func _ready() -> void:
	make_environment()
	snow_material = ShaderMaterial.new()
	snow_material.shader = preload("res://scripts/snow.gdshader")
	rock_mesh = SphereMesh.new()
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 4
	rock_mesh.radius = 1
	rock_mesh.height = 2
	rock_mat = material(Color("526170"))
	for start in range(-200, 9600, 200):
		make_chunk(float(start))
		make_scenery(float(start))
	make_finish()
	make_backdrop()
	print("MOUNTAIN ", COURSE_ID, " length=", LENGTH, " width=", WIDTH, " trees=", tree_count, " rocks=", rock_count)

func make_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("325a87")
	sky_mat.sky_horizon_color = Color("b6d3e5")
	sky_mat.ground_horizon_color = Color("b6d3e5")
	sky_mat.ground_bottom_color = Color("50657a")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("bed9f4")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("9cbacf")
	env.fog_density = 0.00022
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -38, 0)
	sun.light_color = Color("fff0d3")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 145
	add_child(sun)

func make_chunk(start: float) -> void:
	# Indexed grid computes each vertex once; identical rendered/collision topology.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	const NX := 150
	const NZ := 25
	for iz in NZ + 1:
		for ix in NX + 1:
			var x := -WIDTH * 0.5 + ix * STEP
			var z := start + iz * STEP
			var n := normal_at(x, z)
			vertices.append(Vector3(x, height_at(x, z), z))
			normals.append(n)
			var shade := 0.92 + 0.035 * sin(z / 120.0) * cos(x / 70.0)
			colors.append(Color(shade, shade + 0.025, 1) if n.y > 0.68 else Color("586573"))
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
	surface.material_override = snow_material
	add_child(surface)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat

func batch(mesh: Mesh, transforms: Array[Transform3D], mat: Material) -> void:
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = mat
	instance.visibility_range_end = 1250
	add_child(instance)

func tree(at: Vector3, s: float) -> void:
	var body := StaticBody3D.new()
	body.position = at + Vector3.UP * 2.4 * s
	body.collision_layer = 2
	body.set_meta("hazard", "tree")
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.5 * s
	cylinder.height = 4.8 * s
	collision.shape = cylinder
	body.add_child(collision)
	add_child(body)
	tree_count += 1

func make_scenery(start: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 74021 + int(start) * 13
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var geo_start := start / DISTANCE_SCALE
	var forest := geo_start >= 2800 and geo_start < 4700
	var count := 280 if forest else (40 if geo_start > 1000 else 4)
	for i in count:
		var z := rng.randf_range(start, start + 200)
		var x := rng.randf_range(-495, 495)
		if absf(x-120) < 25 and z > 1430*DISTANCE_SCALE and z < 1600*DISTANCE_SCALE: continue
		var lane_a := -180.0 + 95.0 * sin((z / DISTANCE_SCALE - 2800) / 300.0)
		var lane_b := 260.0 + 65.0 * sin(z / DISTANCE_SCALE / 180.0)
		# Two winding forest corridors. Neither is a straight central protected lane.
		if forest and (absf(x - lane_a) < 20 or absf(x - lane_b) < 15): continue
		if normal_at(x, z).y < 0.83 or z < 150 or z > FINISH - 150: continue
		var at := Vector3(x, height_at(x, z), z)
		var s := rng.randf_range(1, 2.1) if forest else rng.randf_range(0.8, 1.5)
		trunks.append(Transform3D(Basis().scaled(Vector3.ONE * s), at + Vector3.UP * 2.4 * s))
		crowns.append(Transform3D(Basis().scaled(Vector3.ONE * s), at + Vector3.UP * 5 * s))
		caps.append(Transform3D(Basis().scaled(Vector3.ONE * s), at + Vector3.UP * 5.65 * s))
		tree(at, s)
	for i in (28 if geo_start > 1100 and geo_start < 6500 else 7):
		var z := rng.randf_range(start, start + 200)
		var x := rng.randf_range(-490, 490)
		if absf(x-120) < 40 and z > 1430*DISTANCE_SCALE and z < 1600*DISTANCE_SCALE: continue
		if normal_at(x, z).y < 0.75 or z < 180 or z > FINISH - 120: continue
		var s := rng.randf_range(1.3, 4.0)
		if geo_start > 1100 and geo_start < 2800: s *= 2.5
		var scale_vec := Vector3(s * 1.3, s, s)
		var rotation_basis := Basis.from_euler(Vector3(0.15, rng.randf() * TAU, 0.1))
		var at := Vector3(x, height_at(x, z) + s * 0.35, z)
		rocks.append(Transform3D(rotation_basis.scaled_local(scale_vec), at))
		# Bake actual faceted rock vertices into convex collision; no oversized capsule.
		var body := StaticBody3D.new()
		body.transform = Transform3D(rotation_basis, at)
		body.collision_layer = 2
		body.set_meta("hazard", "rock")
		var shape := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for p in rock_mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]: points.append(p * scale_vec)
		shape.points = points
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		rock_count += 1
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.5
	trunk.bottom_radius = 0.5
	trunk.height = 4.8
	trunk.radial_segments = 8
	batch(trunk, trunks, material(Color("443a35")))
	var crown := CylinderMesh.new()
	crown.top_radius = 0
	crown.bottom_radius = 2.8
	crown.height = 7
	crown.radial_segments = 7
	batch(crown, crowns, material(Color("193f48")))
	var cap := CylinderMesh.new()
	cap.top_radius = 0
	cap.bottom_radius = 2.2
	cap.height = 5.8
	cap.radial_segments = 7
	batch(cap, caps, material(Color("d2e1eb")))
	batch(rock_mesh, rocks, rock_mat)

func box(at: Vector3, size: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	add_child(node)

func make_finish() -> void:
	var orange := material(Color("ee5c29"))
	var dark := material(Color("163447"))
	for x in [-50.0, 50.0]:
		var h := height_at(x, FINISH)
		box(Vector3(x, h + 8, FINISH), Vector3(1, 16, 1), orange)
		box(Vector3(x * 0.9, h + 12, FINISH), Vector3(10, 5, 0.3), orange)
	for i in 20:
		var x := -47.5 + i * 5
		box(Vector3(x, height_at(x, FINISH) + 0.04, FINISH), Vector3(5, 0.08, 4), dark if i % 2 == 0 else orange)
	var sign := Label3D.new()
	sign.text = "F I N I S H"
	sign.font_size = 96
	sign.pixel_size = 0.06
	sign.position = Vector3(0, height_at(0, FINISH) + 12, FINISH)
	sign.rotation.y = PI
	add_child(sign)
	for z in [FINISH - 200, FINISH - 100, FINISH - 40]:
		for x in [-48.0, 48.0]:
			box(Vector3(x, height_at(x, z) + 3, z), Vector3(0.2, 6, 0.2), dark)
			box(Vector3(x, height_at(x, z) + 5, z), Vector3(2, 1.5, 0.2), orange)

func make_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 840
	for i in 24:
		var z := -600.0 + i * 400
		for side in [-1, 1]:
			var peak := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0
			cone.bottom_radius = rng.randf_range(600, 1000)
			cone.height = rng.randf_range(900, 1600)
			cone.radial_segments = 7
			peak.mesh = cone
			peak.position = Vector3(side * rng.randf_range(1500, 2100), height_at(0, z) - 200, z)
			peak.material_override = material(Color("9bafc3"))
			add_child(peak)

