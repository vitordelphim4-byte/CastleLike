// Villager outline seen through walls and ground: drawn on top of everything (material_overlay),
// but only where something else is in front of the villager. Tint = the villager's color.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
instance uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.3, 1.0);

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	// Nothing in front (the villager's own body is within the margin): the normal mesh shows.
	if (-v.z / v.w > -VERTEX.z - 0.6) {
		discard;
	}
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = tint.rgb;
	ALPHA = 0.3 + 0.55 * rim;
}
