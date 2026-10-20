shader_type spatial;
// Procedural cracked stone for floor tiles that give way (see cracked_floor.gd).
//
// Two layers of cracks, both drawn on the tile's top face only:
//  - a coarse network that is always there, and
//  - a finer network, plus wider main cracks, that spreads out from `spread_origin` (where
//    the player stands) as `spread` rises from 0 to 1. It stops where it is when the player
//    steps off, because the script stops raising `spread`.
// The cracks are the borders between random cells, bent by zigzag waves so they run in short
// straight jagged segments that change direction suddenly, like fractured stone.

uniform vec4 stone_color : source_color = vec4(0.52, 0.49, 0.44, 1.0);
uniform vec4 crack_color : source_color = vec4(0.015, 0.012, 0.012, 1.0);
// Coarse crack cells per metre, and how wide a crack is (in cell units) at rest.
uniform float crack_scale = 1.1;
uniform float crack_width = 0.02;
// How much wider the main cracks get once the spread has reached them.
uniform float spread_widening = 0.008;
// How far the spread can reach from where it starts, in metres, and how ragged its front is.
uniform float spread_reach = 4.6;
uniform float front_roughness = 1.1;
// How hard the zigzag waves push the cracks sideways (metres): bigger = more jagged.
uniform float jaggedness = 0.09;

// Set per tile from code, so one material serves every tile.
instance uniform float pattern_seed = 0.0;
instance uniform float spread : hint_range(0.0, 1.0) = 0.0;
instance uniform vec2 spread_origin = vec2(0.0, 0.0);

varying vec3 local_position;
varying vec3 local_normal;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Smooth random value between 0 and 1.
float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1(cell);
	float b = hash1(cell + vec2(1.0, 0.0));
	float c = hash1(cell + vec2(0.0, 1.0));
	float d = hash1(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// A triangle wave from 0 to 1: straight slopes that turn round abruptly.
float tri(float x) {
	return abs(fract(x) - 0.5) * 2.0;
}

// A sideways push that bends cracks into jagged runs.
vec2 jag(vec2 q) {
	// Gentle, large bends so the cracks don't all lean the same way.
	vec2 bend = (vec2(value_noise(q * 1.1), value_noise(q * 1.1 + 31.4)) - 0.5) * jaggedness * 1.6;
	// Sharp zigzags at two scales.
	vec2 zig_a = vec2(tri(q.y * 3.7 + q.x * 1.3), tri(q.x * 3.9 - q.y * 1.1)) - 0.5;
	vec2 zig_b = vec2(tri(q.y * 9.3 + q.x * 2.9 + 0.37), tri(q.x * 8.7 - q.y * 3.7 + 0.71)) - 0.5;
	return bend + (zig_a + zig_b * 0.45) * jaggedness;
}

// The exact distance from a point to the nearest border between two cells (0 = on a crack),
// in cell units. Finds the closest cell centre first, then the closest border to it.
float crack_distance(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);

	vec2 nearest_offset = vec2(0.0);
	vec2 nearest_vector = vec2(0.0);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 to_point = offset + hash2(cell + offset + pattern_seed) - local;
			float d = dot(to_point, to_point);
			if (d < nearest) {
				nearest = d;
				nearest_vector = to_point;
				nearest_offset = offset;
			}
		}
	}

	float border = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 offset = nearest_offset + vec2(float(x), float(y));
			vec2 to_point = offset + hash2(cell + offset + pattern_seed) - local;
			vec2 gap = to_point - nearest_vector;
			if (dot(gap, gap) > 0.00001) {
				border = min(border, dot(0.5 * (nearest_vector + to_point), normalize(gap)));
			}
		}
	}
	return border;
}

float crack_line(vec2 p, float width) {
	return 1.0 - smoothstep(width, width * 2.0, crack_distance(p));
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec2 q = local_position.xz;
	vec2 bent = q + jag(q + pattern_seed);
	// A crack is wider in some places than others.
	float taper = 0.65 + 0.6 * value_noise(q * 3.0 + pattern_seed);

	// How far the spread has got: everything within its radius of the origin, with a ragged edge.
	float radius = spread * spread_reach;
	float ragged = (value_noise(q * 2.5 + pattern_seed) - 0.5) * front_roughness;
	float reached = (1.0 - smoothstep(radius - 0.3, radius + 0.3, distance(q, spread_origin) + ragged))
			* smoothstep(0.0, 0.04, spread);

	float coarse = crack_line(bent * crack_scale, (crack_width + reached * spread_widening) * taper);
	float fine = crack_line(bent * crack_scale * 2.4 + 11.7, crack_width * 0.9 * taper) * reached;
	float top = step(0.5, local_normal.y);
	float crack = max(coarse, fine) * top;

	float grain = 0.88 + 0.12 * hash2(floor(q * 6.0)).x;
	ALBEDO = mix(stone_color.rgb * grain, crack_color.rgb, crack);
	ROUGHNESS = 0.95;
}
