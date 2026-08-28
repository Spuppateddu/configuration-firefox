// Firefox — portable configuration prefs.
//
// A hand-curated subset of prefs.js containing ONLY durable settings (toolbar
// layout, theme, fonts, privacy/behaviour choices) — no personal data. Firefox
// reads user.js at every startup and applies these over prefs.js, so it is safe
// to copy between machines and safe to keep in a public repo. Deliberately
// excluded from the original prefs.js: telemetry/normandy/nimbus client IDs, the
// contextual-services context ID, safebrowsing + region timestamps, session and
// build bookkeeping, and every "hasMigrated…" flag.
//
// Note: values here are re-applied on every launch. To change one permanently on
// a machine, edit it here (and re-run ./setup.sh) rather than only in the UI.

// ── Toolbar layout (the main "same layout" pref) ─────────────────────────────
// The Bitwarden ({446900e4-…}) and Wappalyzer button placements are kept even
// though those two add-ons are installed by hand (see extensions.conf) — an
// unknown widget id is simply ignored, and keeping them means the toolbar looks
// right on a machine where you did install them.
user_pref("browser.uiCustomization.state", "{\"placements\":{\"widget-overflow-fixed-list\":[],\"unified-extensions-area\":[\"ublock0_raymondhill_net-browser-action\"],\"nav-bar\":[\"back-button\",\"forward-button\",\"stop-reload-button\",\"customizableui-special-spring1\",\"vertical-spacer\",\"urlbar-container\",\"customizableui-special-spring2\",\"downloads-button\",\"unified-extensions-button\",\"_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action\",\"wappalyzer_crunchlabz_com-browser-action\",\"_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action\"],\"toolbar-menubar\":[\"menubar-items\"],\"TabsToolbar\":[\"firefox-view-button\",\"tabbrowser-tabs\",\"new-tab-button\",\"alltabs-button\"],\"vertical-tabs\":[],\"PersonalToolbar\":[\"personal-bookmarks\"]},\"seen\":[\"developer-button\",\"screenshot-button\",\"ipprotection-button\",\"ublock0_raymondhill_net-browser-action\",\"_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action\",\"wappalyzer_crunchlabz_com-browser-action\",\"_d7742d87-e61d-4b78-b8a1-b469842139fa_-browser-action\"],\"dirtyAreaCache\":[\"nav-bar\",\"vertical-tabs\",\"PersonalToolbar\",\"toolbar-menubar\",\"TabsToolbar\",\"unified-extensions-area\"],\"currentVersion\":23,\"newElementCount\":2}");
// Doubles as the chrome toggle: chrome/userChrome.css reads #PersonalToolbar's
// collapsed state to decide whether the whole toolbar area is shown, and
// Ctrl+Shift+B is what flips it. Pinned to "never" here so every launch starts
// chromeless — the toggle then lasts for the session.
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("sidebar.visibility", "hide-sidebar");
// Firefox's built-in "Compact" density (0 = normal, 1 = compact, 2 = touch).
// Customize Toolbar only offers it once you've used it, but the pref always
// works. chrome/userChrome.css tightens the chrome further on top of this.
user_pref("browser.uidensity", 1);
user_pref("sidebar.revamp.defaultLauncherVisible", false);

// ── Theme ────────────────────────────────────────────────────────────────────
// Gruvbox is a static theme from AMO, installed by policy (extensions.conf).
// Naming its ID here makes it the active theme instead of the built-in default.
user_pref("extensions.activeThemeID", "{08d5243b-4236-4a27-984b-1ded22ce01c3}");
user_pref("browser.theme.toolbar-theme", 0);           // 0 = dark chrome
user_pref("layout.css.prefers-color-scheme.content-override", 0); // 0 = tell pages "dark"

// ── Custom userChrome.css ────────────────────────────────────────────────────
// Required for Firefox to load chrome/userChrome.css at startup — that is what
// hides the whole toolbar area until you toggle it back with Ctrl+Shift+B.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// ── Fonts ────────────────────────────────────────────────────────────────────
// The size of ordinary page text: font.default.x-western below is sans-serif,
// so this — not font.size.monospace — is what an unstyled page lands on.
// Cascadia Code NF has a 0.518em x-height, so 12 reads close to nominal; drop to
// 11 if it now reads too big. Nothing downstream
// depends on this number, unlike the desktop sizes, so it is the cheapest one in
// the repo to change — but keep font.size.monospace.x-western in step with it.
user_pref("font.size.variable.x-western", 12);

// All three slots, on purpose: this desktop renders its text in one family (the
// i3 config in ~/.i3rc and ~/.alacritty/alacritty.toml name the same Cascadia
// Code NF), and a browser left on the distro serif / sans-serif was the last
// thing on screen showing a different face. Yes, that means an ordinary page
// with no font stack of its own comes out fixed-width — that is the intent.
// Drop the two lines below to get the stock proportional defaults back for page
// text while keeping <code>/<pre> monospace.
//
// Cascadia Code NF, and the browser is where that choice is easiest to justify:
// the web leans on bold for emphasis, so the everyday face needs a real Bold
// sitting above the regular — a family whose heaviest face IS the everyday one
// would flatten every <strong>, <b> and heading into body text. Cascadia ships
// four real faces (Regular, Bold, Italic, Bold Italic), so it keeps that apart.
//
// 50-fonts-cursor.sh installs it from upstream's own release, taking the four
// static TTFs (NOT the variable build — that one reports no style=Bold, which
// costs you the real bold this whole choice was about). NF is Microsoft's own
// Nerd-Font build: the same face plus the icon range, so the whole machine needs
// exactly one family and nothing sits behind these prefs.
//
// A page that wants icons ships its own icon font in its own stack, and that
// stack still wins here (see the note below); these prefs only decide what the
// *text* of an unstyled page lands on.
user_pref("font.name.serif.x-western", "Cascadia Code NF");
user_pref("font.name.sans-serif.x-western", "Cascadia Code NF");
user_pref("font.name.monospace.x-western", "Cascadia Code NF");
// Which of the two above a page with no font-family of its own lands on.
user_pref("font.default.x-western", "sans-serif");
// 13, Firefox's own default. Only <pre>/<code> and pages that ask for monospace
// use this — ordinary page text is font.size.variable.x-western above. Keep the
// two in step, or code blocks end up a different size from the body around them.
user_pref("font.size.monospace.x-western", 13);
// Note: a site that names its own font stack still wins. Forcing ours would
// mean browser.display.use_document_fonts=0, which is NOT set here — it also
// kills icon fonts, so half the web loses its glyphs.

// ── Zoom ─────────────────────────────────────────────────────────────────────
// One zoom for the whole web, not one per site: a blank new tab has no host, so
// it used to inherit the zoom of whatever tab opened it. 0.9 is the default.
user_pref("browser.zoom.siteSpecific", false);

// ── New tab / startup ────────────────────────────────────────────────────────
// A blank new tab: no Firefox Home feed, no top sites, no sponsored anything.
user_pref("browser.startup.homepage", "chrome://browser/content/blanktab.html");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.showSearch", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

// ── Tabs ─────────────────────────────────────────────────────────────────────
user_pref("browser.tabs.groups.smart.userEnabled", false);   // no AI tab grouping
user_pref("browser.tabs.hoverPreview.showThumbnails", false);

// ── Tab unloading ────────────────────────────────────────────────────────────
// Linux ships this false, so background tabs are NEVER dropped and a heavy web
// app (Teams, Outlook) holds its GB until you close it. On = discard on low RAM.
user_pref("browser.tabs.unloadOnLowMemory", true);
// How long a tab must sit untouched before it may be discarded. 10min → 3min.
user_pref("browser.tabs.min_inactive_duration_before_unload", 180000);
// Trigger at 20% free instead of the stock threshold, which fires far too late
// to help. Only lever the Linux watcher (it reads /proc/meminfo) exposes.
user_pref("browser.low_commit_space_threshold_percent", 20);
// bfcache: default -1 lets Firefox keep ~8 whole back/forward pages in RAM.
// 2 keeps instant Back for the last two, drops the rest.
user_pref("browser.sessionhistory.max_total_viewers", 2);

// ── GPU video decoding ───────────────────────────────────────────────────────
// Skips Firefox's own hardware blocklist, which new Intel silicon is often not
// on yet. install.sh installs the driver. Drop this if video comes out torn.
user_pref("media.hardware-video-decoding.force-enabled", true);

// ── Less background work ─────────────────────────────────────────────────────
// The session is written to disk every 15s — a constant trickle for a file only
// read after a crash. 60s costs at worst the last minute of tabs.
user_pref("browser.sessionstore.interval", 60000);
// Closed tabs kept for Ctrl+Shift+T, each holding its page state in RAM (25, 5).
user_pref("browser.sessionstore.max_tabs_undo", 5);
user_pref("browser.sessionstore.max_windows_undo", 1);

// Telemetry, Normandy and Shield studies each wake on a timer and hit the network.
// toolkit.telemetry.enabled is locked in release builds — uploadEnabled is the one.
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);

// Search engines are NOT synced — the file that holds them (search.json.mozlz4)
// is a whole-list replacement, so it would drop any engine you added on this
// machine. Pick your default once in Settings › Search; it then stays put.

// ── Passwords / autofill: Bitwarden owns this, Firefox stays out ─────────────
user_pref("signon.rememberSignons", false);
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);
user_pref("privacy.clearOnShutdown_v2.formdata", true);

// ── No speculative network chatter ───────────────────────────────────────────
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.http.speculative-parallel-limit", 0);
