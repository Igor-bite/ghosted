#include <metal_stdlib>
using namespace metal;

// Shared by the dissolve pass and the particle pass so particles leave exactly where pixels vanish.
struct DustParams {
    float progress;      // 0 = intact person, 1 = fully dissolved
    float life;          // fraction of the timeline a particle lives
    float2 size;         // output size, px
    float2 wind;         // drift direction (texture space, y down)
    float2 bboxX;        // person bbox min/max x in uv
    float2 bboxY;        // person bbox min/max y in uv (top→bottom)
    uint gridStep;       // particle spacing, px
    uint gridWidth;      // particles per row
    float pointSize;
    uint style;          // 0 dust, 1 glitch, 2 beam
};

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash12(i);
    float b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1));
    float d = hash12(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// When (in progress units) the pixel at uv turns to dust. Sweeps from the right edge of the person.
static float releaseAt(float2 uv, constant DustParams &P) {
    float span = max(P.bboxX.y - P.bboxX.x, 0.05);
    float sweep = clamp((P.bboxX.y - uv.x) / span, 0.0, 1.0);
    float n = valueNoise(uv * float2(14.0, 9.0)) * 0.7 + hash12(uv * P.size) * 0.3;
    float r = clamp(sweep * 0.6 + n * 0.4, 0.0, 1.0);
    return r * (1.0 - P.life);
}

// ---------- Pass 1: dissolve live person into the room ----------

struct FSOut { float4 position [[position]]; float2 uv; };

vertex FSOut fullscreenVertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    FSOut o;
    o.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(pos.x, 1.0 - pos.y);
    return o;
}

constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);

constant half3 kCyan = half3(0.13, 0.83, 0.93);
constant half3 kOrchid = half3(0.69, 0.42, 1.0);

/// Glitch: horizontal slices jump sideways, RGB splits, blocks of the person drop out in random order.
static half4 dissolveGlitch(float2 uv, texture2d<half> live, texture2d<half> room, texture2d<half> mask,
                            constant DustParams &P) {
    float p = clamp(P.progress, 0.0, 1.0);
    float intensity = sin(M_PI_F * p);                 // calm at both ends, wild in the middle
    float tick = floor(p * 28.0);                      // stutter: jitter changes in steps
    float rows = mix(16.0, 52.0, hash12(float2(tick, 3.1)));
    float band = floor(uv.y * rows);
    float jumps = step(0.55, hash12(float2(band + 7.0, tick)));
    float shift = (hash12(float2(band, tick)) - 0.5) * 0.14 * intensity * jumps;
    float2 suv = float2(uv.x + shift, uv.y);

    // Mask and colour come from the same shifted spot, so only the person ever moves.
    float m = float(mask.sample(linearClamp, suv).r);
    float2 cell = floor(suv * float2(40.0, 22.5));
    float release = 0.04 + hash12(cell + 0.37) * 0.9;
    float remaining = release - p;
    float visible = m * step(0.0, remaining);

    float split = 0.004 + 0.018 * intensity;
    half3 c = half3(live.sample(linearClamp, suv + float2(split, 0.0)).r,
                    live.sample(linearClamp, suv).g,
                    live.sample(linearClamp, suv - float2(split, 0.0)).b);
    c *= half(1.0 - 0.2 * intensity * step(0.5, fract(uv.y * P.size.y / 3.0)));
    // Blocks about to drop out flash in brand colours.
    float flash = step(0.0, remaining) * step(remaining, 0.045);
    c = mix(c, hash12(cell + tick) > 0.5 ? kCyan : kOrchid, half(flash * 0.75));

    half4 r = room.sample(linearClamp, uv);
    return mix(r, half4(c, 1.0h), half(visible));
}

/// Beam: a glowing scan line sweeps down the person; above it they linger briefly as hologram lines.
static half4 dissolveBeam(float2 uv, texture2d<half> live, texture2d<half> room, texture2d<half> mask,
                          constant DustParams &P) {
    float p = clamp(P.progress, 0.0, 1.0);
    float top = P.bboxY.x - 0.04;
    float bottom = P.bboxY.y + 0.04;
    float scan = mix(top, bottom, p);
    float d = uv.y - scan;                             // > 0: below the line, still solid

    half4 l = live.sample(linearClamp, uv);
    half4 r = room.sample(linearClamp, uv);
    float m = float(mask.sample(linearClamp, uv).r);
    half4 c = mix(r, l, half(m * step(0.0, d)));

    // Hologram trail right above the line.
    float trail = m * smoothstep(-0.18, 0.0, d) * (1.0 - step(0.0, d));
    float lines = step(0.45, fract(uv.y * P.size.y / 4.0 - p * 30.0));
    half3 holo = kCyan * 0.55h + l.rgb * 0.45h;
    c.rgb = mix(c.rgb, holo, half(trail * lines * 0.85));

    // The line glows across the silhouette at its row, with a soft halo.
    float onPerson = float(mask.sample(linearClamp, float2(uv.x, scan)).r);
    float ends = smoothstep(0.0, 0.06, p) * smoothstep(1.0, 0.94, p);
    float glow = (exp(-abs(d) * 260.0) + 0.35 * exp(-abs(d) * 40.0)) * onPerson * ends;
    c.rgb = min(c.rgb + half3(0.55, 0.88, 1.0) * half(glow), 1.0h);
    return c;
}

fragment half4 dissolveFragment(FSOut in [[stage_in]],
                                texture2d<half> live [[texture(0)]],
                                texture2d<half> room [[texture(1)]],
                                texture2d<half> mask [[texture(2)]],
                                constant DustParams &P [[buffer(0)]]) {
    if (P.style == 1) { return dissolveGlitch(in.uv, live, room, mask, P); }
    if (P.style == 2) { return dissolveBeam(in.uv, live, room, mask, P); }
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    half4 l = live.sample(s, in.uv);
    half4 r = room.sample(s, in.uv);
    float m = float(mask.sample(s, in.uv).r);
    float rel = releaseAt(in.uv, P);
    float remaining = rel - P.progress;             // >0: still intact
    float visible = m * step(0.0, remaining);
    // Darken a thin band right before the pixel crumbles: ash edge.
    float edge = m * smoothstep(0.035, 0.0, remaining) * step(0.0, remaining);
    half4 person = l * half(1.0 - 0.55 * edge);
    return mix(r, person, half(visible));
}

// ---------- Pass 2: particles ----------

struct ParticleOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    half4 color;
};

vertex ParticleOut particleVertex(uint vid [[vertex_id]],
                                  texture2d<half> snapshot [[texture(0)]],
                                  texture2d<half> snapshotMask [[texture(1)]],
                                  constant DustParams &P [[buffer(0)]]) {
    ParticleOut o;
    o.position = float4(2.0, 2.0, 0.0, 1.0); // culled by default
    o.pointSize = 0.0;
    o.color = half4(0);

    uint gx = vid % P.gridWidth;
    uint gy = vid / P.gridWidth;
    float2 origin = (float2(gx, gy) + 0.5) * float(P.gridStep);
    float2 uv = origin / P.size;
    if (uv.y >= 1.0) { return o; }

    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float m = float(snapshotMask.sample(s, uv).r);
    if (m < 0.5) { return o; }

    float rnd = hash12(origin);
    float rnd2 = hash12(origin.yx + 17.0);

    if (P.style == 2) {
        // Beam: sparse sparks lift off where the scan line passes.
        if (rnd > 0.12) { return o; }
        float top = P.bboxY.x - 0.04;
        float bottom = P.bboxY.y + 0.04;
        float relB = clamp((uv.y - top) / max(bottom - top, 0.05), 0.0, 1.0);
        float ageB = (P.progress - relB) / 0.22;
        if (ageB <= 0.0 || ageB >= 1.0) { return o; }
        float a = pow(ageB, 0.8);
        float2 q = uv * 9.0 + ageB * 2.3;
        float2 sway = float2(valueNoise(q) - 0.5, 0.0) * 60.0 * a;
        float2 pB = origin + sway + float2(0.0, -mix(60.0, 170.0, rnd2) * a);
        o.position = float4(pB.x / P.size.x * 2.0 - 1.0, 1.0 - pB.y / P.size.y * 2.0, 0.0, 1.0);
        o.pointSize = P.pointSize * mix(1.6, 0.6, ageB);
        half4 cB = snapshot.sample(s, uv);
        half3 tint = mix(cB.rgb, kCyan, 0.65h) + 0.25h;
        float alphaB = pow(1.0 - ageB, 1.2);
        o.color = half4(min(tint, 1.0h) * half(alphaB), half(alphaB));
        return o;
    }

    float rel = releaseAt(uv, P);
    float age = (P.progress - rel) / P.life;
    if (age <= 0.0 || age >= 1.0) { return o; }

    float speed = mix(0.6, 1.4, rnd);
    float a = pow(age, 1.5);
    float2 drift = normalize(P.wind) * a * 260.0 * speed;
    // Swirl: low-frequency noise field.
    float2 q = uv * 6.0 + age * 1.7;
    float2 swirl = float2(valueNoise(q) - 0.5, valueNoise(q + 31.7) - 0.5) * 120.0 * a;
    float2 lift = float2(0.0, -70.0 * a * rnd2);
    float2 p = origin + drift + swirl + lift;

    o.position = float4(p.x / P.size.x * 2.0 - 1.0, 1.0 - p.y / P.size.y * 2.0, 0.0, 1.0);
    o.pointSize = P.pointSize * mix(1.15, 0.45, age);
    half4 c = snapshot.sample(s, uv);
    float alpha = pow(1.0 - age, 1.3) * 0.95;
    o.color = half4(c.rgb * half(alpha), half(alpha));
    return o;
}

fragment half4 particleFragment(ParticleOut in [[stage_in]], float2 pc [[point_coord]]) {
    float d = length(pc - 0.5);
    if (d > 0.5) { discard_fragment(); }
    return in.color;
}
