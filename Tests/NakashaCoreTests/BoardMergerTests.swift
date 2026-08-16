import XCTest
@testable import NakashaCore

final class BoardMergerTests: XCTestCase {

    /// The product claim: load the bar board *and* the High Court causelist for the same
    /// day and you get complete counsel names (which only the causelist has) together
    /// with the registry's office notes (which only the bar board has).
    func testTruncatedNamesAreCompletedFromTheFullerSource() {
        let barBoard = ParsedBoard(formatName: "bar", rows: [
            BoardRow(court: "REGISTRAR", serial: "12", caseNumber: "WP/7117/2091",
                     caseName: "R RUMEDOLI vs THE SUB-DIVI",
                     counsels: "BADAM SAKUTU TESTIVANK I",
                     officeNote: "ORDERS ON CAW NO 1004/2091. (FRESH)")
        ])
        let causelist = ParsedBoard(formatName: "hc", rows: [
            BoardRow(court: "COURT NO. A", serial: "3", caseNumber: "WP/7117/2091",
                     caseName: "RAJESH RUMEDOLI TESTOL vs THE SUB-DIVISIONAL OFFICER",
                     counsels: "BADAM SAKUTU TESTIVANKARI",
                     officeNote: "FOR ADMISSION. GP FOR R.NO.1.")
        ])
        let merged = BoardMerger.merge([barBoard, causelist])
        XCTAssertEqual(merged.count, 1, "one matter, two sources, one row")
        XCTAssertEqual(merged[0].counsels, "BADAM SAKUTU TESTIVANKARI")
        XCTAssertEqual(merged[0].caseName, "RAJESH RUMEDOLI TESTOL vs THE SUB-DIVISIONAL OFFICER")
        XCTAssertEqual(merged[0].court, "REGISTRAR", "listing facts stay with the first source")
        XCTAssertEqual(merged[0].serial, "12")
        XCTAssertTrue(merged[0].officeNote.contains("(FRESH)"))
        XCTAssertTrue(merged[0].officeNote.contains("GP FOR R.NO.1"),
                      "the two sources say different true things; both are kept")
    }

    func testAFullNameIsNeverReplacedByATruncatedOne() {
        let full = ParsedBoard(rows: [BoardRow(caseNumber: "WP/1/2026",
                                               counsels: "BADAM SAKUTU TESTIVANKARI")])
        let cut = ParsedBoard(rows: [BoardRow(caseNumber: "WP/1/2026",
                                              counsels: "BADAM SAKUTU TESTIVANK I")])
        XCTAssertEqual(BoardMerger.merge([full, cut])[0].counsels, "BADAM SAKUTU TESTIVANKARI")
        XCTAssertEqual(BoardMerger.merge([cut, full])[0].counsels, "BADAM SAKUTU TESTIVANKARI",
                       "the result must not depend on which file was dropped first")
    }

    func testCaseNumberPunctuationAndTwoDigitYearsJoinTheSameMatter() {
        XCTAssertEqual(BoardMerger.normalise("W.P./7117/2091"), "WP/7117/2091")
        XCTAssertEqual(BoardMerger.normalise("wp/7117/2091"), "WP/7117/2091")
        XCTAssertEqual(BoardMerger.normalise("APEAL/7013/26"), "APEAL/7013/2026",
                       "a two-digit year is widened so the same matter joins across sources")
        XCTAssertEqual(BoardMerger.normalise("APEAL/7013/91"), "APEAL/7013/1991",
                       "and a year at or above 50 belongs to the last century")

        let a = ParsedBoard(rows: [BoardRow(caseNumber: "W.P./7117/2091", counsels: "AB")])
        let b = ParsedBoard(rows: [BoardRow(caseNumber: "wp/7117/2091", counsels: "ABCDEF")])
        XCTAssertEqual(BoardMerger.merge([a, b]).count, 1)
    }

    func testIdenticalNotesAreNotPrintedTwice() {
        let note = "FOR ADMISSION."
        let a = ParsedBoard(rows: [BoardRow(caseNumber: "WP/1/2026", officeNote: note)])
        let b = ParsedBoard(rows: [BoardRow(caseNumber: "WP/1/2026", officeNote: note)])
        XCTAssertEqual(BoardMerger.merge([a, b])[0].officeNote, note)
    }

    func testMergingNeverDropsAMatter() {
        let a = ParsedBoard(rows: [BoardRow(caseNumber: "WP/1/2026"),
                                   BoardRow(caseNumber: "WP/2/2026")])
        let b = ParsedBoard(rows: [BoardRow(caseNumber: "WP/2/2026"),
                                   BoardRow(caseNumber: "WP/3/2026")])
        XCTAssertEqual(BoardMerger.merge([a, b]).map(\.caseNumber),
                       ["WP/1/2026", "WP/2/2026", "WP/3/2026"])
    }

    func testConnectedNumbersAreUnionedWithoutSelfReference() {
        let a = ParsedBoard(rows: [BoardRow(caseNumber: "WP/1/2026",
                                            connectedCaseNumbers: ["CAW/9/2026"])])
        let b = ParsedBoard(rows: [BoardRow(caseNumber: "WP/1/2026",
                                            connectedCaseNumbers: ["CAW/9/2026", "APPA/8/2026",
                                                                   "WP/1/2026"])])
        XCTAssertEqual(BoardMerger.merge([a, b])[0].connectedCaseNumbers,
                       ["CAW/9/2026", "APPA/8/2026"])
    }

    func testRowsWithoutACaseNumberAreNotEmitted() {
        let a = ParsedBoard(rows: [BoardRow(caseName: "debris"), BoardRow(caseNumber: "WP/1/2026")])
        XCTAssertEqual(BoardMerger.merge([a]).map(\.caseNumber), ["WP/1/2026"])
    }
}
