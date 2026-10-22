#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Text Prediction (Wayland input method)        ║
# ║  "Choose your words with care." — Epictetus                 ║
# ║                                                              ║
# ║  Word and emoji suggestions in a popup next to the text      ║
# ║  cursor. Runs as a Wayland input method (input-method-v2,    ║
# ║  the protocol fcitx uses), started and stopped by the        ║
# ║  Noctalia stoa/predict plugin (Super+Shift+S).               ║
# ║                                                              ║
# ║    ↓ / ↑      enter the popup (and leave it again)           ║
# ║    ← / →      move between suggestions                       ║
# ║    Enter/Tab  accept       Esc  dismiss       click  accept  ║
# ║                                                              ║
# ║  Requires: python-pywayland, python-cairo, python-gobject    ║
# ║  (Pango). Apps need text-input-v3: GTK, Qt, kitty, foot,     ║
# ║  Zed, Firefox; Chromium/Electron with --enable-wayland-ime.  ║
# ╚══════════════════════════════════════════════════════════════╝
#
# stdout is read by theme/noctalia-plugins/stoa-predict/service.luau: one
# JSON object per line, {"ready": true} once the input method is
# registered, or {"error": "..."} before exiting. Logs go to stderr.

import ctypes
import heapq
import json
import mmap
import os
import re
import signal
import sys
import time
import unicodedata
from bisect import bisect_left
from pathlib import Path

# ── Configuration ──
MAX_SUGGESTIONS = 5
MAX_EMOJIS = 3
MIN_PREFIX = 2
_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
_DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
LANGUAGES_FILE = _CONFIG_HOME / "stoa/predict-languages"   # written by stoa-predict set-languages
LANGUAGE_DIR = _DATA_HOME / "stoa/predict"                 # <code>.txt frequency lists
CUSTOM_WORDS = _CONFIG_HOME / "stoa/predict-words.txt"
FALLBACK_DICTS = [Path("/usr/share/dict/words"), Path("/usr/share/dict/american-english")]
_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
PIDFILE = f"{_RUNTIME_DIR}/stoa-predict.pid"
PROTOCOL_DIR = Path(__file__).resolve().parent / "stoa-predict-protocols"
WAYLAND_XML = Path("/usr/share/wayland/wayland.xml")

# The last word before the cursor: a run of letters (any script, so
# "ação" and "über" count; digits and "_" end it).
WORD_BEFORE_CURSOR = re.compile(r"[^\W\d_]+$")
# U+0080–U+00BF inside a word is UTF-8 read as Latin-1 ("vocãª"), never a
# real spelling; the frequency lists have a few of those.
MOJIBAKE = re.compile("[\u0080-\u00bf]")


def fold(text: str) -> str:
    """Lowercase without accents, for lookup: "Ação" -> "acao"."""
    decomposed = unicodedata.normalize("NFD", text.lower())
    return "".join(c for c in decomposed if not unicodedata.combining(c))


def enabled_languages() -> list[str]:
    try:
        lines = LANGUAGES_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        return ["en"]
    return [line.strip() for line in lines if line.strip() and not line.startswith("#")]


def say(**payload):
    """One protocol line for the Noctalia service."""
    print(json.dumps(payload), flush=True)


def log(message: str):
    print(f"[predict] {message}", file=sys.stderr, flush=True)


DEBUG = bool(os.environ.get("STOA_PREDICT_DEBUG"))


def debug(message: str):
    if DEBUG:
        log(message)


def remove_pidfile():
    """Only ours: a second instance that lost the input-method slot must not
    delete the file pointing at the one that holds it."""
    try:
        if Path(PIDFILE).read_text().strip() == str(os.getpid()):
            os.remove(PIDFILE)
    except OSError:
        pass


def quit_now(code: int = 0):
    """Exit from anywhere, including a Wayland callback. pywayland runs
    callbacks through cffi, which swallows SystemExit ("Exception ignored
    from cffi callback"), so sys.exit() there would leave the daemon
    running. Closing the connection is all the cleanup the compositor needs:
    it drops the keyboard grab and the popup with it."""
    remove_pidfile()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)


class EmojiIndex:
    """Keyword-to-emoji lookup for related emoji suggestions."""

    def __init__(self):
        self.keyword_map: dict[str, list[dict]] = {}
        self._load()

    def _load(self):
        """Load emoji keyword index from bundled file or generate a basic one."""
        emoji_path = Path.home() / ".config/stoa/predict-emojis.json"
        if emoji_path.exists():
            try:
                data = json.loads(emoji_path.read_text(encoding="utf-8"))
                self.keyword_map = data
                print(f"[predict] Loaded {len(self.keyword_map)} emoji keywords", file=sys.stderr)
                return
            except Exception:
                pass

        # Built-in compact emoji index (common words → emojis)
        self.keyword_map = {
            "happy": [{"emoji": "😊", "name": "happy"}, {"emoji": "😄", "name": "grin"}, {"emoji": "🥳", "name": "party"}],
            "sad": [{"emoji": "😢", "name": "sad"}, {"emoji": "😭", "name": "crying"}, {"emoji": "😔", "name": "pensive"}],
            "love": [{"emoji": "❤️", "name": "heart"}, {"emoji": "😍", "name": "heart eyes"}, {"emoji": "💕", "name": "hearts"}],
            "heart": [{"emoji": "❤️", "name": "red heart"}, {"emoji": "💜", "name": "purple"}, {"emoji": "💚", "name": "green"}],
            "fire": [{"emoji": "🔥", "name": "fire"}, {"emoji": "🔥", "name": "hot"}],
            "star": [{"emoji": "⭐", "name": "star"}, {"emoji": "🌟", "name": "glowing"}, {"emoji": "✨", "name": "sparkles"}],
            "sun": [{"emoji": "☀️", "name": "sun"}, {"emoji": "🌞", "name": "sun face"}, {"emoji": "🌅", "name": "sunrise"}],
            "moon": [{"emoji": "🌙", "name": "moon"}, {"emoji": "🌕", "name": "full moon"}, {"emoji": "🌑", "name": "new moon"}],
            "rain": [{"emoji": "🌧️", "name": "rain"}, {"emoji": "☔", "name": "umbrella"}, {"emoji": "💧", "name": "droplet"}],
            "snow": [{"emoji": "❄️", "name": "snowflake"}, {"emoji": "⛄", "name": "snowman"}, {"emoji": "🌨️", "name": "snow"}],
            "cloud": [{"emoji": "☁️", "name": "cloud"}, {"emoji": "🌥️", "name": "partly sunny"}],
            "wind": [{"emoji": "💨", "name": "wind"}, {"emoji": "🌬️", "name": "wind face"}],
            "water": [{"emoji": "💧", "name": "droplet"}, {"emoji": "🌊", "name": "wave"}, {"emoji": "💦", "name": "splash"}],
            "food": [{"emoji": "🍕", "name": "pizza"}, {"emoji": "🍔", "name": "burger"}, {"emoji": "🍜", "name": "noodles"}],
            "coffee": [{"emoji": "☕", "name": "coffee"}, {"emoji": "🫖", "name": "teapot"}],
            "beer": [{"emoji": "🍺", "name": "beer"}, {"emoji": "🍻", "name": "cheers"}],
            "wine": [{"emoji": "🍷", "name": "wine"}, {"emoji": "🥂", "name": "champagne"}],
            "cake": [{"emoji": "🎂", "name": "birthday"}, {"emoji": "🍰", "name": "cake slice"}],
            "music": [{"emoji": "🎵", "name": "music"}, {"emoji": "🎶", "name": "notes"}, {"emoji": "🎸", "name": "guitar"}],
            "book": [{"emoji": "📖", "name": "book"}, {"emoji": "📚", "name": "books"}, {"emoji": "📕", "name": "red book"}],
            "phone": [{"emoji": "📱", "name": "phone"}, {"emoji": "📞", "name": "telephone"}],
            "computer": [{"emoji": "💻", "name": "laptop"}, {"emoji": "🖥️", "name": "desktop"}, {"emoji": "⌨️", "name": "keyboard"}],
            "code": [{"emoji": "💻", "name": "laptop"}, {"emoji": "🧑‍💻", "name": "coder"}, {"emoji": "⚙️", "name": "gear"}],
            "game": [{"emoji": "🎮", "name": "gamepad"}, {"emoji": "🕹️", "name": "joystick"}],
            "money": [{"emoji": "💰", "name": "money bag"}, {"emoji": "💵", "name": "dollar"}, {"emoji": "💸", "name": "money wings"}, {"emoji": "🤑", "name": "money face"}],
            "time": [{"emoji": "⏰", "name": "alarm"}, {"emoji": "🕐", "name": "clock"}, {"emoji": "⌛", "name": "hourglass"}],
            "home": [{"emoji": "🏠", "name": "house"}, {"emoji": "🏡", "name": "garden"}],
            "car": [{"emoji": "🚗", "name": "car"}, {"emoji": "🚙", "name": "suv"}],
            "plane": [{"emoji": "✈️", "name": "airplane"}, {"emoji": "🛫", "name": "departure"}],
            "rocket": [{"emoji": "🚀", "name": "rocket"}],
            "dog": [{"emoji": "🐕", "name": "dog"}, {"emoji": "🐶", "name": "dog face"}],
            "cat": [{"emoji": "🐈", "name": "cat"}, {"emoji": "🐱", "name": "cat face"}],
            "fish": [{"emoji": "🐟", "name": "fish"}, {"emoji": "🐠", "name": "tropical"}],
            "bird": [{"emoji": "🐦", "name": "bird"}, {"emoji": "🦅", "name": "eagle"}],
            "tree": [{"emoji": "🌳", "name": "tree"}, {"emoji": "🌲", "name": "evergreen"}, {"emoji": "🌴", "name": "palm"}],
            "flower": [{"emoji": "🌸", "name": "cherry blossom"}, {"emoji": "🌹", "name": "rose"}, {"emoji": "🌻", "name": "sunflower"}],
            "check": [{"emoji": "✅", "name": "check"}, {"emoji": "☑️", "name": "checkbox"}],
            "cross": [{"emoji": "❌", "name": "cross"}, {"emoji": "✖️", "name": "multiply"}],
            "warning": [{"emoji": "⚠️", "name": "warning"}, {"emoji": "🚨", "name": "alert"}],
            "error": [{"emoji": "❌", "name": "error"}, {"emoji": "🚫", "name": "prohibited"}],
            "ok": [{"emoji": "👍", "name": "thumbs up"}, {"emoji": "👌", "name": "ok hand"}],
            "good": [{"emoji": "👍", "name": "thumbs up"}, {"emoji": "✨", "name": "sparkles"}, {"emoji": "🌟", "name": "star"}],
            "bad": [{"emoji": "👎", "name": "thumbs down"}, {"emoji": "😬", "name": "grimace"}],
            "laugh": [{"emoji": "😂", "name": "tears of joy"}, {"emoji": "🤣", "name": "rofl"}, {"emoji": "😆", "name": "laughing"}],
            "think": [{"emoji": "🤔", "name": "thinking"}, {"emoji": "💭", "name": "thought"}, {"emoji": "🧠", "name": "brain"}],
            "idea": [{"emoji": "💡", "name": "lightbulb"}, {"emoji": "🧠", "name": "brain"}],
            "sleep": [{"emoji": "😴", "name": "sleeping"}, {"emoji": "💤", "name": "zzz"}, {"emoji": "🛏️", "name": "bed"}],
            "angry": [{"emoji": "😠", "name": "angry"}, {"emoji": "😡", "name": "rage"}, {"emoji": "🤬", "name": "cursing"}],
            "cool": [{"emoji": "😎", "name": "sunglasses"}, {"emoji": "🆒", "name": "cool"}],
            "sick": [{"emoji": "🤒", "name": "thermometer"}, {"emoji": "🤢", "name": "nauseated"}, {"emoji": "🤮", "name": "vomiting"}],
            "work": [{"emoji": "💼", "name": "briefcase"}, {"emoji": "🏢", "name": "office"}],
            "party": [{"emoji": "🎉", "name": "party"}, {"emoji": "🥳", "name": "partying"}, {"emoji": "🎊", "name": "confetti"}],
            "gift": [{"emoji": "🎁", "name": "gift"}, {"emoji": "🎀", "name": "ribbon"}],
            "flag": [{"emoji": "🏳️", "name": "white flag"}, {"emoji": "🚩", "name": "red flag"}, {"emoji": "🏁", "name": "checkered"}],
            "eye": [{"emoji": "👀", "name": "eyes"}, {"emoji": "👁️", "name": "eye"}],
            "hand": [{"emoji": "👋", "name": "wave"}, {"emoji": "✋", "name": "raised"}, {"emoji": "🤝", "name": "handshake"}],
            "hello": [{"emoji": "👋", "name": "wave"}, {"emoji": "🙋", "name": "greeting"}],
            "bye": [{"emoji": "👋", "name": "wave"}, {"emoji": "✌️", "name": "peace"}],
            "yes": [{"emoji": "✅", "name": "check"}, {"emoji": "👍", "name": "thumbs up"}],
            "no": [{"emoji": "❌", "name": "cross"}, {"emoji": "👎", "name": "thumbs down"}, {"emoji": "🚫", "name": "prohibited"}],
            "question": [{"emoji": "❓", "name": "question"}, {"emoji": "🤷", "name": "shrug"}],
            "key": [{"emoji": "🔑", "name": "key"}, {"emoji": "🗝️", "name": "old key"}],
            "lock": [{"emoji": "🔒", "name": "locked"}, {"emoji": "🔓", "name": "unlocked"}],
            "mail": [{"emoji": "📧", "name": "email"}, {"emoji": "✉️", "name": "envelope"}],
            "link": [{"emoji": "🔗", "name": "link"}, {"emoji": "⛓️", "name": "chains"}],
            "pin": [{"emoji": "📌", "name": "pushpin"}, {"emoji": "📍", "name": "pin"}],
            "bug": [{"emoji": "🐛", "name": "bug"}, {"emoji": "🐞", "name": "ladybug"}, {"emoji": "🪲", "name": "beetle"}],
            "light": [{"emoji": "💡", "name": "lightbulb"}, {"emoji": "🔦", "name": "flashlight"}],
            "dark": [{"emoji": "🌑", "name": "new moon"}, {"emoji": "🌙", "name": "crescent"}],
            "fast": [{"emoji": "⚡", "name": "lightning"}, {"emoji": "🏎️", "name": "racing"}],
            "slow": [{"emoji": "🐢", "name": "turtle"}, {"emoji": "🦥", "name": "sloth"}],
            "up": [{"emoji": "⬆️", "name": "up arrow"}, {"emoji": "📈", "name": "chart up"}],
            "down": [{"emoji": "⬇️", "name": "down arrow"}, {"emoji": "📉", "name": "chart down"}],
            "world": [{"emoji": "🌍", "name": "globe"}, {"emoji": "🌎", "name": "americas"}, {"emoji": "🗺️", "name": "map"}],
            "brain": [{"emoji": "🧠", "name": "brain"}],
            "muscle": [{"emoji": "💪", "name": "flexed bicep"}],
            "clap": [{"emoji": "👏", "name": "clapping"}],
            "pray": [{"emoji": "🙏", "name": "folded hands"}],
            "stop": [{"emoji": "🛑", "name": "stop sign"}, {"emoji": "✋", "name": "raised hand"}],
            "run": [{"emoji": "🏃", "name": "running"}, {"emoji": "💨", "name": "wind"}],
            "write": [{"emoji": "✍️", "name": "writing"}, {"emoji": "📝", "name": "memo"}],
            "read": [{"emoji": "📖", "name": "book"}, {"emoji": "👓", "name": "glasses"}],
            "eat": [{"emoji": "🍽️", "name": "plate"}, {"emoji": "😋", "name": "yummy"}],
            "drink": [{"emoji": "🥤", "name": "cup"}, {"emoji": "🍹", "name": "cocktail"}],
            "smile": [{"emoji": "😊", "name": "smile"}, {"emoji": "😁", "name": "grin"}, {"emoji": "🙂", "name": "slight smile"}],
            "cry": [{"emoji": "😢", "name": "cry"}, {"emoji": "😭", "name": "sobbing"}],
            "surprise": [{"emoji": "😮", "name": "open mouth"}, {"emoji": "😲", "name": "astonished"}],
            "fear": [{"emoji": "😨", "name": "fearful"}, {"emoji": "😱", "name": "screaming"}],
            "confused": [{"emoji": "😕", "name": "confused"}, {"emoji": "🤨", "name": "raised brow"}],
            "tired": [{"emoji": "😫", "name": "tired"}, {"emoji": "🥱", "name": "yawning"}],
            "strong": [{"emoji": "💪", "name": "flexed"}, {"emoji": "🦾", "name": "mechanical arm"}],
            "magic": [{"emoji": "✨", "name": "sparkles"}, {"emoji": "🪄", "name": "wand"}, {"emoji": "🧙", "name": "mage"}],
            "crown": [{"emoji": "👑", "name": "crown"}],
            "king": [{"emoji": "👑", "name": "crown"}, {"emoji": "🤴", "name": "prince"}],
            "queen": [{"emoji": "👑", "name": "crown"}, {"emoji": "👸", "name": "princess"}],
            "baby": [{"emoji": "👶", "name": "baby"}, {"emoji": "🍼", "name": "bottle"}],
            "family": [{"emoji": "👨‍👩‍👧‍👦", "name": "family"}],
            "friend": [{"emoji": "🤝", "name": "handshake"}, {"emoji": "👫", "name": "holding hands"}],
            "war": [{"emoji": "⚔️", "name": "swords"}, {"emoji": "🏴", "name": "black flag"}],
            "peace": [{"emoji": "☮️", "name": "peace"}, {"emoji": "🕊️", "name": "dove"}, {"emoji": "✌️", "name": "victory"}],
            "math": [{"emoji": "🔢", "name": "numbers"}, {"emoji": "➕", "name": "plus"}, {"emoji": "📐", "name": "ruler"}],
            "science": [{"emoji": "🔬", "name": "microscope"}, {"emoji": "🧪", "name": "test tube"}],
            "art": [{"emoji": "🎨", "name": "palette"}, {"emoji": "🖼️", "name": "frame"}],
            "sport": [{"emoji": "⚽", "name": "soccer"}, {"emoji": "🏀", "name": "basketball"}, {"emoji": "🏈", "name": "football"}],
            "mountain": [{"emoji": "⛰️", "name": "mountain"}, {"emoji": "🏔️", "name": "snow capped"}],
            "beach": [{"emoji": "🏖️", "name": "beach"}, {"emoji": "🌴", "name": "palm tree"}],
            "city": [{"emoji": "🏙️", "name": "cityscape"}, {"emoji": "🌆", "name": "dusk"}],
            "night": [{"emoji": "🌙", "name": "crescent"}, {"emoji": "🌃", "name": "night city"}],
            "morning": [{"emoji": "🌅", "name": "sunrise"}, {"emoji": "☀️", "name": "sun"}],
            "thanks": [{"emoji": "🙏", "name": "folded hands"}, {"emoji": "💖", "name": "sparkling heart"}],
            "sorry": [{"emoji": "😔", "name": "pensive"}, {"emoji": "🙏", "name": "folded hands"}],
            "please": [{"emoji": "🙏", "name": "folded hands"}, {"emoji": "🥺", "name": "pleading"}],
            "wait": [{"emoji": "⏳", "name": "hourglass"}, {"emoji": "⏱️", "name": "stopwatch"}],
            "hurry": [{"emoji": "⚡", "name": "lightning"}, {"emoji": "🏃", "name": "running"}],
            "boring": [{"emoji": "😐", "name": "neutral"}, {"emoji": "🥱", "name": "yawning"}],
            "crazy": [{"emoji": "🤪", "name": "zany"}, {"emoji": "😜", "name": "winking tongue"}],
            "celebrate": [{"emoji": "🎉", "name": "party"}, {"emoji": "🎊", "name": "confetti"}, {"emoji": "🥂", "name": "toast"}],
            "danger": [{"emoji": "⚠️", "name": "warning"}, {"emoji": "☠️", "name": "skull"}, {"emoji": "💀", "name": "skull"}],
            "secret": [{"emoji": "🤫", "name": "shushing"}, {"emoji": "🔒", "name": "locked"}],
            "lucky": [{"emoji": "🍀", "name": "four leaf clover"}, {"emoji": "🎰", "name": "slot machine"}],
            "camera": [{"emoji": "📷", "name": "camera"}, {"emoji": "📸", "name": "flash"}],
            "video": [{"emoji": "🎥", "name": "movie camera"}, {"emoji": "📹", "name": "video camera"}],
            "tool": [{"emoji": "🔧", "name": "wrench"}, {"emoji": "🛠️", "name": "tools"}],
            "build": [{"emoji": "🔨", "name": "hammer"}, {"emoji": "🏗️", "name": "construction"}],
            "paint": [{"emoji": "🎨", "name": "palette"}, {"emoji": "🖌️", "name": "paintbrush"}],
            "clean": [{"emoji": "🧹", "name": "broom"}, {"emoji": "🧼", "name": "soap"}, {"emoji": "✨", "name": "sparkles"}],
            "trash": [{"emoji": "🗑️", "name": "wastebasket"}, {"emoji": "♻️", "name": "recycle"}],
            "save": [{"emoji": "💾", "name": "floppy disk"}, {"emoji": "📥", "name": "inbox"}],
            "search": [{"emoji": "🔍", "name": "magnifying glass"}, {"emoji": "🔎", "name": "right magnifying"}],
            "settings": [{"emoji": "⚙️", "name": "gear"}, {"emoji": "🔧", "name": "wrench"}],
            "update": [{"emoji": "🔄", "name": "arrows"}, {"emoji": "⬆️", "name": "up arrow"}],
            "linux": [{"emoji": "🐧", "name": "penguin"}],
            "windows": [{"emoji": "🪟", "name": "window"}],
            "apple": [{"emoji": "🍎", "name": "red apple"}, {"emoji": "🍏", "name": "green apple"}],
        }
        print(f"[predict] Loaded {len(self.keyword_map)} built-in emoji keywords", file=sys.stderr)

    def search(self, word: str, limit: int = 3) -> list[dict]:
        """Return emojis related to the given word."""
        word = word.lower()
        # Exact match first
        if word in self.keyword_map:
            return self.keyword_map[word][:limit]
        # Prefix match
        results = []
        for kw, emojis in self.keyword_map.items():
            if kw.startswith(word) or word.startswith(kw):
                results.extend(emojis)
                if len(results) >= limit:
                    break
        # Deduplicate by emoji char
        seen = set()
        unique = []
        for e in results:
            if e["emoji"] not in seen:
                seen.add(e["emoji"])
                unique.append(e)
        return unique[:limit]


class WordDictionary:
    """Word suggestions for the enabled languages, most frequent first.

    Each language is a frequency list (`word count` per line, from
    FrequencyWords — OpenSubtitles 2018, CC BY-SA 4.0) that
    `stoa-predict set-languages` downloads into LANGUAGE_DIR; the choice is
    in LANGUAGES_FILE (one code per line). Languages are merged by relative
    frequency, so a common Portuguese word and a common English one rank
    alike. Lookup ignores case and accents: "acao" finds "ação"."""

    def __init__(self, languages: list[str] | None = None):
        self.languages = enabled_languages() if languages is None else languages
        scores: dict[str, float] = {}
        for code in self.languages:
            self._load_language(code, scores)
        if not scores:
            self._load_fallback(scores)
        scores = self._drop_rare_variants(scores)
        self._load_custom(scores)
        self.index = sorted((fold(w), -score, w) for w, score in scores.items())
        self.keys = [key for key, _score, _word in self.index]

    def _load_language(self, code: str, scores: dict):
        path = LANGUAGE_DIR / f"{code}.txt"
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            log(f"language '{code}' is enabled but {path} is missing — re-add it in Stoa Settings")
            return
        counts = {}
        for line in lines:
            parts = line.split()
            if not parts:
                continue
            word = parts[0].lower()
            if len(word) < MIN_PREFIX or not WORD_BEFORE_CURSOR.fullmatch(word) or MOJIBAKE.search(word):
                continue
            count = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 1
            counts[word] = counts.get(word, 0) + count
        total = sum(counts.values()) or 1
        for word, count in counts.items():
            scores[word] = max(scores.get(word, 0.0), count / total)
        log(f"Loaded {len(counts)} words for '{code}'")

    @staticmethod
    def _drop_rare_variants(scores: dict) -> dict:
        """Subtitle lists carry typos that differ only in accents ("nâo",
        "näo" next to "não"). Keep a spelling only if it is at least 5% as
        frequent as the commonest word that folds the same way, which still
        keeps real pairs such as "esta"/"está"."""
        best: dict[str, float] = {}
        for word, score in scores.items():
            key = fold(word)
            best[key] = max(best.get(key, 0.0), score)
        return {w: sc for w, sc in scores.items() if sc >= 0.05 * best[fold(w)]}

    def _load_fallback(self, scores: dict):
        """No language downloaded yet: the system word list, unranked."""
        for path in FALLBACK_DICTS:
            try:
                raw = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for line in raw.splitlines():
                word = line.strip().lower()
                if len(word) >= MIN_PREFIX and WORD_BEFORE_CURSOR.fullmatch(word):
                    scores.setdefault(word, 0.0)
            log(f"Loaded {len(scores)} words from {path} (no prediction language downloaded)")
            return
        log("WARNING: no word list — add a language in Stoa Settings → Keyboard → Text prediction")

    def _load_custom(self, scores: dict):
        """~/.config/stoa/predict-words.txt: your own words, ranked first."""
        try:
            raw = CUSTOM_WORDS.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return
        for line in raw.splitlines():
            word = line.strip()
            if len(word) >= MIN_PREFIX and WORD_BEFORE_CURSOR.fullmatch(word):
                scores[word] = 1.0

    def search(self, prefix: str, limit: int = MAX_SUGGESTIONS) -> list[str]:
        """Up to `limit` words starting with `prefix`, most frequent first."""
        if len(prefix) < MIN_PREFIX or not self.index:
            return []
        key = fold(prefix)
        lo = bisect_left(self.keys, key)
        hi = bisect_left(self.keys, key + "\U0010ffff", lo)
        typed = prefix.lower()
        matches = (entry for entry in self.index[lo:hi] if entry[2] != typed)
        best = heapq.nsmallest(limit, matches, key=lambda entry: entry[1])  # entry[1] = -score
        return [word for _key, _score, word in best]



# ── Wayland protocol bindings ──
# pywayland ships the core protocol only. input-method-v2 and
# virtual-keyboard-v1 are wlroots protocols that no Arch package installs,
# so their XML lives next to this script and the bindings are generated
# once into ~/.cache (keyed by the XML and pywayland version). The core
# protocol is generated into the same package because the generated code
# imports it relatively (`from .wayland import WlSeat`).
def load_protocols():
    import hashlib
    import importlib
    import shutil

    import pywayland
    from pywayland.scanner.protocol import Protocol

    xmls = [
        WAYLAND_XML,
        PROTOCOL_DIR / "input-method-unstable-v2.xml",
        PROTOCOL_DIR / "virtual-keyboard-unstable-v1.xml",
    ]
    digest = hashlib.sha256(
        b"".join(p.read_bytes() for p in xmls) + pywayland.__version__.encode()
    ).hexdigest()[:16]
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    root = cache / "stoa" / "predict-protocols" / digest
    package = root / "stoa_wl"
    if not (package / "__init__.py").exists():
        staging = root.with_name(f"{digest}.tmp{os.getpid()}")
        shutil.rmtree(staging, ignore_errors=True)
        (staging / "stoa_wl").mkdir(parents=True)  # Protocol.output uses a plain os.mkdir
        protocols = [Protocol.parse_file(str(p)) for p in xmls]
        imports = {i.name: p.name for p in protocols for i in p.interface}
        for protocol in protocols:
            protocol.output(str(staging / "stoa_wl"), imports)
        (staging / "stoa_wl" / "__init__.py").touch()
        shutil.rmtree(root, ignore_errors=True)
        os.replace(staging, root)
    sys.path.insert(0, str(root))
    return (
        importlib.import_module("stoa_wl.wayland"),
        importlib.import_module("stoa_wl.input_method_unstable_v2"),
        importlib.import_module("stoa_wl.virtual_keyboard_unstable_v1"),
    )


# ── xkbcommon (ctypes; libxkbcommon is already on every Wayland system) ──
class Xkb:
    """Turns the grab's keycodes into keysyms and text, for the arrow keys
    and for following the typed word in apps that send no surrounding text
    (terminals)."""

    def __init__(self):
        lib = ctypes.CDLL("libxkbcommon.so.0")
        lib.xkb_context_new.restype = ctypes.c_void_p
        lib.xkb_context_new.argtypes = [ctypes.c_int]
        lib.xkb_keymap_new_from_string.restype = ctypes.c_void_p
        lib.xkb_keymap_new_from_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
        lib.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
        lib.xkb_state_new.restype = ctypes.c_void_p
        lib.xkb_state_new.argtypes = [ctypes.c_void_p]
        lib.xkb_state_unref.argtypes = [ctypes.c_void_p]
        lib.xkb_state_update_mask.argtypes = [ctypes.c_void_p] + [ctypes.c_uint32] * 6
        lib.xkb_state_key_get_one_sym.restype = ctypes.c_uint32
        lib.xkb_state_key_get_one_sym.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        lib.xkb_keymap_min_keycode.restype = ctypes.c_uint32
        lib.xkb_keymap_min_keycode.argtypes = [ctypes.c_void_p]
        lib.xkb_keymap_max_keycode.restype = ctypes.c_uint32
        lib.xkb_keymap_max_keycode.argtypes = [ctypes.c_void_p]
        lib.xkb_state_key_get_utf8.restype = ctypes.c_int
        lib.xkb_state_key_get_utf8.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
        self.lib = lib
        self.context = lib.xkb_context_new(0)
        self.keymap = None
        self.state = None

    def set_keymap(self, text: bytes):
        keymap = self.lib.xkb_keymap_new_from_string(self.context, text, 1, 0)
        if not keymap:
            log("could not compile the grab keymap")
            return
        if self.state:
            self.lib.xkb_state_unref(self.state)
            self.lib.xkb_keymap_unref(self.keymap)
        self.keymap = keymap
        self.state = self.lib.xkb_state_new(keymap)

    def update(self, depressed, latched, locked, group):
        if self.state:
            self.lib.xkb_state_update_mask(self.state, depressed, latched, locked, 0, 0, group)

    def keysym(self, key: int) -> int:
        return self.lib.xkb_state_key_get_one_sym(self.state, key + 8) if self.state else 0

    def key_for(self, sym: int, fallback: int) -> int:
        """The evdev code that produces `sym` in the current keymap. The
        grab's keymap is whatever the keyboard sends, so do not assume the
        US/evdev code for BackSpace."""
        if self.state:
            first = self.lib.xkb_keymap_min_keycode(self.keymap)
            last = self.lib.xkb_keymap_max_keycode(self.keymap)
            for code in range(first, last + 1):
                if self.lib.xkb_state_key_get_one_sym(self.state, code) == sym:
                    return code - 8
        return fallback

    def text(self, key: int) -> str:
        if not self.state:
            return ""
        buf = ctypes.create_string_buffer(16)
        n = self.lib.xkb_state_key_get_utf8(self.state, key + 8, buf, 16)
        return buf.raw[:n].decode("utf-8", "replace") if n > 0 else ""


XK_BACKSPACE, XK_TAB, XK_RETURN, XK_ESCAPE = 0xFF08, 0xFF09, 0xFF0D, 0xFF1B
XK_LEFT, XK_UP, XK_RIGHT, XK_DOWN = 0xFF51, 0xFF52, 0xFF53, 0xFF54
XK_KP_ENTER = 0xFF8D
# Keys that move the caret or end the word without typing text.
XK_WORD_BREAKERS = {XK_TAB, XK_RETURN, XK_ESCAPE, XK_LEFT, XK_UP, XK_RIGHT, XK_DOWN, XK_KP_ENTER,
                    0xFF50, 0xFF57, 0xFF55, 0xFF56, 0xFFFF}  # Home End PgUp PgDn Delete
KEY_BACKSPACE = 14  # evdev BackSpace; the fallback when the keymap has none
KEY_PRESSED, KEY_RELEASED = 1, 0


def match_case(word: str, typed: str) -> str:
    """Suggestions come from a lowercase list; follow the case of what was typed."""
    if len(typed) > 1 and typed.isupper():
        return word.upper()
    if typed[:1].isupper():
        return word[:1].upper() + word[1:]
    return word


def load_palette() -> dict:
    """Colours of the active Stoa palette (Super+S → Theme writes StoaCustom)."""
    colours = {
        "mSurface": "#211e19", "mOnSurface": "#d4cfc4", "mOnSurfaceVariant": "#a89f91",
        "mPrimary": "#c49a5c", "mOnPrimary": "#211e19", "mOutline": "#6e6a62",
        "mSurfaceVariant": "#2d2921",
    }
    palettes = Path.home() / ".config/noctalia/palettes"
    for name in ("StoaCustom.json", "Stoa.json"):
        try:
            data = json.loads((palettes / name).read_text(encoding="utf-8"))
            colours.update({k: v for k, v in data.get("dark", {}).items() if isinstance(v, str)})
            break
        except (OSError, ValueError):
            continue
    return colours


def rgb(hex_colour: str, alpha: float = 1.0):
    h = hex_colour.lstrip("#")
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, alpha)


class Popup:
    """The suggestion strip: an input-method popup surface, which the
    compositor places next to the text cursor (below it, or above when
    there is no room), drawn with cairo + Pango into shm buffers."""

    PAD, GAP, CHIP_PAD_X, CHIP_PAD_Y, RADIUS = 5, 3, 9, 4, 7
    FONT = "Sans 10.5"

    def __init__(self, app):
        import cairo
        import gi
        gi.require_version("Pango", "1.0")
        gi.require_version("PangoCairo", "1.0")
        from gi.repository import Pango, PangoCairo
        self.cairo, self.Pango, self.PangoCairo = cairo, Pango, PangoCairo
        self.app = app
        self.surface = app.compositor.create_surface()
        self.popup = app.im.get_input_popup_surface(self.surface)
        self.visible = False
        self.chips = []          # (x0, x1) in surface coordinates, per item
        self.buffers = []        # live (buffer, pool, mmap, fd)
        self.palette = load_palette()

    def _buffer(self, width, height):
        stride = width * 4
        size = stride * height
        fd = os.memfd_create("stoa-predict", os.MFD_CLOEXEC)
        os.ftruncate(fd, size)
        data = mmap.mmap(fd, size)
        pool = self.app.shm.create_pool(fd, size)
        buffer = pool.create_buffer(0, width, height, stride, self.app.wl.WlShm.format.argb8888.value)
        entry = (buffer, pool, data, fd)
        self.buffers.append(entry)

        def released(_buffer):
            buffer.destroy()
            pool.destroy()
            data.close()
            os.close(fd)
            if entry in self.buffers:
                self.buffers.remove(entry)

        buffer.dispatcher["release"] = released
        return buffer, data, stride

    def show(self, items, selected):
        cairo, Pango, PangoCairo = self.cairo, self.Pango, self.PangoCairo
        scale = self.app.scale
        font = Pango.FontDescription.from_string(self.FONT)

        # Measure on a scratch surface first.
        scratch = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))
        layouts = []
        for _kind, text in items:
            layout = PangoCairo.create_layout(scratch)
            layout.set_font_description(font)
            layout.set_text(text, -1)
            layouts.append((layout, *layout.get_pixel_size()))
        hint = PangoCairo.create_layout(scratch)
        hint.set_font_description(font)
        hint.set_text("↓", -1)
        hint_w, hint_h = hint.get_pixel_size()

        text_h = max([h for _l, _w, h in layouts] + [hint_h])
        chip_h = text_h + 2 * self.CHIP_PAD_Y
        width = self.PAD
        self.chips = []
        for _layout, w, _h in layouts:
            self.chips.append((width, width + w + 2 * self.CHIP_PAD_X))
            width += w + 2 * self.CHIP_PAD_X + self.GAP
        if selected is None:
            width += hint_w + self.CHIP_PAD_X
        width += self.PAD - self.GAP
        height = chip_h + 2 * self.PAD

        buffer, data, stride = self._buffer(width * scale, height * scale)
        image = cairo.ImageSurface.create_for_data(data, cairo.FORMAT_ARGB32, width * scale, height * scale, stride)
        cr = cairo.Context(image)
        cr.scale(scale, scale)
        p = self.palette

        def rounded(cr, x, y, w, h, r):
            cr.new_sub_path()
            cr.arc(x + w - r, y + r, r, -1.5708, 0)
            cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
            cr.arc(x + r, y + h - r, r, 1.5708, 3.1416)
            cr.arc(x + r, y + r, r, 3.1416, 4.7124)
            cr.close_path()

        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)
        rounded(cr, 0.5, 0.5, width - 1, height - 1, self.RADIUS + 2)
        cr.set_source_rgba(*rgb(p["mSurface"], 0.97))
        cr.fill_preserve()
        cr.set_source_rgba(*rgb(p["mOutline"], 0.8))
        cr.set_line_width(1)
        cr.stroke()

        for i, ((layout, w, h), (x0, x1)) in enumerate(zip(layouts, self.chips)):
            kind = items[i][0]
            if i == selected:
                rounded(cr, x0, self.PAD, x1 - x0, chip_h, self.RADIUS)
                cr.set_source_rgba(*rgb(p["mPrimary"]))
                cr.fill()
                colour = p["mOnPrimary"]
            elif kind == "emoji":
                colour = p["mOnSurface"]
            else:
                colour = p["mPrimary"] if (selected is None and i == 0) else p["mOnSurface"]
            cr.set_source_rgba(*rgb(colour))
            cr.move_to(x0 + self.CHIP_PAD_X, self.PAD + (chip_h - h) / 2)
            PangoCairo.show_layout(cr, layout)
        if selected is None:
            cr.set_source_rgba(*rgb(p["mOnSurfaceVariant"], 0.8))
            cr.move_to(width - self.PAD - hint_w - self.CHIP_PAD_X / 2, self.PAD + (chip_h - hint_h) / 2)
            PangoCairo.show_layout(cr, hint)
        image.flush()

        self.surface.set_buffer_scale(scale)
        self.surface.attach(buffer, 0, 0)
        self.surface.damage_buffer(0, 0, width * scale, height * scale)
        self.surface.commit()
        self.visible = True

    def hide(self):
        if self.visible:
            self.surface.attach(None, 0, 0)
            self.surface.commit()
            self.visible = False
            self.chips = []

    def hit(self, x: float) -> int | None:
        for i, (x0, x1) in enumerate(self.chips):
            if x0 <= x < x1:
                return i
        return None


class InputMethod:
    def __init__(self, words, emojis):
        from pywayland.client import Display

        self.wl, self.imp, self.vkp = load_protocols()
        self.words, self.emojis = words, emojis
        self.display = Display()
        self.display.connect()
        self.compositor = self.shm = self.seat = self.im_manager = self.vk_manager = None
        self.output_scales = {}
        registry = self.display.get_registry()
        registry.dispatcher["global"] = self._global
        self.display.roundtrip()
        self.display.roundtrip()  # wl_output scale / seat capabilities

        missing = [n for n, v in (("wl_compositor", self.compositor), ("wl_shm", self.shm), ("wl_seat", self.seat),
                                  ("zwp_input_method_manager_v2", self.im_manager),
                                  ("zwp_virtual_keyboard_manager_v1", self.vk_manager)) if v is None]
        if missing:
            say(error="This compositor does not offer " + ", ".join(missing) + " — text prediction needs a Wayland input method.")
            sys.exit(1)

        self.im = self.im_manager.get_input_method(self.seat)
        self.vk = self.vk_manager.create_virtual_keyboard(self.seat)
        self.xkb = Xkb()
        self.keymap_sent = False
        self.grab = None
        self.serial = 0

        # Pending state (applied on `done`) and current state.
        self.pending_active = False
        self.pending_surrounding = None
        self.active = False
        self.surrounding_known = False
        self.before_cursor = ""
        self.typed = ""                 # fallback for apps without surrounding text
        self.items = []
        self.selected = None            # None = popup shown but not entered
        self.dismissed_prefix = None    # Esc hides the popup until the word changes
        self.consumed = set()           # keys whose press we kept from the app

        for event in ("activate", "deactivate", "surrounding_text", "done", "unavailable"):
            self.im.dispatcher[event] = getattr(self, f"_im_{event}")
        self.im.dispatcher["text_change_cause"] = lambda *_: None
        self.im.dispatcher["content_type"] = lambda *_: None

        self.popup = Popup(self)
        self.popup.popup.dispatcher["text_input_rectangle"] = lambda *_: None

        self.pointer = None
        self.pointer_x = None
        self.display.roundtrip()

    @property
    def scale(self) -> int:
        return max(self.output_scales.values(), default=1)

    # ── registry ──
    def _global(self, registry, name, interface, version):
        wl = self.wl
        if interface == "wl_compositor":
            self.compositor = registry.bind(name, wl.WlCompositor, min(version, 4))
        elif interface == "wl_shm":
            self.shm = registry.bind(name, wl.WlShm, 1)
        elif interface == "wl_seat" and self.seat is None:
            self.seat = registry.bind(name, wl.WlSeat, min(version, 5))
            self.seat.dispatcher["capabilities"] = self._seat_capabilities
            self.seat.dispatcher["name"] = lambda *_: None
        elif interface == "wl_output":
            output = registry.bind(name, wl.WlOutput, min(version, 2))
            self.output_scales[name] = 1

            def scale(_output, factor, key=name):
                self.output_scales[key] = factor

            output.dispatcher["scale"] = scale
            for event in ("geometry", "mode", "done"):
                output.dispatcher[event] = lambda *_: None
        elif interface == "zwp_input_method_manager_v2":
            self.im_manager = registry.bind(name, self.imp.ZwpInputMethodManagerV2, 1)
        elif interface == "zwp_virtual_keyboard_manager_v1":
            self.vk_manager = registry.bind(name, self.vkp.ZwpVirtualKeyboardManagerV1, 1)

    def _seat_capabilities(self, seat, caps):
        has_pointer = bool(caps & self.wl.WlSeat.capability.pointer.value)
        if has_pointer and self.pointer is None:
            self.pointer = seat.get_pointer()
            self.pointer.dispatcher["enter"] = self._pointer_enter
            self.pointer.dispatcher["leave"] = lambda *_: setattr(self, "pointer_x", None)
            self.pointer.dispatcher["motion"] = lambda _p, _t, x, _y: setattr(self, "pointer_x", x) if self.pointer_x is not None else None
            self.pointer.dispatcher["button"] = self._pointer_button
            for event in ("axis", "frame", "axis_source", "axis_stop", "axis_discrete"):
                self.pointer.dispatcher[event] = lambda *_: None

    # ── pointer: click a suggestion ──
    def _pointer_enter(self, _pointer, _serial, surface, x, _y):
        self.pointer_x = x if surface == self.popup.surface else None

    def _pointer_button(self, _pointer, _serial, _time, _button, state):
        if state == 1 and self.pointer_x is not None and self.popup.visible:
            index = self.popup.hit(self.pointer_x)
            if index is not None:
                self.accept(index)

    # ── input method state ──
    def _im_activate(self, _im):
        self.pending_active = True
        self.pending_surrounding = None

    def _im_deactivate(self, _im):
        self.pending_active = False

    def _im_surrounding_text(self, _im, text, cursor, _anchor):
        self.pending_surrounding = (text, cursor)

    def _im_unavailable(self, _im):
        say(error="Another input method (fcitx, ibus…) is already running; stop it to use Stoa text prediction.")
        quit_now(1)

    def _im_done(self, _im):
        self.serial += 1
        debug(f"done #{self.serial}: active={self.pending_active} surrounding={self.pending_surrounding!r}")
        was_active = self.active
        self.active = self.pending_active
        if self.active and not was_active:
            self.surrounding_known = False
            self.before_cursor = ""
            self.typed = ""
            self.dismissed_prefix = None
            self._grab_keyboard()
        elif was_active and not self.active:
            self._release_keyboard()
            self.selected = None
            self.popup.hide()
            return
        if self.pending_surrounding is not None:
            text, cursor = self.pending_surrounding
            self.pending_surrounding = None
            self.surrounding_known = True
            self.before_cursor = text.encode("utf-8")[:cursor].decode("utf-8", "ignore")
        self.refresh()

    # ── keyboard grab ──
    def _grab_keyboard(self):
        if self.grab is not None:
            return
        self.grab = self.im.grab_keyboard()
        self.grab.dispatcher["keymap"] = self._grab_keymap
        self.grab.dispatcher["key"] = self._grab_key
        self.grab.dispatcher["modifiers"] = self._grab_modifiers
        self.grab.dispatcher["repeat_info"] = lambda *_: None

    def _release_keyboard(self):
        if self.grab is not None:
            self.grab.release()
            self.grab = None
        self.consumed.clear()

    def _grab_keymap(self, _grab, fmt, fd, size):
        try:
            with mmap.mmap(fd, size, prot=mmap.PROT_READ) as data:
                self.xkb.set_keymap(data[:].rstrip(b"\0"))
            self.vk.keymap(fmt, fd, size)
            self.keymap_sent = True
        finally:
            os.close(fd)

    def _grab_modifiers(self, _grab, _serial, depressed, latched, locked, group):
        self.xkb.update(depressed, latched, locked, group)
        if self.keymap_sent:
            self.vk.modifiers(depressed, latched, locked, group)

    def _forward(self, time_ms, key, state):
        if self.keymap_sent:
            self.vk.key(time_ms, key, state)

    def _grab_key(self, _grab, _serial, time_ms, key, state):
        debug(f"key {key} {'down' if state else 'up'} sym={self.xkb.keysym(key):#x}")
        if state == KEY_RELEASED:
            if key in self.consumed:
                self.consumed.discard(key)
            else:
                self._forward(time_ms, key, state)
            return

        sym = self.xkb.keysym(key)
        if self.popup.visible and self.navigate(sym):
            self.consumed.add(key)
            return
        self._forward(time_ms, key, state)

        # Follow the word ourselves for apps that send no surrounding text.
        if sym == XK_BACKSPACE:
            self.typed = self.typed[:-1]
        else:
            text = self.xkb.text(key)
            if text and WORD_BEFORE_CURSOR.fullmatch(text):
                self.typed += text
            elif text or sym in XK_WORD_BREAKERS:
                self.typed = ""
        if not self.surrounding_known:
            self.refresh()

    # ── suggestions ──
    def prefix(self) -> str:
        if self.surrounding_known:
            match = WORD_BEFORE_CURSOR.search(self.before_cursor)
            return match.group(0) if match else ""
        return self.typed

    def refresh(self):
        prefix = self.prefix()
        debug(f"prefix={prefix!r}")
        if self.dismissed_prefix is not None and prefix != self.dismissed_prefix:
            self.dismissed_prefix = None
        items = []
        if len(prefix) >= MIN_PREFIX and self.dismissed_prefix is None:
            items = [("word", match_case(w, prefix)) for w in self.words.search(prefix)]
            items += [("emoji", e["emoji"]) for e in self.emojis.search(prefix, MAX_EMOJIS)]
        if items != self.items:
            self.items = items
            self.selected = None
        if self.items:
            self.popup.show(self.items, self.selected)
        else:
            self.popup.hide()

    def navigate(self, sym) -> bool:
        """Arrow-key handling while the popup is up. True = key consumed."""
        if self.selected is None:
            if sym in (XK_DOWN, XK_UP):
                self.selected = 0
                self.popup.show(self.items, self.selected)
                return True
            if sym == XK_ESCAPE:           # let the app see Esc too (vim…)
                self.dismiss()
            return False
        if sym in (XK_LEFT, XK_RIGHT):
            step = -1 if sym == XK_LEFT else 1
            self.selected = (self.selected + step) % len(self.items)
            self.popup.show(self.items, self.selected)
            return True
        if sym in (XK_DOWN, XK_UP):
            self.selected = None
            self.popup.show(self.items, self.selected)
            return True
        if sym in (XK_RETURN, XK_KP_ENTER, XK_TAB):
            self.accept(self.selected)
            return True
        if sym == XK_ESCAPE:
            self.dismiss()
            return True
        # Any other key leaves the popup and reaches the app.
        self.selected = None
        self.popup.show(self.items, self.selected)
        return False

    def dismiss(self):
        self.dismissed_prefix = self.prefix()
        self.selected = None
        self.items = []
        self.popup.hide()

    def accept(self, index: int):
        kind, text = self.items[index]
        prefix = self.prefix()
        # Both kinds replace the typed prefix: "ke" + 🔑 gives "🔑", not "ke🔑".
        if self.surrounding_known:
            self.im.delete_surrounding_text(len(prefix.encode("utf-8")), 0)
        else:
            # Terminals and other apps without surrounding text: erase
            # the typed prefix with real BackSpaces first.
            now = int(time.monotonic() * 1000) & 0xFFFFFFFF
            backspace = self.xkb.key_for(XK_BACKSPACE, KEY_BACKSPACE)
            for _ in prefix:
                self._forward(now, backspace, KEY_PRESSED)
                self._forward(now, backspace, KEY_RELEASED)
        # A word ends with a space so typing goes on; an emoji does not.
        self.im.commit_string(text + " " if kind == "word" else text)
        self.im.commit(self.serial)
        self.typed = ""
        self.before_cursor = ""
        self.selected = None
        self.items = []
        self.popup.hide()

    def run(self):
        # The pidfile is written only once the compositor has handed us the
        # input method (an `unavailable` would have arrived during the
        # roundtrips in __init__), so it always names the instance holding it.
        Path(PIDFILE).write_text(str(os.getpid()))
        say(ready=True)
        while self.display.dispatch(block=True) != -1:
            pass


def main():
    try:
        import cairo  # noqa: F401
        import gi
        gi.require_version("Pango", "1.0")
        gi.require_version("PangoCairo", "1.0")
        import pywayland  # noqa: F401
    except (ImportError, ValueError) as err:
        say(error=f"Missing dependency ({err}): sudo pacman -S python-pywayland python-cairo python-gobject pango")
        sys.exit(1)
    if not os.environ.get("WAYLAND_DISPLAY"):
        say(error="No Wayland session (WAYLAND_DISPLAY is unset).")
        sys.exit(1)

    try:
        ime = InputMethod(WordDictionary(), EmojiIndex())
        ime.run()
    finally:
        remove_pidfile()


if __name__ == "__main__":
    # Default (kernel) action for SIGTERM/SIGINT, deliberately. While idle
    # the daemon sits inside libwayland's poll(), which restarts on EINTR,
    # so a Python-level handler would not run until the next Wayland event:
    # `stoa-predict kill` would wait in vain and the next start would be
    # refused as "unavailable". Nothing needs cleaning up on the way out —
    # the compositor drops the grab and the popup when the connection
    # closes, and `stoa-predict kill` removes the pidfile.
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    main()
