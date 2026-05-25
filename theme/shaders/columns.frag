// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Columns shader                                      ║
// ║  Vertical column silhouettes against a gradient sky.        ║
// ╚══════════════════════════════════════════════════════════════╝

#ifdef GL_ES
precision highp float;
#endif

uniform vec2  u_resolution;
uniform float u_seed;

const vec3 bg2     = vec3(0.102, 0.090, 0.078);
const vec3 bg      = vec3(0.129, 0.118, 0.098);
const vec3 bgLight = vec3(0.176, 0.161, 0.129);
const vec3 bronze  = vec3(0.769, 0.604, 0.361);
const vec3 gold    = vec3(0.831, 0.659, 0.294);
const vec3 olive   = vec3(0.541, 0.604, 0.424);

float hash1(float x) { return fract(sin(x * 12.9898 + u_seed) * 43758.5453); }
float hash2(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i),                  hash2(i + vec2(1.0, 0.0)), f.x),
               mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    // Sky gradient — slightly lighter at the top, deeper at the bottom.
    vec3 sky = mix(bg2, bgLight, 1.0 - uv.y);
    // Subtle atmospheric noise.
    sky += vec3(noise(uv * 3.0)) * 0.03;

    // Pick column count + accent based on seed.
    float nCols = floor(4.0 + hash1(0.0) * 4.0);
    vec3 accent = (mod(u_seed, 3.0) < 1.0) ? bronze
                 : (mod(u_seed, 3.0) < 2.0) ? gold
                                            : olive;

    // Compute distance from current pixel to the nearest column edge.
    // Unrolled loop with a safe upper bound so GLSL can compile.
    float minD = 1.0;
    for (int i = 0; i < 10; i++) {
        if (float(i) >= nCols) break;
        float fi = (float(i) + 0.5) / nCols;
        float cx = fi + (hash1(float(i) + 1.0) - 0.5) * 0.04;
        float halfW = 0.018 + hash1(float(i) + 2.0) * 0.022;
        float d = abs(uv.x - cx) - halfW;
        if (d < minD) minD = d;
    }

    // Inside a column → solid deep dark, edge → thin accent stroke.
    float inside = smoothstep(0.002, -0.001, minD);
    float edge   = exp(-pow(minD * 700.0, 2.0)) * 0.6;

    vec3 col = mix(sky, bg2 * 0.45, inside);
    col += accent * edge;

    // Slight floor shadow.
    col *= 1.0 - 0.25 * smoothstep(0.7, 1.0, uv.y);

    gl_FragColor = vec4(col, 1.0);
}
