import Foundation
import Combine
import VideoEngine

@MainActor
final class StyleStore: ObservableObject {
    private struct State: Codable {
        var version = 1
        var custom: [StyleConditioning] = []
        var selected = VisualStyle.default.rawValue
        var favorites: Set<String> = []
        var recent: [String] = []
    }
    @Published private var state: State
    @Published var error: String?
    private let url: URL
    init(url: URL, legacyStyle: VisualStyle = .default) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(State.self, from: data), saved.version == 1 {
            state = saved
        } else { state = State(selected: legacyStyle.rawValue) }
    }
    var all: [StyleConditioning] { StyleCatalog.all + state.custom }
    var custom: [StyleConditioning] { state.custom }
    var selected: StyleConditioning { all.first { $0.id == state.selected } ?? StyleCatalog.definition(.default) }
    var recent: [StyleConditioning] { state.recent.compactMap { id in all.first { $0.id == id } } }
    func isFavorite(_ style: StyleConditioning) -> Bool { state.favorites.contains(style.id) }
    func select(_ style: StyleConditioning) {
        guard all.contains(where: { $0.id == style.id }) else { return }
        state.selected = style.id; save()
    }
    func recordUse() {
        state.recent.removeAll { $0 == selected.id }; state.recent.insert(selected.id, at: 0)
        state.recent = Array(state.recent.prefix(10)); save()
    }
    func toggleFavorite(_ style: StyleConditioning) {
        if !state.favorites.insert(style.id).inserted { state.favorites.remove(style.id) }; save()
    }
    func upsert(_ style: StyleConditioning) throws {
        try style.validate()
        guard style.isCustom, style.id.hasPrefix("custom-"),
              !StyleCatalog.all.contains(where: { $0.id == style.id }),
              state.custom.count < 100 || state.custom.contains(where: { $0.id == style.id }) else {
            throw GenerationError.incompatibleModel("Keep up to 100 custom styles. Built-in styles can be duplicated, but not replaced.")
        }
        var updated = state
        if let index = updated.custom.firstIndex(where: { $0.id == style.id }) { updated.custom[index] = style }
        else { updated.custom.append(style) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: url, options: .atomic)
        state = updated
    }
    func remove(_ style: StyleConditioning) {
        guard style.isCustom else { return }
        state.custom.removeAll { $0.id == style.id }; state.favorites.remove(style.id)
        state.recent.removeAll { $0 == style.id }
        if state.selected == style.id { state.selected = VisualStyle.default.rawValue }
        save()
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch { self.error = "The style change is available for this session but could not be saved: " + error.localizedDescription }
    }
}
