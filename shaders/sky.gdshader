shader_type sky;
// SNOW sky, two presentations of the same place blended by `night` (0 day, 1 night).
// DAY: deep zenith, luminous horizon haze, sun disk and glow, slow high cirrus.
// NIGHT: a luminous moon with halo, stars in three stable layers (sized to the
// pixel so they never shimmer), the Milky Way with dust lanes, and aurora
// curtains with vertical rays that drift slowly. Everything is procedural: no
// textures, so nothing tiles or repeats.
#include "res://shaders/noise.gdshaderinc"

uniform float night = 0.0;
uniform vec3 sun_dir = vec3(-0.904, 0.425, 0.053);
uniform vec3 moon_dir = vec3(0.524, 0.454, 0.721);
uniform vec3 sun_color : source_color = vec3(1.0, 0.945, 0.86);
uniform float pixel_angle = 0.0005;       // radians per screen pixel (set by SnowAtmosphere)

// Day palette
uniform vec3 zenith : source_color = vec3(0.13, 0.30, 0.58);
uniform vec3 horizon : source_color = vec3(0.68, 0.79, 0.88);
uniform vec3 haze : source_color = vec3(0.80, 0.85, 0.90);
uniform vec3 below : source_color = vec3(0.56, 0.64, 0.72);

// Night palette and features (see SnowAtmosphere for the tweakable values)
uniform vec3 night_zenith = vec3(0.018, 0.032, 0.080);
uniform vec3 night_horizon = vec3(0.060, 0.105, 0.190);
uniform vec3 night_below = vec3(0.022, 0.038, 0.072);
uniform vec3 moon_color = vec3(1.0, 0.96, 0.88);
uniform float moon_size = 0.021;          // angular radius (rad); a little larger than life
uniform float star_brightness = 1.0;
uniform float milky_way_brightness = 1.0;
uniform vec3 galaxy_pole = vec3(-0.69, 0.25, -0.68); // normal of the Milky Way's plane: the band
                                                       // climbs from the horizon ahead-right over the zenith
uniform vec3 galaxy_core = vec3(-0.64, 0.42, 0.64);    // brightest direction along the band
uniform float aurora_strength = 1.0;
uniform vec2 aurora_dir = vec2(0.0, -1.0);              // horizontal direction the aurora owns (north)
uniform float aurora_speed = 1.0;

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), u.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), u.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), u.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm3d(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise3(p);
		p = p * 2.07 + vec3(11.3, 4.7, 7.9);
		a *= 0.5;
	}
	return v;
}

// One layer of stars: a 3D grid on the sky sphere, at most one star per cell,
// fixed in world space. `r` grows to cover at least ~1.3 pixels and the star is
// dimmed to match, so small stars stay steady instead of flickering as the
// camera moves.
vec3 star_layer(vec3 d, float cells, float chance, float size, float gain) {
	vec3 p = d * cells;
	vec3 c = floor(p);
	float h = hash13(c);
	if (h > chance) {
		return vec3(0.0);
	}
	vec3 sp = c + 0.28 + 0.44 * vec3(hash13(c + 3.1), hash13(c + 7.7), hash13(c + 13.3));
	float dist = length(p - normalize(sp) * cells);
	float r = max(size, pixel_angle * cells * 1.3);
	float core = smoothstep(r, 0.0, dist);
	float mag = pow(hash13(c + 21.9), 5.0);                      // few bright, many faint
	float twinkle = 0.9 + 0.1 * sin(TIME * (1.2 + h * 30.0) + h * 400.0);
	vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.86, 0.68), hash13(c + 5.5));
	tint = mix(vec3(1.0), tint, 0.55);
	return tint * core * core * (0.12 + mag) * gain * (size * size) / (r * r) * twinkle;
}

// Curtains of light: wavy sheet lines sampled on stacked altitude planes. Parallax
// between the planes extrudes each line into a vertical curtain; a streak
// pattern that is the SAME on every plane gives the fine vertical rays; slow
// noise along the sheet makes it brighten and fade in places. Green at the hem,
// cyan above, violet at the top, with a faint pink lower fringe.
vec3 aurora(vec3 d, float dither) {
	if (d.y < 0.02) {
		return vec3(0.0);
	}
	float t = TIME * 0.02 * aurora_speed;
	vec3 col = vec3(0.0);
	for (int i = 0; i < 16; i++) {
		// A per-pixel offset between the planes hides their stepping.
		float k = (float(i) + dither) / 16.0;
		float height = 0.8 + k * 1.15;
		vec2 uv = d.xz / (d.y + 0.14) * height;
		float warp = vnoise(uv * 0.3 + vec2(t, 0.0)) * 1.9 + vnoise(uv * 0.9 - vec2(0.0, t * 1.6)) * 0.5 + sin(uv.x * 0.22 + t * 1.3) * 0.9;
		float c1 = uv.y - (2.3 + warp);
		float c2 = uv.y - (4.3 + warp * 1.3 + sin(uv.x * 0.41 - t * 2.0) * 0.6);
		float c3 = uv.y - (1.25 + warp * 0.7);
		float along = uv.x * 0.45 + warp;
		float lit1 = smoothstep(0.25, 0.7, vnoise(vec2(along, t * 1.5)));
		float lit2 = smoothstep(0.3, 0.75, vnoise(vec2(along * 0.8 + 9.0, t * 1.2)));
		float lit3 = smoothstep(0.45, 0.8, vnoise(vec2(along * 1.3 + 21.0, t)));
		float sheets = exp(-c1 * c1 * 14.0) * lit1 + exp(-c2 * c2 * 7.0) * lit2 * 0.7 + exp(-c3 * c3 * 18.0) * lit3 * 0.6;
		float rays = 0.35 + 0.65 * smoothstep(0.2, 0.8, vnoise(vec2(uv.x * 7.0 + warp * 3.0, t * 2.5)));
		float profile = exp(-k * 2.0) * smoothstep(-0.03, 0.08, k);
		vec3 c = mix(vec3(0.16, 1.0, 0.50), vec3(0.10, 0.86, 0.90), smoothstep(0.1, 0.5, k));
		c = mix(c, vec3(0.62, 0.30, 1.0), smoothstep(0.38, 0.9, k));
		c = mix(c, vec3(1.0, 0.55, 0.75), (1.0 - smoothstep(0.0, 0.09, k)) * 0.3);
		col += c * sheets * rays * profile;
	}
	// It owns the northern sky (a broad arc either side of north, away from the
	// moon in the east-south-east) and thins toward the zenith and the horizon.
	float region = smoothstep(-0.5, 0.45, dot(normalize(d.xz + vec2(0.0001)), normalize(aurora_dir)));
	float alt = smoothstep(0.03, 0.18, d.y) * (1.0 - smoothstep(0.72, 0.97, d.y));
	return col * region * alt * 0.4 * aurora_strength;
}

// `probe` is true while the low-resolution light probe is drawn: broad light only.
vec3 day_sky(vec3 d, bool probe) {
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
	col = mix(col, haze, exp(-max(h, 0.0) * 18.0) * 0.6);
	if (h < 0.0) {
		col = mix(haze, below, clamp(-h * 4.0, 0.0, 1.0));
	}
	float cos_sun = dot(d, normalize(sun_dir));
	float glow = pow(max(cos_sun, 0.0), 8.0) * 0.25 + pow(max(cos_sun, 0.0), 120.0) * 0.6;
	col += sun_color * glow * 0.6;
	if (!probe && h > 0.0) {
		vec2 uv = d.xz / (h + 0.08) * 0.6;
		float c = fbm3(uv * 1.4 + vec2(TIME * 0.0015, 0.0));
		c *= vnoise(uv * 0.35 + 3.0);
		float cloud = smoothstep(0.32, 0.6, c) * smoothstep(0.0, 0.2, h);
		col = mix(col, vec3(1.0, 0.99, 0.97) + sun_color * glow * 0.3, cloud * 0.55);
		float disk = smoothstep(0.99985, 0.99995, cos_sun);
		col += sun_color * disk * 12.0;
	}
	return col;
}

vec3 night_sky(vec3 d, bool probe, float dither) {
	float h = d.y;
	vec3 m = normalize(moon_dir);
	float cos_moon = dot(d, m);
	vec3 col = mix(night_horizon, night_zenith, pow(clamp(h, 0.0, 1.0), 0.45));
	if (h < 0.0) {
		col = mix(night_horizon, night_below, clamp(-h * 5.0, 0.0, 1.0));
	}
	// Moonlit air: a wide soft bloom and a tighter halo around the moon.
	float halo = pow(max(cos_moon, 0.0), 14.0) * 0.10 + pow(max(cos_moon, 0.0), 220.0) * 0.28 + pow(max(cos_moon, 0.0), 2500.0) * 0.7;
	col += vec3(0.55, 0.68, 1.0) * halo;
	if (probe) {
		// Ambient/reflection probe: broad light only (moon glow, a breath of aurora).
		col += vec3(0.05, 0.22, 0.14) * 0.3 * aurora_strength * smoothstep(0.0, 0.4, h) * smoothstep(-0.2, 0.6, dot(d.xz, normalize(aurora_dir)));
		return col;
	}
	if (h > -0.02) {
		float clear = smoothstep(-0.02, 0.12, h);                    // stars drown in the horizon haze
		float lat = dot(d, normalize(galaxy_pole));
		float band = exp(-lat * lat / 0.06);
		float core = 0.5 + 0.5 * dot(d, normalize(galaxy_core));
		// The Milky Way: glowing star clouds split by darker dust lanes.
		if (band > 0.01) {
			float clouds = fbm3d(d * 5.5 + 2.0);
			float dust = fbm3d(d * 9.0 + 17.0);
			float lanes = smoothstep(0.42, 0.68, dust) * exp(-lat * lat / 0.009);
			float glow = band * (0.35 + 0.65 * core) * (0.25 + 1.1 * clouds * clouds) * (1.0 - 0.85 * lanes);
			vec3 mw = mix(vec3(0.50, 0.60, 0.90), vec3(1.0, 0.86, 0.70), core * clouds);
			col += mw * glow * 0.9 * milky_way_brightness * clear;
		}
		float dense = 1.0 + 3.0 * band;
		float moon_wash = 1.0 - 0.75 * pow(max(cos_moon, 0.0), 30.0);  // fewer stars beside the moon
		vec3 st = star_layer(d, 70.0, 0.12, 0.11, 9.0);
		st += star_layer(d, 150.0, 0.24 * min(dense, 2.0), 0.13, 3.6);
		st += star_layer(d, 330.0, 0.32 * min(dense, 2.6), 0.16, 1.6);
		col += st * star_brightness * clear * moon_wash;
		col += aurora(d, dither);
	}
	// The moon: limb darkening, soft maria, an ever so slightly warm face.
	float cos_r = cos(moon_size);
	if (cos_moon > cos_r - 0.0002) {
		float edge = smoothstep(cos_r - 0.00002, cos_r + 0.00004, cos_moon);
		float mu = sqrt(clamp((cos_moon - cos_r) / (1.0 - cos_r), 0.0, 1.0));
		vec3 local = (d - m * cos_moon) / max(moon_size, 0.0001);
		float maria = fbm3d(local * 2.6 + 4.0);
		float face = (0.72 + 0.28 * mu) * (1.0 - 0.38 * smoothstep(0.45, 0.7, maria));
		col = mix(col, moon_color * face * 3.2, edge);
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.0);
	if (night < 0.999) {
		col += day_sky(d, AT_CUBEMAP_PASS) * (1.0 - night);
	}
	if (night > 0.001) {
		col += night_sky(d, AT_CUBEMAP_PASS, hash12(SCREEN_UV * 1733.0)) * night;
	}
	COLOR = col;
}
