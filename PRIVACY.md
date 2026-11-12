# Privacy

Last updated: 12 November 2026

Glade has no accounts, advertising, analytics, crash reporting or remote logging, and no server. Nothing is sent to the developer. Glade itself makes one kind of network request, the update check to GitHub. The other way anything leaves your Mac is when you ask a cloud AI a question through Glade, and then it goes to that AI's provider under your own account. Glade never sends what's inside your files.

## What Glade reads

- **Names, sizes and dates on your disk.** To find what can be cleared, a scan walks known locations (caches, build data, package caches, simulators, AI models, agent history, downloads and so on) and your own folders for large and long-unused files, reading each file's name, size, kind and when it was last changed or opened. It does not open files to read them, with two exceptions below.
- **The whole disk, when you open Other.** On Overview, **Other** (or `glade usage`) adds up every folder on your Mac's disk, including Applications, the shared Library and system folders outside your home folder, reading names and sizes only. It also asks `diskutil` how big macOS's own volumes are. Protected areas are stepped around and never measured; their space shows as "Not Measured". The result, folder names and sizes, is kept in `~/Library/Application Support/Glade/disk-usage.json` and is never shown to an AI.
- **Duplicates, only when you ask.** **Scan Including Duplicates** (or `glade scan --deep`) reads files of 1 MB or more in Desktop, Documents, Downloads, Movies, Music, Pictures and CleanShot's folder to compute fingerprints, so identical copies can be found. Fingerprints are compared on your Mac and not kept after the scan. Files are read without changing their last-opened dates, and cloud placeholders are never downloaded.
- **What files contain, only if you switch it on.** **Settings > Search** is off by default. When on, Glade reads documents, PDFs and images in the folders you list (Downloads, Desktop and Documents unless you change them) to build a search index: extracted text, a numeric fingerprint of each passage and image, and a short excerpt. All of it is worked out by Apple's on-device models and kept in `~/Library/Application Support/Glade/index.sqlite`. None of it is sent anywhere or shown to a cloud AI. Protected areas and cloud placeholders are never opened. Switching it off stops indexing; delete that file to remove what was built.
- **Git worktrees.** To tell an agent's leftover worktree from work in progress, Glade runs `git status` in it and reads the small `.git` pointer file that links it to its repository.
- **What's running.** Memory, processor and graphics use per process, which app is in front, which apps are playing or recording audio or keeping the Mac awake, how long since you last used the keyboard or pointer, and booted simulators. Glade reads these from macOS and from `ps` and `xcrun simctl`. So that nothing in use is removed, a scan and a clean also note which folder each running program was started from, and read where an app's `SingletonLock` link points (the computer name and process number Chromium-based apps such as Slack or VS Code leave there while they're open).
- **The battery and power.** Charge, whether it's charging, the charger, power flowing in and out, temperature, health and cycle count, from macOS's power-source and battery readings, and `system_profiler` for the health figure System Settings shows. The charge limit, from `pmset -g battlimit`. Which apps and tools are keeping the Mac awake, from macOS's sleep requests, and the sleep settings in `/Library/Preferences/com.apple.PowerManagement.plist`. Recent sleeps, wakes and their causes, from `pmset -g log`. The energy macOS has counted against each running process, the same figure Activity Monitor's Energy tab starts from. Glade reads all of these and changes none of them.
- **Which apps are installed**, through Spotlight and the Applications folders, so leftovers of apps you've removed can be found.
- **Which AI tools you have.** Glade looks for each tool on your `PATH`, asks it for its version, and checks whether its sign-in file or Keychain item exists. It never opens a sign-in file or reads a password; for Keychain items it only asks whether one exists. In **Settings > Advanced**, Glade also asks Claude Code and Codex whether Glade is connected to them (`claude mcp get glade`, `codex mcp get glade`); those tools may contact their own services when they start.

## What Glade never reads

Protected areas are never scanned, listed, measured or shown to an AI: SSH, GPG and cloud credentials, `.env`, key and certificate files, Keychains and password managers, your AI agents' memory, skills, settings and sign-ins, Photos, Music, TV and other media libraries, Messages, Mail and other chat apps, Notes, Contacts, Calendars, Reminders, Health and other personal records kept by Apple's apps, apps' preferences, iCloud Drive and other synced folders, browser profiles, Time Machine and other backups, virtual machines, endpoint security, VPN and device management software, and every `.git` folder. Folders you add under **Protected** in Settings (or with `glade protect add`) are treated the same way. `glade protect list` shows the full list, and `glade protect check <path>` explains any path.

## What Glade stores, and where

Everything stays on your Mac.

| What | Where |
| --- | --- |
| Settings | `~/Library/Application Support/Glade/config.json`, and appearance, setup and update preferences in the app's preferences (`io.github.dlev02.glade`) |
| The last scan: each finding's name, location, size and dates | `~/Library/Application Support/Glade/last-scan.json` |
| Receipts: what each clean removed or moved to the Trash, and where it went, so it can be put back | `~/Library/Application Support/Glade/Receipts/` |
| Assistant runs: exactly what was sent to an AI and what came back, the newest 100 | `~/Library/Application Support/Glade/AgentRuns/` |
| When each app was last in front, by bundle identifier | `~/Library/Application Support/Glade/activity.json` |
| When each alert last fired, so alerts don't repeat | `~/Library/Application Support/Glade/alerts.json` |
| Battery history, recorded while the app is open: the charge, power and temperature every five minutes for 30 days (thinned to every half hour after two days), how much energy each app used for the last 7 days, and battery health once a day for 3 years. App names only, under a megabyte | `~/Library/Application Support/Glade/battery-history.json` |
| The log: what Glade did and what went wrong, up to about 3 MB across two files | `~/Library/Logs/Glade/`, and the macOS system log |

Before a log line is written, your home folder is shortened to `~` and anything that looks like a password, token or API key is replaced. The log records things like scans, what each clean removed, which AI was asked and how long it took, and errors. It never records what was asked or answered; that is in the assistant runs, which you can read under **History** or with `glade runs`.

## What leaves your Mac

### Update checks

Glade uses [Sparkle](https://sparkle-project.org), an open-source update framework, to keep itself current.

- **When:** once a day, in a copy installed in an Applications folder. A copy built from source or run from elsewhere never checks.
- **What it requests:** one file, `appcast.xml`, from `raw.githubusercontent.com`. When it lists a newer version, Glade downloads it from `github.com` and installs it the next time Glade quits. GitHub may redirect the download to `release-assets.githubusercontent.com`. If you use a firewall app, these are the hosts to allow.
- **What GitHub can see:** as with any web request, your IP address and the time, plus the app's name and version and Sparkle's version. GitHub handles this under [its privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
- **What is not sent:** your settings, anything Glade found, the names of your apps or files, device identifiers, or a hardware or system profile.
- **How updates are checked:** the feed and every update are signed, and Glade verifies both against a key built into the app before installing anything.

Turn automatic checks off in Settings. Glade then makes no network requests of its own unless you choose **Check for Updates…**.

### Questions you ask an AI

Glade only asks an AI when you ask it to (**Assistant**, `glade advise`, `glade ask`), or when a coding agent you run calls Glade. It runs the AI tool you installed and signed in to, and that tool sends the request to its provider under your account and their terms: Anthropic for Claude Code, OpenAI for Codex, Google for Gemini CLI, Cursor, GitHub for Copilot CLI, Alibaba for Qwen Code, and whichever provider you set up in OpenCode. Apple Intelligence and Ollama run on your Mac, and nothing leaves it; Glade reaches Ollama through its local address, 127.0.0.1. Apple's Private Cloud Compute is not used: Apple offers it only to apps from the App Store.

What the AI is shown:

- **To refine a clean:** the level and any goal you typed, free and total disk space, and for each finding its identifier, size, category, name (which can be an app, project, model or file name), when it was last used, how it comes back, whether it's selected and why, and, for cloud AIs, its location with your home folder shown as `~` and the project it belongs to. Also which app is in front, which are busy, and the names of open apps. Protected areas never appear, because a scan never produces findings in them.
- **To answer a question:** your question; processor, memory, graphics, disk, power and thermal readings; which app is in front, whether you're in a game, and how long since you last used the keyboard or pointer; the 25 apps using the most memory, with their use and whether each is playing audio, using the microphone or keeping the Mac awake; the battery's charge, state, health, cycle count, temperature, charge limit and time left; what is keeping the Mac awake, in a few words, and for how long; the last three sleeps with their length, charge lost and why the Mac woke; the apps using the most energy, with their share and notes such as "not used for 2 days"; Glade's suggestions; and storage totals by category.
- **Never:** what's inside any file, the contents of a protected area, your settings, or anything from your agents' memory.

Each AI tool runs in a new, empty temporary folder that is deleted afterwards, with its own tools, plugins, MCP servers, memory and project instructions switched off, so it can only reply with text. Glade checks the reply and ignores anything outside the rules.

### Problem reports

**Help > Report a Problem…** and `glade report` save a text file to your Desktop with Glade's and macOS's versions, your Mac's model, core count and memory, whether Full Disk Access is on, disk space, your settings (counts only for protected folders), what kinds of things the last scan found by category, recent cleans, and the last 300 log lines with paths cut short. File names and locations are left out unless you choose to include them. Nothing is sent; you read the file and attach it to a GitHub issue yourself, and GitHub issues are public.

## Permissions

- **Full Disk Access** lets Glade measure folders macOS otherwise keeps from every app. Glade works without it and says what it couldn't see. Withdraw it in System Settings under Privacy & Security > Full Disk Access.
- **Notifications** carry Glade's alerts. Turn them off in System Settings under Notifications.

The `glade` command and the MCP server run with the permissions of the app you start them from, such as Terminal or your coding agent.

## Removing Glade and its data

Quit Glade and move it from Applications to the Trash. To remove what it stored as well:

```sh
rm -rf ~/Library/Application\ Support/Glade ~/Library/Logs/Glade
defaults delete io.github.dlev02.glade
```

If you linked the `glade` command, remove that link (for example `/usr/local/bin/glade`), and remove Glade from any agent you added it to as an MCP server. Items a clean moved to the Trash stay there until you empty it.

## Contact

Questions about privacy go to [GitHub issues](https://github.com/dlev02/Glade/issues). For a security problem, follow [SECURITY.md](SECURITY.md) instead of posting details in a public issue.
