class_name SnowBackdrop
extends Node3D
## The surrounding massif: deep side valleys and serrated ridges either side of the
## course, the summit falling away behind the start and a far range closing the
## valley beyond the finish. One coarse indexed mesh (150 x 200 m cells, ridged
## noise), shared collision so a rider who leaves the course falls onto real
## ground instead of through scenery. It sits a few metres under the course
## edge so the playable mesh always wins.
const X_EXTENT := 9000.0
const Z_MIN := -7000.0
const Z_MAX := 21000.0
const DX := 150.0
const DZ := 200.0
var ridges := FastNoiseLite.new()
var detail := FastNoiseLite.new()

func _ready() -> void:
	ridges.seed = 840
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	ridges.frequency = 0.00042
	detail.seed = 841
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.fractal_octaves = 3
	detail.frequency = 0.0021
	build()

func course_base(z: float) -> float:
	return 3300.0 - 0.34 * clampf(z, -200.0, 9600.0)

func backdrop_height(x: float, z: float) -> float:
	var ax := absf(x)
	var inside_z := z > -200.0 and z < 9600.0
	var r := ridges.get_noise_2d(x, z) * 0.5 + 0.5
	var d := detail.get_noise_2d(x, z)
	if ax < 600.0 and inside_z:
		return course_base(z) - 600.0
	var h := 0.0
	if ax <= 600.0:
		if z <= -200.0:
			h = SnowMountain.height_at(x, -200.0) - 6.0 - (-200.0 - z) * 0.5
		else:
			h = SnowMountain.height_at(x, 9600.0) - 6.0 - (z - 9600.0) * 0.07
	else:
		var edge := SnowMountain.height_at(signf(x) * 600.0, clampf(z, -200.0, 9600.0)) - 6.0
		var t := ax - 600.0
		var valley := -minf(t, 650.0) * 0.75
		var rise := smoothstep(500.0, 3000.0, t) * (1300.0 + r * 1500.0)
		var far := smoothstep(4500.0, 8500.0, t) * -500.0
		h = edge + valley + rise + far + d * 90.0 * smoothstep(200.0, 1200.0, t)
		if z < -200.0:
			h -= (-200.0 - z) * 0.3 * (1.0 - smoothstep(600.0, 3000.0, t))
		elif z > 9600.0:
			h -= (z - 9600.0) * 0.06
	# A far range closes the valley beyond the finish; another rises behind the summit.
	h += smoothstep(12500.0, 17500.0, z) * (1500.0 + r * 1200.0) * (1.0 - smoothstep(5000.0, 8500.0, ax))
	h += smoothstep(-2600.0, -6000.0, z) * (900.0 + r * 900.0)
	return h

func build() -> void:
	var nx := int(X_EXTENT * 2.0 / DX) + 1
	var nz := int((Z_MAX - Z_MIN) / DZ) + 1
	var vertices := PackedVector3Array()
	vertices.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var x := -X_EXTENT + ix * DX
			var z := Z_MIN + iz * DZ
			vertices[iz * nx + ix] = Vector3(x, backdrop_height(x, z), z)
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for iz in nz:
		for ix in nx:
			var l := vertices[iz * nx + maxi(ix - 1, 0)]
			var rr := vertices[iz * nx + mini(ix + 1, nx - 1)]
			var u := vertices[maxi(iz - 1, 0) * nx + ix]
			var dd := vertices[mini(iz + 1, nz - 1) * nx + ix]
			normals[iz * nx + ix] = (dd - u).cross(rr - l).normalized()
	var indices := PackedInt32Array()
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var x0 := -X_EXTENT + ix * DX
			var z0 := Z_MIN + iz * DZ
			# Skip cells completely under the playable course.
			if x0 >= -600.0 and x0 + DX <= 600.0 and z0 >= -200.0 and z0 + DZ <= 9600.0:
				continue
			indices.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/backdrop.gdshader")
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
