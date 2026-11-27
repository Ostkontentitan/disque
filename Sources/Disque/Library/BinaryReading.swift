import Foundation

/// Small random-access reader over a file, used by the tag parsers.
final class BinaryFile {
    private let handle: FileHandle
    let size: Int

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.handle = handle
        self.size = Int((try? handle.seekToEnd()) ?? 0)
    }

    deinit {
        try? handle.close()
    }

    func read(at offset: Int, count: Int) -> [UInt8] {
        guard offset >= 0, offset < size, count > 0 else { return [] }
        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: count) else { return [] }
            return [UInt8](data)
        } catch {
            return []
        }
    }
}

protocol ByteSource {
    var length: Int { get }
    func bytes(at offset: Int, count: Int) -> [UInt8]
}

struct MemoryBytes: ByteSource {
    let data: [UInt8]
    var length: Int { data.count }

    func bytes(at offset: Int, count: Int) -> [UInt8] {
        guard offset >= 0, offset < data.count, count > 0 else { return [] }
        return Array(data[offset..<min(offset + count, data.count)])
    }
}

/// A window into a file, starting at `base`, `length` bytes long.
struct FileBytes: ByteSource {
    let file: BinaryFile
    let base: Int
    let length: Int

    func bytes(at offset: Int, count: Int) -> [UInt8] {
        let available = min(count, length - offset)
        guard offset >= 0, available > 0 else { return [] }
        return file.read(at: base + offset, count: available)
    }
}

enum Bytes {
    static func be32(_ b: [UInt8], _ i: Int) -> Int {
        guard i >= 0, i + 4 <= b.count else { return 0 }
        return (Int(b[i]) << 24) | (Int(b[i + 1]) << 16) | (Int(b[i + 2]) << 8) | Int(b[i + 3])
    }

    static func be24(_ b: [UInt8], _ i: Int) -> Int {
        guard i >= 0, i + 3 <= b.count else { return 0 }
        return (Int(b[i]) << 16) | (Int(b[i + 1]) << 8) | Int(b[i + 2])
    }

    static func le32(_ b: [UInt8], _ i: Int) -> Int {
        guard i >= 0, i + 4 <= b.count else { return 0 }
        return Int(b[i]) | (Int(b[i + 1]) << 8) | (Int(b[i + 2]) << 16) | (Int(b[i + 3]) << 24)
    }

    static func syncsafe32(_ b: [UInt8], _ i: Int) -> Int {
        guard i >= 0, i + 4 <= b.count else { return 0 }
        return (Int(b[i] & 0x7F) << 21) | (Int(b[i + 1] & 0x7F) << 14) | (Int(b[i + 2] & 0x7F) << 7) | Int(b[i + 3] & 0x7F)
    }

    static func ascii(_ b: [UInt8], _ i: Int, _ count: Int) -> String? {
        guard i >= 0, i + count <= b.count else { return nil }
        return String(decoding: b[i..<(i + count)], as: UTF8.self)
    }

    static func latin1(_ b: some Collection<UInt8>) -> String {
        String(bytes: b, encoding: .windowsCP1252) ?? String(bytes: b, encoding: .isoLatin1) ?? ""
    }
}
