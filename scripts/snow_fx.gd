class_name SnowFX
extends Node3D
## World-space snow presentation driven only by rider state: carve/brake spray
## from the working edge, powder plumes, landing and crash bursts, nitro ember
## crystals from the board, falling snow when riding through low boughs, and
## persistent board tracks carved into the snow for the whole run.
var rider: SnowRider
var mountain: SnowMountain
var spray: CPUParticles3D
var burst: CPUParticles3D
var embers: CPUParticles3D
var bough: CPUParticles3D
var track_root: Node3D
var track_material: ShaderMaterial
var live_track: MeshInstance3D
var live_mesh: ImmediateMesh
var track_points: Array = []        # [left, right, alpha]
var committed: Array[MeshInstance3D] = []
var last_track_point := Vector3.INF
var bough_cooldown := 0.0
const TRACK_SPACING := 0.7
const TRACK_SEGMENT := 120
const TRACK_SEGMENTS_KEPT := 70

func _ready() -> void:
	spray = particles(260, 0.55, 0.16, Color(0.93, 0.95, 1.0, 0.85))
	spray.emitting = false
	burst = particles(180, 0.9, 0.24, Color(0.94, 0.96, 1.0, 0.9))
	burst.one_shot = true
	burst.explosiveness = 0.92
	burst.emitting = false
	embers = particles(90, 0.6, 0.07, Color(1.0, 0.62, 0.22, 1.0), true)
	embers.emitting = false
	bough = particles(90, 1.6, 0.2, Color(0.95, 0.96, 1.0, 0.8))
	bough.one_shot = true
	bough.explosiveness = 0.7
	bough.emitting = false
	bough.gravity = Vector3(0, -4.0, 0)
	bough.direction = Vector3(0, -1, 0)
	bough.spread = 70.0
	bough.initial_velocity_min = 0.2
	bough.initial_velocity_max = 1.5
	bough.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bough.emission_sphere_radius = 1.4
	track_root = Node3D.new()
	track_root.name = "Tracks"
	add_child(track_root)
	track_material = ShaderMaterial.new()
	track_material.shader = preload("res://shaders/track.gdshader")
	live_mesh = ImmediateMesh.new()
	live_track = MeshInstance3D.new()
	live_track.mesh = live_mesh
	live_track.material_override = track_material
	live_track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track_root.add_child(live_track)
	rider.sound_event.connect(_on_event)
	rider.reset_performed.connect(clear_tracks)

func particles(amount: int, lifetime: float, size: float, color: Color, glow := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	p.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.width = 32
	tex.height = 32
	mat.albedo_texture = tex
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.55, 0.15)
		mat.emission_energy_multiplier = 4.0
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = grow
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	add_child(p)
	return p

func board_point() -> Vector3:
	return rider.global_position - rider.grounded_normal * 0.6

func _on_event(kind: String, strength: float) -> void:
	match kind:
		"land", "land_sketchy":
			emit_burst(board_point(), 3.0 + strength * 7.0, int(40 + strength * 140))
		"crash", "fatal":
			emit_burst(rider.global_position, 4.0 + strength * 8.0, 180)
		"tumble":
			if strength > 0.35:
				emit_burst(rider.tumble_pos, 2.0 + strength * 4.0, 60)

func emit_burst(at: Vector3, speed: float, amount: int) -> void:
	burst.global_position = at
	burst.amount = clampi(amount, 20, 180)
	burst.direction = Vector3.UP
	burst.spread = 75.0
	burst.initial_velocity_min = speed * 0.35
	burst.initial_velocity_max = speed
	burst.restart()
	burst.emitting = true

func _physics_process(delta: float) -> void:
	var speed := rider.speed
	var contact := rider.ground_contact and rider.recovery <= 0.0 and rider.run.state in ["running", "finished"]
	var fwd := rider.forward()
	var side := rider.grounded_normal.cross(fwd).normalized()
	# Edge spray: thrown from the working edge, outward from the turn and back.
	var carve := absf(rider.steer)
	var brake := rider.brake_input
	var intensity := 0.0
	if contact and speed > 3.0:
		intensity = clampf(speed / 30.0, 0.0, 1.2) * (0.12 + carve * 0.9 + brake * 1.3 + rider.surface.x * 0.35)
	# CPU particles have no emission ratio: density reads through opacity and size.
	spray.emitting = intensity > 0.04
	spray.color = Color(0.93, 0.95, 1.0, clampf(0.25 + intensity * 0.75, 0.0, 0.9))
	spray.scale_amount_min = 0.5 + intensity * 0.6
	spray.scale_amount_max = 0.9 + intensity * 1.4
	if intensity > 0.0:
		var outward := -side * signf(rider.steer if absf(rider.steer) > 0.05 else 1.0)
		var dir := (outward * (0.6 + carve) + rider.grounded_normal * 0.9 - fwd * 0.35).normalized()
		spray.global_position = board_point() - fwd * 0.4
		spray.direction = dir
		spray.spread = 28.0
		spray.initial_velocity_min = 1.0 + speed * 0.12
		spray.initial_velocity_max = 2.5 + speed * 0.3 * (0.5 + carve + brake)
	# Nitro: hot ice crystals streaming from the glowing board.
	embers.emitting = rider.boosting
	if rider.boosting:
		embers.global_position = rider.global_position - rider.grounded_normal * 0.55 - fwd * 0.7
		embers.direction = (-fwd + Vector3.UP * 0.3).normalized()
		embers.spread = 20.0
		embers.initial_velocity_min = 2.0
		embers.initial_velocity_max = 6.0
		embers.gravity = Vector3(0, -2.0, 0)
	# Riding through low boughs knocks snow loose (canopies stay non-solid).
	bough_cooldown = maxf(0.0, bough_cooldown - delta)
	if mountain and bough_cooldown == 0.0 and speed > 6.0 and rider.recovery <= 0.0:
		for h in mountain.hazards_near(rider.global_position, 2.6, true):
			var d := Vector2(h.x - rider.global_position.x, h.z - rider.global_position.z).length()
			if d < h.w * 7.5 and d > h.w + 0.3:
				bough.global_position = Vector3(h.x, rider.global_position.y + 2.2, h.z).lerp(rider.global_position + Vector3.UP * 1.5, 0.5)
				bough.restart()
				bough.emitting = true
				rider.sound_event.emit("bough", clampf(speed / 25.0, 0.3, 1.0))
				bough_cooldown = 0.6
				break
	update_tracks(contact)

func update_tracks(contact: bool) -> void:
	if not contact:
		if not track_points.is_empty():
			commit_track()
		last_track_point = Vector3.INF
		return
	var center := board_point() + rider.grounded_normal * 0.035
	if last_track_point != Vector3.INF and center.distance_to(last_track_point) < TRACK_SPACING:
		return
	if last_track_point != Vector3.INF and center.distance_to(last_track_point) > 6.0:
		commit_track()
	last_track_point = center
	var fwd := rider.forward()
	var side := rider.grounded_normal.cross(fwd).normalized()
	var width := 0.15 - absf(rider.steer) * 0.04 + rider.brake_input * 0.12
	var depth := clampf(0.35 + rider.surface.x * 0.4 + absf(rider.steer) * 0.25 + rider.brake_input * 0.2, 0.0, 1.0)
	track_points.append([center + side * width, center - side * width, depth])
	if track_points.size() >= TRACK_SEGMENT:
		commit_track()
		track_points.append([center + side * width, center - side * width, depth])
	else:
		draw_live()

func strip(target: Object, points: Array) -> void:
	for i in points.size():
		var p: Array = points[i]
		var a: float = p[2]
		if i == 0 or i == points.size() - 1:
			a *= 0.3
		target.surface_set_color(Color(1, 1, 1, a))
		target.surface_set_uv(Vector2(i * 0.1, 0.0))
		target.surface_add_vertex(p[0])
		target.surface_set_color(Color(1, 1, 1, a))
		target.surface_set_uv(Vector2(i * 0.1, 1.0))
		target.surface_add_vertex(p[1])

func draw_live() -> void:
	live_mesh.clear_surfaces()
	if track_points.size() < 2:
		return
	live_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	strip(live_mesh, track_points)
	live_mesh.surface_end()

func commit_track() -> void:
	live_mesh.clear_surfaces()
	if track_points.size() >= 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in track_points.size() - 1:
			var p0: Array = track_points[i]
			var p1: Array = track_points[i + 1]
			var a0: float = p0[2] * (0.3 if i == 0 else 1.0)
			var a1: float = p1[2] * (0.3 if i + 1 == track_points.size() - 1 else 1.0)
			for v in [[p0[0], a0, 0.0], [p1[0], a1, 0.0], [p0[1], a0, 1.0], [p1[0], a1, 0.0], [p1[1], a1, 1.0], [p0[1], a0, 1.0]]:
				st.set_color(Color(1, 1, 1, v[1]))
				st.set_uv(Vector2(0, v[2]))
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
		var instance := MeshInstance3D.new()
		instance.mesh = st.commit()
		instance.material_override = track_material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		track_root.add_child(instance)
		committed.append(instance)
		while committed.size() > TRACK_SEGMENTS_KEPT:
			committed.pop_front().queue_free()
	track_points.clear()

func clear_tracks() -> void:
	track_points.clear()
	last_track_point = Vector3.INF
	if live_mesh:
		live_mesh.clear_surfaces()
	for m in committed:
		m.queue_free()
	committed.clear()
