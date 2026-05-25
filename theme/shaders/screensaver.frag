// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Screensaver shader                                  ║
// ║  Marble flow with continuous domain drift and slow palette  ║
// ║  cycling. Designed for indefinite playback — no loop point. ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_time;

const vec3 bg2        = vec3(0.102, 0.090, 0.078);
const vec3 bgLight    = vec3(0.176, 0.161, 0.129);
const vec3 bronze     = vec3(0.769, 0.604, 0.361);
const vec3 gold       = vec3(0.831, 0.659, 0.294);
const vec3 olive      = vec3(0.541, 0.604, 0.424);
const vec3 terracotta = vec3(0.702, 0.420, 0.353);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 p  = uv * 2.5;

    // Two slowly-drifting warps so the marble swirl is never the same twice.
    p += vec2(u_time * 0.03, u_time * 0.02);
    float w1 = fbm(p + vec2(u_time * 0.04, 0.0));
    float w2 = fbm(p + vec2(0.0,            u_time * 0.05));
    float m  = fbm(p + vec2(w1 * 3.0, w2 * 2.5));

    float vein = 1.0 - smoothstep(0.0, 0.04, abs(m - 0.5));
    vec3  col  = mix(bg2, bgLight, smoothstep(0.25, 0.75, m));

    // Cycle the accent through bronze → gold → olive → terracotta → …
    // Period ≈ 8 minutes at 4 colors × 2 minutes each.
    float t = u_time * 0.002;
    float k = mod(t, 4.0);
    vec3 a0 = bronze, a1 = gold;
    if (k < 1.0)      { a0 = bronze;     a1 = gold; }
    else if (k < 2.0) { a0 = gold;       a1 = olive; }
    else if (k < 3.0) { a0 = olive;      a1 = terracotta; }
    else              { a0 = terracotta; a1 = bronze; }
    vec3 accent = mix(a0, a1, fract(k));

    col += accent * vein * 0.55;

    // Vignette.
    col *= 1.0 - 0.4 * length(uv - 0.5);

    gl_FragColor = vec4(col, 1.0);
}
