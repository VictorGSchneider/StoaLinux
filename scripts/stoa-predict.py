#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Text Prediction Daemon                        ║
# ║  "Choose your words with care." — Epictetus                 ║
# ║                                                              ║
# ║  System-wide word suggestions via evdev + eww.               ║
# ║  Requires: python-evdev, eww, wtype                          ║
# ║  User must be in the 'input' group.                          ║
# ╚══════════════════════════════════════════════════════════════╝

import asyncio
import json
import os
import signal
import subprocess
import sys
from bisect import bisect_left
from pathlib import Path

import evdev
from evdev import ecodes

# ── Configuration ──
MAX_SUGGESTIONS = 5
MIN_PREFIX = 2
DICT_PATHS = [
    Path.home() / ".config/stoa/predict-words.txt",
    Path("/usr/share/dict/words"),
    Path("/usr/share/dict/american-english"),
]
_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
PIDFILE = f"{_RUNTIME_DIR}/stoa-predict.pid"
SUGGEST_FILE = f"{_RUNTIME_DIR}/stoa-predict.json"

# ── Keycode to character mapping (US/BR base — lowercase) ──
KEY_MAP = {
    ecodes.KEY_A: "a", ecodes.KEY_B: "b", ecodes.KEY_C: "c",
    ecodes.KEY_D: "d", ecodes.KEY_E: "e", ecodes.KEY_F: "f",
    ecodes.KEY_G: "g", ecodes.KEY_H: "h", ecodes.KEY_I: "i",
    ecodes.KEY_J: "j", ecodes.KEY_K: "k", ecodes.KEY_L: "l",
    ecodes.KEY_M: "m", ecodes.KEY_N: "n", ecodes.KEY_O: "o",
    ecodes.KEY_P: "p", ecodes.KEY_Q: "q", ecodes.KEY_R: "r",
    ecodes.KEY_S: "s", ecodes.KEY_T: "t", ecodes.KEY_U: "u",
    ecodes.KEY_V: "v", ecodes.KEY_W: "w", ecodes.KEY_X: "x",
    ecodes.KEY_Y: "y", ecodes.KEY_Z: "z",
}

# Keys that reset the word buffer
RESET_KEYS = {
    ecodes.KEY_SPACE, ecodes.KEY_ENTER, ecodes.KEY_TAB,
    ecodes.KEY_ESC, ecodes.KEY_DOT, ecodes.KEY_COMMA,
    ecodes.KEY_SEMICOLON, ecodes.KEY_APOSTROPHE,
    ecodes.KEY_SLASH, ecodes.KEY_MINUS, ecodes.KEY_EQUAL,
    ecodes.KEY_LEFTBRACE, ecodes.KEY_RIGHTBRACE,
    ecodes.KEY_GRAVE, ecodes.KEY_BACKSLASH,
    ecodes.KEY_HOME, ecodes.KEY_END,
    ecodes.KEY_LEFT, ecodes.KEY_RIGHT, ecodes.KEY_UP, ecodes.KEY_DOWN,
}

# Modifier keys to ignore
MODIFIER_KEYS = {
    ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT,
    ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL,
    ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT,
    ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA,
    ecodes.KEY_CAPSLOCK, ecodes.KEY_NUMLOCK,
}


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
                print(f"[predict] Loaded {len(self.keyword_map)} emoji keywords")
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
        print(f"[predict] Loaded {len(self.keyword_map)} built-in emoji keywords")

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
    """Sorted word list with fast prefix search via bisect."""

    def __init__(self):
        self.words = []
        self._load()

    def _load(self):
        """Load word list from first available source."""
        for path in DICT_PATHS:
            if path.exists():
                try:
                    raw = path.read_text(encoding="utf-8", errors="ignore")
                    # Filter to lowercase words, 2+ chars, no possessives
                    self.words = sorted({
                        w.lower()
                        for line in raw.splitlines()
                        for w in [line.strip()]
                        if w and w.isalpha() and len(w) >= 2 and "'" not in w
                    })
                    print(f"[predict] Loaded {len(self.words)} words from {path}")
                    return
                except Exception as e:
                    print(f"[predict] Error loading {path}: {e}")

        # Fallback: generate from aspell
        try:
            result = subprocess.run(
                ["aspell", "-d", "en", "dump", "master"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                self.words = sorted({
                    w.lower()
                    for line in result.stdout.splitlines()
                    for w in [line.strip()]
                    if w and w.isalpha() and len(w) >= 2
                })
                print(f"[predict] Loaded {len(self.words)} words from aspell")
                return
        except Exception:
            pass

        print("[predict] WARNING: No word list found. Install 'words' package.")
        self.words = []

    def search(self, prefix: str, limit: int = MAX_SUGGESTIONS) -> list[str]:
        """Return up to `limit` words starting with `prefix`."""
        if not prefix or len(prefix) < MIN_PREFIX or not self.words:
            return []

        prefix = prefix.lower()
        idx = bisect_left(self.words, prefix)
        results = []
        while idx < len(self.words) and len(results) < limit:
            word = self.words[idx]
            if word.startswith(prefix):
                # Don't suggest the exact typed prefix
                if word != prefix:
                    results.append(word)
            else:
                break
            idx += 1
        return results


class PredictDaemon:
    """Main daemon: reads evdev input, emits suggestions to eww."""

    def __init__(self):
        self.dictionary = WordDictionary()
        self.emoji_index = EmojiIndex()
        self.buffer = ""
        self.last_suggestions: list[str] = []
        self.ctrl_held = False
        self.alt_held = False
        self.meta_held = False

    def find_keyboards(self) -> list[evdev.InputDevice]:
        """Find all keyboard input devices."""
        keyboards = []
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
                caps = dev.capabilities(verbose=False)
                if ecodes.EV_KEY in caps:
                    key_caps = caps[ecodes.EV_KEY]
                    # Must have letter keys to be a keyboard
                    if ecodes.KEY_A in key_caps and ecodes.KEY_Z in key_caps:
                        keyboards.append(dev)
                        print(f"[predict] Found keyboard: {dev.name} ({dev.path})")
            except Exception:
                continue

        if not keyboards:
            print("[predict] ERROR: No keyboard devices found.")
            print("[predict] Make sure you are in the 'input' group:")
            print("[predict]   sudo usermod -aG input $USER")
            print("[predict]   (then log out and back in)")
        return keyboards

    def update_eww(self, suggestions: list[str]):
        """Send suggestion data to eww."""
        if suggestions == self.last_suggestions:
            return
        self.last_suggestions = suggestions

        # Get related emojis for the current buffer
        emojis = self.emoji_index.search(self.buffer) if self.buffer else []

        data = json.dumps({
            "prefix": self.buffer,
            "words": suggestions,
            "emojis": emojis,
            "visible": len(suggestions) > 0 or len(emojis) > 0,
        })

        # Write to file for eww defpoll fallback
        try:
            with open(SUGGEST_FILE, "w") as f:
                f.write(data)
        except Exception:
            pass

        # Update eww variable directly
        try:
            subprocess.Popen(
                ["eww", "update", f"predict-data={data}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass

    def process_key(self, keycode: int, key_state: int):
        """Process a single key event."""
        # Only handle key-down events
        if key_state != 1:
            # Track modifier releases
            if key_state == 0:
                if keycode in (ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL):
                    self.ctrl_held = False
                elif keycode in (ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT):
                    self.alt_held = False
                elif keycode in (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA):
                    self.meta_held = False
            return

        # Track modifiers
        if keycode in (ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL):
            self.ctrl_held = True
            return
        if keycode in (ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT):
            self.alt_held = True
            return
        if keycode in (ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA):
            self.meta_held = True
            return

        # Ignore keystrokes with modifiers (shortcuts, not typing)
        if self.ctrl_held or self.alt_held or self.meta_held:
            # Ctrl+A, Ctrl+C, etc. — reset buffer
            self.buffer = ""
            self.update_eww([])
            return

        # Skip other modifier keys
        if keycode in MODIFIER_KEYS:
            return

        # Backspace: remove last char
        if keycode == ecodes.KEY_BACKSPACE:
            if self.buffer:
                self.buffer = self.buffer[:-1]
                if len(self.buffer) >= MIN_PREFIX:
                    suggestions = self.dictionary.search(self.buffer)
                    self.update_eww(suggestions)
                else:
                    self.update_eww([])
            return

        # Reset keys (space, enter, punctuation, arrows)
        if keycode in RESET_KEYS:
            self.buffer = ""
            self.update_eww([])
            return

        # Letter keys
        char = KEY_MAP.get(keycode)
        if char:
            self.buffer += char
            if len(self.buffer) >= MIN_PREFIX:
                suggestions = self.dictionary.search(self.buffer)
                self.update_eww(suggestions)
            else:
                self.update_eww([])
            return

        # Number keys or unknown — reset
        if ecodes.KEY_1 <= keycode <= ecodes.KEY_0:
            self.buffer = ""
            self.update_eww([])

    async def listen_device(self, device: evdev.InputDevice):
        """Async listener for a single keyboard device."""
        try:
            async for event in device.async_read_loop():
                if event.type == ecodes.EV_KEY:
                    self.process_key(event.code, event.value)
        except Exception as e:
            print(f"[predict] Device {device.name} disconnected: {e}")

    async def run(self):
        """Start listening on all keyboards."""
        keyboards = self.find_keyboards()
        if not keyboards:
            sys.exit(1)

        # Write PID file
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))

        print(f"[predict] Daemon started (PID {os.getpid()})")

        # Open eww predict window
        try:
            subprocess.Popen(
                ["eww", "open", "predict"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass

        # Initialize with empty state
        self.update_eww([])

        # Listen on all keyboards concurrently
        tasks = [self.listen_device(kb) for kb in keyboards]
        await asyncio.gather(*tasks)


def cleanup(_sig=None, _frame=None):
    """Clean up on exit."""
    try:
        os.remove(PIDFILE)
    except FileNotFoundError:
        pass
    try:
        subprocess.run(
            ["eww", "close", "predict"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
    except Exception:
        pass
    try:
        os.remove(SUGGEST_FILE)
    except FileNotFoundError:
        pass
    sys.exit(0)


def main():
    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    daemon = PredictDaemon()
    try:
        asyncio.run(daemon.run())
    except KeyboardInterrupt:
        cleanup()


if __name__ == "__main__":
    main()
