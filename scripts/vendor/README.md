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
| `scripts/vendor/dfm`       | https://github.com/VictorGSchneider/DFM          | `main` | — (reference only) |

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

### `scripts/vendor/dfm` ↔ (reference only)

DFM is a Python/GTK4 application rather than a single-file shell script,
so there is no one-to-one “Stoa fork” counterpart inside this repo — the
vendor is a reference snapshot of the upstream Python package. Use it to:

1. Diff against when checking what changed upstream:
   `diff -u -r scripts/vendor/dfm/dfm /path/to/local/dfm`.
2. Cherry-pick fixes into any Stoa scripts that interact with DFM data
   (backups, themes, config paths) after a sync.

Because there is no direct fork file, `sync-upstream.sh dfm` skips the
diff summary step and just updates the vendored snapshot.
