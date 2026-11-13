class_name SnowRiderVisual
extends Node3D
## Procedural snowboarder: shaped board with real thickness, camber, upturned
## tips and a base graphic; curved highbacks and strapped bindings; flexed boots;
## baggy pants that flare over the boots; a fitted jacket with shoulder yoke,
## piping, zip, collar and hood; a backpack with harness; gauntlet mitts; a vented
## helmet with wrap goggles, mirrored lens and face mask. Every garment is swept
## procedurally (SnowRiderMesh) with colour blocking in its vertex colours.
## Limbs are posed every frame with analytic two-bone IK against the bindings,
## so knees absorb terrain, hips drop into a tuck, the whole rig inclines into
## carves and hands reach for real grabs.
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
	board_material.albedo_color = BOARD_TOP
	board_material.vertex_color_use_as_albedo = true
	board_material.vertex_color_is_srgb = true
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
## Clothing palette (sRGB). The red jacket is the rider's identity: it reads
## against snow by day and, with the rim light, against moonlit slopes at night.
const JACKET := Color("c4282f")
const JACKET_SHADE := Color("8e1c24")
const YOKE := Color("2b2f36")
const PIPING := Color("ece5d2")
const ZIP := Color("17191d")
const PANTS := Color("30353d")
const PANTS_DARK := Color("1f2329")
const PACK := Color("31363d")
const PACK_LID := Color("4a515b")
const WEBBING := Color("1b1e22")
const ACCENT := Color("e2761d")      # the orange of the nitro glow, used sparingly
const BOOT := Color("2a2d31")
const SOLE := Color("131417")
const LACES := Color("7f868f")
const GLOVE := Color("1b1d21")
const GLOVE_CUFF := Color("3c424b")
const HELMET := Color("eceee9")
const VENT := Color("2a2c30")
const EARPAD := Color("34373c")
const MASK := Color("1e2127")
const FRAME := Color("17181c")
const BOARD_TOP := Color("232c38")    # times the top-sheet vertex shade: dark when uncharged

func mat(color: Color, rough := 0.75, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	# A soft rim so the rider keeps a readable outline when backlit (moonlight).
	m.rim_enabled = true
	m.rim = 0.45
	m.rim_tint = 0.35
	return m

## A material whose colour comes from the mesh (colour blocking, seams, stripes).
func painted(rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := mat(Color.WHITE, rough, metal)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m

func mesh_part(key: String, mesh: Mesh, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	(rig if parent == null else parent).add_child(instance)
	parts[key] = instance
	return instance

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

## Top-sheet shade along the board (multiplies BOARD_TOP and the charge colour):
## two light bands toward each tip and slightly lighter kicks. Stays dark overall.
func top_sheet(t: float) -> Color:
	var a := absf(t)
	var shade := 0.7
	if absf(a - 0.7) < 0.045:
		shade = 1.0
	elif a > 0.88:
		shade = 0.85
	return Color(shade, shade, shade)

func build_board() -> void:
	const N := 40
	const LENGTH := 1.56
	const THICK := 0.022
	var top := PackedVector3Array()
	var top_n := PackedVector3Array()
	var top_c := PackedColorArray()
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
			top_c.append(top_sheet(v.z / (LENGTH * 0.5)))
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
	# Base graphic (seen in the air and in falls): dark base, a cream band near
	# each tip and an orange slash under the stance.
	var base_c := PackedColorArray()
	for v in base:
		var t := v.z / (LENGTH * 0.5)
		var c := Color("15181d")
		if absf(absf(t) - 0.62) < 0.07:
			c = PIPING
		elif absf(t + v.x * 1.8) < 0.08:
			c = ACCENT
		base_c.append(c)
	var mesh := ArrayMesh.new()
	for surface in [[top, top_n, top_c], [rim, rim_n, null], [base, base_n, base_c]]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface[0]
		arrays[Mesh.ARRAY_NORMAL] = surface[1]
		if surface[2] != null:
			arrays[Mesh.ARRAY_COLOR] = surface[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var board := MeshInstance3D.new()
	board.mesh = mesh
	board.set_surface_override_material(0, board_material)
	board.set_surface_override_material(1, board_material)
	board.set_surface_override_material(2, painted(0.25, 0.3))
	rig.add_child(board)
	parts["board"] = board
	# Bindings and boots, one mesh each per foot. Foot frame: toe toward -X (the
	# toe edge, where the rider faces), up +Y, along the board +Z.
	var plastic := painted(0.5, 0.1)
	var rubber := painted(0.75)
	for side in [1.0, -1.0]:
		var foot := Node3D.new()
		foot.position = Vector3(0, THICK + 0.012, side * STANCE)
		foot.rotation.y = deg_to_rad(15.0 if side > 0 else -6.0)
		rig.add_child(foot)
		mesh_part("binding%d" % side, binding_mesh(), plastic, foot)
		mesh_part("boot%d" % side, boot_mesh(), rubber, foot)

func binding_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	b.box(Vector3(0.0, 0.0, 0.0), Vector3(0.29, 0.016, 0.15), Color("1f2226"), 5.0)
	# Heel cup and highback: bands bent round the heel; the highback leans forward.
	var cup := []
	var back := []
	var back_h := []
	for i in 9:
		var f := deg_to_rad(lerpf(-100.0, 100.0, i / 8.0))
		cup.append(Vector3(0.035 + 0.09 * cos(f), 0.045, 0.09 * sin(f)))
	for i in 7:
		var f := deg_to_rad(lerpf(-68.0, 68.0, i / 6.0))
		back.append(Vector3(0.05 + 0.088 * cos(f), 0.16, 0.088 * sin(f)))
		back_h.append(lerpf(0.095, 0.06, absf(i - 3) / 3.0))
	b.sweep(cup, fill(9, 0.04), fill(9, 0.008), Vector3.UP, Color("25292e"), 8, 4.0)
	b.sweep(back, back_h, fill(7, 0.008), Vector3.UP, func(v: Vector3, _i: int, _a: float) -> Color:
		return ACCENT if v.y > 0.235 else Color("25292e"), 8, 4.0, true, Transform3D.IDENTITY,
		func(v: Vector3) -> Vector3: return v - Vector3((v.y - 0.06) * 0.28, 0, 0))
	# Ankle strap over the instep and toe strap over the toe box.
	for spec in [[-0.015, 0.085, 0.11, 0.03, 0.03], [-0.12, 0.07, 0.072, 0.018, 0.025]]:
		var arc := []
		for i in 9:
			var f := deg_to_rad(lerpf(-90.0, 90.0, i / 8.0))
			arc.append(Vector3(spec[0], spec[4] + spec[2] * cos(f), spec[1] * sin(f)))
		b.sweep(arc, fill(9, spec[3]), fill(9, 0.011), Vector3.RIGHT, Color("c3c8cd"), 8, 4.0)
	return b.commit()

func boot_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	b.box(Vector3(-0.045, 0.02, 0.0), Vector3(0.31, 0.024, 0.125), SOLE, 5.0)
	# Shaft, leaning slightly forward like a flexed boot, with a padded collar.
	b.column([[0.03, 0.085, 0.07, 0.025], [0.1, 0.082, 0.066, 0.02], [0.17, 0.075, 0.063, 0.012], [0.225, 0.071, 0.063, 0.006], [0.25, 0.064, 0.058, 0.004], [0.258, 0.045, 0.04, 0.004]],
		func(v: Vector3, _i: int, _a: float) -> Color:
			if v.y > 0.215: return Color("43484f")
			if v.x < -0.04 and v.y > 0.08: return LACES
			return BOOT, 16)
	# Vamp and toe box.
	b.sweep([Vector3(0.06, 0.07, 0), Vector3(-0.02, 0.068, 0), Vector3(-0.1, 0.062, 0), Vector3(-0.15, 0.055, 0), Vector3(-0.172, 0.05, 0)],
		[0.05, 0.05, 0.045, 0.035, 0.02], [0.062, 0.064, 0.062, 0.055, 0.03], Vector3.UP,
		func(v: Vector3, _i: int, _a: float) -> Color:
			return LACES if v.y > 0.1 and v.x < 0.0 and v.x > -0.12 else BOOT, 14, 3.0)
	for z in [0.071, -0.071]:
		b.ellipsoid(Vector3(0.015, 0.15, z), Vector3(0.019, 0.019, 0.009), ACCENT, 10, 4)
	return b.commit()

func fill(n: int, value: float) -> Array:
	var a := []
	a.resize(n)
	a.fill(value)
	return a

# ---------------------------------------------------------------- body
## Garments are authored in the frame they are posed in:
## - torso/hem: spine frame, origin at the pelvis, +Y up the spine, front -X,
##   +Z toward the nose-side shoulder;
## - limbs: origin at the upper joint, +Y along the bone, +X the limb's front
##   (knee cap / inside of the elbow);
## - head: origin at the head centre, front -X.
func build_body() -> void:
	var fabric := painted(0.86)
	mesh_part("torso", torso_mesh(), fabric)
	mesh_part("hem", hem_mesh(), fabric)
	for leg in ["front", "back"]:
		mesh_part("thigh_" + leg, thigh_mesh(), fabric)
		mesh_part("shin_" + leg, shin_mesh(), fabric)
	for arm in ["front", "back"]:
		mesh_part("upper_" + arm, upper_arm_mesh(), fabric)
		mesh_part("fore_" + arm, forearm_mesh(), fabric)
		mesh_part("glove_" + arm, glove_mesh(1.0 if arm == "front" else -1.0), painted(0.7))
	var neck := SnowRiderMesh.new()
	neck.column([[0.0, 0.055, 0.058], [0.12, 0.058, 0.06]], MASK, 12)
	mesh_part("neck", neck.commit(), fabric)
	mesh_part("head", helmet_mesh(), painted(0.32))
	var mask := SnowRiderMesh.new()
	mask.ellipsoid(Vector3(-0.025, -0.065, 0.0), Vector3(0.1, 0.088, 0.092), MASK, 16, 8)
	mesh_part("mask", mask.commit(), fabric)
	mesh_part("lens", lens_mesh(), painted(0.06, 0.8))

func torso_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	# Jacket: waist, chest, squared shoulders; a charcoal yoke over the shoulders
	# behind cream piping, and a zip down the front.
	var jacket := SnowRiderMesh.cut([[-0.03, 0.158, 0.208, 0.008], [0.05, 0.152, 0.198, 0.004], [0.14, 0.145, 0.19, 0.0], [0.26, 0.15, 0.2, -0.008],
		[0.37, 0.155, 0.212, -0.012], [0.45, 0.148, 0.218, -0.01], [0.51, 0.128, 0.212, 0.0], [0.56, 0.1, 0.165, 0.005], [0.595, 0.075, 0.095, 0.005]], [0.476, 0.492])
	b.column(jacket, func(v: Vector3, _i: int, _a: float) -> Color:
			# The yoke wraps the shoulders and upper back; the chest stays red.
			var back := v.x > -0.07 + absf(v.z) * 0.25
			if v.y > 0.49 and back: return YOKE
			if v.y > 0.474 and back: return PIPING
			return JACKET, 20, 2.3)
	b.front_strip(jacket, -0.03, 0.5, 0.009, ZIP)
	# Pants seat, hidden under the jacket hem.
	b.column([[-0.19, 0.05, 0.07, 0.01], [-0.15, 0.1, 0.15, 0.015], [-0.09, 0.125, 0.17, 0.02], [0.0, 0.13, 0.175, 0.015]], PANTS, 16)
	# Tall collar (charcoal rim) and the hood bunched behind it.
	b.column(SnowRiderMesh.cut([[0.555, 0.1, 0.107, 0.0], [0.6, 0.095, 0.101, 0.004], [0.66, 0.104, 0.11, 0.01], [0.69, 0.108, 0.114, 0.012], [0.695, 0.09, 0.096, 0.012]], [0.675]),
		func(v: Vector3, _i: int, _a: float) -> Color: return YOKE if v.y > 0.675 else JACKET, 16)
	b.ellipsoid(Vector3(0.115, 0.572, 0.0), Vector3(0.045, 0.052, 0.125), YOKE, 14, 6)
	# Backpack with a lighter lid and two compression straps.
	b.column(SnowRiderMesh.cut([[0.12, 0.055, 0.125, 0.205], [0.15, 0.066, 0.135, 0.212], [0.4, 0.068, 0.135, 0.215], [0.47, 0.06, 0.125, 0.205], [0.5, 0.04, 0.1, 0.195]], [0.39]),
		func(v: Vector3, _i: int, _a: float) -> Color:
			if v.y > 0.39: return PACK_LID
			if v.x > 0.25 and absf(absf(v.z) - 0.07) < 0.018: return WEBBING
			return PACK, 16, 4.5)
	# Shoulder straps over the shoulders and down the chest, and a sternum strap.
	for side in [1.0, -1.0]:
		var path := [Vector3(0.215, 0.47, 0.08 * side), Vector3(0.16, 0.545, 0.095 * side), Vector3(0.07, 0.6, 0.11 * side), Vector3(-0.03, 0.595, 0.115 * side),
			Vector3(-0.125, 0.525, 0.12 * side), Vector3(-0.172, 0.42, 0.115 * side), Vector3(-0.178, 0.32, 0.11 * side), Vector3(-0.162, 0.21, 0.115 * side)]
		b.sweep(path, fill(8, 0.024), fill(8, 0.009), Vector3.BACK, WEBBING, 8, 4.0)
	b.box(Vector3(-0.182, 0.36, 0.0), Vector3(0.012, 0.022, 0.24), WEBBING, 4.0)
	b.box(Vector3(-0.189, 0.36, 0.0), Vector3(0.014, 0.03, 0.045), ACCENT, 4.0)
	return b.commit()

## The long lower jacket, a separate piece so it can flap in the wind. It falls
## past the seat and flares enough to cover the tops of the thighs.
func hem_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	var rings := SnowRiderMesh.cut([[-0.165, 0.168, 0.22, 0.014], [-0.12, 0.166, 0.217, 0.012], [-0.05, 0.16, 0.21, 0.01], [0.0, 0.157, 0.206, 0.007], [0.02, 0.155, 0.202, 0.006]], [-0.128])
	b.column(rings, func(v: Vector3, _i: int, _a: float) -> Color: return JACKET_SHADE if v.y < -0.128 else JACKET, 20, 2.3, false)
	b.front_strip(rings, -0.165, 0.02, 0.009, ZIP)
	return b.commit()

func thigh_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	b.column(SnowRiderMesh.cut([[-0.04, 0.085, 0.09], [0.0, 0.1, 0.104], [0.08, 0.104, 0.106], [0.2, 0.1, 0.102], [0.34, 0.093, 0.095], [0.44, 0.088, 0.09], [0.49, 0.065, 0.065]], [0.38]),
		func(v: Vector3, _i: int, _a: float) -> Color: return PANTS_DARK if v.y > 0.38 and v.x > 0.03 else PANTS, 16)
	return b.commit()

func shin_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	# Baggy leg that flares into a cuff over the boot; reinforced knee.
	b.column(SnowRiderMesh.cut([[-0.06, 0.08, 0.083], [0.0, 0.09, 0.092], [0.1, 0.087, 0.089], [0.24, 0.086, 0.088], [0.33, 0.094, 0.096], [0.4, 0.108, 0.11], [0.445, 0.116, 0.118], [0.465, 0.114, 0.116]], [0.13, 0.42]),
		func(v: Vector3, _i: int, _a: float) -> Color:
			if v.y > 0.42: return PANTS_DARK
			if v.y < 0.13 and v.x > 0.03: return PANTS_DARK
			return PANTS, 16)
	return b.commit()

func upper_arm_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	b.column(SnowRiderMesh.cut([[-0.035, 0.05, 0.054], [0.0, 0.077, 0.081], [0.05, 0.078, 0.081], [0.16, 0.073, 0.076], [0.27, 0.068, 0.07], [0.315, 0.062, 0.064], [0.34, 0.04, 0.04]], [0.012, 0.026]),
		func(v: Vector3, _i: int, _a: float) -> Color:
			if v.y < 0.012: return YOKE
			if v.y < 0.026: return PIPING
			return JACKET, 14)
	return b.commit()

func forearm_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	b.column(SnowRiderMesh.cut([[-0.03, 0.062, 0.066], [0.02, 0.066, 0.07], [0.14, 0.064, 0.066], [0.215, 0.06, 0.062], [0.235, 0.068, 0.07], [0.285, 0.066, 0.068], [0.3, 0.05, 0.05]], [0.222]),
		func(v: Vector3, _i: int, _a: float) -> Color: return YOKE if v.y > 0.222 else JACKET, 14)
	return b.commit()

func glove_mesh(side: float) -> ArrayMesh:
	var b := SnowRiderMesh.new()
	# Gauntlet over the sleeve, then a mitt flattened across the palm.
	b.column(SnowRiderMesh.cut([[-0.065, 0.074, 0.078], [-0.02, 0.072, 0.076], [0.0, 0.05, 0.055], [0.03, 0.036, 0.056], [0.08, 0.034, 0.054], [0.11, 0.03, 0.046], [0.125, 0.015, 0.025]], [-0.005]),
		func(v: Vector3, _i: int, _a: float) -> Color: return GLOVE_CUFF if v.y < -0.005 else GLOVE, 12)
	b.sweep([Vector3(0.012, 0.012, 0.035 * side), Vector3(0.03, 0.045, 0.055 * side), Vector3(0.035, 0.072, 0.05 * side)], [0.018, 0.017, 0.013], [0.018, 0.017, 0.013], Vector3.RIGHT, GLOVE, 8)
	return b.commit()

func helmet_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	# Shell: the lower edge rises at the front to leave room for the goggles.
	var shell := [[-0.05, 0.148, 0.132, 0.012], [-0.01, 0.152, 0.135, 0.01], [0.04, 0.148, 0.131, 0.008], [0.085, 0.128, 0.113, 0.01], [0.12, 0.094, 0.083, 0.012], [0.143, 0.052, 0.046, 0.012], [0.152, 0.015, 0.013, 0.012]]
	b.column(shell, func(v: Vector3, _i: int, _a: float) -> Color:
			return EARPAD if absf(v.z) > 0.112 and v.y < 0.025 else HELMET, 24, 2.2, true, Transform3D.IDENTITY,
		func(v: Vector3) -> Vector3:
			if v.x < 0.0 and v.y < 0.035:
				v.y = lerpf(v.y, 0.035, pow(clampf(-v.x / 0.13, 0.0, 1.0), 1.5))
			return v)
	# Two vent ridges running front to back over the crown.
	for z in [0.032, -0.032]:
		var ridge := []
		for side in [1.0, -1.0]:
			var order := range(2, shell.size() - 1) if side > 0.0 else range(shell.size() - 2, 1, -1)
			for i in order:
				var r: Array = shell[i]
				var k := sqrt(maxf(0.0, 1.0 - pow(z / r[2], 2.0)))
				ridge.append(Vector3(r[3] + side * r[1] * k * 1.02, r[0] + 0.004, z))
		b.sweep(ridge, fill(ridge.size(), 0.007), fill(ridge.size(), 0.006), Vector3.BACK, VENT, 6, 3.0)
	# Goggle frame wrapping the face, strap round the back of the helmet.
	var frame := []
	var frame_h := []
	for i in 11:
		var f := deg_to_rad(lerpf(-75.0, 75.0, i / 10.0))
		var k := pow(absf(f) / deg_to_rad(75.0), 2.0)
		var r := 0.124 + 0.022 * k
		frame.append(Vector3(-r * cos(f), -0.012 + 0.03 * k, (r + 0.006) * sin(f)))
		frame_h.append(lerpf(0.038, 0.024, k))
	b.sweep(frame, frame_h, fill(11, 0.012), Vector3.UP, FRAME, 10, 3.0)
	var strap := []
	for i in 13:
		var f := deg_to_rad(lerpf(70.0, 290.0, i / 12.0))
		strap.append(Vector3(0.01 - 0.158 * cos(f), 0.018, 0.141 * sin(f)))
	b.sweep(strap, fill(13, 0.021), fill(13, 0.005), Vector3.UP,
		func(v: Vector3, _i: int, _a: float) -> Color: return ACCENT if v.x > 0.14 else FRAME, 8, 4.0)
	return b.commit()

func lens_mesh() -> ArrayMesh:
	var b := SnowRiderMesh.new()
	var arc := []
	for i in 11:
		var f := deg_to_rad(lerpf(-62.0, 62.0, i / 10.0))
		var k := pow(absf(f) / deg_to_rad(75.0), 2.0)
		var r := 0.124 + 0.022 * k + 0.02
		arc.append(Vector3(-r * cos(f), -0.012 + 0.03 * k, (r + 0.006) * sin(f)))
	# Mirrored lens: amber at the top shading to fire red, like a real coating.
	b.sweep(arc, fill(11, 0.029), fill(11, 0.006), Vector3.UP,
		func(v: Vector3, _i: int, _a: float) -> Color: return Color("c4452a").lerp(Color("f5b53e"), clampf((v.y + 0.035) / 0.06, 0.0, 1.0)), 10, 3.0)
	return b.commit()

# ---------------------------------------------------------------- posing helpers
## Pose a limb mesh authored along +Y from `a` toward `b`, its +X turned toward `front`.
func place_bone(key: String, a: Vector3, b: Vector3, front: Vector3) -> void:
	var node: MeshInstance3D = parts[key]
	var dir := b - a
	if dir.length() < 0.0001:
		return
	var y := dir.normalized()
	var x := front - y * front.dot(y)
	if x.length() < 0.0001:
		x = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	node.transform = Transform3D(Basis(x, y, x.cross(y)), a)

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
	board_material.albedo_color = BOARD_TOP.lerp(warm.darkened(0.35), charge)
	board_material.emission = warm
	var flare := 1.0
	if rider != null and rider.boosting:
		flare = 1.25 + 0.2 * sin(time * 47.0)
	board_material.emission_energy_multiplier = charge * charge * 4.5 * flare + charge * 0.8
	# At night the charged board throws its glow onto the snow around it.
	var night := SnowAtmosphere.night_amount
	lamp.light_energy = charge * 1.6 * flare * lerpf(1.0, 1.9, night)
	lamp.omni_range = lerpf(3.5, 7.0, night)

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
	if r != null and r.run.state == "ready":
		t_pitch += 0.018 * sin(time * 1.6)   # slow breathing while waiting at the summit
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
		var knee_front := knee - (hip + ankle) * 0.5
		if knee_front.length() < 0.02:
			knee_front = facing
		place_bone("thigh_" + leg, hip, knee, knee_front)
		place_bone("shin_" + leg, knee, ankle, knee_front)
	(parts["torso"] as MeshInstance3D).transform = Transform3D(spine_basis, pelvis)
	# Jacket hem flutters in the airstream as speed builds.
	var wind := 0.0 if r == null else clampf(r.speed / 35.0, 0.0, 1.3)
	var flap := (sin(time * 23.0) * 0.6 + sin(time * 37.0) * 0.4) * 0.045 * wind
	(parts["hem"] as MeshInstance3D).transform = Transform3D(spine_basis * Basis.from_euler(Vector3(flap, 0.0, flap * 0.6)), pelvis)
	# Head stays level-ish and looks toward the direction of travel (the nose).
	var turn_target := 1.1 + (0.0 if r == null else clampf(-r.yaw_rate * 0.25, -0.3, 0.3))
	if r != null and r.run.state == "ready":
		turn_target = 0.9 + 0.5 * sin(time * 0.37)
	head_turn = lerpf(head_turn, turn_target, k)
	var head_basis := Basis(Vector3.UP, head_turn) * Basis(Vector3.BACK, -0.1)
	var head_pos := neck + Vector3.UP * 0.15
	for key in ["head", "mask", "lens"]:
		(parts[key] as MeshInstance3D).transform = Transform3D(head_basis, head_pos)
	place_bone("neck", neck - spine_up * 0.06, head_pos - Vector3.UP * 0.07, facing)
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
		var inside := (shoulder + hand) * 0.5 - elbow
		if inside.length() < 0.02:
			inside = facing
		place_bone("upper_" + arm, shoulder, elbow, inside)
		place_bone("fore_" + arm, elbow, hand, inside)
		place_bone("glove_" + arm, hand, hand + (hand - elbow), inside)
