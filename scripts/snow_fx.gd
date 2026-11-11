class_name SnowFX
extends Node3D
## World-space snow presentation driven only by rider state: carve/brake spray
## from the working edge; the deep-lean PLUME (a rooster tail of snow, hanging
## mist and sun-glitter thrown out the side opposite the lean); landing bursts;
## fall dispersion (an impact burst and flying clods at every bounce of a tumble,
## thrown along the body's momentum, plus a ploughed trail while it rolls); nitro
## ember crystals; falling snow from brushed boughs; and persistent board tracks.
var rider: SnowRider
var mountain: SnowMountain
var spray: CPUParticles3D
var bursts: Array[CPUParticles3D] = []
var burst_index := 0
var clods: CPUParticles3D
var tumble_trail: CPUParticles3D
var plume_core: CPUParticles3D
var plume_mist: CPUParticles3D
var plume_glitter: CPUParticles3D
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
	for i in 3:
		var b := particles(200, 1.0, 0.3, Color(0.78, 0.85, 0.95, 0.9))
		b.one_shot = true
		b.explosiveness = 0.92
		b.emitting = false
		bursts.append(b)
	clods = particles(28, 1.5, 0.55, Color(0.72, 0.8, 0.92, 0.95))
	clods.one_shot = true
	clods.explosiveness = 0.95
	clods.emitting = false
	clods.gravity = Vector3(0, -15.0, 0)
	clods.spread = 55.0
	tumble_trail = particles(170, 0.9, 0.34, Color(0.78, 0.85, 0.95, 0.8))
	tumble_trail.emitting = false
	tumble_trail.spread = 60.0
	tumble_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	tumble_trail.emission_sphere_radius = 0.6
	# Plume: a dense arcing core, soft mist that hangs in the air, and glitter.
	plume_core = particles(520, 1.25, 0.42, Color(0.74, 0.82, 0.94, 0.9))
	plume_core.emitting = false
	plume_core.spread = 15.0
	plume_core.gravity = Vector3(0, -9.8, 0)
	plume_core.damping_min = 0.4
	plume_core.damping_max = 1.2
	plume_core.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	plume_core.emission_sphere_radius = 0.45
	plume_mist = particles(70, 2.4, 2.6, Color(0.8, 0.86, 0.95, 0.25))
	plume_mist.emitting = false
	plume_mist.spread = 30.0
	plume_mist.gravity = Vector3(0, -0.5, 0)
	plume_mist.damping_min = 2.0
	plume_mist.damping_max = 3.5
	plume_glitter = particles(170, 1.1, 0.07, Color(1.0, 1.0, 1.0, 1.0), true, Color(1.0, 0.98, 0.92))
	plume_glitter.emitting = false
	plume_glitter.spread = 24.0
	plume_glitter.gravity = Vector3(0, -7.0, 0)
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
	for hidden in OS.get_environment("SNOW_FX_HIDE").split(",", false):
		var node = get(hidden)
		if node is Node3D: node.visible = false

func particles(amount: int, lifetime: float, size: float, color: Color, glow := false, glow_color := Color(1.0, 0.55, 0.15)) -> CPUParticles3D:
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
	# Keep the particle's own scale: without this, particles that have not been
	# emitted yet (zero scale) are drawn full-size and black at the emitter, and the
	# size-over-life curve is ignored.
	mat.billboard_keep_scale = true
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
		mat.emission = glow_color
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

## Start/stop a continuous emitter. Starting goes through restart() so no stale or
## uninitialised particle from a previous burst is ever drawn (seen as a black disc).
func flow(emitter: CPUParticles3D, on: bool) -> void:
	if on and not emitter.emitting:
		emitter.restart()
	emitter.emitting = on

func board_point() -> Vector3:
	return rider.global_position - rider.grounded_normal * 0.6

func _on_event(kind: String, strength: float) -> void:
	match kind:
		"land", "land_sketchy":
			emit_burst(board_point(), Vector3.UP, 3.0 + strength * 7.0, int(40 + strength * 140))
		"crash", "fatal":
			# Snow explodes along the direction the body is thrown.
			emit_burst(rider.global_position, momentum_direction(), 5.0 + strength * 10.0, 200)
			emit_clods(rider.global_position, 5.0 + strength * 6.0)
		"tumble":
			emit_burst(rider.tumble_pos, momentum_direction(), 2.5 + strength * 7.0, int(50 + strength * 150))
			if strength > 0.45:
				emit_clods(rider.tumble_pos, 3.0 + strength * 6.0)

func momentum_direction() -> Vector3:
	var flat := Vector3(rider.tumble_vel.x, 0, rider.tumble_vel.z)
	if flat.length() < 0.5:
		return Vector3.UP
	return (flat.normalized() * 0.75 + Vector3.UP).normalized()

func emit_burst(at: Vector3, direction: Vector3, speed: float, amount: int) -> void:
	var burst := bursts[burst_index]
	burst_index = (burst_index + 1) % bursts.size()
	burst.global_position = at
	burst.amount = clampi(amount, 20, 200)
	burst.direction = direction
	burst.spread = 70.0
	burst.initial_velocity_min = speed * 0.35
	burst.initial_velocity_max = speed
	burst.restart()
	burst.emitting = true

func emit_clods(at: Vector3, speed: float) -> void:
	clods.global_position = at
	clods.direction = momentum_direction()
	clods.initial_velocity_min = speed * 0.5
	clods.initial_velocity_max = speed
	clods.restart()
	clods.emitting = true

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
	flow(spray, intensity > 0.04)
	spray.color = Color(0.93, 0.95, 1.0, clampf(0.25 + intensity * 0.75, 0.0, 0.9))
	spray.scale_amount_min = 0.5 + intensity * 0.6
	spray.scale_amount_max = 0.9 + intensity * 1.4
	if intensity > 0.0:
		var outward := side * signf(rider.steer if absf(rider.steer) > 0.05 else 1.0) # outside of the turn
		var dir := (outward * (0.6 + carve) + rider.grounded_normal * 0.9 - fwd * 0.35).normalized()
		spray.global_position = board_point() - fwd * 0.4
		spray.direction = dir
		spray.spread = 28.0
		spray.initial_velocity_min = 1.0 + speed * 0.12
		spray.initial_velocity_max = 2.5 + speed * 0.3 * (0.5 + carve + brake)
	# Deep-lean plume: a rooster tail thrown out the side OPPOSITE the lean.
	var p := rider.plume if contact else 0.0
	flow(plume_core, p > 0.06)
	flow(plume_mist, p > 0.25)
	flow(plume_glitter, p > 0.12)
	if p > 0.06:
		var out := side * rider.plume_side
		var origin := board_point() + out * 0.15 - fwd * 0.2
		var throw := (out * 1.0 + rider.grounded_normal * (0.75 + 0.25 * p) - fwd * 0.12).normalized()
		var reach := (4.0 + speed * 0.32) * (0.55 + 0.75 * p)
		plume_core.global_position = origin
		plume_core.direction = throw
		plume_core.initial_velocity_min = reach * 0.55
		plume_core.initial_velocity_max = reach * 1.15
		# Slightly blue-grey so the airborne snow reads against sunlit snow behind it.
		plume_core.color = Color(0.74, 0.82, 0.94, clampf(0.4 + p * 0.55, 0.0, 0.95))
		plume_core.scale_amount_min = 0.6 + p * 0.5
		plume_core.scale_amount_max = 1.0 + p * 1.5
		plume_mist.global_position = origin + throw * 1.2
		plume_mist.direction = (throw + Vector3.UP * 0.4).normalized()
		plume_mist.initial_velocity_min = reach * 0.25
		plume_mist.initial_velocity_max = reach * 0.5
		plume_mist.color = Color(0.8, 0.86, 0.95, 0.14 + 0.2 * p)
		plume_glitter.global_position = origin
		plume_glitter.direction = throw
		plume_glitter.initial_velocity_min = reach * 0.7
		plume_glitter.initial_velocity_max = reach * 1.35
	# A tumbling body ploughs a trail of snow while it rolls and slides.
	var rolling := rider.tumble_active and not rider.tumble_resting and not rider.tumble_airborne and rider.tumble_vel.length() > 1.5
	flow(tumble_trail, rolling)
	if rolling:
		var tumble_speed := rider.tumble_vel.length()
		tumble_trail.global_position = rider.tumble_pos
		tumble_trail.direction = momentum_direction()
		tumble_trail.initial_velocity_min = 1.0 + tumble_speed * 0.15
		tumble_trail.initial_velocity_max = 2.5 + tumble_speed * 0.45
		tumble_trail.color = Color(0.78, 0.85, 0.95, clampf(0.3 + tumble_speed / 20.0, 0.0, 0.9))
	# Nitro: hot ice crystals streaming from the glowing board.
	flow(embers, rider.boosting)
	if rider.boosting:
		embers.global_position = rider.global_position - rider.grounded_normal * 0.55 - fwd * 0.7
		embers.direction = (-fwd + Vector3.UP * 0.3).normalized()
		embers.spread = 20.0
		embers.initial_velocity_min = 2.0
		embers.initial_velocity_max = 6.0
		embers.gravity = Vector3(0, -2.0, 0)
	# Riding through low boughs knocks snow loose (canopies stay non-solid).
	bough_cooldown = maxf(0.0, bough_cooldown - delta)
	if mountain and bough_cooldown == 0.0 and speed > 6.0 and rider.recovery <= 0.0 and Engine.get_physics_frames() % 3 == 0:
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
