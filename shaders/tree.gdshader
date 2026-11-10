shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
// Conifers. COLOR.rgb = local shade, COLOR.a = snow load, UV.x 0 bark / 1 needles.
// INSTANCE_CUSTOM: r = snow multiplier, g = hue variation, b = sway phase.
#include "res://shaders/noise.gdshaderinc"
uniform vec3 needles : source_color = vec3(0.075, 0.15, 0.11);
uniform vec3 needles_alt : source_color = vec3(0.11, 0.17, 0.10);
uniform vec3 bark : source_color = vec3(0.21, 0.15, 0.11);
uniform vec3 snow : source_color = vec3(0.93, 0.95, 0.98);
varying vec4 vcol;
varying float foliage;
varying vec3 wpos;
varying vec4 inst;
void vertex() {
	vcol = COLOR;
	foliage = UV.x;
	inst = INSTANCE_CUSTOM;
	// Gentle sway of the upper boughs only; trunks (and colliders) stay put.
	float h = max(VERTEX.y - 3.0, 0.0);
	float sway = sin(TIME * 0.9 + inst.b * 6.28) * 0.012 * h * h / 20.0 * foliage;
	VERTEX.x += sway;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 green = mix(needles, needles_alt, inst.g) * vcol.rgb;
	float tuft = vnoise(wpos.xz * 3.0 + wpos.y * 2.0);
	green *= 0.8 + 0.4 * tuft;
	vec3 base = mix(bark * (0.8 + 0.3 * vnoise(vec2(wpos.y * 4.0, atan(wpos.x, wpos.z) * 3.0))), green, foliage);
	float s = clamp(vcol.a * inst.r * 1.25 + (vnoise(wpos.xz * 1.7 + wpos.y) - 0.5) * 0.8, 0.0, 1.0);
	s = smoothstep(0.35, 0.65, s);
	ALBEDO = mix(base, snow, s);
	ROUGHNESS = mix(0.85, 0.7, s);
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.05, 0.08, 0.04) * foliage * (1.0 - s);
}
