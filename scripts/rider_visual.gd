class_name SnowRiderVisual
extends Node3D
var board_material: StandardMaterial3D
var body: Node3D
var lamp: OmniLight3D

func _ready() -> void:
	board_material = mat(Color("101925"))
	board_material.emission_enabled = true
	part(self, Vector3(0, -0.59, 0), Vector3(0.34, 0.09, 1.7), board_material)
	# Rounded nose and tail identify the long downhill axis.
	for z in [-0.82, 0.82]:
		var tip := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.17
		mesh.height = 0.12
		tip.mesh = mesh
		tip.position = Vector3(0, -0.55, z)
		tip.material_override = board_material
		add_child(tip)
	body = Node3D.new()
	add_child(body)
	var pants := mat(Color("182735"))
	var jacket := mat(Color("e47732"))
	var boot := mat(Color("24282b"))
	# Sideways stance across the board, knees bent, arms forward/back for balance.
	for z in [-0.38, 0.38]:
		part(body, Vector3(0, -0.47, z), Vector3(0.38, 0.18, 0.19), boot)
		limb(body, Vector3(0.03, -0.38, z), Vector3(-0.19, 0.0, z * 0.8), 0.13, pants)
		limb(body, Vector3(-0.19, 0.0, z * 0.8), Vector3(0.02, 0.33, 0), 0.15, pants)
	part(body, Vector3(0, 0.52, 0), Vector3(0.43, 0.58, 0.5), jacket)
	limb(body, Vector3(0, 0.7, -0.27), Vector3(-0.14, 0.3, -0.61), 0.10, jacket)
	limb(body, Vector3(0, 0.7, 0.27), Vector3(0.24, 0.38, 0.58), 0.10, jacket)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.23
	sphere.height = 0.46
	head.mesh = sphere
	head.position = Vector3(0.03, 1.02, 0.07)
	head.material_override = mat(Color("253345"))
	body.add_child(head)
	part(body, Vector3(0.05, 1.04, 0.26), Vector3(0.32, 0.12, 0.10), mat(Color("72d5e3")))
	lamp = OmniLight3D.new()
	lamp.position = Vector3(0, -0.4, 0)
	lamp.omni_range = 3.0
	lamp.light_color = Color("ff731b")
	lamp.shadow_enabled = false
	add_child(lamp)

func mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	return material

func part(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)

func limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 8
	instance.mesh = cylinder
	instance.position = (a + b) * 0.5
	instance.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	instance.material_override = material
	parent.add_child(instance)

func animate(delta: float, charge: float, steer: float, tuck: float, grab: bool, recovering: float) -> void:
	var warm := Color("ff6514").lerp(Color("fff1bd"), maxf(0, charge - 0.65) / 0.35)
	board_material.albedo_color = Color("101925").lerp(warm, charge)
	board_material.emission = warm
	board_material.emission_energy_multiplier = charge * 3.2
	lamp.light_energy = charge * 1.5
	body.rotation.z = lerp_angle(body.rotation.z, steer * 0.25 + recovering * 1.3, 1.0 - exp(-10 * delta))
	body.position.y = lerpf(body.position.y, -tuck * 0.25 - (0.25 if grab else 0.0), 1.0 - exp(-10 * delta))
	body.rotation.x = lerpf(body.rotation.x, -0.22 if grab else tuck * 0.15, 1.0 - exp(-10 * delta))
