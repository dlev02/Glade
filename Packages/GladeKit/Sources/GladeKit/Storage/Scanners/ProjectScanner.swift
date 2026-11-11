import Foundation

/// Finds dependencies and build outputs inside code projects: folders that a command
/// or the next build puts back. Each is attributed to its project, and the project’s
/// idle time (not the folder’s, which installs keep fresh) decides when a clean level
/// may pick it.
public struct ProjectScanner: StorageScanner {
  public let id = "projects"
  public let title = "Project dependencies and build outputs"

  public init() {}

  static let minimumBytes: Int64 = 1_000_000
  static let idleDays = 14

  struct Project: Sendable {
    /// The repository or checkout root, or for folders outside git, the project folder.
    var root: String
    var isGit: Bool
    var candidates: [ProjectTree.Candidate]
    /// The repository’s name; for a linked worktree, the repository it belongs to.
    var name: String = ""
    /// For a linked worktree, its own folder name, shown alongside the repository’s.
    var worktree: String?
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    let ignoredCategories = context.config.ignoredCategories
    let tree = await ProjectTree.shared(context)
    let wanted = tree.candidates.filter { !ignoredCategories.contains(ProjectRules.all[$0.rule].category) }
    guard !wanted.isEmpty, !context.cancel.isCancelled else { return [] }
    let projects = await context.background { Self.group(wanted) }
    let busy = await context.background { WorkingDirectories.current() }
    let batches = await forEachConcurrently(projects, limit: 4) { project in
      if context.cancel.isCancelled { return [Finding]() }
      return await Self.examine(project, context, busy: busy)
    }
    return batches.flatMap { $0 }
  }

  // MARK: Grouping

  /// The folder whose manifest proved the match (the parent, or for `vendor/bundle` the
  /// folder above `vendor`).
  static func manifestFolder(_ candidate: ProjectTree.Candidate) -> String {
    let parent = (candidate.path as NSString).deletingLastPathComponent
    return ProjectRules.all[candidate.rule].subpath == nil ? parent : (parent as NSString).deletingLastPathComponent
  }

  static func group(_ candidates: [ProjectTree.Candidate]) -> [Project] {
    var gitRoots: [String: String] = [:]
    var noGit = Set<String>()
    var projects: [String: Project] = [:]
    var order: [String] = []
    for candidate in candidates {
      let folder = manifestFolder(candidate)
      var root: String?
      if let known = gitRoots[folder] {
        root = known
      } else if !noGit.contains(folder) {
        root = Git.workTreeRoot(containing: folder)
        if let root { gitRoots[folder] = root } else { noGit.insert(folder) }
      }
      let key = root ?? topFolder(folder, under: candidate.root)
      if projects[key] == nil {
        projects[key] = Project(root: key, isGit: root != nil, candidates: [])
        order.append(key)
      }
      projects[key]?.candidates.append(candidate)
    }
    return order.compactMap { key in
      guard var project = projects[key] else { return nil }
      let folderName = (project.root as NSString).lastPathComponent
      project.name = folderName
      if project.isGit, let gitDir = Git.gitDirectory(of: project.root),
         let owner = Git.owningRepository(ofWorktreeGitDirectory: gitDir) {
        let ownerName = ((owner as NSString).lastPathComponent as NSString).deletingPathExtension
        if ownerName != folderName {
          project.name = ownerName
          project.worktree = folderName
        }
      }
      return project
    }
  }

  /// Outside git, a project is the top-level folder it sits in under the projects folder.
  static func topFolder(_ folder: String, under walkRoot: String) -> String {
    guard folder.hasPrefix(walkRoot + "/") else { return folder }
    let relative = folder.dropFirst(walkRoot.count + 1)
    guard let first = relative.split(separator: "/").first else { return folder }
    return walkRoot + "/" + first
  }

  // MARK: Examining one project

  static func examine(_ project: Project, _ context: ScanContext, busy: [String]) async -> [Finding] {
    // Git decides what is source: anything inside a repository must be ignored by it.
    var lastCommit: Date?
    var ignored = Set<String>()
    var gitAnswered = false
    if project.isGit {
      if let result = await Git.run(["log", "-1", "--format=%ct"], in: project.root), result.succeeded,
         let seconds = TimeInterval(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
        lastCommit = Date(timeIntervalSince1970: seconds)
      }
      let input = project.candidates.map(\.path).joined(separator: "\0") + "\0"
      if let result = await Git.run(["check-ignore", "--stdin", "-z"], in: project.root, input: input),
         !result.timedOut, result.status == 0 || result.status == 1 {
        gitAnswered = true
        for path in result.stdout.split(separator: "\0") { ignored.insert(String(path)) }
      } else {
        Log.warning(.scan, "Couldn’t ask git what it ignores in \(project.root); leaving its folders alone")
      }
    }

    var kept: [ProjectTree.Candidate] = []
    var rejected: [String] = []
    for candidate in project.candidates {
      let rule = ProjectRules.all[candidate.rule]
      let accepted = project.isGit ? (gitAnswered && ignored.contains(candidate.path)) : !rule.mustBeIgnored
      if accepted { kept.append(candidate) } else { rejected.append((candidate.path as NSString).lastPathComponent) }
    }
    if !rejected.isEmpty {
      Log.debug(.scan, "\(project.root): left \(rejected.count) folders alone that git doesn’t ignore or can’t vouch for (\(rejected.prefix(5).joined(separator: ", ")))")
    }
    guard !kept.isEmpty else { return [] }

    let activity = lastWorkedOn(project, kept: kept, lastCommit: lastCommit)
    let inUse = WorkingDirectories.anyInside(project.root, busy)

    var findings: [Finding] = []
    let singles = kept.filter { !ProjectRules.all[$0.rule].grouped }
    let measured = await forEachConcurrently(singles, limit: 6) { candidate in
      (candidate, await context.measure([candidate.path]))
    }
    for (candidate, measure) in measured {
      let rule = ProjectRules.all[candidate.rule]
      if let finding = make(
        rule, paths: [candidate.path], measure: measure, project: project, context: context,
        activity: activity, inUse: inUse, proof: proof(rule, candidate)
      ) {
        findings.append(finding)
      }
    }

    let groups = Dictionary(grouping: kept.filter { ProjectRules.all[$0.rule].grouped }) { ProjectRules.all[$0.rule].id }
    for (_, members) in groups.sorted(by: { $0.key < $1.key }) {
      guard let first = members.first else { continue }
      let rule = ProjectRules.all[first.rule]
      let paths = members.map(\.path).sorted()
      let measure = await context.measure(paths)
      let example = paths[0].hasPrefix(project.root + "/") ? String(paths[0].dropFirst(project.root.count + 1)) : paths[0]
      let proof = paths.count == 1
        ? "One cache folder, \(example), named the way only Python and its tools name them."
        : "\(paths.count) cache folders, for example \(example), named the way only Python and its tools name them."
      if let finding = make(
        rule, paths: paths, measure: measure, project: project, context: context,
        activity: activity, inUse: inUse, proof: proof
      ) {
        findings.append(finding)
      }
    }
    return findings
  }

  struct Activity: Sendable {
    var date: Date?
    var source: String
  }

  /// When someone last worked on the project: the newest of the last commit, git’s own
  /// bookkeeping files, the manifests, and the project folders themselves. Never the
  /// files inside the dependency folders, which every install rewrites.
  static func lastWorkedOn(_ project: Project, kept: [ProjectTree.Candidate], lastCommit: Date?) -> Activity {
    var signals: [(Date, String)] = []
    if let lastCommit { signals.append((lastCommit, "last commit")) }
    if project.isGit, let gitDir = Git.gitDirectory(of: project.root) {
      for file in ["index", "HEAD"] {
        if let date = FileFacts.modified(gitDir + "/" + file) { signals.append((date, "git activity")) }
      }
    }
    var folders = Set(kept.map(manifestFolder))
    folders.insert(project.root)
    for folder in folders {
      if let date = FileFacts.modified(folder) { signals.append((date, "files added or removed")) }
      for manifest in ProjectRules.manifests {
        if let date = FileFacts.modified(folder + "/" + manifest) { signals.append((date, manifest)) }
      }
    }
    guard let newest = signals.max(by: { $0.0 < $1.0 }) else { return Activity(date: nil, source: "") }
    return Activity(date: newest.0, source: newest.1)
  }

  static func proof(_ rule: ProjectRule, _ candidate: ProjectTree.Candidate) -> String {
    let folder = rule.subpath == nil ? candidate.path : (candidate.path as NSString).deletingLastPathComponent
    return rule.proofSentence(parent: manifestFolder(candidate), folder: folder)
  }

  static func make(
    _ rule: ProjectRule, paths: [String], measure: Measure, project: Project, context: ScanContext,
    activity: Activity, inUse: Bool, proof: String
  ) -> Finding? {
    guard measure.bytes >= minimumBytes, !measure.cancelled, let first = paths.first else { return nil }
    let name = project.name
    let shown = project.worktree.map { "\(name) (\($0))" } ?? name
    var evidence = [proof]
    evidence.append(project.isGit
      ? "Git ignores it, so it isn’t part of the project’s source."
      : "Not in a git repository.")
    if let days = context.days(since: activity.date) {
      evidence.append("Project last changed \(FileFacts.daysAgo(days)) (\(activity.source)).")
    }

    var risk = Risk.safe
    var level: CleanLevel? = rule.level
    var method = RemovalMethod.delete
    var blockers: [Blocker] = []
    let manifestFolder = rule.subpath == nil
      ? (first as NSString).deletingLastPathComponent
      : ((first as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent

    switch rule.id {
    case "project.venv":
      if !ProjectRules.pythonDependencyLists.contains(where: { FileFacts.exists(manifestFolder + "/" + $0) }) {
        risk = .caution
        level = nil
        evidence.append("No requirements file or pyproject.toml next to it, so its packages may have to be reinstalled by hand.")
      }
    case "project.terraform":
      if FileFacts.exists(first + "/environment") {
        risk = .caution
        level = nil
        evidence.append("It remembers the selected Terraform workspace; after removal, `terraform workspace select` is needed again.")
      }
    case "project.node_modules":
      if FileFacts.exists(first + "/.pnpm") {
        evidence.append("Installed by pnpm, which shares files with its store, so removing it may free less than shown.")
      }
    default:
      break
    }

    if measure.unreadable > 0 {
      evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.")
    }
    if measure.containsStrict {
      blockers.append(Blocker(.inUse, "Contains a library or backup that must stay whole."))
    }
    for path in paths {
      let verdict = context.protection.verdict(forRemoving: path)
      if !verdict.isAllowed {
        blockers.append(Blocker(.inUse, verdict.explanation))
        break
      }
    }
    if inUse {
      blockers.append(Blocker(.inUse, "A terminal, agent or dev server is working in this project."))
    }
    if context.protection.isPersonalArea(first) {
      method = .trash
      level = nil
      evidence.append("In a personal folder, so it goes to the Trash and is only removed when you choose it.")
    }
    if !blockers.isEmpty { level = nil }

    return Finding(
      id: Finding.makeID(rule: rule.id, path: rule.grouped ? project.root : first),
      ruleID: rule.id, category: rule.category, title: "\(rule.label) – \(shown)", detail: rule.detail,
      paths: paths, bytes: measure.bytes, fileCount: measure.files, lastUsed: activity.date,
      recovery: rule.recovery, risk: risk, blockers: blockers, method: method, evidence: evidence,
      project: name, autoLevel: level, idleDaysRequired: rule.idleDays
    )
  }
}
