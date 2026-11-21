import SwiftUI
import VideoEngine

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { CreateView(openSetup: { tab = 2 }) }
                .tabItem { Label("Create", systemImage: "sparkles.tv") }.tag(0)
            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "rectangle.stack") }.tag(1)
            NavigationStack { SetupView() }
                .tabItem { Label("Setup", systemImage: "square.and.arrow.down") }.tag(2)
        }
        .onChange(of: model.creationRequestID) { tab = 0 }
    }
}

struct CreateView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tokenCount: Int?
    let openSetup: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little motion.\nAll yours.").font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Describe a moment and bring it to life on your iPhone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "film.stack.fill").font(.largeTitle).foregroundStyle(.mint)
                }
                Label("Experimental build · performance testing", systemImage: "flask")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Menu {
                        Label("Text to Video", systemImage: "checkmark")
                        Button("Image to Video · model unavailable") { }.disabled(true)
                        Button("Extend Video · model unavailable") { }.disabled(true)
                    } label: { Label("Text to Video", systemImage: "text.bubble") }
                    Spacer()
                    NavigationLink("Capabilities") { ModelCapabilitiesView() }.font(.caption)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SCENE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("A small sailboat glides across a calm lake at sunrise…", text: $model.prompt, axis: .vertical)
                        .lineLimit(4...7).disabled(model.working).accessibilityIdentifier("promptInput")
                    HStack {
                        Text("Include an action, a subject, and a setting.")
                        Spacer()
                        Text("\(model.prompt.count)/500")
                    }.font(.caption2).foregroundStyle(.secondary)
                }.padding(20).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 14) {
                    Text("DURATION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Duration", selection: $model.duration) {
                        ForEach(2...5, id: \.self) { Text("\($0) sec").tag($0) }
                    }.pickerStyle(.segmented).disabled(model.working).accessibilityIdentifier("durationPicker")
                    HStack {
                        Label("256 × 256", systemImage: "square.dashed")
                        Spacer()
                        Text("12 FPS")
                        Spacer()
                        Label("On device", systemImage: "iphone")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                GenerationOptionsView(tokenCount: $tokenCount)
                if !model.installed {
                    Button(action: openSetup) {
                        Label("Install the video model to begin", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).accessibilityIdentifier("openSetup")
                }
                if model.working {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: model.progress.fraction)
                        Text(model.progressMessage).font(.subheadline)
                        if model.isGenerating { Label(model.estimatedTimeMessage, systemImage: "clock").font(.caption).accessibilityIdentifier("generationETA") }
                        Text(model.backgroundStatus).font(.caption).foregroundStyle(.secondary)
                        Button(model.installing ? "Pause installation" : (model.exportingCrop ? "Cancel export" : "Cancel generation"), role: .cancel) { model.cancel() }
                    }.padding().background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Button(action: model.generate) {
                        Label("Generate Video", systemImage: "sparkles").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                        .disabled(!model.installed || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || model.prompt.count > 500 || tokenCount == nil || (tokenCount ?? 0) > 63
                                  || (model.useFixedSeed && UInt64(model.generationSeed) == nil))
                        .accessibilityIdentifier("generateButton")
                }
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                Text("Your prompts and videos stay in this app. Internet is needed only to install the model.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively)
            .navigationTitle("Local Frames").navigationBarTitleDisplayMode(.inline)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if model.videos.isEmpty {
                ContentUnavailableView("Your first frame awaits", systemImage: "film.stack", description: Text("Generated videos will appear here, saved on your iPhone."))
                    .accessibilityIdentifier("emptyLibrary")
            } else {
                List(model.videos) { video in
                    Button { model.selectedVideo = video } label: {
                        HStack(spacing: 14) {
                            if let thumbnail = UIImage(contentsOfFile: model.library.thumbnailURL(video.id).path) {
                                Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 78, height: 78).clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Image(systemName: "film").frame(width: 78, height: 78).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(video.prompt).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text("\(video.duration)s · \(video.width) × \(video.height) · \(video.framesPerSecond) FPS").font(.caption).foregroundStyle(.secondary)
                                Text(video.style.name + (video.isCrop ? " · cropped copy" : " · original")).font(.caption2).foregroundStyle(.mint)
                                Text(video.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }.listStyle(.plain)
            }
        }.navigationTitle("Library")
    }
}

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var confirmDiscardBaseline = false
    var body: some View {
        Form {
            Section {
                Label(model.installed ? "Model installed" : "Install MOVD", systemImage: model.installed ? "checkmark.seal.fill" : "cpu")
                    .font(.headline).foregroundStyle(model.installed ? .mint : .primary)
                Text("A genuine video diffusion model with temporal attention and a video decoder. Generation runs locally; this experimental port is undergoing performance and quality testing.")
                Text("Download: approximately 14.1 GB. Allow 50 GB free during installation. Wi-Fi required.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if model.working {
                    ProgressView(value: model.progress.fraction)
                    Text(model.progressMessage).font(.caption)
                    if model.installing { Button("Pause installation") { model.cancel() } }
                } else if model.installed {
                    Button("Delete model", role: .destructive) { confirmDelete = true }
                } else {
                    Button("Install model") { model.install() }.accessibilityIdentifier("installModelButton")
                }
            } header: { Text("Offline video model") }
            Section("Optional support") {
                NavigationLink("Online support and model updates") { OnlineSupportView(support: model.support) }
                    .disabled(model.working).accessibilityIdentifier("openOnlineSupport")
                Text("Optional Wi-Fi catalog checks and consent-based reports. Generation stays offline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Device benchmark") {
                Toggle("Record local diagnostics for Create jobs", isOn: $model.recordCreationDiagnostics).disabled(model.working)
                Text("Optional logs include prompts, seeds, partition timings, sampled memory and thermal state. They stay on this iPhone unless you export them. Baseline tests always record logs.")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink("Benchmark results and comparisons") { BenchmarkView() }
                    .accessibilityIdentifier("openBenchmarks")
                Text("Run the unchanged 2-second baseline with a fixed prompt and seed. Records each model load and prediction, process memory/CPU samples, and thermal state locally. GPU utilization requires Instruments.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Prompt", selection: $model.benchmarkPromptIndex) {
                    Text("Sailboat").tag(0)
                    Text("Flag").tag(1)
                    Text("Rolling ball").tag(2)
                }.disabled(model.working)
                TextField("Seed", text: $model.benchmarkSeed).keyboardType(.numberPad).disabled(model.working)
                if let saved = model.savedBaselineDescription, !model.working {
                    Text(saved).font(.footnote)
                    Button("Resume saved baseline", action: model.resumeBaseline)
                        .disabled(!model.installed).accessibilityIdentifier("resumeBaseline")
                    Button("Discard saved baseline", role: .destructive) { confirmDiscardBaseline = true }
                }
                Button("Run 2-second baseline", action: model.runBaselineBenchmark)
                    .disabled(!model.installed || model.working || model.savedBaselineDescription != nil).accessibilityIdentifier("runBaselineBenchmark")
                Text("Pauses automatically for cooling and continues when the phone is cool. Completed motion steps are saved for recovery after relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Inspect compute plans", action: model.inspectComputePlans)
                    .disabled(!model.installed || model.working || model.videos.isEmpty)
                Text("Compute-plan inspection becomes available after a video completes. It estimates compatible hardware; it does not measure GPU or Neural Engine utilization.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.working && !model.installing {
                    ProgressView(value: model.progress.fraction)
                    Text(model.progressMessage).font(.caption)
                    Text(model.backgroundStatus).font(.caption).foregroundStyle(.secondary)
                    if model.isGenerating {
                        Label(model.estimatedTimeMessage, systemImage: "clock").font(.caption).accessibilityIdentifier("benchmarkETA")
                        Text("Estimates adapt as work completes. Saving, cooling, and background waits can add time.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Pause benchmark") { model.cancel() }
                }
                if !model.benchmarkFiles.isEmpty {
                    ShareLink(items: model.benchmarkFiles) { Label("Export benchmark files", systemImage: "square.and.arrow.up") }
                        .disabled(model.working)
                    Text("Includes prompts, seeds, measurements, errors, and completed benchmark videos. Export remains available after relaunch, including interrupted attempts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("About this build") {
                NavigationLink("Model capabilities and optional models") { ModelCapabilitiesView() }
                LabeledContent("Engine", value: "MOVD / Open-Sora")
                LabeledContent("Output", value: "256 × 256 · 12 FPS")
                LabeledContent("Duration", value: "2–5 seconds")
                Text("Xcode Cloud tests check the app and supporting code. Device benchmarks record generation time, sampled memory and thermal behavior. Model and sampler changes need on-device quality comparisons.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Source and model documentation", destination: URL(string: "https://github.com/AgileJurf/OfflineVideoGen")!)
            }
        }.navigationTitle("Setup")
            .confirmationDialog("Delete the installed model? Your videos will remain in the library.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete model", role: .destructive) { Task { await model.removeModel() } }
            }
            .confirmationDialog("Discard the saved baseline progress? Exported logs and videos will remain.", isPresented: $confirmDiscardBaseline, titleVisibility: .visible) {
                Button("Discard saved baseline", role: .destructive, action: model.discardSavedBaseline)
            }
    }
}
