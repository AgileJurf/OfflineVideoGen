import SwiftUI

@main
struct LocalFramesApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(.mint)
                .preferredColorScheme(.dark)
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
                .sheet(item: $model.selectedVideo) { video in
                    PreviewView(video: video).environmentObject(model)
                }
                .sheet(item: $model.workflowReview) { video in
                    WorkflowReviewSheet(video: video).environmentObject(model)
                }
        }
    }
}
