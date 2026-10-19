"""Stoa snapshot browser — GTK4/libadwaita front end over core.py.

Left: every package snapshot and config backup, newest first, each with a
one-line summary of what it holds. Right: what is inside the selected one,
in terms of the system as it is now:

* package snapshot → which packages were upgraded / downgraded / installed
  / removed, either since this snapshot or between the previous one and
  this; plus the full list, searchable.
* config backup → every file it holds, marked same / changed / gone
  compared with the file on disk today; open one to see the diff or the
  saved copy, and restore just that file.

Only uses API present in GTK 4.14 / libadwaita 1.5, so it runs on Arch and
on older stacks alike.
"""

from __future__ import annotations

import subprocess
import sys
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import core  # noqa: E402

APP_ID = "org.stoa.Snapshots"

CSS = """
@define-color stoa_bg_dark     #1a1714;
@define-color stoa_bg          #211e19;
@define-color stoa_bg_light    #2d2921;
@define-color stoa_fg          #d4cfc4;
@define-color stoa_fg_dim      #a89f91;
@define-color stoa_bronze      #c49a5c;
@define-color stoa_olive       #8a9a6c;
@define-color stoa_terracotta  #b36b5a;
@define-color stoa_azure       #5a7a8a;
@define-color stoa_stone       #6e6a62;

@define-color accent_bg_color      @stoa_bronze;
@define-color accent_fg_color      @stoa_bg_dark;
@define-color accent_color         @stoa_bronze;
@define-color window_bg_color      @stoa_bg;
@define-color window_fg_color      @stoa_fg;
@define-color view_bg_color        @stoa_bg_dark;
@define-color view_fg_color        @stoa_fg;
@define-color headerbar_bg_color   @stoa_bg_dark;
@define-color headerbar_fg_color   @stoa_fg;
@define-color sidebar_bg_color     @stoa_bg_dark;
@define-color sidebar_fg_color     @stoa_fg;
@define-color card_bg_color        @stoa_bg_light;
@define-color card_fg_color        @stoa_fg;
@define-color popover_bg_color     @stoa_bg_light;
@define-color dialog_bg_color      @stoa_bg;

.sidebar-section { font-weight: bold; font-size: 0.8em; letter-spacing: 1px;
                   color: @stoa_bronze; margin: 12px 12px 4px 12px; }
.snap-subtitle   { color: @stoa_fg_dim; font-size: 0.9em; }
.pill            { border-radius: 99px; padding: 1px 10px; font-size: 0.85em;
                   font-weight: bold; }
.pill.same       { background: alpha(@stoa_stone, 0.35);      color: @stoa_fg_dim; }
.pill.changed    { background: alpha(@stoa_bronze, 0.25);     color: @stoa_bronze; }
.pill.missing    { background: alpha(@stoa_terracotta, 0.25); color: @stoa_terracotta; }
.pill.unreadable { background: alpha(@stoa_azure, 0.25);      color: @stoa_azure; }
.pill.up         { background: alpha(@stoa_olive, 0.25);      color: @stoa_olive; }
.pill.down       { background: alpha(@stoa_terracotta, 0.25); color: @stoa_terracotta; }
.pill.add        { background: alpha(@stoa_azure, 0.25);      color: @stoa_azure; }
.pill.remove     { background: alpha(@stoa_stone, 0.45);      color: @stoa_fg; }
.big-title       { font-size: 1.5em; font-weight: bold; }
.code            { font-family: monospace; }
.hint            { color: @stoa_fg_dim; }
"""

STATUS_TEXT = {
    core.SAME: ("same", "same"),
    core.CHANGED: ("changed", "changed"),
    core.MISSING: ("gone", "missing"),
    core.UNREADABLE: ("needs root", "unreadable"),
}


# ── Small widget helpers ──────────────────────────────────────────────


def pill(text: str, kind: str) -> Gtk.Label:
    lbl = Gtk.Label(label=text, valign=Gtk.Align.CENTER)
    lbl.add_css_class("pill")
    lbl.add_css_class(kind)
    return lbl


def action_row(title: str, subtitle: str = "", suffix: Gtk.Widget | None = None) -> Adw.ActionRow:
    row = Adw.ActionRow(title=title, subtitle=subtitle)
    # Package names and paths are not markup ("libsigc++" would break it).
    row.set_use_markup(False)
    if suffix is not None:
        row.add_suffix(suffix)
    return row


def run_async(cmd: list[str], done) -> None:
    """Run a command off the UI thread; done(ok, output) back on it."""
    def work():
        try:
            r = subprocess.run(cmd, capture_output=True, text=True)
            ok, out = r.returncode == 0, (r.stderr or r.stdout).strip()
        except OSError as e:
            ok, out = False, str(e)
        GLib.idle_add(done, ok, out)
    threading.Thread(target=work, daemon=True).start()


def open_terminal(title: str, cmd: list[str]) -> None:
    """Interactive commands (restore with prompts) get a terminal that stays
    open until Enter, same as stoa-snapshot does."""
    term = GLib.getenv("TERMINAL") or "kitty"
    shell = " ".join(GLib.shell_quote(c) for c in cmd)
    subprocess.Popen([term, "--title", title, "-e", "bash", "-c",
                      f"{shell}; echo; read -rp 'Press Enter to close…' _"],
                     start_new_session=True)


def scrolled(child: Gtk.Widget) -> Gtk.ScrolledWindow:
    sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
    clamp = Adw.Clamp(maximum_size=900, tightening_threshold=600, child=child)
    sw.set_child(clamp)
    return sw


def page_box() -> Gtk.Box:
    return Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                   margin_top=18, margin_bottom=24, margin_start=18, margin_end=18)


def segmented(options: list[tuple[str, str]], active: str, on_change) -> Gtk.Box:
    """A linked row of toggle buttons; on_change(key) when one is picked.
    (Adw.ToggleGroup needs libadwaita 1.7.)"""
    box = Gtk.Box(css_classes=["linked"], halign=Gtk.Align.START)
    first = None
    buttons = {}
    for key, label in options:
        b = Gtk.ToggleButton(label=label)
        if first is None:
            first = b
        else:
            b.set_group(first)
        buttons[key] = b
        box.append(b)
    buttons[active].set_active(True)
    for key, b in buttons.items():
        b.connect("toggled", lambda btn, k=key: btn.get_active() and on_change(k))
    box.buttons = buttons
    return box


# ── Sidebar ───────────────────────────────────────────────────────────


class SnapRow(Gtk.ListBoxRow):
    def __init__(self, item, section: str, title: str, subtitle: str, badge: Gtk.Widget | None = None):
        super().__init__()
        self.item = item
        self.section = section
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                      margin_top=8, margin_bottom=8, margin_start=6, margin_end=6)
        top = Gtk.Box(spacing=6)
        t = Gtk.Label(label=title, xalign=0, hexpand=True, ellipsize=Pango.EllipsizeMode.END)
        top.append(t)
        if badge is not None:
            top.append(badge)
        box.append(top)
        s = Gtk.Label(label=subtitle, xalign=0, ellipsize=Pango.EllipsizeMode.END)
        s.add_css_class("snap-subtitle")
        box.append(s)
        self.set_child(box)


SECTION_TITLES = {"packages": "PACKAGES", "configs": "CONFIGS"}


def _section_header(row: SnapRow, before: SnapRow | None) -> None:
    if before is None or before.section != row.section:
        lbl = Gtk.Label(label=SECTION_TITLES[row.section], xalign=0)
        lbl.add_css_class("sidebar-section")
        row.set_header(lbl)
    else:
        row.set_header(None)


# ── Package snapshot view ─────────────────────────────────────────────


class PackageView(Gtk.Box):
    def __init__(self, window: "SnapshotWindow", snap: core.PkgSnapshot,
                 previous: core.PkgSnapshot | None, current: dict | None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.window, self.snap, self.previous, self.current = window, snap, previous, current
        self.query = ""
        self.mode = "now" if current is not None else "previous"

        box = page_box()

        # Summary
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        title = Gtk.Label(label=f"Packages · {core.when(snap.taken)}", xalign=0)
        title.add_css_class("big-title")
        head.append(title)
        facts = [f"{snap.total} packages"]
        if snap.explicit is not None:
            facts.append(f"{snap.explicit} explicitly installed")
        if snap.foreign is not None:
            facts.append(f"{snap.foreign} from the AUR")
        sub = Gtk.Label(label=" · ".join(facts), xalign=0)
        sub.add_css_class("hint")
        head.append(sub)
        hint = Gtk.Label(
            label="Taken just before a pacman transaction — the system as it was right then.",
            xalign=0, wrap=True)
        hint.add_css_class("hint")
        head.append(hint)
        box.append(head)

        # Compare against…
        options = []
        if current is not None:
            options.append(("now", "This snapshot → now"))
        if previous is not None:
            options.append(("previous", "Previous → this snapshot"))
        if options:
            if self.mode not in dict(options):
                self.mode = options[0][0]
            cmp_box = Gtk.Box(spacing=12)
            cmp_box.append(segmented(options, self.mode, self._set_mode))
            search = Gtk.SearchEntry(placeholder_text="Filter packages", hexpand=True)
            search.connect("search-changed", self._on_search)
            cmp_box.append(search)
            box.append(cmp_box)

        self.changes = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        box.append(self.changes)

        # Everything in the snapshot, searchable (a ListView: ~1500 rows).
        all_group = Adw.PreferencesGroup(
            title=f"Everything in this snapshot ({snap.total})",
            description="name and version, exactly as pacman -Q listed them")
        self.strings = Gtk.StringList.new([f"{n}  {v}" for n, v in sorted(snap.packages.items())])
        self.filter = Gtk.StringFilter(
            expression=Gtk.PropertyExpression.new(Gtk.StringObject, None, "string"),
            ignore_case=True, match_mode=Gtk.StringFilterMatchMode.SUBSTRING)
        model = Gtk.FilterListModel(model=self.strings, filter=self.filter)
        factory = Gtk.SignalListItemFactory()
        factory.connect("setup", lambda f, li: li.set_child(
            Gtk.Label(xalign=0, margin_start=12, margin_top=3, margin_bottom=3, css_classes=["code"])))
        factory.connect("bind", lambda f, li: li.get_child().set_label(li.get_item().get_string()))
        lv = Gtk.ListView(model=Gtk.NoSelection(model=model), factory=factory)
        lv.add_css_class("card")
        lsw = Gtk.ScrolledWindow(min_content_height=280, max_content_height=280, child=lv)
        all_group.add(lsw)
        box.append(all_group)

        self.append(scrolled(box))
        self._render_changes()

    def _set_mode(self, mode: str) -> None:
        self.mode = mode
        self._render_changes()

    def _on_search(self, entry: Gtk.SearchEntry) -> None:
        self.query = entry.get_text().strip().lower()
        self.filter.set_search(self.query)
        self._render_changes()

    def _render_changes(self) -> None:
        while (child := self.changes.get_first_child()) is not None:
            self.changes.remove(child)

        if self.mode == "now" and self.current is not None:
            diff = core.diff_packages(self.snap.packages, self.current)
            what = "Changed on this system since the snapshot"
        elif self.previous is not None:
            diff = core.diff_packages(self.previous.packages, self.snap.packages)
            what = f"Changed between {core.when(self.previous.taken)} and this snapshot"
        else:
            self.changes.append(Adw.StatusPage(
                icon_name="emblem-documents-symbolic", title="Oldest snapshot",
                description="Nothing earlier to compare with, and pacman is not available."))
            return

        q = self.query
        def keep(name): return not q or q in name.lower()

        sections = [
            ("Upgraded", "up", [(n, f"{a} → {b}") for n, a, b in diff.upgraded if keep(n)]),
            ("Downgraded", "down", [(n, f"{a} → {b}") for n, a, b in diff.downgraded if keep(n)]),
            ("Installed", "add", [(n, v) for n, v in diff.added if keep(n)]),
            ("Removed", "remove", [(n, v) for n, v in diff.removed if keep(n)]),
        ]
        header = Gtk.Label(label=f"{what}: {diff.short()}", xalign=0, wrap=True)
        header.add_css_class("heading")
        self.changes.append(header)

        if diff.empty:
            self.changes.append(Adw.StatusPage(
                icon_name="emblem-ok-symbolic", title="No package changes",
                description="Every package has the same version."))
            return
        shown = 0
        for title, kind, rows in sections:
            if not rows:
                continue
            group = Adw.PreferencesGroup(title=f"{title} ({len(rows)})")
            for name, detail in rows:
                group.add(action_row(name, detail, pill(title.lower(), kind)))
                shown += 1
            self.changes.append(group)
        if not shown:
            nothing = Gtk.Label(label="No changed package matches the filter.", xalign=0)
            nothing.add_css_class("hint")
            self.changes.append(nothing)


# ── Config backup view ────────────────────────────────────────────────


class ConfigView(Gtk.Stack):
    """Two pages: the file list, and one file's diff / saved copy."""

    def __init__(self, window: "SnapshotWindow", backup: core.ConfigBackup):
        super().__init__(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.window, self.backup = window, backup
        self.entries: list[core.BackupEntry] = []
        self.filter_mode = "all"
        self.query = ""

        box = page_box()
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        title = Gtk.Label(label=f"{backup.title} · {core.when(backup.taken)}", xalign=0)
        title.add_css_class("big-title")
        head.append(title)
        self.facts = Gtk.Label(label="Reading…", xalign=0)
        self.facts.add_css_class("hint")
        head.append(self.facts)
        hint_text = ("The files a restore was about to overwrite, saved just before it ran."
                     if backup.safety else
                     "Each file is compared with the one on disk now.")
        hint = Gtk.Label(label=hint_text, xalign=0, wrap=True)
        hint.add_css_class("hint")
        head.append(hint)
        box.append(head)

        bar = Gtk.Box(spacing=12)
        self.seg = segmented([("all", "All"), ("changed", "Changed"), ("missing", "Gone now")],
                             "all", self._set_filter)
        bar.append(self.seg)
        search = Gtk.SearchEntry(placeholder_text="Filter files", hexpand=True)
        search.connect("search-changed", self._on_search)
        bar.append(search)
        box.append(bar)

        self.groups = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        self.groups.append(Adw.Spinner() if hasattr(Adw, "Spinner") else Gtk.Spinner(spinning=True))
        box.append(self.groups)

        self.add_named(scrolled(box), "list")
        self.file_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add_named(self.file_page, "file")
        self.set_visible_child_name("list")

        # Comparing a few hundred files with disk is quick but not instant.
        def work():
            try:
                entries = core.backup_entries(backup.path)
                err = None
            except Exception as e:  # OSError, BadZipFile and friends
                entries, err = [], str(e)
            GLib.idle_add(self._loaded, entries, err)
        threading.Thread(target=work, daemon=True).start()

    def _loaded(self, entries, err) -> None:
        self.entries = entries
        if err:
            self.facts.set_label(f"Cannot read this backup: {err}")
        else:
            counts = {k: 0 for k in STATUS_TEXT}
            for e in entries:
                counts[e.status] = counts.get(e.status, 0) + 1
            parts = [core.plural(len(entries), "file"), core.human_size(self.backup.size)]
            if counts[core.CHANGED]:
                parts.append(f"{counts[core.CHANGED]} changed since then")
            if counts[core.MISSING]:
                parts.append(f"{counts[core.MISSING]} gone now")
            if counts[core.UNREADABLE]:
                parts.append(f"{counts[core.UNREADABLE]} not readable without root")
            self.facts.set_label(" · ".join(parts))
            # Open on what is most likely wanted: what is different.
            if counts[core.CHANGED] and self.filter_mode == "all":
                self.seg.buttons["changed"].set_active(True)
        self._render()

    def _set_filter(self, mode: str) -> None:
        self.filter_mode = mode
        self._render()

    def _on_search(self, entry) -> None:
        self.query = entry.get_text().strip().lower()
        self._render()

    def _visible(self) -> list[core.BackupEntry]:
        out = []
        for e in self.entries:
            if self.filter_mode == "changed" and e.status != core.CHANGED:
                continue
            if self.filter_mode == "missing" and e.status != core.MISSING:
                continue
            if self.query and self.query not in str(e.path).lower():
                continue
            out.append(e)
        return out

    def _render(self) -> None:
        while (child := self.groups.get_first_child()) is not None:
            self.groups.remove(child)
        visible = self._visible()
        if not visible:
            self.groups.append(Adw.StatusPage(
                icon_name="edit-find-symbolic", title="Nothing to show",
                description="No file in this backup matches."))
            return
        by_group: dict[str, list[core.BackupEntry]] = {}
        for e in visible:
            by_group.setdefault(core.group_of(e.path), []).append(e)
        # Home first — it is what people usually restore.
        for name in sorted(by_group, key=lambda g: (g != "~", g)):
            rows = by_group[name]
            label = "Home (~)" if name == "~" else name
            group = Adw.PreferencesGroup(title=f"{label} ({len(rows)})")
            for e in rows:
                text, kind = STATUS_TEXT.get(e.status, (e.status, "same"))
                row = action_row(core.display_path(e.path), core.human_size(e.size), pill(text, kind))
                row.set_activatable(True)
                row.add_suffix(Gtk.Image(icon_name="go-next-symbolic"))
                row.connect("activated", lambda _r, entry=e: self.show_file(entry))
                group.add(row)
            self.groups.append(group)

    # ── one file ──

    def show_file(self, entry: core.BackupEntry) -> None:
        while (child := self.file_page.get_first_child()) is not None:
            self.file_page.remove(child)

        saved = core.read_member(self.backup.path, entry.member)
        current = None
        if entry.status in (core.SAME, core.CHANGED):
            try:
                current = entry.path.read_bytes()
            except OSError:
                current = None

        top = Gtk.Box(spacing=8, margin_top=12, margin_bottom=6, margin_start=12, margin_end=12)
        back = Gtk.Button(icon_name="go-previous-symbolic", tooltip_text="Back to the file list")
        back.connect("clicked", lambda _b: self.set_visible_child_name("list"))
        top.append(back)
        title = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        path_lbl = Gtk.Label(label=core.display_path(entry.path), xalign=0,
                             ellipsize=Pango.EllipsizeMode.MIDDLE)
        path_lbl.add_css_class("heading")
        title.append(path_lbl)
        text, kind = STATUS_TEXT.get(entry.status, (entry.status, "same"))
        st = Gtk.Box(spacing=6)
        st.append(pill(text, kind))
        title.append(st)
        top.append(title)
        restore = Gtk.Button(label="Restore this file")
        restore.add_css_class("suggested-action")
        restore.set_sensitive(entry.status != core.SAME)
        restore.set_tooltip_text("Same as the file on disk now" if entry.status == core.SAME
                                 else "Put the backed-up copy back (the current file is saved first)")
        restore.connect("clicked", lambda _b: self._confirm_restore(entry))
        top.append(restore)
        self.file_page.append(top)

        modes = []
        if current is not None and entry.status == core.CHANGED:
            modes.append(("diff", "Changes since backup"))
        modes.append(("saved", "Saved copy"))
        view_holder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, vexpand=True)

        def show(mode):
            while (c := view_holder.get_first_child()) is not None:
                view_holder.remove(c)
            view_holder.append(self._file_view(mode, entry, saved, current))

        seg_bar = Gtk.Box(margin_start=12, margin_end=12, margin_bottom=8)
        seg_bar.append(segmented(modes, modes[0][0], show))
        self.file_page.append(seg_bar)
        self.file_page.append(view_holder)
        show(modes[0][0])
        self.set_visible_child_name("file")

    def _file_view(self, mode, entry, saved: bytes, current: bytes | None) -> Gtk.Widget:
        if not core.is_text(saved) or (current is not None and not core.is_text(current)):
            return Adw.StatusPage(icon_name="application-x-executable-symbolic", title="Binary file",
                                  description=f"{core.human_size(len(saved))} — not shown as text.")
        buf = Gtk.TextBuffer()
        tags = {
            "add": buf.create_tag("add", foreground="#8a9a6c"),
            "del": buf.create_tag("del", foreground="#b36b5a"),
            "hunk": buf.create_tag("hunk", foreground="#5a7a8a"),
            "meta": buf.create_tag("meta", foreground="#a89f91"),
        }
        if mode == "diff" and current is not None:
            lines = core.text_diff(saved, current, core.display_path(entry.path))
            legend = "− what the backup has    + what the file has now"
            for line in lines:
                tag = None
                if line.startswith(("---", "+++")):
                    tag = "meta"
                elif line.startswith("@@"):
                    tag = "hunk"
                elif line.startswith("+"):
                    tag = "add"
                elif line.startswith("-"):
                    tag = "del"
                end = buf.get_end_iter()
                if tag:
                    buf.insert_with_tags(end, line + "\n", tags[tag])
                else:
                    buf.insert(end, line + "\n")
        else:
            legend = "The file as it was when the backup was taken"
            buf.set_text(saved.decode("utf-8", errors="replace"))

        tv = Gtk.TextView(buffer=buf, editable=False, cursor_visible=False, monospace=True,
                          wrap_mode=Gtk.WrapMode.NONE, left_margin=12, right_margin=12,
                          top_margin=8, bottom_margin=8)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, vexpand=True)
        lg = Gtk.Label(label=legend, xalign=0, margin_start=12, margin_bottom=4)
        lg.add_css_class("hint")
        box.append(lg)
        sw = Gtk.ScrolledWindow(vexpand=True, child=tv)
        sw.add_css_class("card")
        sw.set_margin_start(12)
        sw.set_margin_end(12)
        sw.set_margin_bottom(12)
        box.append(sw)
        return box

    def _confirm_restore(self, entry: core.BackupEntry) -> None:
        path = core.display_path(entry.path)
        body = (f"{path} will be replaced by the copy from {core.when(self.backup.taken)}. "
                "The current file is saved first, as a new “Before a restore” backup.")
        if core.needs_privilege(entry.path):
            body += " You will be asked for your password."
        dialog = Adw.AlertDialog(heading="Restore this file?", body=body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("restore", "Restore")
        dialog.set_response_appearance("restore", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("cancel")
        dialog.connect("response", lambda _d, r: r == "restore" and self._restore(entry))
        dialog.present(self.window)

    def _restore(self, entry: core.BackupEntry) -> None:
        def work():
            try:
                saved = core.restore_entry(self.backup.path, entry)
                msg = f"Restored {core.display_path(entry.path)}"
                if saved:
                    msg += " · previous copy kept"
                GLib.idle_add(self._restored, msg, True)
            except (OSError, RuntimeError) as e:
                GLib.idle_add(self._restored, str(e), False)
        threading.Thread(target=work, daemon=True).start()

    def _restored(self, msg: str, ok: bool) -> None:
        self.window.toast(msg)
        if ok:
            # Statuses changed and a safety backup appeared.
            self.window.reload(keep=self.backup.path)


# ── Window ────────────────────────────────────────────────────────────


class SnapshotWindow(Adw.ApplicationWindow):
    def __init__(self, app: Adw.Application, show: str | None = None):
        super().__init__(application=app, title="Stoa Snapshots", default_width=1080, default_height=720)
        self.show_section = show
        self.toasts = Adw.ToastOverlay()
        self.split = Adw.NavigationSplitView(min_sidebar_width=280, max_sidebar_width=360)
        self.toasts.set_child(self.split)
        self.set_content(self.toasts)

        # Sidebar
        side = Adw.ToolbarView()
        sh = Adw.HeaderBar()
        refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text="Reload")
        refresh.connect("clicked", lambda _b: self.reload())
        sh.pack_start(refresh)
        new = Gtk.MenuButton(icon_name="list-add-symbolic", tooltip_text="Take a new snapshot")
        menu = Gio.Menu()
        menu.append("Snapshot packages now", "win.snap-packages")
        menu.append("Back up configs now", "win.backup-configs")
        new.set_menu_model(menu)
        sh.pack_end(new)
        side.add_top_bar(sh)
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.list.add_css_class("navigation-sidebar")
        self.list.set_header_func(_section_header)
        self.list.connect("row-selected", self._on_select)
        side.set_content(Gtk.ScrolledWindow(child=self.list, vexpand=True))
        self.split.set_sidebar(Adw.NavigationPage(title="Snapshots", child=side))

        # Content
        self.content = Adw.ToolbarView()
        self.header = Adw.HeaderBar()
        self.wtitle = Adw.WindowTitle(title="Stoa Snapshots", subtitle="")
        self.header.set_title_widget(self.wtitle)
        self.actions = Gtk.Box(spacing=6)
        self.header.pack_end(self.actions)
        self.content.add_top_bar(self.header)
        self.split.set_content(Adw.NavigationPage(title="Snapshot", child=self.content))

        for name, cb in (("snap-packages", self._snap_packages), ("backup-configs", self._backup_configs)):
            a = Gio.SimpleAction.new(name, None)
            a.connect("activate", lambda *_x, f=cb: f())
            self.add_action(a)

        self.reload()

    def toast(self, text: str) -> None:
        self.toasts.add_toast(Adw.Toast(title=GLib.markup_escape_text(text), timeout=4))

    # ── data ──

    def reload(self, keep=None) -> None:
        selected = keep
        if selected is None and (row := self.list.get_selected_row()) is not None:
            selected = row.item.path
        while (row := self.list.get_row_at_index(0)) is not None:
            self.list.remove(row)

        self.pkgs = core.list_pkg_snapshots()
        self.cfgs = core.list_config_backups()
        self.current = None  # pacman -Q, fetched once per reload, lazily

        for i, s in enumerate(self.pkgs):
            prev = self.pkgs[i + 1] if i + 1 < len(self.pkgs) else None
            sub = core.plural(s.total, "package")
            if prev is not None:
                sub += " · " + core.diff_packages(prev.packages, s.packages).short() + " since previous"
            self.list.append(SnapRow(s, "packages", core.when(s.taken), sub))
        for b in self.cfgs:
            badge = pill("before restore", "unreadable") if b.safety else None
            files = core.count_files(b.path)
            sub = f"{core.plural(files, 'file')} · {core.human_size(b.size)}" if files >= 0 else core.human_size(b.size)
            self.list.append(SnapRow(b, "configs", core.when(b.taken), sub, badge))

        if not self.pkgs and not self.cfgs:
            self.wtitle.set_title("No snapshots yet")
            self._set_body(Adw.StatusPage(
                icon_name="document-save-symbolic", title="No snapshots yet",
                description="Package snapshots appear by themselves before every pacman "
                            "transaction. Use + to take one now or to back up your configs."))
            return

        target = None
        i = 0
        while (row := self.list.get_row_at_index(i)) is not None:
            if selected is not None and row.item.path == selected:
                target = row
                break
            # --show configs opens the newest real backup, not a
            # "before restore" safety copy.
            if (target is None and self.show_section and row.section == self.show_section
                    and not getattr(row.item, "safety", False)):
                target = row
            i += 1
        self.show_section = None
        self.list.select_row(target or self.list.get_row_at_index(0))

    def _set_body(self, widget: Gtk.Widget) -> None:
        self.content.set_content(widget)

    def _set_actions(self, buttons: list[Gtk.Widget]) -> None:
        while (c := self.actions.get_first_child()) is not None:
            self.actions.remove(c)
        for b in buttons:
            self.actions.append(b)

    def _on_select(self, _lb, row: SnapRow | None) -> None:
        if row is None:
            return
        item = row.item
        if isinstance(item, core.PkgSnapshot):
            if self.current is None:
                self.current = core.current_packages() or {}
            idx = self.pkgs.index(item)
            prev = self.pkgs[idx + 1] if idx + 1 < len(self.pkgs) else None
            self.wtitle.set_title("Package snapshot")
            self.wtitle.set_subtitle(item.taken.strftime("%A %d %B %Y, %H:%M"))
            self._set_body(PackageView(self, item, prev, self.current or None))
        else:
            self.wtitle.set_title(item.title)
            self.wtitle.set_subtitle(item.taken.strftime("%A %d %B %Y, %H:%M"))
            self._set_body(ConfigView(self, item))
        self._set_actions(self._item_actions(item))
        self.split.set_show_content(True)

    def _item_actions(self, item) -> list[Gtk.Widget]:
        out = []
        if isinstance(item, core.ConfigBackup):
            ra = Gtk.Button(label="Restore all…", tooltip_text="Go through every file, with its diff, in a terminal")
            ra.connect("clicked", lambda _b: self._restore_all(item))
            out.append(ra)
        trash = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Move to trash")
        trash.connect("clicked", lambda _b: self._trash(item))
        out.append(trash)
        folder = Gtk.Button(icon_name="folder-open-symbolic", tooltip_text="Show in the file manager")
        folder.connect("clicked", lambda _b: Gio.AppInfo.launch_default_for_uri(
            item.path.parent.as_uri(), None))
        out.append(folder)
        return out

    # ── actions ──

    def _snap_packages(self) -> None:
        cmd = core.which("stoa-pkg-snapshot")
        if not cmd:
            self.toast("stoa-pkg-snapshot is not installed")
            return
        self.toast("Taking a package snapshot…")
        run_async([cmd], lambda ok, out: (self.toast("Package snapshot taken" if ok else f"Failed: {out}"),
                                          ok and self.reload()))

    def _backup_configs(self) -> None:
        cmd = core.which("stoa-maintain")
        if not cmd:
            self.toast("stoa-maintain is not installed")
            return
        self.toast("Backing up configs…")
        run_async([cmd, "--backup"], lambda ok, out: (self.toast("Configs backed up" if ok else f"Failed: {out}"),
                                                      ok and self.reload()))

    def _restore_all(self, backup: core.ConfigBackup) -> None:
        cmd = core.which("stoa-maintain")
        if not cmd:
            self.toast("stoa-maintain is not installed")
            return
        open_terminal("Stoa — Restore configs", [cmd, "--restore-interactive", str(backup.path)])

    def _trash(self, item) -> None:
        dialog = Adw.AlertDialog(
            heading="Move this snapshot to the trash?",
            body=f"{item.path.name} — you can get it back from the trash.")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("trash", "Move to trash")
        dialog.set_response_appearance("trash", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")

        def respond(_d, r):
            if r != "trash":
                return
            try:
                Gio.File.new_for_path(str(item.path)).trash(None)
                self.toast("Moved to trash")
            except GLib.Error as e:
                self.toast(f"Could not move to trash: {e.message}")
            self.reload()
        dialog.connect("response", respond)
        dialog.present(self)


class SnapshotApp(Adw.Application):
    def __init__(self, show: str | None):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.show = show

    def do_startup(self):
        Adw.Application.do_startup(self)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        provider = Gtk.CssProvider()
        provider.load_from_string(CSS) if hasattr(provider, "load_from_string") else provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def do_activate(self):
        win = self.props.active_window or SnapshotWindow(self, self.show)
        win.present()


def main(argv: list[str]) -> int:
    show = None
    if "--show" in argv:
        i = argv.index("--show")
        if i + 1 < len(argv) and argv[i + 1] in ("packages", "configs"):
            show = argv[i + 1]
    return SnapshotApp(show).run([argv[0]])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
