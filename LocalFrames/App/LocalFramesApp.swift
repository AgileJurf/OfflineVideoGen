import SwiftUI

@main
struct LocalFramesApp: App {
    @StateObject private var model = Self.makeModel()
    @AppStorage("studio.appearance") private var appearance = StudioAppearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    @MainActor private static func makeModel() -> AppModel {
        #if DEBUG
        // Isolated data only, never an alternative generation engine. Release
        // archives contain neither fixture launch arguments nor fake generation.
        if let value = ProcessInfo.processInfo.environment["LOCALFRAMES_UI_TEST_ID"], UUID(uuidString: value) != nil {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("UI-" + value)
            if !FileManager.default.fileExists(atPath: root.path) {
                for key in ["studio.appearance", "studio.reduceEffects", "studio.haptics", "studio.libraryGrid", "studio.libraryNewest", "studio.selectedTab"] {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            return AppModel(root: root)
        }
        #endif
        return AppModel()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(StudioTheme.accent)
                .foregroundStyle(StudioTheme.text)
                .preferredColorScheme((StudioAppearance(rawValue: appearance) ?? .system).scheme)
                .task { await model.load() }
                .onChange(of: scenePhase) { _, phase in
                    model.sceneChanged(phase)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    model.handleMemoryWarning()
                }
                .alert("Local Frames", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
                .fullScreenCover(item: $model.selectedVideo) { video in
                    PreviewView(video: video).environmentObject(model)
                }

        }
    }
}
