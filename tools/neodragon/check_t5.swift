import Foundation

// Standalone harness supplies only the production tokenizer's error vocabulary.
enum GenerationError: Error { case invalidTensor, invalidPrompt, incompatibleModel(String) }

@main
struct CheckT5 {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: check-t5 tokenizer-root fixture.json") }
        let tokenizer = try NeodragonT5Tokenizer(directory: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("tokenizer_3"))
        struct Fixture: Decodable {
            struct Case: Decodable { let text: String; let ids: [Int32]; let count: Int }
            let cases: [Case]
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        var failures = 0
        for (index, item) in fixture.cases.enumerated() {
            let actual = try tokenizer.encode(item.text)
            if actual.ids != item.ids || actual.count != item.count {
                print("T5 parity failed case \(index): \(item.text.debugDescription)")
                print("actual=\(actual.ids.prefix(actual.count)); expected=\(item.ids.prefix(item.count))")
                failures += 1
            }
        }
        guard failures == 0 else { exit(1) }
        do {
            _ = try tokenizer.encode(Array(repeating: "sailboat", count: 200).joined(separator: " "))
            fatalError("Prompt was silently truncated")
        } catch GenerationError.incompatibleModel { }
        print("Passed \(fixture.cases.count) original SentencePiece/T5 cases and overflow rejection")
    }
}
