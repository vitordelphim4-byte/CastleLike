// Still water (rivers, lakes): translucent blue with a gentle ripple on the surface.
// The mesh is in world coordinates, so VERTEX doubles as the world position.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
#include "res://shaders/view_clip.gdshaderinc"

uniform float daylight = 1.0;  // set by day_night.gd: dims the water at night

varying vec3 wpos;

void vertex() {
	wpos = VERTEX;
	if (NORMAL.y > 0.5) {
		VERTEX.y += sin(TIME * 1.4 + VERTEX.x * 0.7 + VERTEX.z * 0.5) * 0.035;
	}
}

void fragment() {
	if (wpos.y > cut_y + 0.001 || xray_hit(wpos, CAMERA_POSITION_WORLD) > 1.5) {
		discard;
	}
	ALBEDO = vec3(0.1, 0.36, 0.66) * mix(0.3, 1.0, daylight);
	ALPHA = 0.74;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
