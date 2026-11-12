# Changelog

## 0.2.1 — unreleased

### More space from Balanced

- Each test and preview simulator Xcode makes is now its own item ("Test simulator · iPhone 17 · iOS 27.2"), with its own size and last use. One clone Xcode used today no longer holds back the ones it hasn't touched for days, and a simulator that's running is always left alone.
- Build folders inside your projects and their worktrees (`build`, `dist`, `.build`, `DerivedData`, `target` and the like) are cleared sooner, because the next build makes them again: Balanced takes them after 3 days without work on the project, Careful after a week. Installed packages such as `node_modules`, worktrees and agent history still wait 14 days.
- Each downloaded version of a test browser (Playwright, Puppeteer, Cypress) is its own item, so versions you stopped using months ago go even when you ran a newer one today.
- When a bolder level would free a lot more, `glade plan` says so, and `glade doctor` too when space is low: "Balanced frees 33.3 GB. Aggressive would free 143 GB, including Xcode build data (54.7 GB) and simulators (28.1 GB)."

### Quicker

- Storage and Performance open straight away when you switch to them, even with hundreds of items found and dozens of apps running. Overview, the clean bar and the menu bar also add up your selection once instead of every time they're drawn.

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
