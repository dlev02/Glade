import Foundation

/// The briefing for AI agents that drive Glade from outside: Claude Code, Codex,
/// Cursor and others calling the command line or the MCP server. Printed by
/// `glade guide` and sent as the MCP server’s instructions.
public enum Guide {
  public static let text = """
    # Glade: a briefing for agents

    Glade shows what is using this Mac’s storage, memory, processors, graphics and battery, and clears it safely. You drive it; it does the looking and the removing. You never need to run `rm`, `du`, `find`, `kill` or `ps` yourself, and you shouldn’t: Glade knows which locations are safe and enforces rules you can’t see from a shell.

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

    ## Battery and energy

    ```
    glade battery --json           # charge, charging or not (and why), time to full or left, charger, watts in/out, temperature, health, cycles, charge limit
    glade battery history --days 7 # what the app recorded: charge every 5 min, health once a day
    glade energy --period hour --json   # apps by energy: now, hour, 12h or unplugged
    glade awake --json             # what is keeping the Mac or its screen awake, since when, and why
    glade sleeps --json            # recent sleeps: how long, charge before and after, what woke it
    glade battery limit            # the charge limit; --open opens System Settings to change it
    ```

    Answering “what is draining my battery”: start with `glade battery` (is it on battery, how fast is it draining), then `glade energy --period unplugged` (or `hour` on the charger) and `glade awake`. Energy is what macOS bills each process for the processor and neural engine; the screen, graphics chip and radios aren’t in it, so apps together are usually a fraction of what the whole Mac uses. Say that when the numbers don’t add up. Longer periods only cover the time the app was open.

    Health is System Settings’ “Maximum Capacity”: below 80% Apple may recommend a service. The charge limit is set in System Settings › Battery › Battery Health; Glade can read it but can’t change it, and neither can you, so open the pane for the person with `glade battery limit --open` after asking. macOS charges to 100% now and then even with a limit, to keep its gauge accurate.

    Something keeping the Mac awake follows the same rule as quitting: never stop it without asking, because it may be a download, an export or a call. Requests one process holds for another (coreaudiod for a simulator playing sound) are credited to the real one. Glade doesn’t stop command-line tools such as `caffeinate`; it names the app or terminal that started it so the person can stop it there. “Sleep is turned off for this whole Mac” means `pmset disablesleep` is on, usually set by an app that keeps Macs awake; turning it back on needs an administrator, so tell the person rather than trying.

    ## Network

    ```
    glade network --json             # verdicts, Wi-Fi link, latency to router / provider / internet, apps using it, router, last speed test
    glade network watch --for 30     # second by second, with the busiest app at each spike
    glade network apps --json        # traffic per app now, and today’s totals
    glade network usage --period week --by app   # data used (day, app or network), recorded while the app is open
    glade network check www.netflix.com          # one service against apple.com: is it the service or the connection?
    glade network router --json      # what an AT&T gateway reports: line, speed, devices by connection and signal
    glade network test               # dry run: what a speed test would use
    glade network test --confirm     # macOS’s speed test: download, upload, latency idle and when busy
    ```

    Answering “why is my internet slow” or “why does this buffer”: start with `glade network`. It measures three segments, and comparing them is the diagnosis: spikes or loss to the **router** with a weak or fair signal mean the Wi-Fi; a steady router with a slow **provider** hop means the line; both steady with a slow **internet** means further out. An app sending heavily while latency rises is the likely cause of calls stuttering (it fills the upload). The Mac using little while latency rises points at another device on the network. For one slow service, `glade network check <host>`. For intermittent trouble, `watch` while it happens. The Wi-Fi link rate is what the radio could carry, not internet speed; never report it as speed.

    Reading the output: latencies are milliseconds; traffic is bytes a second (now) or bytes (totals); `lastTest` is absent until a test has run. In `watch`, a spike is a reply over three times the typical and at least 30 ms more, or a lost one, and each names the busiest app then (`busiestApp`). VPNs set up in System Settings are in `path.vpns`, and `path.defaultInterface` starting `utun` means a tunnel carries everything, whatever made it. The router’s port speed and the Wi-Fi link rate are ratings, not measured speed; the router’s byte totals run since it last restarted and aren’t a weekly figure. Output leaves out the network’s name, addresses and device names unless `--show-names` is given; never pass that flag on the person’s behalf.

    Stutter on a call or in a game isn’t always the network: check `glade status` and `glade context` too, since a busy processor or memory pressure stutters calls as well.

    A speed test fills the connection against Apple’s servers and uses a lot of data (hundreds of MB, gigabytes on a fast line). Run it only when speed under load is the question and the person agrees; check the dry run’s estimate first, and never on a hotspot. Results include latency when the line is full: a large gap over idle is bufferbloat, which a router’s Smart Queue or QoS setting fixes.

    Little Snitch: `glade littlesnitch` summarises the rules the person imported (`glade littlesnitch import <backup>`), with what stands out; `glade littlesnitch review` asks Glade’s AI for suggestions and writes new rules to an .lsrules file. Never try to run Little Snitch’s own command line: it needs root and an opening in its security that the person shouldn’t have to make.

    Data used covers only the time Glade’s app was open (`coverage` is the share of the period it saw) and includes local traffic, so it isn’t the provider’s bill. If nothing is recorded, the person’s app may be an older version or not running; say so rather than guessing.

    ## Notes and rules

    ```
    glade notes --json        # what the person has told Glade to remember, dated
    glade rules --json        # apps whose leftovers and caches are always ticked, and what each covers now
    ```

    Read the notes before advising: they hold what a reading can’t show (the internet provider, a router, a problem that came back before, an app no longer used). Current readings win where a note disagrees. Notes and rules are the person’s to keep: suggest one (“Want me to remember that you’re on AT&T fibre? `glade notes add …`”) rather than adding it unasked. A rule ticks that app’s leftovers and caches in plans the person sees (never in MCP cleans by level); only the person can add one, from their own Terminal or Settings, so suggest it in words.

    ## Asking Glade’s own assistant

    ```
    glade advise --level balanced --goal "free 30 GB" --json   # a plan refined by the person’s chosen AI
    glade ask "why is my Mac slow right now?"
    glade providers --json   # which AIs are connected
    ```

    ## Showing the person

    ```
    glade show storage      # open Glade’s window on overview, storage, performance, battery, network, assistant or history
    ```

    When you’ve found something worth a look, open the matching section so the person sees it in the app. This brings Glade in front of what they’re doing, so do it once, when there’s something to see; `--background` changes the section without coming forward.

    ## When something looks wrong

    `glade doctor` shows permissions and what Glade can’t see (without Full Disk Access some folders can’t be measured). `glade logs --problems` shows recent warnings and errors. If a finding looks misclassified, don’t remove it; tell the person and suggest they report it with `glade report`.
    """
}
