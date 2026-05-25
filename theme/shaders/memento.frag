// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Memento shader (v3 — dramatic duotone)              ║
// ║  One strong light source from a seeded position, deep shadow ║
// ║  on the opposite side, warm fBm sepia base, scattered dust   ║
// ║  particles. Reads "vanitas oil-painting" instead of "flat    ║
// ║  brown square". Text overlay still composited afterwards.    ║
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

vec3 paletteAt(int i) {
    if (i == 0) return bronze;
    if (i == 1) return gold;
    if (i == 2) return olive;
    if (i == 3) return terracotta;
    return stone;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    // Two accents (warm + cool) for the duotone.
    int iA = int(mod(u_seed,             5.0));
    int iB = int(mod(u_seed * 0.37 + 1.0, 5.0));
    if (iB == iA) iB = int(mod(float(iA) + 1.0, 5.0));
    vec3 warmA = paletteAt(iA);
    vec3 coolB = paletteAt(iB);

    // Aged sepia base with real fBm texture (no flat color).
    float field = fbm(uv * 1.8);
    vec3 base = mix(bg2, mix(bg, warmA * 0.30, 0.5), smoothstep(0.2, 0.85, field));

    // SINGLE strong light source from a seeded edge position. Pushed off
    // to a side or corner so the canvas reads "chiaroscuro candle" not
    // "blob in the middle".
    float lightAng = u_seed * 0.137;
    vec2  lightPos = vec2(0.5 + 0.45 * cos(lightAng),
                          0.5 + 0.45 * sin(lightAng * 1.3));
    float lightD = length((uv - lightPos) * vec2(1.0, 1.1));
    float litness = exp(-lightD * 1.6);

    // Compose: deep shadow tint on the far side, strong warm tint near the light.
    vec3 col = mix(base * 0.55, base + warmA * 0.55, litness);

    // A second softer light pool in the cool accent so the canvas isn't monochromatic.
    vec2 light2 = vec2(0.5 - 0.40 * cos(lightAng),
                       0.5 - 0.30 * sin(lightAng * 1.3));
    float light2D = length(uv - light2);
    col += coolB * exp(-light2D * 2.5) * 0.25;

    // Scattered dust particles — high-freq noise thresholded so only the
    // peaks become specks.
    float dustField = fbm(uv * 28.0);
    float dust = smoothstep(0.62, 0.78, dustField);
    col += warmA * dust * 0.20;

    // Subtle fold/wrinkle texture: low-freq noise riding the surface.
    col += vec3(fbm(uv * 4.0) - 0.5) * 0.06;

    // Vignette — but lighter on the side where the light source is, so
    // it doesn't fight the duotone.
    float vig = 1.0 - 0.35 * length(uv - 0.5);
    col *= vig;

    gl_FragColor = vec4(col, 1.0);
}
