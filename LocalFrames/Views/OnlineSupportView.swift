import SwiftUI
import VideoEngine

struct OnlineSupportView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var support: OnlineSupport
    @State private var sessions: [BenchmarkSummary] = []
    @State private var confirmRollback = false
    var body: some View {
        Form {
            Section("Optional connection") {
                Toggle("Enable online support", isOn: $support.enabled).accessibilityIdentifier("enableOnlineSupport")
                Text("Off by default. Choose update checks, diagnostic reports or a 24 FPS copy over Wi-Fi. Each video upload requires separate consent. Video generation stays on your iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(OnlineSupport.origin.absoluteString).font(.caption).textSelection(.enabled)
            }
            Section("24 FPS smoothing · beta") {
                Text("Create a smoother copy of a saved 2-second, 256 × 256, 12 FPS video using the free Hugging Face RIFE helper. Your original stays local. This is optional postprocessing, not faster diffusion.").font(.caption)
                NavigationLink("Helper account and free quota") { HelperAccountView(account: model.helperAccount, support: support) }
                    .disabled(!support.enabled || model.working).accessibilityIdentifier("helperAccountSettings")
                NavigationLink("Choose a clip for 24 FPS smoothing") { SmoothingLibraryView(support: support) }
                    .disabled(!support.enabled || model.working || support.busy).accessibilityIdentifier("chooseSmoothingClip")
                Text("Preview and approve every clip before upload. No automatic uploads, payments or retries. Connect a free Hugging Face account to use its included quota; anonymous access shares a smaller allowance. Other durations and crops are not yet supported.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Model updates") {
                LabeledContent("Configuration", value: support.catalogLabel).accessibilityIdentifier("supportCatalogSource")
                if let checked = support.snapshot?.checkedAt { LabeledContent("Last verified", value: checked.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Compatible model", value: "MOVD v1")
                LabeledContent("Download", value: "14.1 GB · 50 GB free to install")
                Text(model.installed ? "Your installed model remains available offline. No replacement weights are currently offered." : "Install the verified model from Setup. Checking this catalog never starts a model download.")
                    .font(.caption)
                Button("Check model updates") { Task { await support.refresh() } }
                    .disabled(!support.enabled || support.busy || model.working).accessibilityIdentifier("checkSupportUpdates")
                if support.busy { ProgressView(); Button("Cancel support request") { support.cancel() } }
                if let message = support.message { Text(message).font(.footnote).accessibilityIdentifier("supportMessage") }
                Text("A valid catalog is saved locally. If a check fails, the previous catalog and bundled defaults remain available. New model weights need app compatibility and your explicit download choice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Compatible inference settings") {
                LabeledContent("Profile", value: "Original baseline")
                LabeledContent("Reference test", value: "2 seconds · 256 × 256 · 12 FPS")
                LabeledContent("Diffusion evaluations", value: "21")
                Text("The catalog describes the approved local configuration. It cannot change your prompt, sampler, precision or existing generation settings. No faster or higher-quality replacement is being advertised.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.hasModelRollback {
                    Button("Restore previous model") { confirmRollback = true }.disabled(model.working)
                }
            }
            Section("Share a diagnostic report") {
                Text("Choose one local session, inspect its report, then explicitly consent to send it. Prompts, seeds, videos, files and raw error messages are excluded. Nothing is uploaded or queued automatically.")
                    .font(.caption)
                if sessions.isEmpty { Text("Run a baseline, install the model, or enable local Create diagnostics to record a session.").foregroundStyle(.secondary) }
                ForEach(sessions) { session in
                    NavigationLink {
                        DiagnosticReviewView(summary: session, support: support)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(session.kind.capitalized) · \(session.status)")
                            Text("Build \(session.appBuild) · \(session.elapsedSeconds, specifier: "%.1f") seconds").font(.caption)
                        }
                    }
                }
                Link("Support privacy and retention", destination: OnlineSupport.origin.appendingPathComponent("privacy.html"))
            }
        }.navigationTitle("Online support")
            .task {
                let directory = model.benchmarkDirectory
                sessions = (try? await Task.detached { try BenchmarkSummary.list(in: directory) }.value) ?? []
            }
            .confirmationDialog("Restore the previous verified model? The current model will be replaced; your videos remain unchanged.", isPresented: $confirmRollback, titleVisibility: .visible) {
                Button("Restore previous model") { Task { await model.restoreModelRollback() } }
            }
    }
}

struct HelperAccountView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var account: HFAccountModel
    @ObservedObject var support: OnlineSupport
    var body: some View {
        Form { Section("Free helper account · optional") {
            if let name = account.name {
                LabeledContent("Connected", value: name).accessibilityIdentifier("helperAccountConnected")
                Text("Free-account status and available GPU quota are verified before every approved upload. A connected account does not guarantee capacity.").font(.caption)
                Button("Disconnect Hugging Face") { model.closeSmoothingReview(); account.disconnect() }
                    .disabled(model.working || account.busy).accessibilityIdentifier("disconnectHelperAccount")
            } else {
                Text("Connect on Hugging Face’s own website. The permission covers your public profile, billing status and usage, and organization memberships. Local Frames reads only eligibility and GPU quota to verify free-only use. No repository, payment, paid-inference or account-management permissions are requested. Signing in never uploads a video.").font(.caption)
                Text("An expiring connection is stored in this device’s Keychain. Paid accounts, billing-enabled accounts and organization memberships are blocked in this beta. Tokens are sent only to Hugging Face and the selected helper, never to Vercel or diagnostics.").font(.caption)
                if let challenge = account.challenge {
                    LabeledContent("Enter this code", value: challenge.userCode).font(.body.monospaced()).textSelection(.enabled)
                        .accessibilityIdentifier("helperDeviceCode")
                    Link("Open Hugging Face to approve", destination: challenge.verificationURL)
                    Text("Expires \(challenge.expiresAt.formatted(date: .omitted, time: .shortened)). After approval, return here and tap Finish connecting.").font(.caption)
                    Button("Finish connecting") { account.finish() }.disabled(!support.enabled || account.busy || model.working)
                        .accessibilityIdentifier("finishHelperConnection")
                    Button("Cancel connection", role: .cancel) { account.cancel() }
                } else {
                    Button("Connect free Hugging Face account") { account.begin() }
                        .disabled(!support.enabled || account.busy || model.working).accessibilityIdentifier("connectHelperAccount")
                }
            }
            if account.busy { ProgressView("Checking helper connection") }
            if let message = account.message { Text(message).font(.footnote).accessibilityIdentifier("helperAccountMessage") }
        } }.navigationTitle("Helper account").navigationBarTitleDisplayMode(.inline)
            .task { await account.restore() }
            .onDisappear { account.cancel() }
    }
}

struct DiagnosticReviewView: View {
    @EnvironmentObject private var model: AppModel
    let summary: BenchmarkSummary
    @ObservedObject var support: OnlineSupport
    @State private var consent = false
    @State private var sent = false
    @State private var result: String?
    private var report: DiagnosticReport? { try? DiagnosticReport(summary: summary) }
    var body: some View {
        Form {
            if let report {
                Section("Report preview") {
                    LabeledContent("Session", value: report.kind + " · " + report.outcome)
                    LabeledContent("App / OS", value: report.appVersion + " (\(report.appBuild)) / " + report.osVersion)
                    LabeledContent("Model", value: report.modelVersion)
                    LabeledContent("Elapsed", value: String(format: "%.2f seconds", report.elapsedSeconds))
                    LabeledContent("Sampled peak memory", value: ByteCountFormatter.string(fromByteCount: Int64(report.peakSampledMemoryBytes), countStyle: .memory))
                    LabeledContent("Thermal state", value: report.thermalState)
                    LabeledContent("Error category", value: report.errorCategory)
                    LabeledContent("Model partitions", value: "\(report.partitions.count)")
                    DisclosureGroup("Exact report to send") {
                        Text((try? report.encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "Report unavailable")
                            .font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("diagnosticPayload")
                    }
                }
                Section("Your choice") {
                    Text("Destination: \(OnlineSupport.origin.host ?? "LocalFrames support"). Stored privately in your developer’s Vercel account with a 30-day expiration; daily cleanup can take up to about 32 days. Vercel also processes network metadata such as IP addresses.")
                        .font(.caption)
                    Text("No prompts, seeds, generated videos, personal files, device identifiers or raw journal attachments are sent. Sending is optional and does not affect offline generation.")
                        .font(.caption)
                    Toggle("I consent to send this report", isOn: $consent).disabled(support.busy || sent).accessibilityIdentifier("diagnosticConsent")
                    Button(sent ? "Report sent" : "Send this report") {
                        Task {
                            do { try await support.send(report, consent: consent); sent = true; consent = false; result = "This report was stored privately. No further reports will be sent automatically." }
                            catch is CancellationError { result = "The request stopped. It may already have reached support; nothing will be retried automatically." }
                            catch { result = (error as? SupportError)?.localizedDescription ?? SupportError.unavailable.localizedDescription }
                        }
                    }.disabled(!consent || sent || !support.enabled || support.busy || model.working).accessibilityIdentifier("sendDiagnosticReport")
                    if !support.enabled { Text("Enable online support in the previous screen to send a report.").font(.caption) }
                    if support.busy { ProgressView() }
                    if let result { Text(result).font(.footnote) }
                }
            } else { Text("This earlier session does not contain a compatible model identifier. Its raw files stay local; record a new session to share a structured report.") }
        }.navigationTitle("Review diagnostic report")
    }
}
