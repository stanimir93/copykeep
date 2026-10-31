# Copykeep

A clipboard history for macOS that works like Windows' Win+V. Press **⌥V** in any app and a
small panel opens next to the text cursor with everything you copied recently. Type to search,
pick one with the arrow keys and press Return, and it's pasted into the app you're in.

**[Download for Mac](https://github.com/stanimir93/copykeep/releases/latest/download/Copykeep.zip)**
(macOS 14 or later, Apple silicon and Intel). Install steps are on the
[download page](https://stanimir93.github.io/copykeep/).

Copykeep used to be called Clipboard Shelf. Its first launch takes over Clipboard Shelf's history
and settings. `scripts/install.sh` also removes the old app; after a download, drag
ClipboardShelf out of Applications yourself and allow Accessibility for Copykeep.

## Features

- **Opens at the text cursor.** ⌥V puts the panel below the caret, or above it when there's no
  room. When an app doesn't report its caret (some Electron apps), the panel opens at the mouse.
  Clicking the menu bar icon opens it under the icon instead.
- **Search as you type.** The search field is focused when the panel opens. Every word you type
  must appear in the clip or the name of the app it came from, and matching clips stay listed
  with the newest first.
- **Tabs:** All, Pinned, Text, Images, Links and Shortcuts. Tab and ⇧Tab switch between them.
- **Text shortcuts.** Type `-email` in any app and it's replaced with your email address. The
  Shortcuts tab lists them; Return pastes one from there too. See [Text shortcuts](#text-shortcuts).
- **Pinned clips** stay at the top of All and are never removed, by the history limit or by Clear.
- **Keeps text, formatting, links, images and files.** Formatting (RTF, HTML) comes back when you
  paste. ⇧Return pastes the text only, without formatting.
- **The same copy twice moves to the top** instead of being added again.
- **Passwords stay out.** Nothing copied in 1Password, Bitwarden, Passwords, Keychain Access,
  KeePassXC, LastPass or Dashlane is kept, nor anything an app marks as concealed or temporary
  ([nspasteboard.org](http://nspasteboard.org) markers).
- **Secrets are hidden in the list.** `API_KEY=…`, `password: …`, tokens recognisable by their
  shape (OpenAI, Stripe, GitHub, Slack, AWS, Google, JWTs), and a lone word mixing upper case,
  lower case and digits (likely a password) show as `••••••••`. They still paste in full.
  Settings can turn this off.
- **Code looks like code.** Clips copied from a terminal or a code editor use a monospaced font.
- **Auto-clear.** Clips copied from chosen apps, such as Bitwarden's browser extension, are
  deleted after a time you pick. All clips can be cleared after a time too (off by default).
  See [Auto-clear](#auto-clear).
- Pause Recording in the menu bar icon's menu stops keeping copies until you turn it back on.
- Light and dark mode follow the system.

## Keys

| Key | Does |
| --- | --- |
| ⌥V | Open or close the panel (change it in Settings) |
| ↑ ↓, Page Up/Down | Move the selection |
| Return or a click | Paste |
| ⇧Return | Paste as plain text |
| ⌘1 – ⌘9 | Paste the first nine |
| ⌘P | Pin or unpin |
| ⌘⌫ | Delete the clip or shortcut |
| ⌘N | New text shortcut |
| ⌘E | Edit the selected shortcut (Shortcuts tab) |
| Tab, ⇧Tab | Next or previous tab |
| Esc | Clear the search, or close |
| ⌘, | Settings |

Hovering a clip shows pin and delete buttons. Right-clicking the menu bar icon gives Pause
Recording, Clear History and Settings.

## Accessibility access

Pasting into another app means pressing ⌘V for you, and opening at the text cursor means asking
the app where its cursor is. Both need **System Settings › Privacy & Security › Accessibility**.
The app asks on its first launch. Without it, choosing a clip copies it and you press ⌘V
yourself, and the panel opens at the mouse.

`build.sh` signs with the `Local Self-Signed` certificate when this Mac has it, so the permission
survives rebuilds. With an ad hoc signature, macOS forgets it after every build: remove the app
from the Accessibility list and add it again.

## Install

Download it from the [download page](https://stanimir93.github.io/copykeep/). The app isn't
notarized, so the first launch needs **System Settings › Privacy & Security › Open Anyway**.

To build from source instead you need macOS 14 and Xcode or the Command Line Tools.

```sh
scripts/install.sh            # builds, installs /Applications/Copykeep.app, launch at login, starts it
scripts/install.sh --dest ~/Applications
```

`./build.sh` alone builds `build/Copykeep.app`.

## Releasing

The download page is `docs/` on GitHub Pages, and its button links to the latest release's
`Copykeep.zip`. To publish a new version, bump `VERSION`, commit, and run
`scripts/release.sh`: it builds a universal app, zips it and creates the `v<VERSION>` release.
`scripts/screenshots.sh` redraws the page's screenshots from a made-up history.

## Auto-clear

Settings › Auto-clear lists apps whose clips are deleted after a set time (1 minute to 7 days),
counted from the last copy or paste. If the clip is still on the clipboard then, the clipboard is
emptied too. Pinned clips are never deleted. All clips, at the top of the section, does the same
for every clip whatever app it came from; it's Never until you pick a time. A clip that both
cover goes at the shorter time. A rule for a password manager (Bitwarden, 1Password,
Passwords…) lets its copies into the history for that long; without one they're never kept.

The rules are in `~/.config/copykeep/auto-clear.json`. Settings writes it, and edits made by hand
or by a script are picked up within 10 seconds:

```json
{
  "allClips": 1440,
  "rules": [
    { "app": "browser-extension:bitwarden", "name": "Bitwarden (browser extension)", "minutes": 15 },
    { "app": "com.bitwarden.desktop", "name": "Bitwarden", "minutes": 15 }
  ]
}
```

`app` is the app's bundle ID (`osascript -e 'id of app "Mail"'` prints it). `name` is what Settings
and the panel show. `minutes` is any whole number of minutes. `allClips` is the minutes for every clip; leave it
out for Never.

`browser-extension:bitwarden` is for copies made in Bitwarden's browser extension, which come
from the browser app itself. With that rule on, Copykeep asks the browser through Accessibility
which page has the focus when something is copied. In Chrome, Edge, Brave, Arc, Vivaldi and
Opera, Bitwarden's popup and side panel have the address `chrome-extension://<Bitwarden's
extension ID>/…`. In Zen, Firefox and Safari an extension's ID differs per install, so Copykeep
goes by the page title "Bitwarden". Copies from the web vault (`vault.bitwarden.com`,
`vault.bitwarden.eu`) count too. A copy Bitwarden makes while you're on another site (the
one-time code after autofill) isn't recognised. Chromium browsers only share page details with
apps that ask, so the rule switches that on (`AXManualAccessibility`) for the browser you copy in.

## Text shortcuts

A shortcut is a short trigger, such as `-email`, and the text it stands for. Type the trigger in
any app and Copykeep deletes it and pastes the text. It fires only at the start of a word (after a
space, punctuation or nothing), so `re-email` stays as typed. A sign in front, like `-` or `;`,
keeps a trigger from firing in normal writing. When one trigger ends another (`-mail` and
`-email`), the longer one wins.

Make them in the panel's Shortcuts tab (⌘N, or New in its footer) or in Settings › Shortcuts,
which also turns expanding off. Expanding needs Accessibility, like pasting.

The shortcuts are in `~/.config/copykeep/shortcuts.json`. The app writes it, and edits made by
hand or by an agent are picked up the next time you type:

```json
{
  "shortcuts": [
    { "trigger": "-email", "text": "you@example.com" },
    { "trigger": ";sig", "text": "Best,\nYour Name" }
  ]
}
```

`trigger` is what you type and `text` is what replaces it; `\n` starts a new line. Triggers are
case-sensitive, and the first of two shortcuts with the same trigger is used. The text goes in
through the clipboard, which gets its old contents back half a second later, and isn't added to
the history. Keys typed while it goes in are held back and follow it.

## Where the history is kept

`~/Library/Application Support/Copykeep`: `history.json` lists the clips, and `blobs/` holds
each clip's clipboard data (`<id>.plist`) and an image's thumbnail (`<id>.png`). It stays on this
Mac. Settings › History sets how many unpinned clips to keep (200 by default).

Only these formats are read from the clipboard: plain text, RTF, RTFD, HTML, web archive, URL,
file URL, PNG, TIFF, JPEG and HEIC. Reading every format an app offers can make apps such as
Excel render each one. Images are kept as PNG, and a TIFF is added again when pasting. A single
format over 30 MB is skipped.

## Command line

```sh
CS=/Applications/Copykeep.app/Contents/MacOS/Copykeep
$CS --dump                         # the history as JSON (what the panel lists)
$CS --snapshot panel.png dark zens # draw the panel offscreen, dark, searching "zens"
$CS --snapshot s.png tab=shortcuts # draw it on the Shortcuts tab
$CS --snapshot-settings s.png dark # draw the Settings window offscreen
$CS --expire                       # delete the clips past their auto-clear time, print them
$CS --register-login-item          # launch at login on (--unregister-login-item: off)
```
