class_name SnowAtmosphere
extends Node3D
## Daylight, sky, haze and exposure. Low raking sun from ahead-right of the fall
## line models every roll and lip with long shadows; cool sky ambient keeps
## shadowed snow blue-white and readable instead of grey. Atmospheric depth fog
## sells kilometres of scale without hiding hazards within riding distance.
const SUN_DIRECTION := Vector3(-0.45, 0.48, 0.75) # toward the sun (shared by shaders)
var environment: Environment
var sun: DirectionalLight3D

func _ready() -> void:
	environment = Environment.new()
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Mostly sky light, partly a neutral pale fill: blue-white shadows, not saturated blue.
	environment.ambient_light_color = Color("c9d3de")
	environment.ambient_light_sky_contribution = 0.6
	environment.ambient_light_energy = 0.6
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.66
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("b4c6d6")
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.18
	environment.fog_density = 0.000085
	environment.fog_aerial_perspective = 0.35
	environment.fog_sky_affect = 0.0
	environment.fog_height = 900.0
	environment.fog_height_density = 0.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.15
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.04
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(-SUN_DIRECTION.normalized(), Vector3.UP)
	sun.light_color = Color("fff1dc")
	sun.light_energy = 1.3
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
