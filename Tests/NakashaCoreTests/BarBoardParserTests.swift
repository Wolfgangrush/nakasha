import XCTest
@testable import NakashaCore

final class BarBoardParserTests: XCTestCase {

    private func board() throws -> ParsedBoard {
        BarBoardParser().parse(lines: try Fixture.lines(Fixture.hcba),
                                     sourceName: Fixture.hcba)
    }

    private func row(_ caseNumber: String) throws -> BoardRow {
        let b = try board()
        guard let r = b.rows.first(where: { $0.caseNumber == caseNumber }) else {
            XCTFail("no row for \(caseNumber); parsed: \(b.rows.map(\.caseNumber))")
            return BoardRow()
        }
        return r
    }

    func testFormatIsRecognised() throws {
        let lines = try Fixture.lines(Fixture.hcba)
        XCTAssertGreaterThan(BarBoardParser().confidence(for: lines), 0.8)
        XCTAssertGreaterThan(MainCauselistParser().confidence(for: lines), -1)
        XCTAssertLessThan(MainCauselistParser().confidence(for: lines),
                          BarBoardParser().confidence(for: lines),
                          "the causelist parser must not outbid on a bar board")
    }

    func testEveryNumberedMatterIsRead() throws {
        let b = try board()
        XCTAssertEqual(b.rows.map(\.caseNumber),
                       ["WP/7117/2091", "WP/7130/2091", "WP/7078/2091",
                        "APEAL/701/2091", "APEAL/702/2091", "APEAL/703/2091"],
                       "a dropped matter is the one failure this tool cannot have")
        XCTAssertEqual(b.boardDate, "17.07.2091")
    }

    /// The core arithmetic of the whole product. The export chops the left field mid-word
    /// at a fixed width; joined wrongly it yields `O RDERS`, `DET AILED`, `CORREC T`.
    func testHardWrappedOfficeNoteIsRejoinedWithoutInventedSpaces() throws {
        let r = try row("WP/7117/2091")
        XCTAssertEqual(r.officeNote,
                       "ORDERS ON CAW NO 1004/2091 ( DELETING THE NAME OF R-12 FROM THE "
                       + "ARRAY OF THE RESP. ). (FRESH)")

        let r3 = try row("WP/7078/2091")
        XCTAssertTrue(r3.officeNote.contains("CORRECT AND DETAILED ADD OF R-2"),
                      "mid-word chop must rejoin to CORRECT/DETAILED, got: \(r3.officeNote)")
        XCTAssertFalse(r3.officeNote.contains("DETAILE D"))

        let r4 = try row("APEAL/703/2091")
        XCTAssertTrue(r4.officeNote.contains("DETAILED COMPLIANCE REPORT IS AWTD."),
                      "got: \(r4.officeNote)")
    }

    func testOfficeNoteIsSplitFromPartiesAtTheFirstColon() throws {
        XCTAssertEqual(try row("APEAL/702/2091").officeNote, "ADM")
        XCTAssertEqual(try row("WP/7130/2091").officeNote,
                       "ORDERS ON CAW NO 1615/2091 ( PERMISSION TO SUPPLY CORRECT AND "
                       + "DETAIL ADD OF R-4).(FRESH)")
    }

    func testPartiesUseTheBoardsOwnHashSeparator() throws {
        XCTAssertEqual(try row("WP/7130/2091").caseName, "SEVIB KHAN H vs HAJI LOGOTO")
    }

    func testConnectedMattersFoldIntoTheirParentAndNeverBecomeRows() throws {
        let b = try board()
        XCTAssertFalse(b.rows.contains { $0.caseNumber == "CAW/7052/2091" },
                       "a tagged civil application is part of the parent matter, not a listing")
        XCTAssertEqual(try row("WP/7117/2091").connectedCaseNumbers, ["CAW/7052/2091"])
        XCTAssertEqual(try row("APEAL/701/2091").connectedCaseNumbers, ["APPA/706/2091"])
        XCTAssertEqual(try row("WP/7117/2091").numberColumn,
                       "WP/7117/2091\nwith CAW/7052/2091")
    }

    /// A stray `:` printed on a tagged matter's wrapped line used to be appended to the
    /// parent's note, producing a note that ended in a phantom colon.
    func testTaggedMatterFragmentsDoNotLeakIntoTheParentsNote() throws {
        let note = try row("APEAL/701/2091").officeNote
        XCTAssertFalse(note.hasSuffix(":"), "got: \(note)")
        XCTAssertTrue(note.hasSuffix("R & P IS NOT RECD. AS YET."), "got: \(note)")
    }

    func testCourtIsTakenFromTheBoardsOwnHeadingIncludingRegistrars() throws {
        XCTAssertEqual(try row("WP/7117/2091").court,
                       "REGISTRAR SHRI T.N. EXAMPLEKAR R (JUDICIAL)")
        XCTAssertEqual(try row("APEAL/702/2091").court,
                       "HON'BLE SHRI JUSTICE YASH G. THIRDNAME")
    }

    func testSectionBandCarriesToTheMattersUnderIt() throws {
        XCTAssertEqual(try row("WP/7117/2091").section, "FOR ORDERS")
        XCTAssertEqual(try row("APEAL/701/2091").section, "PART HEARD")
        XCTAssertEqual(try row("APEAL/702/2091").section, "FOR ADMISSION")
    }

    func testCounselColumnKeepsBothSidesAndCarriesNoStrayHashes() throws {
        let r = try row("WP/7117/2091")
        XCTAssertTrue(r.counsels.contains("BADAM SAKUTU TESTWALA"))
        XCTAssertTrue(r.counsels.contains("for respondent:"))
        XCTAssertTrue(r.counsels.contains("GOVERNMENT PLEADER"))
        XCTAssertFalse(r.counsels.contains("#"),
                       "the hash is a field separator, not counsel text: \(r.counsels)")
    }

    func testNoticesAndPageFurnitureNeverBecomeMatters() throws {
        let b = try board()
        XCTAssertTrue(b.rows.allSatisfy { $0.isMeaningful })
        XCTAssertFalse(b.rows.contains { $0.caseName.contains("parking stickers") })
    }

    func testEmptyDocumentIsHandledWithoutCrashing() {
        let b = BarBoardParser().parse(lines: [], sourceName: "empty")
        XCTAssertTrue(b.rows.isEmpty)
    }
}
