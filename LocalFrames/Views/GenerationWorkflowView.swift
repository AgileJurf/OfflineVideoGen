import SwiftUI

struct GenerationFinishOptions: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var support: OnlineSupport
    @ObservedObject var account: HFAccountModel
    var body: some View {
        CreationSection("Frame rate & finish", icon: "sparkles.tv", detail: "Choose how this job completes") {
            Picker("Final frame rate", selection: $model.smoothAfterGeneration) {
                Text("12 FPS · offline").tag(false)
                Text("24 FPS · online finish").tag(true)
            }.pickerStyle(.segmented).disabled(model.working).accessibilityIdentifier("finalFrameRate")
            if model.smoothAfterGeneration {
                Text("One job, four stages").font(.subheadline.weight(.semibold))
                Label("Generate a 12 FPS original on your iPhone", systemImage: "1.circle")
                Label("Preview that clip and approve its upload", systemImage: "2.circle")
                Label("Free RIFE helper adds intermediate frames", systemImage: "3.circle")
                Label("Save a separate 24 FPS copy to Library", systemImage: "4.circle")
                Text("Your approval is required after generation. Only the chosen clip is uploaded; your prompt and other files stay here. Smoothing does not make the offline generation stage faster.")
                    .font(.caption).foregroundStyle(.secondary)
                if let issue = model.smoothingSelectionIssue {
                    Label(issue, systemImage: "info.circle").font(.caption).foregroundStyle(.orange).accessibilityIdentifier("smoothingSelectionIssue")
                }
                if support.enabled {
                    Divider()
                    HFQuotaPanel(account: account, support: support, canRefresh: !model.working)
                    NavigationLink("Helper account & quota details") { HelperAccountView(account: account, support: support) }
                        .font(.subheadline).disabled(model.working)
                }
            } else {
                Label("Entire job stays on your iPhone", systemImage: "iphone").font(.subheadline)
                Text("Native 12 FPS generation. No upload or Hugging Face quota is needed.").font(.caption).foregroundStyle(.secondary)
            }
        }.font(.subheadline)
    }
}

struct PendingSmoothingCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let video = model.pendingSmoothingVideo, !model.isGenerating {
            CreationSection("Finish your 24 FPS job", icon: "checkmark.circle", detail: "The 12 FPS original is saved safely") {
                Text(video.prompt).lineLimit(2).font(.subheadline)
                Text("Next: review this clip and approve its upload. Closing the review or restarting the app keeps this step available; it never uploads automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Review upload & continue") { model.workflowReview = video }
                    .buttonStyle(.borderedProminent).disabled(model.working).accessibilityIdentifier("continue24FPSJob")
                Button("Keep 12 FPS only") { model.keepOriginalWithoutSmoothing() }.disabled(model.working)
                    .accessibilityIdentifier("keep12FPSOriginal")
            }
        }
    }
}

struct WorkflowReviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let video: VideoRecord
    var body: some View {
        NavigationStack {
            SmoothingReviewView(video: video, support: model.support)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct SetupOnlineSummary: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var support: OnlineSupport
    @ObservedObject var account: HFAccountModel
    var body: some View {
        Toggle(isOn: $support.enabled) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Enable online support").font(.headline)
                Text("Optional 24 FPS smoothing, model checks and approved reports. Switching this on does not upload anything.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("setupOnlineSupportToggle")
        NavigationLink {
            OnlineSupportView(support: support)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Online support and model updates")
                Text(support.enabled ? "On · manage helper, quota and updates" : "Off · offline generation remains available")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(model.working).accessibilityIdentifier("openOnlineSupport")
        if support.enabled {
            HFQuotaPanel(account: account, support: support, canRefresh: !model.working)
        }
    }
}

struct HFQuotaPanel: View {
    @ObservedObject var account: HFAccountModel
    @ObservedObject var support: OnlineSupport
    var canRefresh = true
    private func time(_ seconds: Double) -> String { "\(Int(seconds) / 60)m \(Int(seconds) % 60)s" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hugging Face GPU allowance", systemImage: "gauge.with.dots.needle.50percent").font(.subheadline.weight(.semibold))
            if let quota = account.quota {
                LabeledContent("Remaining at last check", value: "\(time(quota.remaining)) / \(time(quota.total))")
                    .font(.subheadline).accessibilityIdentifier("helperQuotaRemaining")
                ProgressView(value: quota.remaining, total: quota.total).tint(quota.canSubmit ? .mint : .orange)
                if let reset = quota.resetsAt {
                    Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                } else { Text("Reset time not reported yet.").font(.caption) }
                Text("Checked \(quota.checkedAt.formatted(date: .abbreviated, time: .shortened)). Shared across your ZeroGPU Spaces; refresh for changes elsewhere.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(quota.canSubmit ? "Enough at the last check to request a job. Queue capacity is not guaranteed." : "Below the helper’s allowance requirement. Wait for a reset before uploading.")
                    .font(.caption).foregroundStyle(quota.canSubmit ? Color.secondary : Color.orange)
            } else {
                Text(account.name == nil ? "Connect a free account to see its balance. Anonymous access uses a shared pool with no reliable balance in this app." : "Refresh to read your remaining GPU time and reset date.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("This helper requires at least 90 GPU-seconds available to submit. That is not a price or a guaranteed per-clip usage. Local generation uses none of this allowance.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = account.quotaMessage { Text(message).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("helperQuotaMessage") }
            if account.quotaBusy { ProgressView("Refreshing allowance…") }
            Button("Refresh free quota") { account.refreshQuota(enabled: support.enabled) }
                .disabled(!support.enabled || account.name == nil || account.quotaBusy || account.busy || !canRefresh)
                .accessibilityIdentifier("refreshHelperQuota")
            if !support.enabled { Text("Online support is off. No quota requests are made.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
