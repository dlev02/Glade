import Foundation

/// A folder that holds code projects, and how deep to look inside it.
struct ProjectRoot: Sendable, Hashable {
  var path: String
  var maxDepth: Int
}

/// Where the person’s code projects live.
enum ProjectPlaces {
  /// Folders people commonly keep projects in, relative to home. `*` matches one component.
  static let usual: [String] = [
    "~/Developer", "~/Projects", "~/Code", "~/code", "~/src", "~/dev", "~/Development",
    "~/workspace", "~/repos", "~/git", "~/GitHub", "~/Documents/GitHub", "~/Documents/Projects",
    "~/Documents/Developer", "~/Library/Bitrig/Users/*/Projects",
  ]

  /// Where coding agents keep the worktrees they create. Also walked for projects, since
  /// each worktree is a full checkout with its own dependencies.
  /// `~/.t3/worktrees` rather than all of `~/.t3`: its `tools` folder holds installed tools.
  static let agentWorktreeParents: [String] = [
    "~/conductor", "~/.codex/worktrees", "~/.cursor/worktrees", "~/.claude/worktrees", "~/.t3/worktrees",
  ]

  static let deepLimit = 8
  /// The Desktop is a personal area that rarely holds projects; look only near the top.
  static let shallowLimit = 3

  /// The folders to walk: the configured ones, or the usual places that exist. Roots that
  /// sit in a protected zone (iCloud Drive, Dropbox and the like) are left out, as are
  /// roots inside another root.
  static func roots(_ context: ScanContext) -> [ProjectRoot] {
    var candidates: [ProjectRoot] = []
    if !context.config.projectRoots.isEmpty {
      for pattern in context.config.projectRoots {
        for path in DiskWalk.expand(pattern, home: context.home) {
          candidates.append(ProjectRoot(path: path, maxDepth: deepLimit))
        }
      }
    } else {
      for pattern in usual + agentWorktreeParents {
        for path in DiskWalk.expand(pattern, home: context.home) {
          candidates.append(ProjectRoot(path: path, maxDepth: deepLimit))
        }
      }
      for path in DiskWalk.expand("~/Desktop", home: context.home) {
        candidates.append(ProjectRoot(path: path, maxDepth: shallowLimit))
      }
    }
    return usable(candidates, context)
  }

  /// Agent worktree parents that the project roots don’t already cover.
  static func extraAgentParents(_ context: ScanContext, covered: [ProjectRoot]) -> [ProjectRoot] {
    var extra: [ProjectRoot] = []
    for pattern in agentWorktreeParents {
      for path in DiskWalk.expand(pattern, home: context.home) {
        extra.append(ProjectRoot(path: path, maxDepth: 3))
      }
    }
    let resolved = usable(extra, context)
    return resolved.filter { root in
      !covered.contains { root.path == $0.path || root.path.hasPrefix($0.path + "/") }
    }
  }

  private static func usable(_ candidates: [ProjectRoot], _ context: ScanContext) -> [ProjectRoot] {
    var resolved: [ProjectRoot] = []
    for candidate in candidates {
      let cleaned = Protection.clean(candidate.path)
      let real = Protection.clean(URL(fileURLWithPath: cleaned).resolvingSymlinksInPath().path)
      var info = stat()
      guard stat(real, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
      guard context.protection.canScan(cleaned), context.protection.canScan(real) else {
        Log.info(.scan, "Skipped project folder \(cleaned): it’s in a protected zone")
        continue
      }
      if !resolved.contains(where: { $0.path == real }) {
        resolved.append(ProjectRoot(path: real, maxDepth: candidate.maxDepth))
      }
    }
    // Drop roots that sit inside a deeper-walked root; that root’s walk covers them.
    return resolved.filter { root in
      !resolved.contains { other in
        other.path != root.path && root.path.hasPrefix(other.path + "/") && other.maxDepth >= root.maxDepth
      }
    }
  }
}

/// What one walk of the project folders turned up. Both the project and the worktree
/// scanners need it, so it’s built once per scan and shared.
struct ProjectTree: Sendable {
  struct Candidate: Sendable, Hashable {
    /// The folder that would be removed.
    var path: String
    /// Index into `ProjectRules.all`.
    var rule: Int
    /// The project folder the walk started from.
    var root: String
  }

  var candidates: [Candidate] = []
  /// Folders with a `.git` directory: ordinary repositories.
  var repositories: [String] = []
  /// Folders with a `.git` file: linked worktrees and submodules.
  var checkouts: [String] = []

  /// Builds the tree for this scan, or waits for the one already being built.
  static func shared(_ context: ScanContext) async -> ProjectTree {
    let roots = ProjectPlaces.roots(context)
    let key = "\(context.now.timeIntervalSince1970)|\(context.home)|" + roots.map { "\($0.path):\($0.maxDepth)" }.joined(separator: "|")
    return await ProjectTreeCache.shared.tree(key: key) {
      let protection = context.protection
      let cancel = context.cancel
      let started = Date()
      let tree = await context.background {
        ProjectTree.walk(roots, protection: protection, cancel: cancel, findCandidates: true)
      }
      Log.info(.scan, "Project walk: \(roots.count) folders, \(tree.repositories.count) repositories, \(tree.checkouts.count) linked checkouts, \(tree.candidates.count) candidates in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
      return tree
    }
  }

  /// Bundles, packages and other folders that never hold projects worth walking into.
  static let packageExtensions: Set<String> = [
    "app", "bundle", "framework", "xcframework", "xcodeproj", "xcworkspace", "xcassets", "plugin",
    "kext", "appex", "playground", "xcarchive", "dSYM", "lproj", "docc", "xcresult", "photoslibrary",
  ]

  /// Walks the roots, depth-limited, pruning at every match so nothing inside a
  /// dependency folder is ever visited.
  static func walk(_ roots: [ProjectRoot], protection: Protection, cancel: CancelFlag, findCandidates: Bool) -> ProjectTree {
    var tree = ProjectTree()
    var counter = 0
    var stopped = false
    for root in roots {
      if stopped { break }
      DiskWalk.walk([root.path]) { entry in
        counter += 1
        if counter & 0x3FF == 0, cancel.isCancelled {
          stopped = true
          return .stop
        }
        let depth = entry.depth
        guard depth > 0 else { return .proceed }
        let name = entry.name
        if name == ".git" {
          let parent = (entry.path as NSString).deletingLastPathComponent
          if entry.isDirectory {
            tree.repositories.append(parent)
            return .skip
          }
          if !entry.isSymlink { tree.checkouts.append(parent) }
          return .proceed
        }
        guard entry.isDirectory else { return .proceed }
        if depth > root.maxDepth { return .skip }
        if protection.isProtectedName(name) { return .skip }
        let path = entry.path
        let parent = (path as NSString).deletingLastPathComponent
        if findCandidates, let match = ProjectRules.match(name: name, parent: parent, folder: path) {
          if protection.canScan(match.path) {
            tree.candidates.append(Candidate(path: match.path, rule: match.rule, root: root.path))
          }
          return .skip
        }
        if ProjectRules.prunedNames.contains(name) { return .skip }
        if name.hasPrefix(".") {
          // Agents keep worktrees in `<repo>/.claude/worktrees`; nothing else hidden is walked.
          return name == ".claude" ? .proceed : .skip
        }
        if (parent as NSString).lastPathComponent == ".claude", name != "worktrees" { return .skip }
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, packageExtensions.contains(ext) { return .skip }
        return .proceed
      }
    }
    return tree
  }
}

/// Remembers the most recent project walk so scanners running side by side share it.
actor ProjectTreeCache {
  static let shared = ProjectTreeCache()

  private var key: String?
  private var task: Task<ProjectTree, Never>?

  func tree(key: String, build: @escaping @Sendable () async -> ProjectTree) async -> ProjectTree {
    if key == self.key, let task { return await task.value }
    let task = Task { await build() }
    self.key = key
    self.task = task
    return await task.value
  }
}

// MARK: - Git

/// Read-only git queries. Every call has a short timeout, takes no optional locks (so
/// `git status` never rewrites the index), and never prompts.
enum Git {
  /// The git to run, or `nil` when only Apple’s installer stub is present (running it
  /// would pop up a dialog offering to install the developer tools).
  static let executable: String? = {
    let manager = FileManager.default
    for candidate in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where manager.isExecutableFile(atPath: candidate) {
      return candidate
    }
    let developerDirs = [
      URL(fileURLWithPath: "/var/db/xcode_select_link").resolvingSymlinksInPath().path,
      "/Library/Developer/CommandLineTools",
      "/Applications/Xcode.app/Contents/Developer",
    ]
    if developerDirs.contains(where: { manager.isExecutableFile(atPath: $0 + "/usr/bin/git") }) {
      return "/usr/bin/git"
    }
    Log.info(.scan, "Git isn’t installed; repositories won’t be examined")
    return nil
  }()

  /// Runs `git -C <directory> <arguments>`. `nil` when git is missing or couldn’t start.
  static func run(_ arguments: [String], in directory: String, input: String? = nil, timeout: TimeInterval = 5) async -> ShellResult? {
    guard let executable else { return nil }
    let environment = ["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"]
    do {
      return try await Shell.run(
        executable, ["-C", directory, "-c", "core.fsmonitor=false"] + arguments,
        input: input, environment: environment, timeout: timeout, quiet: true
      )
    } catch {
      Log.warning(.scan, "git couldn’t run in \(directory): \(error.localizedDescription)")
      return nil
    }
  }

  /// The git directory of a checkout: `<path>/.git` for a repository, or where its
  /// `.git` file points for a linked worktree or submodule.
  static func gitDirectory(of checkout: String) -> String? {
    let dotGit = checkout + "/.git"
    var info = stat()
    guard lstat(dotGit, &info) == 0 else { return nil }
    switch info.st_mode & S_IFMT {
    case S_IFDIR: return dotGit
    case S_IFREG:
      guard info.st_size < 4096, let text = try? String(contentsOfFile: dotGit, encoding: .utf8) else { return nil }
      guard let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return nil }
      let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
      guard !target.isEmpty else { return nil }
      return Protection.clean(target.hasPrefix("/") ? target : checkout + "/" + target)
    default: return nil
    }
  }

  /// For a linked worktree’s git directory, the repository it belongs to (the folder to
  /// run `git worktree` in). `nil` for anything else, including submodules.
  static func owningRepository(ofWorktreeGitDirectory gitDir: String) -> String? {
    let commonFile = gitDir + "/commondir"
    var info = stat()
    guard lstat(commonFile, &info) == 0, info.st_size < 4096,
          let text = try? String(contentsOfFile: commonFile, encoding: .utf8) else { return nil }
    let relative = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !relative.isEmpty else { return nil }
    let common = Protection.clean(relative.hasPrefix("/") ? relative : gitDir + "/" + relative)
    if (common as NSString).lastPathComponent == ".git" { return (common as NSString).deletingLastPathComponent }
    return common
  }

  /// The innermost repository or checkout containing a folder, found by looking for a
  /// `.git` entry in it and each folder above it.
  static func workTreeRoot(containing folder: String) -> String? {
    var current = Protection.clean(folder)
    while current != "/" && !current.isEmpty {
      var info = stat()
      if lstat(current + "/.git", &info) == 0 {
        let kind = info.st_mode & S_IFMT
        if kind == S_IFDIR || kind == S_IFREG { return current }
      }
      current = (current as NSString).deletingLastPathComponent
    }
    return nil
  }
}

// MARK: - Small file-system helpers

enum FileFacts {
  static func exists(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0
  }

  static func isDirectory(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
  }

  static func modified(_ path: String) -> Date? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
  }

  /// "today", "yesterday", "43 days ago".
  static func daysAgo(_ days: Int) -> String {
    switch days {
    case ..<1: "today"
    case 1: "yesterday"
    default: "\(days) days ago"
    }
  }
}

/// The working folders of this user’s running processes, so a scan can tell where a
/// terminal, editor or agent is at work.
enum WorkingDirectories {
  static func current() -> [String] {
    let uid = getuid()
    let needed = proc_listpids(UInt32(PROC_UID_ONLY), UInt32(uid), nil, 0)
    guard needed > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.size + 64)
    let filled = proc_listpids(UInt32(PROC_UID_ONLY), UInt32(uid), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard filled > 0 else { return [] }
    let own = getpid()
    var folders = Set<String>()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    for pid in pids.prefix(Int(filled) / MemoryLayout<pid_t>.size) where pid > 0 && pid != own {
      var info = proc_vnodepathinfo()
      guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { continue }
      let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
      }
      if path.count > 1 { folders.insert(Protection.clean(path)) }
    }
    return Array(folders)
  }

  /// Whether any of `folders` is `path` or inside it.
  static func anyInside(_ path: String, _ folders: [String]) -> Bool {
    let cleaned = Protection.clean(path)
    let real = Protection.clean(URL(fileURLWithPath: cleaned).resolvingSymlinksInPath().path)
    return folders.contains { folder in
      folder == cleaned || folder.hasPrefix(cleaned + "/") || folder == real || folder.hasPrefix(real + "/")
    }
  }
}

/// Runs work over items a few at a time.
func forEachConcurrently<Item: Sendable, Result: Sendable>(
  _ items: [Item], limit: Int, _ work: @escaping @Sendable (Item) async -> Result
) async -> [Result] {
  await withTaskGroup(of: (Int, Result).self) { group in
    var results: [(Int, Result)] = []
    var next = 0
    for _ in 0..<min(limit, items.count) {
      let index = next
      group.addTask { (index, await work(items[index])) }
      next += 1
    }
    for await result in group {
      results.append(result)
      if next < items.count {
        let index = next
        group.addTask { (index, await work(items[index])) }
        next += 1
      }
    }
    return results.sorted { $0.0 < $1.0 }.map(\.1)
  }
}
