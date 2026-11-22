import SwiftUI
import VideoEngine

struct GenerationOptionsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var tokenCount: Int?
    var focusedField: FocusState<CreationField?>.Binding
    @State private var tokenError: String?
    private var promptKey: String { model.visualStyle.rawValue + "\n" + model.prompt }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CreationSection("Visual style", icon: "paintpalette", detail: "Prompt styling for your scene") {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(VisualStyle.allCases) { style in
                            StyleSelectionCard(style: style, selected: model.visualStyle == style) {
                                model.visualStyle = style
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
                Text(model.visualStyle.detail).font(.subheadline)
                HStack {
                    Text(tokenCount.map { "\($0)/63 model tokens · scene + style" } ?? "Checking prompt tokens…")
                        .foregroundStyle((tokenCount ?? 0) > 63 ? .orange : .secondary)
                        .accessibilityIdentifier("promptTokenBudget")
                }.font(.caption)
                if (tokenCount ?? 0) > 63 {
                    Text("Shorten your scene or choose Default. Your prompt will not be truncated.").font(.caption).foregroundStyle(.orange)
                }
                if let tokenError { Text(tokenError).font(.caption).foregroundStyle(.orange) }
                DisclosureGroup("Text sent to the model") {
                    Text(model.visualStyle.applying(to: model.prompt)).font(.caption).textSelection(.enabled).padding(.top, 4)
                    Text("Illustrated swatches, not example results. These styles use prompt instructions, not trained adapters.").font(.caption).foregroundStyle(.secondary)
                }.font(.caption)
            }
            CreationSection("Video settings", icon: "film", detail: "Length and framing of your saved video") {
                Picker("Duration", selection: $model.duration) {
                    ForEach(2...5, id: \.self) { Text("\($0) sec").tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("durationPicker")
                Text("Output framing").font(.subheadline.weight(.medium))
                Picker("Output framing", selection: $model.outputFraming) {
                    Text("Square").tag(OutputFraming.square)
                    Text("Portrait crop").tag(OutputFraming.portrait)
                    Text("Landscape crop").tag(OutputFraming.landscape)
                }.pickerStyle(.segmented).accessibilityIdentifier("outputFramingPicker")
                HStack(spacing: 14) {
                    FramingDiagram(framing: model.outputFraming).frame(width: 66, height: 66)
                    Text(model.outputFraming.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            CreationSection("Repeatable settings", icon: "slider.horizontal.3", detail: "Use the same seed to compare results") {
                LabeledContent("Generation preset", value: "Baseline · 21 evaluations").font(.subheadline)
                Toggle(isOn: $model.useFixedSeed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use a fixed seed")
                        Text("Off chooses a new seed for each video.").font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("fixedSeedToggle")
                if model.useFixedSeed {
                    TextField("Seed", text: $model.generationSeed).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        .focused(focusedField, equals: .seed)
                        .accessibilityIdentifier("generationSeed")
                    Text("Repeat the same prompt, style and seed to compare settings.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Faster presets are awaiting device measurements.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.working)
        .task(id: promptKey) {
            tokenCount = nil; tokenError = nil
            guard model.prompt.count <= 500 else {
                tokenError = "Use a scene of up to 500 characters. Your text has not been shortened."
                return
            }
            let text = model.visualStyle.applying(to: model.prompt)
            do {
                try await Task.sleep(for: .milliseconds(250))
                let count = try await Task.detached(priority: .userInitiated) { try MOVDEngine.promptTokenCount(text) }.value
                try Task.checkCancellation()
                tokenCount = count
            } catch is CancellationError { }
            catch { tokenError = "Prompt tokens could not be checked: " + error.localizedDescription }
        }
    }
}

private struct StyleSelectionCard: View {
    let style: VisualStyle
    let selected: Bool
    let action: () -> Void
    private var backgroundColor: Color { selected ? Color.mint.opacity(0.14) : Color.white.opacity(0.04) }
    private var borderColor: Color { selected ? Color.mint : Color.clear }
    private var traits: AccessibilityTraits { selected ? .isSelected : [] }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                StyleSwatch(style: style).frame(width: 126, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text(style.name).font(.caption.weight(.semibold))
                    Spacer(minLength: 2)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint) }
                }
            }.padding(9).frame(width: 144)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
        }.buttonStyle(.plain)
            .accessibilityLabel(style.name + ". " + style.detail)
            .accessibilityAddTraits(traits)
            .accessibilityIdentifier("style-" + style.rawValue)
    }
}

private struct FramingDiagram: View {
    let framing: OutputFraming
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.07))
            Rectangle().fill(.mint.opacity(0.2)).overlay(Rectangle().stroke(.mint, lineWidth: 2))
                .frame(width: 62 * CGFloat(framing.width) / 256, height: 62 * CGFloat(framing.height) / 256)
        }.accessibilityLabel(framing.name + (framing.isCrop ? ", center crop of square" : ", native"))
    }
}

/// Hand-drawn interface illustrations, not generated-model examples or quality claims.
private struct StyleSwatch: View {
    let style: VisualStyle
    private var colors: [Color] {
        switch style {
        case .default: return [.init(red: 0.10, green: 0.24, blue: 0.28), .mint, .teal]
        case .photorealistic: return [.init(red: 0.52, green: 0.75, blue: 0.89), .init(red: 0.27, green: 0.46, blue: 0.36), .init(red: 0.12, green: 0.3, blue: 0.24)]
        case .cinematic: return [.init(red: 0.07, green: 0.16, blue: 0.22), .orange, .init(red: 0.1, green: 0.32, blue: 0.36)]
        case .anime: return [.cyan, .pink, .indigo]
        case .cartoon: return [.blue, .yellow, .green]
        case .animation3D: return [.indigo, .purple, .cyan]
        case .pixelArt: return [.init(red: 0.12, green: 0.1, blue: 0.28), .pink, .purple]
        case .watercolor: return [.init(red: 0.9, green: 0.87, blue: 0.76), .init(red: 0.6, green: 0.76, blue: 0.76), .init(red: 0.4, green: 0.6, blue: 0.5)]
        case .claymation: return [.init(red: 0.68, green: 0.45, blue: 0.31), .orange, .init(red: 0.4, green: 0.5, blue: 0.32)]
        case .blackAndWhite: return [.gray, .white, .black]
        case .vintageFilm: return [.init(red: 0.66, green: 0.55, blue: 0.39), .init(red: 0.9, green: 0.74, blue: 0.49), .init(red: 0.35, green: 0.4, blue: 0.3)]
        case .fantasy: return [.init(red: 0.12, green: 0.06, blue: 0.29), .purple, .mint]
        }
    }
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colors[0]))
            let sun = CGRect(x: size.width * 0.7, y: size.height * 0.15, width: 15, height: 15)
            context.fill(style == .pixelArt ? Path(sun) : Path(ellipseIn: sun), with: .color(colors[1]))
            for (index, peak) in [0.32, 0.65].enumerated() {
                var path = Path()
                path.move(to: CGPoint(x: -10 + index * 35, y: Int(size.height)))
                path.addLine(to: CGPoint(x: size.width * peak, y: size.height * (index == 0 ? 0.3 : 0.48)))
                path.addLine(to: CGPoint(x: size.width + 10, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(colors[index + 1].opacity(style == .watercolor ? 0.65 : 1)))
                if style == .anime || style == .cartoon { context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 2) }
            }
            if style == .pixelArt || style == .vintageFilm || style == .claymation {
                for i in 0..<42 {
                    let x = CGFloat((i * 37) % 126), y = CGFloat((i * 17) % 72)
                    context.fill(Path(CGRect(x: x, y: y, width: style == .pixelArt ? 4 : 1, height: 2)), with: .color(.white.opacity(0.22)))
                }
            }
            if style == .cinematic {
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 7)), with: .color(.black))
                context.fill(Path(CGRect(x: 0, y: size.height - 7, width: size.width, height: 7)), with: .color(.black))
            }
        }.accessibilityHidden(true)
    }
}

struct ModelCapabilitiesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Section("Current model") {
                LabeledContent("MOVD text to video", value: model.installed ? "Installed" : "Not installed")
                LabeledContent("Revision", value: String(MOVDModel.revision.prefix(8)))
                LabeledContent("Download", value: "14.1 GB · SHA-256 verified")
                Text("T5, STDiT-v3 and the video decoder are shared by all prompt styles. Selecting a style does not download another model.").font(.caption)
                Text("Native output: square, 256 × 256, 12 FPS, 2–5 seconds. Longer durations still require separate device validation.").font(.caption)
            }
            Section("Additional generation modes") {
                ForEach([GenerationMode.imageToVideo, .extendVideo]) { mode in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(mode.name + " · unavailable", systemImage: "lock")
                        Text(mode.unavailableReason ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("No compatible, device-validated optional model package is available in this build. Additional model downloads will require your confirmation when a verified package is available.").font(.caption)
            }
            Section("Framing and style") {
                Text("Portrait and landscape are explicitly labeled center crops of square output. Native non-square inference is not enabled.")
                Text("All 12 visual styles use text conditioning. Style quality is awaiting on-device comparison; no LoRA or trained style adapter is installed.")
            }
            Section("Offline and rollback") {
                Text("Generation, styling, crop exports, comparison and the local library do not require a server after the MOVD model is installed.")
                Text("Original weights, the baseline sampler, thermal pauses and saved-baseline recovery are preserved. Cropping always creates a separate library item.")
            }
        }.navigationTitle("Model capabilities")
    }
}
