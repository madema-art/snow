shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, diffuse_burley;
// Board track: a pressed groove that shades slightly darker/bluer than the
// surrounding snow with raised, brighter spoil at its edges. Fades with distance.
uniform vec3 groove : source_color = vec3(0.70, 0.75, 0.84);
uniform vec3 spoil : source_color = vec3(0.86, 0.88, 0.92);
varying vec3 wpos;
varying float depth;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = COLOR.a;
	NORMAL = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}
void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float edge = smoothstep(0.65, 1.0, across);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	ALBEDO = mix(groove, spoil, edge);
	ROUGHNESS = mix(0.45, 0.85, edge);
	ALPHA = depth * (0.42 - edge * 0.2) * (1.0 - smoothstep(120.0, 260.0, dist)) * (1.0 - smoothstep(0.92, 1.0, across));
}
