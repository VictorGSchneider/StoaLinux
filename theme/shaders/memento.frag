// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Memento shader (v2)                                 ║
// ║  Aged sepia background with multiple soft light pools in     ║
// ║  varying accent colors. Text overlay (MEMENTO MORI + quote)  ║
// ║  is composited by stoa-walls.sh afterwards.                  ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_seed;

const vec3 bg2        = vec3(0.102, 0.090, 0.078);
const vec3 bg         = vec3(0.129, 0.118, 0.098);
const vec3 bgLight    = vec3(0.176, 0.161, 0.129);
const vec3 stone      = vec3(0.431, 0.416, 0.384);
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

// Cycle three accents from the palette per render so memento never
// feels mono-color.
void pickTriad(float s, out vec3 a, out vec3 b, out vec3 c) {
    vec3 pal[5];
    pal[0] = bronze; pal[1] = gold; pal[2] = olive; pal[3] = terracotta; pal[4] = stone;
    int i = int(mod(s,             5.0));
    int j = int(mod(s * 0.37 + 1.0, 5.0));
    int k = int(mod(s * 0.71 + 2.0, 5.0));
    if (j == i) j = (i + 1) % 5;
    if (k == i || k == j) k = (j + 1) % 5;
    a = pal[i]; b = pal[j]; c = pal[k];
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    vec3 a, b, c; pickTriad(u_seed, a, b, c);

    // Aged sepia base — warmer than pure dark, with surface variation.
    float field = fbm(uv * 1.8);
    float grain = fbm(uv * 50.0) * 0.05;
    vec3  base = mix(bg2, mix(bg, a * 0.28, 0.4), smoothstep(0.2, 0.85, field));
    base += vec3(grain);

    // Three soft glow pools in different accents.
    vec3 col = base;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 p = vec2(
            0.15 + 0.7 * fract(u_seed * (0.13 + fi * 0.21)),
            0.15 + 0.7 * fract(u_seed * (0.29 + fi * 0.17))
        );
        // Avoid the dead-center band where text lands.
        if (abs(p.y - 0.5) < 0.18 && abs(p.x - 0.5) < 0.35) {
            p.y += sign(p.y - 0.5) * 0.25;
        }
        float r = length(uv - p);
        vec3 cc = (i == 0) ? a : (i == 1 ? b : c);
        col += cc * exp(-r * 4.0) * 0.18;
    }

    // Subtle ink-wash sweep across the canvas.
    float ang = u_seed * 0.11;
    vec2  dir = vec2(cos(ang), sin(ang));
    float t   = dot(uv - 0.5, dir);
    col += b * 0.05 * smoothstep(-0.2, 0.2, t) * smoothstep(0.4, 0.0, t);

    // Vignette that protects the text region in the middle.
    col *= 1.0 - 0.45 * length(uv - 0.5);

    gl_FragColor = vec4(col, 1.0);
}
