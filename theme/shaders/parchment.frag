// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Parchment shader                                    ║
// ║  Warm gradient + horizon glow + paper-grain noise.           ║
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
const vec3 terracotta = vec3(0.702, 0.420, 0.353);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i),                hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.0; a *= 0.5; }
    return s;
}

vec3 pickAccent(float s) {
    float k = mod(s, 3.0);
    if (k < 1.0) return bronze;
    if (k < 2.0) return gold;
    return terracotta;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    // Horizon position varies by seed in [0.35, 0.65].
    float horizonY = 0.5 + 0.15 * (fract(u_seed * 0.7) * 2.0 - 1.0);

    vec3 sky    = mix(bg2,           bg,           smoothstep(0.0, horizonY, uv.y));
    vec3 ground = mix(bg2 * 0.8,     bronze * 0.3, smoothstep(0.0, horizonY, horizonY - uv.y));
    vec3 col    = uv.y > horizonY ? sky : ground;

    // Horizon glow — a soft Gaussian band in the accent color.
    float dy   = (uv.y - horizonY) * 30.0;
    float glow = exp(-dy * dy);
    col += pickAccent(u_seed) * glow * 0.85;

    // Paper grain.
    col += vec3(fbm(uv * 8.0)) * 0.04;

    // Subtle warmer light pool drifting in by seed.
    vec2 pool = vec2(0.5 + 0.3 * cos(u_seed * 0.13),
                     horizonY + 0.1 * sin(u_seed * 0.11));
    float plr = length(uv - pool);
    col += bronze * 0.15 * exp(-plr * 4.0);

    gl_FragColor = vec4(col, 1.0);
}
