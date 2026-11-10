shader_type spatial;
render_mode diffuse_burley, shadows_disabled;
// Distant ranges: snowfields on gentle faces, dark rock on steep ones, couloirs.
#include "res://shaders/noise.gdshaderinc"
uniform vec3 snow : source_color = vec3(0.80, 0.83, 0.88);
uniform vec3 rock : source_color = vec3(0.2, 0.2, 0.21);
uniform vec3 forest : source_color = vec3(0.06, 0.11, 0.09);
uniform float tree_line = 2100.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = fbm3(wpos.xz * 0.004);
	float gully = vnoise(vec2(wpos.x * 0.02 + wpos.z * 0.003, wpos.y * 0.004));
	float s = smoothstep(0.68, 0.84, nw.y + (n - 0.5) * 0.4 + (gully - 0.5) * 0.3);
	float trees = (1.0 - smoothstep(tree_line - 250.0, tree_line + 150.0, wpos.y + n * 300.0)) * smoothstep(0.62, 0.8, nw.y);
	vec3 ground = mix(snow, forest, trees * 0.8);
	float strata = sin(wpos.y * 0.035 + n * 8.0) * 0.5 + 0.5;
	vec3 r = rock * (0.6 + 0.5 * n + 0.35 * strata);
	ALBEDO = mix(r, ground, s);
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
