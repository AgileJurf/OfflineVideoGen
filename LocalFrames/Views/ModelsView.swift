import SwiftUI
import VideoEngine

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var download = false
    @State private var remove = false
    @State private var downloadAttention = false
    @State private var removeAttention = false
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Create entirely on your device.").font(.title2.weight(.semibold))
                StudioSection(title: "Neodragon", subtitle: "Qualcomm AI Research · Core ML on iPhone") {
                    HStack {
                        Image(systemName: "cpu").font(.largeTitle).foregroundStyle(StudioTheme.accent)
                        Spacer()
                        Label(model.installed ? "Installed" : "Not installed", systemImage: model.installed ? "checkmark.seal" : "arrow.down.circle").font(.subheadline)
                    }
                    Text("SSD-1B first-frame diffusion, Pyramid MMDiT video diffusion and an asymmetric causal video decoder.").font(.subheadline)
                    LabeledContent("Mode", value: "Text to Video")
                    LabeledContent("Native output", value: "512 × 320 · 24 FPS")
                    LabeledContent("Aspect ratio", value: "Landscape · 16:10")
                    LabeledContent("Precision", value: "Mixed FP16/FP32")
                    LabeledContent("Style method", value: "Local prompt conditioning")
                    if let manifest = model.manifest {
                        LabeledContent("Package", value: manifest.modelVersion).font(.caption)
                        LabeledContent("Weight revision", value: String(manifest.weightsRevision.prefix(12))).font(.caption.monospaced())
                        LabeledContent("Download", value: size(manifest.downloadBytes))
                        if let bytes = model.modelStorageBytes { LabeledContent("Installed + cached", value: size(bytes)) }
                        Text("Allow \(size(manifest.minimumFreeBytes)) free for installation. Downloads resume where supported and pass SHA-256 verification before use.").font(.caption).foregroundStyle(.secondary)
                        if model.installing && !model.installingAttentionTrial {
                            ProgressView(value: model.progress.fraction)
                            Text(model.progressMessage).font(.caption)
                            Button("Pause installation", action: model.cancel).studioButton()
                        } else if model.installed {
                            Button("Remove model", role: .destructive) { remove = true }.disabled(model.working || model.exportingFiles)
                        } else {
                            Button { download = true } label: { Label("Download model", systemImage: "arrow.down.circle").frame(maxWidth: .infinity, minHeight: 44) }
                                .studioButton(prominent: true).disabled(!model.ready || model.working || model.exportingFiles).accessibilityIdentifier("installModelButton")
                        }
                    } else { Text("The verified download manifest is unavailable in this build.").foregroundStyle(.orange) }
                }
                if let manifest = model.attentionManifest {
                    StudioSection(title: "Five-second memory trial", subtitle: "Optional attention update · original model preserved") {
                        Text("Evaluates motion attention in smaller groups with the same trained weights and sampling schedule. The five-second iPhone test is pending.").font(.subheadline)
                        LabeledContent("Additional download", value: size(manifest.downloadBytes))
                        Text("Reuses your existing encoders and decoder. Allow \(size(manifest.minimumFreeBytes)) free during installation. This update is a memory candidate; it does not claim to fix blur.").font(.caption).foregroundStyle(.secondary)
                        if model.installingAttentionTrial {
                            ProgressView(value: model.progress.fraction)
                            Text(model.progressMessage).font(.caption)
                            Button("Pause installation", action: model.cancel).studioButton()
                        } else if model.attentionTrialInstalled {
                            Toggle("Use attention trial", isOn: $model.useAttentionTrial).disabled(model.working || model.exportingFiles)
                                .accessibilityIdentifier("modelsAttentionTrialToggle")
                            Text("Turn off for the original model. Both versions work offline after installation.").font(.caption).foregroundStyle(.secondary)
                            NavigationLink("Run matched tests in Frame Lab") { DeviceBenchmarkToolsView() }
                            Button("Remove optional update", role: .destructive) { removeAttention = true }.disabled(model.working || model.exportingFiles)
                        } else {
                            Button("Download optional update", systemImage: "arrow.down.circle") { downloadAttention = true }
                                .studioButton().disabled(!model.ready || !model.installed || model.working || model.exportingFiles)
                                .accessibilityIdentifier("installAttentionTrialButton")
                            if !model.installed { Text("Install the core model first.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                StudioSection(title: "Capabilities & validation") {
                    Text("The working two-second path is preserved. Longer clips and each new prompt style still need device comparisons.")
                    Text("No trained style adapters are installed. There are no compatible, validated optional adapter downloads in this build.").font(.caption).foregroundStyle(.secondary)
                    NavigationLink("Supported and unavailable features") { OfflineInformationView() }
                    NavigationLink("Licenses and upstream model") { ModelLicensesView() }
                }
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }.padding(20)
        }.studioBackground().navigationTitle("Models")
            .confirmationDialog("Download Neodragon over Wi-Fi?", isPresented: $download, titleVisibility: .visible) {
                Button("Download model", action: model.install)
            } message: { if let manifest = model.manifest { Text("\(size(manifest.downloadBytes)) download. Allow \(size(manifest.minimumFreeBytes)) free during installation. Generation works offline after installation.") } }
            .confirmationDialog("Remove the installed model and its download cache?", isPresented: $remove, titleVisibility: .visible) {
                Button("Remove model", role: .destructive) { Task { await model.removeModel() } }
            } message: { Text("Your videos, styles and history remain. A new model download will be needed before generating again.") }
            .confirmationDialog("Download the optional attention update?", isPresented: $downloadAttention, titleVisibility: .visible) {
                Button("Download update", action: model.installAttentionTrial)
            } message: { if let manifest = model.attentionManifest { Text("\(size(manifest.downloadBytes)) over Wi-Fi. Your original model stays installed and selected. Enable the trial after installation when ready to compare.") } }
            .confirmationDialog("Remove only the attention update?", isPresented: $removeAttention, titleVisibility: .visible) {
                Button("Remove optional update", role: .destructive) { Task { await model.removeAttentionTrial() } }
            } message: { Text("The original model, all videos and benchmark files remain.") }
    }
}
struct ModelLicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Neodragon · Qualcomm AI Research").font(.title2.bold())
                Text("The model card lists BSD-3-Clause-Clear and the Qualcomm Responsible AI License. Converted components retain their upstream notices. This iOS port is independent of Qualcomm and uses Apple Core ML.")
                Link("Upstream model card and weights", destination: URL(string: "https://huggingface.co/Qualcomm-AI-Research/Neodragon")!)
                Link("Qualcomm Responsible AI License", destination: URL(string: "https://www.qualcomm.com/site/responsible-ai-license")!)
                Text(NeodragonModel.licenseNotices).font(.caption).textSelection(.enabled)
                if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"), let notices = try? String(contentsOf: url, encoding: .utf8) {
                    DisclosureGroup("Shared component notices") { Text(notices).font(.caption).textSelection(.enabled) }
                }
            }.padding(20)
        }.studioBackground().navigationTitle("Licenses")
    }
}
