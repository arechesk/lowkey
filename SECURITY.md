# Security

## Reporting a vulnerability

Do not post cookies, credentials, private URLs, website data or local configuration
in a public issue. Contact the maintainer through the GitHub profile linked from
https://github.com/bobuk-io/lowkey, or use GitHub private vulnerability reporting
if it is enabled. Include the version, macOS version and a minimal local reproduction.

## Security model

- lowkey uses the macOS system WebKit. Keep macOS up to date for WebKit security fixes.
- Each saved site uses a persistent `WKWebsiteDataStore` identified by a UUID.
  Ordinary windows share the default persistent store. Popups share their opener's
  store. Profiles separate website state; they are not a separate OS user or an
  application sandbox. The application itself is not sandboxed.
- Websites receive ordinary browser traffic, including cookies belonging to their
  profile. lowkey has no analytics, account service or application backend. It does
  not transfer cookies from Safari or other browsers.
- Saved sites and appearance are in `~/.config/lowkey/config.json`. Submitted
  addresses/aliases are stored in `~/Library/Application Support/Lowkey/history.json`
  (up to 1,000 unique entries). These may contain private addresses or URL query
  parameters; do not publish them. The history is not a record of every page visited.
- `LOWKEY_CONFIG=/tmp/test.json` isolates configuration and input history, not the
  default WebKit store. Automated/manual tests use random site IDs or nonpersistent
  stores and local test pages; never use real sign-in data for screenshots.
- An external-link policy is navigation convenience, not an origin security boundary.
  Redirects and script navigation can stay in the profile to support authentication.
  Command-Shift-L explicitly loads an address in the current profile once, without
  permanently allowing that origin. Recognized sign-in pages and real WebKit popups
  share the profile. Embedded-browser OAuth restrictions may still block login.
- TLS uses WebKit's normal validation. lowkey does not accept invalid certificates,
  impersonate Safari or bypass identity-provider restrictions.
- Camera and microphone usage strings and entitlements are present for website
  requests. macOS and WebKit mediate access. Uploads use file pickers; downloads
  use a save dialog. lowkey does not need Accessibility or Input Monitoring.
- `lowkey://alias/command` controls a saved site's window/navigation. It cannot run
  JavaScript or shell commands. Another local application may invoke these links;
  do not treat possession of an alias as authentication.
- Closing a window retains cookies. Removing a saved site in Settings requests
  deletion of its website-data profile. Uninstalling the application alone does
  not erase configuration, history or WebKit data.

## Release safety

Public binaries are Developer ID signed, notarized, stapled and checked with
`Scripts/release/check_privacy.swift` before publication. Local source builds are
ad-hoc signed unless a Developer ID identity is specified. There is no automatic
updater or Homebrew cask; download updates from GitHub Releases and replace only
the app. The product name is always lowercase: lowkey. The shared release kit
in `Scripts/release/` runs local tests, prepares the universal ZIP and checksums,
installs the verified app, then publishes it. Never publish signing keys, notary
credentials, local profiles or the ignored `design/` directory.
