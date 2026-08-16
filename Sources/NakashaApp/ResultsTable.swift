import SwiftUI
import AppKit
import NakashaCore

/// One candidate row in the results table. `keep` survives across re-renders
/// and is what the export pipeline reads, so mutating it must go through a binding.
struct ResultRow: Identifiable, Equatable {
    let id: String
    var row: BoardRow
    var keep: Bool
}

/// The verification surface for a daily board: the advocate scans, prunes, and
/// clicks through to the PDF. Layout is hand-built because conditional and
/// editable SwiftUI `Table` columns require macOS 14, and NAKASHA promises to
/// run on macOS 13 machines still common among High Court advocates.
struct ResultsTable: View {
    @Binding var rows: [ResultRow]
    /// Point size selected in Settings; clamped at usage sites to 9...20.
    var textSize: Double
    /// Tapping a row surfaces that matter in the PDF for visual confirmation
    /// against the printed board, which is the only ground truth for names.
    var onReveal: (BoardRow) -> Void

    // Column fractions of the table's available width (after the fixed
    // checkbox and delete columns). Order is fixed by product decision and
    // mirrors the way the board is read: court, position, number, parties,
    // note, counsel.
    private let fractions: [CGFloat] = [0.14, 0.05, 0.13, 0.24, 0.23, 0.21]
    // Wide enough for their HEADER LABELS, not just their glyphs. A 30pt column
    // clips the word "Remove" to "Rem…", which defeats the point of labelling it.
    private let checkboxWidth: CGFloat = 42
    private let deleteWidth: CGFloat = 54
    private let rowSpacing: CGFloat = 0

    var body: some View {
        // Empty state must skip the header entirely: a header above an empty
        // list reads as "data missing" rather than "nothing matched".
        if rows.isEmpty {
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                Text("No matters to show.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
            }
        } else {
            GeometryReader { proxy in
                let widths = computedWidths(total: proxy.size.width)
                VStack(spacing: 0) {
                    headerRow(widths: widths)
                    ScrollView {
                        LazyVStack(spacing: rowSpacing) {
                            ForEach(rows.indices, id: \.self) { idx in
                                rowView(idx: idx, widths: widths)
                                    .background(rowBackground(idx: idx))
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Column geometry

    /// Distributes the available width across the six data columns after
    /// reserving space for the leading checkbox and trailing delete button.
    private func computedWidths(total: CGFloat) -> [CGFloat] {
        let dataWidth = max(0, total - checkboxWidth - deleteWidth)
        return fractions.map { dataWidth * $0 }
    }

    // MARK: - Header

    private func headerRow(widths: [CGFloat]) -> some View {
        let titles = ["Court", "Sr.", "Case No.", "Party", "Office note", "Counsel"]
        return HStack(spacing: 0) {
            // Both control columns are LABELLED. Leaving them blank was a mistake:
            // a bare checkbox and a bare glyph give the advocate no way to know that
            // one governs the export and the other removes the matter.
            //
            // The HEIGHT here is not cosmetic: `Color` has no intrinsic size, so a
            // bare `Color.clear.frame(width:)` inside a GeometryReader expands to
            // fill every available point of height and turns the header into a slab
            // covering a third of the pane.
            Text("Keep")
                .font(.system(size: max(9, textSize - 2), weight: .semibold))
                .frame(width: checkboxWidth, height: 14)
            ForEach(Array(zip(titles, widths)), id: \.0) { title, w in
                Text(title)
                    .font(.system(size: max(10, textSize - 1), weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .frame(width: w, alignment: .topLeading)
            }
            Text("Remove")
                .font(.system(size: max(9, textSize - 2), weight: .semibold))
                .frame(width: deleteWidth, height: 14)
        }
        .fixedSize(horizontal: false, vertical: true)   // hug the labels, nothing more
        .padding(.vertical, 7)
        .background(Theme.accentSoft)
        .overlay(alignment: .bottom) {
            // 1pt divider so the header reads as a band even before the first row.
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.rule)
        }
    }

    // MARK: - Rows

    private func rowBackground(idx: Int) -> some View {
        // Faint zebra striping so the eye can track a row horizontally across
        // six columns without losing place. Bound to odd index only.
        Theme.accent.opacity(idx.isMultiple(of: 2) ? 0.0 : 0.035)
    }

    private func rowView(idx: Int, widths: [CGFloat]) -> some View {
        // Pull the binding once so the closure captures a stable reference;
        // rebinding $rows[idx] inside the body is fine but reads poorly.
        let element = rows[idx]
        let keepBinding = Binding<Bool>(
            get: { self.rows[idx].keep },
            set: { self.rows[idx].keep = $0 }
        )
        let deleteAction: () -> Void = {
            guard self.rows.indices.contains(idx) else { return }
            self.rows.remove(at: idx)
        }

        return HStack(spacing: 0) {
            // KEEP checkbox — read by the export pipeline. Individual rows
            // must be toggleable without rebuilding the whole list.
            Toggle("", isOn: keepBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: checkboxWidth, alignment: .center)
                .help(element.keep ? "Exported as your matter" : "Excluded from export")

            // Six data cells, in fixed product-decided order.
            //
            // The click-through lives on THESE, not on the whole row. With the
            // gesture on the row, the keep checkbox and the delete button sat inside
            // the tap target and competed with it.
            HStack(spacing: 0) {
                cell(text: element.row.court, width: widths[0])
                cell(text: element.row.serial, width: widths[1])
                cell(text: element.row.numberColumn, width: widths[2], monospaced: true)
                // Party cell carries the verify badge when the match landed
                // outside the counsel column; dropping such a row could hide a
                // real listing, so it stays in view and is flagged for inspection.
                partyCell(row: element.row, width: widths[3], keep: element.keep)
                cell(text: element.row.officeNote, width: widths[4], secondary: true)
                cell(text: element.row.counsels, width: widths[5])
            }
            .contentShape(Rectangle())
            .onTapGesture { onReveal(element.row) }

            // DELETE. Deliberately NOT quiet: this is the control the whole
            // prune-what-is-not-yours workflow depends on, and a grey glyph that
            // only appears on hover is a control the advocate cannot find.
            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .imageScale(.medium)
                    .foregroundStyle(Color.red.opacity(0.85))
            }
            .buttonStyle(.borderless)
            .frame(width: deleteWidth, alignment: .center)
            .help("Remove this matter from the list")
        }
        .help("Click the row to show this matter in the PDF")
        .onHover { hovering in
            // Hover highlight must not rely on system accent colour alone —
            // advocates using grayscale printing need to see the hit area.
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .background(
            // Light hover wash so the click target is visible without
            // competing with the row's zebra background.
            Color.accentColor.opacity(0.06)
        )
        // Pruned rows stay visible at reduced opacity with the Party struck
        // through: the advocate is still finishing their scan, and a row
        // that disappears mid-pass looks like a bug rather than intent.
        .opacity(element.keep ? 1.0 : 0.45)
        .padding(.vertical, 4)
    }

    // MARK: - Cells

    private func cell(text: String,
                      width: CGFloat,
                      monospaced: Bool = false,
                      secondary: Bool = false) -> some View {
        Text(text)
            .font(.system(size: textSize, design: monospaced ? .monospaced : .default))
            .foregroundStyle(secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(4)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .frame(width: width, alignment: .topLeading)
    }

    /// Party cell, with the verify badge after the name when the match was
    /// outside the counsel column. The badge exists so an over-loose hit does
    /// not silently drop a real matter.
    private func partyCell(row: BoardRow, width: CGFloat, keep: Bool) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(row.caseName)
                .font(.system(size: textSize))
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // Strike-through on the Party only — bold-weight text in the
                // other columns would become illegible at 9pt; the Party is
                // the column the advocate reads first.
                .strikethrough(!keep, color: .primary)

            if row.matchedOutsideCounselColumn {
                verifyBadge
            }
        }
        .padding(.horizontal, 4)
        .frame(width: width, alignment: .topLeading)
    }

    /// Small orange capsule that means "name found outside counsel column —
    /// eyeball this one before deleting". The colour is reserved for this
    /// signal so the advocate learns to look for it within a session.
    private var verifyBadge: some View {
        Text("verify")
            .font(.system(size: max(9, textSize - 3)))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.accent.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("The name was found outside the counsel column — check this one against the board.")
            .fixedSize()
    }
}
