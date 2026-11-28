import Foundation

/// Prompt-based presets; no trained adapter is implied.
public enum VisualStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case `default`, photorealistic, hyperrealistic, cinematic, documentary, photography, naturalLighting, filmNoir, vintageFilm, blackAndWhite, film35mm, vhs, foundFootage, anime, retroAnime, manga, cartoon, westernAnimation, animation3D, claymation, stopMotion, handDrawn, celShaded, pixelArt, lowPoly, watercolor, oilPainting, pencilSketch, comicBook, graphicNovel, impressionism, surrealism, abstractArt, inkIllustration, paperCutout, scienceFiction, cyberpunk, steampunk, darkFantasy, highFantasy, fantasy, horror, gothic, western, historical, postApocalyptic, action, noirThriller, dreamlike, experimentalCinema, natureDocumentary, underwater, spaceExploration, atmospheric, neonCity, retroFuturism, miniature, macro
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .default: return "Default / Original"
        case .photorealistic: return "Photorealistic"
        case .cinematic: return "Cinematic"
        case .anime: return "Anime"
        case .cartoon: return "Cartoon"
        case .animation3D: return "3D Animation"
        case .pixelArt: return "Pixel Art"
        case .watercolor: return "Watercolor"
        case .claymation: return "Claymation"
        case .blackAndWhite: return "Black & White"
        case .vintageFilm: return "Vintage Film"
        case .fantasy: return "Fantasy"
        default: return StyleCatalog.definition(self).name
        }
    }

    public var detail: String {
        switch self {
        case .default: return "Your scene, without added style instructions."
        case .photorealistic: return "Natural lighting and realistic textures."
        case .cinematic: return "Film lighting and composed camera movement."
        case .anime: return "Anime-inspired lines and cel shading."
        case .cartoon: return "Bold shapes and playful drawn colors."
        case .animation3D: return "Sculpted forms and animated-film lighting."
        case .pixelArt: return "Retro pixels and a limited color palette."
        case .watercolor: return "Soft washes and painted paper textures."
        case .claymation: return "Handcrafted clay and stop-motion character."
        case .blackAndWhite: return "Monochrome tones and contrast."
        case .vintageFilm: return "Soft retro colors and film grain."
        case .fantasy: return "Dreamlike light and a magical atmosphere."
        default: return StyleCatalog.definition(self).aesthetic
        }
    }

    public var instruction: String {
        switch self {
        case .default: return ""
        case .photorealistic: return "Photorealistic, natural lighting, realistic textures."
        case .cinematic: return "Cinematic lighting, film composition, smooth camera motion."
        case .anime: return "Anime style, cel shading, expressive line art."
        case .cartoon: return "Cartoon animation, bold shapes, vibrant colors."
        case .animation3D: return "3D animated film style, soft lighting, detailed materials."
        case .pixelArt: return "Pixel art, crisp pixel shapes, limited retro palette."
        case .watercolor: return "Watercolor painting, soft washes, textured paper."
        case .claymation: return "Claymation, handmade clay figures, stop-motion style."
        case .blackAndWhite: return "Black and white, monochrome, rich tonal contrast."
        case .vintageFilm: return "Vintage film, subtle grain, faded retro colors."
        case .fantasy: return "Fantasy art, magical atmosphere, luminous cinematic light."
        default: return StyleCatalog.definition(self).aesthetic
        }
    }

    public func applying(to prompt: String) -> String {
        let original = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return self == .default ? original : original + "\nVisual style: " + instruction
    }
}

public enum GenerationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case textToVideo, imageToVideo, extendVideo
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .textToVideo: return "Text to Video"
        case .imageToVideo: return "Image to Video"
        case .extendVideo: return "Extend Video"
        }
    }
    public var unavailableReason: String? {
        switch self {
        case .textToVideo: return nil
        case .imageToVideo: return "The installed model cannot use a reference image. An image encoder and compatible image-conditioned model partitions still need conversion and iPhone validation."
        case .extendVideo: return "Continuation needs a model that can condition new frames on the ending of your video. The installed text-only model cannot do this yet. Your original video is preserved."
        }
    }
}

/// Export framing, never a change to the diffusion model's native square tensors.
public enum OutputFraming: String, Codable, CaseIterable, Identifiable, Sendable {
    case square, portrait, landscape
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .square: return "Square (1:1)"
        case .portrait: return "Portrait (9:16)"
        case .landscape: return "Landscape (16:9)"
        }
    }
    public var width: Int { self == .portrait ? 144 : 256 }
    public var height: Int { self == .landscape ? 144 : 256 }
    public var isCrop: Bool { self != .square }
    public var detail: String {
        isCrop ? "Center crop · \(width) × \(height). Generates a square video first and saves a cropped copy. The full square original stays in your library."
            : "Native square generation · 256 × 256."
    }
}
