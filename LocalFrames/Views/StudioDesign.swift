import SwiftUI
import UIKit

enum StudioAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
}

enum StudioTheme {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 8 / 255, alpha: 1) : UIColor(white: 0.97, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 23 / 255, alpha: 1) : .white })
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.78, green: 0.87, blue: 0.94, alpha: 1) : UIColor(red: 0.20, green: 0.36, blue: 0.48, alpha: 1) })
    static let text = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1) : .label })
    static let spacing: CGFloat = 20
    static let radius: CGFloat = 24
    @MainActor static func feedback() {
        guard UserDefaults.standard.object(forKey: "studio.haptics") as? Bool != false else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// SDK and OS gates are both necessary. Xcode Cloud compiles the native branch;
/// the Intel Mac's older SDK validates only the iOS 18 material fallback.
private struct StudioGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("studio.reduceEffects") private var reduceEffects = false
    let radius: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || reduceEffects {
            content.background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(0.18)))
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: radius))
            } else { fallback(content) }
            #else
            fallback(content)
            #endif
        }
    }
    private func fallback(_ content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
    }
}

struct StudioGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 16) { content } }
        else { content }
        #else
        content
        #endif
    }
}

private struct StudioButton: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("studio.reduceEffects") private var reduceEffects = false
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency, !reduceEffects {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else { fallback(content) }
        #else
        fallback(content)
        #endif
    }
    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if prominent { content.buttonStyle(.borderedProminent) }
        else { content.buttonStyle(.bordered) }
    }
}

extension View {
    func studioGlass(radius: CGFloat = StudioTheme.radius) -> some View { modifier(StudioGlass(radius: radius)) }
    func studioButton(prominent: Bool = false) -> some View { modifier(StudioButton(prominent: prominent)) }
    func studioBackground() -> some View { scrollContentBackground(.hidden).background(StudioTheme.background) }
}

struct StudioSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: StudioTheme.radius))
    }
}

struct StudioStatus: View {
    let text: String
    var symbol = "iphone"
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

func dismissNativeKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
