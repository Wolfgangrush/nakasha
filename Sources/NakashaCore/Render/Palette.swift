import Foundation
import CoreGraphics

/// NAKASHA's own design tokens. These colours are original to this app and are not
/// derived from any third party's brand palette. They are chosen so a single set
/// stays legible in both light and dark appearance, which matters because the same
/// tokens drive the on-screen table and the exported PDF.
public enum Palette {

    /// CGColor-backed colour tokens. CGColor is used (not SwiftUI.Color) because the
    /// CoreGraphics PDF renderer needs CGColor directly; the SwiftUI views derive
    /// Colors from these on demand.
    public struct Tokens: Sendable {
        public let accent: CGColor
        public let accentSoft: CGColor
        public let muted: CGColor
        public let rule: CGColor
        public let ink: CGColor
        public let paper: CGColor
    }

    /// Tokens for the light appearance. The rust accent (#9C4A2F) is used for
    /// column headers and hairlines so the eye finds structure first.
    public static let light: Tokens = tokens(dark: false)

    /// Tokens for the dark appearance. The accent lifts in luminance so it still
    /// reads against a near-black paper without becoming neon.
    public static let dark: Tokens = tokens(dark: true)

    /// Resolve tokens for the given appearance. Centralised so a future "high
    /// contrast" or accessibility variant only needs another branch here.
    public static func tokens(dark: Bool) -> Tokens {
        if dark {
            return Tokens(
                accent: cg(0xC9_71_4E),
                accentSoft: cg(0x3A_28_22),
                muted: cg(0xA7_9E_96),
                rule: cg(0x4A_40_3A),
                ink: cg(0xED_E8_E3),
                paper: cg(0x17_15_13)
            )
        } else {
            return Tokens(
                accent: cg(0x9C_4A_2F),
                accentSoft: cg(0xF3_E6_DF),
                muted: cg(0x6E_68_62),
                rule: cg(0xD6_CC_C3),
                ink: cg(0x1C_1A_18),
                paper: cg(0xFF_FF_FF)
            )
        }
    }

    // MARK: - Private helpers

    /// Build an sRGB CGColor from a 6-digit hex literal (e.g. 0x9C4A2F).
    /// Keeping values as hex in source makes intent obvious during palette review.
    private static func cg(_ hex: UInt32) -> CGColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
