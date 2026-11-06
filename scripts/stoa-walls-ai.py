#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — AI wallpaper renderer                          ║
# ║                                                              ║
# ║  Backend for `stoa-walls` (STOA_WALLS_BACKEND=ai). One call  ║
# ║  renders ONE wallpaper:                                      ║
# ║    1. builds an abstract prompt from (theme, seed) — the     ║
# ║       seed picks subject / palette / light, so every image   ║
# ║       differs, but the same seed always gives the same one   ║
# ║    2. runs stable-diffusion.cpp (sd-cli, Vulkan) locally     ║
# ║    3. upscales to 1920x1080, tames saturation                ║
# ║    4. places the quote where the image is calmest, picking   ║
# ║       light/dark text by local luminance and adding a soft   ║
# ║       scrim only when contrast would drop under 4.5:1        ║
# ║                                                              ║
# ║  Needs: sd-cli (yay -S stable-diffusion.cpp-vulkan-bin),     ║
# ║  numpy + Pillow (venv made by `stoa-walls setup-ai`).        ║
# ╚══════════════════════════════════════════════════════════════╝
"""Usage: stoa-walls-ai.py --theme T --seed N --out FILE [--quote Q]

Environment:
  STOA_WALLS_AI_MODEL   checkpoint (.safetensors)  [turbo, ~/.local/share/stoa/models]
  STOA_WALLS_AI_STEPS   sampling steps             [4]
  STOA_WALLS_AI_TYPE    sd-cli weight type         [q8_0]  (fp16 can OOM on 14 GB RAM)
  STOA_WALLS_AI_DEVICE  sd-cli backend device      [auto: first NVIDIA Vulkan device]
  STOA_WALLS_AI_SAMPLER sampling method            [euler_a]
  STOA_WALLS_AI_SAT     saturation after render    [0.72]
"""
import argparse, datetime, hashlib, json, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1920, 1080
GEN_W, GEN_H = 1024, 576
MARGIN_X, MARGIN_TOP, MARGIN_BOTTOM = 120, 90, 140
LIGHT, DARK, BRONZE = (236, 230, 216), (28, 26, 23), (196, 154, 92)
DATA = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")) + "/stoa"
DEFAULT_MODEL = DATA + "/models/sd_xl_turbo_1.0_fp16.safetensors"
# Memento wallpapers keep their un-annotated image here so the week bar can be
# redrawn later (--refresh) without running the model again.
BASE_DIR = DATA + "/walls-base"

# ── Prompts ──────────────────────────────────────────────────────
# Muted Stoa palettes; the theme only biases the subject.
PALETTES = [
    "muted bronze and charcoal", "dusty olive and stone gray",
    "terracotta, sand and slate", "ash gray and faded gold",
    "deep brown and oxidized copper", "bone white and dark umber",
    "sage green and warm travertine", "slate blue-gray and pale bronze",
]
LIGHTS = ["soft diffuse light", "warm low sun glow", "dim museum light", "overcast light"]
SUBJECTS = {
    "marble": [
        "abstract marble texture with thin mineral veins",
        "abstract flowing marble swirls",
        "polished dark stone slab with golden veining",
        "abstract fluid ink waves in smooth silky layers",
    ],
    "parchment": [
        "abstract warm parchment paper washes with soft gradients",
        "abstract layered translucent pigment on aged paper",
        "abstract brushed limewash plaster wall",
        "abstract overlapping soft rectangles of clay plaster",
    ],
    "columns": [
        "abstract minimalist vertical {m} columns dissolving into haze",
        "abstract receding rows of {m} pillars, shallow depth of field",
        "abstract backlit {m} colonnade, long soft shadows",
    ],
    "memento": [
        "abstract dark ink on aged stone with sparse speckled patina",
        "abstract oxidized bronze surface with faint cracks",
        "abstract weathered black stone with sparse gold dust",
        "abstract cracked dark plaster, quiet and melancholic",
    ],
}
MATERIALS = ["weathered marble", "carved stone", "aged wood", "sandstone", "travertine"]
SUFFIX = "desaturated, low saturation, matte, calm negative space, minimal, no text, no people"


def seed_of(text):
    return int(hashlib.sha1(text.encode()).hexdigest()[:8], 16)


def build_prompt(theme, seed):
    rng = np.random.default_rng(seed)
    pick = lambda xs: xs[int(rng.integers(len(xs)))]
    subject = pick(SUBJECTS.get(theme, SUBJECTS["marble"])).format(m=pick(MATERIALS))
    return f"{subject}, {pick(PALETTES)}, {pick(LIGHTS)}, {SUFFIX}"


# ── sd-cli ───────────────────────────────────────────────────────
def pick_device():
    dev = os.environ.get("STOA_WALLS_AI_DEVICE")
    if dev is not None:
        return dev  # may be "" to disable
    try:
        out = subprocess.run(["sd-cli", "--list-devices"], capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    for line in out.splitlines():
        if "NVIDIA" in line and "\t" in line:
            return line.split("\t")[0].strip()
    return ""


def run_sd(prompt, seed, raw_path, tries=3):
    model = os.environ.get("STOA_WALLS_AI_MODEL", DEFAULT_MODEL)
    if not os.path.isfile(model):
        sys.exit(f"stoa-walls-ai: model not found: {model}\n  run: stoa-walls setup-ai")
    cmd = ["sd-cli", "-m", model, "--type", os.environ.get("STOA_WALLS_AI_TYPE", "q8_0"),
           "-p", prompt, "--steps", os.environ.get("STOA_WALLS_AI_STEPS", "4"),
           "--cfg-scale", "1.0", "--sampling-method", os.environ.get("STOA_WALLS_AI_SAMPLER", "euler_a"),
           "-W", str(GEN_W), "-H", str(GEN_H), "--vae-tiling", "-s", str(seed), "-o", raw_path]
    dev = pick_device()
    if dev:
        cmd += ["--backend", f"diffusion={dev},te={dev},vae={dev}"]
    for attempt in range(1, tries + 1):
        if os.path.exists(raw_path):
            os.remove(raw_path)
        # sd-cli sometimes aborts at exit (heap corruption) AFTER saving the
        # image, so judge success by the file, not the exit code.
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            Image.open(raw_path).load()
            return
        except (OSError, SyntaxError):
            print(f"  [~] sd-cli attempt {attempt}/{tries} produced no image", file=sys.stderr)
    sys.exit("stoa-walls-ai: sd-cli failed")


# ── Text placement ───────────────────────────────────────────────
def font_path(style):
    out = subprocess.run(["fc-match", f"Noto Serif:{style}", "-f", "%{file}"],
                         capture_output=True, text=True).stdout.strip()
    return out or "/usr/share/fonts/TTF/DejaVuSerif.ttf"


def split_quote(q):
    if " — " in q:
        body, author = q.rsplit(" — ", 1)
        return body.strip(), author.strip()
    return q.strip(), ""


def pick_size(n):
    return 46 if n <= 60 else 40 if n <= 120 else 34 if n <= 200 else 30 if n <= 320 else 26


def wrap(text, font, max_w):
    lines, cur = [], ""
    for word in text.split():
        t = f"{cur} {word}".strip()
        if font.getlength(t) <= max_w or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def spaced_len(text, font, tracking):
    return sum(font.getlength(c) + tracking for c in text) - tracking


def rel_lum(rgb):
    c = np.asarray(rgb, dtype=np.float32) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def energy_map(img):
    g = np.asarray(img.convert("L").resize((W // 4, H // 4), Image.LANCZOS), dtype=np.float32) / 255
    e = np.abs(np.diff(g, axis=1, prepend=g[:, :1])) + np.abs(np.diff(g, axis=0, prepend=g[:1, :]))
    k = 5
    pad = np.pad(g, k // 2, mode="edge")
    s = np.zeros_like(g); s2 = np.zeros_like(g)
    for dy in range(k):
        for dx in range(k):
            win = pad[dy:dy + g.shape[0], dx:dx + g.shape[1]]
            s += win; s2 += win * win
    var = s2 / k**2 - (s / k**2) ** 2
    return e + 2.0 * np.sqrt(np.maximum(var, 0))


def integral(a):
    return np.pad(a, ((1, 0), (1, 0))).cumsum(0).cumsum(1)


def box_mean(ii, x, y, w, h):
    return (ii[y + h, x + w] - ii[y, x + w] - ii[y + h, x] + ii[y, x]) / (w * h)


def choose_box(energy, lum, bw, bh, seed):
    s = 4
    ii = integral(energy)
    e90 = np.percentile(energy, 90) + 1e-6
    LL, LD = rel_lum(LIGHT), rel_lum(DARK)
    cw, ch = bw // s + 1, bh // s + 1
    cands = []
    for y in range(MARGIN_TOP // s, (H - MARGIN_BOTTOM) // s - ch, 6):
        for x in range(MARGIN_X // s, (W - MARGIN_X) // s - cw, 6):
            pad = 3
            x0, y0 = max(x - pad, 0), max(y - pad, 0)
            x1, y1 = min(x + cw + pad, energy.shape[1]), min(y + ch + pad, energy.shape[0])
            cost = box_mean(ii, x0, y0, x1 - x0, y1 - y0) / e90
            p10, p90 = np.percentile(lum[y:y + ch, x:x + cw], [10, 90])
            best = max((LL + 0.05) / (p90 + 0.05), (p10 + 0.05) / (LD + 0.05))
            cost += 1.5 * max(0.0, 4.5 - best) / 4.5          # spots that would need a scrim
            dist = np.hypot((x + cw / 2) * s - W / 2, (y + ch / 2) * s - H / 2)
            cost += 0.10 * np.exp(-(dist / 260) ** 2)           # mild anti-dead-center
            cands.append((cost, x * s, y * s))
    cands.sort()
    chosen = []
    for c in cands:
        if all(np.hypot(c[1] - o[1], c[2] - o[2]) > 350 for o in chosen):
            chosen.append(c)
        if len(chosen) == 4:
            break
    chosen = [c for c in chosen if c[0] <= chosen[0][0] + 0.25]  # never gamble on a clearly worse spot
    w = np.array([0.5, 0.25, 0.15, 0.10])[:len(chosen)]
    idx = int(np.random.default_rng(seed).choice(len(chosen), p=w / w.sum()))
    return chosen[idx][1], chosen[idx][2]


TITLE = "memento mori"
TERTIARY_DARK, TERTIARY_LIGHT = (212, 168, 75), (168, 124, 28)  # Stoa palette mTertiary


def week_fraction(now=None):
    """Share of the ISO week (Monday 00:00 -> Monday 00:00) already elapsed.

    Same formula as `week_pct` in stoa-memento-data, computed here so the
    renderer does not consume a quote from the playlist.
    """
    now = now or datetime.datetime.now()
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elapsed = (now.isoweekday() - 1) * 86400 + (now - midnight).total_seconds()
    return min(max(elapsed / (7 * 86400), 0.0), 1.0)


def compose(img, quote, memento, seed):
    """Quote wallpaper, or (memento=True) 'memento mori' + week progress bar."""
    if memento:
        title_px, gap, bar_h = 72, 34, 8
        f_title = ImageFont.truetype(font_path("regular"), title_px)
        bw = int(spaced_len(TITLE, f_title, 12))
        bh = int(title_px * 1.25) + gap + bar_h
    else:
        body, author = split_quote(quote)
        size = pick_size(len(body))
        f_body = ImageFont.truetype(font_path("italic"), size)
        f_auth = ImageFont.truetype(font_path("regular"), max(int(size * 0.62), 18))
        lines = wrap(body, f_body, int(min(max(np.sqrt(len(body)) * 95, 620), 1150)))
        lh = int(size * 1.4)
        bw = int(max(f_body.getlength(l) for l in lines))
        bh = len(lines) * lh
        if author:
            bh += int(size * 0.62 * 1.5) + int(size * 0.5)
            bw = max(bw, int(f_auth.getlength("— " + author)))

    lum = rel_lum(np.asarray(img.resize((W // 4, H // 4), Image.LANCZOS), dtype=np.float32))
    bx, by = choose_box(energy_map(img), lum, bw, bh, seed)
    cx = bx + bw / 2
    align = "left" if cx < W * 0.38 else "right" if cx > W * 0.62 else "center"

    region = np.asarray(img.crop((bx - 20, by - 20, bx + bw + 20, by + bh + 20)), dtype=np.float32)
    L = rel_lum(region)
    p10, p90 = np.percentile(L, [10, 90])
    cr_light = (rel_lum(LIGHT) + 0.05) / (p90 + 0.05)
    cr_dark = (p10 + 0.05) / (rel_lum(DARK) + 0.05)
    use_light = cr_light >= cr_dark
    fg = LIGHT if use_light else DARK
    scrim = max(cr_light, cr_dark) < 4.5

    canvas = img.convert("RGBA")
    if scrim:
        pad = 70
        target = np.array((10, 9, 8) if use_light else (244, 238, 224), dtype=np.float32)
        tone = tuple(int(v) for v in region.reshape(-1, 3).mean(0) * 0.25 + target * 0.75) + (185,)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle(
            (bx - pad, by - pad, bx + bw + pad, by + bh + pad), radius=90, fill=tone)
        canvas = Image.alpha_composite(canvas, layer.filter(ImageFilter.GaussianBlur(60)))

    def x_for(width):
        return bx if align == "left" else bx + bw - width if align == "right" else bx + (bw - width) / 2

    text = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(text)
    if memento:
        title_col = (BRONZE if use_light else DARK) + (235,)
        x = x_for(bw)
        for c in TITLE:
            d.text((x, by), c, font=f_title, fill=title_col)
            x += f_title.getlength(c) + 12
        bar_y = by + int(title_px * 1.25) + gap
        bx0 = int(x_for(bw))
        d.rounded_rectangle((bx0, bar_y, bx0 + bw, bar_y + bar_h), radius=bar_h // 2, fill=fg + (70,))
        fill_w = max(int(bw * week_fraction()), bar_h)
        d.rounded_rectangle((bx0, bar_y, bx0 + fill_w, bar_y + bar_h), radius=bar_h // 2,
                            fill=(TERTIARY_DARK if use_light else TERTIARY_LIGHT) + (255,))
    else:
        y = by
        for l in lines:
            d.text((x_for(f_body.getlength(l)), y), l, font=f_body, fill=fg + (255,))
            y += lh
        if author:
            a = "— " + author
            d.text((x_for(f_auth.getlength(a)), y + int(size * 0.5)), a, font=f_auth, fill=fg + (200,))

    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    halo.paste(Image.new("RGBA", (W, H), (0, 0, 0, 110) if use_light else (255, 250, 240, 110)),
               mask=text.getchannel("A"))
    canvas = Image.alpha_composite(canvas, halo.filter(ImageFilter.GaussianBlur(5)))
    return Image.alpha_composite(canvas, text).convert("RGB")


# ── main ─────────────────────────────────────────────────────────
def base_paths(out):
    name = os.path.basename(out)
    return os.path.join(BASE_DIR, name), os.path.join(BASE_DIR, name + ".json")


def refresh(out):
    """Redraw the week bar of an existing memento wallpaper from its saved base."""
    base, meta = base_paths(out)
    if not (os.path.isfile(base) and os.path.isfile(meta)):
        sys.exit(f"stoa-walls-ai: no saved base for {os.path.basename(out)} (render it again)")
    seed = json.load(open(meta))["seed"]
    save(compose(Image.open(base).convert("RGB"), "", True, seed), out)


def save(img, out):
    tmp_out = out + ".tmp.png"
    img.save(tmp_out)
    os.replace(tmp_out, out)


def main():
    ap = argparse.ArgumentParser(description="Render one AI wallpaper for stoa-walls.")
    ap.add_argument("--theme", choices=sorted(SUBJECTS))
    ap.add_argument("--seed", type=int)
    ap.add_argument("--out", required=True)
    ap.add_argument("--quote", default="")
    ap.add_argument("--print-prompt", action="store_true", help="only print the prompt")
    ap.add_argument("--refresh", action="store_true",
                    help="redraw the memento week bar from the saved base (no model run)")
    a = ap.parse_args()

    if a.refresh:
        return refresh(a.out)
    if a.theme is None or a.seed is None:
        ap.error("--theme and --seed are required")
    prompt = build_prompt(a.theme, a.seed)
    if a.print_prompt:
        print(prompt)
        return
    with tempfile.TemporaryDirectory(prefix="stoa-walls-") as tmp:
        raw = os.path.join(tmp, "raw.png")
        run_sd(prompt, a.seed, raw)
        img = Image.open(raw).convert("RGB").resize((W, H), Image.LANCZOS)
    sat = float(os.environ.get("STOA_WALLS_AI_SAT", "0.72"))
    if sat != 1.0:
        img = Image.blend(img.convert("L").convert("RGB"), img, sat)
    if a.theme == "memento":  # no quote: just "memento mori" and the week bar
        base, meta = base_paths(a.out)
        os.makedirs(BASE_DIR, exist_ok=True)
        img.save(base)
        json.dump({"theme": a.theme, "seed": a.seed}, open(meta, "w"))
        img = compose(img, "", True, a.seed)
    elif a.quote:
        img = compose(img, a.quote, False, seed_of(a.quote))
    save(img, a.out)


if __name__ == "__main__":
    main()
