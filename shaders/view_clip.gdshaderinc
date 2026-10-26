// Phase 9 "see inside the ground", shared by terrain, water and grass (World sets the uniforms).
// Layer cut: everything above cut_y is not drawn. X-ray: a screen-round hole (cone from the camera)
// through whatever stands between the camera and each xray point (w = 1 active).
uniform float cut_y = 10000.0;
uniform vec4 xray[9];
uniform float xray_radius = 2.2;  // hole radius, in blocks, at the target's distance

// 0 = keep, 1 = on the hole's rim (darken), 2 = inside the hole (discard).
float xray_hit(vec3 p, vec3 cam) {
	float rim = 0.0;
	for (int i = 0; i < 9; i++) {
		if (xray[i].w < 0.5) {
			continue;
		}
		vec3 d = xray[i].xyz - cam;
		float len = length(d);
		vec3 dir = d / len;
		vec3 f = p - cam;
		float t = dot(f, dir);
		if (t <= 0.0 || t > len - 1.0) {
			continue;  // behind the camera, or at / past the target: keep
		}
		float r = length(f - dir * t) / t * len;
		if (r < xray_radius) {
			return 2.0;
		}
		if (r < xray_radius + 0.15) {
			rim = 1.0;
		}
	}
	return rim;
}
