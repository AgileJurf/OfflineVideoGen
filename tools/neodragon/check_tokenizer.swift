import Foundation

@main
struct CheckTokenizer {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: check-tokenizer weights-folder fixture.json") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        struct Fixture: Decodable {
            struct Case: Decodable { let tokenizer: String; let text: String; let ids: [Int32] }
            let cases: [Case]
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        var tokenizers: [String: NeodragonCLIPTokenizer] = [:]
        for (index, item) in fixture.cases.enumerated() {
            let tokenizer = try tokenizers[item.tokenizer] ?? NeodragonCLIPTokenizer(directory: root.appendingPathComponent(item.tokenizer))
            tokenizers[item.tokenizer] = tokenizer
            let actual = try tokenizer.encode(item.text)
            guard actual == item.ids else {
                print("Tokenizer parity failed: case \(index), \(item.tokenizer), \(item.text.debugDescription)")
                print("actual=\(actual)\nexpected=\(item.ids)")
                exit(1)
            }
        }
        for (name, tokenizer) in tokenizers {
            do {
                _ = try tokenizer.encode(Array(repeating: "sailboat", count: 100).joined(separator: " "))
                fatalError("\(name) silently accepted an over-limit prompt")
            } catch NeodragonCLIPTokenizer.Failure.tooManyTokens { }
        }
        print("Passed \(fixture.cases.count) full-vocabulary tokenizer cases and \(tokenizers.count) overflow checks")
    }
}
