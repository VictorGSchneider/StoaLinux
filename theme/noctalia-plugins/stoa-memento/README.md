# Stoa Memento Mori

A Noctalia desktop widget showing days / weeks / years lived against a
configurable life expectancy, with a rotating Stoic quote. Lives on the
desktop, on top of the wallpaper and below windows.

> *"Remember that you will die."* — Stoic tradition

## Configuration

The widget is UI-only. All inputs come from `~/.config/stoa/memento.conf`:

```
NAME=Your Full Name
BIRTH=YYYY-MM-DD
LIFE_YEARS=80
```

The file is created with defaults the first time `stoa-memento-data` runs.
Edit it in place — the widget picks up changes on the next 60 s tick.

## Data flow

```
~/.config/stoa/memento.conf
            │
            ▼
       stoa-memento-data         ◄── polled every 60 s
            │  (JSON: days, weeks, years, year_pct, quote, ...)
            ▼
       DesktopWidget.qml
```

The Stoic quote pool is the same one that feeds `stoa-quotes-sync` and
the shell greeting, so the widget never repeats the line you just saw in
your terminal.

## Install

StoaLinux's `install.sh` symlinks this directory to
`~/.config/noctalia/plugins/stoa-memento/`. Enable it via
Noctalia Settings → Plugins, or by flipping `enabled: true` in
`~/.config/noctalia/plugins.json`.

## Source

Part of [StoaLinux](https://github.com/VictorGSchneider/StoaLinux).
