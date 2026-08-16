import XCTest
import CoreGraphics
@testable import NakashaCore

final class LayoutGridTests: XCTestCase {

    // MARK: - LayoutLine

    func testSliceIsHalfOpenAndClamped() {
        let line = LayoutLine(text: "abcdef")
        XCTAssertEqual(line.slice(0, 3), "abc")
        XCTAssertEqual(line.slice(3), "def")
        XCTAssertEqual(line.slice(4, 99), "ef", "out-of-range end must clamp, not trap")
        XCTAssertEqual(line.slice(99, 120), "", "out-of-range start must yield empty")
        XCTAssertEqual(line.slice(4, 2), "", "reversed range must yield empty, not crash")
    }

    func testSlicePreservesInternalSpacing() {
        // This is load-bearing: on a hard-wrapped fixed-width field a leading space is
        // content. Trimming it here would merge two words that the board kept apart.
        let line = LayoutLine(text: "     APPLICATION   ")
        XCTAssertEqual(line.slice(4, 17), " APPLICATION ")
    }

    func testInkColumns() {
        XCTAssertEqual(LayoutLine(text: "   xy  ").firstInkColumn, 3)
        XCTAssertEqual(LayoutLine(text: "   xy  ").lastInkColumn, 4)
        XCTAssertNil(LayoutLine(text: "     ").firstInkColumn)
        XCTAssertTrue(LayoutLine(text: "   ").isBlank)
    }

    func testTabsExpandSoColumnArithmeticSurvives() {
        let lines = LayoutGrid.lines(fromPlainText: "a\tb")
        XCTAssertEqual(lines[0].text, "a       b")
        XCTAssertEqual(lines[0].firstInkColumn, 0)
    }

    // MARK: - Glyph gridding

    /// Lay out a monospaced row of glyphs and confirm the grid puts each character in the
    /// column its x-position implies — including a gap that must become real spaces.
    func testGlyphsSnapToColumns() {
        let advance: CGFloat = 6
        var glyphs: [PositionedGlyph] = []
        func put(_ s: String, atColumn col: Int, row: Int) {
            for (i, ch) in s.enumerated() {
                glyphs.append(PositionedGlyph(
                    character: ch,
                    rect: CGRect(x: CGFloat(col + i) * advance,
                                 y: 100 - CGFloat(row) * 10,
                                 width: advance, height: 8)))
            }
        }
        put("AB", atColumn: 0, row: 0)
        put("CD", atColumn: 5, row: 0)      // 3-column gap
        put("EF", atColumn: 2, row: 1)

        let lines = LayoutGrid.lines(from: glyphs, page: 1, pageHeight: 120)
        XCTAssertEqual(lines.count, 2, "two vertical bands must produce two lines")
        // The grid unit is finer than one character cell by design, so the gap is asserted
        // structurally rather than as an exact space count.
        XCTAssertTrue(lines[0].text.hasPrefix("AB"))
        XCTAssertTrue(lines[0].text.hasSuffix("CD"))
        XCTAssertTrue(lines[0].text.dropFirst(2).dropLast(2).allSatisfy { $0 == " " })
        XCTAssertGreaterThanOrEqual(lines[0].text.count - 4, 3,
                                    "a three-cell gap must survive as real blank columns")
        XCTAssertEqual(lines[1].trimmed, "EF")
        XCTAssertGreaterThan(lines[1].firstInkColumn ?? 0, 0, "indent must be preserved")
        XCTAssertEqual(lines[0].page, 1)
    }

    /// A capital and a lowercase letter on the same printed line have very different
    /// tops but nearly the same baseline. Grouping by top tears the line apart and
    /// scatters its characters, which is what a mixed-case cause list triggers.
    func testMixedGlyphHeightsStayOnOneLine() {
        // Ascenders (T, d), x-height letters (y, p, e) and a descender, all on one line.
        let word = "Typedescender"
        let glyphs = word.enumerated().map { i, ch -> PositionedGlyph in
            let tall = "Tdb".contains(ch)
            let descends = "ypg".contains(ch)
            return PositionedGlyph(character: ch,
                                   rect: CGRect(x: CGFloat(i) * 6,
                                                y: descends ? 98 : 100,
                                                width: 6,
                                                height: tall ? 9 : 6))
        }
        let lines = LayoutGrid.lines(from: glyphs, page: 1, pageHeight: 200)
        XCTAssertEqual(lines.count, 1, "one printed line must not split by glyph height")
        XCTAssertEqual(lines[0].trimmed, word)
    }

    /// A raised apostrophe sits on its own optical baseline. Left in its own group the
    /// coram reads "HON BLE" and no court header regex will ever match it.
    func testRaisedGlyphRejoinsItsLine() {
        var glyphs = [
            PositionedGlyph(character: "H", rect: CGRect(x: 0,  y: 100, width: 6, height: 8)),
            PositionedGlyph(character: "O", rect: CGRect(x: 6,  y: 100, width: 6, height: 8)),
            PositionedGlyph(character: "N", rect: CGRect(x: 12, y: 100, width: 6, height: 8)),
        ]
        // the apostrophe: small, and raised well above the baseline
        glyphs.append(PositionedGlyph(character: "\u{2019}",
                                      rect: CGRect(x: 18, y: 105, width: 3, height: 3)))
        glyphs.append(PositionedGlyph(character: "B", rect: CGRect(x: 22, y: 100, width: 6, height: 8)))
        let lines = LayoutGrid.lines(from: glyphs, page: 1, pageHeight: 200)
        XCTAssertEqual(lines.count, 1, "got \(lines.map(\.text))")
        XCTAssertTrue(lines[0].trimmed.contains("HON"))
        XCTAssertTrue(lines[0].trimmed.hasSuffix("B"))
    }

    /// The cell pitch is the step between neighbouring characters, not the width of one
    /// glyph's ink. Court PDFs are proportional: a `.` is a fraction of its cell, so ink
    /// width under-reads the pitch and every column downstream lands wrong.
    func testPitchComesFromCharacterStepsNotInkWidth() {
        let glyphs = (0..<10).map { i in
            PositionedGlyph(character: Character(UnicodeScalar(65 + i)!),
                            rect: CGRect(x: CGFloat(i) * 10, y: 100,
                                         width: i % 2 == 0 ? 2 : 9, height: 8))
        }
        let lines = LayoutGrid.lines(from: glyphs, page: 1, pageHeight: 200)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].trimmed, "ABCDEFGHIJ",
                       "uniform 10pt steps with wildly varying ink widths must still "
                       + "produce one unbroken run, got \(lines[0].text)")
    }

    func testEmptyGlyphSetYieldsNoLines() {
        XCTAssertTrue(LayoutGrid.lines(from: [], page: 1, pageHeight: 100).isEmpty)
    }

    // MARK: - Gutter detection

    func testGutterFoundBetweenTwoTextBlocks() {
        let text = """
        left one        right one
        left two        right two
        left three      right three
        left four       right four
        left five       right five
        """
        let gutters = ColumnDetector.gutters(in: LayoutGrid.lines(fromPlainText: text))
        XCTAssertTrue(gutters.contains { $0.start <= 14 && $0.end >= 16 },
                      "expected a channel spanning the blank band, got \(gutters)")
    }

    func testPrimaryGutterIgnoresLeftMarginAndRightEdge() {
        let text = """
            aaa        bbb
            aaa        bbb
            aaa        bbb
            aaa        bbb
            aaa        bbb
        """
        let g = ColumnDetector.primaryGutter(in: LayoutGrid.lines(fromPlainText: text))
        XCTAssertNotNil(g)
        XCTAssertGreaterThan(g!.start, 4, "the left indent must not be taken as the column break")
    }

    /// The defect this guards: measuring the gutter over a whole page lets a full-width
    /// notice line paper over the channel, the detector returns nil, and the parser falls
    /// back to a guessed column — silently mixing counsel text into the case name.
    func testFullWidthNoticeDestroysGutterUnlessMatterRowsAreIsolated() {
        let matterRows = """
        1  WP/1/2026 A # B:NOTE          COUNSEL ONE
        2  WP/2/2026 C # D:NOTE          COUNSEL TWO
        3  WP/3/2026 E # F:NOTE          COUNSEL THREE
        4  WP/4/2026 G # H:NOTE          COUNSEL FOUR
        """
        let noticed = matterRows + "\nMembers are requested to clear their subscription dues today."
        XCTAssertNotNil(ColumnDetector.primaryGutter(in: LayoutGrid.lines(fromPlainText: matterRows)),
                        "matter rows alone must expose the channel")
        XCTAssertNil(ColumnDetector.primaryGutter(in: LayoutGrid.lines(fromPlainText: noticed)),
                     "a full-width notice must be shown to destroy the channel — which is "
                     + "exactly why the parser measures over matter rows only")
    }
}
