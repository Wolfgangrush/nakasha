import Foundation

/// Front-door orchestration for the product. Pure value-type service: given the
/// user's intent, produce filtered rows and a printable PDF/CSV. Never lets one
/// bad PDF take down the rest of a batch.
public struct BoardService {

    public struct Input: Sendable {
        public var pdfURLs: [URL]
        public var watchedNamesText: String
        public var showSerial: Bool
        public var showSection: Bool
        public var boardDate: String           // caller-supplied; deterministic output

        public init(pdfURLs: [URL],
                    watchedNamesText: String,
                    showSerial: Bool = true,
                    showSection: Bool = true,
                    boardDate: String = "") {
            self.pdfURLs = pdfURLs
            self.watchedNamesText = watchedNamesText
            self.showSerial = showSerial
            self.showSection = showSection
            self.boardDate = boardDate
        }
    }

    public struct Result: Sendable {
        public var rows: [BoardRow]
        public var boards: [ParsedBoard]
        public var warnings: [String]

        public init(rows: [BoardRow] = [],
                    boards: [ParsedBoard] = [],
                    warnings: [String] = []) {
            self.rows = rows
            self.boards = boards
            self.warnings = warnings
        }
    }

    public init() {}

    /// Build the subtitle string once, here, so the renderer stays format-agnostic.
    public func subtitle(for result: Result, input: Input) -> String {
        let dates = Self.collectDates(result.boards)
        let datePart = dates.isEmpty
            ? (input.boardDate.isEmpty ? "Date not detected" : input.boardDate)
            : dates.joined(separator: ", ")
        let watchedPart = input.watchedNamesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Watched: all matters (no filter)"
            : "Watched: \(input.watchedNamesText)"
        return "\(datePart)  -  \(result.boards.count) source file(s)  -  "
            + "\(result.rows.count) of \(result.boards.reduce(0) { $0 + $1.rows.count }) matched  -  \(watchedPart)"
    }

    public func run(_ input: Input) throws -> Result {
        guard !input.pdfURLs.isEmpty else {
            return Result()
        }

        var boards: [ParsedBoard] = []
        var warnings: [String] = []

        for url in input.pdfURLs {
            do {
                let extracted = try PDFTextExtractor.pages(of: url)

                // A page with no text layer yields no lines and therefore no matters. Name it.
                // Staying silent here is the one failure this product may not have: the page
                // looks identical to a page that genuinely held nothing. (01-PRD §8.)
                let unreadable = extracted.filter { !$0.hasTextLayer }.map(\.number)
                if !unreadable.isEmpty {
                    let list = unreadable.map(String.init).joined(separator: ", ")
                    let plural = unreadable.count == 1 ? "page \(list) has" : "pages \(list) have"
                    warnings.append(
                        "\(url.lastPathComponent): \(plural) no text layer and could not be read. "
                        + "Check \(unreadable.count == 1 ? "that page" : "those pages") against the board by eye."
                    )
                }

                let lines = extracted.flatMap { page in
                    page.lines.map { LayoutLine(text: $0.text, page: page.number, y: $0.y) }
                }
                var parsed = FormatDetector.parse(lines: lines, sourceName: url.lastPathComponent)
                // Stamp provenance now, while we still know which file these rows came from.
                // The click-through needs it to open the right document.
                let name = url.lastPathComponent
                parsed.rows = parsed.rows.map { row -> BoardRow in
                    var copy = row
                    copy.sourceFile = name
                    return copy
                }
                boards.append(parsed)
            } catch let err as PDFTextExtractor.ExtractError {
                warnings.append("\(url.lastPathComponent): \(err.localizedDescription)")
            } catch {
                warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Even if every PDF failed, we still want to return the warnings.
        let merged = BoardMerger.merge(boards)
        let matcher = NameMatcher(entries: NameMatcher.entries(fromUserText: input.watchedNamesText))
        let filtered: [BoardRow]
        if matcher.isEmpty {
            filtered = merged
        } else {
            filtered = merged.filtered(by: matcher)
        }

        // Stamp positions last, so every row the interface shows has a unique identity even
        // when two connected matters share court, serial, case number and page.
        let numbered = filtered.enumerated().map { index, row -> BoardRow in
            var copy = row
            copy.ordinal = index
            return copy
        }

        return Result(rows: numbered, boards: boards, warnings: warnings)
    }

    public func writePDF(_ result: Result, input: Input, to url: URL) throws {
        let opts = BoardPDFRenderer.Options(
            title: "NAKASHA — My Matters",
            subtitle: subtitle(for: result, input: input),
            showSerial: input.showSerial,
            showSection: input.showSection,
            landscape: true,
            pageSize: CGSize(width: 842, height: 595)  // A4 landscape
        )
        let renderer = BoardPDFRenderer(options: opts)
        try renderer.render(rows: result.rows, to: url)
    }

    public func writeCSV(_ result: Result, to url: URL) throws {
        try CSVExporter.write(rows: result.rows, to: url, includeSerial: true)
    }

    // MARK: - Helpers

    private static func collectDates(_ boards: [ParsedBoard]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for b in boards {
            let d = b.boardDate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !d.isEmpty else { continue }
            if seen.insert(d).inserted {
                ordered.append(d)
            }
        }
        return ordered
    }
}
