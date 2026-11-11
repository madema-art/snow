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
	// Ridged/gullied relief below the mesh resolution so faces are not flat planes.
	vec2 q = wpos.xz * 0.018 + wpos.y * 0.004;
	float d0 = fbm3(q);
	float dx = fbm3(q + vec2(0.05, 0.0));
	float dz = fbm3(q + vec2(0.0, 0.05));
	nw = normalize(nw - vec3(dx - d0, 0.0, dz - d0) * 5.0);
	float n = fbm3(wpos.xz * 0.004);
	float gully = vnoise(vec2(wpos.x * 0.02 + wpos.z * 0.003, wpos.y * 0.004));
	float s = smoothstep(0.6, 0.8, nw.y + (n - 0.5) * 0.4 + (gully - 0.5) * 0.3);
	float trees = (1.0 - smoothstep(tree_line - 250.0, tree_line + 150.0, wpos.y + n * 300.0)) * smoothstep(0.62, 0.8, nw.y);
	// Timber grows in patches and stands, never as a uniform dark carpet.
	float stands = smoothstep(0.42, 0.62, vnoise(wpos.xz * 0.0035) * 0.7 + vnoise(wpos.xz * 0.02) * 0.3);
	vec3 ground = mix(snow, forest, trees * stands * 0.6);
	float strata = sin(wpos.y * 0.035 + n * 8.0) * 0.5 + 0.5;
	vec3 r = rock * (0.8 + 0.45 * n + 0.08 * strata);
	ALBEDO = mix(r, ground, s);
	ROUGHNESS = 0.9;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	SPECULAR = 0.25;
}
