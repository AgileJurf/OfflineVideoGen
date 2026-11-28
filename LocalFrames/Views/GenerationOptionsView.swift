import SwiftUI
import VideoEngine

struct GenerationSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var seedFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("Generation") {
                    LabeledContent("Engine", value: "Neodragon · Qualcomm AI Research")
                    LabeledContent("Output", value: "512 × 320 · 24 FPS")
                    LabeledContent("Framing", value: "Native landscape · 16:10")
                    LabeledContent("Preset", value: model.inferenceProfileName)
                    Text("Fast, Balanced and Cinema configurations are awaiting matched device measurements. This build preserves the working sampling schedule.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Detail conditioning · comparison") {
                    Toggle("Use upstream detail prompt", isOn: $model.useUpstreamDetailPrompt).accessibilityIdentifier("upstreamDetailToggle")
                    Text("Adds Neodragon’s reference instructions for cinematic detail, textures and natural colors to both image and motion generation. This is prompt conditioning, with quality still to be compared on your device. It may influence your selected style.").font(.caption).foregroundStyle(.secondary)
                }
                if model.attentionTrialInstalled {
                    Section("Memory comparison") {
                        Toggle("Use lower-memory attention trial", isOn: $model.useAttentionTrial).accessibilityIdentifier("attentionTrialToggle")
                        Text("Uses an optional conversion of the same weights for up to five seconds. Turn off to return to the original model. Device validation is pending.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Reproducibility") {
                    Toggle("Use a fixed seed", isOn: $model.useFixedSeed).accessibilityIdentifier("fixedSeedToggle")
                    if model.useFixedSeed {
                        TextField("Seed", text: $model.generationSeed).keyboardType(.numberPad).focused($seedFocused).accessibilityIdentifier("generationSeed")
                    }
                    Text("Use the same scene, style, duration and seed to compare outputs. Seeds are repeatable within this engine, not equivalent across different models.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Effective model input") {
                    Text(model.effectivePrompt.isEmpty ? "Enter a scene in Create." : model.effectivePrompt).font(.callout).textSelection(.enabled)
                    Text("Styles add local prompt instructions. No style adapter, remote assistant or postprocessing filter is used.").font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(model.working).studioBackground().navigationTitle("Generation settings").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.immediately)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismissNativeKeyboard(); dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { seedFocused = false; dismissNativeKeyboard() }.accessibilityIdentifier("dismissKeyboard") }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct PromptEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe your scene").font(.title2.bold())
                TextEditor(text: $model.prompt).focused($focused).scrollContentBackground(.hidden)
                    .padding(12).studioGlass().accessibilityIdentifier("expandedPromptInput").disabled(model.working)
                Text("\(model.prompt.count)/500 characters · Your full scene and style must fit the model’s encoders.")
                    .font(.caption).foregroundStyle(model.prompt.count > 500 ? .orange : .secondary)
            }.padding(20).background(StudioTheme.background)
                .navigationTitle("Prompt").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { focused = false; dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard") { focused = false } }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct StyleCard: View {
    let style: StyleConditioning
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                StyleThumbnail(style: style).frame(height: 78).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        if selected { Image(systemName: "checkmark").font(.caption.bold()).padding(8).studioGlass(radius: 20).padding(6) }
                    }
                Text(style.name).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
            }.frame(width: 142, alignment: .leading).padding(8)
                .background(selected ? StudioTheme.accent.opacity(0.12) : StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? StudioTheme.accent : .clear, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(style.name + ", prompt-based style")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("style-" + style.id)
    }
}

/// Bundled vector illustrations; explicitly identified as illustrations, not model samples.
struct StyleThumbnail: View {
    let style: StyleConditioning
    private var palette: [Color] {
        if ["blackAndWhite", "filmNoir", "manga", "pencilSketch", "inkIllustration"].contains(style.id) { return [.init(white: 0.2), .init(white: 0.55), .init(white: 0.9)] }
        switch style.category {
        case .realistic: return [.init(red: 0.29, green: 0.40, blue: 0.43), .init(red: 0.55, green: 0.63, blue: 0.57), .init(red: 0.91, green: 0.81, blue: 0.62)]
        case .animation: return [.init(red: 0.35, green: 0.38, blue: 0.61), .init(red: 0.77, green: 0.62, blue: 0.71), .init(red: 0.91, green: 0.84, blue: 0.65)]
        case .artistic: return [.init(red: 0.73, green: 0.72, blue: 0.65), .init(red: 0.46, green: 0.58, blue: 0.58), .init(red: 0.9, green: 0.85, blue: 0.74)]
        case .genre: return [.init(red: 0.12, green: 0.22, blue: 0.31), .init(red: 0.34, green: 0.46, blue: 0.5), .init(red: 0.72, green: 0.62, blue: 0.48)]
        case .environment: return [.init(red: 0.2, green: 0.36, blue: 0.4), .init(red: 0.48, green: 0.61, blue: 0.49), .init(red: 0.82, green: 0.86, blue: 0.68)]
        }
    }
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette[0]))
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.72, y: 12, width: 20, height: 20)), with: .color(palette[2]))
            var mountain = Path(); mountain.move(to: CGPoint(x: 0, y: size.height))
            mountain.addLine(to: CGPoint(x: size.width * 0.38, y: 24)); mountain.addLine(to: CGPoint(x: size.width, y: size.height)); mountain.closeSubpath()
            context.fill(mountain, with: .color(palette[1]))
            if style.category == .animation || style.id == "inkIllustration" { context.stroke(mountain, with: .color(palette[2]), lineWidth: 2) }
            if style.id == "pixelArt" {
                for n in 0..<12 { context.fill(Path(CGRect(x: n * 14, y: 60 - (n % 3) * 6, width: 12, height: 12)), with: .color(palette[2])) }
            }
        }.accessibilityHidden(true)
    }
}

struct StyleBrowser: View {
    @ObservedObject var store: StyleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var scope = "All"
    @State private var category: StyleCategory?
    @State private var editing: StyleConditioning?
    @State private var deleting: StyleConditioning?
    private var filtered: [StyleConditioning] {
        let source = scope == "Recent" ? store.recent : (scope == "Custom" ? store.custom : store.all)
        return source.filter { item in
            (scope != "Favorites" || store.isFavorite(item)) && (category == nil || category == item.category)
                && (search.isEmpty || (item.name + " " + item.instructions).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Style collection", selection: $scope) { ForEach(["All", "Favorites", "Recent", "Custom"], id: \.self) { Text($0) } }
                        .pickerStyle(.segmented).accessibilityIdentifier("styleCollection")
                    HStack {
                        Picker("Category", selection: $category) {
                            Text("All categories").tag(nil as StyleCategory?)
                            ForEach(StyleCategory.allCases) { Text($0.title).tag(Optional($0)) }
                        }.pickerStyle(.menu).accessibilityIdentifier("styleCategory")
                        Spacer()
                        Button("Reset") { store.select(StyleCatalog.definition(.default)); StudioTheme.feedback() }.frame(minHeight: 44)
                    }
                    Text("Illustrative thumbnails · prompt-based styles. These are not generated previews or trained adapters. Style consistency requires device comparisons.")
                        .font(.caption).foregroundStyle(.secondary)
                    if filtered.isEmpty { ContentUnavailableView("No matching styles", systemImage: "paintpalette", description: Text("Try another category or create a custom style.")) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 150), spacing: 14)], spacing: 16) {
                        ForEach(filtered) { style in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { store.select(style); StudioTheme.feedback(); dismiss() } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        StyleThumbnail(style: style).frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 16))
                                            .overlay(alignment: .topTrailing) {
                                                if store.selected.id == style.id { Image(systemName: "checkmark").padding(8).studioGlass(radius: 18).padding(6) }
                                            }
                                        Text(style.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(style.aesthetic.isEmpty ? "Your original scene." : style.aesthetic).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain).accessibilityIdentifier("browse-style-" + style.id)
                                HStack {
                                    Button { store.toggleFavorite(style) } label: { Image(systemName: store.isFavorite(style) ? "star.fill" : "star").frame(minWidth: 44, minHeight: 44) }
                                        .accessibilityLabel((store.isFavorite(style) ? "Unfavorite " : "Favorite ") + style.name)
                                    Spacer()
                                    Menu {
                                        Button("Duplicate", systemImage: "plus.square.on.square") { var copy = style; copy.id = "custom-" + UUID().uuidString; copy.isCustom = true; copy.name = String(style.name.prefix(50)) + " copy"; editing = copy }
                                        if style.isCustom {
                                            Button("Edit or rename", systemImage: "pencil") { editing = style }
                                            Button("Delete custom style", systemImage: "trash", role: .destructive) { deleting = style }
                                        }
                                    } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Actions for " + style.name)
                                }
                            }.padding(12).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                }.padding(20)
            }.studioBackground().navigationTitle("Visual styles").searchable(text: $search, prompt: "Search aesthetics, light, color…")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("New style", systemImage: "plus") { editing = .init(id: "custom-" + UUID().uuidString, name: "", isCustom: true) }.accessibilityIdentifier("newCustomStyle") }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(item: $editing) { CustomStyleEditor(store: store, draft: $0) }
                .confirmationDialog("Delete this custom style? Saved videos retain their style metadata.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete style", role: .destructive) { if let deleting { store.remove(deleting) }; deleting = nil }
                }
                .alert("Style storage", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        }.presentationDragIndicator(.visible)
    }
}

struct CustomStyleEditor: View {
    @ObservedObject var store: StyleStore
    @State var draft: StyleConditioning
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Your style") {
                    TextField("Style name", text: $draft.name).accessibilityIdentifier("customStyleName")
                    TextField("Aesthetic, texture and artistic medium", text: $draft.aesthetic, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("customStyleDescription")
                    Picker("Category", selection: $draft.category) { ForEach(StyleCategory.allCases) { Text($0.title).tag($0) } }
                }
                Section("Optional direction") {
                    TextField("Color palette", text: $draft.palette, axis: .vertical)
                    TextField("Lighting", text: $draft.lighting, axis: .vertical)
                    TextField("Camera and composition", text: $draft.camera, axis: .vertical)
                    TextField("Motion", text: $draft.motion, axis: .vertical)
                }
                Section {
                    Text("Stored only on your device. Keep instructions concise: they share the model’s token budget with your scene. Reference images and independent style strength are not supported by this model path.").font(.caption).foregroundStyle(.secondary)
                    if let failure { Text(failure).foregroundStyle(.orange) }
                }
            }.studioBackground().navigationTitle("Custom style").scrollDismissesKeyboard(.immediately)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { do { try store.upsert(draft); store.select(draft); dismiss() } catch { failure = error.localizedDescription } }.accessibilityIdentifier("saveCustomStyle") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hide keyboard", action: dismissNativeKeyboard) }
                }
        }
    }
}
