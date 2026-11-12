# Glade

A macOS 26+ app that shows what is using the Mac's storage, memory, processors and graphics, and clears it safely. It lives in a window and the menu bar; its executable is also the `glade` command line and an MCP server (`glade mcp`).
Swift 6, SwiftUI; Sparkle 2 and Swift Argument Parser are the only dependencies. GPL-3.0. Not sandboxed (it needs Full Disk Access and runs other tools), hardened runtime, no entitlements.
Sparkle's update check is the only network use of Glade's own, and asking an AI goes through the person's own command-line tool ([PRIVACY.md](PRIVACY.md)).

## Layout

- `App/`: a thin host. `main.swift` decides between the app and the command line (started as `glade`, or with a command name as the first argument, it runs `CLI`). `GladeApp` and `AppDelegate` start the shared `AppModel`; `UpdateController` wraps Sparkle.
- `Packages/GladeKit`: everything else, a Swift package that builds without the Xcode project.
  - `GladeKit`: the engine, no UI. `Safety/` (`ProtectedZones`, `Protection`), `Storage/` (`Catalog` of known locations, `Scanners/`, `ScanEngine`, `Planner`, `Cleaner`), `System/` (readings, apps, simulators, alerts), `Agent/` (`Assistant`, `StoragePrompt`, `Guide`, `Providers/`), `Core/` (`Config`, `Log`, `DiagnosticReport`, `Brand`, `Shell`).
  - `GladeUI`: the interface. Screens read `AppModel` and call its methods; none talk to the engine directly.
  - `GladeCLI`: every command, and `MCPServer`. Anything a person can do in the window has a command.
  - `glade`: the development executable, the same commands without the app.
  - `Tests/GladeKitTests/SafetyTests.swift`: the one automated test.

## Build

- The app inside Bitrig: `bitrig build -destination 'generic/platform=macOS'`. Otherwise: `xcodebuild -project Glade.xcodeproj -scheme Glade build`.
- The package: `cd Packages/GladeKit && swift build`, then `.build/debug/glade <command>`.
- The safety test: `swift test` in `Packages/GladeKit`. Run it after any change to `Safety/`, `Storage/` or `Agent/`.

## Look at it

- A screen: `glade snapshot <screen> --out /tmp/x.png` (`glade snapshot list` for names; `--dark`, `--live` for this Mac's last scan, `window --section storage`). Read the PNG; check light and dark.
- The engine: `glade doctor`, `glade scan --category <c>`, `glade plan --level careful --all`, `glade clean --level careful` (a dry run), `glade logs --problems`.
- Never pull Glade in front of what the person is doing. Check screens with `glade snapshot`, not `glade show` (use `glade show <section> --background` if the running app must change section), and start a build with `open -g`.
- Only one copy of the app runs at a time; quit the installed one first. A copy outside an Applications folder never starts the updater.

## Rules that aren't negotiable

- **The safety policy.** `ProtectedZones` and `Protection` decide what Glade may touch. Never narrow a zone, unlock a locked one or loosen `verdict(forRemoving:)` without the owner agreeing first. When you add a way something could slip through, add the case to `SafetyTests` in the same change.
- **Only `Cleaner` deletes, trashes or empties anything**, and it takes finding identifiers from a scan, never paths, and checks each path with `Protection` again at the moment of removal.
- **Uninstalling has its own, narrower rule.** `Protection.verdict(forUninstalling:)` allows only a real `.app` folder (not a link, no `.` or `..`) directly in `/Applications` or `~/Applications` or one plain folder below, on the same disk, not sealed, SIP-restricted or under `/System`, with a bundle identifier that isn't Glade's or one macOS keeps. `Cleaner` checks the identifier is unchanged and the app isn't running, trashes the app first, then each data folder only if `verdict(forRemoving:)` allows it; one that fails stays and is named in the receipt. Apps are never auto-selected and always go to the Trash.
- **A folder picked in the whole-disk sheet** becomes a finding through `PickedFolder` only if `verdict(forRemoving:)` allows it, is removed by `Cleaner` like any other, and is never saved with the scan. It is window-only: no command or MCP tool may take a path.
- **Scanners never enter protected zones**, ask `Protection.canScan` before measuring, and read names, sizes and dates only. Opening a file needs a reason the owner agreed to (duplicate fingerprints, a worktree's `.git` pointer).
- **Models never get tools.** Every provider runs with its tools, plugins, MCP servers and memory off, in an empty temporary folder. Their output is parsed, and every suggestion is checked with `Planner.mayAutoSelect` and the plan's level before it counts.
- **No file contents to a cloud AI** unless the person turns on `assistant.shareExcerpts`, which nothing uses yet. Prompts are built only in `StoragePrompt` and `MacDescription`.
- **One logging helper.** Log through `Log` with a category, at every boundary that can fail or surprise, naming the thing and keeping the error code. No `print` outside the command line's own output. `Redactor` scrubs the home folder and secrets; never log prompt or reply text.
- **No network code** beyond Sparkle and the local Ollama connection to 127.0.0.1. No analytics, crash reporting or server; problem reports are a file the person attaches themselves.
- **A new known location** in `Catalog` states how it comes back, and errs toward caution: when unsure, `caution`, or leave it out.

## Code style

- 2-space indent. One main type per file, named after it, with only its small helpers beside it. No SwiftUI previews.
- `GladeUI` and the app default to `MainActor` isolation.
- British spelling in comments and interface copy (colour, centre, licence).
- Interface copy is plain language for non-technical people, with as little helper text as the layout allows. No jargon ("regenerable", "artifacts").

## Commits and releases

- One user-facing change per commit. The title is plain English a user would understand, such as "Show memory per simulator and suggest shutting down idle ones".
- Commits, pull requests and files carry the author's name only, with no tool, assistant or AI attribution.
- Releases follow `docs/RELEASING.md`. The top section of [CHANGELOG.md](CHANGELOG.md) becomes the release notes shown in the update window, so write it for people who use the app.
- When behaviour, network use or permissions change, update [README.md](README.md) and [PRIVACY.md](PRIVACY.md) in the same commit. A new protected zone, AI provider or anything sent to an AI always counts.
