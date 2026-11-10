shader_type spatial;
render_mode specular_disabled;
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 cell=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	// World-space wind-packed snow: mottling and fine ridges reveal scale without textures.
	float broad=noise(world_position.xz*0.045);
	float grain=noise(world_position.xz*2.5);
	float ridges=sin(world_position.x*4.0+noise(world_position.xz*0.1)*8.0)*0.012;
	ALBEDO=COLOR.rgb*vec3(0.38,0.45,0.53)*(0.78+broad*0.20+grain*0.065+ridges);
	ROUGHNESS=0.96;
}
