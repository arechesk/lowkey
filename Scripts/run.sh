#!/usr/bin/env bash
# Builds and starts a development copy. Below 0.5, replaces the local install.
# Set LOWKEY_CONFIG=/tmp/x.json to use an isolated config and skip installation.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"

quit_lowkey() {
  swift - <<'SWIFT'
import AppKit

let copies = NSRunningApplication.runningApplications(withBundleIdentifier: "io.bobuk.lowkey")

func waitForExit(seconds: TimeInterval) {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while copies.contains(where: { !$0.isTerminated }) && ProcessInfo.processInfo.systemUptime < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
}

for app in copies { _ = app.terminate() }
waitForExit(seconds: 5)
for app in copies where !app.isTerminated { _ = app.forceTerminate() }
waitForExit(seconds: 2)
if copies.contains(where: { !$0.isTerminated }) {
    fputs("Could not quit all lowkey copies. The installed bundle was not replaced.\n", stderr)
    exit(EXIT_FAILURE)
}
SWIFT
}

if [[ -z "${LOWKEY_CONFIG:-}" && "$MARKETING_VERSION" =~ ^0\.[0-4]\.[0-9]+$ ]]; then
  installed=/Applications/lowkey.app
  stage=$(mktemp -d /Applications/.lowkey-development.XXXXXX)
  swapped=0
  cleanup() {
    if [[ "$swapped" == 0 && ( -e "$stage/previous" || -L "$stage/previous" ) ]]; then
      if [[ -e "$installed" || -L "$installed" ]] || ! mv -- "$stage/previous" "$installed"; then
        echo "Previous bundle preserved at $stage/previous" >&2
        return
      fi
    fi
    rm -rf -- "$stage"
  }
  trap cleanup EXIT

  # Build before stopping anything. Keeping both bundles on the same volume lets
  # the final moves rename directories rather than copying over the running app.
  APP_OUTPUT_DIR="$stage" "$ROOT/Scripts/package_app.sh" "${1:-debug}"
  quit_lowkey
  if [[ -e "$installed" || -L "$installed" ]]; then
    mv -- "$installed" "$stage/previous"
  fi
  mv -- "$stage/lowkey.app" "$installed"
  swapped=1
  open "$installed"
else
  "$ROOT/Scripts/package_app.sh" "${1:-debug}"
  app="${APP_OUTPUT_DIR:-"$ROOT/build"}/lowkey.app"
  if [[ -n "${LOWKEY_CONFIG:-}" ]]; then
    "$app/Contents/MacOS/Lowkey" >/dev/null 2>&1 &
  else
    open "$app"
  fi
fi
