import SwiftUI

/// The About screen. Read it once: it states in plain language what the app does
/// and does not do. Because the wording is load-bearing, point 5 about
/// over-inclusive matching is deliberately left in this author's voice.
struct AboutView: View {

    private let maxWidth: CGFloat = 520

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleBlock

                Group {
                    paragraph("1.", text: point1)
                    paragraph("2.", text: point2)
                    paragraph("3.", text: point3)
                    paragraph("4.", text: point4)
                    paragraph("5.", text: point5)
                }

                Divider().padding(.vertical, 6)

                footer
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .textSelection(.enabled)
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NAKASHA — High Court Board Parser")
                .font(.system(size: 22, weight: .semibold))
            Text("\"nakasha\" means the sanctioned plan.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Apache License 2.0.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Rushikesh R. Mahajan (publishing as wolfgang_rush)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func paragraph(_ index: String, text: String) -> some View {
        H(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // The wording of each point is part of the product. Do not paraphrase.
    private let point1 = """
This application accesses nothing and sends nothing. It has no network permission at \
all. You can verify this yourself: run

`codesign -d --entitlements - /Applications/NAKASHA.app`

and you will see no network entitlement listed.
"""

    private let point2 = """
Nothing you open leaves your Mac, and the publisher never receives anything — not your \
board, not your names, not a count of how often you opened this. There is no server for it \
to reach. The board PDF is never copied. Your watched names are stored only in this Mac's \
local preferences. There is no account, no sign-in, no sync, no telemetry, no analytics and \
no crash reporting.
"""

    // A statement of FACT, not a conclusion of law. An assertion that the app "complies
    // with" professional-conduct rules is a legal opinion about the publisher's own conduct,
    // published in his own name — if it were ever questioned he would be defending the
    // conclusion rather than the facts. The facts below are checkable and say more.
    private let point3 = """
NAKASHA does not advertise and carries no advertising. It does not solicit work, for anyone. \
It names no advocate, chambers or firm anywhere in the application. It publishes, transmits \
and shares nothing — no advocate's details and no litigant's. It communicates with no one. It \
is given away free and its source is published, so each of those can be checked rather than \
believed.
"""

    private let point4 = """
It is a tool. The advocate remains responsible for verifying every listing against the \
board itself before acting on it. NAKASHA narrows the field; it does not replace the \
reading.
"""

    private let point5 = """
Name matching is deliberately over-inclusive. You will see matters that are not yours, \
because the board truncates and wraps advocate names, and missing one of your matters \
would be far worse than showing you one extra. Delete the rows that are not yours.
"""
}

// SwiftUI's HStack cannot host a .top alignment with `alignment:` on plain `H`; we
// wrap a small helper that does exactly what we need without pulling in VStack
// nesting tricks.
private struct H<Content: View>: View {
    let alignment: VerticalAlignment
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    init(alignment: VerticalAlignment = .center,
         spacing: CGFloat = 0,
         @ViewBuilder content: @escaping () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }
    var body: some View {
        HStack(alignment: alignment, spacing: spacing, content: content)
    }
}
