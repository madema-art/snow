class_name SnowRiderVisual
extends Node3D
## Procedural snowboarder: shaped board with real thickness, camber and upturned
## tips, bindings (base plates, highbacks, straps), boots, baggy pants, layered
## jacket, gloves, helmet and goggles. Limbs are posed every frame with analytic
## two-bone IK against the bindings, so knees absorb terrain, hips drop into a
## tuck, the whole rig inclines into carves and hands reach for real grabs.
## The board's own glow is the ONLY nitro indicator.
var rider: SnowRider
var board_material: StandardMaterial3D
var lamp: OmniLight3D
var lean_pivot: Node3D
var rig: Node3D
var parts: Dictionary = {}
var time := 0.0
var crouch := 0.35
var crouch_vel := 0.0
var lean := 0.0
var torso_pitch := 0.0
var torso_twist := 0.0
var head_turn := 0.0
var arm_front := Vector3.ZERO
var arm_back := Vector3.ZERO
var flail := 0.0
var charge_shown := 0.0
var getup_from := Transform3D()
var getup_captured := false
var lying_weight := 0.0

const STANCE := 0.26           # half stance width along the board (m)
const THIGH := 0.45
const SHIN := 0.45
const UPPER_ARM := 0.3
const FOREARM := 0.29
const BOARD_Y := -0.62         # board top relative to body origin (capsule centre)

func _ready() -> void:
	lean_pivot = Node3D.new()
	lean_pivot.position = Vector3(0, BOARD_Y, 0)
	add_child(lean_pivot)
	rig = Node3D.new()
	lean_pivot.add_child(rig)
	board_material = StandardMaterial3D.new()
	board_material.albedo_color = Color("141a22")
	board_material.roughness = 0.35
	board_material.metallic = 0.15
	board_material.emission_enabled = true
	board_material.emission = Color("ff6514")
	board_material.emission_energy_multiplier = 0.0
	build_board()
	build_body()
	lamp = OmniLight3D.new()
	lamp.position = Vector3(0, BOARD_Y + 0.15, 0)
	lamp.omni_range = 3.5
	lamp.omni_attenuation = 1.4
	lamp.light_color = Color("ff731b")
	lamp.light_energy = 0.0
	lamp.shadow_enabled = false
	add_child(lamp)
	refresh_charge(0.0)

# ---------------------------------------------------------------- materials
func mat(color: Color, rough := 0.75, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

func mesh_part(key: String, mesh: Mesh, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	(rig if parent == null else parent).add_child(instance)
	parts[key] = instance
	return instance

func capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0 + 0.01)
	c.radial_segments = 12
	c.rings = 4
	return c

func rounded_box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

# ---------------------------------------------------------------- board
func board_half_width(t: float) -> float:
	# t in -1..1 along the board; sidecut waist, wide rounded nose/tail.
	var sidecut := 0.124 + 0.022 * t * t
	var tip := absf(t)
	if tip > 0.86:
		var k := (tip - 0.86) / 0.14
		sidecut *= sqrt(maxf(0.0, 1.0 - k * k * 0.92))
	return sidecut

func board_rise(t: float) -> float:
	var tip := absf(t)
	var kick := 0.0 if tip < 0.8 else pow((tip - 0.8) / 0.2, 2.0) * 0.085
	return kick - 0.006 * (1.0 - t * t) # slight camber under the feet

func build_board() -> void:
	const N := 40
	const LENGTH := 1.56
	const THICK := 0.022
	var top := PackedVector3Array()
	var top_n := PackedVector3Array()
	var base := PackedVector3Array()
	var base_n := PackedVector3Array()
	var rim := PackedVector3Array()
	var rim_n := PackedVector3Array()
	var outline_l: Array[Vector3] = []
	var outline_r: Array[Vector3] = []
	for i in N + 1:
		var t := -1.0 + 2.0 * i / N
		var z := t * LENGTH * 0.5
		var w := board_half_width(t)
		var y := board_rise(t)
		outline_l.append(Vector3(-w, y, z))
		outline_r.append(Vector3(w, y, z))
	for i in N:
		var a0 := outline_l[i]
		var a1 := outline_l[i + 1]
		var b0 := outline_r[i]
		var b1 := outline_r[i + 1]
		var up := (a1 - a0).cross(b0 - a0).normalized()
		if up.y < 0: up = -up
		for v in [a0, b0, a1, b0, b1, a1]:
			top.append(v + Vector3(0, THICK, 0))
			top_n.append(up)
		for v in [a0, a1, b0, b0, a1, b1]:
			base.append(v)
			base_n.append(-up)
		for pair in [[a0, a1, -1.0], [b0, b1, 1.0]]:
			var p0: Vector3 = pair[0]
			var p1: Vector3 = pair[1]
			var side := Vector3(pair[2], 0, 0)
			var quad := [p0, p1, p1 + Vector3(0, THICK, 0), p0, p1 + Vector3(0, THICK, 0), p0 + Vector3(0, THICK, 0)]
			if pair[2] < 0:
				quad = [p0, p1 + Vector3(0, THICK, 0), p1, p0, p0 + Vector3(0, THICK, 0), p1 + Vector3(0, THICK, 0)]
			for v in quad:
				rim.append(v)
				rim_n.append(side)
	var mesh := ArrayMesh.new()
	for surface in [[top, top_n], [rim, rim_n], [base, base_n]]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface[0]
		arrays[Mesh.ARRAY_NORMAL] = surface[1]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var board := MeshInstance3D.new()
	board.mesh = mesh
	board.set_surface_override_material(0, board_material)
	board.set_surface_override_material(1, board_material)
	board.set_surface_override_material(2, mat(Color("0b0d10"), 0.25, 0.4))
	rig.add_child(board)
	parts["board"] = board
	# Bindings: base plate, heel cup/highback and two straps per foot.
	var binding_mat := mat(Color("202428"), 0.5, 0.2)
	var strap_mat := mat(Color("b8bec4"), 0.45, 0.3)
	for side in [1.0, -1.0]:
		var foot := Node3D.new()
		foot.position = Vector3(0, THICK + 0.012, side * STANCE)
		foot.rotation.y = deg_to_rad(15.0 if side > 0 else -6.0)
		rig.add_child(foot)
		mesh_part("plate%d" % side, rounded_box(Vector3(0.27, 0.018, 0.13)), binding_mat, foot)
		var highback := mesh_part("highback%d" % side, rounded_box(Vector3(0.025, 0.2, 0.15)), binding_mat, foot)
		highback.position = Vector3(0.115, 0.11, 0)
		highback.rotation.z = 0.22
		for strap_x in [-0.08, 0.02]:
			var strap := mesh_part("strap%d_%s" % [side, strap_x], rounded_box(Vector3(0.05, 0.035, 0.15)), strap_mat, foot)
			strap.position = Vector3(strap_x, 0.1 if strap_x > 0 else 0.07, 0)
		var boot := mesh_part("boot%d" % side, capsule(0.075, 0.3), mat(Color("2b2f33"), 0.8), foot)
		boot.rotation.z = PI * 0.5
		boot.position = Vector3(-0.015, 0.07, 0)
		boot.scale = Vector3(1.0, 1.0, 1.15)

# ---------------------------------------------------------------- body
func build_body() -> void:
	var pants := mat(Color("23272e"), 0.9)
	var jacket := mat(Color("b8262f"), 0.8)
	var jacket_dark := mat(Color("3a1418"), 0.85)
	var glove := mat(Color("15171a"), 0.7)
	var helmet := mat(Color("e9ebe6"), 0.4)
	var lens := mat(Color("e09a2c"), 0.08, 0.85)
	var skin := mat(Color("1c1f24"), 0.9) # neck gaiter / face mask
	for leg in ["front", "back"]:
		mesh_part("thigh_" + leg, capsule(0.1, THIGH + 0.12), pants)
		mesh_part("shin_" + leg, capsule(0.088, SHIN + 0.08), pants)
		mesh_part("knee_" + leg, capsule(0.095, 0.2), pants)
	mesh_part("pelvis", capsule(0.15, 0.4), pants)
	mesh_part("torso", capsule(0.19, 0.6), jacket)
	mesh_part("jacket_hem", capsule(0.2, 0.42), jacket_dark)
	mesh_part("collar", capsule(0.115, 0.24), jacket_dark)
	mesh_part("pack", rounded_box(Vector3(0.12, 0.34, 0.26)), jacket_dark)
	for arm in ["front", "back"]:
		mesh_part("upper_" + arm, capsule(0.075, UPPER_ARM + 0.1), jacket)
		mesh_part("fore_" + arm, capsule(0.066, FOREARM + 0.08), jacket)
		var g := SphereMesh.new()
		g.radius = 0.06
		g.height = 0.12
		mesh_part("glove_" + arm, g, glove)
	var head := SphereMesh.new()
	head.radius = 0.135
	head.height = 0.27
	mesh_part("helmet", head, helmet)
	mesh_part("gaiter", capsule(0.1, 0.2), skin)
	var goggle := rounded_box(Vector3(0.05, 0.075, 0.2))
	mesh_part("goggles", goggle, lens)
	var band := CylinderMesh.new()
	band.top_radius = 0.138
	band.bottom_radius = 0.138
	band.height = 0.035
	band.radial_segments = 16
	mesh_part("goggle_strap", band, mat(Color("111111"), 0.7))

# ---------------------------------------------------------------- posing helpers
func place_segment(key: String, a: Vector3, b: Vector3) -> void:
	var node: MeshInstance3D = parts[key]
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)

func two_bone(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var to := target - root
	var d := clampf(to.length(), 0.05, l1 + l2 - 0.002)
	var dir := to.normalized() if to.length() > 0.0001 else Vector3.DOWN
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	var pole_dir := (pole - dir * pole.dot(dir))
	pole_dir = pole_dir.normalized() if pole_dir.length() > 0.0001 else Vector3.LEFT
	return root + dir * a + pole_dir * h

func reach(root: Vector3, target: Vector3, max_len: float) -> Vector3:
	var to := target - root
	return root + to.limit_length(max_len)

# ---------------------------------------------------------------- state
func refresh_charge(charge: float) -> void:
	if board_material == null:
		return
	charge = clampf(charge, 0.0, 1.0)
	charge_shown = charge
	var warm := Color("ff5a0e").lerp(Color("fff3c4"), maxf(0.0, charge - 0.6) / 0.4)
	board_material.albedo_color = Color("141a22").lerp(warm.darkened(0.35), charge)
	board_material.emission = warm
	var flare := 1.0
	if rider != null and rider.boosting:
		flare = 1.25 + 0.2 * sin(time * 47.0)
	board_material.emission_energy_multiplier = charge * charge * 4.5 * flare + charge * 0.8
	lamp.light_energy = charge * 1.6 * flare

func reset_pose(start: Basis) -> void:
	basis = start
	position = Vector3.ZERO
	top_level = false
	crouch = 0.1
	crouch_vel = 0.0
	lean = 0.0
	flail = 0.0
	getup_captured = false
	lying_weight = 0.0
	lean_pivot.rotation = Vector3.ZERO
	refresh_charge(0.0)
	pose(0.0)

## Called by the rider every physics step with the desired board orientation.
func update_pose(delta: float, target: Basis, on_ground: bool) -> void:
	time += delta
	var r := rider
	var recovering := r.recovery > 0.0 or (r.run.state == "ended" and r.fatal_crash)
	if recovering:
		top_level = true
		if r.getup_started and r.recovery > 0.0:
			if not getup_captured:
				getup_from = global_transform
				getup_captured = true
			var g := smoothstep(0.0, 1.0, 1.0 - r.recovery / SnowTuning.GETUP_TIME)
			var upright := Transform3D(r.basis_for(SnowMountain.normal_at(r.position.x, r.position.z), r.heading), r.global_position)
			global_transform = getup_from.interpolate_with(upright, g)
			flail = lerpf(flail, 0.0, 1.0 - exp(-8.0 * delta))
			crouch = lerpf(0.95, 0.4, g)
			lying_weight = 1.0 - g
		else:
			getup_captured = false
			global_transform = Transform3D(r.tumble_basis, r.tumble_pos)
			flail = lerpf(flail, clampf(r.tumble_vel.length() / 6.0, 0.0, 1.0), 1.0 - exp(-6.0 * delta))
			crouch = lerpf(crouch, 0.6, 1.0 - exp(-4.0 * delta))
			lying_weight = lerpf(lying_weight, 1.0 - flail, 1.0 - exp(-3.0 * delta))
		lean_pivot.rotation = lean_pivot.rotation.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
		pose(delta)
		return
	if top_level:
		top_level = false
		position = Vector3.ZERO
		getup_captured = false
	flail = 0.0
	lying_weight = 0.0
	basis = basis.slerp(target.orthonormalized(), 1.0 - exp(-(14.0 if on_ground else 9.0) * delta)).orthonormalized()
	# Inclination into the carve follows the actual lateral acceleration.
	var target_lean := 0.0
	if on_ground and r.run.state != "ready":
		target_lean = clampf(-atan2(r.speed * r.yaw_rate, SnowTuning.GRAVITY) * 0.9, -0.95, 0.95)
		target_lean -= r.brake_input * 0.22 * clampf(r.speed / 10.0, 0.0, 1.0)
		# Deep carve and over-lean: the body drops toward the snow, nearly laid out
		# just before the edge washes out (the only "warning light" there is).
		target_lean += signf(r.steer) * (r.plume * 0.12 + r.over_lean * 0.55)
	lean = lerpf(lean, target_lean, 1.0 - exp(-9.0 * delta))
	# Board chatter on hard, icy snow at speed (tiny, visual only).
	var chatter := 0.0
	if on_ground and r.run.state == "running":
		chatter = r.surface.y * clampf((r.speed - 12.0) / 25.0, 0.0, 1.0) * 0.018 * (sin(time * 61.0) + 0.6 * sin(time * 97.0))
	lean_pivot.rotation = Vector3(chatter, 0, lean)
	# Crouch: athletic stance, tuck, ollie preload, pop extension and landing absorb.
	var target_crouch := 0.35
	if r.run.state == "ready":
		target_crouch = 0.12 + 0.02 * sin(time * 1.7)
	elif on_ground:
		target_crouch = 0.33 + r.tuck_input * 0.5 + r.ollie_preload * 0.45 + r.brake_input * 0.15 + absf(lean) * 0.25
		target_crouch += clampf(r.speed / 45.0, 0.0, 1.0) * 0.08
		if r.pop_time < 0.2:
			target_crouch = -0.15
	else:
		target_crouch = 0.45 + (0.35 if Input.is_action_pressed("grab") else 0.0) + absf(r.flip_rate) * 0.06 + absf(r.spin_rate) * 0.025
		if r.pop_time < 0.18:
			target_crouch = -0.15
	# Landing compression: a spring the knees absorb.
	if r.land_time < 0.02:
		crouch_vel += r.land_impact * 6.5
	crouch_vel += (target_crouch - crouch) * 140.0 * delta
	crouch_vel *= exp(-17.0 * delta)
	crouch = clampf(crouch + crouch_vel * delta, -0.2, 1.15)
	pose(delta)

func pose(delta: float) -> void:
	var r := rider
	var k := clampf(1.0 - exp(-10.0 * delta), 0.0, 1.0) if delta > 0.0 else 1.0
	var on_ground := r == null or r.ground_contact or r.run.state == "ready"
	var grab := r != null and not on_ground and Input.is_action_pressed("grab") and r.recovery <= 0.0
	var tuck := r.tuck_input if r != null else 0.0
	var carve := r.steer if r != null else 0.0
	# Hips: centred between the bindings, lower with crouch, shifted toward the
	# toe edge (-X) and toward the nose at speed.
	var crouch_c := clampf(crouch, -0.2, 1.15)
	var hip_h := lerpf(0.98, 0.48, clampf(crouch_c, 0.0, 1.0)) + maxf(0.0, -crouch_c) * 0.25
	if grab:
		hip_h = 0.55
	var pelvis := Vector3(-0.06 - crouch_c * 0.05 - tuck * 0.05, hip_h, 0.02 + tuck * 0.05)
	var t_pitch := 0.18 + crouch_c * 0.32 + tuck * 0.35 + (0.25 if grab else 0.0)
	var t_twist := 0.32 + carve * 0.18 + tuck * 0.15
	if r != null and not on_ground:
		t_twist += clampf(r.spin_rate * 0.07, -0.4, 0.4)
	torso_pitch = lerpf(torso_pitch, t_pitch, k)
	torso_twist = lerpf(torso_twist, t_twist, k)
	# Spine basis: lean forward toward the toe side (-X), twist shoulders toward the nose.
	var spine_basis := Basis(Vector3.UP, torso_twist) * Basis(Vector3.BACK, torso_pitch)
	var spine_up := spine_basis * Vector3.UP
	var chest := pelvis + spine_up * 0.46
	var neck := pelvis + spine_up * 0.66
	var shoulder_axis := spine_basis * Vector3.BACK
	var facing := spine_basis * Vector3.LEFT
	# Legs: two-bone IK from hip sockets to the bindings, knees toward the toe edge.
	for leg in ["front", "back"]:
		var s := 1.0 if leg == "front" else -1.0
		var hip := pelvis + shoulder_axis * (0.1 * s)
		var ankle := Vector3(-0.015, 0.11, s * STANCE)
		var pole := Vector3(-1.0, 0.25, -s * 0.35)
		var knee := two_bone(hip, ankle, THIGH, SHIN, pole)
		place_segment("thigh_" + leg, hip, knee)
		place_segment("shin_" + leg, knee, ankle)
		place_segment("knee_" + leg, knee - (knee - hip).normalized() * 0.05, knee + (ankle - knee).normalized() * 0.05)
	place_segment("pelvis", pelvis + shoulder_axis * 0.12, pelvis - shoulder_axis * 0.12)
	place_segment("torso", pelvis + spine_up * 0.12, chest + spine_up * 0.02)
	# Jacket hem flutters in the airstream as speed builds.
	var wind := 0.0 if r == null else clampf(r.speed / 35.0, 0.0, 1.3)
	var flap := (sin(time * 23.0) * 0.6 + sin(time * 37.0) * 0.4) * 0.03 * wind
	place_segment("jacket_hem", pelvis + spine_up * 0.02 + shoulder_axis * flap, pelvis + spine_up * 0.22 - facing * flap * 0.5)
	place_segment("collar", neck - spine_up * 0.06, neck + spine_up * 0.04)
	var pack: MeshInstance3D = parts["pack"]
	pack.transform = Transform3D(spine_basis, chest - spine_up * 0.12 - facing * 0.2)
	# Head stays level-ish and looks toward the direction of travel (the nose).
	var turn_target := 1.1 + (0.0 if r == null else clampf(-r.yaw_rate * 0.25, -0.3, 0.3))
	if r != null and r.run.state == "ready":
		turn_target = 0.9 + 0.5 * sin(time * 0.37)
	head_turn = lerpf(head_turn, turn_target, k)
	var head_basis := Basis(Vector3.UP, head_turn) * Basis(Vector3.BACK, -0.1)
	var head_pos := neck + Vector3.UP * 0.15
	var helmet: MeshInstance3D = parts["helmet"]
	helmet.transform = Transform3D(head_basis.scaled(Vector3(1.0, 1.05, 0.95)), head_pos)
	var look := head_basis * Vector3.LEFT
	var goggles: MeshInstance3D = parts["goggles"]
	goggles.transform = Transform3D(head_basis, head_pos + look * 0.115 + Vector3.UP * 0.01)
	var strap: MeshInstance3D = parts["goggle_strap"]
	strap.transform = Transform3D(head_basis, head_pos + Vector3.UP * 0.01)
	place_segment("gaiter", neck, head_pos - Vector3.UP * 0.06 + look * 0.03)
	# Arms.
	var lean_v := lean
	var front_target := chest + spine_basis * Vector3(-0.25, -0.2, 0.55)
	var back_target := chest + spine_basis * Vector3(0.05, -0.35, -0.5)
	if on_ground:
		# Inside hand reaches toward the snow in a hard carve.
		if lean_v > 0.25:
			front_target = front_target.lerp(Vector3(-0.75, 0.15, 0.25), clampf((lean_v - 0.25) * 1.6, 0.0, 0.8))
		elif lean_v < -0.25:
			back_target = back_target.lerp(Vector3(0.65, 0.2, -0.35), clampf((-lean_v - 0.25) * 1.6, 0.0, 0.8))
		if tuck > 0.05:
			front_target = front_target.lerp(chest + Vector3(-0.42, -0.25, 0.22), tuck)
			back_target = back_target.lerp(chest + Vector3(-0.4, -0.28, 0.02), tuck)
		if r != null and r.run.state == "ready":
			front_target = chest + spine_basis * Vector3(-0.08, -0.5, 0.25)
			back_target = chest + spine_basis * Vector3(0.05, -0.52, -0.22)
	else:
		if grab:
			# Indy: back hand to the toe edge between the bindings.
			back_target = Vector3(-0.15, 0.1, -0.02)
			front_target = chest + spine_basis * Vector3(-0.2, 0.25, 0.6)
		elif r != null and absf(r.spin_rate) > 0.5:
			var wrap := signf(r.spin_rate)
			front_target = chest + spine_basis * Vector3(-0.35, 0.0, 0.25 * wrap)
			back_target = chest + spine_basis * Vector3(-0.3, 0.0, -0.25 * wrap)
		elif r != null and absf(r.flip_rate) > 0.5:
			front_target = chest + Vector3(-0.35, -0.35, 0.18)
			back_target = chest + Vector3(-0.35, -0.38, -0.12)
		else:
			front_target = chest + spine_basis * Vector3(-0.15, 0.05, 0.6)
			back_target = chest + spine_basis * Vector3(0.1, 0.0, -0.6)
	if flail > 0.01:
		var w := time * 11.0
		front_target = front_target.lerp(chest + Vector3(-0.2 + sin(w) * 0.3, 0.35 + cos(w * 1.3) * 0.25, 0.55), flail)
		back_target = back_target.lerp(chest + Vector3(0.3 + cos(w * 0.9) * 0.3, 0.3 + sin(w * 1.1) * 0.25, -0.55), flail)
	if lying_weight > 0.01:
		front_target = front_target.lerp(chest + spine_basis * Vector3(0.0, 0.0, 0.62), lying_weight * 0.7)
		back_target = back_target.lerp(chest + spine_basis * Vector3(0.0, 0.0, -0.62), lying_weight * 0.7)
	arm_front = front_target if delta <= 0.0 else arm_front.lerp(front_target, k)
	arm_back = back_target if delta <= 0.0 else arm_back.lerp(back_target, k)
	for arm in ["front", "back"]:
		var s := 1.0 if arm == "front" else -1.0
		var shoulder := chest + spine_up * 0.06 + shoulder_axis * (0.22 * s)
		var hand := reach(shoulder, arm_front if s > 0 else arm_back, UPPER_ARM + FOREARM - 0.01)
		var elbow := two_bone(shoulder, hand, UPPER_ARM, FOREARM, Vector3(0.3, -1.0, s * 0.6))
		place_segment("upper_" + arm, shoulder, elbow)
		place_segment("fore_" + arm, elbow, hand)
		var glove_node: MeshInstance3D = parts["glove_" + arm]
		glove_node.position = hand + (hand - elbow).normalized() * 0.03
