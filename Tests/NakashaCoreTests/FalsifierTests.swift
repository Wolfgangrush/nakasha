import XCTest
@testable import NakashaCore

/// The falsifier, written down as tests.
///
/// From `04-BMAD-SPEC.md`: *an advocate runs NAKASHA on a real board, prunes nothing, and a
/// matter in which they are actually listed does not appear in the result set.* One such miss
/// ends the design. Over-inclusion is NOT a falsifier — that is the design, and pruning is
/// the user's job.
///
/// Every test here guards a specific route by which a listing could vanish. They are grouped
/// in one file on purpose: if any of these ever goes red, the product claim is broken, not
/// merely a feature.
final class FalsifierTests: XCTestCase {

    // MARK: - Route 1: the merge deletes one of two listings

    /// A part-heard matter is called before two courts on the same day. Both listings are
    /// real and the advocate has to be in both places. An earlier version keyed the merge on
    /// case number alone, which silently collapsed them into one row.
    func testTheSameCaseBeforeTwoCourtsInOneBoardStaysTwoRows() {
        let board = ParsedBoard(formatName: "bar", rows: [
            BoardRow(court: "COURT NO. A", serial: "11", caseNumber: "WP/7042/2091",
                     caseName: "FIKTUS vs MOKARA", counsels: "R. R. VERNEKAR"),
            BoardRow(court: "COURT NO. B", serial: "4", caseNumber: "WP/7042/2091",
                     caseName: "FIKTUS vs MOKARA", counsels: "R. R. VERNEKAR"),
        ])
        let merged = BoardMerger.merge([board])
        XCTAssertEqual(merged.count, 2,
                       "one matter, two courts, two places to be — never one row")
        XCTAssertEqual(merged.map(\.court), ["COURT NO. A", "COURT NO. B"])
    }

    /// The same guard must hold once a second source is in play, so that fixing the merge
    /// did not simply move the collapse one step later.
    func testTwoListingsSurviveEvenWhenASecondSourceIsLoaded() {
        let bar = ParsedBoard(formatName: "bar", rows: [
            BoardRow(court: "COURT NO. A", caseNumber: "WP/9/2026", counsels: "VERNEKA"),
            BoardRow(court: "COURT NO. B", caseNumber: "WP/9/2026", counsels: "VERNEKA"),
        ])
        let causelist = ParsedBoard(formatName: "hc", rows: [
            BoardRow(court: "COURT NO. A", caseNumber: "WP/9/2026",
                     counsels: "ANANTRAO VITHALRAO VERNEKAR"),
        ])
        let merged = BoardMerger.merge([bar, causelist])
        XCTAssertEqual(merged.count, 2, "the second board repairs a row; it never removes one")
        XCTAssertEqual(merged[0].counsels, "ANANTRAO VITHALRAO VERNEKAR",
                       "and the repair still happens: the truncated reading is completed")
    }

    // MARK: - Route 2: the view layer drops a row with a duplicate identity

    /// Two connected matters under one court on one page both carry an empty serial and the
    /// same case number. If their `id`s collide, a SwiftUI `Table`/`ForEach` silently drops
    /// one — a matter disappearing because of the view, where no parser test is looking.
    func testEveryRowInAResultSetHasAUniqueIdentity() throws {
        let board = ParsedBoard(rows: [
            BoardRow(court: "COURT NO. A", serial: "", caseNumber: "CAW/7052/2091",
                     sourcePage: 5),
            BoardRow(court: "COURT NO. A", serial: "", caseNumber: "CAW/7052/2091",
                     sourcePage: 5),
            BoardRow(court: "COURT NO. A", serial: "", caseNumber: "CAW/7052/2091",
                     sourcePage: 5),
        ])
        // Ordinals are what the service stamps on; simulate that here.
        let stamped = board.rows.enumerated().map { index, row -> BoardRow in
            var copy = row
            copy.ordinal = index
            return copy
        }
        XCTAssertEqual(Set(stamped.map(\.id)).count, stamped.count,
                       "three identical-looking rows must still be three identities")
    }

    // MARK: - Route 3: the counsel-column restriction hides a real listing

    /// Searching ONLY the counsel column is a precision optimisation. The moment a parse
    /// defect misfiles counsel text into another column, a counsel-only search returns
    /// nothing and the advocate reads a clean empty table as "I am not on this board".
    /// The row must survive, flagged — never be dropped.
    func testANameFoundOutsideTheCounselColumnStillProducesARowAndIsFlagged() {
        let rows = [
            BoardRow(caseNumber: "WP/1/2026",
                     caseName: "STATE vs SOMEONE",
                     counsels: "MR. R. R. VERNEKAR"),          // clean: in the counsel column
            BoardRow(caseNumber: "WP/2/2026",
                     caseName: "ADV. R. R. VERNEKAR APPEARING", // misfiled into the party column
                     counsels: ""),
            BoardRow(caseNumber: "WP/3/2026",
                     caseName: "NOTHING TO DO WITH IT",
                     counsels: "MR. P. Q. FIKTORNE"),
        ]
        let out = rows.filtered(by: NameMatcher(entries: NameMatcher.entries(fromUserText: "Vernekar")))

        XCTAssertEqual(out.map(\.caseNumber), ["WP/1/2026", "WP/2/2026"],
                       "the misfiled row is the one this product may not lose")
        XCTAssertFalse(out[0].matchedOutsideCounselColumn,
                       "a counsel-column hit is the clean case and is not flagged")
        XCTAssertTrue(out[1].matchedOutsideCounselColumn,
                      "it is shown, and it is marked for the advocate to check")
    }

    /// The widened search must not undo the guard that keeps a party's father's or husband's
    /// name from producing a listing — otherwise every common surname becomes noise.
    func testTheRelationshipGuardStillHoldsInTheWidenedSearch() {
        let rows = [
            BoardRow(caseNumber: "WP/1/2026",
                     caseName: "RAMESH S/O VERNEKAR vs STATE",
                     counsels: "MR. P. Q. FIKTORNE"),
        ]
        let out = rows.filtered(by: NameMatcher(entries: NameMatcher.entries(fromUserText: "Vernekar")))
        XCTAssertTrue(out.isEmpty,
                      "the name after S/O is the party's father, never the appearing advocate")
    }

    // MARK: - Route 4: the surname the advocate will actually type finds nothing

    /// The author, 2026-08-16: advocates are "100% going to search with the surname". Every printed
    /// shape of a surname that the board can produce must be found by typing that surname.
    func testTheSurnameAloneFindsEveryPrintedShapeOfIt() {
        let matcher = NameMatcher(entries: NameMatcher.entries(fromUserText: "Vankole"))
        let printedShapes = [
            "ANANTRAO VITHALRAO VANKOLE",     // as printed in full
            "ANANTRAO VITHALRAO VANK OLE",    // hard-wrapped mid-word, no hyphen
            "R. R. VANKOA",                   // cut at the field width
            "adv. anantrao vankole",         // lower case
        ]
        for shape in printedShapes {
            XCTAssertFalse(matcher.hits(in: shape).isEmpty,
                           "typing the surname must find it printed as '\(shape)'")
        }
    }
}
