#include <metal_stdlib>
using namespace metal;

// Shared by the dissolve pass and the particle pass so particles leave exactly where pixels vanish.
struct DustParams {
    float progress;      // 0 = intact person, 1 = fully dissolved
    float life;          // fraction of the timeline a particle lives
    float2 size;         // output size, px
    float2 wind;         // drift direction (texture space, y down)
    float2 bboxX;        // person bbox min/max x in uv
    uint gridStep;       // particle spacing, px
    uint gridWidth;      // particles per row
    float pointSize;
    float pad;
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

fragment half4 dissolveFragment(FSOut in [[stage_in]],
                                texture2d<half> live [[texture(0)]],
                                texture2d<half> room [[texture(1)]],
                                texture2d<half> mask [[texture(2)]],
                                constant DustParams &P [[buffer(0)]]) {
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

    float rel = releaseAt(uv, P);
    float age = (P.progress - rel) / P.life;
    if (age <= 0.0 || age >= 1.0) { return o; }

    float rnd = hash12(origin);
    float rnd2 = hash12(origin.yx + 17.0);
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
