# Changelog

## Unreleased

### Network

- A new **Network** section answers "is it my Wi-Fi, my internet or the service?" It draws your connection from this Mac to your router, your provider and the internet, each with its latency, so a slow hop stands out, and leads with a plain verdict such as "Uploads are making everything wait" or "Your Wi-Fi signal is weak here".
- **Latency** updates every second while the section is open, like the ping graph in a call app. **Wi-Fi** shows the signal, band, channel and link rate.
- **Test Speed** runs macOS's own speed test when you ask. It says how much data it will use first, and afterwards how much slower the line gets when busy and whether it's good for calls, 4K and game streaming.
- **Using the Network** lists apps by what they're sending and receiving now and today, and Performance has a Network column.
- **Data Used** shows what this Mac used today, this week and this month, by day, app and network, counted while Glade is open.
- On an AT&T gateway, **Your Network** shows whether the line is up and lists the devices on your network with their signal, without a password.
- **Settings > Network** turns the section off, changes the host latency is measured against and sets how long a speed test runs.
- `glade network` says whether your connection is healthy and, if not, where the problem is: your Wi-Fi, your internet line or further out. It measures latency to your router, your provider and the internet separately, reads the Wi-Fi signal, and names the apps using the network, so "Dropbox is filling your upload" or "your Wi-Fi is dropping data" comes with the readings behind it.
- `glade network watch` follows latency second by second and says what was busiest at each spike, for when a call breaks up or a stream buffers.
- `glade network check www.netflix.com` tells a slow service from a slow connection by comparing it with apple.com.
- `glade network usage` totals data used by day, app or network. It's recorded while the app is open.
- `glade network test` runs macOS's own speed test when you confirm it, with how much slower the line gets when busy and whether it's good enough for calls, 4K, game streaming and uploads. It says first how much data it would use.
- On an AT&T gateway, `glade network router` reads the line's state and speed and lists the devices on your network with their signal, without a password.
- Coding agents connected to Glade get the same tools. They see verdicts, numbers and app names, never your network's name, addresses or device names.

### Assistant

- The Assistant now follows the conversation, so a follow-up like "and the other one?" or "is it safe to quit that?" is answered in the light of what came before. **New Conversation** starts afresh. On the command line, `glade ask --continue` follows on from your last question.

## 0.3.0 — 2026-11-12

### Battery

- A new **Battery** section (called Energy on a Mac without a battery) shows the charge with one plain sentence, such as "On battery, about 6½ hours left", and a chart of the last 24 hours, 7 days or 30 days with time on the charger and asleep shaded.
- **Health**, **Power** and **Temperature** each get a panel: how much of its original capacity the battery still holds, how hard the Mac is working, and how warm the battery is.
- **Using the most power** lists apps by the energy they've used now, over the last hour, the last 12 hours or since you unplugged, with Quit on the row. It counts processor work only; the screen and graphics chip aren't split between apps.
- **Keeping your Mac awake** names what is stopping it sleeping and for how long, including tools like `caffeinate` and simulators playing sound, with Quit or Shut Down beside each.
- **While it slept** lists recent sleeps with the charge lost and how often the Mac woke; open one to see why.
- The **charge limit** you set in System Settings is shown, with a shortcut to change it there. macOS doesn't let other apps change it.
- Six alerts in **Settings > Alerts**: charged past the limit, limit turned off and health below 80% are on; hot while charging, kept awake on battery and a large drain while asleep are off until you switch them on.
- **Settings > General > Battery detail**: Simple shows sentences and percentages; Technical adds watts, volts, mAh and cycle counts.
- On battery, the menu bar shows the time left and what is using the most power, and Overview has a Battery tile.
- Ask the Assistant "What's draining my battery?".

### Uninstall apps

- Storage has an **Apps** section: every app with its size, when you last opened it and where it came from, with big and long-unused ones first. Nothing is ever ticked for you.
- Uninstalling moves the app and its own settings, caches and data to the Trash, and **Put Back** returns it all. The inspector shows what goes and what stays, such as data another app shares.
- Apps that come with their own uninstaller (Adobe's, for example) get **Open Uninstaller**, because it removes parts Glade can't reach. Apps macOS asks for your password to remove get **Show in Finder**.
- In **What's on This Disk**, each folder in your Library says which app uses it, or that no installed app does. From a row you can move a folder to the Trash, uninstall an app or find it in Storage.

### Ask the Assistant to remove things

- Ask it to remove apps by name ("remove the Adobe apps", "uninstall iMovie"). It lists what matches with a reason for each, and a second AI notes what to know first: a subscription that keeps billing, files only that app opens, other apps from the same developer.
- Only what you named, and what Glade can remove, starts ticked. **Review and Remove…** opens the usual confirmation; everything goes to the Trash and the card offers **Put Back**.
- For this, the AI you chose is sent the names, sizes and last-opened dates of the matching apps. [PRIVACY.md](PRIVACY.md) has the full list.

### Command line and AI agents

- New commands: `glade battery`, `glade energy`, `glade awake`, `glade sleeps`, `glade installed` and `glade uninstall` (a dry run unless you add `--confirm`), with matching tools for agents connected to Glade.
- `glade ask` lists what it proposes removing and prints the commands to do it. It never removes anything itself.
- `glade show <section> --background` changes the window's section without bringing Glade in front of what you're doing.

### Fixed

- In the menu bar, a suggestion's warning ("May be in use by Bitrig") and the memory reading ("Under pressure") are no longer cut off.
- In dark mode, cards stand out from the window again instead of blending into it.

### Changed

- With Battery in the sidebar, Assistant is ⌘5 and History is ⌘6.

## 0.2.3 — 2026-11-12

### Fixed

- In Storage, the group headings (Simulators, Agent Worktrees and so on) scroll along with their items. Before, the top one stuck to the window on a lighter strip with a gap beneath it, which stood out in dark mode.
- Searching Storage for something that isn't there shows "No Results" across the whole list, with the Free Up bar at the bottom where it belongs, instead of a lighter band and the bar floating halfway up.

## 0.2.2 — 2026-11-12

### See what "Other" is

- On Overview, **Other** now opens a list of everything else on the disk, biggest first: your home folder, apps, macOS and the simulator systems and assets it downloads, system data and memory swap. Open any folder to see the biggest things inside it, and how much of it Storage already lists. It reads names and sizes only, and protected folders are never measured. `glade usage` shows the same from the command line.
- Other sits with the rest of the key under the storage bar instead of on the heading's line.

### Storage

- An older version of a test browser is cleared after three days once a newer version beside it is the one being used, instead of waiting a month.
- Hidden Xcode build folders inside projects (`.deriveddata` and the like, which scripts and agents make) are found and cleared like any other build data.
- Aside's saved sessions older than two weeks are listed, and CleanShot's capture history is listed once it is a week old instead of a month. Both are yours to decide: Glade never ticks them, and they go to the Trash.
- Free just the rows you highlight: Shift- or Command-click several, then right-click and choose **Free Up…** (or press Delete). What you ticked elsewhere stays as it was.

### Fixed

- Pointing at the storage bar on Overview shows the slice under the pointer. Before, every part of the bar answered as Other.
- The key under the bar no longer flickers as the pointer moves from one entry to the next.

## 0.2.1 — 2026-11-11

### Fixed

- Glade now notices Full Disk Access on newer versions of macOS. Before, it could go on saying access was off after you had switched it on.

### More space from Balanced

- Each test and preview simulator Xcode makes is now its own item ("Test simulator · iPhone 17 · iOS 27.2"), with its own size and last use. One clone Xcode used today no longer holds back the ones it hasn't touched for days, and a simulator that's running is always left alone.
- Build folders inside your projects and their worktrees (`build`, `dist`, `.build`, `DerivedData`, `target` and the like) are cleared sooner, because the next build makes them again: Balanced takes them after 3 days without work on the project, Careful after a week. Installed packages such as `node_modules`, worktrees and agent history still wait 14 days.
- Each downloaded version of a test browser (Playwright, Puppeteer, Cypress) is its own item, so versions you stopped using months ago go even when you ran a newer one today.
- When a bolder level would free a lot more, the low-space alert says so, as do `glade plan` and `glade doctor`: "Balanced frees 33.3 GB. Aggressive would free 143 GB, including Xcode build data (54.7 GB) and simulators (28.1 GB)."

### Free Up Memory

- One button to lighten the load, the way Free Up does for storage. On Performance (⌘Return), on Overview and from the menu bar, Free Up Memory shows every app it would quit and simulator it would shut down, with how long each has sat idle and the memory it holds, and asks "Quit 2 apps and shut down 2 simulators?". It ticks only the ones it's sure nobody is using; anything with a doubt ("May be in use by Bitrig"), anything you used in the last few minutes and anything that goes with a game or full-screen video in front starts unticked. What's in front, playing or recording sound, keeping the Mac awake or on your keep-running list is never on it, and it says what it's leaving alone ("Leaving Safari, Xcode and Music: in use").
- Apps are asked to quit, never forced, so one with unsaved work can ask you first; the result says so ("Still open: it may be asking about unsaved changes") and shows memory in use before and after, as measured.
- The memory pressure alert says how much Free Up Memory would give back, and clicking it opens the list.
- Big apps left unused for half an hour or more are suggested even when they do a little in the background, as a browser with open tabs does, and menu bar apps or moving wallpapers keeping the graphics chip busy are named as such, with Quit offered when nobody has used them for a while.
- `glade relieve` does the same from the command line and for AI agents: a dry run by default, `--confirm` to do it.

### Storage

- Bitrig's own simulators are listed with their size under Everything, marked as managed by Bitrig. Glade never selects or removes them.

### Quicker

- Storage and Performance open straight away when you switch to them, even with hundreds of items found and dozens of apps running. Overview, the clean bar and the menu bar also add up your selection once instead of every time they're drawn.
- Click Memory, Processor or Graphics on Overview to open Performance with its apps sorted by that reading.

## 0.2.0 — 2026-11-11

### Honest about the Trash

- Glade now says "freed" only for space that is free straight away. Things it moves to the Trash still take up space until you empty the Trash, so they're counted on their own everywhere: "102 GB ready to free · 12 GB to the Trash" on Overview and in Storage, and a clean that only moves things to the Trash asks "Move 18 items to the Trash?" and ends with "Moved 110 GB to the Trash. Space is freed when the Trash is emptied."
- The confirmation lists every item with whole rows and a count, says up front how many can't be recreated, and its button says what will happen: "Free Up 102 GB" or "Move to Trash". The result shows free space before and after only as measured, warns when something was left in place, and says "Put back 18 items" once you've put them back.
- After a clean that moved things to the Trash, Show Trash opens it in Finder. Putting things back says plainly when only some came back ("Put back 9 of 11 items") or none did.
- The setting that sends things to the Trash is now called "Use the Trash where possible": simulators and worktrees are always removed by Xcode's and git's own tools.
- When only some of the items removed straight away can't be recreated, the confirmation says the rest rebuild or download again and names the exceptions ("Can't be recreated: Archive – Lantern 2.3"), or counts them when there are more than three. Long names wrap instead of being cut short.
- The clean levels say what they actually select: Careful takes things that rebuild themselves and haven't been used lately, Balanced adds old downloads, idle simulators and stale agent history, and Aggressive adds tools you'd reinstall and things used recently.
- History keeps freed and moved-to-the-Trash apart in its total and in each clean, and groups a clean's items as "In the Trash", "Deleted" and "Left in place".
- A folder inside another selected folder is counted once, and cleaned with it, so the number of items agrees from Storage to the result.

### Look and feel

- The accent colour you choose now colours the sidebar too.
- The assistant's answers are shown with their formatting: bold, lists, small headings, code and tables, each labelled with the AI (and model, if you picked one) that wrote it. You can choose the model right in the chat.
- The assistant's advice on Storage sits on the list's own grid, and its reasons always include something to review when there is one. Ask keeps its size while it works.
- Pointing at Overview's storage bar shows each slice's name and size, and the key separates what Glade can clear from everything else on the disk.
- Performance has one status style that agrees with each chart's colour, quieter empty cells, and a table that ends on a whole row; power and uptime sit under the title.
- History rows highlight under the pointer and when chosen. The scan shows what it has checked and how much it has found so far.
- Overview, Performance and History sit in the middle of a wide window, and History's rows are narrower so each size is near its name.
- Click the advice's counts on Storage ("3 to review") to see which items they are and why; choosing one shows its row. The advice text keeps a comfortable line length, and the clean level now sits beside Free Up.
- Performance hides the Graphics and Last Used columns when nothing in them has a reading, and its search field is narrower.
- Settings uses shorter labels ("Ask AI at alert thresholds", "Daily limit", "Search file contents") and the same effort choices as the chat.
- Simulators are named one way everywhere: "iPad Air 11-inch · iOS 27.2".
- The chat's AI, model and effort menus open above the question box instead of over it, and every answer names its AI and model the same way.
- The second opinion's AI and model sit together in one row of Settings, apart from each AI's everyday model. Setup and Settings use the same names ("Open at login", "Command line tool").
- Overview's cards share one inner margin, and the storage key keeps one four-column layout at every window size.
- The advice counts' lists show each item's size, and refused suggestions read "1 suggestion refused".
- Checkboxes and the main button turn grey when Glade's window isn't the active one, like the rest of macOS. Warning colours sit on symbols, so the words beside them stay easy to read.
- The Glade menu has Check for Updates… in an installed copy (0.1.0 left it out) and a new Open at Login item.
- Calmer details throughout: plain recovery words ("Downloads again", "Needs reinstall", "Can't be undone"), one figure style, a shorter search prompt, wider inspectors, and tidier Settings, Setup and menu bar wording.

### Storage

- Some things that live in cache folders aren't caches, and Glade now treats them that way: Poetry's project environments, the local storage of Deno programs and R's renv packages are left alone; models downloaded with llama.cpp or Buzz count as AI models; Yarn's Plug'n'Play packages and the browsers Playwright, Puppeteer and Cypress run say they need reinstalling and wait for a bolder level; and the Maven repository is flagged because it can hold your own `mvn install` builds.
- JetBrains caches wait for Balanced, since reindexing a project takes a while.
- Finds tool versions installed with mise, Bundler's and RubyGems' download caches, and the installer downloads pyenv and rbenv keep.
- Finds old Claude Code and Cursor Agent versions those tools keep after updating themselves, often hundreds of megabytes each. The version the command runs, a newer one waiting to switch over and the one before it always stay, and nothing is offered while an older version is still running.

### Safety

- Caches of Chromium-based apps such as Slack, Discord, VS Code and Docker Desktop are left alone while that app is open, even when they haven't changed for days, and a toolkit or runtime that a running program was started from is never removed. Both are checked again at the moment of removal.
- Codex's synced plugins, bundled marketplace and backups, and Antigravity's knowledge, skills and conversations, are no longer mistaken for scratch files. Gemini CLI's own skills, agents, commands and hooks are protected like other agents' memory, and Codex's tool runtimes aren't offered while Codex is running.
- Endpoint security, VPN and device management software (CrowdStrike, SentinelOne, ESET, Jamf, GlobalProtect, Cisco Secure Client and others) is now a protected area: removing its files can set off tamper alarms your organisation sees.

## 0.1.0 — 2026-11-11

The first version of Glade. It shows what is using your Mac's storage, memory, processors and graphics, and clears it safely.

### Storage

- A scan finds what can be cleared across 26 categories: app and browser caches, logs, Xcode build data, simulators and their runtimes, package caches, project dependencies and build output, toolkits, AI models, agent history and leftover worktrees, editor extensions, leftovers of removed apps, old installers, large and long-unused files, and more.
- Scan Including Duplicates also finds identical files in your own folders.
- Every finding says how it comes back: it rebuilds itself, downloads again, needs a reinstall, or is permanent.
- Three levels choose what to clear: Careful, Balanced and Aggressive. Change any choice by hand before you clean.

### Search

- Optional and off by default: Glade can read what documents, PDFs and images contain, on this Mac only, so you can search by meaning (`glade search "the lease for the flat"`), find files like another, and find near-identical photos and documents.

### Safety

- Keys and credentials, Keychains and password managers, your AI agents' memory and settings, Photos and other libraries, Messages, Mail, Notes, iCloud Drive and other synced folders, browser profiles, backups and `.git` folders are never scanned, shown or removed. Add folders of your own.
- Only things a scan found can be removed, and every path is checked again at the moment of removal.
- Personal files are never chosen for you.
- Things that rebuild are deleted; everything else goes to the Trash and can be put back.
- Caches aren't offered while their app is open, and worktrees with uncommitted changes are never removed.

### Performance

- Live processor, memory, graphics, disk and thermal readings, and every app with its helpers grouped and what it is doing.
- Suggestions for what to quit, which leave alone the app in front, anything playing or recording, and anything keeping the Mac awake.
- Quit an app politely, or shut down idle simulators with their apps and data kept.
- Alerts when free space runs low, memory is under pressure or the processor stays busy.

### Your AI

- Ask a question about your Mac, or have your AI refine a clean towards a goal such as "free 30 GB".
- Works with Claude Code, Codex, OpenCode and Apple Intelligence. Gemini CLI, Cursor CLI, GitHub Copilot CLI, Qwen Code and Ollama are supported from their documentation and not yet tested.
- The AI gets no tools and never sees what's inside your files. Glade drops any suggestion that breaks its rules, and keeps a record of what was asked and answered.

### For coding agents

- The `glade` command line does everything the app does, with JSON output and nothing removed without `--confirm`.
- `glade guide` briefs Claude Code, Codex, Cursor and other agents on the safety rules and the commands.
- `glade mcp` runs Glade as an MCP server.

### Good to know

- Glade needs macOS 26 or later. Give it Full Disk Access to measure everything.
- It checks for updates once a day and installs an update the next time it quits. This can be turned off.
- There is no account, analytics or server. Report a Problem saves a report to your Desktop for you to attach to an issue.
