#!/usr/bin/env bash
# Apply this repo into Firefox: prefs, userChrome.css, add-on policy, Vimium's
# settings, and the browser-level key bindings. Idempotent, safe to re-run.
#
# Usage:
#   ./install.sh                       asks which add-ons; without a terminal,
#                                      the ones last chosen
#   ./install.sh --extensions=a,b      exactly these amo slugs (or all / none),
#                                      and don't ask
#   ./install.sh --dry-run             preview only (or DRY_RUN=true)
#
# It does NOT install Firefox — that must be the deb from packages.mozilla.org,
# which is best-linux-environment's basic/70-firefox.sh.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Recorded here, not inside can_sudo: write_root always has stdin redirected to
# its payload, so a -t 0 test down there can never see the terminal.
STDIN_IS_TTY=false; [[ -t 0 ]] && STDIN_IS_TTY=true

# ── Arguments ────────────────────────────────────────────────────────────────
# DRY_RUN=1 is the obvious way for an orchestrator to write it, so normalise
# rather than let anything but `true` fall through to a real install.
dry="${DRY_RUN:-false}"
case "${dry,,}" in
    false|0|no|off) DRY_RUN=false ;;
    true|1|yes|on)  DRY_RUN=true ;;
    *) printf '%s: DRY_RUN=%s is not a boolean — use true or false\n' "${0##*/}" "$dry" >&2; exit 2 ;;
esac

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    exit "${1:-2}"
}

# Empty means "not asked", which is not the same as `none` — see SELECTED below.
WANT_EXT=""
for arg in "$@"; do
    case "$arg" in
        '')             ;;   # 10-tools.sh passes one possibly-empty argument
        --dry-run)      DRY_RUN=true ;;
        --extensions=*) WANT_EXT="${arg#--extensions=}" ;;
        -h|--help|help) usage 0 ;;
        *) printf '%s: unknown argument %s\n' "${0##*/}" "$arg" >&2; usage ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi
step()  { printf '%s▸%s %s\n' "$C_BLUE"  "$C_OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip()  { printf '%s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
title() { printf '\n%s══ %s ══%s\n' "$C_BOLD" "$*" "$C_OFF"; }
would() { printf '%s  would %s:%s %s\n' "$C_DIM" "$1" "$C_OFF" "${*:2}"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
# Needs a tty for the prompt, or cached credentials — never hang the boot cron.
can_sudo() { [[ "$STDIN_IS_TTY" == true ]] || sudo -n true 2>/dev/null; }
tilde()   { printf '%s' "${1/#$HOME/\~}"; }

# ── The checkbox list ────────────────────────────────────────────────────────
# The same widget best-linux-environment asks everything with (its lib/ui.sh),
# carried here rather than sourced: this repo is cloned and run on its own, so it
# cannot reach into the orchestrator's lib/. One question, every add-on visible
# at once, arrow keys to move and space to tick.
#
#   CHK_LABELS=(…)  what to show      CHK_STATE=(1 0 …)  1 pre-ticked
#   checklist "Heading" "hint"        # CHK_STATE now holds what was chosen
CHK_LABELS=(); CHK_STATE=()

# Arrow keys arrive as three bytes (ESC [ A). The two after ESC are read with a
# timeout so a bare Escape — one byte — doesn't hang waiting for the rest of a
# sequence that is never coming. 0.3s, not 50ms: over ssh the tail can lag, and
# too short a window turns an arrow key into an Escape.
read_key() {
    local k rest=''
    IFS= read -rsn1 k 2>/dev/null || { printf 'enter'; return; }
    case "$k" in
        $'\e') read -rsn2 -t 0.3 rest 2>/dev/null || rest=''
               case "$rest" in '[A') printf 'up' ;; '[B') printf 'down' ;; *) printf 'esc' ;; esac ;;
        '')  printf 'enter' ;;
        ' ') printf 'space' ;;
        *)   printf '%s' "$k" ;;
    esac
}

# Cut to N columns. A row must never wrap: the redraw moves the cursor up by
# exactly one line per row, so a wrapped row smears every later frame down the
# screen. ${#s} counts characters, close enough for these ASCII labels.
fit() {
    local s="$1" max="$2"
    (( max < 10 )) && max=10
    if (( ${#s} > max )); then printf '%s…' "${s:0:max-1}"; else printf '%s' "$s"; fi
}

# checklist HEADING [HINT] — edits CHK_STATE in place.
checklist() {
    local heading="$1" hint="${2:-}" n=${#CHK_LABELS[@]} i
    (( n )) || return 0

    local width; width="$(tput cols 2>/dev/null || echo 80)"
    (( width > 20 )) || width=80

    printf '\n%s══ %s ══%s\n' "$C_BOLD" "$heading" "$C_OFF"
    [[ -n "$hint" ]] && printf '%s   %s%s\n' "$C_DIM" "$hint" "$C_OFF"

    # No terminal → show the list, change nothing. This is the boot cron and
    # `| tee install.log`; silently keeping the defaults is the only honest
    # answer when there is nobody to ask. Guarded again at the call site, so
    # this path is belt and braces.
    if [[ ! -t 0 || ! -t 1 ]]; then
        skip "No terminal to ask on — keeping the defaults below."
        for i in "${!CHK_LABELS[@]}"; do
            printf '   %s %s\n' \
                "$( ((CHK_STATE[i])) && printf '[x]' || printf '[ ]' )" "${CHK_LABELS[$i]}"
        done
        return 0
    fi

    printf '%s   ↑/↓ move · space toggle · a all · n none · enter confirm%s\n\n' "$C_DIM" "$C_OFF"

    local cur=0 first=1 key
    # Hidden for the duration and put back on every exit path — including
    # Ctrl-C, which would otherwise leave an invisible cursor behind.
    printf '\033[?25l'
    trap 'printf "\033[?25h"; exit 130' INT

    while :; do
        if (( first )); then first=0; else printf '\033[%dA' "$n"; fi
        for i in "${!CHK_LABELS[@]}"; do
            local mark box row
            if (( i == cur )); then mark="${C_BLUE}❯${C_OFF}"; else mark=' '; fi
            if (( CHK_STATE[i] )); then box="${C_GREEN}[x]${C_OFF}"; else box="${C_DIM}[ ]${C_OFF}"; fi
            row="$(fit "${CHK_LABELS[$i]}" $((width - 10)))"
            (( i == cur )) && row="${C_BOLD}${row}${C_OFF}"
            # \033[2K first: without it a short row drawn over a longer one
            # leaves the tail of the old text behind.
            printf '\033[2K %s %s %s\n' "$mark" "$box" "$row"
        done

        key="$(read_key)"
        # `x=$(( … ))` throughout, never `(( x = … ))`: this script runs under
        # `set -e`, and an arithmetic COMMAND whose result is zero exits
        # non-zero — so `(( CHK_STATE[cur] = 1 - CHK_STATE[cur] ))` would kill
        # the run the first time you unticked something. An assignment carries
        # the status of the assignment, which is always success.
        case "$key" in
            up|k)    cur=$(( (cur - 1 + n) % n )) ;;
            down|j)  cur=$(( (cur + 1) % n )) ;;
            space|x) CHK_STATE[cur]=$(( 1 - CHK_STATE[cur] )) ;;
            a|A)     for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=1; done ;;
            n|N)     for i in "${!CHK_STATE[@]}"; do CHK_STATE[$i]=0; done ;;
            enter)   break ;;
            # q ends the list as it stands. Escape does NOT: a slow link can
            # split an arrow key's three bytes far enough apart that the tail
            # arrives after the timeout above, and the lone ESC left over must
            # not be able to confirm a list you were still editing.
            q|Q)     break ;;
            esc)     ;;
        esac
    done

    printf '\033[?25h'
    trap - INT
    return 0
}

# Never "/tmp/name.$$": guessable, and a pre-planted symlink there would be
# followed by the `sudo install` below.
tmp_file() {
    if [[ "$DRY_RUN" == true ]]; then printf '/tmp/firefox-config-dry-run%s\n' "${1:-}"
    else mktemp --suffix="${1:-}"; fi
}

# write_user DEST — content on stdin. An identical file is left completely alone
# (no write, no backup, no mtime), which is what makes boot-time re-runs free.
write_user() {
    local dst="$1" label new
    label="$(tilde "$dst")"
    new="$(cat)"

    if [[ -f "$dst" ]] && [[ "$new" == "$(cat "$dst" 2>/dev/null)" ]]; then
        skip "$label already up to date."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -e "$dst" ]]; then would rewrite "$label (backing the old one up)"
        else would write "$label"; fi
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    local verb=wrote
    # One rolling copy, not one per run: ".backup.$$" was never pruned and $$
    # collides across boots, so it neither bounded the clutter nor reliably kept
    # the version you'd actually roll back to.
    if [[ -e "$dst" ]]; then
        cp -a "$dst" "$dst.backup"
        verb=rewrote
        warn "$label differed — old copy kept as $(basename "$dst").backup"
    fi
    printf '%s\n' "$new" > "$dst"
    ok "$verb $label"
}

# write_root DEST MODE — the same contract through sudo. Non-zero when sudo is
# unavailable, so the caller stops rather than pressing on half-applied.
write_root() {
    local dst="$1" mode="${2:-0644}" new tmp
    new="$(cat)"

    if [[ -f "$dst" ]] && [[ "$new" == "$(cat "$dst" 2>/dev/null)" ]]; then
        skip "$dst already up to date."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -e "$dst" ]]; then would rewrite "$dst (backing the old one up)"
        else would write "$dst"; fi
        return 0
    fi
    if ! can_sudo; then
        warn "sudo unavailable (non-interactive) — skipped $dst."
        return 1
    fi
    tmp="$(tmp_file)"
    printf '%s\n' "$new" > "$tmp"
    step "Writing $dst"
    # Checked by hand, not left to `set -e`: this function is always called from
    # an `if`/`||` list, which suspends errexit for everything inside it — so a
    # failed sudo would otherwise fall through to the "wrote" line below.
    sudo mkdir -p "$(dirname "$dst")" \
        || { rm -f "$tmp"; warn "could not create $(dirname "$dst")."; return 1; }
    if [[ -e "$dst" ]]; then
        sudo cp -a "$dst" "$dst.backup"
        warn "$dst differed — old copy kept as $(basename "$dst").backup"
    fi
    sudo install -m "$mode" "$tmp" "$dst" \
        || { rm -f "$tmp"; warn "could not write $dst."; return 1; }
    rm -f "$tmp"
    ok "wrote $dst"
}

title "Firefox config"

# Under sudo $HOME is /root: no profile is found there, so it would write the
# system half as root and silently skip yours. Real root (no SUDO_USER) is fine.
if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    warn "Don't run this with sudo — run it as $SUDO_USER."
    warn "It asks for sudo itself, for /etc/firefox/policies/ and /usr/lib/firefox/."
    exit 2
fi

if ! has_cmd firefox; then
    skip "Firefox is not installed — nothing to configure."
    skip "Install the deb (NOT the snap): best-linux-environment/basic/70-firefox.sh"
    exit 0
fi

# ── Add-ons: the catalogue ──────────────────────────────────────────────────
EXT_CONF="$REPO/extensions.conf"
EXT_ID=(); EXT_SLUG=(); EXT_LABEL=(); EXT_DEFAULT=()
if [[ -f "$EXT_CONF" ]]; then
    while IFS='|' read -r id slug label def; do
        [[ -z "$id" || "$id" == \#* ]] && continue
        EXT_ID+=("$id"); EXT_SLUG+=("$slug"); EXT_LABEL+=("$label")
        EXT_DEFAULT+=("${def:-1}")
    done < "$EXT_CONF"
else
    warn "No extensions.conf in $(tilde "$REPO") — no add-on policy will be written."
fi

# ── Add-ons: the selection ──────────────────────────────────────────────────
# Four sources, in order: --extensions= (an orchestrator already asked, so don't
# ask twice), the checkbox list when there is a terminal to show it on, the state
# file (the boot-cron path — your last choice, not the repo's defaults), the
# `default` column. Not in the repo: the choice is this machine's.
STATE_DIR="$HOME/.cache/firefox-config"
STATE_FILE="$STATE_DIR/extensions"
SELECTED=()
selection_source=""

select_by_slug() {
    local want="$1" i found=false
    for i in "${!EXT_SLUG[@]}"; do
        if [[ "${EXT_SLUG[$i]}" == "$want" ]]; then SELECTED+=("$want"); found=true; break; fi
    done
    [[ "$found" == true ]] || warn "Unknown add-on '$want' — not in extensions.conf, ignored."
}

# The list opens on what this machine last chose, not on the repo's defaults —
# so confirming it straight through is a no-op rather than a reset.
ask_extensions() {
    local i
    CHK_LABELS=(); CHK_STATE=()
    for i in "${!EXT_SLUG[@]}"; do
        CHK_LABELS+=("${EXT_LABEL[$i]}")
        if [[ -f "$STATE_FILE" ]]; then
            # -Fx: a slug must not match as a substring of another.
            if grep -Fxq "${EXT_SLUG[$i]}" "$STATE_FILE"; then CHK_STATE+=(1); else CHK_STATE+=(0); fi
        elif [[ "${EXT_DEFAULT[$i]}" == 1 ]]; then
            CHK_STATE+=(1)
        else
            CHK_STATE+=(0)
        fi
    done

    checklist "Firefox — which add-ons to install" \
        "Installed by Firefox's own policy and kept updated from AMO. Unticking one never uninstalls it — do that in about:addons."

    # An `if`, not `(( … )) && SELECTED+=…`: under `set -e` a loop whose last
    # iteration ends on a false test carries that failure out as the loop's own
    # status, and unticking the bottom row would end the run right here.
    for i in "${!CHK_STATE[@]}"; do
        if (( CHK_STATE[i] )); then SELECTED+=("${EXT_SLUG[$i]}"); fi
    done
    return 0
}

if [[ -n "$WANT_EXT" ]]; then
    selection_source="asked"
    case "$WANT_EXT" in
        all)  for i in "${!EXT_SLUG[@]}"; do SELECTED+=("${EXT_SLUG[$i]}"); done ;;
        none) ;;
        *)    while IFS= read -r slug; do
                  [[ -n "$slug" ]] && select_by_slug "$slug"
              done < <(printf '%s\n' "${WANT_EXT//,/$'\n'}") ;;
    esac
elif [[ ${#EXT_SLUG[@]} -gt 0 && -t 0 && -t 1 ]]; then
    # An empty answer is an answer — "none" — and records as such below, which
    # is what stops the next boot from re-adding what you just unticked.
    selection_source="asked"
    ask_extensions
elif [[ -f "$STATE_FILE" ]]; then
    # An empty state file is a real answer — "none" — and must not fall through
    # to the defaults, or the next boot would undo unticking everything.
    selection_source="remembered"
    while IFS= read -r slug; do
        [[ -n "$slug" && "$slug" != \#* ]] && select_by_slug "$slug"
    done < "$STATE_FILE"
else
    selection_source="default"
    for i in "${!EXT_SLUG[@]}"; do
        [[ "${EXT_DEFAULT[$i]}" == 1 ]] && SELECTED+=("${EXT_SLUG[$i]}")
    done
fi

selected() {
    local want="$1" s
    for s in ${SELECTED[@]+"${SELECTED[@]}"}; do [[ "$s" == "$want" ]] && return 0; done
    return 1
}

case "$selection_source" in
    asked)      step "Add-ons: ${#SELECTED[@]} selected — ${SELECTED[*]:-none}" ;;
    remembered) skip "Add-ons: ${#SELECTED[@]} selected — ${SELECTED[*]:-none} (your last choice; --extensions= to change)" ;;
    default)    skip "Add-ons: ${#SELECTED[@]} by default — ${SELECTED[*]:-none} (never chosen on this machine, and no terminal to ask on)" ;;
esac

# Only for an explicit --extensions=: recording the defaults would invent a
# choice nobody made. Truncate-then-append, since `printf` on an empty array
# still writes a blank line and "none" has to record as an empty file.
if [[ "$selection_source" == asked && "$DRY_RUN" != true ]]; then
    mkdir -p "$STATE_DIR"
    : > "$STATE_FILE"
    for slug in ${SELECTED[@]+"${SELECTED[@]}"}; do printf '%s\n' "$slug" >> "$STATE_FILE"; done
elif [[ "$selection_source" == asked ]]; then
    would remember "${SELECTED[*]:-none} → $(tilde "$STATE_FILE")"
fi

# ── The policy file ─────────────────────────────────────────────────────────
# Mozilla's supported way to declare add-ons. `normal_installed` = installed at
# the next start and kept updated from AMO, still removable by hand.
POLICY_FILE="/etc/firefox/policies/policies.json"

build_policies() {
    local i first=true
    printf '{\n  "policies": {\n    "ExtensionSettings": {\n'
    for i in "${!EXT_ID[@]}"; do
        selected "${EXT_SLUG[$i]}" || continue
        [[ "$first" == true ]] || printf ',\n'
        first=false
        printf '      "%s": {\n' "${EXT_ID[$i]}"
        printf '        "installation_mode": "normal_installed",\n'
        printf '        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/%s/latest.xpi"\n' "${EXT_SLUG[$i]}"
        printf '      }'
    done
    printf '\n    }\n  }\n}\n'
}

if [[ ${#EXT_ID[@]} -gt 0 ]]; then
    build_policies | write_root "$POLICY_FILE" 0644 \
        || warn "Add-on policy not applied — the rest of the config still is."
fi

# ── The active profile ──────────────────────────────────────────────────────
# ~/.mozilla first: 70-firefox.sh leaves the old ~/snap copy as a rollback, so
# checking snap-first would sync into the dead profile forever after.
FF_ROOT=""
for candidate in "$HOME/.mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox"; do
    [[ -f "$candidate/profiles.ini" ]] && { FF_ROOT="$candidate"; break; }
done

if [[ -z "$FF_ROOT" ]]; then
    warn "No Firefox profile yet — launch Firefox once so it creates one, then re-run this."
    exit 0
fi

# The profile locked to this install ([InstallXXXX] Default=), else the one
# flagged Default=1. Paths are relative (IsRelative=1) unless they start with /.
resolve_profile() {
    local ini="$FF_ROOT/profiles.ini" rel=""

    rel="$(awk -F= '
        /^\[Install/      {ins=1; next}
        /^\[/             {ins=0}
        ins && $1=="Default" {print $2; exit}
    ' "$ini")"

    if [[ -z "$rel" ]]; then
        rel="$(awk -F= '
            /^\[Profile/ {p=1; path=""; def=0; next}
            /^\[/        {p=0}
            p && $1=="Path"    {path=$2}
            p && $1=="Default" && $2=="1" {def=1}
            p && def && path   {print path; exit}
        ' "$ini")"
    fi

    [[ -n "$rel" ]] || return 1
    if [[ "$rel" == /* ]]; then
        [[ -d "$rel" ]] && { printf '%s\n' "$rel"; return 0; }
    else
        [[ -d "$FF_ROOT/$rel" ]] && { printf '%s\n' "$FF_ROOT/$rel"; return 0; }
    fi
    return 1
}

PROFILE="$(resolve_profile || true)"
if [[ -z "$PROFILE" ]]; then
    warn "profiles.ini names no usable profile under $(tilde "$FF_ROOT") — launch Firefox once and re-run."
    exit 0
fi
step "Target profile: $(tilde "$PROFILE")"

# `lock` is a symlink to <ip>:+<pid>, created on start and removed on exit — so
# test -L, not -e: its target never exists, so -e is false even while Firefox is
# open. (.parentlock is NOT usable here: on Linux it survives shutdown, so -e on
# it is true forever.) pgrep -f, because -x tests the process name and the deb's
# is `firefox-bin`, not `firefox`. Either signal alone is enough: a stale lock
# after a crash only defers the write, which is the safe direction.
FF_RUNNING=false
if [[ "$DRY_RUN" != true ]] \
   && { [[ -L "$PROFILE/lock" ]] || pgrep -f '(^|/)firefox(-bin)?( |$)' >/dev/null 2>&1; }; then
    FF_RUNNING=true
fi

# ── Prefs + chrome/ ─────────────────────────────────────────────────────────
# Firefox only ever READS these, so they sync whether or not it is open. They
# are the repo's outright, unlike everything else in the profile.
copy_file() {
    local rel="$1" src="$REPO/$1"
    [[ -f "$src" ]] || return 0
    write_user "$PROFILE/$rel" < "$src"
}

# user.js and this machine's user.local.js land as ONE file, in that order:
# Firefox reads it top down and the last user_pref wins, so the local one does.
if [[ -f "$REPO/user.js" ]]; then
    { cat "$REPO/user.js"
      [[ -f "$REPO/user.local.js" ]] && cat "$REPO/user.local.js"
      :; } | write_user "$PROFILE/user.js"
fi

# File by file, never a directory-level diff: that would also see a
# userContent.css of your own, never come back equal, and recopy on every boot.
if [[ -d "$REPO/chrome" ]]; then
    while IFS= read -r -d '' f; do
        copy_file "chrome/${f#"$REPO/chrome/"}"
    done < <(find "$REPO/chrome" -type f -print0)
fi

# ── Vimium's settings ───────────────────────────────────────────────────────
# Its options are one JSON blob per extension in storage-sync-v2.sqlite, which
# Firefox holds open — so this is the one write that waits for it to close.
VIMIUM_SLUG="vimium-ff"
VIMIUM_ID="{d7742d87-e61d-4b78-b8a1-b469842139fa}"

sync_vimium() {
    local src="$REPO/vimium-settings.json" db="$PROFILE/storage-sync-v2.sqlite"
    [[ -f "$src" ]] || return 0
    if ! has_cmd python3; then
        warn "python3 not found — skipped the Vimium settings."
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        would write "Vimium settings → $(tilde "$db")"
        return 0
    fi
    local result
    result="$(python3 - "$db" "$src" "$VIMIUM_ID" "$db.backup" <<'PY'
import json, os, shutil, sqlite3, sys

db, src, ext_id, backup = sys.argv[1:5]
want = json.load(open(src))

def read_current(path):
    """Vimium's blob in PATH, or None if there is none we can use. Read-only, and
    deliberately lets a corrupt file raise before anything has been written."""
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        con.execute("PRAGMA schema_version")   # rejects a non-database outright
        try:
            row = con.execute(
                "SELECT data FROM storage_sync_data WHERE ext_id = ?", (ext_id,)
            ).fetchone()
        except sqlite3.OperationalError:
            return None                        # real database, table not made yet
        if not row or not row[0]:
            return None
        try:
            return json.loads(row[0])
        except ValueError:
            return None                        # unparseable row → overwrite it
    finally:
        con.close()


# No write and no backup when it already matches — backing up unconditionally is
# what left another copy of this database in the profile at every boot.
had_db = os.path.exists(db)
current = read_current(db) if had_db else None

if current == want:
    print("unchanged")
    sys.exit(0)

if had_db:
    shutil.copy2(db, backup)

con = sqlite3.connect(db)
con.execute("""CREATE TABLE IF NOT EXISTS storage_sync_data (
    ext_id TEXT NOT NULL PRIMARY KEY,
    data TEXT,
    sync_change_counter INTEGER NOT NULL DEFAULT 1
)""")
# A database we just created starts at user_version 0 and Firefox would try to
# migrate it — stamp it with the schema version it actually has.
if con.execute("PRAGMA user_version").fetchone()[0] == 0:
    con.execute("""CREATE TABLE IF NOT EXISTS storage_sync_mirror (
        guid TEXT NOT NULL PRIMARY KEY,
        ext_id TEXT UNIQUE,
        data TEXT
        CHECK((ext_id IS NULL AND data IS NULL) OR (ext_id IS NOT NULL AND data IS NOT NULL))
    )""")
    con.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value NOT NULL) WITHOUT ROWID")
    con.execute("PRAGMA user_version = 2")

con.execute(
    "INSERT INTO storage_sync_data (ext_id, data, sync_change_counter) VALUES (?, ?, 1) "
    "ON CONFLICT(ext_id) DO UPDATE SET data = excluded.data, sync_change_counter = 1",
    (ext_id, json.dumps(want, separators=(",", ":"))),
)
con.commit()
con.close()
print("written")
PY
)" || { warn "Could not write the Vimium settings — left the profile alone."; return 0; }

    if [[ "$result" == unchanged ]]; then
        skip "Vimium settings already up to date."
    else
        ok "applied vimium-settings.json (key mappings + hint/vomnibar CSS)"
    fi
}

if ! selected "$VIMIUM_SLUG"; then
    skip "Vimium not selected — its settings were not written."
elif [[ "$FF_RUNNING" == true ]]; then
    warn "Firefox is running — deferred the Vimium settings (it holds the database open)."
    warn "Close Firefox and re-run. Prefs + userChrome.css were applied."
else
    sync_vimium
fi

# ── Key bindings, via Mozilla's autoconfig mechanism ────────────────────────
# firefox.cfg is the privileged script, autoconfig.js the pref that points at
# it. Neither belongs to the deb, so `apt upgrade firefox` leaves them alone.
FF_DIR="/usr/lib/firefox"
AUTOCONFIG="$REPO/autoconfig"

if [[ ! -d "$AUTOCONFIG" ]]; then
    skip "No autoconfig/ payload — no key bindings to install."
elif [[ ! -x "$FF_DIR/firefox" ]]; then
    # The unpacked application dir exists only for the deb — the transitional
    # package is a shim and the snap's is read-only squashfs.
    skip "Firefox deb not installed — no $FF_DIR to write into (see basic/70-firefox.sh)."
else
    # The .cfg first: a launch that finds the pref pointing at a file that isn't
    # there yet shows a "Failed to read the configuration file" modal.
    if write_root "$FF_DIR/firefox.cfg" 0644 < "$AUTOCONFIG/firefox.cfg" \
       && write_root "$FF_DIR/defaults/pref/autoconfig.js" 0644 < "$AUTOCONFIG/autoconfig.js"; then
        ok "Key bindings ready — Super+h/l tabs, Super+j/k history, Super+1..9 jump, Ctrl+d duplicates."
        skip "They take effect at the next Firefox start. Errors, if any, land in Ctrl+Shift+J."
    else
        warn "Key bindings not installed — the rest of the config still is."
    fi
fi

# ── GPU video decoding, via VA-API ──────────────────────────────────────────
# Firefox decodes video on the GPU by itself, but needs a VA-API backend. libva
# is on every machine; the driver behind it is not, so video lands on the CPU.

# Intel's driver sits outside Mesa and nothing pulls it in — va-driver-all lets
# apt pick iHD vs i965. AMD/nouveau get theirs inside Mesa, so there is nothing.
va_detect() {
    local gpu
    VAAPI_DRIVERS=""; VAAPI_PKG=""
    has_cmd lspci || return 1
    gpu="$(lspci 2>/dev/null | grep -iE 'vga|3d controller|display controller' || true)"
    case "$gpu" in
        *Intel*)              VAAPI_DRIVERS="iHD i965"; VAAPI_PKG="va-driver-all" ;;
        *AMD*|*ATI*|*Radeon*) VAAPI_DRIVERS="radeonsi r600" ;;
        *) return 1 ;;
    esac
}

# By name, not a glob over dri/: Mesa drops radeonsi/nouveau on every machine,
# so "some driver exists" is true everywhere and would skip the Intel install.
va_driver_present() {
    local d
    for d in $VAAPI_DRIVERS; do
        compgen -G "/usr/lib/*/dri/${d}_drv_video.so" >/dev/null 2>&1 && return 0
    done
    return 1
}

if ! va_detect; then
    # NVIDIA lands here too: its bridge needs the proprietary driver underneath.
    skip "No Intel or AMD GPU found (or no lspci) — skipping the VA-API driver."
elif va_driver_present; then
    skip "VA-API driver already installed — video decodes on the GPU."
elif [[ -z "$VAAPI_PKG" ]]; then
    # AMD only: Mesa should have shipped one, and its package name keeps changing.
    warn "No VA-API driver for this GPU — expected one from Mesa (mesa-libgallium)."
elif ! has_cmd apt-get; then
    skip "Not an apt system — install a VA-API driver by hand, or video decodes on the CPU."
elif [[ "$DRY_RUN" == true ]]; then
    would install "$VAAPI_PKG + vainfo (VA-API, so video decodes on the GPU)"
elif ! can_sudo; then
    warn "sudo unavailable (non-interactive) — skipped the VA-API driver ($VAAPI_PKG)."
else
    step "Installing $VAAPI_PKG for GPU video decoding"
    # stdout hidden, stderr kept: a failure explains itself, success is apt noise.
    if sudo apt-get install -y "$VAAPI_PKG" vainfo >/dev/null; then
        ok "VA-API ready — \`vainfo\` lists what the GPU can decode."
        skip "Confirm in about:support › Media › Codec support after a restart."
    else
        warn "Could not install $VAAPI_PKG (try 'sudo apt update' first) — video still decodes on the CPU."
    fi
fi

ok "Firefox config applied — restart Firefox to see it."
