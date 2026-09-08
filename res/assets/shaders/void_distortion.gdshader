// =================================================================================================
// VOID DISTORTION - the visual for the Banshee's void tears.
//
// ORIGINAL AUTHOR: GavstarB.
//
// This shader is a near-verbatim copy of `chromatic_aberration.gdshader` from GavstarB's
// "HORUS Alts 1st Party" mod, where it draws the Calendula's Void Husks
// (mf_calendula/mt_sculptor_of_fate/deployable/). It is used here WITH PERMISSION and with thanks.
//
// The Banshee's tears and the Calendula's Void Husks are both holes in tangible space, and they are
// meant to read as the same phenomenon seen twice - so they deliberately share a visual language
// rather than each inventing one. The colour is the only thing that separates them: the Husks are
// violet (#2C1170), the tears are a colder indigo (#112C70).
//
// If permission is ever withdrawn, DELETE THIS FILE and replace it with an original distortion
// shader. Nothing else in the mod depends on its internals - `fxe_void_tear.tscn` is the only
// consumer, and it only sets uniforms.
//
// CHANGES FROM THE ORIGINAL, in full:
//
//   1. The rim tint in fragment() was a hardcoded `vec3(1.0, 0.0 + abs(COLOR.x), 0.0 + abs(COLOR.z))`,
//      which pins the red channel at full and makes every instance red-dominant regardless of
//      proximity_color. That is now the `edge_color` uniform, defaulting to vec3(1.0, 0.0, 0.0) so
//      the shader is pixel-identical to the original when the uniform is left alone. The tear scene
//      overrides it; a Husk-faithful copy would not.
//   2. Removed two functions that were dead in the original: `fresnel` (never called) and `randomf`
//      (called only from a commented-out block), along with that commented block itself.
//
// Nothing else was touched. The distortion, aberration and proximity-fade maths are his, verbatim.
// =================================================================================================

shader_type spatial;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture;
uniform float distortion_intensity : hint_range(0.0, 1.0) = 0.1;
uniform float noise_influence : hint_range(0.0, 1.0) = 1.0;
uniform float shake_color_rate : hint_range(0.0, 1.0) = 0.01;
uniform float strength : hint_range(0.0, 1.0) = 0.1;

uniform vec3 proximity_color : source_color = vec3(2.0, 2.0, 2.0);
uniform float proximity_distance = 0.05;
uniform float transparency = 1.0;

// See the header. Default reproduces the original's hardcoded rim exactly.
uniform vec3 edge_color : source_color = vec3(1.0, 0.0, 0.0);

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

float randomvec2(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void vertex() {
	COLOR.xyz = VERTEX;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center_uv = uv - vec2(0.5);

	float dist = length(center_uv);
	vec2 distortion_dir = normalize(center_uv);

	float noise = 1.0 + (randomvec2(uv + (TIME * 0.00001)) * 2.0 - 1.0) * noise_influence;

	// constant distortion based on distance from screen centre
	vec2 noise_offset = distortion_dir * distortion_intensity * dist * noise;

	vec4 distorted_color = texture(screen_texture, (uv + noise_offset));

	vec2 uv_offset = vec2(0.0, 0.0);
	// subtle sine wave drift for atmosphere
	uv_offset.x += sin(TIME * 2.0 + uv.y * 10.0) * 0.002;

	// chromatic aberration
	distorted_color.r = texture(screen_texture, uv + noise_offset + uv_offset + vec2(shake_color_rate, 0.0)).r;
	distorted_color.g = texture(screen_texture, uv + noise_offset + uv_offset).g;
	distorted_color.b = texture(screen_texture, uv + noise_offset + uv_offset + vec2(-shake_color_rate, 0.0)).b;

	vec4 normal_color = texture(screen_texture, uv);
	float scl = clamp(sqrt(COLOR.x * COLOR.x + COLOR.z * COLOR.z) * 2.0, 0.0, 1.0);
	scl = sqrt(sqrt(scl)) * 1.0 + 0.1;
	scl += sin(TIME * 2.0 + uv.x * 10.0) * 0.02;

	vec3 rim = vec3(edge_color.r, edge_color.g + abs(COLOR.x), edge_color.b + abs(COLOR.z));
	normal_color.rgb = mix(mix(rim, normal_color.rgb, strength), normal_color.rgb, scl);
	vec3 final_albedo = mix(distorted_color.rgb, normal_color.rgb, scl);

	// proximity fade
	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;

	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		float ndc_z = depth_raw * 2.0 - 1.0;
	#else
		float ndc_z = depth_raw;
	#endif

	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, ndc_z, 1.0);
	vec4 proximity_view_pos = INV_PROJECTION_MATRIX * ndc;
	proximity_view_pos.xyz /= proximity_view_pos.w;

	// both are negative view-space values; step returns 1 (normal) when the object is nearer the
	// camera than the scene surface behind it
	float proximity_mask = step(proximity_view_pos.z + proximity_distance, VERTEX.z);

	ALBEDO = mix(proximity_color, final_albedo, proximity_mask);
	ALPHA = mix(transparency, distorted_color.a, proximity_mask);
}
