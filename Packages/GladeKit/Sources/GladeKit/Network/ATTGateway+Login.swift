import CryptoKit
import Foundation

/// Signing in to an AT&T gateway with its Device Access Code. The gateway hands out a
/// one-time nonce with a session cookie, and the browser sends `md5(code + nonce)`, so
/// the code itself never crosses the network; Glade does the same.
extension ATTGateway {
  /// A signed-in session, for reading pages that need the code.
  struct Session: Sendable {
    let host: String
    let urlSession: URLSession

    func page(_ path: String) async -> String? {
      guard let url = URL(string: "http://\(host)\(path)") else { return nil }
      guard let (data, response) = try? await urlSession.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      return String(decoding: data, as: UTF8.self)
    }
  }

  static func signIn(host: String, code: String) async throws -> Session {
    guard NetworkTargets.isPrivate(host) else { throw RouterAccessError.unreachable }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = HTTPCookieStorage()
    configuration.httpCookieAcceptPolicy = .always
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 15
    let session = URLSession(configuration: configuration, delegate: SameHostRedirects(), delegateQueue: nil)
    guard let loginURL = URL(string: "http://\(host)/cgi-bin/login.ha") else { throw RouterAccessError.unreachable }
    // The first visit sets the cookie; the second shows the form with its nonce.
    _ = try? await session.data(from: loginURL)
    guard let (formData, _) = try? await session.data(from: loginURL) else { throw RouterAccessError.unreachable }
    let form = String(decoding: formData, as: UTF8.self)
    guard let nonce = HTMLRow.matches(#"name="nonce"\s+value="([^"]+)""#, in: form).first else {
      Log.warning(.network, "The gateway’s login page had no nonce")
      throw RouterAccessError.unreachable
    }
    let hash = Insecure.MD5.hash(data: Data((code + nonce).utf8)).map { String(format: "%02x", $0) }.joined()
    var request = URLRequest(url: loginURL)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let fields = [
      ("nonce", nonce), ("password", String(repeating: "*", count: code.count)), ("hashpassword", hash), ("Continue", "Continue"),
    ]
    request.httpBody = Data(fields.map { "\($0)=\(formEncode($1))" }.joined(separator: "&").utf8)
    guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw RouterAccessError.unreachable
    }
    let reply = String(decoding: data, as: UTF8.self)
    // A refused code shows the form again.
    if reply.contains(#"name="hashpassword""#) || reply.contains("Access Code Required") {
      Log.info(.network, "The gateway refused the access code")
      throw RouterAccessError.wrongCode
    }
    Log.info(.network, "Signed in to the AT&T gateway")
    return Session(host: host, urlSession: session)
  }

  static func formEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._*")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}

extension RouterReader {
  /// Checks a router password by signing in, and keeps it in the Keychain if it works.
  public static func saveAccess(_ code: String, router host: String) async throws {
    guard let report = await read(router: host, maximumAge: 0), report.kind == "AT&T gateway", let model = report.model else {
      throw RouterAccessError.notSupported
    }
    _ = try await ATTGateway.signIn(host: host, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
    try RouterCredentials.save(code.trimmingCharacters(in: .whitespacesAndNewlines), account: RouterCredentials.account(model: model, host: host))
  }

  /// Whether Glade has a working password for this router.
  public static func hasAccess(_ report: RouterReport, host: String) -> Bool {
    guard let model = report.model else { return false }
    return RouterCredentials.has(account: RouterCredentials.account(model: model, host: host))
  }

  public static func forgetAccess(_ report: RouterReport, host: String) {
    guard let model = report.model else { return }
    RouterCredentials.delete(account: RouterCredentials.account(model: model, host: host))
  }

  /// Signs in with the saved password, for reading or, later, changing settings.
  static func session(_ report: RouterReport, host: String) async throws -> ATTGateway.Session {
    guard let model = report.model, let code = RouterCredentials.read(account: RouterCredentials.account(model: model, host: host)) else {
      throw RouterAccessError.wrongCode
    }
    return try await ATTGateway.signIn(host: host, code: code)
  }

  /// Checks the saved password still works.
  public static func checkAccess(_ report: RouterReport, host: String) async -> Bool {
    (try? await session(report, host: host)) != nil
  }
}
