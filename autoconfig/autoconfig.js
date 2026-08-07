// Firefox autoconfig bootstrap.
//
// Installed to /usr/lib/firefox/defaults/pref/autoconfig.js by this repo's
// ./install.sh. Its only job is to point Firefox at firefox.cfg, which sits next
// to the binary in /usr/lib/firefox/ and holds the actual code.
//
// This is Mozilla's own enterprise mechanism (the same one CCK2 and fx-autoconfig
// build on), not a patched browser: nothing in /usr/lib/firefox that the deb
// owns is modified, so `apt upgrade firefox` leaves both files alone — dpkg only
// removes files it shipped. A `dpkg --purge` does take the directory, which is
// why this lives in an idempotent installer and not a one-off: it runs again on
// every update (best-linux-environment's ./boot.sh calls it at every boot) and
// puts the file straight back.
//
// These must be pref() — the *default* branch — and not user_pref(). A file
// under defaults/pref/ is read before any profile exists; a user_pref() there is
// discarded.

pref("general.config.filename", "firefox.cfg");

// Firefox's legacy .cfg format is byte-shifted by 13 ("ROT-13 for files").
// 0 turns that off so the file stays readable, greppable and diffable in git.
pref("general.config.obscure_value", 0);

// Runs firefox.cfg with chrome privileges instead of in the restricted sandbox.
// Required: the sandbox has no Services and no access to browser windows, which
// is exactly what binding a key needs. Blast radius is one file, root-owned and
// root-writable only — see the header of firefox.cfg.
pref("general.config.sandbox_enabled", false);
