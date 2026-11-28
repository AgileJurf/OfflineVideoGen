import AVKit
import SwiftUI
import VideoEngine

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @SceneStorage("studio.selectedTab") private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { CreateView(styles: model.styles, openModels: { tab = 2 }) }
                .tabItem { Label("Create", systemImage: "sparkles.tv") }.tag(0)
            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "rectangle.stack") }.tag(1)
            NavigationStack { ModelsView() }
                .tabItem { Label("Models", systemImage: "cpu") }.tag(2)
            NavigationStack { SettingsView(openModels: { tab = 2 }) }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .onChange(of: model.creationRequestID) { tab = 0 }
        .onChange(of: tab) { dismissNativeKeyboard() }
    }
}

struct CreateView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var styles: StyleStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedPrompt = false
    @State private var advanced = false
    @State private var styleBrowser = false
    @State private var logSheet = false
    @State private var tokenCount: Int?
    @State private var tokenError: String?
    @FocusState private var promptFocused: Bool
    let openModels: () -> Void
    private var promptKey: String { model.effectivePrompt + "\n" + String(model.installed) }
    private var canGenerate: Bool {
        model.ready && model.installed && !model.working && !model.exportingFiles && tokenCount != nil && tokenError == nil
            && !model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.prompt.count <= 500
            && (!model.useFixedSeed || UInt64(model.generationSeed) != nil)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    StudioStatus(text: model.installed ? "On-device AI · ready" : "Install once. Create offline.", symbol: model.installed ? "checkmark.shield" : "iphone")
                    Spacer()
                    Button { advanced = true } label: { Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44) }
                        .studioButton().accessibilityLabel("Generation settings").accessibilityIdentifier("advancedGenerationSettings")
                }
                CreationCanvas(video: model.videos.first)
                if model.working { GenerationJobCard(log: model.jobLog) }
                StudioGlassGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Text to Video", systemImage: "text.bubble").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button { expandedPrompt = true; dismissNativeKeyboard() } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("Expand prompt editor").accessibilityIdentifier("expandPrompt")
                        }
                        TextField("Describe a subject, an action and a setting…", text: $model.prompt, axis: .vertical)
                            .lineLimit(3...7).font(.body).focused($promptFocused).disabled(model.working)
                            .accessibilityIdentifier("promptInput")
                        HStack {
                            Text("\(model.prompt.count)/500").monospacedDigit()
                            Spacer()
                            Button("Clear", systemImage: "xmark.circle") { model.prompt = ""; model.clearRestoredConditioning() }
                                .disabled(model.prompt.isEmpty || model.working).frame(minHeight: 44).accessibilityIdentifier("clearPrompt")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(18).studioGlass()
                }
                tokenStatus
                HStack(alignment: .center, spacing: 12) {
                    Picker("Duration", selection: $model.duration) {
                        ForEach(model.supportedDurations, id: \.self) { Text("\($0) seconds").tag($0) }
                    }.pickerStyle(.menu).frame(minHeight: 44).studioGlass(radius: 16).accessibilityIdentifier("durationPicker")
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("512 × 320 · 24 FPS").font(.subheadline.weight(.medium))
                        Text("Native landscape · 16:10").font(.caption).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                }.disabled(model.working)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Visual direction").font(.headline)
                        Spacer()
                        Button("Browse styles", systemImage: "square.grid.2x2") { styleBrowser = true }
                            .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("browseStyles")
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(featuredStyles) { style in
                                StyleCard(style: style, selected: styles.selected.id == style.id) {
                                    styles.select(style); model.clearRestoredConditioning(); StudioTheme.feedback()
                                }
                            }
                        }
                    }.scrollIndicators(.hidden)
                    Text("\(styles.selected.name) · prompt conditioning").font(.caption).foregroundStyle(.secondary)
                }.disabled(model.working)
                if !model.installed {
                    Button(action: openModels) { Label("Install Neodragon to begin", systemImage: "arrow.down.circle").frame(maxWidth: .infinity, minHeight: 44) }
                        .studioButton().accessibilityIdentifier("openModels")
                }
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                if !model.jobLog.entries.isEmpty && !model.working {
                    Button("View last job log", systemImage: "list.bullet.rectangle") { logSheet = true }.frame(minHeight: 44)
                }
                if model.duration > 2 { Text("Longer durations use the existing model path and need further device quality testing. Start with 2 seconds when comparing styles.").font(.caption).foregroundStyle(.secondary) }
            }.padding(20)
        }
        .studioBackground().scrollDismissesKeyboard(.immediately)
        .navigationTitle("LOCAL FRAMES").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !model.working {
                Button { promptFocused = false; dismissNativeKeyboard(); StudioTheme.feedback(); model.generate() } label: {
                    Label(model.exportingFiles ? "Saving export copies…" : "Generate Video", systemImage: "sparkles")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }.studioButton(prominent: true).disabled(!canGenerate).accessibilityIdentifier("generateButton")
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(StudioTheme.background)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { promptFocused = false; dismissNativeKeyboard() }.accessibilityIdentifier("dismissKeyboard") }
            ToolbarItem(placement: .topBarTrailing) {
                if promptFocused { Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { promptFocused = false; dismissNativeKeyboard() }.accessibilityIdentifier("hideKeyboardNavigation") }
            }
        }
        .sheet(isPresented: $advanced) { GenerationSettingsSheet().environmentObject(model) }
        .sheet(isPresented: $expandedPrompt) { PromptEditor().environmentObject(model) }
        .sheet(isPresented: $styleBrowser) { StyleBrowser(store: styles) }
        .onChange(of: styles.selected) { model.clearRestoredConditioning() }
        .sheet(isPresented: $logSheet) { JobLogView(log: model.jobLog) }
        .onChange(of: model.working) { if model.working { promptFocused = false; dismissNativeKeyboard() } }
        .onDisappear { promptFocused = false; dismissNativeKeyboard() }
        .task(id: promptKey) { await checkTokens() }
    }
    private var featuredStyles: [StyleConditioning] {
        var list = [styles.selected]
        for item in [VisualStyle.default, .anime, .photorealistic, .cinematic].map(StyleCatalog.definition) where !list.contains(where: { $0.id == item.id }) { list.append(item) }
        return list
    }
    private var tokenStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tokenCount.map { "\($0)/128 motion tokens · all four CLIP inputs fit 77 tokens" } ?? (model.installed ? "Checking complete prompt…" : "Token validation becomes available after model installation"))
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("promptTokenBudget")
            if let tokenError { Text(tokenError).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("promptError") }
        }
    }
    private func checkTokens() async {
        tokenCount = nil; tokenError = nil
        guard model.prompt.count <= 500 else { tokenError = "Use up to 500 characters. Your prompt has not been shortened."; return }
        guard model.installed else { return }
        let text = model.effectivePrompt, directory = model.modelDirectory
        do {
            try await Task.sleep(for: .milliseconds(250))
            let count = try await Task.detached(priority: .userInitiated) { try NeodragonEngine.promptTokenCount(text, modelsAt: directory) }.value
            try Task.checkCancellation(); tokenCount = count
        } catch is CancellationError { }
        catch { tokenError = error.localizedDescription }
    }
}

struct CreationCanvas: View {
    @EnvironmentObject private var model: AppModel
    let video: VideoRecord?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(StudioTheme.surface)
            if let video {
                VideoThumbnail(url: model.library.thumbnailURL(video.id)).scaledToFit()
                VStack { Spacer(); HStack {
                    Text(model.working ? "Previous output" : "Latest video").font(.caption.weight(.medium))
                    Spacer()
                    Button { model.selectedVideo = video } label: { Image(systemName: "play.fill").frame(minWidth: 44, minHeight: 44) }
                        .studioButton().accessibilityLabel("Play latest video").disabled(model.isGenerating)
                }.padding(12).studioGlass(radius: 18).padding(10) }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder").font(.system(size: 32, weight: .ultraLight))
                    Text("Your scene starts here").font(.headline)
                    Text("Describe the motion. Keep it on your device.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding()
            }
        }.aspectRatio(1.6, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 26))
            .accessibilityIdentifier("creationCanvas")
    }
}

struct GenerationJobCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var log: JobActivityLog
    @State private var showLog = false
    var body: some View {
        StudioSection(title: model.installing ? "Installing model" : "Current generation", subtitle: model.progressMessage) {
            if model.progress.fraction > 0 && model.progress.fraction < 1 { ProgressView(value: model.progress.fraction).accessibilityLabel("Reported engine progress") }
            else { ProgressView().accessibilityLabel("Working") }
            if model.isGenerating {
                if let start = model.jobStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Elapsed " + elapsed(max(0, context.date.timeIntervalSince(start)))).font(.caption.monospacedDigit())
                    }
                }
                Text(model.estimatedTimeMessage).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("generationETA")
                LiveJobRows(log: log)
            }
            HStack {
                if model.isGenerating { Button("Running log", systemImage: "list.bullet.rectangle") { showLog = true }.accessibilityIdentifier("runningJobLog") }
                Spacer()
                Button(model.installing ? "Pause download" : "Cancel job", role: .cancel, action: model.cancel).accessibilityIdentifier("cancelGeneration")
            }.font(.subheadline).frame(minHeight: 44)
        }.sheet(isPresented: $showLog) { JobLogView(log: log) }
    }
    private func elapsed(_ seconds: Double) -> String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

struct LiveJobRows: View {
    @ObservedObject var log: JobActivityLog
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(log.entries.suffix(4)) { entry in
                HStack(alignment: .top, spacing: 8) { Text(entry.time).monospacedDigit(); Text(entry.message).lineLimit(2) }
                    .font(.caption).foregroundStyle(.secondary).accessibilityElement(children: .combine)
            }
        }.accessibilityIdentifier("liveJobRows")
    }
}
struct JobLogView: View {
    @ObservedObject var log: JobActivityLog
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("Latest 200 events. The view refreshes at most twice per second. Full journals are available in Settings → Export Benchmark Files.").font(.caption).foregroundStyle(.secondary)
                ForEach(log.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 5) { Text(entry.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary); Text(entry.message).font(.subheadline).textSelection(.enabled) }
                }
            }.studioBackground().navigationTitle(log.recording ? "Running log" : "Job log")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
