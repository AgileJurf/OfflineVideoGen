import Foundation

/// CLIP byte-level BPE for the pinned Neodragon assets. This mirrors the
/// transformers 4.46 BasicTokenizer path (without optional ftfy). MOVD's T5
/// tokenizer is separate. The caller must provide verified local model assets.
final class NeodragonCLIPTokenizer {
    enum Failure: LocalizedError {
        case invalidAssets, tooManyTokens(Int)
        var errorDescription: String? {
            switch self {
            case .invalidAssets: return "The Neodragon CLIP tokenizer files are incompatible."
            case .tooManyTokens(let count): return "This prompt uses \(count) CLIP tokens. The limit is 77 including start and end tokens; shorten the prompt or style. Nothing was truncated."
            }
        }
    }

    private struct Pair: Hashable { let first: String; let second: String }
    private let vocabulary: [String: Int]
    private let ranks: [Pair: Int]
    private let special: [String: Int]
    private let specialPattern: NSRegularExpression
    private let pattern = try! NSRegularExpression(pattern: #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#, options: [.caseInsensitive])
    private let bytes: [String]
    private let start: Int
    private let end: Int
    private let pad: Int
    private var cache: [String: [Int]] = [:]

    init(directory: URL) throws {
        let vocabulary = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: directory.appendingPathComponent("vocab.json")))
        self.vocabulary = vocabulary
        guard let config = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("tokenizer_config.json"))) as? [String: Any],
              config["model_max_length"] as? Int == 77,
              config["tokenizer_class"] as? String == "CLIPTokenizer" else { throw Failure.invalidAssets }
        func token(_ key: String) throws -> (String, Int) {
            guard let name = (config[key] as? String) ?? (config[key] as? [String: Any])?["content"] as? String,
                  let id = vocabulary[name] else { throw Failure.invalidAssets }
            return (name, id)
        }
        let bos = try token("bos_token"), eos = try token("eos_token"), padding = try token("pad_token")
        start = bos.1; end = eos.1; pad = padding.1
        var specials = [bos.0: bos.1, eos.0: eos.1]
        specials[padding.0] = padding.1
        if let added = config["added_tokens_decoder"] as? [String: [String: Any]] {
            for (key, value) in added where value["special"] as? Bool == true {
                guard let id = Int(key), let name = value["content"] as? String, vocabulary[name] == id else {
                    throw Failure.invalidAssets
                }
                specials[name] = id
            }
        }
        special = specials
        specialPattern = try NSRegularExpression(pattern: specials.keys.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|"))
        let lines = try String(contentsOf: directory.appendingPathComponent("merges.txt"), encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        guard lines.first?.hasPrefix("#version:") == true else { throw Failure.invalidAssets }
        var mergeRanks: [Pair: Int] = [:]
        for (rank, line) in lines.dropFirst().prefix(48_894).enumerated() {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { throw Failure.invalidAssets }
            mergeRanks[Pair(first: String(parts[0]), second: String(parts[1]))] = rank
        }
        ranks = mergeRanks
        var encoded = [String](repeating: "", count: 256)
        let visible = Set(Array(33...126) + Array(161...172) + Array(174...255))
        var extra = 256
        for byte in 0..<256 {
            let scalar = visible.contains(byte) ? byte : extra
            encoded[byte] = String(UnicodeScalar(scalar)!)
            if !visible.contains(byte) { extra += 1 }
        }
        bytes = encoded
    }

    func encode(_ text: String) throws -> [Int32] {
        let source = text as NSString
        var ids = [start]
        var location = 0
        for match in specialPattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            ids += tokenize(source.substring(with: NSRange(location: location, length: match.range.location - location)))
            ids.append(special[source.substring(with: match.range)]!)
            location = NSMaxRange(match.range)
        }
        ids += tokenize(source.substring(from: location))
        ids.append(end)
        guard ids.count <= 77 else { throw Failure.tooManyTokens(ids.count) }
        ids += Array(repeating: pad, count: 77 - ids.count)
        return ids.map(Int32.init)
    }

    private func tokenize(_ text: String) -> [Int] {
        let normalized = Self.clean(text)
        let source = normalized as NSString
        return pattern.matches(in: normalized, range: NSRange(location: 0, length: source.length)).flatMap {
            bpe(source.substring(with: $0.range))
        }
    }

    private func bpe(_ token: String) -> [Int] {
        if let result = cache[token] { return result }
        var word = token.utf8.map { bytes[Int($0)] }
        guard !word.isEmpty else { return [] }
        word[word.count - 1] += "</w>"
        while word.count > 1 {
            var selected: Pair?, lowest = Int.max
            for index in 0..<(word.count - 1) {
                let pair = Pair(first: word[index], second: word[index + 1])
                if let rank = ranks[pair], rank < lowest { selected = pair; lowest = rank }
            }
            guard let selected else { break }
            var merged: [String] = [], index = 0
            while index < word.count {
                if index + 1 < word.count, word[index] == selected.first, word[index + 1] == selected.second {
                    merged.append(word[index] + word[index + 1]); index += 2
                } else { merged.append(word[index]); index += 1 }
            }
            word = merged
        }
        let result = word.map { vocabulary[$0] ?? end }
        if cache.count < 2048 { cache[token] = result }
        return result
    }

    private static func clean(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 0 || value == 0xFFFD { continue }
            if scalar.properties.isWhitespace { result.append(" "); continue }
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: continue
            default: break
            }
            let chinese = (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
                || (0x20000...0x2A6DF).contains(value) || (0x2A700...0x2B73F).contains(value)
                || (0x2B740...0x2B81F).contains(value) || (0x2B820...0x2CEAF).contains(value)
                || (0xF900...0xFAFF).contains(value) || (0x2F800...0x2FA1F).contains(value)
            if chinese { result.append(" ") }
            result.unicodeScalars.append(scalar)
            if chinese { result.append(" ") }
        }
        return result.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
