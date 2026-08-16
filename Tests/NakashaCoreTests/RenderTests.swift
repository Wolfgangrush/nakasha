import XCTest
import CoreGraphics
import PDFKit
@testable import NakashaCore

final class RenderTests: XCTestCase {

    private var sampleRows: [BoardRow] {
        [
            BoardRow(court: "COURT NO. A - HON'BLE SHRI JUSTICE AAROHI T. FIRSTNAME",
                     serial: "1", caseNumber: "WP/7143/2091",
                     connectedCaseNumbers: ["CAW/7066/2091"],
                     caseName: "ALPHA NADEBU TESTWALA vs SMT. NEVIFA MOCKDEKAR",
                     counsels: "ZAMIR G. SAMPLEKAR · for respondent: TUVAV K. DEMOPURKAR",
                     officeNote: "FOR ADMISSION / ORDER ON INTERIM ORDER / REMOVING OFFICE "
                               + "OBJ.NO.3,8,14,19. STATUS QUO / CON. WRIT COMPLIANCE AWAITED.",
                     section: "FOR ADMISSION-LAR MATTERS", category: "Civil",
                     sourcePage: 1, matchedNames: ["Zamir Samplekar"]),
            BoardRow(court: "COURT NO. B - HON'BLE SHRI JUSTICE LUSUFI R. THIRDNAME",
                     serial: "7", caseNumber: "CRIAPL/700/2091",
                     caseName: "KOFOG SAMPLEKAR vs STATE OF EXAMPLE",
                     counsels: "K. R. TESTER · for respondent: ADDL. P.P.",
                     officeNote: "FOR ADMISSION. R & P IS NOT RECD. AS YET.",
                     section: "FOR ADMISSION - (CRIMINAL SIDE MATTERS)", category: "Criminal",
                     sourcePage: 2, matchedNames: ["K. R. Tester"]),
        ]
    }

    private func renderer(_ title: String = "My board") -> BoardPDFRenderer {
        BoardPDFRenderer(options: .init(title: title, subtitle: "17.07.2091 · 2 matters",
                                        showSerial: true, showSection: true, landscape: true,
                                        pageSize: CGSize(width: 842, height: 595)))
    }

    // MARK: - PDF

    func testRendersARealPDF() throws {
        let data = try renderer().renderData(rows: sampleRows)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
        XCTAssertTrue(data.suffix(2048).range(of: Data("%%EOF".utf8)) != nil,
                      "a truncated PDF opens as a blank page and looks like the app worked")
    }

    /// Silence must never look like success: an advocate who matches nothing has to be
    /// told so on the page, not handed a zero-byte file.
    func testEmptyResultStillProducesAReadablePage() throws {
        let data = try renderer().renderData(rows: [])
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
    }

    func testAVeryLongOfficeNoteDoesNotLoseTheMatter() throws {
        var row = sampleRows[0]
        row.officeNote = String(repeating: "ORDERS TO FILE CIVIL APPLICATION WITH CORRECT "
                                         + "AND DETAILED ADDRESS OF RESPONDENT NO. 4. ",
                                count: 120)
        let data = try renderer().renderData(rows: [row])
        XCTAssertGreaterThan(data.count, 2000,
                             "a cell taller than the page must paginate, never be clipped away")
    }

    func testWritesToDiskAtTheGivenURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("board-test-\(ProcessInfo.processInfo.globallyUniqueString).pdf")
        try renderer().render(rows: sampleRows, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, 1000)
    }

    func testRenderingIsDeterministic() throws {
        let a = try renderer().renderData(rows: sampleRows)
        let b = try renderer().renderData(rows: sampleRows)
        XCTAssertEqual(a.count, b.count,
                       "a timestamp baked into the renderer would make diffs meaningless")
    }

    /// The column headers must appear ONCE per page.
    ///
    /// They appeared twice on page one: a court band was drawn whenever the court
    /// changed, and it pulled a second copy of the header row down with it. The
    /// band itself was redundant — "Name of Court" is column 1 of the export
    /// (01-PRD §11), so the band repeated, above every group, what the row already
    /// said a centimetre to the right.
    func testColumnHeadersAppearOncePerPage() throws {
        let data = try renderer().renderData(rows: sampleRows)
        let doc = PDFDocument(data: data)
        XCTAssertNotNil(doc)
        let page1 = doc?.page(at: 0)?.string ?? ""
        let occurrences = page1.components(separatedBy: "Office note").count - 1
        XCTAssertEqual(occurrences, 1,
                       "the header row is printed once per page, never twice")
    }

    /// The order is the product owner's decision, and it is asserted on the PAGE,
    /// not merely in the column plan — a correct plan drawn in the wrong order is
    /// still a wrong document.
    func testExportedPageCarriesTheColumnsInTheSpecifiedOrder() throws {
        let data = try renderer().renderData(rows: sampleRows)
        let page1 = PDFDocument(data: data)?.page(at: 0)?.string ?? ""
        guard let header = page1.components(separatedBy: "\n").first(where: { $0.contains("Office note") }) else {
            return XCTFail("no header row found on page 1")
        }
        let order = ["Court", "Sr.", "Case No.", "Case", "Office note", "Counsel"]
        var cursor = header.startIndex
        for column in order {
            guard let r = header.range(of: column, range: cursor..<header.endIndex) else {
                return XCTFail("column '\(column)' missing or out of order in: \(header)")
            }
            cursor = r.upperBound
        }
    }

    // MARK: - CSV

    /// The column ORDER is the product owner's decision (01-PRD §11), not a layout
    /// preference, so it is asserted exactly rather than by presence. The office note comes
    /// BEFORE the counsel. Presence-only assertions let an order change slip through
    /// unnoticed, and the CSV is read side by side with the exported PDF.
    func testCSVHeaderOrderIsExactlyTheSpecifiedOrder() {
        let csv = CSVExporter.csv(rows: sampleRows)
        let header = csv.components(separatedBy: "\r\n")[0]
        XCTAssertEqual(header,
                       "\"Court\",\"Sr.\",\"Case No.\",\"Party\",\"Office note\",\"Counsel\","
                       + "\"Section\",\"Category\",\"Source page\",\"Matched\",\"Verify\"")
    }

    /// A row that matched outside the counsel column is carried into the export flagged,
    /// because the advocate reads the exported sheet in court, away from the app, and that
    /// is precisely the row they must check against the board a second time.
    func testCSVCarriesTheVerifyFlag() {
        var flagged = sampleRows[0]
        flagged.matchedOutsideCounselColumn = true
        XCTAssertTrue(CSVExporter.csv(rows: [flagged]).contains("\"verify\""))

        var clean = sampleRows[0]
        clean.matchedOutsideCounselColumn = false
        XCTAssertFalse(CSVExporter.csv(rows: [clean]).contains("\"verify\""))
    }

    func testCSVQuotesCommasQuotesAndNewlines() {
        let rows = [BoardRow(caseNumber: "WP/1/2026",
                             caseName: "A, B and C",
                             counsels: "MR. \"BUNTY\" FIKTORNE",
                             officeNote: "line one\nline two")]
        let csv = CSVExporter.csv(rows: rows)
        XCTAssertTrue(csv.contains("\"A, B and C\""))
        XCTAssertTrue(csv.contains("\"\"BUNTY\"\""), "an embedded quote must be doubled")
        XCTAssertTrue(csv.contains("line one\nline two"),
                      "a newline inside a quoted field is legal and must survive")
    }

    func testCSVMatchedNamesJoined() {
        var row = sampleRows[0]
        row.matchedNames = ["A. S. Tarkel", "N. Vankole"]
        XCTAssertTrue(CSVExporter.csv(rows: [row]).contains("A. S. Tarkel; N. Vankole"))
    }

    func testCSVWithNoRowsIsHeaderOnly() {
        let csv = CSVExporter.csv(rows: [])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)
    }
}
