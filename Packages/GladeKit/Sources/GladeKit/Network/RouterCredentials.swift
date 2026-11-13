import Foundation
import Security

/// A router’s admin password (an AT&T gateway’s Device Access Code), kept in the
/// person’s Keychain and read only by the code that logs in to that router. It never
/// reaches an AI, a log, the command line’s arguments or the MCP server; nothing in
/// Glade can print it back.
public enum RouterCredentials {
  static let service = "Glade router access"

  /// The Keychain account: the router’s model and serial number, so another gateway at
  /// the same address (every BGW320 is 192.168.1.254) is never offered this password.
  public static func account(model: String, serial: String?, host: String) -> String {
    serial.map { "\(model) \($0)" } ?? "\(model) at \(host)"
  }

  public static func has(account: String) -> Bool {
    var query = base(account)
    query[kSecReturnAttributes as String] = true
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
  }

  /// Saves or replaces the password. Not synced through iCloud.
  public static func save(_ secret: String, account: String) throws {
    let data = Data(secret.utf8)
    let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = base(account)
      item[kSecValueData as String] = data
      item[kSecAttrLabel as String] = "Glade: \(account)"
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      let added = SecItemAdd(item as CFDictionary, nil)
      guard added == errSecSuccess else { throw failure(added) }
    } else if status != errSecSuccess {
      throw failure(status)
    }
    Log.info(.network, "Saved router access for \(account) in the Keychain")
  }

  public static func delete(account: String) {
    let status = SecItemDelete(base(account) as CFDictionary)
    if status != errSecSuccess, status != errSecItemNotFound { Log.warning(.network, "Couldn’t remove router access: OSStatus \(status)") }
  }

  /// Only for the code that logs in to the router.
  static func read(account: String) -> String? {
    var query = base(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      if status != errSecItemNotFound { Log.warning(.network, "Couldn’t read router access: OSStatus \(status)") }
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func base(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  static func failure(_ status: OSStatus) -> Error {
    Log.warning(.network, "Keychain refused router access: OSStatus \(status)")
    return RouterAccessError.keychain(status)
  }
}

public enum RouterAccessError: Error, LocalizedError {
  case keychain(OSStatus)
  case notSupported
  case wrongCode
  case unreachable

  public var errorDescription: String? {
    switch self {
    case .keychain(let status): "The Keychain wouldn’t keep it (error \(status))."
    case .notSupported: "Glade can only sign in to AT&T gateways so far."
    case .wrongCode: "The router didn’t accept that code. It’s printed on the gateway’s label as Device Access Code."
    case .unreachable: "The router didn’t answer. Are you on its network?"
    }
  }
}
