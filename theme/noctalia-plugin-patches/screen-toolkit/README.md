# screen-toolkit: screenshot delay patch

Local patch over the upstream Noctalia
[`screen-toolkit`](https://github.com/noctalia-dev/noctalia-plugins/tree/main/screen-toolkit)
plugin. It adds a new integer setting `screenshotDelaySec` (0-60).
Whenever it's > 0, the three annotate flows (fullscreen / region /
active-window) wait that many seconds before invoking `grim` — so you
have time to arrange your screen.

Annotate is the only flow touched; OCR / QR / palette / color picker
keep their current zero-delay behaviour because the selection itself
is the composition there.

## Why it lives here

Plugins installed through the Noctalia plugin manager
(`~/.config/noctalia/plugins/<name>/`) are auto-updated via `git pull`
(see `"plugins.autoUpdate": true` in `~/.config/noctalia/settings.json`).
Editing the installed copy in place works, but every autoUpdate
overwrites it. Keeping the patch versioned here means:

- one `apply.sh` re-applies it after each autoUpdate;
- the upstream-contribution materials sit next to the patch, so when
  the change merges upstream we can delete this whole directory in one
  go.

## Re-apply (post-autoUpdate)

```sh
~/StoaLinux/theme/noctalia-plugin-patches/screen-toolkit/apply.sh
killall quickshell && ~/.local/bin/stoa-bar &
```

`apply.sh` is idempotent: running it on an already-patched tree
returns success and changes nothing. If upstream drifted and the patch
no longer applies cleanly, it exits with status 2 and leaves the tree
untouched.

## Upstream contribution

The same patch is what should be sent to
[`noctalia-dev/noctalia-plugins`](https://github.com/noctalia-dev/noctalia-plugins).
Draft commit message and PR body sit under `upstream-pr/`. Steps:

1. Fork `noctalia-dev/noctalia-plugins`.
2. `git apply` the patch in `screen-toolkit/` of the fork.
3. Use `upstream-pr/COMMIT_MSG.txt` as the commit message.
4. Open a PR with `upstream-pr/PR_BODY.md` as the body.

When the PR merges and Noctalia's plugin autoUpdate pulls it in, this
whole directory becomes obsolete — delete it.

## Files

| file | purpose |
|---|---|
| `0001-screenshot-delay.patch` | unified diff over `Main.qml`, `Settings.qml`, `i18n/en.json` |
| `apply.sh` | idempotent re-apply script |
| `upstream-pr/COMMIT_MSG.txt` | commit message template |
| `upstream-pr/PR_BODY.md` | PR body template |
