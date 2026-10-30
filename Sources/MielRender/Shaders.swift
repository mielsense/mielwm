// Metal source, compiled once per device at runtime (the Command Line Tools
// ship no `metal` compiler). Every position is in render-target pixels with a
// top-left origin, the same frame Core's geometry uses.

let shaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

struct Quad {
    float4 rect;   // target px: x, y, w, h
    float2 target; // render target size in px
    float2 pad;
};

// A 4-vertex triangle strip covering `rect`.
vertex VOut quad_vertex(uint vid [[vertex_id]], constant Quad& q [[buffer(0)]]) {
    float2 corner = float2(float(vid & 1u), float(vid >> 1u));
    float2 px = q.rect.xy + corner * q.rect.zw;
    VOut o;
    o.position = float4(px.x / q.target.x * 2.0 - 1.0, 1.0 - px.y / q.target.y * 2.0, 0.0, 1.0);
    o.uv = corner;
    return o;
}

float rounded_distance(float2 p, float4 rect, float radius) {
    float2 halfSize = rect.zw * 0.5;
    radius = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    float2 centered = p - (rect.xy + halfSize);
    float2 delta = abs(centered) - halfSize + float2(radius);
    return length(max(delta, float2(0.0))) + min(max(delta.x, delta.y), 0.0) - radius;
}

float rounded_mask(float2 p, float4 rect, float radius) {
    return 1.0 - smoothstep(-0.75, 0.75, rounded_distance(p, rect, radius));
}

float rounded_border_mask(float2 p, float4 rect, float radius, float thickness) {
    float outer = rounded_mask(p, rect, radius);
    float4 innerRect = float4(rect.xy + float2(thickness), max(rect.zw - float2(thickness * 2.0), float2(0.0)));
    float inner = rounded_mask(p, innerRect, max(radius - thickness, 0.0));
    return max(outer - inner, 0.0);
}

float4 blend_overlay(float4 base, float3 color, float alpha) {
    alpha = clamp(alpha, 0.0, 1.0);
    return float4(mix(base.rgb, color, alpha), base.a);
}

bool is_even(float n) {
    return fmod(abs(n), 2.0) < 0.5;
}

// ---- backdrop: wallpaper (parallax, mirrored tiles, cached blur), dim, grid

struct Backdrop {
    float4 tile;   // px origin and size of one wallpaper tile
    float4 solid;  // rgb used without a wallpaper
    float2 gridOrigin;
    float hasWallpaper;
    float blurAlpha;
    float dim;
    float gridOpacity;
    float gridCell;
    float gridFine;
    float gridMark;
    float gridDots;
    float pad0;
    float pad1;
};

fragment float4 backdrop_fragment(VOut in [[stage_in]], constant Backdrop& b [[buffer(0)]],
                                  texture2d<float> sharp [[texture(0)]], texture2d<float> blurred [[texture(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 p = in.position.xy;
    float3 color = b.solid.rgb;
    if (b.hasWallpaper > 0.5) {
        // Every other tile is mirrored, so the canvas pans forever without a seam.
        float2 local = (p - b.tile.xy) / b.tile.zw;
        float2 cell = floor(local);
        float2 f = local - cell;
        if (!is_even(cell.x)) f.x = 1.0 - f.x;
        if (!is_even(cell.y)) f.y = 1.0 - f.y;
        color = sharp.sample(s, f).rgb;
        if (b.blurAlpha > 0.001)
            color = mix(color, blurred.sample(s, f).rgb, b.blurAlpha);
    }
    color *= 1.0 - b.dim;

    if (b.gridOpacity > 0.001) {
        // Marks every cell from the world origin; odd marks carry the fading
        // finer level so zooming never makes them jump.
        float2 g = p - b.gridOrigin;
        float2 n = round(g / b.gridCell);
        float2 d = g - n * b.gridCell;
        float a;
        if (b.gridDots > 0.5) {
            float weight = is_even(n.x) && is_even(n.y) ? 1.0 : b.gridFine;
            a = saturate(b.gridMark * 0.5 - length(d) + 0.5) * weight;
        } else {
            float vx = saturate(b.gridMark * 0.5 - abs(d.x) + 0.5) * (is_even(n.x) ? 1.0 : b.gridFine);
            float vy = saturate(b.gridMark * 0.5 - abs(d.y) + 0.5) * (is_even(n.y) ? 1.0 : b.gridFine);
            a = max(vx, vy);
        }
        color = mix(color, float3(1.0), a * b.gridOpacity);
    }
    return float4(color, 1.0);
}

// ---- windows: rounded live image, soft shadow, dim, outlines, accent ring + glow

struct Window {
    float4 rect;        // content px
    float4 accent;      // rgb, ring alpha
    float4 dimColor;    // rgb, dim alpha
    float4 placeholder; // premultiplied color without an image
    float radius;
    float alpha;
    float shadow;
    float shadowSigma;
    float shadowDrop;
    float ringGap;
    float ringWidth;
    float glow;
    float glowRadius;
    float outline;
    float outlineWidth;
    float hasTexture;
};

// Window images are usually much larger than their quad when zoomed out.
// Average a small grid of bilinear taps across the pixel's footprint so text
// does not shimmer; at 1:1 this is a single exact tap.
float4 sample_window(texture2d<float> tex, float2 uv, float2 dx, float2 dy) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 size = float2(tex.get_width(), tex.get_height());
    float footprint = max(length(dx * size), length(dy * size));
    if (footprint <= 1.01)
        return tex.sample(s, uv);
    int n = int(clamp(ceil(footprint * 0.5), 2.0, 4.0));
    float4 sum = float4(0.0);
    for (int j = 0; j < n; ++j) {
        for (int i = 0; i < n; ++i) {
            float2 o = (float2(i, j) + 0.5) / float(n) - 0.5;
            sum += tex.sample(s, uv + dx * o.x + dy * o.y);
        }
    }
    return sum / float(n * n);
}

fragment float4 window_fragment(VOut in [[stage_in]], constant Window& w [[buffer(0)]],
                                texture2d<float> tex [[texture(0)]]) {
    float2 p = in.position.xy;
    float2 uv = (p - w.rect.xy) / w.rect.zw;
    float2 dx = dfdx(uv);
    float2 dy = dfdy(uv);
    float d = rounded_distance(p, w.rect, w.radius);
    float4 result = float4(0.0);

    if (w.shadow > 0.0) {
        float ds = rounded_distance(p - float2(0.0, w.shadowDrop), w.rect, w.radius);
        // Logistic stand-in for a Gaussian-blurred rounded box.
        float a = w.shadow / (1.0 + exp(1.702 * ds / max(w.shadowSigma, 0.5)));
        result = float4(0.0, 0.0, 0.0, a);
    }

    float ringRadius = w.radius + w.ringGap;
    float4 ringRect = float4(w.rect.xy - w.ringGap, w.rect.zw + 2.0 * w.ringGap);
    float dr = rounded_distance(p, ringRect, ringRadius);
    if (w.glow > 0.0) {
        float g = w.glow * exp(-max(dr, 0.0) / max(w.glowRadius, 0.5)) * smoothstep(-0.5, 0.5, d);
        result = float4(w.accent.rgb * g, g) + result * (1.0 - g);
    }

    float inside = 1.0 - smoothstep(-0.5, 0.5, d);
    if (inside > 0.0) {
        float4 c = w.hasTexture > 0.5 ? sample_window(tex, uv, dx, dy) : w.placeholder;
        c.rgb = mix(c.rgb, w.dimColor.rgb * c.a, w.dimColor.a);
        c *= inside;
        result = c + result * (1.0 - c.a);
    }

    if (w.outline > 0.0) {
        float band = smoothstep(-0.5, 0.5, d) * (1.0 - smoothstep(w.outlineWidth - 0.5, w.outlineWidth + 0.5, d));
        float a = w.outline * band;
        result = float4(float3(0.93) * a, a) + result * (1.0 - a);
    }

    if (w.accent.a > 0.0) {
        float band = smoothstep(-w.ringWidth - 0.5, -w.ringWidth + 0.5, dr) * (1.0 - smoothstep(-0.5, 0.5, dr));
        float a = w.accent.a * band;
        result = float4(w.accent.rgb * a, a) + result * (1.0 - a);
    }
    return result * w.alpha;
}

// ---- flat pieces: drop indicator, workspace frames

struct Solid {
    float4 rect;
    float4 fill;   // premultiplied
    float4 border; // premultiplied
    float radius;
    float borderWidth;
    float pad0;
    float pad1;
};

fragment float4 solid_fragment(VOut in [[stage_in]], constant Solid& s [[buffer(0)]]) {
    float2 p = in.position.xy;
    float4 c = s.fill * rounded_mask(p, s.rect, s.radius);
    if (s.borderWidth > 0.0) {
        float b = rounded_border_mask(p, s.rect, s.radius, s.borderWidth);
        c = s.border * b + c * (1.0 - s.border.a * b);
    }
    return c;
}

// ---- premultiplied textures: the tags

struct Textured {
    float alpha;
    float pad0;
    float pad1;
    float pad2;
};

fragment float4 texture_fragment(VOut in [[stage_in]], constant Textured& t [[buffer(0)]],
                                 texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return tex.sample(s, in.uv) * t.alpha;
}

// ---- lens: a port of shaders/barrel.frag, with the minimap composed after it

struct Lens {
    float4 panel;
    float4 button;
    float4 viewport;
    float4 active;
    float4 inactive;   // window markers: rgb, alpha
    float4 panelColor;
    float4 hairline;   // panel edge: rgb, alpha
    float4 line;       // viewport and glyph: rgb, alpha
    float4 map;        // screen uv to world uv (offset, scale): the world is drawn past the screen's edges
    float2 size;
    float distort;
    float contrast;    // edge overscan, 1 disables it
    float feather;
    float edgeBlur;
    float edgeBlurStart;
    float vignette;
    float chromatic;
    float minimapOpacity;
    float minimapTransition;
    float pixelScale;
    int count;
    int focused;
    float opacity;
    int workspaceCount; // outlines in `windows` after the window markers
    float liquid;       // 1: Liquid glass, 0: frosted
    float pad0;
    float pad1;
    float pad2;
};

constant float GOLDEN_ANGLE = 2.39996323;
constant int BLUR_TAPS = 24;
constant int MATERIAL_TAPS = 48;

// Screen uv (0...1 across the screen) to the overscanned world texture's uv.
float2 world_uv(float2 uv, float4 map) {
    return clamp(uv * map.zw + map.xy, 0.0, 1.0);
}

float3 lens_sample(texture2d<float> tex, float2 uv, float2 fringe, float4 map) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    if (fringe.x == 0.0 && fringe.y == 0.0)
        return tex.sample(s, world_uv(uv, map)).rgb;
    return float3(tex.sample(s, world_uv(uv + fringe, map)).r,
                  tex.sample(s, world_uv(uv, map)).g,
                  tex.sample(s, world_uv(uv - fringe, map)).b);
}

// Where the lens samples the world for a target pixel (see lens_fragment).
float2 lens_uv(float2 point, float2 size, float distort, float contrast) {
    float2 centered = point / size * 2.0 - 1.0;
    float radius2 = dot(centered, centered);
    return centered * (1.0 + distort * radius2) / max(contrast, 0.001) * 0.5 + 0.5;
}

// What is behind a panel, blurred: a golden-angle disc of taps through the lens.
float3 frosted(texture2d<float> tex, float2 point, float2 size, float distort, float contrast, float radius, float4 map) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 sum = float3(0.0);
    for (int i = 0; i < MATERIAL_TAPS; ++i) {
        float t = (float(i) + 0.5) / float(MATERIAL_TAPS);
        float angle = float(i) * GOLDEN_ANGLE;
        float2 p = point + float2(cos(angle), sin(angle)) * sqrt(t) * radius;
        sum += tex.sample(s, world_uv(lens_uv(p, size, distort, contrast), map)).rgb;
    }
    return sum / float(MATERIAL_TAPS);
}

// What is behind the minimap with Liquid glass (the overview's other panels are
// native glass): a light blur, bent inward near the rim as by the curved edge
// of a lens, and a little brighter there.
constant int LIQUID_TAPS = 16;

float3 liquid(texture2d<float> tex, float2 point, float4 rect, float radius, float2 size, float distort, float contrast,
              float blur, float scale, float4 map) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float d = rounded_distance(point, rect, radius);
    float2 e = float2(1.0, 0.0);
    float2 n = float2(rounded_distance(point + e.xy, rect, radius) - rounded_distance(point - e.xy, rect, radius),
                      rounded_distance(point + e.yx, rect, radius) - rounded_distance(point - e.yx, rect, radius));
    n = length(n) > 0.0001 ? normalize(n) : float2(0.0);
    float band = max(min(radius, 0.5 * min(rect.z, rect.w)), 10.0 * scale); // the bevel, as wide as the corner
    float rim = 1.0 - clamp(-d / band, 0.0, 1.0); // 1 at the edge, 0 in the flat middle
    float2 q = point - n * rim * rim * band * 0.6; // outward normal: sample further in
    float3 sum = float3(0.0);
    for (int i = 0; i < LIQUID_TAPS; ++i) {
        float t = (float(i) + 0.5) / float(LIQUID_TAPS);
        float angle = float(i) * GOLDEN_ANGLE;
        float2 p = q + float2(cos(angle), sin(angle)) * sqrt(t) * blur;
        sum += tex.sample(s, world_uv(lens_uv(p, size, distort, contrast), map)).rgb;
    }
    return mix(sum / float(LIQUID_TAPS), float3(1.0), 0.1 * rim * rim);
}

float4 compose_minimap(float4 base, float2 point, constant Lens& L, texture2d<float> tex,
                       constant float4* windows, constant float* dims) {
    if (((L.panel.z <= 0.0 || L.panel.w <= 0.0) && (L.button.z <= 0.0 || L.button.w <= 0.0)) || L.minimapTransition <= 0.001)
        return base;

    float ps = L.pixelScale;
    float t = L.minimapTransition;
    float4 color = base;
    float panelRadius = 12.0 * ps;
    float buttonRadius = 10.0 * ps;
    float panelMask = rounded_mask(point, L.panel, panelRadius);
    float buttonMask = rounded_mask(point, L.button, buttonRadius);
    float material = max(panelMask, buttonMask);
    if (material <= 0.0)
        return base;

    // Material: the canvas behind, blurred, under the panel tint.
    if (L.liquid > 0.5) {
        float4 r = panelMask >= buttonMask ? L.panel : L.button;
        float3 behind = liquid(tex, point, r, panelMask >= buttonMask ? panelRadius : buttonRadius, L.size, L.distort, L.contrast, 4.0 * ps, ps, L.map);
        color = blend_overlay(color, behind, t * material);
        color = blend_overlay(color, L.panelColor.rgb, L.minimapOpacity * 0.45 * t * material);
        // Light from above catches the top of the rim.
        float2 c = r.xy + r.zw * 0.5;
        float top = clamp((c.y - point.y) / (r.w * 0.5), 0.0, 1.0);
        float ring = rounded_border_mask(point, r, panelMask >= buttonMask ? panelRadius : buttonRadius, 1.0 * ps);
        color = blend_overlay(color, float3(1.0), (0.12 + 0.4 * top) * t * ring);
    } else {
        color = blend_overlay(color, frosted(tex, point, L.size, L.distort, L.contrast, 16.0 * ps, L.map), t * material);
        color = blend_overlay(color, L.panelColor.rgb, L.minimapOpacity * t * material);
    }

    if (panelMask > 0.0) {
        for (int i = L.count; i < L.count + L.workspaceCount; ++i) {
            color = blend_overlay(color, L.line.rgb, 0.05 * t * rounded_mask(point, windows[i], 3.0 * ps));
            color = blend_overlay(color, L.line.rgb, 0.3 * L.line.a * t * rounded_border_mask(point, windows[i], 3.0 * ps, 1.0));
        }
        for (int i = 0; i < L.count; ++i) {
            bool focused = i == L.focused;
            float marker = rounded_mask(point, windows[i], 2.0 * ps);
            color = blend_overlay(color, focused ? L.active.rgb : L.inactive.rgb,
                                  (focused ? 0.95 : L.inactive.a) * (1.0 - dims[i]) * t * marker);
        }
        float viewportRadius = 4.0 * ps;
        color = blend_overlay(color, L.line.rgb, 0.06 * t * rounded_mask(point, L.viewport, viewportRadius));
        color = blend_overlay(color, L.line.rgb, L.line.a * t * rounded_border_mask(point, L.viewport, viewportRadius, max(1.0, ps * 0.75)));
        color = blend_overlay(color, L.hairline.rgb, L.hairline.a * t * rounded_border_mask(point, L.panel, panelRadius, 1.0));
    }

    if (buttonMask > 0.0) {
        color = blend_overlay(color, L.hairline.rgb, L.hairline.a * t * rounded_border_mask(point, L.button, buttonRadius, 1.0));
        // A 2×2 grid glyph (SF's square.grid.2x2) says "arrange" without text.
        float glyph = min(L.button.z, L.button.w) * 0.44;
        float cell = glyph * 0.42;
        float2 origin = L.button.xy + (L.button.zw - glyph) * 0.5;
        for (int row = 0; row < 2; ++row) {
            for (int column = 0; column < 2; ++column) {
                float2 pos = origin + float2(float(column), float(row)) * (glyph - cell);
                float cellMask = rounded_border_mask(point, float4(pos, cell, cell), 2.0 * ps, max(1.0, 1.5 * ps));
                color = blend_overlay(color, L.line.rgb, L.line.a * t * cellMask);
            }
        }
    }
    return color;
}

fragment float4 lens_fragment(VOut in [[stage_in]], constant Lens& L [[buffer(0)]],
                              constant float4* windows [[buffer(1)]], constant float* dims [[buffer(2)]],
                              texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 point = in.position.xy;
    float2 texcoord = point / L.size;
    float4 color;

    bool lens = abs(L.distort) >= 0.000001 || abs(L.contrast - 1.0) >= 0.000001 || L.edgeBlur > 0.0001 || L.vignette > 0.0001 || L.chromatic > 0.0001;
    if (!lens) {
        color = tex.sample(s, world_uv(texcoord, L.map));
    } else {
        float2 centered = texcoord * 2.0 - 1.0;
        float radius2 = dot(centered, centered);

        // Radial lens mapping; signed strength moves between barrel and pincushion.
        float2 warped = centered * (1.0 + L.distort * radius2) / max(L.contrast, 0.001);
        float2 uv = warped * 0.5 + 0.5;

        float2 inWorld = uv * L.map.zw + L.map.xy; // only extreme settings read past the overscan; fade out there
        float2 edgeDistance = min(inWorld, 1.0 - inWorld);
        float edgeAlpha = L.feather <= 0.0 ? 1.0 : smoothstep(0.0, L.feather, min(edgeDistance.x, edgeDistance.y));

        // 0 at the center of the screen, 1 in its corners.
        float radius = sqrt(radius2) * 0.70710678;
        float ramp = smoothstep(min(L.edgeBlurStart, 0.99), 1.0, radius);
        float2 outward = radius > 0.0001 ? centered / sqrt(radius2) : float2(0.0);
        float fringeRamp = smoothstep(0.1, 1.0, radius);
        float2 fringe = outward * L.chromatic * fringeRamp * fringeRamp * 0.014;

        float3 rgb;
        float blur = L.edgeBlur * ramp;
        if (blur > 0.001) {
            // Golden-angle disc, denser toward its center, like lens bokeh.
            float radiusPx = blur * 0.02 * L.size.y;
            float2 texel = 1.0 / max(L.size, float2(1.0));
            float3 sum = float3(0.0);
            for (int i = 0; i < BLUR_TAPS; ++i) {
                float t = (float(i) + 0.5) / float(BLUR_TAPS);
                float angle = float(i) * GOLDEN_ANGLE;
                sum += lens_sample(tex, uv + float2(cos(angle), sin(angle)) * sqrt(t) * radiusPx * texel, fringe, L.map);
            }
            rgb = sum / float(BLUR_TAPS);
        } else {
            rgb = lens_sample(tex, uv, fringe, L.map);
        }

        float shade = 1.0 - L.vignette * smoothstep(0.2, 1.0, radius);
        color = float4(rgb * edgeAlpha * shade, tex.sample(s, world_uv(uv, L.map)).a);
    }

    return compose_minimap(color, point, L, tex, windows, dims) * L.opacity;
}
"""#
