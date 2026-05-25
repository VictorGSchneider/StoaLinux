// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Parchment shader (v2)                               ║
// ║  Aged paper with warm tones, stains, and atmospheric light.  ║
// ║  Four composition modes picked by seed → no two wallpapers   ║
// ║  read the same.                                              ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_seed;

const vec3 bg2        = vec3(0.102, 0.090, 0.078);
const vec3 bg         = vec3(0.129, 0.118, 0.098);
const vec3 bgLight    = vec3(0.176, 0.161, 0.129);
const vec3 fgDim      = vec3(0.659, 0.624, 0.569);
const vec3 bronze     = vec3(0.769, 0.604, 0.361);
const vec3 gold       = vec3(0.831, 0.659, 0.294);
const vec3 olive      = vec3(0.541, 0.604, 0.424);
const vec3 terracotta = vec3(0.702, 0.420, 0.353);
const vec3 stone      = vec3(0.431, 0.416, 0.384);

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

// GLSL ES 2.0 (the glslViewer target) forbids dynamic indexing into
// local arrays and the integer % operator, so the "palette" is a
// helper that branches on the index instead.
vec3 paletteAt(int i) {
    if (i == 0) return bronze;
    if (i == 1) return gold;
    if (i == 2) return olive;
    return terracotta;
}

void pickAccents(float s, out vec3 a, out vec3 b) {
    int i = int(mod(s,             4.0));
    int j = int(mod(s * 0.31 + 1.0, 4.0));
    if (j == i) j = int(mod(float(i) + 1.0, 4.0));
    a = paletteAt(i);
    b = paletteAt(j);
}

// Warm parchment base: not pure dark — slightly biased toward bronze
// shadow, with high-freq paper grain.
vec3 paperBase(vec2 uv, vec3 warm) {
    float grain = fbm(uv * 60.0) * 0.04;          // fine paper fibres
    float field = fbm(uv * 2.5);                  // large soft variation
    vec3 base = mix(bg2, mix(bg, warm * 0.35, 0.5),
                    smoothstep(0.25, 0.85, field));
    return base + vec3(grain);
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec3 a, b; pickAccents(u_seed, a, b);

    vec3 col = paperBase(uv, a);
    float mode = mod(u_seed, 4.0);

    if (mode < 1.0) {
        // Horizon-glow mode — soft warm band, position varies.
        float hY  = 0.4 + 0.25 * fract(u_seed * 0.71);
        float dy  = (uv.y - hY) * 18.0;
        float glow = exp(-dy * dy);
        col += a * glow * 0.9 + b * glow * 0.2;
    } else if (mode < 2.0) {
        // Corner-light mode — one quadrant lit by a soft pool.
        int idx = int(mod(u_seed * 0.13, 4.0));
        vec2 c;
        if      (idx == 0) c = vec2(0.15, 0.15);
        else if (idx == 1) c = vec2(0.85, 0.15);
        else if (idx == 2) c = vec2(0.15, 0.85);
        else               c = vec2(0.85, 0.85);
        float d = length(uv - c);
        col += a * exp(-d * 2.5) * 0.7;
        col += b * exp(-d * 1.2) * 0.15;
    } else if (mode < 3.0) {
        // Stain mode — three soft ink/aged-paper marks of varying color.
        for (int k = 0; k < 3; k++) {
            float fk = float(k);
            vec2 p = vec2(fract(u_seed * (0.17 + fk * 0.11)),
                          fract(u_seed * (0.29 + fk * 0.13)));
            float r = length(uv - p);
            vec3 cc = (k == 0) ? a : (k == 1 ? b : mix(a, b, 0.5));
            col += cc * exp(-r * 3.5) * (0.35 - 0.08 * fk);
        }
    } else {
        // Gradient-sweep mode — directional warm wash across the canvas.
        float ang = u_seed * 0.137;
        vec2  dir = vec2(cos(ang), sin(ang));
        float t   = dot(uv - 0.5, dir) + 0.5;
        float wave = smoothstep(0.0, 1.0, t)
                   - smoothstep(0.4, 1.4, t);
        col += a * wave * 0.55 + b * wave * 0.2;
    }

    // Subtle atmospheric vignette — always present, draws the eye in.
    col *= 1.0 - 0.35 * length(uv - 0.5);

    gl_FragColor = vec4(col, 1.0);
}
