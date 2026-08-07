# configuration-firefox

My Firefox configuration: the look and feel, the add-ons, Vimium's key mappings,
and browser-level key bindings. One idempotent `./install.sh` applies all of it.

That is the **whole** scope — it is not a profile sync. Bookmarks, history,
cookies, logins, sessions, containers and search engines stay yours and are never
touched.

```sh
git clone https://github.com/Spuppateddu/configuration-firefox.git ~/linux-configuration/firefox
ln -s ~/linux-configuration/firefox ~/.firefox
~/.firefox/install.sh
```

That run asks you which add-ons you want, as a checkbox list, before it applies
anything. Normally you don't do it by hand at all:
[best-linux-environment](https://github.com/Spuppateddu/best-linux-environment)
clones this repo, links it and runs the installer — and asks the same question
up front with all its others, so the installer doesn't have to.

## What's in here

| File | What it carries |
| --- | --- |
| `install.sh` | applies everything below; safe to re-run, and it is re-run at every boot |
| `user.js` | curated prefs — toolbar layout, Gruvbox theme, blank new tab, no autofill/password manager, no speculative prefetch |
| `chrome/userChrome.css` | hides the whole browser UI; **Ctrl+Shift+B** toggles it back |
| `extensions.conf` | the add-on catalogue, as `id\|amo-slug\|label\|default` |
| `vimium-settings.json` | Vimium's key mappings and its Gruvbox hint/vomnibar CSS |
| `autoconfig/` | `firefox.cfg` + `autoconfig.js` — the tab key bindings, installed into `/usr/lib/firefox` |

## Installing

```
./install.sh                    apply everything, asking which add-ons to install
./install.sh --extensions=ublock-origin,vimium-ff
./install.sh --extensions=all   every add-on in extensions.conf
./install.sh --extensions=none  no add-on policy at all
./install.sh --dry-run          preview, change nothing (or DRY_RUN=true)
```

**Run it as yourself, never with `sudo`.** It asks for sudo on its own for the
two root-owned files (`/etc/firefox/policies/policies.json` and
`/usr/lib/firefox/`). Under `sudo` your `$HOME` is `/root`, so your profile is
invisible to it and only the system-wide half would land — it refuses rather than
do that quietly.

It writes five things and nothing more: `user.js` and `chrome/` into the active
profile, the add-on policy into `/etc/firefox/policies/policies.json`, Vimium's
own row in `storage-sync-v2.sqlite`, and the two autoconfig files into
`/usr/lib/firefox`. Every one of them is compared first, so a machine that is
already up to date is not written to at all — no backups, no mtime changes. That
is what makes it safe on a boot cron. Anything it does replace is backed up next
to itself first.

**It does not install Firefox.** The browser has to be the deb from
packages.mozilla.org, not Ubuntu's snap: the snap's `desktop-launch` wrapper
overwrites `XCURSOR_PATH` (so the cursor theme breaks over every Firefox window)
and its application directory is read-only squashfs (so the key bindings have
nowhere to live). That install — apt pin, snap-profile migration, snap removal —
is `basic/70-firefox.sh` in best-linux-environment. With no `firefox` on PATH
this script says so and exits.

## Choosing your add-ons

`extensions.conf` is a catalogue, not an install list. Which of its entries are
actually installed is a **question**, asked as a checkbox list — every add-on
visible at once, arrow keys to move, space to tick, `a` for all and `n` for none:

```
══ Firefox — which add-ons to install ══
   Installed by Firefox's own policy and kept updated from AMO. Unticking one
   never uninstalls it — do that in about:addons.
   ↑/↓ move · space toggle · a all · n none · enter confirm

 ❯ [x] uBlock Origin — content blocker
   [x] Vimium — vim keys for the web
   [x] Gruvbox — the browser theme user.js selects
   [ ] Bitwarden — password manager (needs your account)
   [ ] Wappalyzer — what a site is built with
```

`install.sh` asks it itself, so a clone of this repo on its own is a complete
thing to run. best-linux-environment's `./setup.sh` asks the *same* list up front
with all its other questions and passes the answer down as `--extensions=…`,
which is what stops you being asked twice in one install.

**Where the question comes from, in order:** an explicit `--extensions=`; else the
list above, whenever there is a terminal to draw it on; else — the boot cron, a
pipe, CI — the last answer you gave; else the entries whose `default` column is
`1`. It never blocks on a prompt that nobody is there to answer.

The answer is remembered in `~/.cache/firefox-config/extensions` (one amo slug
per line — this machine's choice, so deliberately not a file in this repo), and
the list opens pre-ticked on it, so pressing enter straight through changes
nothing. That is also what stops the boot cron from re-enabling something you
unticked. An empty answer is a real answer — "none" — and is recorded as one.

Unticking one **never uninstalls it**. The policy stops declaring the add-on and
Firefox leaves what is installed alone — remove it in `about:addons` if that is
what you meant. Vimium is the one entry with a side effect: unticked, its
settings row is not written either.

Add a new add-on by appending a line to `extensions.conf` — its ID (from
`about:debugging`), its addons.mozilla.org slug, a label, and `1`/`0` for whether
it should be on by default.

**Add-ons are installed by policy, not by copying `.xpi` files.** `install.sh`
generates `/etc/firefox/policies/policies.json` with `installation_mode:
normal_installed`, so Firefox installs each add-on at its next start and then
keeps it updated from AMO itself — and you can still disable or remove one by
hand. The deb reads that path directly (and Ubuntu's snap read it through its
`etc-firefox` system-files interface), so it works either way. Writing it needs
`sudo`; on a cron path with no terminal it is skipped with a warning, and the
rest of the config still applies.

Vimium's options live in `chrome.storage.sync`, which Firefox keeps as one JSON
blob per extension in `storage-sync-v2.sqlite`; `install.sh` writes that row
directly (creating the database if this is a brand-new profile). It only does so
while Firefox is **closed** — it holds that database open.

## The chromeless UI

**The browser UI is hidden, and `Ctrl+Shift+B` toggles it.** Firefox ships no
pref and no key for "hide the toolbar", and binding a custom hotkey to one needs
a `userChrome.js` loader in Firefox's *application* directory — which was
read-only squashfs back when this was a snap. So `userChrome.css` borrows a
toggle Firefox already has: `Ctrl+Shift+B` flips
`browser.toolbars.bookmarks.visibility`, which lands on `#PersonalToolbar` as a
`collapsed` attribute. The bookmarks bar itself is never rendered — it is used
purely as a state bit, and the whole `#navigator-toolbox` is driven from it.

Unlike `F11` this leaves the window alone, so i3 keeps tiling it and the status
bar stays put. `Ctrl+L` still reveals the toolbar for as long as the urlbar holds
focus; **hovering does not**, so the chromeless look never breaks by accident.
`user.js` pins the pref to `never`, so each launch starts chromeless and the
toggle lasts for the session.

## Tab keys, bound at the browser level

| Chord | Does |
| --- | --- |
| **Super+l** / **Super+h** | next / previous tab, wrapping at the ends |
| **Super+k** / **Super+j** | forward / back in this tab's history |
| **Super+1** … **Super+8** | jump to tab 1..8 |
| **Super+9** | jump to the last tab |
| **Ctrl+d** | duplicate the current tab |

Horizontal moves between tabs, vertical moves through history, so `h/j/k/l` is
the whole navigation set on one hand. This replaces `Ctrl+Tab` /
`Ctrl+Shift+Tab`, which are awkward to reach. The jump and duplicate bindings
used to be Vimium mappings and moved here.

### The peek

With the chrome hidden a tab switch was invisible — the page changed and nothing
said which tab you had landed on. So every navigation key above **flashes the
header for one second** and folds it away again. **Closing a tab** does the same,
for the same reason: it drops you on a neighbouring tab unannounced.

`firefox.cfg` sets `ble-peek` on the window's root element and a timer removes
it; all the appearance is in `userChrome.css`, which already knows how to unfold
the toolbox for `Ctrl+L`. Pressing another key restarts the timer instead of
stacking a second one, so holding `Super+l` down leaves the header up for a
second after the *last* press.

| Pref (`about:config`) | |
| --- | --- |
| `ble.keys.peekMs` | the duration in ms — default `1000`, `0` turns the peek off and keeps the keys. Read per press, so a change applies to the very next keystroke. |

The peek is click-through: the toolbox is overlaying the page for that second, so
a click aimed at a link near the top of the page still reaches the page rather
than landing on a tab. Pinned open with `Ctrl+Shift+B` the toolbar is in flow and
stays clickable — the rule excludes that state.

Back and forward are matched by **command** id rather than key id, which is what
makes a `Super+j` at the very start of the history flash nothing: `Browser:Back`
is disabled there, a `<key>` naming a disabled command never fires, so there is
nothing to announce. The trade is that the same commands reached another way
(`Alt+Left`, the back button) peek too — which is the behaviour you want anyway.
Duplicating a tab deliberately does not peek: it lands you on a copy of the page
you were already looking at. Add `Browser:DuplicateTab` to `PEEK_COMMANDS` in
`firefox.cfg` if you disagree.

Closing a tab is hooked differently again — on the **`TabClose` event**, not on a
command id. Firefox spreads tab closing over several commands (`cmd_close` for
`Ctrl+w`, `cmd_closeWindow`, one per tab-context-menu entry) and the mouse routes
through none of them, whereas every close of every kind dispatches `TabClose` on
the tab, which bubbles to the document. So `Ctrl+w`, `Ctrl+F4`, middle-clicking a
tab, the tab's X, *Close Tab* / *Close Other Tabs* / *Close Tabs to the Right* in
the context menu and Vimium's `x` all peek, from one listener. Batch closes fire
one event per tab and the timer restarts rather than stacks, so they are a single
flash. Dragging a tab out into its own window is excluded (`detail.adoptedBy` is
set — you are looking at the new window, not this one). For the keys only, put
`cmd_close` in `PEEK_COMMANDS` and drop the `TabClose` listener.

`Browser:Back` and `Browser:Forward` ship `disabled="true"` and Firefox flips
that as the session history changes; a `<key>` naming a disabled command doesn't
fire, so Super+j/k correctly do nothing at either end of the history.

**Super, because i3 owns Alt.** `~/.i3rc/config` sets `$mod` to `Mod1` = Alt, so
Alt+h/j/k/l (focus) and Alt+1..9 (workspaces) are grabbed at the X level and
Firefox never sees them — which is also why Firefox's own `key_selectTab1..8`,
bound to `modifiers="alt"`, have never done anything on this desktop. `Mod4` is
bound to nothing anywhere, so Super is free. On Linux it reaches Gecko as the
`meta` modifier.

**Browser level, not Vimium.** Vimium is a content script, so it isn't running on
`chrome://` or `about:` pages, `addons.mozilla.org`, `view-source:`, the PDF
viewer, or while focus is in the address bar. That last set is the problem:
`user.js` points the new tab at `chrome://browser/content/blanktab.html`, so
**every fresh tab** was a page where the old Vimium tab keys did nothing. A
`<key>` in the browser's own keyset has none of those holes — same mechanism
`Ctrl+T` and `Ctrl+W` come through — and each one is `reserved`, so a page that
captures keys can't swallow it either.

`firefox.cfg` mirrors the architecture `browser-sets.js` already uses: the `<key>`
elements carry no handler, and one delegated `command` listener on the keyset
switches on the id that fired. Keys that map onto a command Firefox already ships
(`Browser:NextTab`, `Browser:PrevTab`, `Browser:DuplicateTab`) just name it and
need no code at all; only "select tab N" needs a handler, because Firefox
dispatches that one off the key's own id and `key_selectTab1`… are taken.

**Every window gets the keys, whichever way it was opened.** The keys are added
per window, so the hook that finds each new window is the whole ballgame.
`browser-delayed-startup-finished` alone was not enough — windows opened with
**Ctrl+N** came up without any of these bindings while `firefox --new-window`
ones worked — so the primary hook is now `domwindowopened` plus the window's
`load` event, the one route every chrome window takes. Gecko also compiles a
window's `<key>` elements into a cached handler chain and does not notice later
appends, so the keyset is re-inserted afterwards to force that rebuild.

To check it: **`ble.keys.windowsPatched`** in `about:config` counts the windows
patched since the browser started, and `ble.keys.lastError` holds anything
`firefox.cfg` threw. A chord that reaches web content is proof the key is missing
from that window — every one is `reserved`, so a live one never gets past chrome.

**Ctrl+d costs you "bookmark this page."** Firefox binds that chord to
`addBookmarkAsKb`, and two `<key>`s claiming one chord resolve in an order
nothing documents — so the built-in is *removed* rather than shadowed.
Bookmarking is still on the star button, the Bookmarks menu and `Ctrl+Shift+O`.
To take Ctrl+d back, drop the `ble_key_duplicateTab` row and the `FREED_KEYS`
entry in `firefox.cfg`. Vimium's side is handled too: its default `<c-d>` is a
half-page scroll, so `vimium-settings.json` carries `unmap <c-d>` and nothing
else.

## What is left alone

Everything not in the table above. `install.sh` does not touch bookmarks or
history (`places.sqlite`), cookies, logins or keys (`logins.db`, `key4.db`),
sessions and tabs, form history, per-site permissions, containers,
file/`mailto:` handlers, search engines, or window state — and it never disables,
removes or reconfigures an add-on you installed yourself, because the policy
names only the ones you selected.

Search engines are the one thing you set by hand: Firefox keeps them in a single
`search.json.mozlz4` blob, so syncing it would replace the whole list. Pick your
default once in Settings › Search.

`user.js` and `chrome/` are files Firefox only ever reads and this repo owns
outright — **managed**, not seeded — so they are re-applied on every run and take
effect at the next restart. To refresh the payload from a machine you've
customised, copy those files back out of your profile into this repo.
