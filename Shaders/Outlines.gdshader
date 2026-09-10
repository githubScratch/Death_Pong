shader_type canvas_item;

// Solid-color outline around this sprite's opaque pixels - built for the
// team-colored wizard outline (see Game_Settings.gd's team_color_for_seat()
// and wizard.gd's _apply_class()), but generic: any AnimatedSprite2D/
// Sprite2D can use it, just set outline_color per-instance.
//
// outline_width is in TEXTURE texel units, not screen pixels - the wizard
// sprite sheet is 192x192 per frame drawn at 0.333 scale (see wizard.tscn),
// so a couple of texels here is roughly a screen pixel once scaled down.
// Bump it up if the outline reads too thin at your sprite's scale.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 8.0, 0.1) = 3.0;

// This sprite's own AtlasTexture region within its sheet, in texel units
// (x, y, width, height) - see wizard.gd's _on_sprite_frame_changed(), which
// keeps this matched to whichever animation frame is currently showing.
//
// A canvas_item shader's UV spans the WHOLE atlas texture for an
// AtlasTexture-backed node, not just its cropped region - a documented,
// "not planned" Godot engine limitation (godotengine/godot#61563), not a
// bug here. Without this, a transparent pixel right at this frame's own
// edge would find its "nearest opaque neighbor" in a DIFFERENT frame
// packed right next to it in the same sheet and outline that instead -
// exactly the floating bar matching the frame-above's silhouette width
// that this uniform exists to prevent. Leave at the default (0,0,0,0) to
// disable region clamping for a sprite that isn't cut from a shared atlas.
uniform vec4 texture_region = vec4(0.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = tex;

	// Only bother looking for an edge on transparent (or near-transparent)
	// pixels - opaque interior pixels just draw normally above.
	if (tex.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		bool has_region = texture_region.z > 0.0 && texture_region.w > 0.0;
		vec2 region_min = texture_region.xy * TEXTURE_PIXEL_SIZE;
		vec2 region_max = region_min + texture_region.zw * TEXTURE_PIXEL_SIZE;

		float neighbor_alpha = 0.0;
		float sx;
		float sy;
		float inside;

		sx = UV.x + px.x; sy = UV.y;
		inside = has_region ? step(sx, region_max.x) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		sx = UV.x - px.x; sy = UV.y;
		inside = has_region ? step(region_min.x, sx) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		sx = UV.x; sy = UV.y + px.y;
		inside = has_region ? step(sy, region_max.y) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		sx = UV.x; sy = UV.y - px.y;
		inside = has_region ? step(region_min.y, sy) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		sx = UV.x + px.x; sy = UV.y + px.y;
		inside = has_region ? step(sx, region_max.x) * step(sy, region_max.y) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		sx = UV.x - px.x; sy = UV.y + px.y;
		inside = has_region ? step(region_min.x, sx) * step(sy, region_max.y) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		sx = UV.x + px.x; sy = UV.y - px.y;
		inside = has_region ? step(sx, region_max.x) * step(region_min.y, sy) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		sx = UV.x - px.x; sy = UV.y - px.y;
		inside = has_region ? step(region_min.x, sx) * step(region_min.y, sy) : 1.0;
		neighbor_alpha += texture(TEXTURE, vec2(sx, sy)).a * inside;

		neighbor_alpha = clamp(neighbor_alpha, 0.0, 1.0);
		COLOR = mix(tex, outline_color, neighbor_alpha);
	}
}
