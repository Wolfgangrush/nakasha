import Foundation

/// A court's board layout. One conformer per published format.
///
/// Adding a new High Court means adding a type here — the app, the renderer and the
/// matcher never change. `confidence` lets the detector pick between formats without
/// the user having to know what their registry calls its own export.
public protocol BoardFormat {
    /// Shown to the user, e.g. "HCBA Daily Board".
    var name: String { get }
    /// 0 = definitely not this format, 1 = certain. Judged from the document's own text.
    func confidence(for lines: [LayoutLine]) -> Double
    func parse(lines: [LayoutLine], sourceName: String) -> ParsedBoard
}

public enum BoardText {

    /// Case numbers as registries actually print them:
    /// `WP/7117/2091` · `APPP(ST)/7088/2` · `APEALST/7099/20` · `CRI.APL/7060/25`
    ///
    /// The year is allowed to be 1–4 digits because HCBA's export truncates the whole
    /// field at a fixed width and will happily cut a year in half. Dropping those rows
    /// would silently lose matters, which is the one failure mode that matters here.
    public static let caseNumber = try! NSRegularExpression(
        pattern: "\\b([A-Z][A-Z0-9()./]{0,14}?)/(\\d{1,6})/(\\d{1,4})\\b"
    )

    /// `12   WP/7034/2091 …` — a numbered matter at the top of its block.
    public static let itemRow = try! NSRegularExpression(
        pattern: "^(\\s*)(\\d{1,4})\\s+([A-Z][A-Z0-9()./]{0,14}?/\\d{1,6}/\\d{1,4})\\b"
    )

    /// A case number sitting at the start of an indented line — a connected matter.
    public static let indentedCase = try! NSRegularExpression(
        pattern: "^(\\s*)([A-Z][A-Z0-9()./]{0,14}?/\\d{1,6}/\\d{1,4})\\b"
    )

    public static let courtHead = try! NSRegularExpression(
        pattern: "IN THE COURT OF\\s+(.+?)\\s*$", options: [.caseInsensitive]
    )

    public static let coramContinuation = try! NSRegularExpression(
        pattern: "^\\s*(?:AND\\s+)?(HON'?BLE\\s+.+?)\\s*$", options: [.caseInsensitive]
    )

    public static let courtNumber = try! NSRegularExpression(
        pattern: "^\\s*COURT\\s+NO\\.?\\s*([A-Z0-9]+)\\s*$", options: [.caseInsensitive]
    )

    public static let justice = try! NSRegularExpression(
        pattern: "HON'?BLE\\s+(?:SHRI\\s+|SMT\\.?\\s+|KUM\\.?\\s+|MS\\.?\\s+|MRS\\.?\\s+)?(?:JUSTICE\\s+)?(.+?)\\s*$",
        options: [.caseInsensitive]
    )

    public static let category = try! NSRegularExpression(
        pattern: "\\[(Civil|Criminal)\\]", options: [.caseInsensitive]
    )

    public static let dateLine = try! NSRegularExpression(
        pattern: "(\\d{1,2}[./-]\\d{1,2}[./-]\\d{2,4})"
    )

    public static func firstMatch(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, options: [],
                                       range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            let r = m.range(at: idx)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    public static func contains(_ regex: NSRegularExpression, _ text: String) -> Bool {
        firstMatch(regex, text) != nil
    }

    /// Remove counsel names the board has printed more than once in one cell.
    ///
    /// A matter with ten tagged applications carries the counsel block of EVERY one of
    /// them, and those are usually the same advocates. Left alone, one matter's counsel
    /// column ran to several hundred words — it filled three pages of the export on its
    /// own, and it is the same six names over and over. Order is preserved and the first
    /// occurrence of each name is kept, so nothing the board says is lost; only the
    /// repetition goes.
    public static func dedupeNames(_ text: String) -> String {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ",·"))
        var seen = Set<String>()
        var kept: [String] = []
        for part in parts {
            let trimmed = collapse(part)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.uppercased()
            if seen.insert(key).inserted { kept.append(trimmed) }
        }
        return kept.joined(separator: ", ")
    }

    /// Collapse the padding a fixed-width column leaves behind, without touching the
    /// single spaces that are real content.
    public static func collapse(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Keyword tests must run against the COLLAPSED line, never the raw grid row.
    ///
    /// The grid preserves page geometry, which means several blank columns can sit
    /// between two words of the same phrase. A literal pattern like `IN THE COURT OF`
    /// then fails against `IN  THE   COURT   OF` and every matter on the page loses its
    /// court. Slice columns from the raw line; recognise words from this.
    public static func flat(_ line: LayoutLine) -> String {
        collapse(line.text)
    }

    /// Lines that carry no matter data in any published format: rules of the grid, page
    /// furniture, separators. Dropping these keeps every parser's state machine honest.
    public static func isFurniture(_ line: LayoutLine) -> Bool {
        let t = flat(line)
        if t.isEmpty { return true }
        if t.allSatisfy({ $0 == "%" || $0 == "-" || $0 == "=" || $0 == "*" || $0 == "_" }) { return true }
        if t.range(of: "^\\d{1,4}\\s*/\\s*\\d{1,4}$", options: .regularExpression) != nil { return true }
        if t.range(of: "^\\d{1,4}$", options: .regularExpression) != nil { return true }
        if t.uppercased().hasPrefix("PAGE:") { return true }
        if t.uppercased().hasPrefix("C.R. NO") { return true }
        return false
    }
}
