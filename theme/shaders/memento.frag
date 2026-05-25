// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Memento shader                                      ║
// ║  Very soft textured background with a contained glow.        ║
// ║  The "MEMENTO MORI" + quote text is composited afterwards    ║
// ║  by stoa-walls.sh (text rendering belongs in IM, not GLSL).  ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_seed;

const vec3 bg2        = vec3(0.102, 0.090, 0.078);
const vec3 bgLight    = vec3(0.176, 0.161, 0.129);
const vec3 stone      = vec3(0.431, 0.416, 0.384);
const vec3 bronze     = vec3(0.769, 0.604, 0.361);
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

vec3 pickAccent(float s) {
    float k = mod(s, 3.0);
    if (k < 1.0) return stone;
    if (k < 2.0) return bronze;
    return terracotta;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    // Very low-contrast surface noise.
    float n = fbm(uv * 1.5);
    vec3 base = mix(bg2, bgLight, smoothstep(0.3, 0.7, n));

    // A single contained glow offset by seed — keeps the center clear
    // for the text overlay to land legibly.
    float angle = u_seed * 0.137;
    vec2 glowPos = vec2(0.15 + 0.7 * fract(u_seed * 0.31),
                        0.65 + 0.25 * sin(angle));
    float r = length(uv - glowPos);
    float glow = exp(-r * 5.5);
    vec3 col = base + pickAccent(u_seed) * glow * 0.18;

    // Soft vignette helps the text catch.
    float vig = 1.0 - 0.4 * length(uv - 0.5);
    col *= vig;

    gl_FragColor = vec4(col, 1.0);
}
