import SwiftUI
import AppKit
import NakashaCore

/// A SwiftUI wrapper around `NSVisualEffectView` that gives the window real
/// depth on macOS 13 without reaching for `glassEffect` or any API introduced
/// after macOS 13 — the product's promise is that it runs on older Macs.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blending: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blending = blending
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

extension Color {
    /// Bridge a `CGColor` palette token into SwiftUI. Falls back to `.clear`
    /// so a missing token never crashes the interface — the advocate must
    /// always verify, and a transparent fallback is conspicuous.
    init(cg: CGColor) {
        self.init(nsColor: NSColor(cgColor: cg) ?? .clear)
    }
}

/// The single source of truth for interface colours and layout constants.
/// Spacing lives here so the window reads as designed rather than assembled.
enum Theme {
    /// Resolve palette tokens for a given SwiftUI colour scheme. Prefer this
    /// inside a view body; the convenience statics below are for call sites
    /// that cannot read `@Environment(\.colorScheme)`.
    static func tokens(_ scheme: ColorScheme) -> Palette.Tokens {
        Palette.tokens(dark: scheme == .dark)
    }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static var accent: Color {
        Color(cg: isDark ? Palette.dark.accent : Palette.light.accent)
    }

    static var accentSoft: Color {
        Color(cg: isDark ? Palette.dark.accentSoft : Palette.light.accentSoft)
    }

    static var muted: Color {
        Color(cg: isDark ? Palette.dark.muted : Palette.light.muted)
    }

    static var rule: Color {
        Color(cg: isDark ? Palette.dark.rule : Palette.light.rule)
    }

    static var ink: Color {
        Color(cg: isDark ? Palette.dark.ink : Palette.light.ink)
    }

    static let gutter: CGFloat = 16
    static let stack: CGFloat = 12
    static let radius: CGFloat = 10
    static let hairline: CGFloat = 1
}

/// A section container: a frosted card on a hairline-rectangle substrate.
/// The hairline is intentionally half-opacity so it reads as a quiet edge.
struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.rule.opacity(0.5), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small-caps section headings. They are what make a dense utility window
/// read as designed rather than assembled.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.muted)
    }
}

/// Rust filled, white label. The press dim is short — 120 ms — so the button
/// feels responsive without theatrics.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .foregroundStyle(.white)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Wrap a section in the standard frosted card.
    func card() -> some View {
        modifier(Card())
    }

    /// The vertical breath between grouped sections. Centralised so the
    /// rhythm of the window stays consistent as views are rearranged.
    func sectionSpacing() -> some View {
        padding(.bottom, Theme.stack)
    }
}

extension View {
    /// `scrollContentBackground` is macOS 13+, but `TextEditor` on 13.0 still
    /// paints its own backing. Wrapping the availability check here keeps the
    /// call sites clean and keeps the deployment target at 13.
    @ViewBuilder func scrollContentBackgroundHidden() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

/// Sizes and centres the window once, on the very first launch.
///
/// SwiftUI's `.defaultSize` is advisory, and here it was ignored outright: the
/// results pane declares an unbounded ideal height so it can fill the pane, and an
/// unbounded ideal makes the window open at the full size of the display. On a
/// 3024-point-wide screen that is a window covering the entire desktop before the
/// advocate has even loaded a board.
///
/// Reaching the window through `NSApp` rather than through a representable's own
/// `view.window` matters: at the moment a representable is made, it is not yet in a
/// window, so the obvious version of this silently does nothing.
///
/// Only the FIRST launch is touched. Afterwards macOS restores the size the user
/// chose, which is what they expect from every other application.
enum InitialWindow {
    private static let key = "NAKASHA.didSetInitialWindowSize"

    static func applyOnce(size: CGSize) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
                    ?? NSApp.windows.first else { return }
            window.setContentSize(size)
            window.center()
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}
