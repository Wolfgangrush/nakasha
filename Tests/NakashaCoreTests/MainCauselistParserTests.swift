import XCTest
@testable import NakashaCore

final class MainCauselistParserTests: XCTestCase {

    private func board() throws -> ParsedBoard {
        MainCauselistParser().parse(lines: try Fixture.lines(Fixture.causelist),
                                    sourceName: Fixture.causelist)
    }

    private func row(_ caseNumber: String) throws -> BoardRow {
        let b = try board()
        guard let r = b.rows.first(where: { $0.caseNumber == caseNumber }) else {
            XCTFail("no row for \(caseNumber); parsed: \(b.rows.map(\.caseNumber))")
            return BoardRow()
        }
        return r
    }

    func testFormatIsRecognisedAndOutbidsTheBarBoardParser() throws {
        let lines = try Fixture.lines(Fixture.causelist)
        XCTAssertGreaterThan(MainCauselistParser().confidence(for: lines), 0.8)
        XCTAssertLessThan(BarBoardParser().confidence(for: lines),
                          MainCauselistParser().confidence(for: lines))
    }

    func testEveryNumberedMatterIsRead() throws {
        XCTAssertEqual(try board().rows.map(\.caseNumber),
                       ["WP/7143/2091", "WP/7104/2091", "WP/715/2091", "CRIAPL/700/2091"])
    }

    func testCourtCarriesNumberAndFullCoram() throws {
        let court = try row("WP/7143/2091").court.uppercased()
        XCTAssertTrue(court.contains("COURT NO. A") || court.contains("COURT NO A"),
                      "got: \(court)")
        XCTAssertTrue(court.contains("AAROHI T. FIRSTNAME"), "got: \(court)")
        XCTAssertTrue(court.contains("VUTALES Q. SECONDNAME"),
                      "a division bench has two judges; dropping one misreports the coram")
        XCTAssertTrue(try row("CRIAPL/700/2091").court.uppercased().contains("THIRDNAME"))
    }

    /// The office note is the flush-left `FOR …` block. A centred `FOR ADMISSION-LAR
    /// MATTERS` band is a *section*, not a note — telling them apart by indentation rather
    /// than by the word "FOR" is the whole trick.
    func testFlushLeftBlockIsTheOfficeNoteAndSpansItsWrappedLines() throws {
        XCTAssertEqual(try row("WP/7143/2091").officeNote,
                       "FOR ADMISSION / ORDER ON INTERIM ORDER / REMOVING OFFICE "
                       + "OBJ.NO.3,8,14,19. STATUS QUO / CON. WRIT COMPLIANCE AWAITED.")
        XCTAssertTrue(try row("WP/7104/2091").officeNote.contains("(MEMO AWAITED)"))
        XCTAssertTrue(try row("CRIAPL/700/2091").officeNote
                        .contains("R & P IS NOT RECD. AS YET."))
    }

    func testCentredBandBecomesSectionNotOfficeNote() throws {
        XCTAssertEqual(try row("WP/7143/2091").section, "FOR ADMISSION-LAR MATTERS")
        XCTAssertEqual(try row("WP/7104/2091").section,
                       "FOR ADMISSION-CO-OPERATIVE SOCIETIES ACT MATTERS")
        XCTAssertFalse(try row("WP/7143/2091").officeNote.contains("LAR MATTERS"))
    }

    func testPartiesJoinAcrossWrappedLinesAndSplitAtVS() throws {
        let name = try row("WP/7143/2091").caseName
        XCTAssertTrue(name.contains("ALPHA NADEBU TESTWALA THR. P.O.A."), "got: \(name)")
        XCTAssertTrue(name.contains(" vs "), "got: \(name)")
        XCTAssertTrue(name.contains("MOCKDEKAR AND OTHERS"), "got: \(name)")
        XCTAssertFalse(name.contains(" VS "),
                       "the standalone VS row is a separator, not part of a party's name")
    }

    func testCategoryIsLiftedOutOfTheCaseName() throws {
        XCTAssertEqual(try row("WP/7143/2091").category, "Civil")
        XCTAssertEqual(try row("CRIAPL/700/2091").category, "Criminal")
        XCTAssertFalse(try row("WP/7143/2091").caseName.contains("[Civil]"))
    }

    func testBothCounselColumnsAreKept() throws {
        let counsels = try row("WP/7143/2091").counsels
        XCTAssertTrue(counsels.contains("ZAMIR G. SAMPLEKAR"), "got: \(counsels)")
        XCTAssertTrue(counsels.contains("TUVAV K. DEMOPURKAR"), "got: \(counsels)")
        XCTAssertTrue(counsels.contains("(FOR R 1 AND 3)"),
                      "the party a counsel appears for is the point of the column")
    }

    func testWITHBlockAttachesToThePrecedingMatter() throws {
        let b = try board()
        XCTAssertFalse(b.rows.contains { $0.caseNumber == "WP/7091/2091" },
                       "a WITH-linked matter is heard with its parent, not listed separately")
        XCTAssertEqual(try row("WP/715/2091").connectedCaseNumbers, ["WP/7091/2091"])
    }

    func testPageFooterNeverBecomesAMatter() throws {
        XCTAssertTrue(try board().rows.allSatisfy {
            !$0.caseName.uppercased().contains("DAILY MAIN CAUSELIST")
        })
    }

    /// The board does not print every page at the same left offset.
    ///
    /// Measured on a real causelist, 2026-08-16: page 1 begins its matter rows at column 0,
    /// later pages at column 2, and others at column 5 — the same template, different
    /// origins. Anchor detection that fits one set of absolute columns to the whole document
    /// is therefore wrong for most of it, and it fails in the worst possible way: the party
    /// column began inside "SECONDNAME" and the counsel column inside "NUKARI", so a surname
    /// split across a misplaced boundary is a surname the matcher cannot find.
    ///
    /// Parsing must depend on the SHAPE of a row, never on its absolute position.
    func testParsingIsUnchangedWhenTheWholeBoardIsIndented() throws {
        let original = MainCauselistParser().parse(lines: try Fixture.lines(Fixture.causelist),
                                                   sourceName: Fixture.causelist)

        // Shift every non-empty line right by two columns, exactly as a later page does.
        let shiftedText = try Fixture.text(Fixture.causelist)
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? $0 : "  " + $0 }
            .joined(separator: "\n")
        let shifted = MainCauselistParser().parse(lines: LayoutGrid.lines(fromPlainText: shiftedText),
                                                   sourceName: "shifted")

        XCTAssertEqual(shifted.rows.map(\.caseNumber), original.rows.map(\.caseNumber),
                       "the same matters must be read at either offset")
        XCTAssertEqual(shifted.rows.map(\.caseName), original.rows.map(\.caseName),
                       "an indent must not slice the party column mid-word")
        XCTAssertEqual(shifted.rows.map(\.counsels), original.rows.map(\.counsels),
                       "and it must not slice the counsel column either — that is the column "
                       + "the matcher searches, so a shift here is a missed listing")
    }

    func testEmptyDocumentIsHandledWithoutCrashing() {
        XCTAssertTrue(MainCauselistParser().parse(lines: [], sourceName: "e").rows.isEmpty)
    }
}
