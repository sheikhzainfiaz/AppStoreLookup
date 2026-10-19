import Foundation

// MARK: - Gzip

/// Foundation has no gzip reader, but a gzip file is just a header, a raw DEFLATE stream and an
/// 8-byte trailer — and Apple's `.zlib` algorithm is raw DEFLATE. Strip the wrapper, inflate.
enum Gzip {

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)

        // Already plain text (or URLSession inflated it for us via Content-Encoding).
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b else { return data }
        guard bytes[2] == 8 else { throw ASCError.unreadableReport } // 8 = DEFLATE

        let flags = bytes[3]
        var index = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { throw ASCError.unreadableReport }
            let length = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + length
        }
        if flags & 0x08 != 0 { // FNAME, zero-terminated
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT, zero-terminated
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            index += 2
        }

        let end = bytes.count - 8
        guard index < end else { throw ASCError.unreadableReport }

        let deflated = Data(bytes[index..<end]) as NSData
        return try deflated.decompressed(using: .zlib) as Data
    }
}

