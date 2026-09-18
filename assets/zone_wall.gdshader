shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// Dense floor line dissolving upward, so the wall reads as a boundary rather
// than a slab of colour painted across the sky.
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Bands are anchored to world height. A fixed band count around the ring
	// instead compresses to sub-pixel stripes at the horizon and aliases into
	// vertical streaks.
	float scan = pow(max(sin(world_pos.y * 1.6 - TIME * 1.6), 0.0), 8.0);
	float seams = pow(max(sin(UV.x * TAU * 24.0), 0.0), 40.0);
	// Grazing views of the far wall are what smeared; fade them out.
	float facing = abs(dot(normalize(NORMAL), vec3(0.0, 0.0, 1.0)));
	float graze = smoothstep(0.02, 0.45, facing);
	float floorline = smoothstep(34.0, 0.0, world_pos.y);
	float glow = (0.055 + scan * 0.16 + seams * 0.10) * floorline * graze;
	ALBEDO = vec3(0.16, 0.49, 1.0);
	ALPHA = clamp(glow, 0.0, 0.42);
}
