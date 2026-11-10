class_name SnowCamera
extends Camera3D
## Chase camera with an independent right-stick free look.
##
## Orientation = follow_yaw (smoothed TRAVEL direction, never board spins/flips)
## + look_yaw (the player's own offset). Because the manual offset is held
## relative to travel, looking behind while carving stays behind; auto-follow
## never fights an active stick. After CAM_IDLE_DELAY seconds without input the
## offset settles gently home; RS click recenters smoothly. At the stationary
## summit a chosen view holds until push-off. Manual look NEVER touches the rider.
const T = preload("res://scripts/snow_tuning.gd")
const PITCH_MIN := T.CAM_PITCH_MIN
const PITCH_MAX := T.CAM_PITCH_MAX
const IDLE_DELAY := T.CAM_IDLE_DELAY
var rider: SnowRider
var orbit := 0.0          # final world yaw of the camera boom (read-only for others)
var follow_yaw := 0.0
var look_yaw := 0.0
var lift := 0.3           # boom elevation (rad)
var idle := 0.0
var recentering := false
var yaw_velocity := 0.0
var pitch_velocity := 0.0
var distance := T.CAM_DISTANCE_MIN
var clear_fraction := 1.0
var anchor := Vector3.ZERO
var anchor_vertical_velocity := 0.0
var bump := 0.0
var bump_velocity := 0.0
var shake := 0.0
var boost_glow := 0.0
var drop_raise := 0.0
var look_point := Vector3.ZERO
var sphere := SphereShape3D.new()
var query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	current = true
	near = 0.15
	far = 30000
	sphere.radius = T.CAM_COLLISION_RADIUS
	query.shape = sphere
	query.collision_mask = 3
	rider.sound_event.connect(_on_rider_event)
	reset()

func auto_lift() -> float:
	var s := rider.speed if rider else 0.0
	var air := 0.0 if rider == null or not rider.airborne else 0.1
	return lerpf(0.3, 0.2, smoothstep(5.0, 40.0, s)) + drop_raise + air

func reset() -> void:
	follow_yaw = rider.heading
	look_yaw = 0.0
	orbit = follow_yaw
	drop_raise = 0.0
	lift = auto_lift()
	idle = 0
	recentering = false
	yaw_velocity = 0.0
	pitch_velocity = 0.0
	distance = T.CAM_DISTANCE_MIN
	clear_fraction = 1.0
	bump = 0.0
	bump_velocity = 0.0
	shake = 0.0
	boost_glow = 0.0
	fov = T.CAM_FOV_REST
	anchor = rider.position + Vector3.UP
	anchor_vertical_velocity = 0.0
	var dir := Vector3(sin(orbit), 0, cos(orbit))
	global_position = anchor - dir * cos(lift) * distance + Vector3.UP * (sin(lift) * distance + 0.6)
	look_point = anchor + dir * 4.0
	look_at(look_point)

## Analog orbit. stick.x orbits horizontally (unlimited), stick.y pitches.
func orbit_input(delta: float, stick: Vector2, recenter: bool) -> void:
	var magnitude := minf(stick.length(), 1.0)
	var target_yaw_rate := 0.0
	var target_pitch_rate := 0.0
	if magnitude > 0.001:
		idle = 0
		recentering = false
		var response := stick.normalized() * pow(magnitude, T.CAM_RESPONSE)
		target_yaw_rate = -response.x * T.CAM_YAW_RATE
		target_pitch_rate = response.y * T.CAM_PITCH_RATE
	else:
		idle += delta
	var k := 1.0 - exp(-T.CAM_INPUT_SMOOTH * delta)
	yaw_velocity = lerpf(yaw_velocity, target_yaw_rate, k)
	pitch_velocity = lerpf(pitch_velocity, target_pitch_rate, k)
	if absf(yaw_velocity) < 0.002: yaw_velocity = 0.0
	if absf(pitch_velocity) < 0.002: pitch_velocity = 0.0
	look_yaw += yaw_velocity * delta
	lift = clampf(lift + pitch_velocity * delta, PITCH_MIN, PITCH_MAX)
	if recenter and magnitude <= 0.001:
		recentering = true
	# At the stationary summit the player may admire any view indefinitely.
	var waiting := rider != null and rider.run != null and rider.run.state == "ready"
	var settling := idle > IDLE_DELAY and not waiting
	if magnitude <= 0.001 and (recentering or settling):
		var gain := T.CAM_RECENTER_RATE if recentering else T.CAM_SETTLE_RATE * smoothstep(IDLE_DELAY, IDLE_DELAY + 1.5, idle)
		var w := 1.0 - exp(-gain * delta)
		look_yaw = lerp_angle(wrapf(look_yaw, -PI, PI), 0.0, w)
		lift = lerpf(lift, auto_lift(), 1.0 - exp(-gain * (1.0 if recentering else 2.5) * delta))
		if absf(look_yaw) < 0.01 and absf(lift - auto_lift()) < 0.01:
			recentering = false
	orbit = follow_yaw + look_yaw

func travel_yaw() -> float:
	var flat := Vector2(rider.velocity.x, rider.velocity.z)
	if flat.length() > 2.5 and rider.recovery <= 0.0:
		return atan2(flat.x, flat.y)
	return rider.heading

func rider_focus() -> Vector3:
	if rider.visual and rider.visual.top_level:
		return rider.visual.global_position
	return rider.global_position

func _on_rider_event(kind: String, strength: float) -> void:
	match kind:
		"land", "land_sketchy":
			bump_velocity -= strength * 2.4
		"crash", "fatal", "tumble":
			shake = maxf(shake, strength * (0.22 if kind == "fatal" else 0.12))
			bump_velocity -= strength * 1.5

func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down", T.CAM_DEADZONE)
	var crashed := rider.recovery > 0.0 or rider.run.state == "ended"
	# Follow the direction of travel: firmly on snow, loosely in the air (tricks never
	# swing the view), frozen while tumbling, gently back to the fall line on get-up.
	var follow_rate := 0.0
	if not crashed:
		follow_rate = 1.1 if rider.airborne else lerpf(2.2, 3.4, smoothstep(5.0, 35.0, rider.speed))
	elif rider.getup_started:
		follow_rate = 1.4
	if rider.run.state == "ready":
		follow_rate = 3.0
	if follow_rate > 0.0:
		var before := follow_yaw
		follow_yaw = lerp_angle(follow_yaw, travel_yaw(), 1.0 - exp(-follow_rate * delta))
		follow_yaw = before + wrapf(follow_yaw - before, -PI, PI)
	update_drop_anticipation(delta)
	orbit_input(delta, stick, Input.is_action_just_pressed("recenter"))
	var speed := rider.speed
	boost_glow = lerpf(boost_glow, 1.0 if rider.boosting else 0.0, 1.0 - exp(-(6.0 if rider.boosting else 2.0) * delta))
	var target_distance := lerpf(T.CAM_DISTANCE_MIN, T.CAM_DISTANCE_MAX, smoothstep(3.0, 42.0, speed)) + boost_glow * 0.7
	if crashed:
		target_distance += 2.5
	distance = lerpf(distance, target_distance, 1.0 - exp(-2.2 * delta))
	# Anchor: horizontally locked to the rider, vertically sprung to absorb bumps.
	var focus := rider_focus() + Vector3.UP * 1.0
	var vertical_stiffness := 90.0 if rider.ground_contact else 45.0
	anchor_vertical_velocity += (focus.y - anchor.y) * vertical_stiffness * delta
	anchor_vertical_velocity *= exp(-14.0 * delta)
	anchor = Vector3(focus.x, anchor.y + anchor_vertical_velocity * delta, focus.z)
	if absf(anchor.y - focus.y) > 6.0:
		anchor.y = focus.y + clampf(anchor.y - focus.y, -6.0, 6.0)
	# Landing / impact nod: a damped spring, never random handheld shake.
	bump_velocity += -bump * 120.0 * delta
	bump_velocity *= exp(-10.0 * delta)
	bump = clampf(bump + bump_velocity * delta, -0.6, 0.6)
	shake = maxf(0.0, shake - delta * 0.6)
	var direction := Vector3(sin(orbit), 0, cos(orbit))
	var desired := anchor - direction * cos(lift) * distance + Vector3.UP * (sin(lift) * distance + 0.6)
	# Collision: retract instantly, re-extend slowly so dense trees never "pump".
	query.transform = Transform3D(Basis(), anchor)
	query.motion = desired - anchor
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	var allowed := 1.0
	if sweep[0] < 1.0:
		allowed = maxf(0.0, sweep[0] - 0.02)
	var boom := (desired - anchor).length()
	if allowed < clear_fraction:
		clear_fraction = allowed
	else:
		clear_fraction = minf(allowed, clear_fraction + T.CAM_REEXTEND_SPEED * delta / maxf(boom, 0.5))
	var position_now := anchor + (desired - anchor) * clear_fraction
	var floor_y := SnowMountain.height_at(position_now.x, position_now.z) + 0.55
	position_now.y = maxf(position_now.y, floor_y)
	position_now.y += bump
	var vibration := 0.0
	if rider.ground_contact and speed > 24.0:
		vibration = (speed - 24.0) / 30.0 * 0.012 * (1.0 + rider.surface.y * 1.5)
	var t := Time.get_ticks_msec() * 0.001
	var jitter := Vector3(sin(t * 71.0) + sin(t * 43.0), sin(t * 59.0) + sin(t * 97.0), 0) * (vibration + shake * 0.5) * 0.5
	global_position = position_now
	# Look ahead along the view direction; at speed, aim down toward the snow the
	# rider is about to reach so lips, drops and trees appear early.
	var chase := 1.0 - smoothstep(0.0, 0.6, absf(wrapf(look_yaw, -PI, PI))) * 0.6
	var lookahead := (3.0 + speed * 0.42) * chase
	if crashed:
		lookahead = 1.0
	var ahead := anchor + direction * lookahead
	var ground_ahead := SnowMountain.height_at(ahead.x, ahead.z) + 1.0
	var target_look := ahead
	target_look.y = lerpf(anchor.y, minf(anchor.y, ground_ahead), 0.55 * chase * smoothstep(4.0, 20.0, speed))
	look_point = look_point.lerp(target_look, 1.0 - exp(-12.0 * delta))
	if global_position.distance_squared_to(look_point) > 0.04:
		look_at(look_point + jitter)
	var target_fov := lerpf(T.CAM_FOV_REST, T.CAM_FOV_FAST, smoothstep(6.0, 45.0, speed)) + boost_glow * T.CAM_FOV_BOOST
	fov = lerpf(fov, target_fov, 1.0 - exp(-2.5 * delta))

## When the snow ahead falls away faster than the slope underfoot (a lip, gorge
## or cliff band) the boom rises so the player can see over the edge in time.
func update_drop_anticipation(delta: float) -> void:
	var target := 0.0
	if rider.run.state == "running" and rider.recovery <= 0.0 and rider.speed > 6.0:
		var dir := Vector3(sin(follow_yaw), 0, cos(follow_yaw))
		var p := rider.global_position
		var here := SnowMountain.height_at(p.x, p.z)
		var near_point := p + dir * 12.0
		var near_h := SnowMountain.height_at(near_point.x, near_point.z)
		var grade := (here - near_h) / 12.0
		var worst := 0.0
		for d in [30.0, 55.0, 85.0]:
			var q: Vector3 = p + dir * float(d)
			var expected: float = here - grade * float(d)
			worst = maxf(worst, (expected - SnowMountain.height_at(q.x, q.z)) / float(d))
		target = clampf(worst * 1.6, 0.0, 0.32)
	drop_raise = lerpf(drop_raise, target, 1.0 - exp(-1.5 * delta))
