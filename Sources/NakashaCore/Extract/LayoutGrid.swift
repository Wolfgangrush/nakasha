import Foundation
import CoreGraphics

/// A single visual line of a page, snapped onto a fixed-width character grid.
///
/// Court cause lists are typeset in a monospaced face and laid out in hard columns.
/// Reconstructing that character grid — rather than reading a flattened text stream —
/// is what makes column slicing (parties | counsels) and hard-wrap rejoining exact.
public struct LayoutLine: Equatable, Sendable {
    /// The line as a grid row. Column *n* of every line refers to the same x on the page.
    public let text: String
    /// Page number this line came from (1-based).
    public let page: Int
    /// Vertical position, page top = 0. Only used for ordering.
    public let y: CGFloat

    public init(text: String, page: Int = 0, y: CGFloat = 0) {
        self.text = text
        self.page = page
        self.y = y
    }

    private var chars: [Character] { Array(text) }

    /// Half-open column slice `[from, to)`. Out-of-range is clamped, never a crash.
    /// Internal spacing is preserved exactly — the caller decides whether to trim,
    /// because on a hard-wrapped field a leading space is *content*, not padding.
    public func slice(_ from: Int, _ to: Int? = nil) -> String {
        let c = chars
        let lo = max(0, min(from, c.count))
        let hi = max(lo, min(to ?? c.count, c.count))
        return String(c[lo..<hi])
    }

    /// Column of the first non-space character, or nil for a blank line.
    /// This is the indentation signal that separates a flush-left office note from a
    /// centred section header from an indented continuation.
    public var firstInkColumn: Int? {
        for (i, ch) in chars.enumerated() where ch != " " {
            return i
        }
        return nil
    }

    public var lastInkColumn: Int? {
        for i in stride(from: chars.count - 1, through: 0, by: -1) where chars[i] != " " {
            return i
        }
        return nil
    }

    public var isBlank: Bool { firstInkColumn == nil }

    public var trimmed: String {
        text.trimmingCharacters(in: .whitespaces)
    }

    public var width: Int { chars.count }
}

/// One page's worth of grid lines.
public struct LayoutPage: Equatable, Sendable {
    public let number: Int
    public let lines: [LayoutLine]

    /// False when the page carried no drawn glyphs at all — a scan or a photograph pasted into
    /// an otherwise readable board. Such a page contributes no rows, so it MUST be reported:
    /// a page that silently contributes nothing is indistinguishable from a page with nothing
    /// on it, and every matter printed there would vanish without a word. See 01-PRD §8.
    public let hasTextLayer: Bool

    public init(number: Int, lines: [LayoutLine], hasTextLayer: Bool = true) {
        self.number = number
        self.lines = lines
        self.hasTextLayer = hasTextLayer
    }
}

/// A positioned glyph as PDFKit reports it. Kept separate from PDFKit so the grid
/// builder is testable without a PDF.
public struct PositionedGlyph: Sendable {
    public let character: Character
    public let rect: CGRect
    public init(character: Character, rect: CGRect) {
        self.character = character
        self.rect = rect
    }
}

/// A glyph after normalisation: x position, baseline measured from the page top, and the
/// box height used to size the line-grouping tolerance.
struct Placed {
    let ch: Character
    let x: CGFloat
    let width: CGFloat
    let base: CGFloat
    let height: CGFloat
}

public enum LayoutGrid {

    /// Build grid lines from positioned glyphs.
    ///
    /// - Line grouping is by vertical overlap of glyph boxes, not by a fixed row height,
    ///   so a page that mixes 8pt and 12pt runs still groups correctly.
    /// - Column mapping uses the *median glyph advance*, which on a monospaced court
    ///   document is the exact cell width. On a proportional document it degrades to a
    ///   sensible approximation rather than failing.
    ///
    /// `originTopLeft` = true when rects already use a top-left origin. PDFKit page space
    /// is bottom-left, so the PDF extractor passes false and we flip.
    public static func lines(from glyphs: [PositionedGlyph],
                             page: Int,
                             pageHeight: CGFloat,
                             originTopLeft: Bool = false) -> [LayoutLine] {
        let usable = glyphs.filter { !$0.character.isNewline && $0.rect.height > 0 }
        guard !usable.isEmpty else { return [] }

        // Work in "distance from the top of the page" so sorting ascending reads the page
        // in reading order regardless of the source's coordinate convention.
        let placed: [Placed] = usable.map { g in
            let bottom = originTopLeft ? g.rect.maxY : pageHeight - g.rect.minY
            return Placed(ch: g.character, x: g.rect.minX, width: g.rect.width,
                          base: bottom, height: g.rect.height)
        }

        // --- line grouping ---------------------------------------------------------
        //
        // Group by BASELINE, never by the top of the glyph box. A capital `T` and a
        // lowercase `y` sitting on the same printed line have very different tops — top
        // grouping tears one line into several and scatters its characters, which is
        // exactly what a court board's mixed-case text triggers. Their bottoms agree to
        // within a descender, so a tolerance of a third of the line height holds them
        // together while still separating adjacent lines.
        let medianHeight = median(placed.map(\.height))
        let tolerance = max(medianHeight * 0.35, 0.5)

        var rows: [[Placed]] = []
        var anchor: CGFloat = .nan
        for glyph in placed.sorted(by: { $0.base == $1.base ? $0.x < $1.x : $0.base < $1.base }) {
            if rows.isEmpty || abs(glyph.base - anchor) > tolerance {
                rows.append([glyph])
                anchor = glyph.base
            } else {
                rows[rows.count - 1].append(glyph)
            }
        }

        // --- reunite raised glyphs with their line ---------------------------------
        //
        // A raised apostrophe (HON'BLE) and an ordinate suffix (the "th" of 17th) sit on
        // their own optical baseline, so baseline clustering correctly puts them in their
        // own group — and then the line reads "HON BLE", which no coram regex will match.
        // Any group that is both TINY and much closer to its neighbour than a line of
        // text ever is belongs to that neighbour.
        if rows.count > 1 {
            var merged: [[Placed]] = []
            for group in rows {
                if let previous = merged.last, group.count <= 3 || previous.count <= 3 {
                    let gap = abs((group.first?.base ?? 0) - (previous.first?.base ?? 0))
                    if gap < medianHeight * 0.85 {
                        merged[merged.count - 1].append(contentsOf: group)
                        continue
                    }
                }
                merged.append(group)
            }
            rows = merged
        }

        // --- column placement ------------------------------------------------------
        //
        // Court PDFs are NOT monospaced, despite reading like fixed-width print. Measured
        // on two real registry exports, glyph advances range 2.7-7.7pt on one and
        // 2.4-33.3pt on the other. Snapping each character independently to a pitch
        // therefore drops characters into each other's cells: `DAILY MAIN CAUSELIST`
        // came out as `DAIL MAI CAUSELIS`.
        //
        // So place WORDS, not characters. A word's characters are written consecutively
        // (their spacing is a property of the font, not of the page), while the word's
        // starting column is derived from its x. That is how `pdftotext -layout`
        // reconstructs a grid, and it is the geometry the parsers here are calibrated
        // against: intra-word text is exact, and a column's left edge lands on the same
        // grid column on every line because it is the same x on every line.
        // Deliberately FINER than one character cell. Word starts are placed from their own
        // x, so a smaller unit keeps the grid faithful to the true page geometry instead
        // of letting accumulated text push words leftward and swallow the channel between
        // columns. Measured on a real bar-association board: at 1.0 the counsel column
        // had no detectable channel at all; at 0.72 it shows as a clean run at ~98%
        // blank. Inside a word nothing changes — those characters are written
        // consecutively regardless of the unit.
        let cell = medianStep(rows) ?? max(median(placed.map(\.height)) * 0.6, 1)
        // Column placement uses a unit DELIBERATELY FINER than one cell. Word starts are
        // positioned from their own x, so a smaller unit keeps the grid faithful to the
        // page instead of letting accumulated text creep leftward and swallow the channel
        // between columns. Measured on a real bar-association board: at one cell the
        // counsel column had no detectable channel at all; at 0.72 it is a clean run.
        let unit = cell * 0.72
        guard unit > 0.01 else { return [] }
        // A word break needs BOTH signals, because either one alone is wrong on a
        // proportional face:
        //   * step alone breaks after every WIDE letter — an `M` advances further than
        //     1.35 cells on its own, which produced `A.M . SAMPLEKAR` and `HON 'BLE`;
        //   * ink gap alone breaks after every NARROW letter — an `I` or a `.` leaves
        //     most of its cell empty even with no space present.
        // A real space both advances more than a cell and leaves visible white.
        let breakStep = cell * 1.15
        let breakGap = cell * 0.25
        let minX = placed.map(\.x).min() ?? 0

        return rows.compactMap { row -> LayoutLine? in
            let ordered = row.filter { $0.ch != " " }.sorted { $0.x < $1.x }
            guard !ordered.isEmpty else { return nil }

            var out: [Character] = []
            var cursor = 0
            var wordStart = 0
            var index = 0

            func flushWord(_ upTo: Int) {
                guard upTo > wordStart else { return }
                let word = ordered[wordStart..<upTo]
                var col = Int(((word.first!.x - minX) / unit).rounded())
                // Never overwrite what is already placed, and always leave at least one
                // space between two words so they do not fuse into a false single token.
                if cursor > 0 { col = max(col, cursor + 1) }
                if out.count < col { out.append(contentsOf: repeatElement(" ", count: col - out.count)) }
                for glyph in word { out.append(glyph.ch) }
                cursor = out.count
            }

            while index < ordered.count {
                if index > wordStart {
                    let prev = ordered[index - 1]
                    let step = ordered[index].x - prev.x
                    let gap = step - prev.width
                    if step > breakStep, gap > breakGap {
                        flushWord(index)
                        wordStart = index
                    }
                }
                index += 1
            }
            flushWord(ordered.count)

            guard !out.isEmpty else { return nil }
            return LayoutLine(text: String(out), page: page, y: row[0].base)
        }
    }

    /// Build grid lines straight from already-laid-out monospaced text — a
    /// `pdftotext -layout` dump, or a test fixture. Tabs are expanded so column
    /// arithmetic still holds.
    ///
    /// This is the seam that lets every parser be tested without a PDF, which matters
    /// here for a reason beyond convenience: real cause lists carry live litigant names
    /// and must never be committed as fixtures.
    public static func lines(fromPlainText text: String, page: Int = 1) -> [LayoutLine] {
        text.components(separatedBy: .newlines).enumerated().map { index, raw in
            LayoutLine(text: expandTabs(raw), page: page, y: CGFloat(index))
        }
    }

    static func expandTabs(_ line: String, stop: Int = 8) -> String {
        guard line.contains("\t") else { return line }
        var out = ""
        var col = 0
        for ch in line {
            if ch == "\t" {
                let pad = stop - (col % stop)
                out += String(repeating: " ", count: pad)
                col += pad
            } else {
                out.append(ch)
                col += 1
            }
        }
        return out
    }

    static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    /// Typical horizontal step between neighbouring glyphs — the effective character
    /// cell for the page. The MEDIAN, not the mode: on a proportional face no single step
    /// value repeats often enough for a mode to mean anything, and a mode computed on
    /// such data picks an arbitrary narrow glyph and shreds the layout.
    ///
    /// Steps are taken only between glyphs already grouped onto the same line, and steps
    /// wider than four cells are discarded so the gaps BETWEEN columns cannot inflate the
    /// estimate.
    static func medianStep(_ rows: [[Placed]]) -> CGFloat? {
        var steps: [CGFloat] = []
        for row in rows {
            let xs = row.sorted { $0.x < $1.x }
            guard xs.count > 1 else { continue }
            for i in 1..<xs.count {
                let step = xs[i].x - xs[i - 1].x
                if step > 0.5, step < 40 { steps.append(step) }
            }
        }
        guard steps.count >= 8 else { return nil }
        return median(steps)
    }

}

// MARK: - Gutter detection

public struct Gutter: Equatable, Sendable {
    public let start: Int
    public let end: Int          // exclusive
    public var width: Int { end - start }
    public var center: Int { (start + end) / 2 }
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public enum ColumnDetector {

    /// Find vertical whitespace channels that run through (almost) every content line.
    ///
    /// This is what separates the parties block from the counsel block on a board.
    /// It is derived from the document itself rather than hardcoded, which is the whole
    /// reason the parser survives a registry changing its column widths.
    ///
    /// - Parameters:
    ///   - minWidth: a channel narrower than this is inter-word space, not a column break.
    ///   - coverage: fraction of content lines that must be blank across the channel.
    /// `minWidth` is 2 by default, not 3: word-run placement guarantees exactly one
    /// blank column between two words, so a blank channel two columns wide that survives
    /// the coverage vote is already a column break. On a real bar-association board the
    /// counsel column sits just two grid columns clear of the matter block.
    public static func gutters(in lines: [LayoutLine],
                               minWidth: Int = 2,
                               coverage: Double = 0.90) -> [Gutter] {
        let content = lines.filter { !$0.isBlank }
        guard content.count >= 4 else { return [] }

        let width = content.map(\.width).max() ?? 0
        guard width > 0 else { return [] }

        // A line only votes about columns up to its own last ink; trailing emptiness is
        // not evidence of a gutter, otherwise every short line invents one.
        var blankVotes = [Int](repeating: 0, count: width)
        var totalVotes = [Int](repeating: 0, count: width)
        for line in content {
            guard let last = line.lastInkColumn else { continue }
            let chars = Array(line.text)
            for col in 0...min(last, width - 1) {
                totalVotes[col] += 1
                if col >= chars.count || chars[col] == " " { blankVotes[col] += 1 }
            }
        }

        var result: [Gutter] = []
        var run: Int? = nil
        for col in 0..<width {
            let votes = totalVotes[col]
            let isGutter = votes > 0 && Double(blankVotes[col]) / Double(votes) >= coverage
            if isGutter {
                if run == nil { run = col }
            } else if let start = run {
                if col - start >= minWidth { result.append(Gutter(start: start, end: col)) }
                run = nil
            }
        }
        if let start = run, width - start >= minWidth {
            result.append(Gutter(start: start, end: width))
        }
        return result
    }

    /// The single channel that splits a two-block layout (matter text | counsel text).
    ///
    /// Picks the widest gutter inside the plausible mid-page band. Leading indentation
    /// gutters (column 0-ish) and trailing right-margin gutters are excluded by the band,
    /// so an unusually deep left indent can't be mistaken for the column break.
    ///
    /// **Feed this the matter rows, not the whole page.** A board's notices, headers and
    /// footnotes run the full page width and will paper over the very channel we are
    /// looking for — measured against a real bar-association board, including the notice
    /// text destroyed the gutter entirely and the parser silently fell back to a guessed
    /// column, which is how a whole counsel column ends up in the wrong field.
    public static func primaryGutter(in lines: [LayoutLine],
                                     bandLow: Double = 0.30,
                                     bandHigh: Double = 0.80,
                                     coverage: Double = 0.90) -> Gutter? {
        let content = lines.filter { !$0.isBlank }
        let width = content.map(\.width).max() ?? 0
        guard width > 0 else { return nil }
        let low = Int(Double(width) * bandLow)
        let high = Int(Double(width) * bandHigh)
        let candidates = gutters(in: lines, coverage: coverage)
            .filter { $0.center >= low && $0.center <= high }
        return candidates.max { lhs, rhs in
            lhs.width == rhs.width ? lhs.start > rhs.start : lhs.width < rhs.width
        }
    }
}
