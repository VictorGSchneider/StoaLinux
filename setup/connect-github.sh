#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Connect this machine to GitHub                 ║
# ║  "No man is free who is not master of himself." — Epictetus  ║
# ║                                                              ║
# ║  Everything stoa-sync needs to pull and push the StoaLinux   ║
# ║  clone without prompts:                                      ║
# ║    1. git + github-cli installed                             ║
# ║    2. gh auth login (browser or one-time code — no token or  ║
# ║       SSH key to create by hand)                             ║
# ║    3. gh auth setup-git: git pushes over HTTPS with that     ║
# ║       login (gh is git's credential helper for github.com)   ║
# ║    4. commit identity (user.name / user.email), defaulting   ║
# ║       to your GitHub name and no-reply address               ║
# ║    5. the clone's origin over HTTPS, and pull.rebase so a    ║
# ║       plain `git pull` never stops on "divergent branches"   ║
# ║    6. a dry-run push to prove it works                       ║
# ║                                                              ║
# ║  Idempotent: re-run any time, it only fixes what is missing. ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="${STOA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_SLUG="VictorGSchneider/StoaLinux"

B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

_ok()   { echo -e "  ${O}[✓] $*${R}"; }
_skip() { echo -e "  ${S}[~] $*${R}"; }
_warn() { echo -e "  ${T}[!] $*${R}"; }

if [ "$(id -u)" -eq 0 ]; then
    _warn "Run as your own user, not root — the login and git config belong to you."
    exit 1
fi

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — Connect to GitHub                   ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# ── 1. Tools ──
_need=()
command -v git >/dev/null 2>&1 || _need+=(git)
command -v gh  >/dev/null 2>&1 || _need+=(github-cli)
if [ ${#_need[@]} -gt 0 ]; then
    echo -e "  ${F}Installing: ${_need[*]}${R}"
    sudo pacman -S --needed --noconfirm "${_need[@]}"
fi
_ok "git $(git --version | awk '{print $3}') · gh $(gh --version | awk 'NR==1{print $3}')"

# ── 2. Log in ──
if gh auth status --hostname github.com >/dev/null 2>&1; then
    _skip "Already logged in to GitHub as $(gh api user --jq .login 2>/dev/null || echo '?')."
else
    echo -e "  ${F}Logging in to GitHub. gh shows a one-time code and opens the browser;${R}"
    echo -e "  ${F}paste the code there and approve. (No browser here? Open the URL it prints on any device.)${R}"
    echo ""
    gh auth login --hostname github.com --git-protocol https --web
    gh auth status --hostname github.com >/dev/null 2>&1 || { _warn "Login did not complete."; exit 1; }
    _ok "Logged in as $(gh api user --jq .login)"
fi
GH_LOGIN="$(gh api user --jq .login)"

# ── 3. git uses that login ──
gh auth setup-git --hostname github.com
_ok "git uses your GitHub login for github.com (gh credential helper)"

# ── 4. Commit identity ──
_cur_name="$(git config --global user.name || true)"
_cur_mail="$(git config --global user.email || true)"
if [ -n "$_cur_name" ] && [ -n "$_cur_mail" ]; then
    _skip "Commits signed as: ${_cur_name} <${_cur_mail}>"
else
    _gh_name="$(gh api user --jq '.name // .login' 2>/dev/null || echo "$GH_LOGIN")"
    _gh_id="$(gh api user --jq .id 2>/dev/null || true)"
    # GitHub's no-reply address keeps a private e-mail private and still
    # links the commits to the account.
    _gh_mail="${_gh_id:+${_gh_id}+}${GH_LOGIN}@users.noreply.github.com"
    read -rp "  Name on your commits [${_cur_name:-$_gh_name}]: " _name
    read -rp "  E-mail on your commits [${_cur_mail:-$_gh_mail}]: " _mail
    git config --global user.name  "${_name:-${_cur_name:-$_gh_name}}"
    git config --global user.email "${_mail:-${_cur_mail:-$_gh_mail}}"
    _ok "Commits signed as: $(git config --global user.name) <$(git config --global user.email)>"
fi

# ── 5. The StoaLinux clone ──
if [ ! -d "$STOA_DIR/.git" ]; then
    _warn "No git clone at ${STOA_DIR} — clone it with: gh repo clone ${REPO_SLUG} ~/StoaLinux"
    exit 1
fi
cd "$STOA_DIR"

_origin="$(git remote get-url origin 2>/dev/null || true)"
case "$_origin" in
    https://github.com/*)
        _skip "origin: ${_origin}" ;;
    git@github.com:*|ssh://git@github.com/*)
        # SSH works too, but only with a key on this machine and on GitHub;
        # the HTTPS remote rides on the gh login just set up.
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            _skip "origin over SSH, and your SSH key works: ${_origin}"
        else
            _https="https://github.com/${_origin#*github.com[:/]}"
            git remote set-url origin "$_https"
            _ok "origin switched from SSH (no working key) to ${_https}"
        fi
        ;;
    "")
        git remote add origin "https://github.com/${REPO_SLUG}.git"
        _ok "origin added: https://github.com/${REPO_SLUG}.git"
        ;;
    *)
        _skip "origin is not on github.com (${_origin}) — left alone." ;;
esac

# Local to this clone only: replay local commits on top of GitHub's instead
# of refusing (the "divergent branches" stop), stashing uncommitted edits
# around it. stoa-sync passes the same flags explicitly.
git config pull.rebase true
git config rebase.autoStash true
_ok "This clone pulls with rebase (no more \"divergent branches\" stops)"

# ── 6. Prove it ──
git fetch origin --quiet
_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
_ahead="$(git rev-list --count "origin/${_branch}..HEAD" 2>/dev/null || echo 0)"
_behind="$(git rev-list --count "HEAD..origin/${_branch}" 2>/dev/null || echo 0)"
# A dry-run push to a branch name that does not exist still authenticates
# against GitHub's receive-pack, but can never be refused for history (being
# behind), so a failure here means the login or permission is wrong.
if git push --dry-run --quiet origin "HEAD:refs/heads/stoa-connect-check" >/dev/null 2>&1; then
    _ok "Read and write access to $(git remote get-url origin) works"
else
    _warn "Pushing is refused. Is ${GH_LOGIN} allowed to push to this repository?"
    echo -e "  ${S}    Check with: gh repo view ${REPO_SLUG} --json viewerPermission${R}"
    exit 1
fi
if [ "$_behind" -gt 0 ] || [ "$_ahead" -gt 0 ]; then
    echo -e "  ${F}${_branch}: ${_ahead} local commit(s) not on GitHub, ${_behind} on GitHub not here.${R}"
    echo -e "  ${S}  stoa-sync will put them together (rebase) and push.${R}"
fi

echo ""
_ok "Connected. stoa-sync can pull and push without asking."
echo ""
