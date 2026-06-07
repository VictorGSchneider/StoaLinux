## Summary

Adds a configurable **screenshot delay** to the screen-toolkit
plugin's annotate flows (region, fullscreen, active-window). The
plugin already has purpose-built launch timers between "user clicks"
and "grim fires" (50 ms / 360 ms / 380 ms) to let the UI settle —
this PR just lets the user extend that wait so they can arrange the
screen.

## Changes

- `Settings.qml`: new `screenshotDelaySec` property, loaded and saved
  through `pluginSettings.screenshotDelaySec`. A small "Screenshot"
  section above "Share" exposes a 0–60 s integer input.
- `Main.qml`: new `_screenshotDelayMs` readonly property derived from
  the setting; added to the existing `launchAnnotate`,
  `launchAnnotateActiveWindow` and `launchAnnotateFullscreen` Timer
  intervals.
- `i18n/en.json`: `settings.screenshotDelay` and
  `settings.screenshotDelayDesc`.

Default `0` preserves current behaviour bit-for-bit — when the
setting is absent, `parseInt(undefined ?? 0) === 0` and the existing
50/360/380 ms intervals are unchanged.

## Why annotate flows only

The countdown UX makes sense when the user is composing a screenshot
("3, 2, 1, capture"). For OCR / QR / palette / color picker the
selection itself is the composition, and a delay would just feel like
lag — so this PR keeps those flows untouched. Same for recording,
which already has its own preroll.

## Test plan

- [ ] `screenshotDelaySec = 0`: fullscreen / region / active-window
      annotate fires immediately (current behaviour).
- [ ] `screenshotDelaySec = 3`: same three flows wait 3 s after panel
      close / region select / window detect before grim runs.
- [ ] Setting persists across Noctalia restarts (round-trips through
      `pluginSettings`).
- [ ] OCR, QR, palette, color picker, recording flows unaffected.
- [ ] i18n: setting label and description render in English; other
      locales fall back to English until translations are added.

## Follow-ups (not in this PR)

- Visible countdown overlay during the wait. The intervals are short
  enough that text feedback is the obvious next step, but it's a
  meaningful UI change so I'd rather land the data path first and
  iterate.
- Per-flow delays. Could be useful if users want a longer delay for
  fullscreen than for region.
