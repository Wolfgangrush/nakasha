import Foundation

/// Reconciles the same matter across two or more source documents.
///
/// This exists because of a specific, concrete defect in how boards are published: the
/// bar-association Daily Board truncates every party and advocate name at a fixed field
/// width, mid-word, and that loss is unrecoverable from that document alone. The High
/// Court's own Daily Main Causelist carries the **full** names for the same case numbers.
///
/// So when an advocate loads both PDFs for the same day, the merge repairs the board:
/// case number is the join key, and for each column the fuller of the two readings wins.
/// The advocate gets a board with complete counsel names *and* the bar board's office
/// notes — which is a document neither source publishes on its own.
///
/// Rules, in order:
/// * Merging happens only ACROSS sources. Two rows carrying the same case number inside
///   ONE board are two listings of one matter — called before two courts on the same day,
///   which is what a part-heard day looks like — and both are kept. Only a row from a
///   *different* source repairs an existing one. A key that ignores which file a row came
///   from silently deletes one of the two courts the advocate is due to appear in.
/// * A row is never dropped by merging. Worst case the output equals the input.
/// * A field is only replaced by a *strictly longer* reading of the same field, so a
///   truncated name can be completed but a complete name can never be truncated.
/// * Office notes differ legitimately between sources (the registry's objection versus
///   the bar's purpose line). Both are kept, joined, never overwritten.
/// * Court, serial and section come from the source that supplied the row first, because
///   those are the source's own listing decision and mixing them would misreport where
///   and when the matter is called.
public enum BoardMerger {

    public static func merge(_ boards: [ParsedBoard]) -> [BoardRow] {
        // Cross-source repair is an explicit workflow, not a hidden side effect (01-PRD §6).
        // With a single source there is nothing to repair FROM, and running the join anyway
        // would silently collapse rows inside one board.
        guard boards.count > 1 else {
            return boards.flatMap { $0.rows.filter { $0.isMeaningful } }
        }

        var order: [String] = []
        var byKey: [String: BoardRow] = [:]
        var sourceOfKey: [String: Int] = [:]

        for (boardIndex, board) in boards.enumerated() {
            for row in board.rows where row.isMeaningful {
                let caseKey = normalise(row.caseNumber)

                guard let existing = byKey[caseKey] else {
                    order.append(caseKey)
                    byKey[caseKey] = row
                    sourceOfKey[caseKey] = boardIndex
                    continue
                }

                if sourceOfKey[caseKey] != boardIndex {
                    // A DIFFERENT source carrying the same matter: this is the repair.
                    var updated = existing
                    merge(row, into: &updated)
                    byKey[caseKey] = updated
                    continue
                }

                // The SAME source, carrying this case number a second time. That is a
                // second LISTING, not a duplicate: the matter is called before two courts
                // on one day, which is what a part-heard day looks like. Collapsing them
                // hides one of the two places the advocate has to be, so it stays its own
                // row.
                let listingKey = caseKey + "#" + String(order.count)
                order.append(listingKey)
                byKey[listingKey] = row
                sourceOfKey[listingKey] = boardIndex
            }
        }
        return order.compactMap { byKey[$0] }
    }

    /// Case numbers are printed inconsistently across registries — `WP/7117/2091`,
    /// `W.P./3642/2025`, `wp/3642/2025` are one matter. Two-digit years are widened to
    /// four so `APEAL/7013/26` joins `APEAL/7013/2026`.
    static func normalise(_ caseNumber: String) -> String {
        var s = caseNumber.uppercased()
        s.removeAll { $0 == "." || $0 == " " || $0 == "-" }
        let parts = s.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return s }
        var year = parts[2]
        if year.count == 2, let n = Int(year) {
            year = n >= 50 ? "19\(year)" : "20\(year)"
        }
        return "\(parts[0])/\(parts[1])/\(year)"
    }

    private static func merge(_ incoming: BoardRow, into row: inout BoardRow) {
        row.caseName = fuller(row.caseName, incoming.caseName)
        row.counsels = fuller(row.counsels, incoming.counsels)
        row.category = row.category.isEmpty ? incoming.category : row.category
        row.court = row.court.isEmpty ? incoming.court : row.court
        row.serial = row.serial.isEmpty ? incoming.serial : row.serial
        row.section = row.section.isEmpty ? incoming.section : row.section

        // Both sources' notes are kept. A registry objection and a bar purpose line are
        // different facts about the same matter; dropping either loses information the
        // advocate is reading the board to find.
        let a = row.officeNote.trimmingCharacters(in: .whitespaces)
        let b = incoming.officeNote.trimmingCharacters(in: .whitespaces)
        if a.isEmpty {
            row.officeNote = b
        } else if !b.isEmpty, !sameNote(a, b) {
            row.officeNote = a + " · " + b
        }

        for number in incoming.connectedCaseNumbers {
            let clean = number.uppercased()
            if !row.connectedCaseNumbers.contains(clean),
               normalise(clean) != normalise(row.caseNumber) {
                row.connectedCaseNumbers.append(clean)
            }
        }
    }

    /// A strictly longer reading wins; equal-length readings keep the incumbent so the
    /// result does not depend on the order files were dropped onto the app.
    private static func fuller(_ current: String, _ candidate: String) -> String {
        candidate.count > current.count ? candidate : current
    }

    /// One source's note is often a prefix of the other's once truncation is accounted
    /// for. Treat containment as sameness so the merged note is not printed twice.
    private static func sameNote(_ a: String, _ b: String) -> Bool {
        let x = a.uppercased(), y = b.uppercased()
        return x == y || x.contains(y) || y.contains(x)
    }
}
