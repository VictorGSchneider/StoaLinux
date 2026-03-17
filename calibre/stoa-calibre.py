#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Calibre Configuration                         ║
# ║  "Reading is nourishment for the soul." — Seneca            ║
# ║                                                              ║
# ║  Applies Stoa dark theme and EB Garamond to Calibre.        ║
# ║  Run: python3 stoa-calibre.py                               ║
# ╚══════════════════════════════════════════════════════════════╝

import json
import os

config_dir = os.path.expanduser("~/.config/calibre")
os.makedirs(config_dir, exist_ok=True)

# ── Calibre GUI tweaks (dynamic.json) ──
dynamic_path = os.path.join(config_dir, "dynamic.json.stoa")
dynamic = {}

# Try to load existing config
dyn_file = os.path.join(config_dir, "dynamic.json")
if os.path.exists(dyn_file):
    try:
        with open(dyn_file, "r") as f:
            dynamic = json.load(f)
    except (json.JSONDecodeError, IOError):
        pass

# Apply Stoa reading preferences
dynamic.update({
    "viewer font family": "EB Garamond",
    "viewer font size": 18,
    "viewer color scheme": "dark",
    "viewer background color": "#211e19",
    "viewer foreground color": "#d4cfc4",
    "viewer link color": "#c49a5c",
})

with open(dyn_file, "w") as f:
    json.dump(dynamic, f, indent=2)

print("Stoa theme applied to Calibre!")

# ── Calibre viewer user stylesheet ──
viewer_dir = os.path.join(config_dir, "viewer")
os.makedirs(viewer_dir, exist_ok=True)

user_css = os.path.join(viewer_dir, "user-stylesheet.css")
with open(user_css, "w") as f:
    f.write("""\
/* ╔══════════════════════════════════════════════════════════════╗
   ║  STOA LINUX — Calibre Viewer Stylesheet                    ║
   ║  Stoic reading experience: EB Garamond on dark parchment   ║
   ╚══════════════════════════════════════════════════════════════╝ */

body {
    font-family: "EB Garamond", Georgia, "Times New Roman", serif !important;
    background-color: #211e19 !important;
    color: #d4cfc4 !important;
    line-height: 1.7 !important;
}

a, a:visited {
    color: #c49a5c !important;
}

a:hover {
    color: #d4a84b !important;
}

h1, h2, h3, h4, h5, h6 {
    color: #c49a5c !important;
    font-family: "EB Garamond", Georgia, serif !important;
}

blockquote {
    border-left: 3px solid #c49a5c !important;
    color: #a89f91 !important;
    padding-left: 1em !important;
}

code, pre {
    font-family: "JetBrains Mono", monospace !important;
    background-color: #2d2921 !important;
    color: #d4cfc4 !important;
}

::selection {
    background-color: #c49a5c !important;
    color: #1a1714 !important;
}

img {
    max-width: 100% !important;
}
""")

print("Stoa viewer stylesheet created!")
