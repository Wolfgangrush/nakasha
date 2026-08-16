import Foundation

/// One matter as it appears on a board, in the five columns a lawyer actually needs
/// standing outside the court hall.
///
/// Field names deliberately mirror the printed board, not a database schema:
/// *Name of Court · Number · Name of Case · Name of the counsels · Office note given.*
public struct BoardRow: Equatable, Codable, Sendable {

    /// "COURT NO. A — HON'BLE SHRI JUSTICE ARJUN T. TESTKAR" / "REGISTRAR SHRI T.N. SAMPLEKAR".
    /// Whatever the board itself printed as the court head — never inferred.
    public var court: String

    /// Serial number on the board (the "when will I be called" number). May be empty for
    /// a connected matter that shares its parent's serial.
    public var serial: String

    /// Case number as printed, e.g. `WP/7117/2091`.
    public var caseNumber: String

    /// Case numbers tagged *with* this matter (connected civil applications etc.),
    /// in board order. Rendered as "with CAW/7052/2091" under the case number.
    public var connectedCaseNumbers: [String]

    /// Parties as printed. HCBA's export truncates party names at a fixed width and that
    /// truncation is not recoverable — the board is reproduced, never guessed at.
    public var caseName: String

    /// Full counsel text for the matter, both sides, as printed.
    public var counsels: String

    /// The office note / office objection / purpose line — the `:`-note on an HCBA board,
    /// the flush-left `FOR …` block on a High Court daily main causelist.
    public var officeNote: String

    /// Board section the matter sat under: PART HEARD / FOR ADMISSION / FOR ORDERS …
    public var section: String

    /// `[Civil]` / `[Criminal]` where the board prints it.
    public var category: String

    /// Page of the source PDF the matter was read from (1-based). For "show me where".
    public var sourcePage: Int

    /// Which watched names matched this row. Empty when no filter was applied.
    public var matchedNames: [String]

    /// True when the watched name was found somewhere OTHER than the counsel column.
    ///
    /// The row is still returned — that is the point. Restricting the search to the counsel
    /// column is a precision optimisation, and it guards the one error this product may not
    /// make: if a parse defect misfiles counsel text into the party column, a counsel-only
    /// search returns nothing and the advocate reads a clean empty table as "I am not on
    /// this board". So the row survives, flagged, and the interface marks it for verification.
    public var matchedOutsideCounselColumn: Bool

    /// File name of the PDF this row was read from.
    ///
    /// Needed because the advocate can load several boards at once, and clicking a result
    /// has to open the RIGHT document at the right page. Without it the click-through jumps
    /// into whichever PDF happens to be on screen and shows the advocate a different matter
    /// with the same page number — which reads as the app being wrong about their listing.
    /// File name only, never the full path: paths leak the user's disk layout.
    public var sourceFile: String

    /// Position in the result set. Part of `id` only; never displayed, never exported.
    ///
    /// Without it, two connected matters under one court on one page — both carrying an
    /// empty serial and the same case number — produce identical identities, and a SwiftUI
    /// `Table`/`ForEach` silently drops the duplicate. That is a matter disappearing from the
    /// advocate's list because of the view layer, where no parser test is looking.
    public var ordinal: Int

    public init(court: String = "",
                serial: String = "",
                caseNumber: String = "",
                connectedCaseNumbers: [String] = [],
                caseName: String = "",
                counsels: String = "",
                officeNote: String = "",
                section: String = "",
                category: String = "",
                sourcePage: Int = 0,
                matchedNames: [String] = [],
                matchedOutsideCounselColumn: Bool = false,
                sourceFile: String = "",
                ordinal: Int = 0) {
        self.court = court
        self.serial = serial
        self.caseNumber = caseNumber
        self.connectedCaseNumbers = connectedCaseNumbers
        self.caseName = caseName
        self.counsels = counsels
        self.officeNote = officeNote
        self.section = section
        self.category = category
        self.sourcePage = sourcePage
        self.matchedNames = matchedNames
        self.matchedOutsideCounselColumn = matchedOutsideCounselColumn
        self.sourceFile = sourceFile
        self.ordinal = ordinal
    }

    /// Everything on the row that is NOT the counsel column, for the fallback search.
    /// Searched only after the counsel column has produced nothing — see `filtered(by:)`.
    public var textOutsideCounselColumn: String {
        [caseName, officeNote, section].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Case number plus any connected matters, for the "Number" column.
    public var numberColumn: String {
        guard !connectedCaseNumbers.isEmpty else { return caseNumber }
        return caseNumber + "\nwith " + connectedCaseNumbers.joined(separator: ", ")
    }

    /// A row carrying no case number is structural debris, not a matter.
    public var isMeaningful: Bool {
        !caseNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension BoardRow: Identifiable {
    /// Stable across a re-parse of the same board. The case number alone is not enough:
    /// the same matter can be listed before two courts on one day (and is, on part-heard
    /// days), and collapsing those into one identity would hide a listing.
    public var id: String { "\(court)|\(serial)|\(caseNumber)|\(sourcePage)|\(ordinal)" }
}

/// Everything read out of one source PDF.
public struct ParsedBoard: Equatable, Codable, Sendable {
    /// Human name of the detected format, e.g. "HCBA Daily Board".
    public var formatName: String
    /// Title line off the document, e.g. "DAILY BOARD FOR: 17.07.2091 (Friday)".
    public var title: String
    /// Board date as printed, if the document states one.
    public var boardDate: String
    /// Source file name (never the full path — paths leak the user's disk layout).
    public var sourceName: String
    public var rows: [BoardRow]

    public init(formatName: String = "",
                title: String = "",
                boardDate: String = "",
                sourceName: String = "",
                rows: [BoardRow] = []) {
        self.formatName = formatName
        self.title = title
        self.boardDate = boardDate
        self.sourceName = sourceName
        self.rows = rows
    }
}
