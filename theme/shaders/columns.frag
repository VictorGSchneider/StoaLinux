// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Columns shader (v2)                                 ║
// ║  Greek-temple columns with capital, base, light side, and    ║
// ║  shadow side. Atmospheric sky behind, dark floor below.      ║
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

float hash1(float x) { return fract(sin(x * 12.9898 + u_seed) * 43758.5453); }
float hash2(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i),                  hash2(i + vec2(1.0, 0.0)), f.x),
               mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.0; a *= 0.5; }
    return s;
}

// GLSL ES 2.0 disallows dynamic indexing into local arrays and integer
// % — branch instead.
vec3 paletteAt(int i) {
    if (i == 0) return bronze;
    if (i == 1) return gold;
    if (i == 2) return olive;
    return terracotta;
}

void pickAccents(float s, out vec3 sun, out vec3 floorAccent) {
    int i = int(mod(s,             4.0));
    int j = int(mod(s * 0.31 + 1.0, 4.0));
    if (j == i) j = int(mod(float(i) + 1.0, 4.0));
    sun         = paletteAt(i);
    floorAccent = paletteAt(j);
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec3 sunCol, floorCol;
    pickAccents(u_seed, sunCol, floorCol);

    // Sky: gradient from light-warm at horizon to dark up top, plus
    // a soft sun pool whose x-position is seeded.
    float sunX = 0.2 + 0.6 * fract(u_seed * 0.41);
    float sunY = 0.25 + 0.2 * fract(u_seed * 0.17);
    vec3 sky = mix(bg2, bgLight, 1.0 - uv.y);
    sky = mix(sky, mix(sky, sunCol, 0.6),
              exp(-length((uv - vec2(sunX, sunY)) * vec2(1.0, 0.7)) * 2.5) * 0.8);
    // Atmospheric haze near horizon.
    sky += sunCol * 0.12 * smoothstep(0.4, 0.65, 1.0 - uv.y);

    // Floor: dark, with subtle warm tint coming from the accent.
    float floorY = 0.78 + 0.05 * fract(u_seed * 0.61);
    vec3  ground = mix(bg2 * 0.4, floorCol * 0.18, smoothstep(floorY, 1.0, uv.y));

    // Pick base layer.
    vec3 col = uv.y > floorY ? sky : ground;

    // ── Columns ─────────────────────────────────────────────────
    float nCols   = floor(5.0 + hash1(0.0) * 5.0);   // 5–9 columns
    float minD    = 1.0;
    float colShade = 0.0;     // 0 inside lit half, 1 inside shadow half
    float capRel  = 0.0;      // 1 if in capital / base band of nearest column
    bool  insideCol = false;

    for (int i = 0; i < 12; i++) {
        if (float(i) >= nCols) break;
        float fi    = (float(i) + 0.5) / nCols;
        float cx    = fi + (hash1(float(i) + 1.0) - 0.5) * 0.03;
        float halfW = 0.020 + hash1(float(i) + 2.0) * 0.020;
        float d     = abs(uv.x - cx) - halfW;
        if (d < minD) {
            minD = d;
            // Lighting: dot(column_normal, light_dir). Light from sun pos.
            float sideOffset = (uv.x - cx) / halfW;     // -1..1
            float lightDirX  = sunX - cx;                // sign tells which side
            colShade = clamp(0.5 - 0.5 * sideOffset * sign(lightDirX), 0.0, 1.0);
            // Capital + base bands.
            float capBand  = smoothstep(0.92, 0.95, uv.y) - smoothstep(0.96, 1.00, uv.y);
            float baseBand = smoothstep(floorY - 0.04, floorY - 0.01, uv.y)
                           - smoothstep(floorY, floorY + 0.01, uv.y);
            float topBand  = smoothstep(0.05, 0.08, 1.0 - uv.y) - smoothstep(0.10, 0.13, 1.0 - uv.y);
            capRel = max(capBand, max(baseBand, topBand));
            insideCol = (d < 0.0);
        }
    }

    if (insideCol) {
        // Stone column gradient — light side warmer, shadow side cool & dark.
        vec3 lightCol = mix(stone * 1.1, sunCol * 0.6, 0.35);
        vec3 darkCol  = bg2 * 0.55;
        col = mix(lightCol, darkCol, colShade);
        // Capital / base bulge in lighter stone.
        col = mix(col, stone * 1.25, capRel * 0.6);
        // Subtle vertical fluting — sinusoidal banding within the column.
        col *= 1.0 - 0.10 * abs(sin((uv.x * 60.0)));
    }

    // Thin accent edge on the lit side of each column rim.
    float rim = exp(-pow(minD * 900.0, 2.0));
    col += sunCol * rim * 0.35;

    // Sky atmospheric noise so it never looks like a flat gradient.
    if (!insideCol && uv.y < floorY) {
        col += vec3(noise(uv * 4.0)) * 0.025;
    }

    gl_FragColor = vec4(col, 1.0);
}
