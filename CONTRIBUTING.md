# Contributing to Glade

Changes are welcome as pull requests: bug fixes, new known locations, focused improvements and documentation. For a larger feature, open an issue describing the problem and the behaviour you propose before you start.

## The rule that matters most

Nothing may weaken the safety policy. Glade's users trust it with their disk, so a change that lets it remove, move, list or show an AI anything it couldn't before needs an issue and a discussion first, whatever it saves. In particular:

- Protected areas (`Safety/ProtectedZones.swift`) can grow freely. Making one smaller, or making a locked one unlockable, needs a reason in the pull request.
- Only `Cleaner` removes anything, and it checks every path against `Protection` again at the moment of removal. Don't add another way to delete, move or empty.
- Scanners never enter protected areas, and never open files except where the code already says why (duplicate fingerprints, a worktree's `.git` pointer).
- An AI only ever suggests findings by identifier. It gets no tools, and Glade checks its reply against the same rules as the levels.

## Build

You need macOS 26 or later and Xcode 26. Open `Glade.xcodeproj` in Xcode or Bitrig, or build from the command line:

```sh
xcodebuild -project Glade.xcodeproj -scheme Glade build
```

Almost everything lives in the Swift package in `Packages/GladeKit`, which builds without Xcode's project:

```sh
cd Packages/GladeKit
swift build
.build/debug/glade --help
```

[AGENTS.md](AGENTS.md) describes the layout and the rules the code follows.

## The safety test

`swift test` in `Packages/GladeKit` runs the project's one automated test. It builds a fake home folder full of things that must survive (SSH keys, agent memory, iCloud files, a repository, a photo library hidden in a cache, links that lead out of the home folder) and checks that the policy refuses them and the cleaner leaves them alone. Run it before every pull request that touches `Safety/`, `Storage/` or the assistant, and add a case to it when you find a way something could slip through.

## Adding a known location

Known locations are `LocationRule` entries in `Packages/GladeKit/Sources/GladeKit/Storage/Catalog.swift`, grouped by kind. Each entry needs:

- `paths`, using `~` for the home folder, `$TMP` and `$CACHE` for the per-user temporary folders, and `*` within one path component. Keep them as narrow as the tool's own documentation allows.
- `recovery`: how it comes back, which must be true for every match. `automatic` if the tool rebuilds it by itself, `redownload` if it is fetched again on next use, `reinstall` if someone has to reinstall or rebuild, `permanent` if it doesn't come back. In the pull request, say how you know: the tool's documentation, or what you did to watch it come back.
- `risk`: err toward caution. `safe` only if losing it costs nothing but time; `caution` if it holds anything a person set up or might miss; `personal` for anything that is theirs.
- `owner` and `blockWhileRunning` when the app keeps the folder open, and `idleDays` when recent use means it's in use.
- `detail`: one plain sentence a non-technical person understands, saying what it is and what happens after removal.

If you aren't sure, leave it out. Then scan your own Mac and check the finding is sized and described correctly:

```sh
.build/debug/glade scan --category <category>
.build/debug/glade plan --level careful --all
```

## Look at a screen

The interface is in `Packages/GladeKit/Sources/GladeUI` and renders without launching the app:

```sh
.build/debug/glade snapshot list
.build/debug/glade snapshot window --section storage --out /tmp/storage.png
.build/debug/glade snapshot storage --dark
```

Snapshots use sample findings unless you add `--live`. Check a visual change in both appearances.

## Try a change in the app

Only one copy of Glade runs at a time. Quit the installed copy from the menu bar, then open the app you built. The built app's executable answers the same commands: `Glade.app/Contents/MacOS/Glade doctor`.

## Pull requests

Keep a change focused and leave unrelated work alone. Describe the result a user would see, what you checked and anything you could not check. Do not include signing keys, credentials, scan results, logs from your Mac or built app bundles.

Changes to these boundaries need discussion first:

- The safety policy, as above.
- Glade's only network use is Sparkle's update check; asking an AI goes through the person's own tool and account.
- No file contents are sent to an AI.
- No analytics, crash reporting or server.

## Licence

Glade is licensed under the [GNU General Public License, version 3](LICENSE). Contributions submitted for inclusion are under the same licence. Submit only work you have the right to contribute, and identify any third-party material and its licence.
