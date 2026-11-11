import CryptoKit
import Darwin
import Foundation

/// Content fingerprints for finding identical files. Reads never follow links, never
/// open cloud placeholders, and don't change the files' last-opened dates.
enum FileHashing {
  /// How much of each end of a file the quick fingerprint reads.
  static let edgeBytes = 64 * 1024
  static let chunkBytes = 1 << 20

  /// SHA-256 of the first and last 64 KB plus the length. Files that differ here can't
  /// be identical; files that match still need the full hash.
  static func edgeHash(_ path: String, expectedLength: Int64) -> Data? {
    withoutAccessTimeUpdates {
      guard let file = OpenFile(path, expectedLength: expectedLength) else { return nil }
      defer { file.close() }
      var hasher = SHA256()
      var length = expectedLength
      withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
      var buffer = [UInt8](repeating: 0, count: edgeBytes)
      guard let head = file.read(into: &buffer, at: 0) else { return nil }
      hasher.update(data: buffer[..<head])
      if expectedLength > Int64(edgeBytes) {
        let offset = max(Int64(edgeBytes), expectedLength - Int64(edgeBytes))
        guard let tail = file.read(into: &buffer, at: offset) else { return nil }
        hasher.update(data: buffer[..<tail])
      }
      return Data(hasher.finalize())
    }
  }

  /// SHA-256 of the whole file, read in 1 MB chunks. `nil` when it couldn't be read,
  /// changed length while being read, or the scan was cancelled.
  static func fullHash(_ path: String, expectedLength: Int64, cancel: CancelFlag) -> Data? {
    withoutAccessTimeUpdates {
      guard let file = OpenFile(path, expectedLength: expectedLength) else { return nil }
      defer { file.close() }
      var hasher = SHA256()
      var buffer = [UInt8](repeating: 0, count: chunkBytes)
      var offset: Int64 = 0
      while true {
        if cancel.isCancelled { return nil }
        guard let count = file.read(into: &buffer, at: offset) else { return nil }
        if count == 0 { break }
        hasher.update(data: buffer[..<count])
        offset += Int64(count)
      }
      guard offset == expectedLength else { return nil }
      return Data(hasher.finalize())
    }
  }

  /// Whether a path is a cloud file whose contents aren't on this Mac.
  static func isDataless(_ path: String) -> Bool {
    var info = stat()
    guard lstat(path, &info) == 0 else { return false }
    return info.st_flags & UInt32(SF_DATALESS) != 0
  }

  /// Runs `work` with this thread's reads leaving access times alone, so hashing a file
  /// doesn't make it look recently opened to later scans.
  static func withoutAccessTimeUpdates<T>(_ work: () -> T) -> T {
    let previous = getiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, IOPOL_SCOPE_THREAD)
    _ = setiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, IOPOL_SCOPE_THREAD, IOPOL_ATIME_UPDATES_OFF)
    defer { _ = setiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, IOPOL_SCOPE_THREAD, previous >= 0 ? previous : IOPOL_ATIME_UPDATES_DEFAULT) }
    return work()
  }

  /// A regular file opened for reading after checking it is what the walk saw.
  private struct OpenFile {
    let descriptor: Int32

    init?(_ path: String, expectedLength: Int64) {
      let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { return nil }
      var info = stat()
      guard fstat(descriptor, &info) == 0,
            (info.st_mode & S_IFMT) == S_IFREG,
            info.st_flags & UInt32(SF_DATALESS) == 0,
            Int64(info.st_size) == expectedLength else {
        Darwin.close(descriptor)
        return nil
      }
      // Large reads shouldn't push everything else out of the memory cache.
      _ = fcntl(descriptor, F_NOCACHE, 1)
      self.descriptor = descriptor
    }

    func read(into buffer: inout [UInt8], at offset: Int64) -> Int? {
      let count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, off_t(offset)) }
      return count < 0 ? nil : count
    }

    func close() { Darwin.close(descriptor) }
  }
}
