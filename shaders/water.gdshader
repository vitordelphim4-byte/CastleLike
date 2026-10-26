// Water: translucent blue, a gentle ripple on top, and moving streaks where it flows (Phase 10e2).
// The mesh is in world coordinates, so VERTEX doubles as the world position.
// COLOR (World._water_flow): r, g = flow direction on x, z (0.5 = still), b = 1 on a falling column.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
#include "res://shaders/view_clip.gdshaderinc"

uniform float daylight = 1.0;  // set by day_night.gd: dims the water at night

varying vec3 wpos;
varying vec3 flow;  // x, z = direction, y = falling

void vertex() {
	wpos = VERTEX;
	flow = vec3(COLOR.r * 2.0 - 1.0, COLOR.b, COLOR.g * 2.0 - 1.0);
	if (NORMAL.y > 0.5) {
		VERTEX.y += sin(TIME * 1.4 + VERTEX.x * 0.7 + VERTEX.z * 0.5) * 0.035;
	}
}

void fragment() {
	if (wpos.y > cut_y + 0.001 || xray_hit(wpos, CAMERA_POSITION_WORLD) > 1.5) {
		discard;
	}
	float streak = 0.0;
	if (flow.y > 0.5) {  // waterfall: streaks rushing down
		float lane = floor((wpos.x + wpos.z) * 6.0);
		streak = smoothstep(0.55, 1.0, sin(wpos.y * 4.0 + TIME * 9.0 + sin(lane * 12.9898) * 6.0)) * 0.45;
	} else if (length(flow.xz) > 0.1) {  // current: streaks running downstream
		vec2 dir = normalize(flow.xz);
		float along = dot(wpos.xz, dir);
		float across = dot(wpos.xz, vec2(-dir.y, dir.x));
		streak = smoothstep(0.7, 1.0, sin(along * 5.0 - TIME * 5.0 + sin(across * 2.7) * 2.0)) * 0.2;
	}
	vec3 base = vec3(0.1, 0.36, 0.66);
	ALBEDO = mix(base, vec3(0.75, 0.88, 1.0), streak) * mix(0.3, 1.0, daylight);
	ALPHA = 0.74 + streak * 0.2;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
