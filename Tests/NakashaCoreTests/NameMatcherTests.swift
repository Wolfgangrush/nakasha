import XCTest
@testable import NakashaCore

final class NameMatcherTests: XCTestCase {

    private func matcher(_ names: String) -> NameMatcher {
        NameMatcher(entries: NameMatcher.entries(fromUserText: names))
    }

    // MARK: - Initials tolerance

    func testInitialSpacingVariantsAllMatchOneName() {
        let m = matcher("A. S. Tarkel")
        for spelling in ["A. S. Tarkel", "A.S. TARKEL", "A S TARKEL", "A.S.Tarkel", "a.s. tarkel"] {
            XCTAssertEqual(m.hits(in: "MR. \(spelling) FOR PETITIONER").first?.display,
                           "A. S. Tarkel",
                           "registries print initials inconsistently; '\(spelling)' must match")
        }
    }

    // MARK: - Loose matching (01-PRD §7, requirement #1)

    /// The doctrine, stated as a test. An earlier version of this suite asserted the
    /// opposite — that `Tarkel` must NOT match `TARKELE`, to protect Tarkele from appearing in
    /// Tarkel's list. That trade is backwards: the extra row costs one click to prune, and
    /// the row it drops is a matter the advocate never learns they are listed in. Over-
    /// inclusion is permitted by design; a miss ends the design (04-BMAD-SPEC, falsifier).
    func testLooseMatchIsOverInclusiveByDesign() {
        let m = matcher("Tarkel")
        XCTAssertEqual(m.hits(in: "ANIL S. TARKEL").count, 1)
        XCTAssertFalse(m.hits(in: "ANIL S. TARKELE").isEmpty,
                       "an over-inclusive row is pruned in one click; a missed row is never "
                       + "seen at all, and that is the failure this product may not have")
        XCTAssertTrue(m.hits(in: "STARKEL").isEmpty,
                      "the LEADING word boundary still holds — truncation cuts the end of a "
                      + "field, never the start, so a surname must not match mid-word")
    }

    /// The bar board hard-wraps mid-word without a hyphen. Shown here with an invented name,
    /// `ANANTRAO VITHALRAO VANK OLE`: the surname VANKOLE
    /// split across the field boundary. Typing the surname must still find it.
    func testHardWrappedSurnameSplitMidWordStillMatches() {
        let m = matcher("Vankole")
        XCTAssertEqual(m.hits(in: "ANANTRAO VITHALRAO VANK OLE").count, 1,
                       "this shape of string is why loose matching exists")
        XCTAssertEqual(m.hits(in: "ANANTRAO VITHALRAO VANKOLE").count, 1,
                       "the unwrapped spelling must match too")
    }

    /// The board truncates every advocate name at a fixed field width, so the printed form
    /// is often a strict prefix of the real one. The typed name is the longer string; the
    /// document holds the shorter. Matching must survive that direction.
    func testFieldWidthTruncationStillMatches() {
        let m = matcher("Vernekar")
        XCTAssertEqual(m.hits(in: "ADV. R. R. VERNEKA FOR R-2").count, 1,
                       "VERNEKA is VERNEKAR with the field width reached")
        XCTAssertEqual(m.hits(in: "ADV. R. R. VERNE").count, 1,
                       "five characters is the floor for an eight-character surname")
        XCTAssertTrue(m.hits(in: "ADV. R. R. VERN FOR R-2").isEmpty,
                      "the floor has to hold somewhere, or every surname matches everything")
    }

    /// A surname alone must match, and a full name must not require every token to be
    /// present, in order, adjacent. Advocates type what they remember, which is usually the
    /// surname and rarely the printed form.
    func testAnyTokenMatchesRatherThanAllTokens() {
        let m = matcher("Anantrao Vernekar")
        XCTAssertEqual(m.hits(in: "SHRI R. R. VERNEKAR FOR PETITIONER").count, 1,
                       "the surname alone must be enough")
        XCTAssertEqual(m.hits(in: "ANANTRAO TESTMUKH").count, 1,
                       "the given name alone is also a hit — over-inclusive, then pruned")
    }

    /// A single-letter token would match on hundreds of unrelated rows and drown the result
    /// set, which is the same defect as a miss wearing different clothes: the advocate stops
    /// trusting the list. Initials and honorifics are dropped as search terms.
    func testInitialsAndHonorificsAreNotSearchTerms() {
        XCTAssertTrue(matcher("A. S. Tarkel").hits(in: "A. B. FIKTORNE").isEmpty,
                      "matching on the initial 'A' would list most of the board")
        XCTAssertTrue(matcher("Dr. Vernekar").hits(in: "DR. P. Q. FIKTORNE").isEmpty,
                      "'DR' is an honorific, not a name")
    }

    /// The escape hatch in 01-PRD §7 for users who want precision: `;`-separated alternates
    /// opt the whole entry back into strict, bounded matching.
    func testSemicolonAliasesOptIntoPreciseMatching() {
        let m = matcher("A. S. Tarkel; Tarkel A S")
        XCTAssertEqual(m.hits(in: "MR. A. S. TARKEL FOR R-1").count, 1)
        XCTAssertTrue(m.hits(in: "MR. A. S. TARKELE FOR R-1").isEmpty,
                      "having asked for precision, the user gets a trailing boundary back")
    }

    /// A user who types nothing but initials still gets the old strict behaviour rather
    /// than an empty pattern list and silent zero results.
    func testOnlyInitialsFallsBackToStrictMatching() {
        XCTAssertFalse(matcher("A S").hits(in: "MR. A. S. TARKEL").isEmpty,
                       "no significant token is a reason to fall back, never to return nothing")
    }

    // MARK: - Party names are not counsel

    func testRelationshipMarkerMeansPartyNotAdvocate() {
        let m = matcher("Testmukh")
        XCTAssertTrue(m.hits(in: "BALU S/O TESTMUKH").isEmpty,
                      "the name after S/O is the party's father, never the appearing advocate")
        XCTAssertTrue(m.hits(in: "SMT. RANI W/O TESTMUKH").isEmpty)
        XCTAssertEqual(m.hits(in: "MR. R. V. TESTMUKH FOR R-1").count, 1)
    }

    // MARK: - User input parsing

    func testAliasesAfterSemicolonAndCommentsIgnored() {
        let entries = NameMatcher.entries(fromUserText: """
        # my chamber
        A. S. Tarkel; Tarkel A S; ASK

        Neelam Vankole
        """)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].display, "A. S. Tarkel")
        XCTAssertEqual(entries[0].aliases, ["A. S. Tarkel", "Tarkel A S", "ASK"],
                       "the display name must always be searchable too")
        XCTAssertEqual(entries[1].display, "Neelam Vankole")
    }

    func testEmptyInputMatchesNothingAndIsReportedEmpty() {
        let m = matcher("   \n # only a comment \n ")
        XCTAssertTrue(m.isEmpty)
        XCTAssertTrue(m.hits(in: "ANYTHING AT ALL").isEmpty)
    }

    func testOccurrencesAreCountedOncePerDistinctSpan() {
        let m = matcher("Tarkel")
        let hit = m.hits(in: "A. S. TARKEL and later again A. S. TARKEL").first
        XCTAssertEqual(hit?.count, 2)
    }

    // MARK: - Row filtering

    func testFilterSearchesCounselColumnOnly() {
        let rows = [
            BoardRow(caseNumber: "WP/1/2026",
                     caseName: "RAMESH S/O TARKEL vs STATE",     // party shares the surname
                     counsels: "MR. P. Q. FIKTORNE"),
            BoardRow(caseNumber: "WP/2/2026",
                     caseName: "SOMEONE ELSE vs STATE",
                     counsels: "MR. A. S. TARKEL for petitioner"),
            BoardRow(caseNumber: "WP/3/2026", caseName: "X vs Y", counsels: ""),
        ]
        let out = rows.filtered(by: matcher("A. S. Tarkel"))
        XCTAssertEqual(out.map(\.caseNumber), ["WP/2/2026"],
                       "a party sharing the surname must not produce a listing, and an "
                       + "empty counsel column can never match")
        XCTAssertEqual(out.first?.matchedNames, ["A. S. Tarkel"])
    }

    func testEmptyMatcherPassesEveryRowThrough() {
        let rows = [BoardRow(caseNumber: "WP/1/2026", counsels: "ANYONE")]
        XCTAssertEqual(rows.filtered(by: matcher("")).count, 1,
                       "no watched names means show the whole board, not an empty board")
    }
}
