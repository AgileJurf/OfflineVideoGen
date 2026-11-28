import SwiftUI
import VideoEngine

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("studio.appearance") private var appearance = StudioAppearance.system.rawValue
    @AppStorage("studio.haptics") private var haptics = true
    @AppStorage("studio.reduceEffects") private var reducedEffects = false
    let openModels: () -> Void
    var body: some View {
        Form {
            ExportFilesSection()
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(StudioAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }.accessibilityIdentifier("appearancePicker")
                Toggle("Reduced visual effects", isOn: $reducedEffects).accessibilityIdentifier("reducedEffectsToggle")
                Toggle("Haptic feedback", isOn: $haptics).accessibilityIdentifier("hapticsToggle")
                Text("System Reduce Motion, Reduce Transparency, Dynamic Type and VoiceOver settings are respected.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Generation") {
                NavigationLink("Generation preferences") { GenerationPreferencesView() }
                Button("AI model management", systemImage: "cpu", action: openModels)
                NavigationLink { OfflineInformationView() } label: { Label("Offline functionality", systemImage: "iphone") }
            }
            Section("Storage and diagnostics") {
                NavigationLink { StorageView() } label: { Label("Storage management", systemImage: "internaldrive") }.accessibilityIdentifier("openStorage")
                NavigationLink { BenchmarkView() } label: { Label("Frame Lab", systemImage: "waveform.path.ecg") }.accessibilityIdentifier("openFrameLab")
            }
            Section("Privacy") {
                Text("Generation, prompt styles and custom presets run entirely on this iPhone. There is no assistant sign-in or video upload in this build.")
                Text("Diagnostics are stored locally. Exporting benchmark files may include prompts, seeds, device measurements and old benchmark videos; review the files before sharing.").font(.caption).foregroundStyle(.secondary)
            }
            Section("About LOCAL FRAMES") {
                Text("Your imagination. Your device.").font(.headline)
                LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development") + ")")
                NavigationLink("Licenses and model provenance") { ModelLicensesView() }
                Link("Source and documentation", destination: URL(string: "https://github.com/AgileJurf/OfflineVideoGen")!)
            }
        }.studioBackground().navigationTitle("Settings")
    }
}
struct ExportFilesSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var share: SharedFiles?
    var body: some View {
        Section {
            Button {
                Task { let urls = await model.exportBenchmarks(); if !urls.isEmpty { share = .init(urls: urls) } }
            } label: {
                Label("Export Benchmark Files", systemImage: "square.and.arrow.up")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.disabled(model.working || model.exportingFiles || model.benchmarkFiles.isEmpty).accessibilityIdentifier("exportBenchmarkFiles")
            Text(model.benchmarkFiles.isEmpty ? "No benchmark files yet. Run a generation or a Frame Lab baseline to record a local journal." : "\(model.benchmarkFiles.count) local files available. Includes prompts and measurements; nothing is uploaded automatically.")
                .font(.caption).foregroundStyle(.secondary)
            Label("Local Frames folder", systemImage: "folder").font(.subheadline.weight(.medium))
            Text("Files → Browse → On My iPhone → Local Frames\nVideos and Benchmarks are stored in separate folders.").font(.caption).foregroundStyle(.secondary)
            if let status = model.filesStatus, status.hasPrefix("Some") { Text(status).font(.caption).foregroundStyle(.orange) }
        } header: { Text("Files & exports") }
        .sheet(item: $share) { ActivityShareSheet(urls: $0.urls) }
    }
}
struct GenerationPreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool
    var body: some View {
        Form {
            Section("Repeatable creation") {
                Toggle("Use a fixed seed", isOn: $model.useFixedSeed)
                TextField("Seed", text: $model.generationSeed).keyboardType(.numberPad).focused($focused)
                Picker("Default duration", selection: $model.duration) { ForEach(model.supportedDurations, id: \.self) { Text("\($0) seconds").tag($0) } }
            }
            Section { Text("The baseline keeps the working weights, precision, sampler and CPU motion compatibility policy. New speed or quality presets require device comparisons.").font(.caption).foregroundStyle(.secondary) }
        }.disabled(model.working).studioBackground().navigationTitle("Generation preferences").scrollDismissesKeyboard(.immediately)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
    }
}
struct StorageView: View {
    @EnvironmentObject private var model: AppModel
    private func size(_ value: Int64?) -> String { value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Not measured" }
    var body: some View {
        Form {
            Section("Current storage") {
                LabeledContent("Neodragon components", value: size(model.modelStorageBytes))
                LabeledContent("Private video library", value: size(model.libraryStorageBytes))
                Text("Export copies in Files are separate from the private library. Moving or deleting an export does not delete its original.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Legacy cleanup") {
                if let report = model.migrationReport {
                    LabeledContent("Migration", value: report.completed ? "Completed · version \(report.version)" : "Will resume")
                    LabeledContent("Retired file bytes removed", value: size(report.removedBytes)).accessibilityIdentifier("reclaimedStorage")
                    LabeledContent("Allocated bytes removed", value: size(report.removedAllocatedBytes))
                    LabeledContent("Items removed", value: String(report.entries.count))
                    if let before = report.freeBefore, let after = report.freeAfter {
                        LabeledContent("Available space before", value: size(before))
                        LabeledContent("Available space after", value: size(after))
                    }
                    if !report.skipped.isEmpty { Text("\(report.skipped.count) paths were left untouched because their ownership or location could not be verified.").font(.caption).foregroundStyle(.orange) }
                    Text("Measured from deleted files on this device. Filesystem sharing and other system activity can change available space independently. Your current model, videos, metadata and saved preferences are preserved.").font(.caption).foregroundStyle(.secondary)
                } else { Text("Cleanup has not completed. Reopen the app to retry safely.").foregroundStyle(.secondary) }
            }
            ExportFilesSection()
        }.studioBackground().navigationTitle("Storage").task { await model.refreshStorage() }
    }
}
struct OfflineInformationView: View {
    var body: some View {
        List {
            Section("After installation") {
                Label("Text-to-video generation", systemImage: "checkmark.circle")
                Label("Built-in and custom prompt styles", systemImage: "checkmark.circle")
                Label("Library, playback and export", systemImage: "checkmark.circle")
                Text("These features work without a connection after the model is installed. Downloads require Wi-Fi; no sign-in is required for generation.")
            }
            Section("Capabilities") {
                Text("Current native output is 512 × 320, landscape 16:10, at 24 FPS. The installed package supports selecting 2–9 seconds; complete two-second runs have been reported on the iPhone 17 Pro Max. Longer jobs need independent validation.")
                Text("Image-to-video, video extension, AI audio, trained style adapters and native alternative aspect ratios are not enabled in this build.")
            }
        }.studioBackground().navigationTitle("Offline functionality")
    }
}
