shader_type spatial;
// Cel shading: one hard light/shadow edge, tinted shadows, a thin rim light.
// Back faces can use a different color (used for robe and sleeve linings).
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_inner = false;
uniform vec4 inner_color : source_color = vec4(0.1, 0.55, 0.6, 1.0);
uniform vec4 shade : source_color = vec4(0.42, 0.4, 0.62, 1.0);
uniform float rim_strength = 0.35;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform bool use_vertex_color = false;
uniform bool ground_noise = false;
uniform vec4 ground_alt : source_color = vec4(0.22, 0.4, 0.16, 1.0);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	if (ground_noise) {
		float n = vnoise(world_pos.xz * 0.08) * 0.65 + vnoise(world_pos.xz * 0.35) * 0.35;
		c = mix(c, ground_alt.rgb, smoothstep(0.35, 0.75, n));
	}
	if (use_inner && !FRONT_FACING) {
		c = inner_color.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = emission_color.rgb * emission_energy;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = smoothstep(0.0, 0.05, nl) * smoothstep(0.35, 0.65, ATTENUATION);
		vec3 band = mix(shade.rgb, vec3(1.0), lit);
		DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
		float rim = smoothstep(0.66, 0.72, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * lit;
		SPECULAR_LIGHT += rim * rim_strength * LIGHT_COLOR / PI * ALBEDO;
	} else {
		DIFFUSE_LIGHT += smoothstep(0.0, 0.2, nl) * ATTENUATION * LIGHT_COLOR / PI * 0.6;
	}
}
