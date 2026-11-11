# Security

Glade removes files, runs without the app sandbox, usually holds Full Disk Access, runs other programs, updates itself and takes commands from scripts, coding agents and an MCP server. Its safety policy is part of its security: what it promises never to touch is listed in [README.md](README.md#what-glade-never-touches) and enforced by `Packages/GladeKit/Sources/GladeKit/Safety`.

A problem is security-sensitive if it:

- makes Glade remove, move, list, measure or show to an AI anything in a protected area, outside your home and temporary folders, on another disk, or reached through a link that leads elsewhere;
- makes Glade remove a path it didn't find in a scan, or remove something with `clean` that a scan, a plan or an AI's suggestion shouldn't have allowed (a personal file selected without the person, a repository removed whole, a worktree with uncommitted changes);
- lets an AI's reply, a file name or folder contents make Glade do anything beyond suggesting findings by identifier;
- gives an AI tool that Glade runs access to tools, files or commands;
- puts file contents, credentials or secrets into a prompt, a log line or a problem report;
- lets an unsigned or tampered update install.

## Reporting a vulnerability

Use [Report a vulnerability](https://github.com/dlev02/Glade/security/advisories/new) to share details privately with the maintainer.

If that page is unavailable, open a public issue asking for a private reporting channel, without including vulnerability details or sensitive attachments. Do not post exploit steps or private data in public issues.

A useful report includes the Glade version or commit, the macOS version, what you expected, what happened and a minimal way to reproduce it. These help:

```sh
glade doctor            # version, Full Disk Access, what's protected, where the log is
glade logs --problems   # recent warnings and errors
glade protect check <path>   # why Glade would or wouldn't remove a path
glade report --print    # versions, settings, scan totals and recent log lines
```

`glade report` leaves file names out unless you add `--include-findings`. Folder and project names can be personal, so read anything before you share it.

## Scope and fixes

Security fixes target the current source on `main` and the latest published release. There is no commitment to maintain older releases. Please allow time to investigate and coordinate a fix before public disclosure; this small project cannot promise a response deadline.

What the AI tools you connect do with a request is up to them and their providers; a weakness in one of those tools belongs with its maker. How Glade runs them, and what it gives them, is in scope.

See [PRIVACY.md](PRIVACY.md) for what Glade reads, stores and sends.
