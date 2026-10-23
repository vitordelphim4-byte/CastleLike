// Tall grass / flower tufts: vertex colors + wind sway (tips move, base stays).
shader_type spatial;
render_mode cull_disabled;

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float w = sin(TIME * 1.8 + wp.x * 0.8 + wp.z * 0.6) * 0.07 * VERTEX.y / 0.45;
	VERTEX.xz += vec2(w, w * 0.6);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)); // colors are authored in sRGB
}
