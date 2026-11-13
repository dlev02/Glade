#!/bin/bash
# Signs a Glade.app from the inside out with the given codesign options: Sparkle's
# helpers first, then the framework, then the app.
# No --deep: it would apply one set of options to everything.
# The app carries one entitlement, Location, which the hardened runtime needs before macOS
# will tell it the Wi-Fi network's name (App/Glade.entitlements; see make_release.sh).
# Glade's engine is a local Swift package linked into the executable, so there is no
# other framework or helper inside the app to sign.
#   script/sign_app.sh path/to/Glade.app --force --sign IDENTITY [--options runtime] [--timestamp]
set -euo pipefail
app="$1"; shift
[ -d "$app/Contents/MacOS" ] || { echo "sign_app: $app isn't an app" >&2; exit 1; }
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for helper in "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc" "$sparkle/Autoupdate" "$sparkle/Updater.app"; do
  if [ -e "$helper" ]; then
    codesign "$@" --preserve-metadata=entitlements "$helper"
  fi
done
codesign "$@" "$app/Contents/Frameworks/Sparkle.framework"
# Anything else in Frameworks would ship unsigned by this script, so stop instead.
for item in "$app/Contents/Frameworks"/*; do
  [ "$(basename "$item")" = "Sparkle.framework" ] || { echo "sign_app: unexpected $item; sign it here first" >&2; exit 1; }
done
codesign "$@" --entitlements "$(dirname "$0")/../App/Glade.entitlements" "$app"
