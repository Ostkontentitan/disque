import Foundation

/// Metadata extracted from an audio file before normalisation.
struct RawMetadata: Sendable {
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var discTotal: Int?
    var year: Int?
    var genre: String?
    var composer: String?
    var isCompilation = false
    var duration: Double?
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var isVBR = false
    var hasArtwork = false
}

/// Minimal, dependency free ID3v2.2 / v2.3 / v2.4 reader.
enum ID3v2 {
    struct Header {
        let major: UInt8
        let flags: UInt8
        let size: Int

        var hasFooter: Bool { major == 4 && flags & 0x10 != 0 }
        var totalSize: Int { 10 + size + (hasFooter ? 10 : 0) }
        var isUnsynchronised: Bool { flags & 0x80 != 0 }
        var hasExtendedHeader: Bool { flags & 0x40 != 0 }
    }

    static func header(in file: BinaryFile, at offset: Int = 0) -> Header? {
        let b = file.read(at: offset, count: 10)
        guard b.count == 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 else { return nil } // "ID3"
        guard (2...4).contains(b[3]), b[4] != 0xFF else { return nil }
        guard b[6] & 0x80 == 0, b[7] & 0x80 == 0, b[8] & 0x80 == 0, b[9] & 0x80 == 0 else { return nil }
        return Header(major: b[3], flags: b[5], size: Bytes.syncsafe32(b, 6))
    }

    /// Walks all frames in the tag. The visitor receives the frame id and a closure that
    /// loads the (flag-processed) frame body on demand. Return `false` to stop walking.
    static func walk(
        _ header: Header,
        file: BinaryFile,
        loadEverything: Bool,
        visitor: (_ id: String, _ load: () -> [UInt8]?) -> Bool
    ) {
        let unsyncWholeTag = header.major < 4 && header.isUnsynchronised
        let source: ByteSource
        if unsyncWholeTag || loadEverything || header.size <= 256 * 1024 {
            var body = file.read(at: 10, count: header.size)
            if unsyncWholeTag { body = removeUnsynchronisation(body) }
            source = MemoryBytes(data: body)
        } else {
            source = FileBytes(file: file, base: 10, length: header.size)
        }

        var position = 0
        if header.hasExtendedHeader && header.major >= 3 {
            let ext = source.bytes(at: 0, count: 4)
            guard ext.count == 4 else { return }
            position = header.major == 4 ? Bytes.syncsafe32(ext, 0) : Bytes.be32(ext, 0) + 4
        }

        let headerLength = header.major == 2 ? 6 : 10
        while position + headerLength <= source.length {
            let fh = source.bytes(at: position, count: headerLength)
            guard fh.count == headerLength, isFrameIDByte(fh[0]) else { break }

            let id: String
            var size: Int
            var flags: UInt16 = 0
            if header.major == 2 {
                id = String(decoding: fh[0..<3], as: UTF8.self)
                size = Bytes.be24(fh, 3)
            } else {
                id = String(decoding: fh[0..<4], as: UTF8.self)
                if header.major == 4 {
                    size = Bytes.syncsafe32(fh, 4)
                    // Some writers (notably old iTunes) stored plain 32-bit sizes in v2.4 tags.
                    let plain = Bytes.be32(fh, 4)
                    if fh[4] & 0x80 != 0 || fh[5] & 0x80 != 0 || fh[6] & 0x80 != 0 || fh[7] & 0x80 != 0 {
                        size = plain
                    } else if plain != size,
                              !isPlausibleFrameStart(source, at: position + headerLength + size, headerLength: headerLength),
                              isPlausibleFrameStart(source, at: position + headerLength + plain, headerLength: headerLength) {
                        size = plain
                    }
                } else {
                    size = Bytes.be32(fh, 4)
                }
                flags = (UInt16(fh[8]) << 8) | UInt16(fh[9])
            }

            guard id.utf8.allSatisfy(isFrameIDByte), size > 0, position + headerLength + size <= source.length else { break }
            let dataStart = position + headerLength
            position = dataStart + size

            let major = header.major
            let tagUnsync = header.isUnsynchronised
            let shouldContinue = visitor(id) {
                var data = source.bytes(at: dataStart, count: size)
                if major == 4 {
                    if flags & 0x000C != 0 { return nil } // compressed or encrypted
                    if flags & 0x0040 != 0 { data = Array(data.dropFirst(1)) } // group id
                    if flags & 0x0001 != 0 { data = Array(data.dropFirst(4)) } // data length indicator
                    if flags & 0x0002 != 0 || tagUnsync { data = removeUnsynchronisation(data) }
                } else if major == 3 {
                    if flags & 0x00C0 != 0 { return nil } // compressed or encrypted
                    if flags & 0x0020 != 0 { data = Array(data.dropFirst(1)) } // group id
                }
                return data
            }
            if !shouldContinue { return }
        }
    }

    private static func isFrameIDByte(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39)
    }

    private static func isPlausibleFrameStart(_ source: ByteSource, at offset: Int, headerLength: Int) -> Bool {
        if offset == source.length { return true }
        let b = source.bytes(at: offset, count: 4)
        guard b.count == 4 else { return false }
        if b[0] == 0 { return true } // padding
        return b.allSatisfy(isFrameIDByte)
    }

    static func removeUnsynchronisation(_ data: [UInt8]) -> [UInt8] {
        guard data.count > 1 else { return data }
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        var i = 0
        while i < data.count {
            out.append(data[i])
            if data[i] == 0xFF, i + 1 < data.count, data[i + 1] == 0x00 { i += 2 } else { i += 1 }
        }
        return out
    }

    // MARK: Text

    /// Decodes a text information frame into its (possibly multiple) values.
    static func textValues(_ data: [UInt8]) -> [String] {
        guard let encoding = data.first else { return [] }
        let decoded = decode(Array(data.dropFirst()), encoding: encoding)
        return decoded
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmed }
            .filter { !$0.isEmpty }
    }

    static func decode(_ bytes: [UInt8], encoding: UInt8) -> String {
        switch encoding {
        case 1:
            var b = bytes
            if b.count % 2 == 1 { b.removeLast() }
            if b.count >= 2 {
                if b[0] == 0xFF && b[1] == 0xFE { return String(bytes: b.dropFirst(2), encoding: .utf16LittleEndian) ?? "" }
                if b[0] == 0xFE && b[1] == 0xFF { return String(bytes: b.dropFirst(2), encoding: .utf16BigEndian) ?? "" }
            }
            return String(bytes: b, encoding: .utf16LittleEndian) ?? ""
        case 2:
            var b = bytes
            if b.count % 2 == 1 { b.removeLast() }
            return String(bytes: b, encoding: .utf16BigEndian) ?? ""
        case 3:
            return String(bytes: bytes, encoding: .utf8) ?? Bytes.latin1(bytes)
        default:
            return Bytes.latin1(bytes)
        }
    }

    // MARK: Pictures

    /// Parses an APIC (v2.3/2.4) or PIC (v2.2) frame body.
    static func picture(from data: [UInt8], major: UInt8) -> (type: UInt8, bytes: [UInt8])? {
        guard data.count > 4 else { return nil }
        let encoding = data[0]
        var i = 1
        if major == 2 {
            i += 3
        } else {
            while i < data.count && data[i] != 0 { i += 1 }
            i += 1
        }
        guard i < data.count else { return nil }
        let type = data[i]
        i += 1
        if encoding == 1 || encoding == 2 {
            while i + 1 < data.count && !(data[i] == 0 && data[i + 1] == 0) { i += 2 }
            i += 2
        } else {
            while i < data.count && data[i] != 0 { i += 1 }
            i += 1
        }
        guard i < data.count else { return nil }
        var payload = Array(data[i...])
        // Be lenient with writers that got the description terminator wrong.
        if !looksLikeImage(payload), let start = imageStart(in: Array(data[min(data.count, 1)...].prefix(256))) {
            payload = Array(data[(1 + start)...])
        }
        return (type, payload)
    }

    private static func looksLikeImage(_ b: [UInt8]) -> Bool {
        guard b.count > 4 else { return false }
        return (b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47)
    }

    private static func imageStart(in b: [UInt8]) -> Int? {
        guard b.count > 4 else { return nil }
        for i in 0..<(b.count - 3) {
            if b[i] == 0xFF && b[i + 1] == 0xD8 && b[i + 2] == 0xFF { return i }
            if b[i] == 0x89 && b[i + 1] == 0x50 && b[i + 2] == 0x4E && b[i + 3] == 0x47 { return i }
        }
        return nil
    }
}

enum ID3v1 {
    static func apply(_ b: [UInt8], to meta: inout RawMetadata) {
        guard b.count == 128 else { return }
        func field(_ range: Range<Int>) -> String? {
            let bytes = b[range].prefix { $0 != 0 }
            return Bytes.latin1(bytes).nilIfEmpty
        }
        if meta.title == nil { meta.title = field(3..<33) }
        if meta.artist == nil { meta.artist = field(33..<63) }
        if meta.album == nil { meta.album = field(63..<93) }
        if meta.year == nil, let y = field(93..<97) { meta.year = MetadataParsing.year(y) }
        if meta.trackNumber == nil, b[125] == 0, b[126] != 0 { meta.trackNumber = Int(b[126]) }
        if meta.genre == nil, Int(b[127]) < MetadataParsing.genres.count { meta.genre = MetadataParsing.genres[Int(b[127])] }
    }
}

enum MetadataParsing {
    static func numberPair(_ text: String) -> (Int?, Int?) {
        let parts = text.split(separator: "/", maxSplits: 1).map { String($0).trimmed }
        let first = parts.first.flatMap { Int($0) }
        let second = parts.count > 1 ? Int(parts[1]) : nil
        return (first, second)
    }

    static func year(_ text: String) -> Int? {
        let digits = text.trimmed.prefix(4)
        guard digits.count == 4, let value = Int(digits), (1000...2999).contains(value) else { return nil }
        return value
    }

    static func genre(_ raw: String) -> String? {
        let text = raw.trimmed
        if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
            let code = text[text.index(after: text.startIndex)..<close]
            let rest = String(text[text.index(after: close)...]).trimmed
            if !rest.isEmpty, !rest.hasPrefix("(") { return rest }
            if code == "RX" { return "Remix" }
            if code == "CR" { return "Cover" }
            if let number = Int(code), number >= 0, number < genres.count { return genres[number] }
        }
        if let number = Int(text), number >= 0, number < genres.count { return genres[number] }
        return text.nilIfEmpty
    }

    static let genres: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
        "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
        "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes",
        "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
        "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebop", "Latin", "Revival", "Celtic", "Bluegrass",
        "Avantgarde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic",
        "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus", "Groove",
        "Satire", "Slow Jam", "Club", "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
        "Duet", "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dance Hall", "Goa", "Drum & Bass", "Club-House", "Hardcore",
        "Terror", "Indie", "Britpop", "Afro-Punk", "Polsk Punk", "Beat", "Christian Gangsta Rap", "Heavy Metal", "Black Metal", "Crossover",
        "Contemporary Christian", "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "J-Pop", "Synthpop",
    ]
}
