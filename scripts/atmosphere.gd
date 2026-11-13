class_name SnowAtmosphere
extends Node3D
## Sky, light, haze and exposure for the two presentations of the same mountain.
##
## The world is one 360-degree mountain, so the sky is composed for every view:
## DAY: the sun stands in the south-south-west at ~32 degrees; each face of the
## mountain is lit by its real orientation to it (north faces stay in cold
## shadow, south faces glow); cool sky ambient keeps shadowed snow blue-white and
## depth fog sells kilometres of scale.
## NIGHT: the moon in the east-south-east is the one real light (the same
## direction as its disc), the aurora owns the northern sky, the Milky Way arches
## from the south-west to the north-east, and stars fill everything (the sky
## shader's `aurora_dir` turns the curtains themselves, not just their glow). Exposure is
## raised so moonlit snow reads silver-blue and hazards stay readable at speed:
## visibility comes from moonlight, sky light and the snow's own response, never
## from a spotlight on the rider.
##
## `set_mode()` cross-fades between the two (it keeps animating while the game is
## paused, so the change is visible behind the pause menu). Everything that needs
## to follow the time of day reads the static `night_amount` / `fx_tint`.
##
## TWEAKABLE: every look parameter for both modes is in MODES below; sky features
## (moon size, star/Milky Way brightness, aurora strength and speed) are in
## SKY_NIGHT. Gameplay never reads any of it.
const SUN_DIRECTION := Vector3(-0.318, 0.530, 0.786)   # toward the sun (SSW, 32 deg up)
const MOON_DIRECTION := Vector3(0.826, 0.454, 0.334)   # toward the moon (ESE, 27 deg up)
const TRANSITION := 1.4                                # seconds to cross-fade

const MODES := {
	"day": {
		"light_direction": SUN_DIRECTION, "light_color": Color("fff1dc"), "light_energy": 1.75,
		"ambient_color": Color("c9d3de"), "ambient_sky": 0.6, "ambient_energy": 0.5,
		"exposure": 0.66, "contrast": 1.06, "saturation": 1.04,
		"fog_color": Color("b4c6d6"), "fog_density": 0.000085, "fog_scatter": 0.18, "fog_aerial": 0.35,
		"glow_intensity": 0.55, "glow_threshold": 1.15,
		"fx_tint": Color(1.0, 1.0, 1.0),
	},
	"night": {
		"light_direction": MOON_DIRECTION, "light_color": Color(0.80, 0.87, 1.0), "light_energy": 0.42,
		"ambient_color": Color(0.20, 0.26, 0.42), "ambient_sky": 0.3, "ambient_energy": 0.9,
		"exposure": 1.25, "contrast": 1.05, "saturation": 0.95,
		"fog_color": Color(0.035, 0.055, 0.11), "fog_density": 0.00006, "fog_scatter": 0.06, "fog_aerial": 0.5,
		"glow_intensity": 0.8, "glow_threshold": 0.9,
		"fx_tint": Color(0.30, 0.38, 0.58),   # unshaded snow particles under moonlight
	},
}
## Night sky features (uniforms of shaders/sky.gdshader).
const SKY_NIGHT := {
	"moon_size": 0.021, "moon_color": Vector3(1.0, 0.96, 0.88),
	"star_brightness": 1.0, "milky_way_brightness": 1.0,
	"aurora_strength": 1.0, "aurora_speed": 1.0,
}
## Aurora light falling on open snow (terrain shader), deliberately faint.
const AURORA_SNOW_TINT := Vector3(0.10, 0.55, 0.36)

## 0 = day, 1 = night (follows the cross-fade). Read by FX, rider glow, tests.
static var night_amount := 0.0
## Multiply unshaded particle colours by this so they sit in the current light.
static var fx_tint := Color(1.0, 1.0, 1.0)

var environment: Environment
var sun: DirectionalLight3D       # the sun by day, the moon by night
var sky_material: ShaderMaterial
var mode := "day"
var blend := 0.0                  # 0 day .. 1 night
var lit_materials: Array[ShaderMaterial] = []   # shaders that take `night` / `sun_direction`

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	environment = Environment.new()
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	sky_material.set_shader_parameter("sun_dir", SUN_DIRECTION)
	sky_material.set_shader_parameter("moon_dir", MOON_DIRECTION)
	for key in SKY_NIGHT:
		sky_material.set_shader_parameter(key, SKY_NIGHT[key])
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	# The animated parts (cirrus, aurora, twinkle) are left out of the light probe,
	# so it only needs refreshing when the time of day changes, a little per frame.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_energy = 1.0
	environment.fog_sky_affect = 0.0
	environment.fog_height = 900.0
	environment.fog_height_density = 0.0
	environment.glow_enabled = true
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.04
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.adjustment_enabled = true
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)
	apply()

## Switch presentation. `instant` skips the cross-fade (startup, tests, captures).
func set_mode(new_mode: String, instant := false) -> void:
	if not MODES.has(new_mode):
		return
	mode = new_mode
	if instant:
		blend = 1.0 if mode == "night" else 0.0
		apply()

func _process(delta: float) -> void:
	var target := 1.0 if mode == "night" else 0.0
	if blend != target:
		blend = move_toward(blend, target, delta / TRANSITION)
		apply()
	var camera := get_viewport().get_camera_3d()
	if camera:
		sky_material.set_shader_parameter("pixel_angle", deg_to_rad(camera.fov) / maxf(1.0, get_viewport().get_visible_rect().size.y))

func mix(key: String, t: float) -> Variant:
	var a = MODES["day"][key]
	var b = MODES["night"][key]
	if a is Color:
		return (a as Color).lerp(b, t)
	return lerpf(a, b, t)

## Push the current blend into the environment, the light and the shaders.
func apply() -> void:
	var t := smoothstep(0.0, 1.0, blend)
	night_amount = t
	fx_tint = mix("fx_tint", t)
	environment.ambient_light_color = mix("ambient_color", t)
	environment.ambient_light_sky_contribution = mix("ambient_sky", t)
	environment.ambient_light_energy = mix("ambient_energy", t)
	environment.tonemap_exposure = mix("exposure", t)
	environment.adjustment_contrast = mix("contrast", t)
	environment.adjustment_saturation = mix("saturation", t)
	environment.fog_light_color = mix("fog_color", t)
	environment.fog_density = mix("fog_density", t)
	environment.fog_sun_scatter = mix("fog_scatter", t)
	environment.fog_aerial_perspective = mix("fog_aerial", t)
	environment.glow_intensity = mix("glow_intensity", t)
	environment.glow_hdr_threshold = mix("glow_threshold", t)
	# One light cannot sweep from sun to moon: it dims out, changes sides at the
	# midpoint, and comes back up as the other body.
	var side: Dictionary = MODES["night"] if blend >= 0.5 else MODES["day"]
	var presence := smoothstep(0.5, 1.0, blend) if blend >= 0.5 else 1.0 - smoothstep(0.0, 0.5, blend)
	var direction: Vector3 = (side["light_direction"] as Vector3).normalized()
	sun.basis = Basis.looking_at(-direction, Vector3.UP)
	sun.light_color = side["light_color"]
	sun.light_energy = side["light_energy"] * presence
	sky_material.set_shader_parameter("night", t)
	for material in lit_materials:
		material.set_shader_parameter("night", t)
		material.set_shader_parameter("sun_direction", direction)
		material.set_shader_parameter("aurora_tint", AURORA_SNOW_TINT * SKY_NIGHT["aurora_strength"])
