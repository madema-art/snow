shader_type sky;
// Alpine sky: deep zenith, luminous haze at the horizon, sun disk and glow,
// and slow high cirrus. Valley haze below the horizon blends with distance fog.
#include "res://shaders/noise.gdshaderinc"
uniform vec3 zenith : source_color = vec3(0.13, 0.30, 0.58);
uniform vec3 horizon : source_color = vec3(0.68, 0.79, 0.88);
uniform vec3 haze : source_color = vec3(0.80, 0.85, 0.90);
uniform vec3 below : source_color = vec3(0.56, 0.64, 0.72);
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
	col = mix(col, haze, exp(-max(h, 0.0) * 18.0) * 0.6);
	if (h < 0.0) {
		col = mix(haze, below, clamp(-h * 4.0, 0.0, 1.0));
	}
	vec3 sun = LIGHT0_DIRECTION;
	float cos_sun = dot(d, sun);
	float glow = pow(max(cos_sun, 0.0), 8.0) * 0.25 + pow(max(cos_sun, 0.0), 120.0) * 0.6;
	col += LIGHT0_COLOR * glow * 0.6;
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec2 uv = d.xz / (h + 0.08) * 0.6;
		float c = fbm3(uv * 1.4 + vec2(TIME * 0.0015, 0.0));
		c *= vnoise(uv * 0.35 + 3.0);
		float cloud = smoothstep(0.32, 0.6, c) * smoothstep(0.0, 0.2, h);
		col = mix(col, vec3(1.0, 0.99, 0.97) + LIGHT0_COLOR * glow * 0.3, cloud * 0.55);
		float disk = smoothstep(0.99985, 0.99995, cos_sun);
		col += LIGHT0_COLOR * disk * 12.0;
	}
	COLOR = col;
}
