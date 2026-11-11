shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Mountain surface. Vertex COLOR carries the same surface data the rider physics
// uses: r = powder, g = wind-scoured ice, b = exposed rock / lip scour, a = AO.
// Detail (sastrugi ripples, bumps, strata, glints) is fully procedural.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.80, 0.83, 0.88);
uniform vec3 powder_color : source_color = vec3(0.86, 0.88, 0.92);
uniform vec3 ice_color : source_color = vec3(0.58, 0.66, 0.76);
uniform vec3 rock_dark : source_color = vec3(0.16, 0.155, 0.15);
uniform vec3 rock_light : source_color = vec3(0.42, 0.40, 0.37);
uniform vec2 wind_dir = vec2(0.92, 0.38);
uniform float detail_strength = 1.0;
uniform vec3 sun_direction = vec3(-0.904, 0.425, 0.053);   // toward the sun, or the moon at night
uniform float night = 0.0;                                 // 0 day .. 1 night
uniform vec3 aurora_tint = vec3(0.10, 0.55, 0.36);

varying vec3 wpos;
varying vec4 surf;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surf = COLOR;
}

float ripple(vec2 p) {
	// Wind-carved sastrugi: elongated ridges perpendicular to the wind, domain-warped.
	vec2 w = normalize(wind_dir);
	float along = dot(p, w);
	float across = dot(p, vec2(-w.y, w.x));
	float warp = vnoise(p * 0.045) * 7.0 + vnoise(p * 0.21) * 1.2;
	float r = sin(along * 1.25 + warp + sin(across * 0.08) * 2.0);
	return r * r * (0.55 + 0.45 * vnoise(p * 0.11));
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near_fade = 1.0 - smoothstep(35.0, 260.0, dist);
	float mid_fade = 1.0 - smoothstep(150.0, 900.0, dist);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 p = wpos.xz;
	float powder = surf.r;
	float ice = surf.g;
	// Rock where the terrain is steep or scoured, with ragged noisy boundaries.
	float breakup = fbm3(p * 0.09 + wpos.y * 0.05);
	float rock = smoothstep(0.42, 0.68, surf.b + (breakup - 0.5) * 0.55);
	rock = max(rock, smoothstep(0.58, 0.42, nw.y + (breakup - 0.5) * 0.18));
	// Detail normal from analytic finite differences of procedural height fields.
	float e = 0.12;
	float sas_amp = (0.07 + ice * 0.07 - powder * 0.05) * near_fade;
	float bump_amp = (0.32 + powder * 0.18) * mid_fade;
	float h0 = ripple(p) * sas_amp + fbm3(p * 0.33) * bump_amp + vnoise(p * 2.6) * 0.012 * near_fade;
	float hx = ripple(p + vec2(e, 0.0)) * sas_amp + fbm3((p + vec2(e, 0.0)) * 0.33) * bump_amp + vnoise((p + vec2(e, 0.0)) * 2.6) * 0.012 * near_fade;
	float hz = ripple(p + vec2(0.0, e)) * sas_amp + fbm3((p + vec2(0.0, e)) * 0.33) * bump_amp + vnoise((p + vec2(0.0, e)) * 2.6) * 0.012 * near_fade;
	vec3 detail_n = normalize(nw - vec3((hx - h0) / e, 0.0, (hz - h0) / e) * detail_strength * (1.0 - rock));
	// Rock strata: horizontal bands warped by noise, darker in cracks.
	float strata = sin(wpos.y * 1.3 + fbm3(p * 0.04) * 9.0) * 0.5 + 0.5;
	float crack = smoothstep(0.75, 0.95, vnoise(vec2(wpos.y * 2.0, dot(p, vec2(0.7, 0.7)) * 0.35)));
	vec3 rock_col = mix(rock_dark, rock_light, strata * 0.3 + breakup * 0.6) * (1.0 - crack * 0.45);
	rock_col *= mix(vec3(1.0), vec3(1.05, 0.98, 0.9), vnoise(p * 0.02));
	// Snow on rock ledges facing up.
	float ledge_snow = smoothstep(0.62, 0.86, nw.y + (vnoise(p * 0.7) - 0.5) * 0.3);
	rock = rock * (1.0 - ledge_snow * 0.85);
	// Snow albedo: packed / powder / ice blend with broad wind-shaded mottling.
	float broad = fbm3(p * 0.012);
	vec3 snow = mix(snow_color, powder_color, powder);
	snow = mix(snow, ice_color, ice * 0.85);
	snow *= 0.93 + 0.07 * broad;
	// Subtle blue in ripple troughs reads as fine relief at riding distance.
	snow = mix(snow, snow * vec3(0.86, 0.91, 1.0), clamp((sas_amp > 0.0 ? ripple(p) : 0.0) * 0.35 * near_fade, 0.0, 0.3));
	float ao = surf.a;
	ALBEDO = mix(snow, rock_col, rock) * mix(0.55, 1.0, ao);
	// Moonlit snow is glossier: a soft silver sheen and a glitter path toward the moon.
	ROUGHNESS = mix(mix(0.72, 0.88, powder) * (1.0 - ice * 0.55) * mix(1.0, 0.72, night), 0.92, rock);
	SPECULAR = mix(mix(0.42, 0.62, night), 0.25, rock);
	// Crystal glints: facets fixed in the snow that flash when they line up with
	// the light. Two scales; each dot grows with distance so it never drops below
	// about a pixel (no shimmer at speed) and fades out before it could alias.
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 light_w = normalize(sun_direction);
	float sparkle = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 7.0 : 2.6;
		float reach = layer == 0 ? 60.0 : 170.0;
		vec3 q = wpos * scale;
		vec3 cell = floor(q);
		float g = hash13(cell + float(layer) * 31.0);
		vec3 in_cell = fract(q) - vec3(0.25 + 0.5 * hash13(cell + 2.1), 0.5, 0.25 + 0.5 * hash13(cell + 8.4));
		float radius = clamp(0.05 + dist * scale * 0.0011, 0.05, 0.24);
		float dot_mask = 1.0 - smoothstep(radius * 0.5, radius, length(in_cell.xz));
		vec3 facet = normalize(vec3(hash13(cell + 1.7), 1.6, hash13(cell + 5.3)) - vec3(0.5, 0.0, 0.5));
		float aligned = pow(max(dot(reflect(-light_w, facet), view_w), 0.0), mix(90.0, 36.0, night));
		float density = step(mix(0.8, 0.62, night), g);
		sparkle += aligned * density * dot_mask * (0.05 / radius) * (1.0 - smoothstep(reach * 0.5, reach, dist));
	}
	vec3 glint = mix(vec3(1.0, 0.97, 0.9) * 1.6, vec3(0.72, 0.85, 1.0) * 2.4, night);
	float open_snow = (1.0 - rock) * (1.0 - powder * 0.5);
	EMISSION = glint * sparkle * open_snow;
	// Night only: a cold frost sheen at grazing angles and the faintest breath of
	// aurora colour on open, sky-facing snow. Moonlight stays the main light.
	float grazing = pow(1.0 - max(dot(detail_n, view_w), 0.0), 4.0);
	float aurora_wash = 0.6 + 0.4 * vnoise(p * 0.004 + vec2(TIME * 0.01, 0.0));
	EMISSION += night * (1.0 - rock) * (vec3(0.20, 0.32, 0.60) * grazing * 0.035 + aurora_tint * aurora_wash * smoothstep(0.6, 0.95, nw.y) * 0.02);
	NORMAL = normalize((VIEW_MATRIX * vec4(detail_n, 0.0)).xyz);
}
