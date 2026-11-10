class_name SnowCamera
extends Camera3D
## Absolute world yaw: manual orbit never modifies rider steering or travel.
const PITCH_MIN := -0.35
const PITCH_MAX := 1.25
const IDLE_DELAY := 3.0
var rider: SnowRider
var orbit := 0.0
var lift := 0.32
var idle := 0.0
var recentering := false
var sphere := SphereShape3D.new()
var query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	current = true
	near = 0.12
	far = 6500
	sphere.radius = 0.45
	query.shape = sphere
	query.collision_mask = 3
	reset()

func reset() -> void:
	orbit = rider.heading
	lift = 0.32
	idle = 0
	recentering = false
	fov = 72
	global_position = rider.position + Vector3(0, 5, -12)
	look_at(rider.position + Vector3(0, 0, 12))

func orbit_input(delta: float, stick: Vector2, recenter: bool) -> void:
	if stick.length() > 0.001:
		idle = 0
		recentering = false
		var response := stick.normalized() * pow(minf(stick.length(), 1), 1.35)
		orbit -= response.x * 2.65 * delta
		lift = clampf(lift + response.y * 1.8 * delta, PITCH_MIN, PITCH_MAX)
	else:
		idle += delta
	if recenter and stick.length() <= 0.001:
		recentering = true
	if recentering or idle > IDLE_DELAY:
		var gain := 5.0 if recentering else 0.85
		orbit = lerp_angle(orbit, rider.heading, 1.0 - exp(-gain * delta))
		lift = lerpf(lift, 0.32, 1.0 - exp(-gain * delta))
		if absf(wrapf(orbit - rider.heading, -PI, PI)) < 0.01 and absf(lift - 0.32) < 0.01:
			recentering = false

func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.18)
	orbit_input(delta, stick, Input.is_action_just_pressed("recenter"))
	var direction := Vector3(sin(orbit), 0, cos(orbit))
	var distance := 11.0 + minf(rider.speed, 65) * 0.10
	var anchor := rider.position + Vector3.UP * 1.0
	var desired := anchor - direction * cos(lift) * distance + Vector3.UP * (sin(lift) * distance + 1.0)
	query.transform = Transform3D(Basis(), anchor)
	query.motion = desired - anchor
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	if sweep[0] < 1:
		desired = anchor + query.motion * maxf(0.0, sweep[0] - 0.025)
	# Low latency while orbiting; still soften chase displacement.
	global_position = global_position.lerp(desired, 1.0 - exp(-18 * delta))
	query.motion = global_position - anchor
	sweep = get_world_3d().direct_space_state.cast_motion(query)
	if sweep[0] < 1:
		global_position = anchor + query.motion * maxf(0.0, sweep[0] - 0.025)
	var chase_weight := smoothstep(2, 4, idle) if not recentering else 1.0
	var look := anchor + direction * (5.0 + rider.speed * 0.23) * chase_weight
	# Anticipate the grade, but never pull a manual view toward a distant gorge floor.
	if chase_weight > 0 and rider.is_on_floor():
		look.y -= minf(6, rider.speed * 0.13) * chase_weight
	if global_position.distance_squared_to(look) > 0.01: look_at(look)
	fov = lerpf(fov, 72.0 + minf(rider.speed / 6.0, 11), 1.0 - exp(-3 * delta))
