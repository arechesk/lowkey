# lowkey project rules

- Always write the public product name **lowkey**, in lowercase, including menus,
  titles, documentation, landing copy and release names. Preserve existing Swift
  module/type names, bundle ID and stored data paths for compatibility.

- Native macOS browser: AppKit, WebKit, SwiftUI settings. Bundle identifier
  `io.bobuk.lowkey`; use `io.bobuk` for new identifiers.
- Repository: `bobuk-io/lowkey`. Keep documentation in English. Original code is
  0BSD; preserve the adapted release scripts' MIT attribution in THIRD_PARTY_NOTICES.md.
- Never publish credentials, private configuration, profiles or design material.
  `/design/`, `.build/`, `build/` and `dist/` are ignored. No discarded prototypes
  or design experiments belong in git history.
- Do not send synthetic keystrokes while the user works. Do not restart their
  browser or replace its running bundle without permission.
- Tests and screenshots use temporary configuration and random site UUIDs or
  nonpersistent WebKit stores. `LOWKEY_CONFIG` isolates config and input history,
  NOT the default WebKit store. Never use real accounts or pages for screenshots.
- Keep pure logic in LowkeyCore, without AppKit. Run focused tests after code
  changes. Run the full tests for release checks. No hosted CI.
- Releases use the shared kit in Scripts/release; read its README. App facts live
  in release.env and version.env. The canonical kit is ../ting/Scripts/release;
  change it there, test it and sync it here, never fork this copy.
- Scripts/release_next.sh makes a real release. Check readiness with
  Scripts/release/doctor.sh and test safely with Scripts/release/test_kit.sh.
  Public binaries require Developer ID signing, notarization, stapling, local
  tests, a universal ZIP, checksums, GitHub publication, installation at
  /Applications/lowkey.app and restart, and landing deployment. No Sparkle or
  Homebrew support is currently shipped; do not claim it exists.
- Update the landing site in all three locales when a release needs it. See
  ../AGENTS.md and ../landing/docs/updating.md. Never announce an unpublished
  binary as available for download.
