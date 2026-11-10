shader_type canvas_item;
// Frosted-glass pause backdrop: a wide 13-tap blur of the frozen frame, cooled
// and darkened toward the left where the text sits.
uniform sampler2D screen : hint_screen_texture, filter_linear;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 9.0;
	vec3 c = texture(screen, SCREEN_UV).rgb * 0.2;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236;
		float r = (i % 2 == 0) ? 1.0 : 2.2;
		c += texture(screen, SCREEN_UV + vec2(cos(a), sin(a)) * px * r).rgb * (0.8 / 12.0);
	}
	vec3 cool = mix(c, vec3(0.02, 0.05, 0.09), 0.72 - SCREEN_UV.x * 0.12);
	COLOR = vec4(cool, 1.0);
}
