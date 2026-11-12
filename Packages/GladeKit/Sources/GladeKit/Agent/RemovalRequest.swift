import Foundation

/// Reads what a person typed to the Assistant for a request to remove something they
/// name ("remove the Adobe apps", "uninstall iMovie"), and finds the apps and findings
/// it refers to. Matching is by words only: an app’s name, its developer’s part of the
/// bundle identifier ("adobe" in com.adobe.Photoshop), a finding’s title and owner.
public enum RemovalRequest {
  /// Words that ask for something to go.
  static let verbs: Set<String> = ["remove", "uninstall", "delete", "clear", "trash", "erase", "wipe", "bin", "ditch"]
  /// Phrases that do the same.
  static let phrases = ["get rid", "throw away", "throw out", "take off", "clean out", "clean up"]
  /// Words that mean apps in general.
  static let appWords: Set<String> = ["app", "apps", "application", "applications", "uninstall", "program", "programs", "software"]
  /// Words that ask for space rather than for something named.
  static let spaceWords: Set<String> = ["space", "storage", "gb", "mb", "tb", "gigabytes", "room"]

  /// Words that name nothing in particular, so they never decide a match.
  static let filler: Set<String> = Set([
    "a", "an", "the", "and", "or", "of", "to", "for", "from", "on", "in", "at", "by", "with", "my", "me", "i", "it", "its",
    "all", "any", "anything", "everything", "something", "related", "relating", "stuff", "things", "thing", "please",
    "can", "could", "would", "you", "your", "this", "that", "these", "those", "them", "they", "is", "are", "be", "do",
    "also", "too", "just", "only", "some", "other", "else", "out", "off", "up", "want", "wanna", "need", "like", "get",
    "rid", "throw", "away", "take", "make", "mac", "macbook", "computer", "laptop", "old", "unused", "used", "use",
    "never", "anymore", "more", "dont", "don't", "no", "not", "which", "what", "who", "how", "now", "here", "there",
    "both", "each", "every", "lot", "lots", "much", "many", "new", "one", "ones", "files", "file", "data", "folder",
    "folders", "clean", "free", "let", "lets", "let's", "via", "into", "about", "anyway", "made", "maker",
  ])
  .union(verbs).union(appWords).union(spaceWords)

  /// Words in app names too common to stand for one app on their own ("Studio",
  /// "Pro"): "Android Studio" is named by "android studio" or "android", not "studio".
  static let commonNameWords: Set<String> = [
    "pro", "studio", "code", "player", "music", "photo", "photos", "editor", "desktop", "viewer", "reader", "browser",
    "mail", "calendar", "notes", "video", "tv", "cloud", "drive", "office", "helper", "launcher", "manager", "tool",
    "tools", "utility", "lite", "plus", "free", "beta", "preview", "update", "updater", "installer", "assistant",
    "center", "centre", "connect", "express", "mobile", "design", "creative", "suite", "edition", "classic", "mini",
    "air", "max", "home", "web", "online", "client", "server", "app", "apps", "for", "the", "and", "of", "x", "hd",
    "community", "insiders", "nightly", "canary", "developer", "dev", "go", "one", "my", "new", "open", "live",
  ]

  /// Parts of bundle identifiers that don’t name a developer.
  static let commonVendors: Set<String> = ["app", "apps", "mac", "macos", "com", "org", "net", "io", "co", "dev", "www", "inc", "ltd", "llc"]

  // MARK: What kind of request

  /// Whether a message asks to remove, uninstall, delete or clear something.
  public static func asksToRemove(_ message: String) -> Bool {
    let lowered = message.lowercased()
    return !Set(words(message)).isDisjoint(with: verbs) || phrases.contains { lowered.contains($0) }
  }

  /// Whether a message should get a proposal (a list of things to remove, which the
  /// person confirms) rather than a refined clean plan or a written answer: it asks to
  /// remove something, and either is about apps or names something on this Mac. A
  /// request for an amount of space ("delete 20 GB") stays with the clean plan.
  /// Without a scan, a removal request still counts, so the answer can say to scan.
  public static func wantsProposal(_ message: String, scan: ScanResult?) -> Bool {
    guard asksToRemove(message) else { return false }
    let words = Set(Self.words(message))
    if !words.isDisjoint(with: appWords) { return true }
    guard let scan else { return true }
    if !words.isDisjoint(with: spaceWords) || message.range(of: #"\d+\s*(gb|mb|tb)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
      return false
    }
    let request = Words(message)
    return scan.findings.contains { relevance($0, request) > 0 }
  }

  // MARK: Words

  /// The message’s words, lowercased, with possessives dropped: "Adobe’s" → "adobe".
  static func words(_ text: String) -> [String] {
    text.lowercased()
      .replacingOccurrences(of: "’", with: "'")
      .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
      .map { word in
        var word = word.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        if word.hasSuffix("'s") { word = String(word.dropLast(2)) }
        return word.replacingOccurrences(of: "'", with: "")
      }
      .filter { !$0.isEmpty }
  }

  /// A request’s words, prepared once for matching against many things.
  struct Words {
    /// Every run of one to four words, each run run together: "final cut pro" gives
    /// "final", "finalcut", "finalcutpro", "cut", …
    var runs: Set<String>
    /// Single words that aren’t filler, with plurals also as singulars.
    var significant: Set<String>

    init(_ text: String) {
      let all = RemovalRequest.words(text)
      var runs = Set<String>()
      for start in all.indices {
        var joined = ""
        for word in all[start..<min(all.count, start + 4)] {
          joined += word
          runs.insert(joined)
        }
      }
      var significant = Set<String>()
      for word in all where !RemovalRequest.filler.contains(word) && word.count >= 3 && !word.allSatisfy(\.isNumber) {
        significant.insert(word)
        if word.count > 3, word.hasSuffix("s") { significant.insert(String(word.dropLast())) }
      }
      // A plural run names the singular too: "adobe photoshops".
      for run in runs where run.count > 4 && run.hasSuffix("s") { runs.insert(String(run.dropLast())) }
      self.runs = runs
      self.significant = significant
    }
  }

  // MARK: Named

  /// Whether the person named this app or finding in their own words: its name (or a
  /// distinctive part of it), its developer, or the part of its bundle identifier that
  /// names the developer. Only named things start ticked.
  public static func isNamed(_ finding: Finding, in message: String) -> Bool {
    isNamed(finding, Words(message))
  }

  static func isNamed(_ finding: Finding, _ request: Words) -> Bool {
    var names = [finding.app?.name ?? finding.title]
    if let owner = finding.owner?.name, owner != names[0] { names.append(owner) }
    if names.contains(where: { nameMatches($0, request) }) { return true }
    return vendors(of: finding).contains { request.significant.contains($0) }
  }

  /// A name matches when the whole of it, or a run of two or more of its words, or one
  /// distinctive word of it, is among the request’s words.
  static func nameMatches(_ name: String, _ request: Words) -> Bool {
    let parts = words(name)
    guard !parts.isEmpty else { return false }
    let whole = parts.joined()
    // A one-word name that is also an everyday word ("Things") needs more than that word.
    if whole.count >= 3, request.runs.contains(whole), parts.count > 1 || !filler.contains(whole) { return true }
    for start in parts.indices {
      var joined = ""
      // A run of words only counts when one of them names something ("final cut"),
      // not when all are everyday words ("apps and").
      var namesSomething = false
      for (offset, word) in parts[start...].enumerated() {
        joined += word
        if !filler.contains(word), !word.allSatisfy(\.isNumber) { namesSomething = true }
        if offset == 0 {
          guard word.count >= 3, !word.allSatisfy(\.isNumber), !commonNameWords.contains(word), !filler.contains(word) else { continue }
          if request.significant.contains(word) { return true }
        } else if namesSomething, request.runs.contains(joined) {
          return true
        }
      }
    }
    return false
  }

  /// The developer parts of a finding’s bundle identifiers: "adobe" for
  /// com.adobe.Photoshop.
  static func vendors(of finding: Finding) -> Set<String> {
    var ids = finding.owner?.bundleIDs ?? []
    if let id = finding.app?.bundleID { ids.append(id) }
    var found = Set<String>()
    for id in ids {
      guard let vendor = InstalledApps.vendor(of: id), let token = vendor.split(separator: ".").last.map(String.init) else { continue }
      if token.count >= 3, !commonVendors.contains(token) { found.insert(token) }
    }
    return found
  }

  // MARK: Relevance

  /// How strongly a finding matches the request: 3 when it’s named, 1 when a word of
  /// its title or category matches, 0 otherwise.
  static func relevance(_ finding: Finding, _ request: Words) -> Int {
    if isNamed(finding, request) { return 3 }
    let titleWords = Set(words(finding.title + " " + finding.category.title)).subtracting(filler)
    var matched = false
    for word in titleWords where word.count >= 4 {
      if request.significant.contains(word) || (word.hasSuffix("s") && request.significant.contains(String(word.dropLast()))) {
        matched = true
        break
      }
    }
    return matched ? 1 : 0
  }

  /// The apps and findings worth showing the model for this request, most relevant
  /// first: what it names, then what its words match. When it’s about apps and matches
  /// nothing, the installed apps longest unused and largest. Findings inside another
  /// finding are left out; they go with it.
  public static func candidates(for message: String, scan: ScanResult, limit: Int, now: Date = Date()) -> [Finding] {
    let request = Words(message)
    let pool = scan.findings.filter { $0.within == nil }
    var scored: [(Finding, Int)] = pool.compactMap { finding in
      let score = relevance(finding, request)
      return score > 0 ? (finding, score) : nil
    }
    scored.sort { lhs, rhs in
      if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
      let lhsApp = lhs.0.category == .installedApps, rhsApp = rhs.0.category == .installedApps
      if lhsApp != rhsApp { return lhsApp }
      return lhs.0.bytes > rhs.0.bytes
    }
    let chosen = scored.prefix(limit).map(\.0)
    // About apps in general ("uninstall apps I never use") and naming none: the apps
    // themselves are the candidates. Otherwise only what matched is sent.
    guard chosen.isEmpty, !Set(words(message)).isDisjoint(with: appWords) else { return chosen }
    return Array(pool.filter { $0.category == .installedApps }.sorted { priority($0, now: now) > priority($1, now: now) }.prefix(limit))
  }

  /// Big apps not opened for a long time first, as the Storage list orders them.
  private static func priority(_ app: Finding, now: Date) -> Double {
    let days = Double(app.idleDays(asOf: now) ?? 30)
    return Double(app.bytes) * min(max(days / 30, 0.25), 12)
  }
}
