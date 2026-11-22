import Foundation

/// The pinned checkpoint uses the slow T5/SentencePiece tokenizer. This reader
/// preserves its compiled normalization table and Float32 unigram scores; the
/// generic Swift tokenizer's approximate normalizer is not used for Neodragon.
/// Algorithm references: Google SentencePiece 0.2.1 normalizer.cc/unigram_model.cc
/// (Apache-2.0). The exact source vocabulary is exported by export_sentencepiece.py.
struct NeodragonT5Tokenizer {
    private struct Metadata: Decodable {
        struct Piece: Decodable { let text: String; let score: Float32; let type: Int }
        struct Added: Decodable {
            let id: Int; let content: String; let lstrip: Bool; let rstrip: Bool
            let normalized: Bool; let single_word: Bool; let special: Bool
        }
        struct Normalizer: Decodable {
            let precompiledCharsmap: String
            let addDummyPrefix: Bool; let removeExtraWhitespaces: Bool; let escapeWhitespaces: Bool
        }
        let schemaVersion: Int; let sourceSHA256: String
        let normalizer: Normalizer; let vocabulary: [Piece]; let addedTokens: [Added]
        let unknownID: Int; let eosID: Int; let paddingID: Int
    }
    private struct Node {
        var children: [UInt8: Int] = [:]
        var token: Int?
        var score: Float32 = 0
    }
    private let nodes: [Node]
    private let normalizationTrie: [UInt32]
    private let replacements: [UInt8]
    private let added: [String: Int]
    private let specialPattern: NSRegularExpression
    private let unknownScore: Float32

    init(directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("sentencepiece-native.json"))
        guard data.count < 6_000_000 else { throw GenerationError.invalidTensor }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        guard metadata.schemaVersion == 1, metadata.sourceSHA256 == "d60acb128cf7b7f2536e8f38a5b18a05535c9e14c7a355904270e15b0945ea86",
              metadata.unknownID == 2, metadata.eosID == 1, metadata.paddingID == 0,
              (30_000...40_000).contains(metadata.vocabulary.count), metadata.addedTokens.count == 103,
              metadata.normalizer.addDummyPrefix, metadata.normalizer.removeExtraWhitespaces,
              metadata.normalizer.escapeWhitespaces,
              let compiled = Data(base64Encoded: metadata.normalizer.precompiledCharsmap),
              (1_024...1_000_000).contains(compiled.count) else { throw GenerationError.invalidTensor }
        let bytes = Array(compiled)
        func word(_ index: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[index + $1]) << (8 * $1)) }
        }
        let size = Int(word(0))
        guard size >= 1_024, size % 1_024 == 0, size + 4 < bytes.count, bytes.last == 0 else {
            throw GenerationError.invalidTensor
        }
        normalizationTrie = stride(from: 4, to: size + 4, by: 4).map { word($0) }
        replacements = Array(bytes[(size + 4)...])
        var trie = [Node()]
        var minimum = Float32.greatestFiniteMagnitude
        for (id, piece) in metadata.vocabulary.enumerated() {
            guard piece.score.isFinite, [1, 2, 3].contains(piece.type) else { throw GenerationError.invalidTensor }
            guard piece.type == 1 else { continue }
            minimum = min(minimum, piece.score)
            var node = 0
            for byte in piece.text.utf8 {
                if let child = trie[node].children[byte] { node = child }
                else {
                    let next = trie.count
                    trie[node].children[byte] = next
                    trie.append(Node())
                    node = next
                }
            }
            guard trie[node].token == nil else { throw GenerationError.invalidTensor }
            trie[node].token = id; trie[node].score = piece.score
        }
        nodes = trie
        unknownScore = minimum - 10
        var special: [String: Int] = [:], patterns: [String] = []
        for token in metadata.addedTokens {
            guard token.special, !token.normalized, !token.single_word, !token.content.isEmpty,
                  (0..<32_100).contains(token.id), special[token.content] == nil else { throw GenerationError.invalidTensor }
            special[token.content] = token.id
            patterns.append((token.lstrip ? "\\s*" : "") + NSRegularExpression.escapedPattern(for: token.content)
                            + (token.rstrip ? "\\s*" : ""))
        }
        added = special
        specialPattern = try NSRegularExpression(pattern: patterns.joined(separator: "|"))
    }

    func encode(_ text: String) throws -> (ids: [Int32], count: Int) {
        guard text.utf8.count <= 32_000 else { throw GenerationError.invalidPrompt }
        var ids: [Int] = [], cursor = text.startIndex
        for match in specialPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), range.lowerBound >= cursor else { throw GenerationError.invalidTensor }
            ids += try ordinary(String(text[cursor..<range.lowerBound]))
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = added[token] else { throw GenerationError.invalidTensor }
            ids.append(id); cursor = range.upperBound
        }
        ids += try ordinary(String(text[cursor...]))
        if ids.last != 1 { ids.append(1) }
        guard ids.count <= 128 else {
            throw GenerationError.incompatibleModel("The prompt and style exceed Neodragon’s 128-token T5 limit. Nothing was truncated.")
        }
        return ((ids + Array(repeating: 0, count: 128 - ids.count)).map(Int32.init), ids.count)
    }

    private func ordinary(_ text: String) throws -> [Int] {
        let bytes = try normalize(Array(text.utf8))
        guard !bytes.isEmpty else { return [] }
        var score = [Float32](repeating: -.infinity, count: bytes.count + 1)
        var starts = [Int](repeating: -1, count: bytes.count + 1)
        var token = [Int](repeating: -1, count: bytes.count + 1)
        score[0] = 0
        var start = 0
        while start < bytes.count {
            let scalarLength = Self.scalarLength(bytes[start])
            guard start + scalarLength <= bytes.count else { throw GenerationError.invalidTensor }
            var node = 0, end = start, single = false
            while end < bytes.count, let child = nodes[node].children[bytes[end]] {
                node = child; end += 1
                if let id = nodes[node].token {
                    let candidate = score[start] + nodes[node].score
                    if starts[end] == -1 || candidate > score[end] {
                        score[end] = candidate; starts[end] = start; token[end] = id
                    }
                    if end - start == scalarLength { single = true }
                }
            }
            if !single {
                let end = start + scalarLength, candidate = score[start] + unknownScore
                if starts[end] == -1 || candidate > score[end] {
                    score[end] = candidate; starts[end] = start; token[end] = 2
                }
            }
            start += scalarLength
        }
        var result: [Int] = [], end = bytes.count
        while end > 0 {
            guard starts[end] >= 0, starts[end] < end, token[end] >= 0 else { throw GenerationError.invalidTensor }
            result.append(token[end]); end = starts[end]
        }
        // SentencePiece emits one unknown piece for a consecutive unknown span.
        return result.reversed().reduce(into: []) { output, id in
            if id != 2 || output.last != 2 { output.append(id) }
        }
    }

    private func normalize(_ input: [UInt8]) throws -> [UInt8] {
        var mapped: [UInt8] = [], cursor = 0
        while cursor < input.count {
            var node = Self.offset(normalizationTrie[0]), position = cursor
            var matchLength = 0, replacementOffset: Int?
            while position < input.count {
                node ^= Int(input[position])
                guard normalizationTrie.indices.contains(node) else { throw GenerationError.invalidTensor }
                let unit = normalizationTrie[node]
                guard unit & 0x800000FF == UInt32(input[position]) else { break }
                node ^= Self.offset(unit); position += 1
                if unit & 0x100 != 0 {
                    guard normalizationTrie.indices.contains(node) else { throw GenerationError.invalidTensor }
                    replacementOffset = Int(normalizationTrie[node] & 0x7FFFFFFF)
                    matchLength = position - cursor
                }
            }
            if var offset = replacementOffset {
                guard replacements.indices.contains(offset) else { throw GenerationError.invalidTensor }
                while offset < replacements.count, replacements[offset] != 0 {
                    mapped.append(replacements[offset]); offset += 1
                }
                guard offset < replacements.count else { throw GenerationError.invalidTensor }
                cursor += matchLength
            } else {
                let length = Self.scalarLength(input[cursor])
                guard cursor + length <= input.count else { throw GenerationError.invalidTensor }
                mapped.append(contentsOf: input[cursor..<(cursor + length)])
                cursor += length
            }
        }
        var collapsed: [UInt8] = []
        for byte in mapped where byte != 32 || (!collapsed.isEmpty && collapsed.last != 32) { collapsed.append(byte) }
        if collapsed.last == 32 { collapsed.removeLast() }
        guard !collapsed.isEmpty else { return [] }
        let space: [UInt8] = [0xE2, 0x96, 0x81]
        var result = space
        for byte in collapsed {
            if byte == 32 { result += space } else { result.append(byte) }
        }
        return result
    }

    private static func offset(_ unit: UInt32) -> Int { Int((unit >> 10) << ((unit & 0x200) >> 6)) }
    private static func scalarLength(_ first: UInt8) -> Int {
        if first < 0x80 { return 1 }
        if first < 0xE0 { return 2 }
        if first < 0xF0 { return 3 }
        return 4
    }
}
