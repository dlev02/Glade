# Privacy

Last updated: 12 November 2026

Glade has no accounts, advertising, analytics, crash reporting or remote logging, and no server. Nothing is sent to the developer. Glade itself makes the update check to GitHub and, when you look at your network, the checks described under **Network checks** below: pings, reading your router's status pages and, only when you ask, a speed test. Those carry nothing about you. The other way anything leaves your Mac is when you ask a cloud AI a question through Glade, and then it goes to that AI's provider under your own account. Glade never sends what's inside your files.

## What Glade reads

- **Names, sizes and dates on your disk.** To find what can be cleared, a scan walks known locations (caches, build data, package caches, simulators, AI models, agent history, downloads and so on) and your own folders for large and long-unused files, reading each file's name, size, kind and when it was last changed or opened. It does not open files to read them, with two exceptions below.
- **The whole disk, when you open Other.** On Overview, **Other** (or `glade usage`) adds up every folder on your Mac's disk, including Applications, the shared Library and system folders outside your home folder, reading names and sizes only. It also asks `diskutil` how big macOS's own volumes are. Protected areas are stepped around and never measured; their space shows as "Not Measured". The result, folder names and sizes, is kept in `~/Library/Application Support/Glade/disk-usage.json` and is never shown to an AI. To say whose a folder in your Library is, Glade compares its name with the installed apps' names and identifiers. A folder you choose to move to the Trash from this list is measured again, checked against the protected areas, and recorded in that clean's receipt; it is never saved with the scan.
- **Duplicates, only when you ask.** **Scan Including Duplicates** (or `glade scan --deep`) reads files of 1 MB or more in Desktop, Documents, Downloads, Movies, Music, Pictures and CleanShot's folder to compute fingerprints, so identical copies can be found. Fingerprints are compared on your Mac and not kept after the scan. Files are read without changing their last-opened dates, and cloud placeholders are never downloaded.
- **What files contain, only if you switch it on.** **Settings > Search** is off by default. When on, Glade reads documents, PDFs and images in the folders you list (Downloads, Desktop and Documents unless you change them) to build a search index: extracted text, a numeric fingerprint of each passage and image, and a short excerpt. All of it is worked out by Apple's on-device models and kept in `~/Library/Application Support/Glade/index.sqlite`. None of it is sent anywhere or shown to a cloud AI. Protected areas and cloud placeholders are never opened. Switching it off stops indexing; delete that file to remove what was built.
- **Git worktrees.** To tell an agent's leftover worktree from work in progress, Glade runs `git status` in it and reads the small `.git` pointer file that links it to its repository.
- **What's running.** Memory, processor and graphics use per process, which app is in front, which apps are playing or recording audio or keeping the Mac awake, how long since you last used the keyboard or pointer, and booted simulators. Glade reads these from macOS and from `ps` and `xcrun simctl`. So that nothing in use is removed, a scan and a clean also note which folder each running program was started from, and read where an app's `SingletonLock` link points (the computer name and process number Chromium-based apps such as Slack or VS Code leave there while they're open).
- **The battery and power.** Charge, whether it's charging, the charger, power flowing in and out, temperature, health and cycle count, from macOS's power-source and battery readings, and `system_profiler` for the health figure System Settings shows. The charge limit, from `pmset -g battlimit`. Which apps and tools are keeping the Mac awake, from macOS's sleep requests, and the sleep settings in `/Library/Preferences/com.apple.PowerManagement.plist`. Recent sleeps, wakes and their causes, from `pmset -g log`. The energy macOS has counted against each running process, the same figure Activity Monitor's Energy tab starts from. Glade reads all of these and changes none of them.
- **Your network.** The Wi-Fi connection's signal, noise, band, channel, width, Wi-Fi generation, link rate and security, from macOS's Wi-Fi framework; the Wi-Fi network's name and which access point you're on only if you give Glade Location access, which macOS requires for those two. How the Mac is connected, whether the network is a hotspot or in Low Data Mode, the router's address, your VPNs and whether they're connected, and whether a web proxy is set, from macOS and from `route` and `scutil`. How many bytes each network interface has carried, from macOS's counters. How much each running process is sending and receiving, from macOS's `nettop`, which counts bytes only and never sees what's in them.
- **Your router, when Glade recognises it.** For AT&T gateways, the status pages that open without the Device Access Code: the model and firmware, whether the line to AT&T is up and at what speed, how much it has carried and any errors, and the device list: each device's name, whether it's on, how it connects (Ethernet, 2.4 GHz or 5 GHz Wi-Fi) and its signal bars. Device hardware and IP addresses on those pages are not kept.
- **Which apps are installed**, through Spotlight and the Applications folders, so they can be listed under Apps and leftovers of apps you've removed can be found. From each app Glade reads its `Info.plist` (name, identifier, version and program name), the developer team and app groups in its code signature (without checking the signature), the names of the items inside it and beside it (to find helpers and its own uninstaller), whether it has an App Store receipt (whether the file exists, not what it says), and the names of Homebrew's links in its `Caskroom` folder. When it was last opened comes from Spotlight, from Glade's own record of apps coming to the front, and from when its program file was last read. Nothing inside an app is opened beyond its `Info.plist`.
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
| Notes you keep for the Assistant: up to 30 short dated notes, only ones you typed or saved | `~/Library/Application Support/Glade/assistant-notes.json` |
| Assistant runs: exactly what was sent to an AI and what came back, the newest 100 | `~/Library/Application Support/Glade/AgentRuns/` |
| When each app was last in front, by bundle identifier | `~/Library/Application Support/Glade/activity.json` |
| When each alert last fired, so alerts don't repeat | `~/Library/Application Support/Glade/alerts.json` |
| Data used, recorded while the app is open: bytes received and sent each hour for each network (by name only with Location access, otherwise "Wi-Fi" or "Ethernet") and each day for each app, for 90 days, under a megabyte | `~/Library/Application Support/Glade/network-history.json` |
| The last 50 speed tests: speed, latency and data used | `~/Library/Application Support/Glade/speed-tests.json` |
| What your router last reported, including its device names, for five minutes | `~/Library/Application Support/Glade/router.json` |
| The addresses latency is measured against: your router, your provider's first hop and the internet host, for a day | `~/Library/Application Support/Glade/network-targets.json` |
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

### Network checks

These run only while you're looking at your network: `glade network` and its commands, the **Network** section while it's on screen, or a coding agent connected to Glade asking. None runs on a schedule, and none carries anything about you beyond what any connection does (your IP address and the time).

- **Latency.** Pings (64 bytes each) to your router, your internet provider's first router past it, and an internet host, `1.1.1.1` (Cloudflare) unless you change it in **Settings > Network**. A reading sends 9 to each; the Network section and `glade network watch` send one a second to each. That host and your provider see the pings, as they would any traffic. To find your provider's first router, Glade runs `traceroute` towards the internet host once a day per network.
- **Your router's status pages**, on your own network only, read without a password. A redirect to anywhere else is refused.
- **A site check** (`glade network check <site>`, or one an agent asks for): one request for the headers of the site you name and of `www.apple.com`, to time each step. Nothing is sent in it.
- **A speed test**, only when you press **Test Speed**, run `glade network test --confirm`, or allow an agent that asks. It runs macOS's own `networkQuality`, which fills your connection for up to the length you set against Apple's servers (`mensura.cdn-apple.com` and Apple's `aaplimg.com` servers it chooses), and uses a lot of data: hundreds of megabytes, or gigabytes on a fast line. Apple handles it under [its privacy policy](https://www.apple.com/legal/privacy/). An agent can't start one on a hotspot or in Low Data Mode unless you allow it in Settings.

If you use a firewall app, these are `/sbin/ping`, `/usr/sbin/traceroute` and `/usr/bin/networkQuality`, and Glade itself for the router and site checks.

### Questions you ask an AI

Glade only asks an AI when you ask it to (**Assistant**, `glade advise`, `glade ask`), or when a coding agent you run calls Glade. It runs the AI tool you installed and signed in to, and that tool sends the request to its provider under your account and their terms: Anthropic for Claude Code, OpenAI for Codex, Google for Gemini CLI, Cursor, GitHub for Copilot CLI, Alibaba for Qwen Code, and whichever provider you set up in OpenCode. Apple Intelligence and Ollama run on your Mac, and nothing leaves it; Glade reaches Ollama through its local address, 127.0.0.1. Apple's Private Cloud Compute is not used: Apple offers it only to apps from the App Store.

What the AI is shown:

- **To refine a clean:** the level and any goal you typed, free and total disk space, and for each finding its identifier, size, category, name (which can be an app, project, model or file name), when it was last used, how it comes back, whether it's selected and why, and, for cloud AIs, its location with your home folder shown as `~` and the project it belongs to. Also which app is in front, which are busy, and the names of open apps. Protected areas never appear, because a scan never produces findings in them.
- **To answer a question:** your question, and the earlier questions and answers in the same conversation until you start a new one; processor, memory, graphics, disk, power and thermal readings; which app is in front, whether you're in a game, and how long since you last used the keyboard or pointer; the 25 apps using the most memory, with their use and whether each is playing audio, using the microphone or keeping the Mac awake; the battery's charge, state, health, cycle count, temperature, charge limit and time left; what is keeping the Mac awake, in a few words, and for how long; the last three sleeps with their length, charge lost and why the Mac woke; the apps using the most energy, with their share and notes such as "not used for 2 days"; Glade's suggestions; and storage totals by category. When the question is about the network (the internet, Wi-Fi, a stream, a call, lag), it is also shown the Wi-Fi signal, band, channel and link rate; latency to your router, provider and the internet; whether a VPN or proxy is on; the apps sending and receiving most; your router's model, line state and speed, and how many devices are online by connection and how many have a weak signal; the last speed test; how much data was used today and this week; and Glade's verdicts. Never the network's name, access point, IP addresses or any device's name.
- **To act on a request to remove something** ("remove the Adobe apps", "uninstall iMovie"): your request, the same readings as for a question, and a short list of what on this Mac matches it. For an installed app that is its name, size and how much of it is data, when it was last opened, where it came from (App Store, Homebrew, Setapp or a download), the developer part of its identifier (such as "adobe"), whether it has its own uninstaller, needs your password or is open. For anything else a scan found, its name, category, size, when it was last used and how it comes back. Only a request like this sends app names; if it is about apps in general ("uninstall apps I never use"), the list is your largest, longest-unused apps. The answer is a list of those items to consider, and a second AI is then shown your request and the items on that list, with the same facts and the other apps installed from the same developer, to say what you should know first. That second opinion comes from the AI you chose for a closer look in **Settings > Assistant**, otherwise Apple Intelligence on your Mac, otherwise another AI you have set up. Nothing is removed until you tick it and confirm in Glade.
- **With every request, if you keep any:** your notes from **Settings > Assistant > Notes**, with the date each was added. Notes are only what you typed or chose to save when an answer suggested one; turn **Use notes** off to send none. An answer may end by suggesting a note ("Remember: AT&T fibre with a BGW320 gateway"); it is kept only if you click **Remember**.
- **Never:** what's inside any file, the contents of a protected area, the list of apps you have installed (except the matching ones above, when you ask to remove something), your settings, or anything from your agents' memory.

Each AI tool runs in a new, empty temporary folder that is deleted afterwards, with its own tools, plugins, MCP servers, memory and project instructions switched off, so it can only reply with text. Glade checks the reply and ignores anything outside the rules.

### Problem reports

**Help > Report a Problem…** and `glade report` save a text file to your Desktop with Glade's and macOS's versions, your Mac's model, core count and memory, whether Full Disk Access is on, disk space, your settings (counts only for protected folders), what kinds of things the last scan found by category, recent cleans, and the last 300 log lines with paths cut short. File names and locations are left out unless you choose to include them. Nothing is sent; you read the file and attach it to a GitHub issue yourself, and GitHub issues are public.

## Permissions

- **Full Disk Access** lets Glade measure folders macOS otherwise keeps from every app. Glade works without it and says what it couldn't see. Withdraw it in System Settings under Privacy & Security > Full Disk Access.
- **Location** (optional) lets Glade read your Wi-Fi network's name and which access point you're on, which macOS treats as location. Glade uses it only to label data used by network and to notice when you move between access points; it never reads where you are. Everything else on Network works without it. Withdraw it in System Settings under Privacy & Security > Location Services.
- **Local Network** lets Glade ping your router and read its status pages. Withdraw it in System Settings under Privacy & Security > Local Network.
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
