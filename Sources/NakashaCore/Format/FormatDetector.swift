import Foundation

/// Resolves which `BoardFormat` should parse a given document, then dispatches
/// to it. Falls back to `GenericBoardParser` when no specialised parser is
/// confident, so the user always sees *some* table rather than nothing.
public enum FormatDetector {

    /// All known parsers in priority order for tie-breaking. Earlier entries
    /// win when `confidence` ties.
    public static let all: [BoardFormat] = [
        BarBoardParser(),
        MainCauselistParser(),
        GenericBoardParser()
    ]

    /// Pick the parser with the highest confidence (ties keep the earlier entry).
    public static func best(for lines: [LayoutLine]) -> BoardFormat {
        var bestFormat: BoardFormat = GenericBoardParser()
        var bestScore = -Double.infinity
        for f in all {
            let s = f.confidence(for: lines)
            if s > bestScore {
                bestScore = s
                bestFormat = f
            }
        }
        return bestFormat
    }

    /// Convenience: pick and immediately parse.
    public static func parse(lines: [LayoutLine], sourceName: String) -> ParsedBoard {
        best(for: lines).parse(lines: lines, sourceName: sourceName)
    }
}

/// Last-resort parser. Walks the document and starts a row at any item row
/// or indented case number. Splits at the primary gutter and treats flush-left
/// prose as the office note. Never crashes, always returns `isMeaningful` rows
/// when it can.
public struct GenericBoardParser: BoardFormat {

    public let name: String = "Generic"

    public init() {}

    public func confidence(for lines: [LayoutLine]) -> Double {
        // Always available as a fallback, but never the first choice — the
        // detector prefers specialised parsers unless they score lower.
        return 0.05
    }

    public func parse(lines: [LayoutLine], sourceName: String) -> ParsedBoard {
        var board = ParsedBoard(formatName: name, sourceName: sourceName)

        var currentCourt = ""
        var currentSection = ""

        var openRow: BoardRow?

        // Primary gutter is computed once per window and reused, instead of
        // re-deriving on every continuation line.
        var windowMarker = -1
        var cachedGutterCut = 70

        func flush() {
            if var row = openRow {
                if !row.officeNote.isEmpty {
                    row.officeNote = BoardText.collapse(row.officeNote)
                }
                if row.isMeaningful {
                    board.rows.append(row)
                }
            }
            openRow = nil
        }

        for (idx, line) in lines.enumerated() {
            if BoardText.isFurniture(line) { continue }

            let t = line.trimmed
            if t.isEmpty { continue }

            // Court header carry.
            if let m = BoardText.firstMatch(BoardText.courtHead, t) {
                currentCourt = BoardText.collapse(m[1])
            }
            if let m = BoardText.firstMatch(BoardText.courtNumber, t) {
                currentCourt = "COURT NO. \(m[1])"
            }

            // Section header (bare heuristic: centring + uppercase FOR/MATTER prefix).
            if isLikelySectionHeader(line) {
                flush()
                currentSection = BoardText.collapse(t)
                continue
            }

            // New item row.
            if let m = BoardText.firstMatch(BoardText.itemRow, line.text) {
                flush()
                var row = BoardRow()
                row.court = currentCourt
                row.section = currentSection
                row.serial = m[2]
                row.caseNumber = BoardText.collapse(m[3])
                row.sourcePage = line.page

                let cut = gutterCut(for: lines, idx: idx,
                                    windowMarker: &windowMarker,
                                    cached: &cachedGutterCut)
                let left = line.slice(0, cut)
                let right = line.slice(cut, nil)
                let collapsedLeft = BoardText.collapse(left)
                let collapsedRight = BoardText.collapse(right)
                let (pet, resp) = splitAtVS(collapsedLeft)
                row.caseName = resp.map { "\(pet) vs \($0)" } ?? collapsedLeft
                row.counsels = collapsedRight
                if let cat = BoardText.firstMatch(BoardText.category, line.text) {
                    row.category = cat[1]
                    row.caseName = stripBracket(row.caseName)
                }
                openRow = row
                continue
            }

            // Indented case row (no item number — common when the matter
            // continues from a prior page).
            if let m = BoardText.firstMatch(BoardText.indentedCase, line.text) {
                flush()
                var row = BoardRow()
                row.court = currentCourt
                row.section = currentSection
                row.caseNumber = BoardText.collapse(m[2])
                row.sourcePage = line.page
                let cut = gutterCut(for: lines, idx: idx,
                                    windowMarker: &windowMarker,
                                    cached: &cachedGutterCut)
                let left = line.slice(0, cut)
                let right = line.slice(cut, nil)
                row.caseName = BoardText.collapse(left)
                row.counsels = BoardText.collapse(right)
                if let cat = BoardText.firstMatch(BoardText.category, line.text) {
                    row.category = cat[1]
                    row.caseName = stripBracket(row.caseName)
                }
                openRow = row
                continue
            }

            // Continuation / office note.
            if var row = openRow {
                if let first = line.firstInkColumn {
                    if first <= 4 {
                        // Flush left — office note.
                        let more = BoardText.collapse(t)
                        if !more.isEmpty {
                            if row.officeNote.isEmpty {
                                row.officeNote = more
                            } else {
                                row.officeNote += " " + more
                            }
                            row.officeNote = BoardText.collapse(row.officeNote)
                        }
                    } else {
                        // Continuation. Use the cached gutter to pick a side.
                        let cut = gutterCut(for: lines, idx: idx,
                                            windowMarker: &windowMarker,
                                            cached: &cachedGutterCut)
                        if first < cut {
                            row.caseName = BoardText.collapse([row.caseName, t].filter { !$0.isEmpty }.joined(separator: " "))
                            let (pet, resp) = splitAtVS(row.caseName)
                            if let r = resp { row.caseName = "\(pet) vs \(r)" }
                        } else {
                            row.counsels = BoardText.collapse([row.counsels, t].filter { !$0.isEmpty }.joined(separator: " "))
                        }
                    }
                }
                // Write the mutated copy back into the optional binding.
                openRow = row
            }
        }

        flush()

        return board
    }

    // MARK: - Helpers

    /// Window the gutter lookup so we don't recompute for every line in a long
    /// matter. The marker stores the lower bound of the last window we computed.
    private func gutterCut(for lines: [LayoutLine], idx: Int,
                           windowMarker: inout Int, cached: inout Int) -> Int {
        if idx - windowMarker >= 8 || windowMarker < 0 {
            let primary = ColumnDetector.primaryGutter(in: linesForContext(lines, idx: idx))
            cached = primary?.start ?? 70
            windowMarker = idx
        }
        return cached
    }

    private func linesForContext(_ lines: [LayoutLine], idx: Int) -> [LayoutLine] {
        let lo = max(0, idx - 5)
        let hi = min(lines.count, idx + 6)
        return Array(lines[lo..<hi])
    }

    private func isLikelySectionHeader(_ line: LayoutLine) -> Bool {
        let t = line.trimmed
        if t.isEmpty { return false }
        guard let first = line.firstInkColumn else { return false }
        // Roughly centred (>= some indent) and not a matter row.
        if BoardText.firstMatch(BoardText.itemRow, line.text) != nil { return false }
        let upper = t.uppercased()
        if first >= 8 && (upper.hasPrefix("FOR ") || upper.contains("MATTER") || upper.hasPrefix("ITEM ")) {
            return true
        }
        return false
    }

    private func splitAtVS(_ text: String) -> (String, String?) {
        let tokens = text.split(separator: " ").map(String.init)
        guard let idx = tokens.firstIndex(where: { $0 == "VS" || $0 == "Vs" || $0 == "vs" }) else {
            return (text, nil)
        }
        let pet = tokens[0..<idx].joined(separator: " ")
        let resp = tokens[(idx + 1)...].joined(separator: " ")
        return (pet, resp.isEmpty ? nil : resp)
    }

    private func stripBracket(_ s: String) -> String {
        guard let r = try? NSRegularExpression(pattern: #"\[[^\]]*\]"#) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return r.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }
}
