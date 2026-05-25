// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA — Columns shader (v3 — actual column geometry)        ║
// ║  Fewer, BIGGER columns (3–5, 8–15% of canvas each), with     ║
// ║  entasis (slight bulge), capital + base bands, cylindrical   ║
// ║  lighting from a seeded sun position, visible fluting,       ║
// ║  textured sky and shadowed floor. No more barcode.           ║
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

    // ── Sky ─────────────────────────────────────────────────────
    // Seeded sun position. Two darker layers + a bright pool around the sun.
    float sunX = 0.20 + 0.60 * fract(u_seed * 0.41);
    float sunY = 0.12 + 0.18 * fract(u_seed * 0.17);
    float floorY = 0.78;

    vec3 sky = mix(bg2, mix(bg, sunCol * 0.5, 0.55), 1.0 - uv.y);
    float sunD = length((uv - vec2(sunX, sunY)) * vec2(1.0, 1.3));
    sky += sunCol * exp(-sunD * 2.5) * 1.0;
    sky += sunCol * 0.18 * smoothstep(0.45, 0.78, 1.0 - uv.y);   // horizon glow
    sky += vec3(noise(uv * 4.0)) * 0.03;                         // atmospheric noise

    // ── Floor ───────────────────────────────────────────────────
    vec3 ground = mix(bg2 * 0.4, floorCol * 0.22, smoothstep(floorY, 1.0, uv.y));
    // Subtle warm reflection of the sun on the floor.
    float refl = exp(-pow((uv.x - sunX) * 4.0, 2.0)) * smoothstep(floorY, 1.0, uv.y);
    ground += sunCol * refl * 0.20;

    // Start with sky/ground.
    vec3 col = uv.y > floorY ? ground : sky;

    // ── Columns ─────────────────────────────────────────────────
    float nCols   = floor(3.0 + hash1(0.0) * 3.0);   // 3–5 columns
    float topY    = 0.08;                            // columns start here
    float botY    = floorY + 0.005;

    bool inside = false;
    vec3 stoneCol = vec3(0.0);

    for (int i = 0; i < 6; i++) {
        if (float(i) >= nCols) break;

        float fi    = (float(i) + 0.5) / nCols;
        float cx    = fi + (hash1(float(i) + 1.0) - 0.5) * 0.025;
        // BIG columns: 7–13% of screen width each.
        float halfW = 0.035 + hash1(float(i) + 2.0) * 0.030;

        // Vertical normalised position along the column (0 top, 1 bottom).
        float vn = clamp((uv.y - topY) / (botY - topY), 0.0, 1.0);

        // Entasis: slight bulge in the middle. Plus wider capital + base bands.
        float entasis    = 1.0 + 0.04 * sin(vn * 3.14159);
        float capBulge   = 1.0 + 0.25 * smoothstep(0.10, 0.0, vn);
        float baseBulge  = 1.0 + 0.20 * smoothstep(0.92, 1.0, vn);
        float effHalfW   = halfW * entasis * capBulge * baseBulge;

        float d = abs(uv.x - cx) - effHalfW;

        if (d < 0.0 && uv.y >= topY && uv.y <= botY) {
            inside = true;

            // Cross-column position 0..1 (0 = left edge, 1 = right edge).
            float t = (uv.x - cx + effHalfW) / (2.0 * effHalfW);

            // Cylindrical lighting based on sun direction. The lit half
            // brightens toward stone+sun, the dark half collapses to deep shadow.
            float lightSign = sign(sunX - cx);
            float litness   = lightSign > 0.0 ? t : 1.0 - t;
            // Curve it so the centre of the lit side really blooms.
            litness = pow(litness, 1.4);

            vec3 lit  = mix(stone * 1.1, sunCol, 0.30);
            vec3 dark = bg2 * 0.55;
            stoneCol  = mix(dark, lit, litness);

            // Vertical fluting — visible grooves running top to bottom.
            float flutes = 6.0;
            float flute  = 0.5 + 0.5 * sin(t * flutes * 6.2832);
            stoneCol *= 0.85 + 0.15 * flute;

            // Capital + base look brighter (carved detail).
            float capBand  = smoothstep(0.08, 0.0,  vn);
            float baseBand = smoothstep(0.94, 1.0, vn);
            stoneCol = mix(stoneCol, stoneCol * 1.35, max(capBand, baseBand) * 0.7);
        }
    }

    if (inside) col = stoneCol;

    // Subtle ambient-occlusion shadow on the floor at the foot of each
    // column — darken just below each centre. Cheap approximation.
    if (uv.y > floorY && uv.y < floorY + 0.05) {
        float ao = 0.0;
        for (int j = 0; j < 6; j++) {
            if (float(j) >= nCols) break;
            float fj = (float(j) + 0.5) / nCols;
            float cx = fj + (hash1(float(j) + 1.0) - 0.5) * 0.025;
            ao += exp(-pow((uv.x - cx) * 25.0, 2.0));
        }
        col *= 1.0 - ao * 0.4 * smoothstep(floorY + 0.05, floorY, uv.y);
    }

    gl_FragColor = vec4(col, 1.0);
}
