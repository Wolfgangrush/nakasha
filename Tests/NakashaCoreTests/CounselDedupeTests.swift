import XCTest
@testable import NakashaCore

/// A matter carries the counsel block of every application tagged with it, and those
/// are usually the same advocates. One real matter with ten tagged applications
/// produced a counsel cell of several hundred words that was the same six names over
/// and over — it filled three pages of the export by itself and made the row taller
/// than a page, which is what drove the renderer into its split path.
final class CounselDedupeTests: XCTestCase {

    func testARepeatedNameIsKeptOnlyOnce() {
        let input = "SAKUT P. DOLKAR, A. B. FIKTUS, SAKUT P. DOLKAR, A. B. FIKTUS"
        XCTAssertEqual(BoardText.dedupeNames(input), "SAKUT P. DOLKAR, A. B. FIKTUS")
    }

    func testOrderOfFirstAppearanceIsPreserved() {
        let input = "THIRD NAME, FIRST NAME, THIRD NAME, SECOND NAME"
        XCTAssertEqual(BoardText.dedupeNames(input),
                       "THIRD NAME, FIRST NAME, SECOND NAME",
                       "the board's own order is the order the advocate reads")
    }

    func testCaseAndPaddingDifferencesAreStillTheSameName() {
        let input = "A. S. Tarkel ,   A. S. TARKEL , a. s. tarkel"
        XCTAssertEqual(BoardText.dedupeNames(input), "A. S. Tarkel")
    }

    func testTheMiddleDotSeparatorIsAlsoABoundary() {
        XCTAssertEqual(BoardText.dedupeNames("X. Y. ZED · X. Y. ZED, Q. R. STU"),
                       "X. Y. ZED, Q. R. STU")
    }

    /// Deduplication must never be allowed to empty a cell: a matter whose counsel
    /// column reads blank looks to the advocate like a matter with no advocate on it.
    func testDistinctNamesAreAllKept() {
        let input = "ONE ADV, TWO ADV, THREE ADV, FOUR ADV"
        XCTAssertEqual(BoardText.dedupeNames(input), input)
    }

    func testEmptyAndWhitespaceOnlyInputSurvive() {
        XCTAssertEqual(BoardText.dedupeNames(""), "")
        XCTAssertEqual(BoardText.dedupeNames("   ,  , "), "")
    }
}
