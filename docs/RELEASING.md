# Releasing Glade

A release is a Developer ID signed, notarized DMG and ZIP attached to a GitHub release, plus a signed update feed (`appcast.xml`) at the repository root on `main`. Installed copies read the feed from `https://raw.githubusercontent.com/dlev02/Glade/main/appcast.xml`.

## Before the first release

### Make the update signing key

This was done on 11 November 2026: the key is in the login Keychain under the account `glade`, backed up to `~/Developer/Glade-signing/sparkle-private-key.txt`, and `SUPublicEDKey` is in `App/Info.plist`. The steps stay here for a new Mac or a lost key. Glade only starts Sparkle when the feed URL and the key are both present, and `make_release.sh` refuses to run without them. Keep a second copy of the backup somewhere off this Mac.

1. Build once (Bitrig or `xcodebuild -project Glade.xcodeproj -scheme Glade build`) so Sparkle's tools are downloaded. They are under `SourcePackages/artifacts/sparkle/Sparkle/bin` in the build's DerivedData folder.
2. Make the key in the login Keychain under Glade's own account, and print its public half:

   ```sh
   generate_keys --account glade
   generate_keys --account glade -p
   ```

   Don't use Sparkle's default account: that key belongs to another project.
3. Add the public half to `App/Info.plist`, beside `SUFeedURL`:

   ```xml
   <key>SUPublicEDKey</key>
   <string>…the printed key…</string>
   ```

4. Back up the private key outside this repository, and keep a second copy off this Mac (a password manager, for example):

   ```sh
   mkdir -p ~/Developer/Glade-signing
   generate_keys --account glade -x ~/Developer/Glade-signing/sparkle-private-key
   chmod 600 ~/Developer/Glade-signing/sparkle-private-key
   ```

   Lose this key and every installed copy needs a download by hand, because the app requires a signed feed and nothing falls back to accepting an unsigned one. Restore it with `generate_keys --account glade -f <file>`.
5. Confirm the backup matches the Keychain by signing the same file both ways and comparing; EdDSA signatures are deterministic:

   ```sh
   sign_update --account glade some-file
   sign_update -f ~/Developer/Glade-signing/sparkle-private-key some-file
   ```

6. Commit `App/Info.plist`. From then on, `make_release.sh` checks that the Keychain's key matches the one in the built app.

### Walk through it as a stranger

Before calling the first release released, start at the GitHub release page on a Mac user account that has never had Glade, with no help from an agent:

1. Download the DMG. Its name should say what it is (`Glade-0.1.0.dmg`).
2. Open it, drag Glade to Applications, and open it from there. Gatekeeper should open it without a warning.
3. Follow setup: Full Disk Access, notifications and an AI. Note every point where you had to know something the app didn't tell you, and fix it before publishing.
4. Run a scan, a Careful clean and an undo. Check `glade logs --problems` afterwards.
5. Link the command (`ln -s /Applications/Glade.app/Contents/MacOS/Glade /usr/local/bin/glade`, or any folder on `PATH`) and check `glade doctor` and `glade quit <some app>` work from the signed copy. The link needs nothing at signing time: it points at the same signed executable, which switches to the command line when it is started under the name `glade`.

Then do the update test below with a second build.

## Steps

1. Set the version and a higher build number on the Glade target. Sparkle compares the build number, so one that doesn't rise never reaches anyone.

   ```sh
   xcrun xcodeproj setting set --target Glade MARKETING_VERSION 0.1.1
   xcrun xcodeproj setting set --target Glade CURRENT_PROJECT_VERSION 2
   ```

2. Add the version's section to `CHANGELOG.md`, in the form `## 0.1.1 — 2026-12-01`. Its text becomes the release notes in the update window, so write it for people.
3. Commit. The script refuses to run with uncommitted changes, so the release is what's in the repository.
4. Run `script/make_release.sh <version>`. It checks this Mac first (certificate, `SUPublicEDKey`, version, bundle identifier, build number against the published feed), builds with only the package versions pinned in `Package.resolved`, signs from the inside out with hardened runtime and secure timestamps, checks the app carries no entitlements and no local paths, notarizes and staples the app, makes the ZIP, makes, signs, notarizes and staples the DMG, writes checksums to `dist/release/<version>`, and writes the signed `appcast.xml` at the repository root. It uploads nothing.
5. Create the GitHub release tagged `v<version>` and attach the DMG, the ZIP and their `.sha256` files. Use the changelog section as the notes.
6. Only then commit and push `appcast.xml`. Pushing it first would point installed copies at a download that doesn't exist yet.
7. Download the published DMG and check it against its checksum. Open it and confirm the drag-to-Applications window looks right in both light and dark appearance.

## After any change to updating

Install the previous release, publish the new one, and watch the installed copy find it, download it and install it when it quits. Check `glade logs` for the `[update]` lines. A release that can't update is worse than no release.

### Testing an update without publishing it

To prove a build can be updated to before it goes out, or when a firewall on the test Mac holds the download from GitHub, serve the update from the same Mac. Glade only starts its updater from an Applications folder, so install the older build there first.

```sh
mkdir /tmp/feed && cp dist/release/<version>/Glade-<version>.zip /tmp/feed/
dist/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --account glade \
  --download-url-prefix http://127.0.0.1:8765/ -o /tmp/feed/appcast.xml /tmp/feed
(cd /tmp/feed && python3 -m http.server 8765 --bind 127.0.0.1) &
osascript -e 'quit app "Glade"'
defaults write io.github.dlev02.glade SUFeedURL http://127.0.0.1:8765/appcast.xml
open /Applications/Glade.app
```

Choose **Check for Updates…** in the Glade menu and install the update; it relaunches into the new version. Then put things back and stop the server:

```sh
defaults delete io.github.dlev02.glade SUFeedURL
kill %1
```

The update is still verified against the signing key, so this exercises everything except GitHub's hosting. If `glade logs` shows "An error occurred while downloading the update" after exactly a minute, something on the Mac is holding the connection to `github.com` or `release-assets.githubusercontent.com`; a firewall app such as Little Snitch waits for an answer to its prompt.

## What the script needs on this Mac

- The Developer ID Application certificate, in the login Keychain. The team is set at the top of the script, or with `GLADE_TEAM`.
- The notarization key stored by `asc auth login`. No credentials are kept in this repository.
- The Sparkle signing key (above), with its public half in `App/Info.plist`.
- `uvx`, which runs `dmgbuild` for the install window. The window's layout is `script/dmg_settings.py` and its background is `Resources/DMG/background.png` and `background@2x.png`, drawn by `script/make_dmg_background.swift`. The wash is a middle green so the icon names read in both light and dark Finder windows.

## Signing

`script/sign_app.sh` signs Sparkle's helpers, then the framework, then the app. The app carries one entitlement, `com.apple.security.personal-information.location` (`App/Glade.entitlements`), because the hardened runtime blocks Location without it, and macOS only tells an app the Wi-Fi network's name with Location access. Otherwise it needs none: it isn't sandboxed, and under the hardened runtime starting other programs (agent tools, `git`, `xcrun simctl`), reading the disk with Full Disk Access and asking for notifications don't require one. Programs Glade starts run under their own signatures. The hardened runtime only asks for entitlements to load unsigned code, use JIT, accept `DYLD_` variables, be debugged, or reach the camera, microphone, location, contacts, calendars, photos or other apps through Apple Events. Quitting an app goes through `NSRunningApplication.terminate()`, which isn't expected to need the Automation entitlement; the stranger walkthrough confirms that on the signed copy with `glade quit`. If a change ever needs one of those entitlements, add an entitlements file, pass it in `sign_app.sh`, and change the check in `make_release.sh` to expect exactly that entitlement.

The engine, interface and command line are a local Swift package (`Packages/GladeKit`) linked statically into the app's one executable, so there is nothing else to sign. `sign_app.sh` stops if anything besides Sparkle appears in `Contents/Frameworks`.
