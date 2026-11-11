import Compression
import CryptoKit
import Darwin
import Foundation

/// Reads a whole file into memory the careful way: never through a link, never a cloud
/// placeholder (that would download it), only a regular file of the expected length,
/// without changing its last-opened date and without filling the memory cache.
/// Everything the index looks at is read through here and then parsed from memory, so
/// no framework ever opens a person's file itself.
enum SafeRead {
  enum Failure: Error, CustomStringConvertible {
    case unreadable(Int32)
    case notRegular
    case cloudPlaceholder
    case changed
    case tooLarge

    var description: String {
      switch self {
      case .unreadable(let code): "couldn’t be opened (\(String(cString: strerror(code))))"
      case .notRegular: "not a regular file"
      case .cloudPlaceholder: "a cloud file that isn’t on this Mac"
      case .changed: "changed while being read"
      case .tooLarge: "too large"
      }
    }
  }

  /// The file's bytes. `limit` guards against a file that grew since the walk.
  static func data(_ path: String, limit: Int64) throws -> Data {
    try FileHashing.withoutAccessTimeUpdates { Result { try read(path, limit: limit) } }.get()
  }

  private static func read(_ path: String, limit: Int64) throws -> Data {
    do {
      let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { throw Failure.unreadable(errno) }
      defer { close(descriptor) }
      var info = stat()
      guard fstat(descriptor, &info) == 0 else { throw Failure.unreadable(errno) }
      guard (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.notRegular }
      guard info.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure.cloudPlaceholder }
      let length = Int64(info.st_size)
      guard length <= limit else { throw Failure.tooLarge }
      _ = fcntl(descriptor, F_NOCACHE, 1)
      var data = Data(count: Int(length))
      var offset = 0
      let ok = data.withUnsafeMutableBytes { buffer -> Bool in
        guard let base = buffer.baseAddress else { return length == 0 }
        while offset < Int(length) {
          let count = pread(descriptor, base + offset, Int(length) - offset, off_t(offset))
          if count < 0 { return false }
          if count == 0 { break }
          offset += count
        }
        return true
      }
      guard ok else { throw Failure.unreadable(errno) }
      guard offset == Int(length) else { throw Failure.changed }
      return data
    }
  }

  /// A short hex fingerprint of some bytes, used to tell exact copies apart.
  static func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  static func fingerprint(_ text: String) -> String {
    fingerprint(Data(text.utf8))
  }
}

/// Just enough of the zip format to pull a few named entries out of Office and iWork
/// files held in memory. Stored and deflated entries only; anything unusual returns nil.
struct ZipArchive {
  struct Entry {
    var name: String
    var method: UInt16
    var compressedSize: Int
    var size: Int
    var localOffset: Int
  }

  let data: Data
  let entries: [Entry]

  /// The largest entry this will inflate, so a hostile archive can't exhaust memory.
  static let entryLimit = 16 * 1024 * 1024

  init?(_ data: Data) {
    self.data = data
    let count = data.count
    guard count >= 22 else { return nil }
    // The end-of-central-directory record sits within the last 64 KB.
    var end = -1
    var position = count - 22
    let floor = max(0, count - 22 - 65_535)
    while position >= floor {
      if ZipArchive.u32(data, position) == 0x0605_4B50 { end = position; break }
      position -= 1
    }
    guard end >= 0 else { return nil }
    let total = Int(ZipArchive.u16(data, end + 10))
    var cursor = Int(ZipArchive.u32(data, end + 16))
    var found: [Entry] = []
    for _ in 0..<total {
      guard cursor + 46 <= count, ZipArchive.u32(data, cursor) == 0x0201_4B50 else { return nil }
      let method = ZipArchive.u16(data, cursor + 10)
      let compressed = Int(ZipArchive.u32(data, cursor + 20))
      let size = Int(ZipArchive.u32(data, cursor + 24))
      let nameLength = Int(ZipArchive.u16(data, cursor + 28))
      let extraLength = Int(ZipArchive.u16(data, cursor + 30))
      let commentLength = Int(ZipArchive.u16(data, cursor + 32))
      let local = Int(ZipArchive.u32(data, cursor + 42))
      guard cursor + 46 + nameLength <= count else { return nil }
      let start = data.startIndex + cursor + 46
      let name = String(decoding: data[start..<(start + nameLength)], as: UTF8.self)
      found.append(Entry(name: name, method: method, compressedSize: compressed, size: size, localOffset: local))
      cursor += 46 + nameLength + extraLength + commentLength
    }
    entries = found
  }

  func names() -> [String] { entries.map(\.name) }

  /// The uncompressed bytes of one entry.
  func read(_ name: String) -> Data? {
    guard let entry = entries.first(where: { $0.name == name }) else { return nil }
    return read(entry)
  }

  func read(_ entry: Entry) -> Data? {
    guard entry.size <= ZipArchive.entryLimit else { return nil }
    let header = entry.localOffset
    guard header + 30 <= data.count, ZipArchive.u32(data, header) == 0x0403_4B50 else { return nil }
    let start = header + 30 + Int(ZipArchive.u16(data, header + 26)) + Int(ZipArchive.u16(data, header + 28))
    guard start + entry.compressedSize <= data.count else { return nil }
    let slice = data[(data.startIndex + start)..<(data.startIndex + start + entry.compressedSize)]
    switch entry.method {
    case 0:
      return Data(slice)
    case 8:
      guard entry.size > 0 else { return Data() }
      var output = Data(count: entry.size)
      let written = output.withUnsafeMutableBytes { destination -> Int in
        slice.withUnsafeBytes { source -> Int in
          guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                let packed = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
          // Apple's ZLIB codec is raw DEFLATE, which is what zip stores.
          return compression_decode_buffer(target, entry.size, packed, entry.compressedSize, nil, COMPRESSION_ZLIB)
        }
      }
      return written == entry.size ? output : nil
    default:
      return nil
    }
  }

  private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
    let i = data.startIndex + offset
    return UInt16(data[i]) | UInt16(data[i + 1]) << 8
  }

  private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
    let i = data.startIndex + offset
    return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
  }
}
