import Foundation
import Perception

/// Compatibility belongs at the subscription boundary, not in API response decoding.
enum SubscriptionDocument {
    static func decode(_ data: Data) throws -> [String: JSONValue] {
        if let value = try? JSONDecoder().decode([String: JSONValue].self, from: data) { return value }
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        let first = bytes.first(where: { !whitespace($0) })
        if first != 123 && first != 91 && first != 47 && first != 35 {
            // TVBox image envelopes end in an eight-character marker and **base64.
            // Decode bytes rather than UTF-8: the image prefix can be arbitrary binary.
            if let start = envelopeStart(bytes) {
                let payload = bytes[start...].filter { !whitespace($0) }
                guard let decoded = Data(base64Encoded: Data(payload)) else { throw TVError.invalidConfiguration }
                bytes = [UInt8](decoded)
                if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
            }
        }
        let prefix = String(decoding: bytes.prefix(256), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") {
            throw TVError.unsupported(L10n.text("The subscription server returned a web page instead of a configuration."))
        }
        if prefix.hasPrefix("2423") { bytes = try decrypt(bytes) }
        return try JSONDecoder().decode([String: JSONValue].self, from: Data(escapeControlCharacters(normalize(bytes))))
    }

    private static func whitespace(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }

    /// CatVod encrypted configuration (FongMi `Decoder.cbc`): the hex of `$#key#$`, the AES-CBC ciphertext
    /// and a 13-character IV. Key and IV are lowercased and padded with "0" to 16 bytes.
    private static func decrypt(_ input: [UInt8]) throws -> [UInt8] {
        let unsupported = TVError.unsupported(L10n.text("This subscription uses an encrypted configuration that is not supported yet."))
        guard let data = Data(hex: String(decoding: input.filter { !whitespace($0) }, as: UTF8.self)) else { throw unsupported }
        let bytes = [UInt8](data), ivStart = bytes.count - 13
        guard ivStart > 2, let keyEnd = (2..<ivStart - 1).first(where: { bytes[$0] == 35 && bytes[$0 + 1] == 36 }) else { throw unsupported }
        func padded(_ text: ArraySlice<UInt8>) -> Data? {
            text.count <= 16 ? Data(text.map { (65...90).contains($0) ? $0 + 32 : $0 } + Array(repeating: 48, count: 16 - text.count)) : nil
        }
        guard let key = padded(bytes[2..<keyEnd]), let iv = padded(bytes[ivStart...]),
              let plain = try? ScriptCrypto.aes(encrypt: false, ecb: false, padding: true, key: key, iv: iv, data: Data(bytes[(keyEnd + 2)..<ivStart]))
        else { throw unsupported }
        var result = [UInt8](plain)
        if result.starts(with: [0xEF, 0xBB, 0xBF]) { result.removeFirst(3) }
        return result
    }

    /// Raw line breaks and tabs inside strings are invalid JSON, but Gson-based TVBox apps read them as
    /// the characters themselves, and some configurations contain them. Escaping keeps that meaning.
    private static func escapeControlCharacters(_ input: [UInt8]) -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(input.count)
        var i = 0
        var quoted = false
        while i < input.count {
            let byte = input[i]
            if quoted && byte == 92 && i + 1 < input.count { output += [byte, input[i + 1]]; i += 2; continue }
            if byte == 34 { quoted.toggle() }
            if quoted && byte < 32 { output += Array(String(format: "\\u%04x", byte).utf8) } else { output.append(byte) }
            i += 1
        }
        return output
    }

    private static func envelopeStart(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 10 else { return nil }
        func alphanumeric(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b) }
        for i in 8..<(bytes.count - 1) where bytes[i] == 42 && bytes[i + 1] == 42 {
            if bytes[(i - 8)..<i].allSatisfy(alphanumeric) { return i + 2 }
        }
        return nil
    }

    private static func normalize(_ input: [UInt8]) throws -> [UInt8] {
        var bytes = input
        var i = 0
        var quoted = false
        while i < bytes.count {
            if quoted {
                if bytes[i] == 92 { i += 2; continue }
                if bytes[i] == 34 { quoted = false }
                i += 1; continue
            }
            if bytes[i] == 34 { quoted = true; i += 1; continue }
            let next = i + 1 < bytes.count ? bytes[i + 1] : 0
            if bytes[i] == 35 || (bytes[i] == 47 && next == 47) {
                while i < bytes.count && bytes[i] != 10 && bytes[i] != 13 { bytes[i] = 32; i += 1 }
            } else if bytes[i] == 47 && next == 42 {
                bytes[i] = 32; bytes[i + 1] = 32; i += 2
                var closed = false
                while i < bytes.count {
                    if bytes[i] == 42 && i + 1 < bytes.count && bytes[i + 1] == 47 {
                        bytes[i] = 32; bytes[i + 1] = 32; i += 2; closed = true; break
                    }
                    if bytes[i] != 10 && bytes[i] != 13 { bytes[i] = 32 }
                    i += 1
                }
                guard closed else { throw TVError.invalidConfiguration }
            } else { i += 1 }
        }
        // Remove trailing commas only outside strings, after comments became whitespace.
        i = 0; quoted = false
        while i < bytes.count {
            if quoted {
                if bytes[i] == 92 { i += 2; continue }
                if bytes[i] == 34 { quoted = false }
            } else if bytes[i] == 34 { quoted = true }
            else if bytes[i] == 44 {
                var end = i + 1
                while end < bytes.count && whitespace(bytes[end]) { end += 1 }
                if end < bytes.count && (bytes[end] == 93 || bytes[end] == 125) { bytes[i] = 32 }
            }
            i += 1
        }
        return bytes
    }
}
