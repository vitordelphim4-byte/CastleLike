// Tall grass / flower tufts: two crossed quads with a pixel-art tile (alpha cut out) + wind sway
// (tips move, base stays).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/view_clip.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest_mipmap;

varying vec3 wpos;
varying float base_y;

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	base_y = wp.y;
	float w = sin(TIME * 1.8 + wp.x * 0.8 + wp.z * 0.6) * 0.07 * VERTEX.y / 0.6;
	VERTEX.xz += vec2(w, w * 0.6);
	NORMAL = vec3(0.0, 1.0, 0.0); // lit like the ground, not like a wall
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(tex, UV);
	// A tuft stands on its block: hidden with the cell it grows in (feet level above the cut).
	if (c.a < 0.5 || base_y > cut_y + 0.5 || xray_hit(wpos, CAMERA_POSITION_WORLD) > 1.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.4); // light shines through the blades: thin leaves, not a solid lump
}
