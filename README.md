# Lowkey

A minimal macOS browser built with AppKit and the system WebKit. No tabs, no permanent address bar. Saved sites open by alias, each with its own persistent profile.

**Source preview · macOS 14 or later · Apple Silicon and Intel.** No public binary release yet. Build with Swift 6.2 / Xcode 26 or later.

## Install from source

```sh
git clone https://github.com/bobuk-io/lowkey.git
cd lowkey
Scripts/run.sh
```

Local builds are ad-hoc signed. Do not disable Gatekeeper to install an unknown
binary. The first official binary will be Developer ID signed, notarized and stapled.

## Build and run

```sh
Scripts/run.sh                     # debug build → build/Lowkey.app → launch
Scripts/package_app.sh release      # release build, signed ad hoc by default
swift test                         # pure-logic tests
```

The selected blue-window icon is bundled from `Assets/AppIcon.png`. `APP_IDENTITY` can select a signing certificate for packaging.

Releases use the shared bobuk.io release kit in [`Scripts/release`](Scripts/release/README.md), the same scheme as Ting, Splash Finish and HAScS; app facts live in `release.env`. The source is public, while the first binary release is still pending:

```sh
APP_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=… Scripts/release.sh   # test, universal build, notarize, install in /Applications
Scripts/release/doctor.sh                                                         # read-only readiness check
```

`Scripts/release_next.sh` prepares and publishes the first binary as 0.1.0 (with
`docs/releases/v0.1.0.md`), then increments patch versions for later releases.
Do not run it as a check: it signs, notarizes, installs, publishes and deploys the
landing site. Check readiness with `Scripts/release/doctor.sh` and test the kit
safely with `Scripts/release/test_kit.sh`.

To use an isolated configuration for manual checks:

```sh
LOWKEY_CONFIG=/tmp/lowkey-test.json Scripts/run.sh
```

This relocates settings and input history, not WebKit's default profile. Use separate site IDs and a local mock server for website-data checks. Quit the development app before rebuilding its bundle.

## Windows

- Launch without a deep link: the address/alias prompt, without restoring old windows.
- One live window per saved site. Reopening an alias brings back its current page, including a hidden window.
- Each saved site remembers its window position and size across closing and app restarts. Geometry uses AppKit's per-site frame autosave key, keyed by the stable site ID, so renaming its alias keeps it. The window saves its frame when moved, resized, hidden, closed or when Lowkey quits. Temporary fullscreen geometry does not replace the saved normal frame.
- The custom strip is 20 pt high with a 2 pt accent line. Only cross/Q on the left and **back · start page · forward** on the right. No fullscreen button.
- Drag the strip to move the window; resize normally. System fullscreen remains available from View or ⌃⌘F.
- A typed alias activates its saved window. A raw URL entered in a saved-site window opens a new ordinary window, leaving the saved site unchanged.
- A raw URL entered in an ordinary window replaces that window's page; ⌘↩ requests a new ordinary window.
- **⌘⇧L — Open Location in This Profile…:** enter a URL or alias to load it in the current window, keeping its exact WebKit profile, cookies and sign-in state. This also works in sign-in/popup windows. Unlike ⌘L, it never switches to the alias’s profile or creates an ordinary window, even with ⌘Return. The explicit location bypasses external-link and sign-in-window routing once; later links keep the usual site policy. Use this for sign-in flows that need a URL opened in the existing profile.

| Window | Click left control / ⌘W | ⌘-click / ⇧⌘W |
| --- | --- | --- |
| Saved site | Hide, keep page running | Close, keep profile |
| Ordinary window | Close, keep default profile | Close |

Saved-site cross changes to a round Q-like glyph while ⌘ is held. Ordinary windows show Q by default. Closing a window never clears cookies. Quit Lowkey to stop all pages.

### Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘L | Address or alias prompt |
| ⌘⇧L | Open a URL or alias in this window’s current profile |
| ⌘N | Prompt for a new ordinary window |
| ⌘← / ⌘→ | Back / forward, except while editing text |
| ⌘[ / ⌘] | Back / forward menu commands |
| ⇧⌘H | Configured start page (initial URL for an ordinary window) |
| ⌘R | Reload; retry a failed address |
| ⌘W / ⇧⌘W | Hide or close / close site |
| ⌘, | Settings |
| ⌘Q | Quit Lowkey |

The prompt accepts http/https URLs and bare hosts. Alias resolution and suggestion search also try Russian/Ukrainian ↔ US keyboard-layout variants, as in Ting: `рф` matches `HA`, `пщщпду` matches Google in history. Original-spelling matches come first. The field text and valid typed URLs are never silently rewritten. Bare hosts use HTTPS; loopback uses HTTP. There is no search-engine fallback yet. Suggestions come from saved aliases and the last **1,000 unique submitted entries**, not every visited page. Use arrows and Return to choose; hover a history entry and click × to forget it. Entering it again restores it as newest. Aliases themselves are removed in Settings, not by deleting history.

## Settings and profiles

Settings contains saved sites, appearance and history controls. Site fields are alias, optional title, start URL, external-link policy and extra origins. Changes save when valid. Alias matching ignores case; profile identity uses a stable UUID, so renaming an alias keeps its sign-in.

- Each saved site has its own `WKWebsiteDataStore` identified by its UUID.
- All ordinary windows use the shared persistent `default` store.
- Popups share the parent site's store.
- Removing a saved site asks for confirmation and deletes its profile. Closing a site does not.
- Default config: `~/.config/lowkey/config.json`.
- Input history: `~/Library/Application Support/Lowkey/history.json`.

Example site:

```json
{
  "sites": [
    {
      "id": "B943B7D1-190E-43CB-AFAE-4058D93274E3",
      "alias": "HA",
      "title": "Home Assistant",
      "startURL": "https://homeassistant.local",
      "externalLinks": "defaultBrowser",
      "extraOrigins": ["https://ha.example.com", "*.nabu.casa"]
    }
  ],
  "appearance": { "mode": "page" }
}
```

The initial origin (scheme, host, port) and optional extra origins count as internal. Subdomains are external unless allowed. `*.example.com` matches subdomains, not the bare host. Clicked external links either stay in Lowkey or open in the default browser, according to the site's setting. Redirects and script navigation are not sent outside automatically, to avoid breaking sign-in. Ordinary links with `target="_blank"` do not create tabs.

## Appearance

Modes: **Page** (default), System, Light and Dark. Light/dark palettes are independent. Presets include Amber, Sage, Ocean, Terracotta, Dracula, Nord, Catppuccin, Gruvbox, Solarized, Tokyo Night, One Light/Dark and Rosé Pine. Panel and accent colors are editable.

Page mode reads WebKit's derived page background and chooses the light or dark palette **per window**. In-page background changes are observed. A short debounce and luminance dead band reduce flicker. A page's `theme-color` is a fallback only; System is used when no usable color is available. Pages dominated by images, video or canvas may not be classified like their visible pixels: this is background detection, not screenshot analysis.

Lowkey never forces the site's CSS appearance or recolors its content. The address prompt follows its parent window; settings use System in Page mode.

## Deep links

```sh
open 'lowkey://HA/open'       # create or bring back the saved-site window
open 'lowkey://HA/toggle'     # visible → hide; hidden/minimized → show; unopened → create
open 'lowkey://*/toggle'      # toggle all existing saved-site windows as a group
open 'lowkey://HA/reload'
open 'lowkey://HA/back'
open 'lowkey://HA/forward'
open 'lowkey://HA/start'      # configured initial page
open 'lowkey://HA/hide'
open 'lowkey://HA/close'      # release live page, retain profile
```

The literal wildcard `lowkey://*/toggle` hides all existing saved-site windows if any is visible, or shows them all if none is visible. It neither opens unused saved sites nor touches ordinary/default-profile windows.

`lowkey://` opens the prompt. Names are case-insensitive. Unknown aliases are shown in the prompt. Arbitrary JavaScript, clicks and other page automation are intentionally not exposed by deep links in this version.

## Sign-in and limits

Lowkey provides separate sign-in/popup windows sharing the parent profile, with the provider's host visible. WebKit-created popups retain opener/window-close behavior. Recognized provider navigations from saved sites can open in a separate window and return their callback to the site window.

**Google and other providers may reject embedded user agents.** Separate windows do not guarantee OAuth support for arbitrary websites. Real-provider sign-in and complex callback flows have not been validated. Lowkey does not impersonate Safari, bypass certificate validation or transfer Safari cookies. This remains an explicit first-version limitation.

Basic downloads, uploads, JavaScript dialogs and HTTP authentication are implemented. No extensions, password manager integration or automatic updates. A signed/notarized distribution pipeline is prepared, but no public binary has been released yet.

## Layout

- `Sources/LowkeyCore`: pure configuration, aliases, URLs, input history, link policy, palette and page-background classification.
- `Sources/Lowkey`: AppKit windows/menus, WebKit and SwiftUI settings.
- `Tests/LowkeyCoreTests`: local logic tests.
- `Tests/LowkeyAppTests`: AppKit window-placement tests using invisible windows and random IDs.
- `Scripts`: local build, icon and bundle assembly.

## Privacy, support and removal

Lowkey has no accounts, analytics or backend. Websites receive ordinary WebKit
traffic for their profile. Camera/microphone access is requested only for website
requests; uploads and downloads use native dialogs. See [SECURITY.md](SECURITY.md)
for profile isolation, permissions and sign-in limits.

Report reproducible problems through [GitHub Issues](https://github.com/bobuk-io/lowkey/issues).
Include macOS and Lowkey versions, but omit cookies, private URLs and configuration.
For a minimal reproduction, use a local page and an isolated configuration.

To uninstall, remove saved sites in Settings first if you want their website data
deleted, quit Lowkey and delete Lowkey.app. Settings and input history are retained:
`~/.config/lowkey/config.json` and `~/Library/Application Support/Lowkey/history.json`.
Removing the app alone does not delete WebKit data, including the ordinary-window
profile. Never delete unrelated WebKit data or another browser's profiles.

## License

Original code is [0BSD](LICENSE). Adapted release scripts retain MIT attribution;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
