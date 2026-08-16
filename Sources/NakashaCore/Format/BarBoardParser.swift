import Foundation

/// Bar-association **Daily Board** (the "final board").
///
/// Layout, per matter:
///
/// ```
/// 12   WP/7034/2091 A.B. TRADERS # FIKTEXO INDU         P. P. TESVAL DEMORA M. FIKTUS
///      :ORDER REGARDING FILING OF CAW CORRECT A         TESTURA H. MOKARA #
///      ND DETAILED ADD OF R.NO.2 TO 4.(3RD DEFAU
///      LT)
///      CAW/7021/2091 A.B. TRADERS # FIKTEXO IND         P. P. TESVAL #
/// ```
///
/// Three things make this format hostile, and each is handled explicitly:
///
/// 1. **Both columns are hard-wrapped at a fixed character width**, mid-word. The left
///    block must therefore be rejoined by *raw concatenation of the column slice* —
///    joining with a space would turn `CORRECT` into `CORREC T`. That is why this parser
///    works on a character grid rather than on extracted text.
/// 2. **Party names are truncated** by the export at a fixed width. That loss is in the
///    source and is reproduced as printed; it is never "completed" by guesswork.
/// 3. **Connected matters** (the CAW/APPA tagged to a main matter) follow as indented
///    case rows and belong to the matter above, not to a matter of their own.
public struct BarBoardParser: BoardFormat {

    public let name = "Bar Association Daily Board"

    public init() {}

    public func confidence(for lines: [LayoutLine]) -> Double {
        let head = lines.prefix(400).map { BoardText.flat($0) }.joined(separator: "\n").uppercased()
        var score = 0.0
        if head.contains("DAILY BOARD") { score += 0.5 }
        if head.contains("HCBA") || head.contains("BAR ASSOCIATION") { score += 0.2 }
        if head.contains("IN THE COURT OF") { score += 0.15 }
        // The `#` party separator is this format's fingerprint; the High Court's own
        // causelist never uses it.
        let hashRows = lines.prefix(600).filter { $0.text.contains("#") }.count
        if hashRows >= 5 { score += 0.3 }
        if head.contains("DAILY MAIN CAUSELIST") { score -= 0.6 }
        return max(0, min(1, score))
    }

    public func parse(lines: [LayoutLine], sourceName: String) -> ParsedBoard {
        var board = ParsedBoard(formatName: name, sourceName: sourceName)
        board.title = lines.prefix(60).map { BoardText.flat($0) }
            .first { $0.uppercased().contains("DAILY BOARD") } ?? ""
        if let m = BoardText.firstMatch(BoardText.dateLine, board.title) { board.boardDate = m[1] }

        // One gutter for the whole document: this format keeps the same column geometry
        // on every page, and a per-page estimate would wobble on sparse pages.
        //
        // Measured ONLY over matter rows. Notices, coram headers and footnotes run the
        // full page width; including them buries the channel and the parser falls back
        // to a guessed column, which silently mixes counsel text into the case name.
        let matterLines = lines.filter {
            BoardText.contains(BoardText.itemRow, $0.text)
                || BoardText.contains(BoardText.indentedCase, $0.text)
        }
        let gutter = ColumnDetector.primaryGutter(in: matterLines)
            ?? Gutter(start: defaultGutter(lines), end: defaultGutter(lines) + 1)

        // The RIGHT EDGE OF THE FIELD BOX, observed rather than assumed.
        //
        // The rejoin rule below asks "did this line have trailing padding inside the
        // box?" — padding means the export broke the line naturally and a space belongs;
        // no padding means it chopped a word in half. Measuring that against the gutter
        // is wrong: the gutter starts a couple of columns past where text actually ends,
        // so EVERY line looks padded and every chopped word gains a space
        // (`CORREC T`, `NOTIC E`, `APPELLA NT`). The true edge is the furthest any line
        // reaches inside the box.
        // Taken as the MODE, not the maximum: a long office note wraps many times and
        // every one of those wrapped lines ends on the box edge, so the edge is by far the
        // most common ending column. The maximum is set by whichever single line strayed
        // furthest — a heading, a stray notice — and would push the edge past the text.
        var edgeVotes: [Int: Int] = [:]
        for line in lines {
            guard let last = line.lastInkColumn, last < gutter.start,
                  let first = line.firstInkColumn, first < continuationLimit else { continue }
            edgeVotes[last, default: 0] += 1
        }
        let fieldEdge = 1 + (edgeVotes.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }?.key ?? (gutter.start - 1))

        var rows: [BoardRow] = []
        var court = ""
        var section = ""
        var open: OpenMatter? = nil

        func flush() {
            if let matter = open?.finish(court: court, section: section) {
                rows.append(matter)
            }
            open = nil
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1

            // --- court head ------------------------------------------------------
            if let m = BoardText.firstMatch(BoardText.courtHead, BoardText.flat(line)) {
                flush()
                var names = [BoardText.collapse(m[1])]
                // "AND HON'BLE SHRI JUSTICE …" on the following line is the same court.
                while index < lines.count,
                      let next = BoardText.firstMatch(BoardText.coramContinuation,
                                                     BoardText.flat(lines[index])),
                      !BoardText.contains(BoardText.caseNumber, BoardText.flat(lines[index])) {
                    names.append(BoardText.collapse(next[1]))
                    index += 1
                }
                court = names.joined(separator: " AND ")
                section = ""
                continue
            }

            if BoardText.isFurniture(line) { continue }

            let left = line.slice(0, gutter.start)
            let right = BoardText.collapse(line.slice(gutter.end))
            let indent = left.firstInkColumnOfString

            // --- new numbered matter ---------------------------------------------
            if let m = BoardText.firstMatch(BoardText.itemRow, left) {
                flush()
                let caseStart = (m[1] as NSString).length + (m[2] as NSString).length
                let actualStart = left.range(of: m[3]).map {
                    left.distance(from: left.startIndex, to: $0.lowerBound)
                } ?? caseStart
                open = OpenMatter(serial: m[2],
                                  caseNumber: m[3],
                                  fieldStart: actualStart,
                                  page: line.page)
                open?.appendLeft(line, boxEnd: fieldEdge)
                open?.appendRight(right)
                continue
            }

            // --- connected matter (indented case number, still carries `#`) -------
            if indent != nil, indent! > 0,
               let m = BoardText.firstMatch(BoardText.indentedCase, left),
               left.contains("#") {
                open?.addConnected(m[2])
                open?.appendRight(right)
                continue
            }

            // --- section band ------------------------------------------------------
            if let heading = sectionHeading(line, gutter: gutter) {
                flush()
                section = heading
                continue
            }

            // --- continuation of the open matter -----------------------------------
            if open != nil, let indent, indent < continuationLimit {
                open?.appendLeft(line, boxEnd: fieldEdge)
                open?.appendRight(right)
                continue
            }

            // Counsel text can spill onto a line whose left column is empty.
            if open != nil, indent == nil, !right.isEmpty {
                open?.appendRight(right)
                continue
            }
        }
        flush()

        board.rows = rows.filter(\.isMeaningful)
        return board
    }

    /// Continuation text of a matter never starts this far in; anything beyond is a
    /// centred heading or page furniture.
    private let continuationLimit = 15

    private func defaultGutter(_ lines: [LayoutLine]) -> Int {
        let width = lines.map(\.width).max() ?? 80
        return Int(Double(width) * 0.55)
    }

    private func sectionHeading(_ line: LayoutLine, gutter: Gutter) -> String? {
        guard let indent = line.firstInkColumn, indent >= continuationLimit else { return nil }
        let t = BoardText.flat(line).trimmingCharacters(in: CharacterSet(charactersIn: "*- "))
        guard !t.isEmpty, !BoardText.contains(BoardText.caseNumber, t) else { return nil }
        let upper = t.uppercased()
        let known = upper.hasPrefix("FOR ") || upper.contains("PART HEARD")
            || upper.contains("PART-HEARD") || upper.hasSuffix("MATTERS")
            || upper.contains("SIDE MATTERS") || upper.contains("FINAL HEARING")
        return known ? BoardText.collapse(t) : nil
    }
}

// MARK: - Matter accumulator

/// Accumulates the column slices of one matter while its lines stream past.
private struct OpenMatter {
    let serial: String
    let caseNumber: String
    /// Column where this matter's left-hand field box begins. Every continuation line is
    /// sliced from here so that a leading space — which is real content on a hard wrap —
    /// survives.
    let fieldStart: Int
    let page: Int

    private var leftRaw = ""
    private var rightParts: [String] = []
    private var connected: [String] = []
    /// Once a connected matter has been seen, the parent's own left field is finished.
    /// The board always prints the office note before the tagged matters, and the tagged
    /// rows carry their own stray `:` fragments — folding those in appended a phantom
    /// colon to the note.
    private var leftClosed = false

    init(serial: String, caseNumber: String, fieldStart: Int, page: Int) {
        self.serial = serial
        self.caseNumber = caseNumber
        self.fieldStart = fieldStart
        self.page = page
    }

    /// Rejoin one line of the hard-wrapped left field.
    ///
    /// The field is a fixed-width box: the export chops it at exactly `boxEnd`, mid-word
    /// and without a hyphen. So the break tells us how to rejoin:
    ///
    /// * slice runs to the box edge with **no trailing space** -> the chop happened
    ///   mid-token; concatenate with NOTHING (`CORREC` + `T` = `CORRECT`).
    /// * slice has **trailing padding** -> the line ended naturally; concatenate with one
    ///   space (`THE RESP` + `. ). (FRESH)` keeps its own leading punctuation).
    ///
    /// Getting this backwards is not cosmetic: it turns `ORDERS` into `O RDERS` and
    /// `DETAILED` into `DET AILED`, which then fails any search the advocate runs.
    mutating func appendLeft(_ line: LayoutLine, boxEnd: Int) {
        guard !leftClosed else { return }
        // Never slice away ink: if a line's text starts left of the expected box, take it
        // from wherever it actually starts.
        let start = min(fieldStart, line.firstInkColumn ?? fieldStart)
        let raw = line.slice(start, boxEnd)
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Trailing padding INSIDE the box is the signal that the export broke this line
        // at a natural boundary; a box filled to its edge was chopped mid-token.
        let padded = raw.hasSuffix(" ")
        var piece = raw
        while piece.hasSuffix(" ") { piece.removeLast() }

        // Did this line run all the way to the right edge of the field box?
        //
        // The export chops the field at a fixed width, mid-word and without a hyphen, so
        // a line that FILLS the box was cut inside a token and must be rejoined with
        // nothing (`CORREC` + `T` = `CORRECT`). A line that stops short ended naturally
        // and needs a space. Getting this backwards yields `O RDERS` and `DET AILED`,
        // which then fails every search the advocate runs.
        //
        // The test is the position of the last ink, not the presence of padding: the page
        // is not truly monospaced, so a chopped line's final character lands within a
        // column or two of the edge rather than exactly on it.
        leftRaw += padded ? piece + " " : piece
    }

    mutating func appendRight(_ text: String) {
        guard !text.isEmpty, text != "--" else { return }
        rightParts.append(text)
    }

    mutating func addConnected(_ number: String) {
        leftClosed = true
        let clean = number.uppercased()
        guard clean != caseNumber.uppercased(), !connected.contains(clean) else { return }
        connected.append(clean)
    }

    func finish(court: String, section: String) -> BoardRow? {
        // The first line's slice still carries the case number itself — strip it once.
        var body = leftRaw
        if let r = body.range(of: caseNumber) {
            body = String(body[r.upperBound...])
        }

        var parties = body
        var note = ""
        if let colon = body.firstIndex(of: ":") {
            parties = String(body[body.startIndex..<colon])
            note = String(body[body.index(after: colon)...])
        }

        var caseName = BoardText.collapse(parties)
        // `PETITIONER # RESPONDENT` is this format's party separator.
        if let hash = caseName.firstIndex(of: "#") {
            let pet = caseName[caseName.startIndex..<hash].trimmingCharacters(in: CharacterSet(charactersIn: " -."))
            let resp = caseName[caseName.index(after: hash)...].trimmingCharacters(in: CharacterSet(charactersIn: " -."))
            caseName = resp.isEmpty ? pet : "\(pet) vs \(resp)"
        }

        var counsels = BoardText.collapse(rightParts.joined(separator: " "))
        // `#` also splits petitioner-side from respondent-side counsel. Keep both, but
        // print the boundary in words so the column is readable at a glance. Connected
        // matters contribute their own `#`, so only the FIRST one is the side boundary;
        // the rest are separators between the tagged matters' counsel blocks.
        if let hash = counsels.firstIndex(of: "#") {
            let forPet = counsels[counsels.startIndex..<hash].trimmingCharacters(in: .whitespaces)
            var forResp = String(counsels[counsels.index(after: hash)...])
            forResp = BoardText.collapse(forResp.replacingOccurrences(of: "#", with: ", "))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            counsels = [forPet.isEmpty ? nil : BoardText.dedupeNames(forPet),
                        forResp.isEmpty ? nil : "for respondent: " + BoardText.dedupeNames(forResp)]
                .compactMap { $0 }.joined(separator: " · ")
        } else {
            counsels = BoardText.dedupeNames(counsels)
        }

        var category = ""
        if let m = BoardText.firstMatch(BoardText.category, caseName) {
            category = m[1]
            caseName = BoardText.collapse(caseName.replacingOccurrences(of: m[0], with: ""))
        }

        return BoardRow(court: court,
                        serial: serial,
                        caseNumber: caseNumber.uppercased(),
                        connectedCaseNumbers: connected,
                        caseName: caseName,
                        counsels: counsels,
                        officeNote: BoardText.collapse(note),
                        section: section,
                        category: category,
                        sourcePage: page)
    }
}

extension String {
    var firstInkColumnOfString: Int? {
        for (i, ch) in Array(self).enumerated() where ch != " " { return i }
        return nil
    }
}
