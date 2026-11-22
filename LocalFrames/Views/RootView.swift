import SwiftUI
import VideoEngine

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { CreateView(support: model.support, openSetup: { tab = 2 }) }
                .tabItem { Label("Create", systemImage: "sparkles.tv") }.tag(0)
            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "rectangle.stack") }.tag(1)
            NavigationStack { SetupView() }
                .tabItem { Label("Setup", systemImage: "square.and.arrow.down") }.tag(2)
        }
        .onChange(of: model.creationRequestID) { tab = 0 }
        .onChange(of: tab) { _, _ in dismissNativeKeyboard() }
    }
}

enum CreationField: Hashable { case prompt, seed }

func dismissNativeKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct CreationSection<Content: View>: View {
    let title: String
    let icon: String
    let detail: String
    @ViewBuilder let content: Content
    init(_ title: String, icon: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.detail = detail; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(.mint)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct CreateView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tokenCount: Int?
    @FocusState private var focusedField: CreationField?
    @ObservedObject var support: OnlineSupport
    let openSetup: () -> Void
    private func hideKeyboard() { focusedField = nil; dismissNativeKeyboard() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Create a video").font(.title.bold())
                        Text("Generate on your iPhone. Choose an optional online finish.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "film.stack.fill").font(.title).foregroundStyle(.mint)
                }
                PendingSmoothingCard()
                if model.working { GenerationJobCard() }
                CreationSection("Video model", icon: "cpu", detail: "Choose the model used on this iPhone") {
                    Picker("Video model", selection: $model.generationModel) {
                        Text("MOVD").tag(VideoModelChoice.movd)
                        Text("Neodragon · experimental").tag(VideoModelChoice.neodragon).disabled(!model.neodragonInstalled)
                    }.pickerStyle(.menu).disabled(model.working).accessibilityIdentifier("generationModelPicker")
                    Text(model.generationModel == .movd ? "256 × 256 · 12 FPS · 2–5 seconds" : "512 × 320 · 24 FPS · up to \(model.supportedDurations.upperBound) seconds")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.neodragonInstalled {
                        Button("Optional Neodragon model in Setup") { hideKeyboard(); openSetup() }.font(.caption).disabled(model.working)
                    }
                }
                CreationSection("Your scene", icon: "text.bubble", detail: "Describe a subject, an action and a setting") {
                    TextField("A small sailboat glides across a calm lake at sunrise…", text: $model.prompt, axis: .vertical)
                        .lineLimit(3...6).focused($focusedField, equals: .prompt)
                        .disabled(model.working).accessibilityIdentifier("promptInput")
                    HStack {
                        Text("Text to Video")
                        Spacer()
                        Text("\(model.prompt.count)/500 characters")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                GenerationOptionsView(tokenCount: $tokenCount, focusedField: $focusedField)
                if model.generationModel == .movd {
                    GenerationFinishOptions(support: model.support, account: model.helperAccount)
                } else {
                    CreationSection("Frame rate", icon: "film", detail: "Native 24 FPS generation") {
                        Label("Entire job stays on your iPhone", systemImage: "iphone")
                        Text("No upload, frame-smoothing helper, or Hugging Face quota is needed.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.selectedModelInstalled {
                    Button { hideKeyboard(); openSetup() } label: {
                        Label("Install the video model to begin", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).accessibilityIdentifier("openSetup")
                }
                if !model.working && model.pendingSmoothingVideo == nil {
                    Button { hideKeyboard(); model.generate() } label: {
                        Label(model.smoothAfterGeneration ? "Start 24 FPS video job" : "Generate Video", systemImage: "sparkles")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                        .disabled(!model.selectedModelInstalled || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || model.prompt.count > 500 || tokenCount == nil || (tokenCount ?? 0) > (model.generationModel == .movd ? 63 : 128)
                                  || (model.useFixedSeed && UInt64(model.generationSeed) == nil)
                                  || (model.smoothAfterGeneration && model.smoothingSelectionIssue != nil))
                        .accessibilityIdentifier("generateButton")
                }
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                NavigationLink("Model capabilities & experimental limits") { ModelCapabilitiesView() }.font(.caption)
                Text("Your original is always saved locally. Online smoothing requires a separate approval for each clip.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.scrollDismissesKeyboard(.immediately)
            .navigationTitle("Local Frames").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done", action: hideKeyboard).accessibilityIdentifier("dismissKeyboard")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if focusedField != nil {
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down", action: hideKeyboard)
                            .labelStyle(.iconOnly).accessibilityIdentifier("hideKeyboardNavigation")
                    }
                }
            }
            .onChange(of: model.working) { _, working in if working { hideKeyboard() } }
            .onDisappear { hideKeyboard() }
    }
}

struct GenerationJobCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        CreationSection("Current job", icon: "waveform.path", detail: model.isGenerating ? "Generating locally on this iPhone" : "\(model.progress.message)") {
            if model.generationWillSmooth && model.isGenerating {
                Text("1 Generate → 2 Review upload → 3 Smooth → 4 Save").font(.caption).foregroundStyle(.mint)
            }
            ProgressView(value: model.progress.fraction)
            Text(model.progressMessage).font(.subheadline)
            if model.isGenerating {
                Label(model.estimatedTimeMessage, systemImage: "clock").font(.caption).accessibilityIdentifier("generationETA")
                Label(model.backgroundStatus, systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
            }
            Button(model.installing ? "Pause installation" : (model.smoothingActive ? "Cancel smoothing" : (model.exportingCrop ? "Cancel export" : "Cancel generation")), role: .cancel) { model.cancel() }
        }
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
                                Text(video.style.name + (video.smoothing != nil ? " · 24 FPS smoothed copy" : (video.isCrop ? " · cropped copy" : " · original"))).font(.caption2).foregroundStyle(.mint)
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
    var body: some View {
        Form {
            Section {
                Label(model.installed ? "Model installed" : "Install MOVD", systemImage: model.installed ? "checkmark.seal.fill" : "cpu")
                    .font(.headline).foregroundStyle(model.installed ? .mint : .primary)
                Text("Creates videos on this iPhone, including in Airplane Mode after installation.").font(.subheadline)
                Text("Download: approximately 14.1 GB. Allow 50 GB free during installation. Wi-Fi required.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if model.installing && !model.installingNeodragon {
                    ProgressView(value: model.progress.fraction)
                    Text(model.progressMessage).font(.caption)
                    Button("Pause installation") { model.cancel() }
                } else if model.installed {
                    DisclosureGroup("Manage installed model") {
                        Button("Delete model", role: .destructive) { confirmDelete = true }.disabled(model.working)
                    }
                } else {
                    Button("Install model") { model.install() }.disabled(model.working).accessibilityIdentifier("installModelButton")
                }
            } header: { Text("Offline video model") }
            NeodragonSetupSection()
            Section("Online assistance") {
                SetupOnlineSummary(support: model.support, account: model.helperAccount)
            }
            Section("Developer tools") {
                NavigationLink("Benchmark results and comparisons") { BenchmarkView() }.accessibilityIdentifier("openBenchmarks")
                NavigationLink("Run a baseline & local diagnostics") { DeviceBenchmarkToolsView() }.accessibilityIdentifier("openBenchmarkTools")
            }
            Section("About this build") {
                NavigationLink("Model capabilities and optional models") { ModelCapabilitiesView() }
                LabeledContent("Selected engine", value: model.generationModel.name)
                LabeledContent("Output", value: model.generationModel == .movd ? "256 × 256 · 12 FPS" : "512 × 320 · 24 FPS")
                LabeledContent("Duration", value: "2–\(model.supportedDurations.upperBound) seconds")
                Text("Xcode Cloud tests check the app and supporting code. Device benchmarks record generation time, sampled memory and thermal behavior. Model and sampler changes need on-device quality comparisons.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Source and model documentation", destination: URL(string: "https://github.com/AgileJurf/OfflineVideoGen")!)
            }
        }.navigationTitle("Setup")
            .confirmationDialog("Delete the installed model? Your videos will remain in the library.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete model", role: .destructive) { Task { await model.removeModel() } }
            }

    }
}

struct NeodragonSetupSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmInstall = false
    @State private var confirmDelete = false
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    var body: some View {
        Section("Optional video model") {
            Label("Neodragon · experimental", systemImage: model.neodragonInstalled ? "checkmark.seal.fill" : "cpu")
                .font(.headline).foregroundStyle(model.neodragonInstalled ? .mint : .primary)
            Text("Native 512 × 320 landscape video at 24 FPS. Generation stays on this iPhone after installation.").font(.subheadline)
            NavigationLink("Model licenses and use terms") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Neodragon uses Qualcomm’s published hybrid checkpoint. Its model card specifies BSD-3-Clause-Clear and the Qualcomm Responsible AI License.")
                        Link("Qualcomm model use terms", destination: URL(string: "https://www.qualcomm.com/site/responsible-ai-license")!)
                        Link("Original model and documentation", destination: URL(string: "https://huggingface.co/Qualcomm-AI-Research/Neodragon")!)
                        Text(NeodragonModel.licenseNotices).font(.caption).textSelection(.enabled)
                    }.padding()
                }.navigationTitle("Neodragon licenses")
            }
            if let manifest = model.neodragonManifest {
                Text("2–\(manifest.maximumSeconds) seconds · \(size(manifest.downloadBytes)) download · allow \(size(manifest.minimumFreeBytes)) free during installation. Wi-Fi required.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Start with a 2-second test. Speed, memory use and longer-video quality still require validation on your device. MOVD remains available separately.")
                    .font(.footnote).foregroundStyle(.secondary)
                if model.installingNeodragon {
                    ProgressView(value: model.progress.fraction)
                    Text(model.progressMessage).font(.caption)
                    Button("Pause Neodragon installation", action: model.cancel)
                } else if model.neodragonInstalled {
                    Label("Installed for offline use", systemImage: "checkmark.circle").foregroundStyle(.mint)
                    Button("Remove Neodragon", role: .destructive) { confirmDelete = true }.disabled(model.working)
                } else {
                    Button("Download optional Neodragon model") { confirmInstall = true }
                        .disabled(model.working).accessibilityIdentifier("installNeodragonButton")
                }
            } else {
                Text("The converted model package is still being validated. Download and generation are unavailable until those checks pass.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Download the optional Neodragon model?", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Download over Wi-Fi", action: model.installNeodragon)
        } message: {
            if let manifest = model.neodragonManifest {
                Text("Downloads \(size(manifest.downloadBytes)) and needs \(size(manifest.minimumFreeBytes)) free during installation. This experimental model is stored separately from MOVD. Your videos remain in Library.")
            }
        }
        .confirmationDialog("Remove only the optional Neodragon model?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove Neodragon", role: .destructive) { Task { await model.removeNeodragon() } }
        } message: { Text("MOVD and all saved videos will remain available.") }
    }
}

struct DeviceBenchmarkToolsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDiscardBaseline = false
    @FocusState private var seedFocused: Bool
    private func hideKeyboard() { seedFocused = false; dismissNativeKeyboard() }
    var body: some View {
        Form {
            Section("Baseline test") {
                Toggle(isOn: $model.recordCreationDiagnostics) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Record local diagnostics for MOVD Create jobs")
                        Text("Includes prompts, seeds, timings, memory and temperature. Logs stay here unless you export them. Baseline tests and experimental Neodragon jobs always keep local logs.").font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(model.working)
                NavigationLink("Benchmark results and comparisons") { BenchmarkView() }
                    .accessibilityIdentifier("openBenchmarks")
                Text("Run the unchanged MOVD 2-second baseline with a fixed prompt and seed. Records each model load and prediction, process memory/CPU samples, and thermal state locally. GPU utilization requires Instruments.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Prompt", selection: $model.benchmarkPromptIndex) {
                    Text("Sailboat").tag(0)
                    Text("Flag").tag(1)
                    Text("Rolling ball").tag(2)
                }.disabled(model.working)
                TextField("Seed", text: $model.benchmarkSeed).keyboardType(.numberPad).focused($seedFocused).disabled(model.working).accessibilityIdentifier("benchmarkSeed")
                if let saved = model.savedBaselineDescription, !model.working {
                    Text(saved).font(.footnote)
                    Button("Resume saved baseline") { hideKeyboard(); model.resumeBaseline() }
                        .disabled(!model.installed).accessibilityIdentifier("resumeBaseline")
                    Button("Discard saved baseline", role: .destructive) { confirmDiscardBaseline = true }
                }
                Button("Run 2-second baseline") { hideKeyboard(); model.runBaselineBenchmark() }
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
        }.navigationTitle("Baseline & diagnostics").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done", action: hideKeyboard).accessibilityIdentifier("dismissKeyboard")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if seedFocused { Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down", action: hideKeyboard).labelStyle(.iconOnly) }
                }
            }
            .onChange(of: model.working) { _, working in if working { hideKeyboard() } }
            .onDisappear { hideKeyboard() }
            .confirmationDialog("Discard the saved baseline progress? Exported logs and videos will remain.", isPresented: $confirmDiscardBaseline, titleVisibility: .visible) {
                Button("Discard saved baseline", role: .destructive, action: model.discardSavedBaseline)
            }
    }
}
