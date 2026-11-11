import Foundation

/// Finds extra git worktrees, which coding agents create by the dozen. One is offered
/// only when removing it loses nothing: `git worktree remove` keeps the branch and its
/// commits, so what matters is anything uncommitted, unreachable, or in use.
public struct WorktreeScanner: StorageScanner {
  public let id = "worktrees"
  public let title = "Extra git worktrees"

  public init() {}

  static let ruleID = "worktree.git"
  static let idleDays = 14

  /// One entry from `git worktree list --porcelain`.
  struct Entry: Sendable {
    var path: String
    var head: String?
    /// Short branch name, or `nil` when detached.
    var branch: String?
    var detached = false
    var bare = false
    var locked: String?
    var prunable = false
  }

  /// What a repository says about its branches, gathered once for all its worktrees.
  struct RepositoryFacts: Sendable {
    var defaultBranch: String?
    /// Branch name → (upstream, tracking summary such as "[ahead 2]").
    var upstreams: [String: (String, String)]
    var merged: Set<String>
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    guard !context.config.ignoredCategories.contains(.agentWorktrees), Git.executable != nil else { return [] }
    let tree = await ProjectTree.shared(context)
    let extraRoots = ProjectPlaces.extraAgentParents(context, covered: ProjectPlaces.roots(context))
    let protection = context.protection
    let cancel = context.cancel
    let extra = extraRoots.isEmpty ? ProjectTree() : await context.background {
      ProjectTree.walk(extraRoots, protection: protection, cancel: cancel, findCandidates: false)
    }
    let repositories = await context.background { Self.repositories(tree, extra, protection) }
    guard !repositories.isEmpty, !context.cancel.isCancelled else { return [] }
    let busy = await context.background { WorkingDirectories.current() }

    let batches = await forEachConcurrently(repositories, limit: 3) { repository in
      if context.cancel.isCancelled { return [Finding]() }
      return await Self.examine(repository, context, busy: busy)
    }
    var seen = Set<String>()
    return batches.flatMap { $0 }.filter { seen.insert($0.paths[0]).inserted }
  }

  /// Repositories that have linked worktrees: those with a `.git/worktrees` folder, and
  /// the owners of every linked checkout the walk met.
  static func repositories(_ tree: ProjectTree, _ extra: ProjectTree, _ protection: Protection) -> [String] {
    var ordered: [String] = []
    var seen = Set<String>()
    func add(_ path: String) {
      let cleaned = Protection.clean(path)
      if FileFacts.isDirectory(cleaned), seen.insert(cleaned).inserted { ordered.append(cleaned) }
    }
    for repository in tree.repositories + extra.repositories where FileFacts.isDirectory(repository + "/.git/worktrees") {
      add(repository)
    }
    for checkout in tree.checkouts + extra.checkouts {
      guard let gitDir = Git.gitDirectory(of: checkout),
            let owner = Git.owningRepository(ofWorktreeGitDirectory: gitDir) else { continue }
      add(owner)
    }
    return ordered
  }

  static func parse(_ porcelain: String) -> [Entry] {
    var entries: [Entry] = []
    var current: Entry?
    for field in porcelain.split(separator: "\0", omittingEmptySubsequences: false) {
      if field.isEmpty {
        if let entry = current { entries.append(entry) }
        current = nil
        continue
      }
      let parts = field.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
      let key = String(parts[0])
      let value = parts.count > 1 ? String(parts[1]) : ""
      switch key {
      case "worktree": current = Entry(path: Protection.clean(value))
      case "HEAD": current?.head = value
      case "branch": current?.branch = value.hasPrefix("refs/heads/") ? String(value.dropFirst("refs/heads/".count)) : value
      case "detached": current?.detached = true
      case "bare": current?.bare = true
      case "locked": current?.locked = value
      case "prunable": current?.prunable = true
      default: break
      }
    }
    if let entry = current { entries.append(entry) }
    return entries
  }

  static func examine(_ repository: String, _ context: ScanContext, busy: [String]) async -> [Finding] {
    guard let list = await Git.run(["worktree", "list", "--porcelain", "-z"], in: repository), list.succeeded else { return [] }
    let entries = parse(list.stdout)
    guard let main = entries.first, entries.count > 1 else { return [] }
    let candidates = entries.dropFirst().filter { entry in
      !entry.prunable && !entry.bare && FileFacts.isDirectory(entry.path) && context.protection.canScan(entry.path)
    }
    guard !candidates.isEmpty else { return [] }
    let facts = await repositoryFacts(main.path)
    var findings: [Finding] = []
    for entry in candidates {
      if context.cancel.isCancelled { break }
      if let finding = await examine(entry, main: main, facts: facts, context, busy: busy) { findings.append(finding) }
    }
    return findings
  }

  static func repositoryFacts(_ repository: String) async -> RepositoryFacts {
    var facts = RepositoryFacts(defaultBranch: nil, upstreams: [:], merged: [])
    if let heads = await Git.run(
      ["for-each-ref", "--format=%(refname:short)%09%(upstream:short)%09%(upstream:track)", "refs/heads"], in: repository
    ), heads.succeeded {
      for line in heads.stdout.split(separator: "\n") {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { continue }
        facts.upstreams[parts[0]] = (parts[1], parts[2])
      }
    }
    if let remote = await Git.run(["symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"], in: repository), remote.succeeded {
      let name = remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty { facts.defaultBranch = name }
    }
    if facts.defaultBranch == nil {
      facts.defaultBranch = ["main", "master", "trunk"].first { facts.upstreams[$0] != nil }
    }
    if let target = facts.defaultBranch,
       let merged = await Git.run(["for-each-ref", "--merged=\(target)", "--format=%(refname:short)", "refs/heads"], in: repository),
       merged.succeeded {
      facts.merged = Set(merged.stdout.split(separator: "\n").map(String.init))
    }
    return facts
  }

  /// Folders a protected-file search skips: they hold only installed packages, package
  /// checkouts and build products, whose own keys, profiles and agent files aren't the
  /// person's. `SourcePackages` is where Xcode checks out Swift packages, whatever the
  /// derived-data folder is called.
  static let regenerated: Set<String> = [
    "node_modules", "Pods", ".build", "DerivedData", "SourcePackages", ".venv", "venv", "__pycache__",
    ".next", ".turbo", ".gradle", ".dart_tool", ".tox", "bower_components",
  ]

  /// Built bundles: an app's embedded provisioning profile is a copy, not the original.
  static let builtBundles: Set<String> = ["app", "appex", "framework", "xcframework", "bundle", "dSYM"]

  /// Files with protected names (`.env`, keys, agent memory files) and other
  /// repositories inside a worktree. `git worktree remove` deletes ignored files too,
  /// so these have to be found before offering it.
  static func protectedEntries(in worktree: String, _ protection: Protection, _ cancel: CancelFlag) -> (files: [String], repositories: [String]) {
    var files: [String] = []
    var repositories: [String] = []
    var counter = 0
    DiskWalk.walk([worktree]) { entry in
      counter += 1
      if counter & 0x3FF == 0, cancel.isCancelled { return .stop }
      guard entry.depth > 0 else { return .proceed }
      let name = entry.name
      if name == ".git" {
        if entry.depth > 1 { repositories.append((entry.path as NSString).deletingLastPathComponent) }
        return entry.isDirectory ? .skip : .proceed
      }
      if entry.isDirectory {
        if regenerated.contains(name) { return .skip }
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, builtBundles.contains(ext) { return .skip }
      }
      if protection.isProtectedName(name) {
        files.append(entry.path)
        return entry.isDirectory ? .skip : .proceed
      }
      return .proceed
    }
    return (files, repositories)
  }

  static func examine(_ entry: Entry, main: Entry, facts: RepositoryFacts, _ context: ScanContext, busy: [String]) async -> Finding? {
    let path = entry.path
    let repositoryName = ((main.path as NSString).lastPathComponent as NSString).deletingPathExtension
    let shortHead = entry.head.map { String($0.prefix(7)) } ?? "unknown"
    var blockers: [Blocker] = []
    var evidence: [String] = []

    // Read git's bookkeeping before running anything in the worktree.
    let gitDir = Git.gitDirectory(of: path)
    let indexDate = gitDir.flatMap { FileFacts.modified($0 + "/index") }

    // 1. Anything uncommitted: modified, staged, or untracked and not ignored.
    if let status = await Git.run(["status", "--porcelain", "--untracked-files=normal", "-z"], in: path), status.succeeded {
      let (changed, untracked) = countStatus(status.stdout)
      if changed > 0 {
        let files = changed == 1 ? "1 uncommitted file" : "\(changed) uncommitted files"
        blockers.append(Blocker(.uncommittedWork, untracked > 0 ? "\(files) (\(untracked) untracked)" : files))
      } else {
        evidence.append("Working tree is clean: nothing modified, staged or untracked.")
      }
    } else {
      blockers.append(Blocker(.uncommittedWork, "Couldn't confirm the working tree is clean."))
    }

    // 2. A detached HEAD whose commit nothing else holds would become unreachable.
    if entry.detached {
      let holders = await Git.run(
        ["for-each-ref", "--contains", "HEAD", "--count=1", "--format=%(refname:short)", "refs/heads", "refs/tags", "refs/remotes"],
        in: path
      )
      let holder = holders.flatMap { $0.succeeded ? $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil } ?? ""
      if holders?.succeeded != true {
        blockers.append(Blocker(.uncommittedWork, "Couldn't check whether its detached commit \(shortHead) is kept elsewhere."))
      } else if holder.isEmpty {
        blockers.append(Blocker(.uncommittedWork, "Detached at \(shortHead), a commit no branch or tag holds; removing the worktree would lose it."))
      } else {
        evidence.append("Detached at \(shortHead), a commit \(holder) also holds.")
      }
    }

    // 3. An operation in progress.
    if let gitDir {
      let states = [
        ("rebase-merge", "A rebase is in progress."), ("rebase-apply", "A rebase or patch is in progress."),
        ("MERGE_HEAD", "A merge is in progress."), ("CHERRY_PICK_HEAD", "A cherry-pick is in progress."),
        ("REVERT_HEAD", "A revert is in progress."), ("BISECT_LOG", "A bisect is in progress."),
        ("sequencer", "A multi-commit operation is in progress."),
      ]
      if let state = states.first(where: { FileFacts.exists(gitDir + "/" + $0.0) }) {
        blockers.append(Blocker(.uncommittedWork, state.1))
      }
    } else {
      blockers.append(Blocker(.uncommittedWork, "Couldn't find its git folder."))
    }

    // 4. Locked, or someone working in it right now.
    if let reason = entry.locked {
      let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
      blockers.append(Blocker(.inUse, trimmed.isEmpty ? "Locked in git." : "Locked in git: \(trimmed.prefix(100))"))
    }
    if WorkingDirectories.anyInside(path, busy) {
      blockers.append(Blocker(.inUse, "An agent or terminal is working here"))
    }

    // 5. Files git ignores that Glade protects, and repositories inside it.
    let protection = context.protection
    let cancel = context.cancel
    let found = await context.background { protectedEntries(in: path, protection, cancel) }
    if let nested = found.repositories.first {
      blockers.append(Blocker(.uncommittedWork, "Contains another repository (\(relative(nested, to: path))), which removing the worktree would delete."))
    }
    if !found.files.isEmpty {
      let untracked = await untrackedAmong(found.files, in: path)
      if let example = untracked.first {
        let count = untracked.count == 1 ? "a file" : "\(untracked.count) files"
        blockers.append(Blocker(.uncommittedWork, "Holds \(count) git doesn't track that Glade protects, such as \(relative(example, to: path))."))
      }
    }

    // Informative facts about the branch.
    if let branch = entry.branch {
      evidence.insert("On branch \(branch).", at: 0)
      if let target = facts.defaultBranch {
        evidence.append(facts.merged.contains(branch)
          ? "Merged into \(target)."
          : "Not merged into \(target); its commits stay on the branch after removal.")
      }
      let (upstream, track) = facts.upstreams[branch] ?? ("", "")
      if upstream.isEmpty {
        evidence.append("No upstream branch; its commits stay in the repository after removal.")
      } else if track.contains("gone") {
        evidence.append("Its upstream \(upstream) no longer exists on the remote.")
      } else if let ahead = aheadCount(track) {
        evidence.append("\(ahead == 1 ? "1 commit" : "\(ahead) commits") not pushed to \(upstream); they stay on the branch after removal.")
      } else {
        evidence.append("Pushed to \(upstream), with nothing unpushed.")
      }
    }

    // Idle time: the newest of its last commit and its index.
    var lastCommit: Date?
    if let log = await Git.run(["log", "-1", "--format=%ct"], in: path), log.succeeded,
       let seconds = TimeInterval(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
      lastCommit = Date(timeIntervalSince1970: seconds)
    }
    let lastUsed = [lastCommit, indexDate].compactMap { $0 }.max()
    if let days = context.days(since: lastUsed) {
      evidence.append("Last worked on \(FileFacts.daysAgo(days)).")
    }
    if let agent = agentName(path) { evidence.append("Made by \(agent).") }

    let measure = await context.measure([path])
    guard !measure.cancelled else { return nil }
    if measure.containsStrict {
      blockers.append(Blocker(.inUse, "Contains a library or backup that must stay whole."))
    }
    let verdict = protection.verdict(forRemoving: path, allowRepository: true)
    if !verdict.isAllowed { blockers.append(Blocker(.inUse, verdict.explanation)) }
    if measure.unreadable > 0 {
      evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.")
    }
    var level: CleanLevel? = .balanced
    if protection.isPersonalArea(path) {
      level = nil
      evidence.append("In a personal folder, so it's only removed when you choose it.")
    }
    if !blockers.isEmpty { level = nil }

    let label = entry.branch ?? "detached \(shortHead)"
    return Finding(
      id: Finding.makeID(rule: ruleID, path: path), ruleID: ruleID, category: .agentWorktrees,
      title: "Worktree – \(repositoryName) / \(label)",
      detail: "An extra checkout of this repository, often made by a coding agent; removing it keeps its branch and commits, and `git worktree add` recreates it.",
      paths: [path], bytes: measure.bytes, fileCount: measure.files, lastUsed: lastUsed,
      recovery: .reinstall, risk: .caution, blockers: blockers, method: .gitWorktree(repository: main.path),
      evidence: evidence, project: repositoryName, autoLevel: level, idleDaysRequired: idleDays
    )
  }

  /// Entries in `git status --porcelain -z`: (all, untracked). Renames carry an extra field.
  static func countStatus(_ output: String) -> (Int, Int) {
    var total = 0, untracked = 0
    var skipNext = false
    for field in output.split(separator: "\0") {
      if skipNext {
        skipNext = false
        continue
      }
      guard field.count >= 3 else { continue }
      total += 1
      if field.hasPrefix("??") { untracked += 1 }
      if let first = field.first, first == "R" || first == "C" { skipNext = true }
    }
    return (total, untracked)
  }

  static func aheadCount(_ track: String) -> Int? {
    guard let range = track.range(of: "ahead ") else { return nil }
    let digits = track[range.upperBound...].prefix { $0.isNumber }
    return Int(digits)
  }

  /// Which of these files git doesn't track. All of them when git can't say.
  static func untrackedAmong(_ files: [String], in worktree: String) async -> [String] {
    let relativePaths = files.map { relative($0, to: worktree) }
    guard let result = await Git.run(["--literal-pathspecs", "ls-files", "-z", "--"] + relativePaths, in: worktree),
          result.succeeded else { return relativePaths }
    let tracked = Set(result.stdout.split(separator: "\0").map(String.init))
    return relativePaths.filter { path in
      !tracked.contains(path) && !tracked.contains { $0.hasPrefix(path + "/") }
    }
  }

  static func relative(_ path: String, to base: String) -> String {
    path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
  }

  static func agentName(_ path: String) -> String? {
    if path.contains("/.claude/worktrees/") { return "Claude Code" }
    if path.contains("/.codex/worktrees/") { return "Codex" }
    if path.contains("/.cursor/worktrees/") { return "Cursor" }
    if path.contains("/.t3/worktrees/") { return "T3 Code" }
    if path.contains("/conductor/") { return "Conductor" }
    return nil
  }
}
