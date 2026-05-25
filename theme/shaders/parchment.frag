// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Parchment shader (v3 — layered light pools)         ║
// ║  Drops the rigid "mode" system: every parchment is a warm    ║
// ║  sepia field with 3 seeded light pools, secondary fBm color  ║
// ║  drift, paper grain, and a directional ink-wash. Cranks the  ║
// ║  feature intensities so the wallpaper actually reads.        ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_seed;

const vec3 bg2        = vec3(0.102, 0.090, 0.078);
const vec3 bg         = vec3(0.129, 0.118, 0.098);
const vec3 bgLight    = vec3(0.176, 0.161, 0.129);
const vec3 bronze     = vec3(0.769, 0.604, 0.361);
const vec3 gold       = vec3(0.831, 0.659, 0.294);
const vec3 olive      = vec3(0.541, 0.604, 0.424);
const vec3 terracotta = vec3(0.702, 0.420, 0.353);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i),                  hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 6; i++) { s += a * noise(p); p *= 2.0; a *= 0.5; }
    return s;
}

vec3 paletteAt(int i) {
    if (i == 0) return bronze;
    if (i == 1) return gold;
    if (i == 2) return olive;
    return terracotta;
}

vec3 paletteAtFor(float key) {
    int i = int(mod(key, 4.0));
    return paletteAt(i);
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    // Warm sepia base — fBm-driven so it's never flat.
    vec2 p = uv * 2.2 + vec2(u_seed * 0.013, 0.0);
    float surface = fbm(p);
    vec3  warm = paletteAtFor(u_seed);
    vec3  base = mix(bg2 * 1.1, mix(bg, warm * 0.45, 0.55),
                     smoothstep(0.2, 0.9, surface));

    // Three light pools — different seeded positions, different accents.
    // Each pool is BIG and BRIGHT so it actually contributes to the image.
    vec3 col = base;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 pos = vec2(
            0.15 + 0.7 * fract(u_seed * (0.13 + fi * 0.27) + fi * 0.31),
            0.15 + 0.7 * fract(u_seed * (0.29 + fi * 0.17) + fi * 0.43)
        );
        float r = length((uv - pos) * vec2(1.0, 1.3));
        // Spread varies per pool — some are tight, some are diffuse.
        float spread = 1.4 + 2.5 * fract(u_seed * (0.41 + fi * 0.11));
        vec3 accent = paletteAtFor(u_seed * (0.7 + fi * 0.3) + fi);
        col += accent * exp(-r * spread) * 0.65;
    }

    // Secondary slow field shifts the overall hue across the canvas, so
    // even regions with no pool get a colour bias.
    float drift = smoothstep(0.25, 0.75, fbm(p * 0.5 + vec2(11.0, 3.7)));
    vec3 driftCol = mix(paletteAtFor(u_seed * 0.5),
                        paletteAtFor(u_seed * 0.5 + 2.0),
                        drift);
    col += driftCol * 0.10;

    // Paper grain — high-frequency noise centred on zero so it doesn't
    // brighten the average value.
    col += vec3(fbm(uv * 90.0) - 0.5) * 0.06;

    // Vignette.
    col *= 1.0 - 0.40 * length(uv - 0.5);

    gl_FragColor = vec4(col, 1.0);
}
