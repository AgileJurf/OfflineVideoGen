import Foundation

/// An isolated conversion of the existing 18 motion blocks. It reuses the
/// installed checkpoint's remaining components and never replaces that install.
public struct NeodragonAttentionVariant: Codable, Sendable {
    public static let identifier = "neodragon-attention-head8-v1"
    public static let profileID = "neodragon-hybrid-motion-head8-cpu-v1"
    public static let metadataFilename = "neodragon-attention.json"
    public static let modelNames = (0..<18).map { String(format: "transformer_block_%02d", $0) }

    public let schemaVersion: Int
    public let variantID: String
    public let baseModelID: String
    public let sourceRevision: String
    public let weightsRevision: String
    public let attentionHeadGroupSize: Int
    public let maximumSeconds: Int
    public let modelNames: [String]

    public func validate() throws {
        guard schemaVersion == 1, variantID == Self.identifier,
              baseModelID == NeodragonModel.identifier,
              sourceRevision == NeodragonModel.sourceRevision,
              weightsRevision == NeodragonModel.weightsRevision,
              attentionHeadGroupSize == 8, maximumSeconds == 9,
              modelNames.count == Self.modelNames.count,
              Set(modelNames) == Set(Self.modelNames) else {
            throw GenerationError.incompatibleModel("The attention update does not match the installed Neodragon checkpoint.")
        }
    }

    public static func validateInstallation(at directory: URL) throws -> Self {
        let file = directory.appendingPathComponent(metadataFilename)
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16_384 else {
            throw GenerationError.invalidTensor
        }
        let metadata = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        try metadata.validate()
        for name in modelNames {
            let path = directory.appendingPathComponent(name + ".mlmodelc")
            let attributes = try path.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard attributes.isDirectory == true, attributes.isSymbolicLink != true,
                  !(try FileManager.default.contentsOfDirectory(atPath: path.path)).isEmpty else {
                throw GenerationError.modelMissing(name)
            }
        }
        return metadata
    }

    /// Experimental phone comparison is limited to the requested short and
    /// five-second runs, even though conversion screens the full original range.
    public static let deviceTrialMaximumSeconds = 5
}
