// =================================================================================================
// VOID DISTORTION - the visual for the Banshee's void tears.
//
// ORIGINAL AUTHOR: GavstarB. Used WITH PERMISSION and with thanks.
//
// Derived from `chromatic_aberration.gdshader` in GavstarB's "HORUS Alts 1st Party" mod, where it
// draws the Calendula's Void Husks (mf_calendula/mt_sculptor_of_fate/deployable/).
//
// The Banshee's tears and the Calendula's Void Husks are both holes in tangible space and are meant
// to read as the same phenomenon seen twice, so they share a visual language rather than each
// inventing one.
//
// WHAT IS HIS, and the reason to keep this file rather than start over: the screen-space
// distortion, the chromatic aberration, and the depth-buffer proximity fade in fragment() are his
// work, essentially unchanged. That is the part that makes a hole in reality look like one.
//
// WHAT IS OURS: the colour treatment. The original decided the body colour through a chain of
// mixes driven by `strength` and a radial term computed from vertex position, with the rim hue
// hardcoded to full red. In practice that made the dome's centre show ~81% of that hardcoded rim
// colour, so the exposed `proximity_color` only ever tinted the contact edge and the body came out
// warm regardless of what it was set to. The Husks want that; a tear does not. So the mixing chain
// is replaced below with three explicit controls - `tint`, `see_through`, and a real Fresnel rim -
// and the radial term is gone.
//
// The Fresnel helper is his: it was declared in the original and never called. It is called now.
//
// If permission is ever withdrawn, DELETE THIS FILE and write an original distortion shader.
// `fxe_void_tear.tscn` is its only consumer and only sets uniforms, so nothing else changes.
// =================================================================================================

shader_type spatial;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// --- his distortion controls, unchanged ---
uniform float distortion_intensity : hint_range(0.0, 1.0) = 0.1;
uniform float noise_influence : hint_range(0.0, 1.0) = 1.0;
uniform float shake_color_rate : hint_range(0.0, 1.0) = 0.01;

// --- the body ---
/// The void itself. Multiplied into whatever is seen through the tear, so a dark value reads as a
/// hole rather than a pane of coloured glass.
uniform vec3 tint : source_color = vec3(0.09, 0.10, 0.24);
/// How much of the distorted scene behind survives. 0 = an opaque void, 1 = clear warped glass.
uniform float see_through : hint_range(0.0, 1.0) = 0.35;

// --- the rim ---
/// Fresnel: bright where the surface turns away from the camera, which outlines the dome's edge and
/// is what makes it legible against busy ground.
uniform vec3 fresnel_color : source_color = vec3(0.45, 0.55, 1.0);
uniform float fresnel_power : hint_range(0.1, 8.0) = 3.0;
uniform float fresnel_strength : hint_range(0.0, 4.0) = 1.4;

// --- his proximity fade, unchanged ---
/// Flat colour where the dome meets the scene surface behind it.
uniform vec3 proximity_color : source_color = vec3(0.17, 0.07, 0.44);
uniform float proximity_distance = 0.05;
uniform float transparency = 1.0;

float randomvec2(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

// GavstarB's, from the original. Declared there but never called.
float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
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

	// subtle sine wave drift for atmosphere
	vec2 uv_offset = vec2(sin(TIME * 2.0 + uv.y * 10.0) * 0.002, 0.0);

	// chromatic aberration
	distorted_color.r = texture(screen_texture, uv + noise_offset + uv_offset + vec2(shake_color_rate, 0.0)).r;
	distorted_color.g = texture(screen_texture, uv + noise_offset + uv_offset).g;
	distorted_color.b = texture(screen_texture, uv + noise_offset + uv_offset + vec2(-shake_color_rate, 0.0)).b;

	// THE BODY. Darken the warped scene towards `tint` rather than mixing a hue over it, so the
	// tear swallows light instead of colouring it.
	vec3 body = tint * mix(vec3(1.0), distorted_color.rgb, see_through);

	// THE RIM.
	float fres = fresnel(fresnel_power, NORMAL, VIEW);
	vec3 final_albedo = body + fresnel_color * fres * fresnel_strength;

	// proximity fade (his)
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
