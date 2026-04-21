# Vendored upstream sources

This directory holds upstream projects that Stoa Linux forks from, imported
as **git subtrees**. A subtree keeps the upstream history grafted into this
repository, so contributors who clone StoaLinux get everything in one
`git clone` — no submodule init step — but we can still pull new upstream
commits with a single command and resolve conflicts only where Stoa has
diverged.

## Currently vendored

| Prefix                     | Upstream                                         | Branch | Stoa fork        |
|----------------------------|--------------------------------------------------|--------|------------------|
| `scripts/vendor/brcs`      | https://github.com/VictorGSchneider/BRCS.sh      | `main` | `scripts/stoa-maintain.sh` |
| `scripts/vendor/dfm`       | https://github.com/VictorGSchneider/DFM          | `main` | `scripts/stoa-dfm/`        |

## Initial import (one-time, per subtree)

The clone cannot reach arbitrary GitHub repos from inside CI, so the first
import has to be run on a workstation that can `git fetch` from the upstream.

```bash
# Ensure a clean working tree first.
git subtree add \
    --prefix=scripts/vendor/brcs \
    https://github.com/VictorGSchneider/BRCS.sh.git \
    main --squash

git subtree add \
    --prefix=scripts/vendor/dfm \
    https://github.com/VictorGSchneider/DFM.git \
    main --squash
```

`--squash` collapses the upstream's history into a single commit on our
`main`, which keeps `git log` readable. Drop it only if you genuinely want
the full upstream history visible in StoaLinux's log.

## Pulling upstream updates

Use the helper — it runs the right `git subtree pull` and reminds you what
to do about conflicts:

```bash
./scripts/vendor/sync-upstream.sh brcs
./scripts/vendor/sync-upstream.sh dfm
```

Equivalent raw commands:

```bash
git subtree pull \
    --prefix=scripts/vendor/brcs \
    https://github.com/VictorGSchneider/BRCS.sh.git \
    main --squash

git subtree pull \
    --prefix=scripts/vendor/dfm \
    https://github.com/VictorGSchneider/DFM.git \
    main --squash
```

## Relationship to Stoa sources

### `scripts/vendor/brcs` ↔ `scripts/stoa-maintain.sh`

`stoa-maintain.sh` is our customized fork of `BRCS.sh` — it carries the
Stoa color palette, different CLI banners, and integrates with the rest of
the Stoa scripts. It is **not** a symlink to the vendored copy. The
vendored `scripts/vendor/brcs/BRCS.sh` is our reference of the upstream,
used to:

1. Diff against when you want to know what changed upstream:
   `diff -u scripts/vendor/brcs/BRCS.sh scripts/stoa-maintain.sh`.
2. Cherry-pick bug-fix hunks into `stoa-maintain.sh` after a sync.

When you run `sync-upstream.sh brcs`, the vendored copy is updated; the
fork is **not** touched automatically. The helper will print a diff
summary and tell you whether there are hunks you probably want to
forward-port.

### `scripts/vendor/dfm` ↔ `scripts/stoa-dfm/`

`scripts/stoa-dfm/` is our customized fork of the DFM Python package —
the place where Stoa-specific tweaks live (color palette, CLI banners,
default paths, integration with the rest of the Stoa scripts). It is
**not** a symlink to the vendored copy. The vendored
`scripts/vendor/dfm/` is our reference snapshot of the upstream Python
package, used to:

1. Diff against when you want to know what changed upstream:
   `diff -urN scripts/vendor/dfm scripts/stoa-dfm`.
2. Cherry-pick bug-fix hunks into `scripts/stoa-dfm/` after a sync.

Unlike the brcs fork (a single file), the DFM fork is a directory that
mirrors the `dfm/` package layout plus `setup.py` and `requirements.txt`
so the fork is directly installable (`pip install ./scripts/stoa-dfm`).
Upstream-only files like `LICENSE`, `README.md`, and `screenshots/` are
not duplicated into the fork — Stoa ships its own.

When you run `sync-upstream.sh dfm`, the vendored copy is updated; the
fork is **not** touched automatically. The helper will walk every entry
in `scripts/stoa-dfm/`, diff it against the matching path under
`scripts/vendor/dfm/`, and print a diffstat summary so you can
forward-port bug fixes deliberately.
