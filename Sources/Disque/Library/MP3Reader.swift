import Foundation

/// Reads tags and stream properties from MP3 files without decoding audio.
enum MP3Reader {
    private static let pictureFrames: Set<String> = ["APIC", "PIC"]

    static func read(url: URL) -> RawMetadata? {
        guard let file = BinaryFile(url: url), file.size > 0 else { return nil }
        var meta = RawMetadata()
        var audioStart = 0
        var lengthFromTag: Double?

        if let header = ID3v2.header(in: file) {
            audioStart = header.totalSize
            ID3v2.walk(header, file: file, loadEverything: false) { id, load in
                if pictureFrames.contains(id) {
                    meta.hasArtwork = true
                    return true
                }
                guard interestingFrames.contains(id), let data = load() else { return true }
                apply(frame: id, values: ID3v2.textValues(data), to: &meta, length: &lengthFromTag)
                return true
            }
            // Some files carry several stacked tags; skip any extra ones.
            var guardCount = 0
            while let extra = ID3v2.header(in: file, at: audioStart), guardCount < 4 {
                audioStart += extra.totalSize
                guardCount += 1
            }
        }

        var audioEnd = file.size
        let v1 = file.read(at: file.size - 128, count: 128)
        if v1.count == 128, v1[0] == 0x54, v1[1] == 0x41, v1[2] == 0x47 { // "TAG"
            audioEnd -= 128
            ID3v1.apply(v1, to: &meta)
        }
        // APEv2 tag sitting before ID3v1 / at the end of the file.
        let apeFooter = file.read(at: audioEnd - 32, count: 32)
        if apeFooter.count == 32, Bytes.ascii(apeFooter, 0, 8) == "APETAGEX" {
            let tagSize = Bytes.le32(apeFooter, 12)
            let flags = Bytes.le32(apeFooter, 20)
            let hasHeader = flags & (1 << 31) != 0
            let total = tagSize + (hasHeader ? 32 : 0)
            if total > 0, total < audioEnd - audioStart { audioEnd -= total }
        }

        MPEGAudio.analyze(file: file, audioStart: audioStart, audioEnd: audioEnd, into: &meta)
        if meta.duration == nil, let lengthFromTag { meta.duration = lengthFromTag }
        return meta
    }

    /// Returns the front cover (or first picture) embedded in the ID3v2 tag.
    static func artwork(url: URL) -> Data? {
        guard let file = BinaryFile(url: url), let header = ID3v2.header(in: file) else { return nil }
        var best: [UInt8]?
        ID3v2.walk(header, file: file, loadEverything: true) { id, load in
            guard pictureFrames.contains(id) else { return true }
            guard let data = load(), let picture = ID3v2.picture(from: data, major: header.major) else { return true }
            if picture.type == 3 {
                best = picture.bytes
                return false
            }
            if best == nil { best = picture.bytes }
            return true
        }
        return best.map { Data($0) }
    }

    private static let interestingFrames: Set<String> = [
        "TIT2", "TT2", "TPE1", "TP1", "TPE2", "TP2", "TALB", "TAL", "TRCK", "TRK", "TPOS", "TPA",
        "TYER", "TYE", "TDRC", "TDRL", "TDOR", "TORY", "TOR", "TCON", "TCO", "TCOM", "TCM", "TCMP", "TCP", "TLEN", "TLE",
    ]

    private static func apply(frame id: String, values: [String], to meta: inout RawMetadata, length: inout Double?) {
        guard let first = values.first else { return }
        switch id {
        case "TIT2", "TT2":
            meta.title = first
        case "TPE1", "TP1":
            meta.artist = values.joined(separator: ", ")
        case "TPE2", "TP2":
            meta.albumArtist = first
        case "TALB", "TAL":
            meta.album = first
        case "TRCK", "TRK":
            let (number, total) = MetadataParsing.numberPair(first)
            meta.trackNumber = number
            meta.trackTotal = total
        case "TPOS", "TPA":
            let (number, total) = MetadataParsing.numberPair(first)
            meta.discNumber = number
            meta.discTotal = total
        case "TYER", "TYE", "TDRC":
            meta.year = MetadataParsing.year(first) ?? meta.year
        case "TDRL", "TDOR", "TORY", "TOR":
            if meta.year == nil { meta.year = MetadataParsing.year(first) }
        case "TCON", "TCO":
            meta.genre = values.lazy.compactMap(MetadataParsing.genre).first
        case "TCOM", "TCM":
            meta.composer = values.joined(separator: ", ")
        case "TCMP", "TCP":
            meta.isCompilation = first == "1"
        case "TLEN", "TLE":
            if let ms = Double(first), ms > 0 { length = ms / 1000 }
        default:
            break
        }
    }
}

/// MPEG audio frame header parsing, used to compute duration and bitrate.
enum MPEGAudio {
    struct FrameHeader {
        let version: Int // 1, 2 or 25 (MPEG 2.5)
        let layer: Int
        let bitrate: Int // kbps
        let sampleRate: Int
        let padding: Int
        let channelMode: Int

        init?(_ b: [UInt8], _ i: Int) {
            guard i >= 0, i + 4 <= b.count, b[i] == 0xFF, b[i + 1] & 0xE0 == 0xE0 else { return nil }
            let versionBits = (b[i + 1] >> 3) & 0x03
            let layerBits = (b[i + 1] >> 1) & 0x03
            guard versionBits != 1, layerBits != 0 else { return nil }
            version = versionBits == 3 ? 1 : (versionBits == 2 ? 2 : 25)
            layer = 4 - Int(layerBits)
            let bitrateIndex = Int(b[i + 2] >> 4)
            let rateIndex = Int((b[i + 2] >> 2) & 0x03)
            guard bitrateIndex != 0, bitrateIndex != 15, rateIndex != 3 else { return nil }
            let table = version == 1 ? layer - 1 : (layer == 1 ? 3 : 4)
            bitrate = MPEGAudio.bitrates[table][bitrateIndex]
            sampleRate = MPEGAudio.sampleRates[version]![rateIndex]
            padding = Int((b[i + 2] >> 1) & 0x01)
            channelMode = Int(b[i + 3] >> 6)
        }

        var samplesPerFrame: Int {
            if layer == 1 { return 384 }
            if layer == 3 && version != 1 { return 576 }
            return 1152
        }

        var frameLength: Int {
            if layer == 1 { return (12 * bitrate * 1000 / sampleRate + padding) * 4 }
            let coefficient = (layer == 3 && version != 1) ? 72 : 144
            return coefficient * bitrate * 1000 / sampleRate + padding
        }

        var sideInfoSize: Int {
            if version == 1 { return channelMode == 3 ? 17 : 32 }
            return channelMode == 3 ? 9 : 17
        }
    }

    static let bitrates: [[Int]] = [
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0], // MPEG1 Layer I
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0], // MPEG1 Layer II
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0], // MPEG1 Layer III
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0], // MPEG2 Layer I
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0], // MPEG2 Layer II & III
    ]

    static let sampleRates: [Int: [Int]] = [
        1: [44100, 48000, 32000],
        2: [22050, 24000, 16000],
        25: [11025, 12000, 8000],
    ]

    static func analyze(file: BinaryFile, audioStart: Int, audioEnd: Int, into meta: inout RawMetadata) {
        let window = min(256 * 1024, max(0, audioEnd - audioStart))
        let buffer = file.read(at: audioStart, count: window)
        var i = 0
        while i + 4 <= buffer.count {
            guard buffer[i] == 0xFF, buffer[i + 1] & 0xE0 == 0xE0, let header = FrameHeader(buffer, i) else {
                i += 1
                continue
            }
            // Require the following frame to look consistent to avoid false sync words.
            let next = i + header.frameLength
            if next + 4 <= buffer.count {
                guard let following = FrameHeader(buffer, next),
                      following.version == header.version,
                      following.layer == header.layer,
                      following.sampleRate == header.sampleRate else {
                    i += 1
                    continue
                }
            }

            meta.sampleRate = header.sampleRate
            meta.channels = header.channelMode == 3 ? 1 : 2
            let frameStart = audioStart + i
            let audioBytes = max(0, audioEnd - frameStart)

            // Xing / Info header (LAME and friends).
            let xingOffset = i + 4 + (header.layer == 3 ? header.sideInfoSize : 0)
            if let tag = Bytes.ascii(buffer, xingOffset, 4), tag == "Xing" || tag == "Info" {
                let flags = Bytes.be32(buffer, xingOffset + 4)
                var cursor = xingOffset + 8
                var frames: Int?
                var bytes: Int?
                if flags & 0x1 != 0 {
                    frames = Bytes.be32(buffer, cursor)
                    cursor += 4
                }
                if flags & 0x2 != 0 { bytes = Bytes.be32(buffer, cursor) }
                if let frames, frames > 0 {
                    let duration = Double(frames) * Double(header.samplesPerFrame) / Double(header.sampleRate)
                    meta.duration = duration
                    meta.isVBR = tag == "Xing"
                    if meta.isVBR {
                        let total = Double((bytes ?? 0) > 0 ? bytes! : audioBytes)
                        meta.bitrate = Int((total * 8 / duration / 1000).rounded())
                    } else {
                        meta.bitrate = header.bitrate
                    }
                    return
                }
            }

            // Fraunhofer VBRI header.
            let vbriOffset = i + 4 + 32
            if Bytes.ascii(buffer, vbriOffset, 4) == "VBRI" {
                let bytes = Bytes.be32(buffer, vbriOffset + 10)
                let frames = Bytes.be32(buffer, vbriOffset + 14)
                if frames > 0 {
                    let duration = Double(frames) * Double(header.samplesPerFrame) / Double(header.sampleRate)
                    meta.duration = duration
                    meta.isVBR = true
                    meta.bitrate = Int((Double(bytes > 0 ? bytes : audioBytes) * 8 / duration / 1000).rounded())
                    return
                }
            }

            // Constant bitrate: derive duration from the stream size.
            meta.bitrate = header.bitrate
            meta.duration = Double(audioBytes) * 8 / Double(header.bitrate * 1000)
            return
        }
    }
}
