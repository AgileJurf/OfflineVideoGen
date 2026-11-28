import Foundation

public enum StyleCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case realistic, animation, artistic, genre, environment
    public var id: String { rawValue }
    public var title: String { switch self { case .realistic: return "Realistic"; case .animation: return "Animation"; case .artistic: return "Artistic"; case .genre: return "Cinema & Genre"; case .environment: return "Environment" } }
}

/// Versioned, local prompt conditioning. Empty fields add no instructions.
/// There is deliberately no strength scalar: this checkpoint has no validated
/// independent style-strength input. Original user text is never shortened.
public struct StyleConditioning: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var category: StyleCategory
    public var aesthetic: String
    public var palette: String
    public var lighting: String
    public var camera: String
    public var motion: String
    public var isCustom: Bool
    public let version: Int
    public init(id: String, name: String, category: StyleCategory = .artistic, aesthetic: String = "", palette: String = "", lighting: String = "", camera: String = "", motion: String = "", isCustom: Bool = false) {
        self.id = id; self.name = name; self.category = category; self.aesthetic = aesthetic
        self.palette = palette; self.lighting = lighting; self.camera = camera; self.motion = motion
        self.isCustom = isCustom; self.version = 2
    }
    public var instructions: String {
        [aesthetic, palette.isEmpty ? "" : "Palette: " + palette,
         lighting.isEmpty ? "" : "Lighting: " + lighting, camera.isEmpty ? "" : "Camera: " + camera,
         motion.isEmpty ? "" : "Motion: " + motion].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    public func applying(to prompt: String) -> String {
        let original = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return instructions.isEmpty ? original : original + "\nVisual direction: " + instructions
    }
    public func validate() throws {
        guard version == 2, !id.isEmpty, id.count <= 100, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 60, [aesthetic, palette, lighting, camera, motion].allSatisfy({ $0.count <= 500 }),
              instructions.count <= 1500 else { throw GenerationError.incompatibleModel("Style fields are too long or incomplete. Shorten them; nothing has been truncated.") }
    }
}

public enum StyleCatalog {
    public static let all: [StyleConditioning] = [
        .init(id: "default", name: "Default / Original", category: .realistic, aesthetic: ""),
        .init(id: "photorealistic", name: "Photorealistic", category: .realistic, aesthetic: "Photographic realism; true-to-life colors; natural light; tactile surfaces; stable anatomy and coherent motion."),
        .init(id: "hyperrealistic", name: "Hyperrealistic", category: .realistic, aesthetic: "Hyperreal photography; fine pores and material detail; lifelike color; precise light; restrained, anatomically coherent movement."),
        .init(id: "cinematic", name: "Cinematic", category: .realistic, aesthetic: "Cinematic film composition; motivated key light; subtle color separation; detailed materials; coherent camera and subject movement."),
        .init(id: "documentary", name: "Documentary", category: .realistic, aesthetic: "Observational documentary; available light; natural colors and textures; candid composition; unembellished movement."),
        .init(id: "photography", name: "Professional Photography", category: .realistic, aesthetic: "Editorial photography; balanced composition; controlled soft light; precise focus; realistic materials and movement."),
        .init(id: "naturalLighting", name: "Natural Lighting", category: .realistic, aesthetic: "Soft available daylight; neutral colors; realistic shadows and textures; gently observed natural movement."),
        .init(id: "filmNoir", name: "Film Noir", category: .realistic, aesthetic: "Film noir; black-and-white silver tones; hard side light; deep shadows; dramatic composition; restrained movement."),
        .init(id: "vintageFilm", name: "Vintage Film", category: .realistic, aesthetic: "Vintage analog film; muted warm colors; gentle grain; soft highlights; composed framing; natural motion."),
        .init(id: "blackAndWhite", name: "Black and White", category: .realistic, aesthetic: "Monochrome photography; rich grayscale; directional light; detailed texture; graphic composition; coherent natural motion."),
        .init(id: "film35mm", name: "35mm Film", category: .realistic, aesthetic: "35mm color film; fine grain; natural contrast; soft highlight rolloff; photographic detail; fluid realistic movement."),
        .init(id: "vhs", name: "1980s VHS", category: .realistic, aesthetic: "1980s VHS home video; soft analog detail; muted chroma; practical light; candid framing; natural movement."),
        .init(id: "foundFootage", name: "Found Footage", category: .realistic, aesthetic: "Found-footage realism; available light; imperfect documentary framing; unpolished textures; believable spontaneous movement."),
        .init(id: "anime", name: "Anime", category: .animation, aesthetic: "Anime cel animation; expressive linework; clean flat colors; painted backgrounds; consistent character silhouettes; purposeful animated motion."),
        .init(id: "retroAnime", name: "Retro Anime", category: .animation, aesthetic: "1980s anime cels; ink outlines; limited warm palette; painted scenery; dramatic shadows; consistent hand-drawn movement."),
        .init(id: "manga", name: "Manga", category: .animation, aesthetic: "Animated manga panels; black ink; monochrome screentones; expressive composition; crisp contours; consistent drawn motion."),
        .init(id: "cartoon", name: "Cartoon", category: .animation, aesthetic: "Cartoon animation; bold outlines; bright flat colors; simplified forms; expressive staging; coherent elastic movement."),
        .init(id: "westernAnimation", name: "Western Animation", category: .animation, aesthetic: "Classic Western animation; appealing rounded forms; painted backgrounds; warm colors; clear silhouettes; expressive character acting."),
        .init(id: "animation3D", name: "3D Animation", category: .animation, aesthetic: "3D animated film; sculpted forms; soft global lighting; rich materials; clear composition; consistent volumetric movement."),
        .init(id: "claymation", name: "Claymation", category: .animation, aesthetic: "Clay stop-motion; sculpted handmade surfaces; soft studio light; miniature scenery; incremental tactile character movement."),
        .init(id: "stopMotion", name: "Stop Motion", category: .animation, aesthetic: "Stop-motion puppet film; miniature sets; tactile fabric and props; practical light; deliberate frame-by-frame movement."),
        .init(id: "handDrawn", name: "Hand-Drawn Animation", category: .animation, aesthetic: "Hand-drawn animation; organic pencil outlines; softly painted colors; clear silhouettes; flowing coherent drawn movement."),
        .init(id: "celShaded", name: "Cel-Shaded Animation", category: .animation, aesthetic: "Cel-shaded animation; sharp ink contours; stepped light and shadow; clean colors; consistent shapes and fluid movement."),
        .init(id: "pixelArt", name: "Pixel Art", category: .animation, aesthetic: "Pixel-art animation; crisp pixel clusters; limited retro palette; consistent pixel scale; readable silhouettes; deliberate sprite motion."),
        .init(id: "lowPoly", name: "Low-Poly Animation", category: .animation, aesthetic: "Low-poly animation; visible geometric facets; restrained palette; simple directional light; coherent solid forms and motion."),
        .init(id: "watercolor", name: "Watercolor", category: .artistic, aesthetic: "Watercolor animation; translucent pigment washes; textured paper; soft edges; luminous colors; coherent painted motion."),
        .init(id: "oilPainting", name: "Oil Painting", category: .artistic, aesthetic: "Animated oil painting; layered brushwork; impasto texture; rich pigments; painterly light; stable subjects in fluid motion."),
        .init(id: "pencilSketch", name: "Pencil Sketch", category: .artistic, aesthetic: "Animated graphite drawing; paper texture; soft crosshatching; monochrome shading; precise contours; coherent drawn movement."),
        .init(id: "comicBook", name: "Comic Book", category: .artistic, aesthetic: "Animated comic-book art; bold ink contours; halftone shading; vivid colors; dynamic composition; consistent character forms."),
        .init(id: "graphicNovel", name: "Graphic Novel", category: .artistic, aesthetic: "Graphic-novel animation; fine ink lines; muted expressive colors; dramatic shadows; cinematic panel composition; coherent motion."),
        .init(id: "impressionism", name: "Impressionism", category: .artistic, aesthetic: "Animated impressionist painting; visible short brushstrokes; luminous broken colors; soft daylight; stable composition and flowing movement."),
        .init(id: "surrealism", name: "Surrealism", category: .artistic, aesthetic: "Surrealist painted world; dreamlike atmosphere; precise unusual forms; unexpected colors; coherent subjects and deliberate movement."),
        .init(id: "abstractArt", name: "Abstract Art", category: .artistic, aesthetic: "Abstract animated art; expressive shapes; layered color fields; rhythmic composition; coherent transformations and flowing motion."),
        .init(id: "inkIllustration", name: "Ink Illustration", category: .artistic, aesthetic: "Animated ink illustration; fluid black lines; crosshatched shadows; paper texture; graphic negative space; coherent contours in motion."),
        .init(id: "paperCutout", name: "Paper Cutout", category: .artistic, aesthetic: "Paper-cutout animation; layered paper edges; matte colors; soft cast shadows; simple stage composition; articulated cut-paper motion."),
        .init(id: "scienceFiction", name: "Science Fiction", category: .genre, aesthetic: "Science-fiction cinema; precise futuristic materials; restrained luminous accents; atmospheric light; coherent scale and believable movement."),
        .init(id: "cyberpunk", name: "Cyberpunk", category: .genre, aesthetic: "Cyberpunk cinema; neon cyan and magenta; wet reflective surfaces; dense urban atmosphere; dramatic framing; coherent realistic motion."),
        .init(id: "steampunk", name: "Steampunk", category: .genre, aesthetic: "Steampunk cinema; brass and weathered leather; warm industrial light; mechanical texture; atmospheric composition; articulated mechanical motion."),
        .init(id: "darkFantasy", name: "Dark Fantasy", category: .genre, aesthetic: "Dark fantasy illustration; desaturated jewel tones; low dramatic light; weathered textures; ominous atmosphere; coherent character motion."),
        .init(id: "highFantasy", name: "High Fantasy", category: .genre, aesthetic: "High-fantasy cinema; luminous natural colors; ornate materials; majestic composition; magical atmosphere; coherent graceful movement."),
        .init(id: "fantasy", name: "Fantasy", category: .genre, aesthetic: "Fantasy art; luminous color; detailed mythical materials; atmospheric light; coherent silhouettes and graceful motion."),
        .init(id: "horror", name: "Horror", category: .genre, aesthetic: "Horror cinema; subdued colors; sparse directional light; deep textured shadows; tense framing; deliberate believable movement."),
        .init(id: "gothic", name: "Gothic", category: .genre, aesthetic: "Gothic cinema; dark jewel tones; candlelit contrast; ornate aged textures; solemn composition; restrained coherent motion."),
        .init(id: "western", name: "Western", category: .genre, aesthetic: "Western film; earthy colors; warm hard sunlight; dusty weathered textures; expansive framing; grounded natural movement."),
        .init(id: "historical", name: "Historical", category: .genre, aesthetic: "Historical cinema; period materials; muted natural dyes; practical light; detailed environments; believable character movement."),
        .init(id: "postApocalyptic", name: "Post-Apocalyptic", category: .genre, aesthetic: "Post-apocalyptic cinema; dusty muted colors; worn surfaces; harsh atmospheric light; grounded scale; believable physical movement."),
        .init(id: "action", name: "Action", category: .genre, aesthetic: "Action cinema; crisp dramatic lighting; clear spatial staging; detailed materials; readable energetic motion and consistent subjects."),
        .init(id: "noirThriller", name: "Noir Thriller", category: .genre, aesthetic: "Noir thriller; restrained cool colors; sharp light and shadow; textured urban realism; tense composition; controlled motion."),
        .init(id: "dreamlike", name: "Dreamlike", category: .genre, aesthetic: "Dreamlike cinema; soft luminous colors; diffused light; delicate textures; spacious composition; coherent floating movement."),
        .init(id: "experimentalCinema", name: "Experimental Cinema", category: .genre, aesthetic: "Experimental cinema; graphic framing; expressive color and shadow; tactile film texture; deliberate visual rhythm and coherent motion."),
        .init(id: "natureDocumentary", name: "Nature Documentary", category: .environment, aesthetic: "Nature documentary; true natural colors; available daylight; detailed organic textures; observational framing; realistic animal and environmental movement."),
        .init(id: "underwater", name: "Underwater", category: .environment, aesthetic: "Underwater cinematography; blue-green light; soft caustics; suspended particles; coherent depth; fluid buoyant movement."),
        .init(id: "spaceExploration", name: "Space Exploration", category: .environment, aesthetic: "Space-exploration cinema; deep black and restrained colors; hard stellar light; precise materials; coherent scale and inertial motion."),
        .init(id: "atmospheric", name: "Atmospheric", category: .environment, aesthetic: "Atmospheric cinema; muted layered colors; diffused volumetric light; fine environmental textures; spatial depth; coherent subtle movement."),
        .init(id: "neonCity", name: "Neon City", category: .environment, aesthetic: "Neon-city cinema; saturated signs; cool shadows; reflective surfaces; layered urban depth; coherent street and camera movement."),
        .init(id: "retroFuturism", name: "Retro Futurism", category: .environment, aesthetic: "Retro-futurist cinema; pastel and chrome palette; soft practical light; rounded vintage technology; clear staging; coherent motion."),
        .init(id: "miniature", name: "Miniature / Tilt-Shift", category: .environment, aesthetic: "Miniature diorama photography; shallow tilt-shift focus; tactile small-scale detail; soft studio light; consistent scale and movement."),
        .init(id: "macro", name: "Macro Photography", category: .environment, aesthetic: "Macro cinematography; precise fine textures; very shallow focus; diffused light; magnified natural detail; coherent small-scale movement."),
    ]
    public static func definition(_ style: VisualStyle) -> StyleConditioning { all.first { $0.id == style.rawValue }! }
}
