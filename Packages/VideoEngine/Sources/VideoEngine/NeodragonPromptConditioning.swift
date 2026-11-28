import Foundation

/// Optional reproduction of DEFAULT_PROMPT_MODIFIER in the pinned upstream
/// hybrid pipeline. This changes text conditioning, not weights or sampling.
public enum NeodragonPromptConditioning {
    public static let upstreamDetailSuffix = ", cinematic, realistic textures, high detail, natural colours"
    public static func upstreamDetail(_ prompt: String) -> String {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.hasSuffix(upstreamDetailSuffix) else { return clean }
        return clean + upstreamDetailSuffix
    }
}
