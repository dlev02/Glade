# Changelog

## 0.2.0 — unreleased

### Storage

- Some things that live in cache folders aren't caches, and Glade now treats them that way: Poetry's project environments, the local storage of Deno programs and R's renv packages are left alone; models downloaded with llama.cpp or Buzz count as AI models; Yarn's Plug'n'Play packages and the browsers Playwright, Puppeteer and Cypress run say they need reinstalling and wait for a bolder level; and the Maven repository is flagged because it can hold your own `mvn install` builds.
- JetBrains caches wait for Balanced, since reindexing a project takes a while.
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
