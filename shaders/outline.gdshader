shader_type spatial;
// Inverted-hull outline: draws the back of a slightly inflated copy in a dark color.
// The width scales with camera distance so lines stay about the same thickness on screen.
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 color : source_color = vec4(0.07, 0.03, 0.1, 1.0);
uniform float thickness = 0.0028;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = clamp(length(wp - CAMERA_POSITION_WORLD), 1.5, 40.0);
	float s = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += NORMAL * thickness * d / s;
}

void fragment() {
	ALBEDO = color.rgb;
}
