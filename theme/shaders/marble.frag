// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Marble shader                                       ║
// ║  Fractal Brownian motion with domain warping → marble       ║
// ║  texture, accent color veining.                              ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_time;
uniform float u_seed;

const vec3 bg2     = vec3(0.102, 0.090, 0.078);
const vec3 bgLight = vec3(0.176, 0.161, 0.129);
const vec3 bronze  = vec3(0.769, 0.604, 0.361);
const vec3 gold    = vec3(0.831, 0.659, 0.294);
const vec3 olive   = vec3(0.541, 0.604, 0.424);
const vec3 stone   = vec3(0.431, 0.416, 0.384);

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

vec3 pickAccent(float s) {
    float k = mod(s, 4.0);
    if (k < 1.0) return bronze;
    if (k < 2.0) return gold;
    if (k < 3.0) return olive;
    return stone;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 p  = uv * 3.0;

    // Domain-warped fBm = swirly marble pattern.
    float w1 = fbm(p);
    float w2 = fbm(p + vec2(5.2, 1.3));
    float m  = fbm(p + 3.0 * vec2(w1, w2));

    // Sharp veining where the warped field crosses 0.5.
    float vein = 1.0 - smoothstep(0.0, 0.05, abs(m - 0.5));

    vec3 col    = mix(bg2, bgLight, smoothstep(0.3, 0.8, m));
    vec3 accent = pickAccent(u_seed);
    col += accent * vein * 0.45;

    // Soft vignette pulls focus toward the center.
    float vig = 1.0 - 0.5 * length(uv - 0.5);
    col *= vig;

    gl_FragColor = vec4(col, 1.0);
}
