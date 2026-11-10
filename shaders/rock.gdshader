shader_type spatial;
render_mode diffuse_burley;
// Faceted boulders and cliff outcrops: strata, lichen, snow caps on top faces.
// INSTANCE_CUSTOM: r = tone, g = snow amount.
#include "res://shaders/noise.gdshaderinc"
uniform vec3 stone_dark : source_color = vec3(0.11, 0.105, 0.10);
uniform vec3 stone_light : source_color = vec3(0.36, 0.34, 0.32);
uniform vec3 lichen : source_color = vec3(0.30, 0.27, 0.16);
uniform vec3 snow : source_color = vec3(0.80, 0.83, 0.88);
varying vec3 wpos;
varying vec4 inst;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	inst = INSTANCE_CUSTOM;
}
void fragment() {
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = fbm3(wpos.xz * 0.6 + wpos.y * 0.4);
	float strata = sin(wpos.y * 3.0 + n * 6.0) * 0.5 + 0.5;
	vec3 col = mix(stone_dark, stone_light, clamp(inst.r * 0.6 + strata * 0.3 + n * 0.3, 0.0, 1.0));
	col = mix(col, lichen, smoothstep(0.62, 0.8, vnoise(wpos.xz * 1.3)) * 0.35);
	float s = smoothstep(0.55, 0.8, nw.y + (n - 0.5) * 0.5 + inst.g * 0.25 - 0.1);
	ALBEDO = mix(col, snow, s);
	ROUGHNESS = mix(0.9, 0.75, s);
	SPECULAR = 0.3;
}
