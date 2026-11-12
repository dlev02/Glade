import Foundation

/// The briefing for AI agents that drive Glade from outside: Claude Code, Codex,
/// Cursor and others calling the command line or the MCP server. Printed by
/// `glade guide` and sent as the MCP server’s instructions.
public enum Guide {
  public static let text = """
    # Glade: a briefing for agents

    Glade shows what is using this Mac’s storage, memory, processors and graphics, and clears it safely. You drive it; it does the looking and the removing. You never need to run `rm`, `du`, `find`, `kill` or `ps` yourself, and you shouldn’t: Glade knows which locations are safe and enforces rules you can’t see from a shell.

    Every command prints JSON with `--json`. Nothing is removed without `--confirm`.

    ## The safety model (so you can explain it to the person)

    - **Protected areas are invisible.** SSH/GPG/cloud credentials, Keychains, password managers, agent memory/skills/settings, Photos libraries, Messages, Mail, Notes, iCloud Drive, Dropbox/Google Drive/OneDrive, browser profiles and `.git` folders are never scanned, listed or removable. You won’t see them in any output. `glade protect check <path>` explains any path.
    - **Only findings can be removed.** `clean` takes finding identifiers from a scan, never paths. You can’t make it remove something it didn’t find.
    - **Every finding says how it comes back**: `automatic` (rebuilds itself), `redownload`, `reinstall`, or `permanent`. And how much care it needs: `safe`, `caution`, or `personal`.
    - **Personal files are never selected for the person.** Anything in Desktop, Documents, Downloads, Movies, Music or Pictures, and anything `permanent`, is only removed when the person picks it, and it goes to the Trash.
    - **Removal is reversible where it matters.** Rebuildable things are deleted outright; everything else goes to the Trash. `glade undo` puts a clean’s Trash items back.
    - **Apps are quit politely.** `glade quit` asks an app to quit, so it can prompt about unsaved work. `--force` exists; use it only when the person explicitly asks.

    ## Storage

    ```
    glade scan --json                 # what’s reclaimable, by category; read-only (30–60 s)
    glade usage --json                # the whole disk, folder by folder; read-only (about a minute)
    glade plan --level careful --json # what that level would remove; read-only
    glade clean --level careful       # dry run: shows exactly what would happen
    glade clean --level careful --confirm
    glade clean --ids <id> <id> --confirm   # specific findings
    glade undo                        # put the last clean’s Trash items back
    glade receipts --json             # history of cleans
    ```

    Levels: `careful` = only things that rebuild themselves and haven’t been touched lately. `balanced` = adds package caches, stale agent sessions (14+ days), idle simulators and models. `aggressive` = everything that can come back, even if recent. Start with `careful`. Move up only when the person asks for more space, and tell them what the next level adds.

    Good practice: run `plan` first and tell the person the total and the three or four biggest items before using `--confirm`. If they named an amount ("free 30 GB"), pick the lowest level that reaches it. For `personal` findings (old downloads, large files, duplicates), list the best candidates and let them choose; pass the chosen ids to `clean --ids`.

    ## Apps

    ```
    glade installed --json                  # every app: size with its data, last opened, where it came from, own uninstaller
    glade installed --unused 180 --sort opened --json
    glade uninstall "<app name>"            # dry run: exactly what goes to the Trash, what stays and why
    glade uninstall "<app name>" --confirm
    glade uninstall "<app name>" --open-uninstaller   # for apps with their own uninstaller
    ```

    Apps are never selected for the person, at any level and whatever you suggest: list candidates (big, long unused) and let them choose by name. Uninstalling moves the app and the data it keeps in the home folder to the Trash, never deletes it, so `glade undo` puts everything back; the space is freed when the Trash is emptied. Data another installed app shares stays, and the dry run says why. Some apps (Adobe’s above all) spread parts across the system that only their own uninstaller removes: Glade won’t remove those, and you must use the vendor’s uninstaller (`--open-uninstaller`), then scan again so App Leftovers lists what it left. Apps that belong to the system account (most App Store apps) can only be moved to the Trash in Finder, which asks for the person’s password; Glade never asks for it. Glade itself and macOS’s own apps are never offered. Apps appear in `scan`, `findings` and `plan` as the `installedApps` category, unselected.

    Folders the person picks in Glade’s window can be removed there, but there is no command for it: you can’t name a path for Glade to remove.

    ## Memory, processor and graphics

    ```
    glade status --json     # CPU, memory pressure, GPU, disk, thermal state
    glade apps --json       # per app: memory, CPU, GPU, frontmost, last active, playing audio, keeping the Mac awake
    glade processes --sort memory --json
    glade context --json    # what the person is doing right now
    glade simulators --json # running simulators and the memory each holds
    glade suggest --json    # what Glade would quit or shut down, and why
    glade relieve --json    # Free Up Memory: the whole plan, what it ticks and why; a dry run
    glade relieve --confirm # carry out the ticked actions, then measure memory again
    glade relieve --include "<name>" --only --confirm   # just the ones the person chose
    glade quit "<app name>" # ask an app to quit
    glade simulators shutdown "<name>"   # turn a simulator off; its data stays
    ```

    Judging what to quit: never the frontmost app, anything playing or recording audio, anything holding the Mac awake (an export, a download, a call), anything using real CPU right now (it’s working), or system apps. Good candidates are apps that are large, idle for 20+ minutes and not visible, and simulators nobody is using: on a developer’s Mac, idle simulators are often the largest memory user of all. Always tell the person what you’ll quit and why before doing it, unless they’ve already told you to go ahead. There is no "purge memory" command, because clearing caches the system manages doesn’t help; quitting what isn’t needed does.

    `glade relieve` is the same judgement in one go, with the same cautions as `quit`: show the person the plan (the ticked actions, the memory they hold, any caveat) and get their go-ahead before `--confirm`. It ticks only confident, idle actions with no doubt attached; relaunches, hogs, anything with a caveat ("May be in use by Bitrig") and anything used in the last few minutes start unticked, and during a game or full-screen video nothing from the same maker is ticked. Use `--include`/`--exclude` to follow what the person chose, and `--only` to act on nothing else. Apps are asked to quit and may stay open to ask about unsaved work; that’s reported, never forced.

    ## Asking Glade’s own assistant

    ```
    glade advise --level balanced --goal "free 30 GB" --json   # a plan refined by the person’s chosen AI
    glade ask "why is my Mac slow right now?"
    glade providers --json   # which AIs are connected
    ```

    ## Showing the person

    ```
    glade show storage      # open Glade’s window on overview, storage, performance, assistant or history
    ```

    When you’ve found something worth a look, open the matching section so the person sees it in the app. This brings Glade in front of what they’re doing, so do it once, when there’s something to see; `--background` changes the section without coming forward.

    ## When something looks wrong

    `glade doctor` shows permissions and what Glade can’t see (without Full Disk Access some folders can’t be measured). `glade logs --problems` shows recent warnings and errors. If a finding looks misclassified, don’t remove it; tell the person and suggest they report it with `glade report`.
    """
}
