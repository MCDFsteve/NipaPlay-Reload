#version 330
//!DESC Danmaku Overlay (GLSL)
//!HOOK OUTPUT
//!BIND HOOKED
//!TEXTURE danmaku_tex
//!PARAM danmaku_w
//!PARAM danmaku_w=0.0
//!PARAM danmaku_h
//!PARAM danmaku_h=0.0
//!PARAM danmaku_opacity
//!PARAM danmaku_opacity=1.0

vec4 hook() {
    vec4 base = HOOKED_tex(HOOKED_pos);
    if (danmaku_w <= 0.0 || danmaku_h <= 0.0) {
        return base;
    }

    vec2 output_size = HOOKED_size;
    vec2 overlay_size = vec2(danmaku_w, danmaku_h);
    vec2 scale = output_size / overlay_size;

    vec2 dm_uv = HOOKED_pos * scale;
    if (dm_uv.x < 0.0 || dm_uv.y < 0.0 || dm_uv.x > 1.0 || dm_uv.y > 1.0) {
        return base;
    }

    vec4 dm = texture(danmaku_tex, dm_uv);
    float alpha = dm.a * danmaku_opacity;
    return mix(base, vec4(dm.rgb, 1.0), alpha);
}
