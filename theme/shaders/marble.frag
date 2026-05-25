// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Marble shader (v3 — softer veining)                 ║
// ║  Domain-warped fBm with diffuse two-color veining.           ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_time;
uniform float u_seed;

const vec3 bg2        = vec3(0.102, 0.090, 0.078);
const vec3 bgLight    = vec3(0.176, 0.161, 0.129);
const vec3 bronze     = vec3(0.769, 0.604, 0.361);
const vec3 gold       = vec3(0.831, 0.659, 0.294);
const vec3 olive      = vec3(0.541, 0.604, 0.424);
const vec3 terracotta = vec3(0.702, 0.420, 0.353);
const vec3 stone      = vec3(0.431, 0.416, 0.384);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 6; i++) {
        sum += amp * noise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

vec3 paletteAt(int i) {
    if (i == 0) return bronze;
    if (i == 1) return gold;
    if (i == 2) return olive;
    if (i == 3) return terracotta;
    return stone;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 p  = uv * 3.0;

    // Domain-warped fBm = swirly marble pattern.
    float w1 = fbm(p);
    float w2 = fbm(p + vec2(5.2, 1.3));
    float m  = fbm(p + 3.0 * vec2(w1, w2));

    // A second slow field selects WHICH accent each vein takes — so a
    // single wallpaper carries two intertwined accent colors.
    float blend = smoothstep(0.3, 0.7, fbm(p * 0.6 + vec2(7.3, 2.1)));
    int   iA = int(mod(u_seed,             5.0));
    int   iB = int(mod(u_seed * 0.31 + 1.0, 5.0));
    if (iB == iA) iB = int(mod(float(iA) + 1.0, 5.0));
    vec3 accent = mix(paletteAt(iA), paletteAt(iB), blend);

    // SOFTER veining: wider smoothstep so the vein has a diffuse
    // halo around the threshold instead of a hard 1-pixel edge. This
    // reads as polished stone, not oil slick.
    float veinNarrow = 1.0 - smoothstep(0.0, 0.10, abs(m - 0.5));
    float veinHalo   = 1.0 - smoothstep(0.0, 0.25, abs(m - 0.5));

    vec3 col = mix(bg2, bgLight, smoothstep(0.25, 0.85, m));
    col += accent * veinHalo * 0.30;      // diffuse coloured wash
    col += accent * veinNarrow * 0.55;    // brighter core of the vein

    // A few brighter "specular" highlights where two warp fields align.
    float spec = smoothstep(0.85, 1.0, w1) * smoothstep(0.85, 1.0, w2);
    col += accent * spec * 0.35;

    // Soft vignette pulls focus toward the center.
    col *= 1.0 - 0.45 * length(uv - 0.5);

    gl_FragColor = vec4(col, 1.0);
}
