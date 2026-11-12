#!/bin/zsh
# Builds a Glade release in dist/release/<version>: a Developer ID signed, notarized and
# stapled DMG and ZIP, SHA-256 checksums, and a signed Sparkle appcast.xml at the
# repository root that points at the release's tag. It uploads nothing.
# See docs/RELEASING.md.
#
#   script/make_release.sh 0.1.0
#
# Set MARKETING_VERSION and a higher CURRENT_PROJECT_VERSION on the Glade target first,
# add the version's section to CHANGELOG.md, and commit. Needs, on this Mac:
#   - The Developer ID Application certificate for the team below, in the login Keychain.
#   - The notarization key that `asc auth login` stores in the keychain.
#   - The Sparkle private key, in the login Keychain under the account `glade`, and its
#     public half as SUPublicEDKey in App/Info.plist. macOS may ask once to let
#     generate_appcast read it. Lose this key and every installed copy needs a download
#     by hand.
#   - uvx, to run dmgbuild for the install window.
set -euo pipefail

cd "${0:A:h:h}"

die() { print -u2 "make_release: $*"; exit 1; }
step() { print "\n== $*"; }

version="${1:-}"
[[ "$version" =~ '^[0-9]+(\.[0-9]+)+$' ]] || die "usage: make_release.sh <version>, for example 0.1.0"

team="${GLADE_TEAM:-7BVMD7TA97}"
account=glade
bundle_id=io.github.dlev02.glade
tag="v$version"
repo=https://github.com/dlev02/Glade
feed=https://raw.githubusercontent.com/dlev02/Glade/main/appcast.xml
out="dist/release/$version"
project=Glade.xcodeproj/project.xcproj
dmg="Glade-$version.dmg"
zip="Glade-$version.zip"

setting() { sed -n "s/.*\"$1\": \"\\([^\"]*\\)\".*/\\1/p" "$project" | head -1; }
# The version's section of the changelog, without its heading. It ends at the next
# version's heading or at the end of the file, so the oldest section keeps its last line.
notes() { awk -v heading="## $version " 'index($0, heading) == 1 { on = 1; next } on && /^## / { exit } on { print }' CHANGELOG.md; }

# Everything that needs setting up on this Mac fails here, not after a long build.
git diff --quiet HEAD -- || die "tracked files have changes: commit first, so the release is what's in the repository"
[[ "$(setting MARKETING_VERSION)" == "$version" ]] || die "MARKETING_VERSION isn't $version"
# Development builds have their own identifier (…glade.dev), so that running one never
# replaces the permissions people gave the released app. Releases must use the real one.
[[ "$(setting 'PRODUCT_BUNDLE_IDENTIFIER\[config=Release\]')" == "$bundle_id" ]] || die "PRODUCT_BUNDLE_IDENTIFIER isn't $bundle_id"
build=$(setting CURRENT_PROJECT_VERSION)
[[ "$build" =~ '^[0-9]+$' ]] || die "the build number must be a whole number, not $build"
print -r -- "$(notes)" | grep -q '[^[:space:]]' || die "CHANGELOG.md has no section for $version"
[[ "$(plutil -extract SUFeedURL raw App/Info.plist)" == "$feed" ]] || die "SUFeedURL isn't $feed"
info_key=$(plutil -extract SUPublicEDKey raw App/Info.plist 2>/dev/null || true)
[[ -n "$info_key" ]] || die "App/Info.plist has no SUPublicEDKey, so the app would never update; see docs/RELEASING.md"
(( $+commands[uvx] )) || die "uvx isn't installed; it runs dmgbuild"
[[ -f Resources/DMG/background.png && -f Resources/DMG/background@2x.png ]] || die "the install window's background is missing from Resources/DMG"

identity=$(security find-identity -v -p codesigning | awk -v team="($team)" '/Developer ID Application/ && index($0, team) { print $2; exit }')
[[ -n "$identity" ]] || die "no Developer ID Application certificate for team $team in the Keychain"

# Sparkle compares CFBundleVersion, so a build number that doesn't rise never reaches anyone.
published=$(curl -fsL "$feed" 2>/dev/null | sed -n 's|.*<sparkle:version>\([0-9]*\)</sparkle:version>.*|\1|p' | sort -n | tail -1 || true)
if [[ -n "$published" ]] && (( build <= published )); then
  die "build $build isn't higher than the published build $published"
fi

rm -rf "$out"
mkdir -p "$out"
app="$out/Glade.app"

step "Building"
# xcodebuild rather than an editor's own builder, so a release is built the same way
# on any Mac and runs on both Apple silicon and Intel. The engine, interface and
# command line come from the local package in Packages/GladeKit and are linked into
# the one executable; only the versions pinned in the project's Package.resolved are
# used, so a release never picks up a dependency nobody reviewed.
xcodebuild -project Glade.xcodeproj -scheme Glade -configuration Release -derivedDataPath dist/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build >"$out/build.log" 2>&1 \
  || { tail -30 "$out/build.log"; die "the build failed; see $out/build.log"; }
built=dist/DerivedData/Build/Products/Release/Glade.app
ditto "$built" "$app"
[[ "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" == "$version" ]] || die "the built app isn't version $version"
[[ "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" == "$bundle_id" ]] || die "the built app isn't $bundle_id"
[[ ! -e "$app/Contents/MacOS/Glade.debug.dylib" ]] || die "this is a debug build"
archs=$(lipo -archs "$app/Contents/MacOS/Glade")
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || die "the app isn't universal: $archs"

sparkle_bin=dist/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
[[ -x "$sparkle_bin/generate_appcast" ]] || die "Sparkle's tools weren't found beside the build"
public_key=$("$sparkle_bin/generate_keys" --account "$account" -p) || die "no Sparkle key for account $account in the Keychain"
[[ "$public_key" == "$(plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist")" ]] || die "the Keychain's Sparkle key doesn't match SUPublicEDKey"

step "Signing with Developer ID"
script/sign_app.sh "$app" --force --options runtime --timestamp --sign "$identity"
codesign --verify --deep --strict "$app" || die "the app's signature doesn't verify"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for code in "$app" "$sparkle" "$sparkle/Autoupdate" "$sparkle/Updater.app" "$sparkle"/XPCServices/*.xpc(N); do
  details=$(codesign -dvv "$code" 2>&1)
  [[ "$details" == *"Authority=Developer ID Application"* && "$details" == *"TeamIdentifier=$team"* ]] || die "$code isn't signed with team $team's Developer ID"
  [[ "$details" == *"(runtime)"* ]] || die "$code has no hardened runtime"
  [[ "$details" == *"Timestamp="* ]] || die "$code has no secure timestamp"
done
# Glade needs no entitlements: it isn't sandboxed, and running other tools, reading the
# disk and asking for notifications are all allowed under the hardened runtime without
# one. Any entitlement here arrived by accident, and get-task-allow fails notarization.
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)
[[ "$entitlements" != *"<key>"* ]] || die "the app carries entitlements it shouldn't: $entitlements"
# The source mentions /Users/ on purpose (log scrubbing, Bitrig's folders), so look for
# this Mac's own folders instead: a build path that leaked would start with one of them.
for local_path in "$HOME/" "$PWD/"; do
  if strings "$app/Contents/MacOS/Glade" | grep -qF "$local_path"; then die "the executable contains a local path ($local_path)"; fi
done

notarize() {
  local result="$out/notary-${1:t}.json"
  asc notarization submit --file "$1" --wait --output json >"$result" || true
  local verdict; verdict=$(plutil -extract data.attributes.status raw "$result" 2>/dev/null || print unknown)
  if [[ "$verdict" != "Accepted" ]]; then
    local id; id=$(plutil -extract data.id raw "$result" 2>/dev/null || print "")
    [[ -n "$id" ]] && asc notarization log --id "$id" || true
    die "notarizing ${1:t} came back $verdict"
  fi
}

step "Notarizing the app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/submission.zip"
notarize "$out/submission.zip"
rm "$out/submission.zip"
xcrun stapler staple -q "$app"
xcrun stapler validate -q "$app"
spctl --assess --type execute "$app" || die "Gatekeeper refuses the stapled app"

step "Making the ZIP"
# ditto keeps the framework's symlinks, which a plain zip would break.
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$zip"

step "Making and notarizing the DMG"
# The install window: the app on the left, Applications on the right, an arrow between.
uvx dmgbuild -s script/dmg_settings.py -D app="$app" -D background=Resources/DMG/background.png Glade "$out/$dmg" >"$out/dmg.log" 2>&1 \
  || { tail -20 "$out/dmg.log"; die "dmgbuild failed; see $out/dmg.log"; }
codesign --sign "$identity" --timestamp "$out/$dmg"
notarize "$out/$dmg"
xcrun stapler staple -q "$out/$dmg"
xcrun stapler validate -q "$out/$dmg"
spctl --assess --type open --context context:primary-signature "$out/$dmg" || die "Gatekeeper refuses the DMG"

step "Signing the appcast"
# Only the ZIP goes in: Sparkle installs from it, and the DMG is for people. The changelog
# section becomes the release notes. The feed lives at the repository root on main, so a
# release can never be published without it; push it only after the release's files are up.
stage="$out/appcast-stage"
mkdir "$stage"
ln "$out/$zip" "$stage/$zip"
print -r -- "$(notes)" >"$stage/${zip:r}.md"
"$sparkle_bin/generate_appcast" --account "$account" --embed-release-notes --maximum-deltas 0 \
  --download-url-prefix "$repo/releases/download/$tag/" --link "$repo/releases/tag/$tag" \
  -o "$PWD/appcast.xml" "$stage" | tee "$out/appcast.log"
rm -rf "$stage"
xmllint --noout appcast.xml
grep -q "url=\"$repo/releases/download/$tag/$zip\"" appcast.xml || die "the appcast's enclosure doesn't point at $tag"
grep -q "<sparkle:version>$build</sparkle:version>" appcast.xml || die "the appcast doesn't offer build $build"
grep -q 'sparkle:edSignature=' appcast.xml || die "the download isn't signed in the appcast"
grep -q 'sparkle-signatures:' appcast.xml || die "the appcast itself isn't signed, and the app requires that"

step "Checksums"
(cd "$out" && shasum -a 256 "$dmg" >"$dmg.sha256" && shasum -a 256 "$zip" >"$zip.sha256" && cat ./*.sha256)

print "\nReady in $out. Nothing has been uploaded. To publish:"
print "  1. Create the release tagged $tag with: $dmg  $dmg.sha256  $zip  $zip.sha256"
print "  2. Then commit and push appcast.xml to main. Installed copies see the update once it is there."
