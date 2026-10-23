// Castle Story-like block texture: 8x8 pixel noise per face, darker block edges,
// grass blocks show dirt on the sides with a jagged green lip.
// COLOR.rgb = block base color, COLOR.a = baked ambient occlusion, UV.x = block type.
shader_type spatial;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	wpos = VERTEX; // world mesh sits at the origin
	wnorm = NORMAL;
}

void fragment() {
	vec3 cell = floor(wpos - wnorm * 0.01);
	vec3 local = wpos - cell;
	vec2 f = abs(wnorm.x) > 0.5 ? local.zy : (abs(wnorm.y) > 0.5 ? local.xz : local.xy);
	vec2 px = floor(f * 8.0);
	vec3 col = COLOR.rgb;
	int t = int(UV.x + 0.5);
	if (t == 1 && abs(wnorm.y) < 0.5) { // grass side
		float lip = 0.75 - 0.125 * floor(hash(cell + vec3(px.x, 3.0, wnorm.x + wnorm.z * 2.0)) * 2.5);
		if (f.y < lip) col = vec3(0.45, 0.30, 0.18);
	} else if (t == 4) { // wood planks
		float row = floor(f.y * 4.0);
		col *= 0.85 + 0.25 * hash(cell + vec3(row, 9.0, 1.0));
		if (fract(f.y * 4.0) < 0.1) col *= 0.6;
	} else if (t == 9) { // iron ore: stone with rust-colored specks
		float h = hash(cell * 3.7 + vec3(px, dot(wnorm, vec3(1.0, 2.0, 3.0))));
		if (h > 0.8) col = vec3(0.78, 0.45, 0.26);
		else if (h > 0.7) col = vec3(0.58, 0.36, 0.24);
	} else if (t == 5) { // stone bricks with mortar
		float row = floor(f.y * 4.0);
		float shifted = f.x * 2.0 + mod(row, 2.0) * 0.5;
		if (fract(f.y * 4.0) < 0.14 || fract(shifted) < 0.07) col = vec3(0.8, 0.78, 0.72);
		else col *= 0.85 + 0.25 * hash(cell + vec3(row, floor(shifted), 5.0));
	}
	col *= 0.86 + 0.2 * hash(cell * 7.13 + vec3(px, dot(wnorm, vec3(1.0, 2.0, 3.0))));
	col *= 0.93 + 0.07 * hash(cell);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	col *= mix(0.78, 1.0, smoothstep(0.0, 0.07, edge));
	ALBEDO = pow(col, vec3(2.2)) * COLOR.a; // colors are authored in sRGB
}
