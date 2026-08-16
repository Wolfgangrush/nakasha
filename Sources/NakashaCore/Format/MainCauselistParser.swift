import Foundation
import CoreGraphics

public struct MainCauselistParser: BoardFormat {
    public let name = "High Court Daily Main Causelist"
    public init() {}

    public func confidence(for lines: [LayoutLine]) -> Double {
        let head = lines.prefix(400).map { BoardText.flat($0).uppercased() }.joined(separator: " ")
        var score = 0.0
        if head.contains("DAILY MAIN CAUSELIST") { score += 0.75 }
        if head.contains("CAUSELIST") || head.contains("CAUSE LIST") { score += 0.10 }
        for flat in lines.prefix(400).map({ BoardText.flat($0) }) {
            if BoardText.contains(BoardText.courtNumber, flat) { score += 0.15; break }
        }
        let firstRaw = lines.prefix(600).filter { $0.text.contains("#") }
        if firstRaw.count >= 5 { score -= 0.50 }
        if head.contains("DAILY BOARD") { score -= 0.40 }
        return min(1.0, max(0.0, score))
    }

    public func parse(lines: [LayoutLine], sourceName: String) -> ParsedBoard {
        var board = ParsedBoard(formatName: name, sourceName: sourceName)

        let flatLines: [String] = lines.map { BoardText.flat($0) }

        // Title — first flat line containing CAUSELIST / CAUSE LIST within the first 60 lines.
        for flat in flatLines.prefix(60) {
            let up = flat.uppercased()
            if up.contains("CAUSELIST") || up.contains("CAUSE LIST") {
                board.title = BoardText.collapse(flat)
                break
            }
        }

        // Date — first line starting with "FOR " (case-insensitive) that contains a 4-digit number.
        for flat in flatLines.prefix(60) {
            let lower = flat.lowercased()
            if lower.hasPrefix("for ") {
                if let _ = flat.range(of: #"\d{4}"#, options: .regularExpression) {
                    board.boardDate = BoardText.collapse(flat)
                    break
                }
            }
        }

        // Geometry is learned per page: the template's shape is constant across the file,
        // but the page origin is not. See `Anchors` for the measurement that forced this.
        let anchorsByPage = Anchors.byPage(for: lines)
        let fallbackAnchors = Anchors(for: lines)
        func anchorsFor(_ line: LayoutLine) -> Anchors {
            anchorsByPage[line.page] ?? fallbackAnchors
        }

        var rows: [BoardRow] = []
        var court = ""
        var coram: [String] = []
        var section = ""
        var open: Matter?
        var pendingWith = false

        func courtLabel() -> String {
            let joined = coram.joined(separator: " AND ")
            if court.isEmpty { return joined }
            if coram.isEmpty { return court }
            return "\(court) - \(joined)"
        }

        func flush() {
            guard let matter = open else { return }
            let result = matter.finish(court: courtLabel(), section: section)
            open = nil
            if result.wasWith, !rows.isEmpty {
                let lastIdx = rows.count - 1
                var last = rows[lastIdx]
                if !last.connectedCaseNumbers.contains(result.row.caseNumber) {
                    last.connectedCaseNumbers.append(result.row.caseNumber)
                }
                let merged = [last.counsels, result.row.counsels]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                last.counsels = BoardText.collapse(merged)
                if last.officeNote.isEmpty {
                    last.officeNote = result.row.officeNote
                }
                rows[lastIdx] = last
                return
            }
            var row = result.row
            row.section = section
            rows.append(row)
        }

        for (index, line) in lines.enumerated() {
            let flat = flatLines[index]

            // 1. Court number banner.
            if let m = BoardText.firstMatch(BoardText.courtNumber, flat) {
                flush()
                let g1 = m.count > 1 ? m[1] : ""
                court = "COURT NO. \(g1.uppercased())"
                coram = []
                section = ""
                pendingWith = false
                continue
            }

            // 2. Coram accumulation.
            let up = flat.uppercased()
            if (up.hasPrefix("HON'BLE") || up.hasPrefix("HONBLE"))
                && !up.contains("COURT")
                && !up.contains("CAUSELIST")
            {
                if let m = BoardText.firstMatch(BoardText.justice, flat), m.count > 1 {
                    flush()
                    coram.append(BoardText.collapse(m[1]))
                    continue
                }
            }

            // 3. Furniture / page footer.
            if BoardText.isFurniture(line) { continue }
            let flatUp = flat.uppercased()
            if flatUp.contains("CAUSELIST COURT NO") && flatUp.contains("HIGH COURT") {
                continue
            }

            // 4. Bench size / sitting-time stamps.
            if flatUp == "DIVISION" || flatUp == "SINGLE" { continue }
            if flat.range(of: #"^AT \d{1,2}[:.]\d{2}( ?[AP]M)?$"#, options: .regularExpression) != nil {
                continue
            }

            // 5. Indent.
            let anchors = anchorsFor(line)
            let indent = line.firstInkColumn ?? 0

            // 6. Numbered matter row.
            if let m = BoardText.firstMatch(BoardText.itemRow, line.text), m.count > 2 {
                flush()
                let serial = m[2]
                let caseNo = m[3].uppercased()
                var mtr = Matter(serial: serial, caseNumber: caseNo, page: line.page, wasWith: pendingWith)
                pendingWith = false
                mtr.absorb(line, anchors: anchors)
                open = mtr
                continue
            }

            // 7. WITH-linked indented case.
            if pendingWith && indent > anchors.item,
               let m = BoardText.firstMatch(BoardText.indentedCase, line.text),
               m.count > 2 {
                flush()
                let caseNo = m[2].uppercased()
                var mtr = Matter(serial: "", caseNumber: caseNo, page: line.page, wasWith: true)
                pendingWith = false
                mtr.absorb(line, anchors: anchors)
                open = mtr
                continue
            }

            // 8. Office note (flush-left).
            if indent <= anchors.item + 1 {
                if open != nil { open?.appendNote(flat) }
                continue
            }

            // 9. Section band / WITH marker.
            // Gated on "not flush left", not on "at or right of the parties column": a
            // centred band can begin to the LEFT of the parties column (a measured one
            // starts at column 21 while parties is 23). The flush-left office-note branch
            // at step 8 runs first, which is what keeps a flush-left "FOR …" a note and a
            // centred "FOR …" a section — told apart by column, never by the word.
            if indent > anchors.item + 1 {
                let noCaseNo = BoardText.firstMatch(BoardText.itemRow, flat) == nil
                let isIndented = (line.firstInkColumn ?? 0) > anchors.item + 2
                let lastInk = line.lastInkColumn ?? 0
                let isCentred = lastInk < anchors.counselB + 8
                if noCaseNo && isIndented && isCentred {
                    let isSectionBand =
                        flatUp == "WITH" ||
                        flatUp.hasPrefix("FOR ") ||
                        flatUp.contains("MATTERS") ||
                        flatUp.contains("PART HEARD") ||
                        flatUp.contains("PART-HEARD") ||
                        flatUp.contains("SIDE MATTERS") ||
                        flatUp.contains("FINAL HEARING") ||
                        flatUp.contains("SUPPLEMENTARY")
                    if isSectionBand {
                        if flatUp == "WITH" {
                            flush()
                            pendingWith = true
                        } else {
                            flush()
                            section = BoardText.collapse(flat)
                        }
                        continue
                    }
                    // Falls through — treat as continuation of open matter.
                    if open != nil, indent >= anchors.caseNumber {
                        open?.absorb(line, anchors: anchors)
                        continue
                    }
                }
            }

            // 10. Continuation of an open matter.
            if open != nil, indent >= anchors.caseNumber {
                open?.absorb(line, anchors: anchors)
                continue
            }
        }

        flush()
        board.rows = rows.filter { $0.isMeaningful }
        return board
    }
}

/// Column boundaries of a matter row: item, case-number, parties, counsel-left, counsel-right.
///
/// Derived in two independent halves, because a real board varies them independently:
///
/// * the **shape** — how far each zone sits from the item column — is a property of the
///   document's template and is stable across the whole file;
/// * the **offset** — where that whole block starts — is a property of the PAGE, and it
///   moves. On a real causelist measured 2026-08-16, page 1 begins at column 0 and every
///   later page begins at column 2. Identical shape, different origin.
///
/// Fitting one set of absolute columns to the whole document therefore cannot be right for
/// every page, and being wrong here is not cosmetic: the matcher searches the counsel
/// column, so a boundary two characters out slices a surname in half and the advocate is
/// told they are not listed. Learn the shape once, then the origin per page.
public struct Anchors {
    public var item = 0
    public var caseNumber = 4
    public var parties = 23
    public var counselA = 51
    public var counselB = 68

    public init() {}

    /// Document-wide anchors, using the most common page origin. The per-page map is what
    /// the parser should use; this exists for callers that only have one page's worth, and
    /// as the fallback for a page that carries no matter row of its own.
    public init(for lines: [LayoutLine]) {
        if let plan = Anchors.Plan(lines: lines) {
            self = plan.anchors(base: plan.dominantBase)
            return
        }
        self = Anchors.gutterFallback(lines: lines)
    }

    /// Anchors for every page that carries at least one matter row. A page without one
    /// inherits the nearest earlier page that had one, so a continuation page still slices
    /// against the geometry it was printed with.
    public static func byPage(for lines: [LayoutLine]) -> [Int: Anchors] {
        guard let plan = Plan(lines: lines) else { return [:] }
        var out: [Int: Anchors] = [:]
        let pages = Set(lines.map(\.page)).sorted()
        var lastKnown = plan.dominantBase
        for page in pages {
            if let base = plan.basesByPage[page] { lastKnown = base }
            out[page] = plan.anchors(base: lastKnown)
        }
        return out
    }

    /// Calibration aid: what the plan actually learned from this document.
    ///
    /// 02-ARCHITECTURE gives the CLI the job of calibrating a new court format. A parser
    /// that mis-slices a board still produces confident-looking output, so the only way to
    /// see WHY is to read the geometry it inferred.
    public static func debugPlan(for lines: [LayoutLine]) -> String {
        guard let plan = Plan(lines: lines) else { return "no plan (too few matter rows)" }
        let bases = plan.basesByPage.sorted { $0.key < $1.key }
            .prefix(8)
            .map { "p\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "shape=\(plan.shape) dominantBase=\(plan.dominantBase) bases: \(bases)"
    }

    // MARK: - Plan

    /// The template: five offsets from the item column, plus where each page starts.
    struct Plan {
        let shape: [Int]
        let basesByPage: [Int: Int]
        let dominantBase: Int

        init?(lines: [LayoutLine]) {
            let matterRows = lines.filter { BoardText.contains(BoardText.itemRow, $0.text) }
            guard matterRows.count >= 3 else { return nil }

            // Zone boundaries are found with a WIDE gap, and the case-number column is not
            // guessed at all — it is read straight off the `itemRow` match.
            //
            // Measured on a real causelist, 2026-08-16. A narrow gap treats the ordinary
            // 3-space gap INSIDE a party name ("FIRSTNAME   SECONDNAME") as a column
            // boundary, so a row reports six or seven segments and the extra ones outvote
            // the real geometry. The gap BETWEEN zones is consistently 8 or more columns,
            // so a threshold of 6 separates zones and ignores the padding inside them.
            let zoneGap = 6
            var caseDeltas: [Int: Int] = [:]
            var partyDeltas: [Int: Int] = [:]
            var counselADeltas: [Int: Int] = [:]
            var counselBDeltas: [Int: Int] = [:]
            var basesPerPage: [Int: [Int: Int]] = [:]
            var overallBase: [Int: Int] = [:]

            for row in matterRows {
                let ns = row.text as NSString
                guard let match = BoardText.itemRow.firstMatch(
                        in: row.text, options: [],
                        range: NSRange(location: 0, length: ns.length)),
                      match.numberOfRanges > 3 else { continue }
                let caseRange = match.range(at: 3)
                guard caseRange.location != NSNotFound else { continue }
                guard let itemCol = row.firstInkColumn else { continue }

                basesPerPage[row.page, default: [:]][itemCol, default: 0] += 1
                overallBase[itemCol, default: 0] += 1
                caseDeltas[caseRange.location - itemCol, default: 0] += 1

                // Everything that begins after the case number ends is a zone start.
                let caseEnd = caseRange.location + caseRange.length
                let zones = Anchors.segmentStarts(of: row, minimumGap: zoneGap)
                    .filter { $0 >= caseEnd }
                if zones.count >= 1 { partyDeltas[zones[0] - itemCol, default: 0] += 1 }
                if zones.count >= 2 { counselADeltas[zones[1] - itemCol, default: 0] += 1 }
                if zones.count >= 3 { counselBDeltas[zones[2] - itemCol, default: 0] += 1 }
            }

            // Each zone votes independently. A whole-vector mode fails here because the
            // columns jitter by a character between pages, so two readings that agree about
            // every boundary still count as different vectors and split the vote.
            func mode(_ counts: [Int: Int]) -> Int? {
                counts.max(by: { l, r in
                    l.value != r.value ? l.value < r.value : l.key > r.key
                })?.key
            }

            // A zone boundary is placed at the LOW edge of its cluster, not at the mode.
            // The columns jitter by a character between pages, and the two directions are
            // not symmetric: starting a slice one column early picks up blank padding and
            // costs nothing, while starting it one column late eats the first letter of the
            // column — "NUKARI" was being read as "UKARI". Trimmed to within two columns
            // of the mode so a single malformed row cannot drag a boundary left.
            func lowEdge(_ counts: [Int: Int]) -> Int? {
                guard let m = mode(counts) else { return nil }
                return counts.keys.filter { abs($0 - m) <= 2 }.min() ?? m
            }

            guard let caseD = lowEdge(caseDeltas),
                  let partyD = lowEdge(partyDeltas),
                  let counselAD = lowEdge(counselADeltas) else { return nil }
            // Counsel-right is legitimately absent on plenty of rows (a lone "ADDL. P.P."
            // with nothing opposite it). When no row on the board ever shows one, put the
            // boundary past the widest line so counsel-left simply takes the rest of the
            // row — keeping the text rather than cutting it at an invented column.
            let counselBD = lowEdge(counselBDeltas)
                ?? max(counselAD + 12, (lines.map(\.width).max() ?? 100))

            self.shape = [0, caseD, partyD, counselAD, counselBD]

            var bases: [Int: Int] = [:]
            for (page, counts) in basesPerPage {
                if let base = mode(counts) { bases[page] = base }
            }
            self.basesByPage = bases
            self.dominantBase = mode(overallBase) ?? 0
        }

        func anchors(base: Int) -> Anchors {
            var a = Anchors()
            a.item = base + shape[0]
            a.caseNumber = base + shape[1]
            a.parties = base + shape[2]
            a.counselA = base + shape[3]
            a.counselB = base + shape[4]
            return a.ordered()
        }
    }

    /// Zones must stay strictly increasing, or a slice runs backwards and silently returns
    /// nothing — which reads to the advocate as a matter with no counsel.
    func ordered() -> Anchors {
        var a = self
        if a.caseNumber <= a.item { a.caseNumber = a.item + 3 }
        if a.parties <= a.caseNumber { a.parties = a.caseNumber + 8 }
        if a.counselA <= a.parties { a.counselA = a.parties + 12 }
        if a.counselB <= a.counselA { a.counselB = a.counselA + 12 }
        return a
    }

    /// Last resort when no matter row could be recognised at all: fall back to blank-column
    /// gutters across the body text.
    static func gutterFallback(lines: [LayoutLine]) -> Anchors {
        var a = Anchors()
        let body = lines.filter { line in
            guard let first = line.firstInkColumn, first > 0 else { return false }
            return !BoardText.isFurniture(line)
        }
        guard !body.isEmpty else { return a }
        let boundaries = ColumnDetector.gutters(in: body)
            .map(\.end)
            .filter { $0 > 1 }
            .sorted()
        guard boundaries.count >= 3 else { return a }
        let widest = lines.map(\.width).max() ?? 100
        a.caseNumber = boundaries[0]
        a.parties = boundaries.count > 1 ? boundaries[1] : a.caseNumber + 17
        a.counselA = boundaries.count > 2 ? boundaries[2] : min(a.parties + 17, widest)
        a.counselB = boundaries.count > 3 ? boundaries[3] : min(a.counselA + 17, widest)
        return a.ordered()
    }

    /// Returns the column indices where each visual segment begins on `line`.
    ///
    /// A segment starts at the first non-blank character of the line, or at any non-blank
    /// character immediately preceded by a run of at least `minimumGap` consecutive blanks.
    /// Blank characters *inside* a segment (the single space in `ALPHA NILANGE`) do not open
    /// a new one. The result is ascending and duplicate-free by construction.
    ///
    /// The index returned is the first **inked** column of the segment, never a column
    /// inside the gutter before it. Returning a gutter column instead put every anchor a
    /// zone to the left, which sliced the case number into the parties column and the
    /// parties into the counsel column — and because the matcher searches only the counsel
    /// column, that reads as "advocate not on this board". An entirely blank line has no
    /// segments and returns `[]`.
    public static func segmentStarts(of line: LayoutLine, minimumGap: Int = 2) -> [Int] {
        let chars = Array(line.text)
        var starts: [Int] = []
        var blanks = 0
        for (i, ch) in chars.enumerated() {
            if ch == " " {
                blanks += 1
            } else {
                // `starts.isEmpty`, not `i == 0`: an item row may itself be indented, and
                // anchoring only at column 0 would drop its first segment entirely.
                if starts.isEmpty || blanks >= minimumGap {
                    starts.append(i)
                }
                blanks = 0
            }
        }
        return starts
    }
}

/// Accumulator for a single matter row. The raw layout preserves column geometry, so we
/// slice from the grid to recover parties and counsel columns even when words wrap.
private struct Matter {
    let serial: String
    let caseNumber: String
    let page: Int
    let wasWith: Bool

    var parties: [String] = []
    var counselA: [String] = []
    var counselB: [String] = []
    var note: [String] = []
    var category = ""

    mutating func absorb(_ line: LayoutLine, anchors: Anchors) {
        var partiesText = line.slice(anchors.parties, anchors.counselA)
        let a = BoardText.collapse(line.slice(anchors.counselA, anchors.counselB))
        let b = BoardText.collapse(line.slice(anchors.counselB))

        if let m = BoardText.firstMatch(BoardText.category, partiesText), m.count > 1 {
            category = m[1]
            partiesText = partiesText.replacingOccurrences(of: m[0], with: " ")
        } else if let m = BoardText.firstMatch(BoardText.category, line.text), m.count > 1 {
            category = m[1]
        }

        let collapsedParties = BoardText.collapse(partiesText)
        if !collapsedParties.isEmpty { parties.append(collapsedParties) }
        if !a.isEmpty { counselA.append(a) }
        if !b.isEmpty { counselB.append(b) }
    }

    mutating func appendNote(_ text: String) {
        let collapsed = BoardText.collapse(text)
        if !collapsed.isEmpty { note.append(collapsed) }
    }

    func finish(court: String, section: String) -> (row: BoardRow, wasWith: Bool) {
        // Rejoin wrapped party lines with a single space: "word-wrapped" columns must collapse
        // across line breaks without inventing new word boundaries.
        let partiesJoined = BoardText.collapse(parties.joined(separator: " "))

        // Split on a standalone VS — petitioner vs respondent.
        let name: String
        if let vsRange = partiesJoined.range(of: #"(?:^|\s)VS(?:\s|$)"#, options: .regularExpression) {
            let lead = partiesJoined[partiesJoined.startIndex..<vsRange.lowerBound]
            let tail = partiesJoined[vsRange.upperBound..<partiesJoined.endIndex]
            let left = BoardText.collapse(String(lead))
            let right = BoardText.collapse(String(tail))
            name = BoardText.collapse("\(left) vs \(right)")
        } else {
            name = partiesJoined
        }
        let stripped = name
            .replacingOccurrences(of: "[Civil]", with: "")
            .replacingOccurrences(of: "[Criminal]", with: "")
        let caseName = BoardText.collapse(stripped)

        let counselLeft = BoardText.collapse(counselA.joined(separator: " "))
        let counselRight = BoardText.collapse(counselB.joined(separator: " "))
        let counselParts = [counselLeft, counselRight].filter { !$0.isEmpty }
        let counsels = BoardText.collapse(counselParts.joined(separator: " · "))

        let officeNote = BoardText.collapse(note.joined(separator: " "))

        let row = BoardRow(
            court: court,
            serial: serial,
            caseNumber: caseNumber,
            connectedCaseNumbers: [],
            caseName: caseName,
            counsels: counsels,
            officeNote: officeNote,
            section: section,
            category: category,
            sourcePage: page,
            matchedNames: []
        )
        return (row, wasWith)
    }
}
