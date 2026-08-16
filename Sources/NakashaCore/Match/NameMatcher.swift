import Foundation

/// Matches the advocate names a user is watching against the counsel text of a matter.
///
/// Two things this deliberately gets right, because getting them wrong is how a lawyer
/// misses a listing or chases a ghost one:
///
/// 1. **Initials are noise.** `A. S. Tarkel`, `A.S. TARKEL`, `A S TARKEL` and `A.S.Tarkel`
///    are the same person. Registries are not consistent, so the matcher is.
/// 2. **A surname after a relationship marker is a *party*, not counsel.** In
///    `BALU S/O TESTMUKH` the word after `S/O` is the father's name. Matching it would
///    flag a matter the watched advocate has nothing to do with. Those are skipped.
///
/// Word boundaries are enforced, so `Tarkel` never matches `Tarkele`.
public struct NameMatcher: Sendable {

    public struct Entry: Sendable, Equatable {
        /// What to show the user, e.g. "A. S. Tarkel".
        public let display: String
        /// Every spelling to look for. The display name is always included.
        public let aliases: [String]

        public init(display: String, aliases: [String] = []) {
            self.display = display
            var all = [display]
            all.append(contentsOf: aliases)
            self.aliases = all.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    public struct Hit: Sendable, Equatable {
        public let display: String
        /// The exact span found in the document — so the user can see what matched.
        public let matched: String
        /// Distinct occurrences within the searched text.
        public let count: Int
    }

    private let compiled: [(display: String, patterns: [NSRegularExpression])]

    /// Compiles one entry's patterns, picking the mode from what the user typed.
    ///
    /// An entry carrying `;`-separated alternates is the user's explicit opt-in to
    /// precision (01-PRD §7) and keeps the strict, bounded regex. A plain single name is
    /// matched **loosely**, because the board hard-wraps mid-word (`VANKOLE` prints as
    /// `VANK OLE`) and truncates at a fixed field width (`VERNEKAR` prints as `VERNEKA`).
    /// Strict matching returns nothing on both, and the advocate concludes — wrongly —
    /// that they are not listed. Over-inclusion costs a click; a miss is unrecoverable.
    public init(entries: [Entry]) {
        compiled = entries.compactMap { entry in
            let patterns: [NSRegularExpression]
            if entry.aliases.count > 1 {
                patterns = entry.aliases.compactMap { NameMatcher.regex(for: $0) }
            } else if let sole = entry.aliases.first {
                patterns = NameMatcher.loosePatterns(for: sole)
            } else {
                patterns = []
            }
            return patterns.isEmpty ? nil : (entry.display, patterns)
        }
    }

    /// Tokens that are never a search term. Initials and honorifics match hundreds of
    /// unrelated rows; so do the joining words in a firm name. Both drown the result set,
    /// which fails the advocate the same way a miss does — they stop trusting the list.
    static let noiseTokens: Set<String> = [
        "MR", "MRS", "MS", "SMT", "SHRI", "SHRIMATI", "KUM", "KUM.",
        "DR", "ADV", "ADVOCATE", "SR", "JR", "M/S",
        // Joining words: a user typing a firm name ("Vankole and Associates") would
        // otherwise compile `\bAND` and match most of the board.
        "AND", "FOR", "THE", "VS", "ORS", "ANR",
    ]

    /// The loose pattern set for one typed name: one regex per significant token, ORed.
    ///
    /// Any single token matching is a hit. That is the whole of "loose" — a surname alone
    /// must find the matter, and typing a full name must not require every token to be
    /// present, in order, adjacent. Advocates type what they remember, and what they
    /// remember is rarely the printed form.
    static func loosePatterns(for name: String) -> [NSRegularExpression] {
        let tokens = name
            .components(separatedBy: CharacterSet(charactersIn: ". ,\t\u{00A0}"))
            .filter { !$0.isEmpty }
        let significant = tokens.filter {
            $0.count >= 3 && !noiseTokens.contains($0.uppercased())
        }
        guard !significant.isEmpty else {
            // Nothing but initials. Fall back to the strict regex rather than returning
            // an empty pattern list, which would read to the user as "you are not listed".
            return [regex(for: name)].compactMap { $0 }
        }
        return significant.compactMap { loosePattern(for: $0) }
    }

    /// One token's regex: a required head, then a tail that degrades one character at a
    /// time.
    ///
    /// The leading `\b` stays — a field is truncated at its END, never its start, so a
    /// surname must not match mid-word (`Tarkel` must not hit `STARKEL`). There is
    /// deliberately **no trailing** `\b`: that is exactly what makes a truncated printed
    /// form fail, and failing is the one thing this matcher may not do. The separator
    /// between characters absorbs a hard wrap that split the surname, and is bounded so a
    /// pattern can never match letters scattered across a whole line.
    static func loosePattern(for token: String) -> NSRegularExpression? {
        let chars = Array(token)
        let n = chars.count
        guard n > 0 else { return nil }
        let sep = "[\\s.\u{00A0}]{0,2}"
        let required = min(n, max(4, Int(ceil(Double(n) * 0.6))))

        var pattern = "\\b"
        for i in 0..<required {
            if i > 0 { pattern += sep }
            pattern += NSRegularExpression.escapedPattern(for: String(chars[i]))
        }
        var openGroups = 0
        for j in required..<n {
            pattern += "(?:" + sep + NSRegularExpression.escapedPattern(for: String(chars[j]))
            openGroups += 1
        }
        pattern += String(repeating: ")?", count: openGroups)

        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    public var isEmpty: Bool { compiled.isEmpty }

    /// Build from free-typed user input: one name per line, `;`-separated aliases allowed.
    ///
    ///     P. R. Testmukh; Testmukh P R
    ///     Neelima Testri Samplekar
    ///
    /// Blank lines and `#` comments are ignored, so a user can keep notes in the box.
    public static func entries(fromUserText text: String) -> [Entry] {
        text.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let parts = line.components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let display = parts.first else { return nil }
            return Entry(display: display, aliases: Array(parts.dropFirst()))
        }
    }

    /// `A. S. Tarkel` -> `\bA\.?\s*S\.?\s*Tarkel\b`
    static func regex(for alias: String) -> NSRegularExpression? {
        let tokens = alias
            .components(separatedBy: CharacterSet(charactersIn: ". \t\u{00A0}"))
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        let body = tokens.map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "\\.?\\s*")
        return try? NSRegularExpression(pattern: "\\b" + body + "\\b",
                                        options: [.caseInsensitive])
    }

    private static let relationshipPrefix = try! NSRegularExpression(
        pattern: "(?:\\bS/O|\\bD/O|\\bW/O|\\bR/O|\\bC/O|\\bSON OF|\\bDAUGHTER OF|\\bWIFE OF)\\.?\\s*$",
        options: [.caseInsensitive]
    )

    /// All watched names present in `text`. Empty result means no hit — never a guess.
    public func hits(in text: String) -> [Hit] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var found: [Hit] = []

        for (display, patterns) in compiled {
            var spans: [NSRange] = []
            for pattern in patterns {
                pattern.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                    guard let range = match?.range else { return }
                    let lookBehindStart = max(0, range.location - 10)
                    let before = ns.substring(with: NSRange(location: lookBehindStart,
                                                            length: range.location - lookBehindStart))
                    let beforeRange = NSRange(location: 0, length: (before as NSString).length)
                    if NameMatcher.relationshipPrefix.firstMatch(in: before,
                                                                 options: [],
                                                                 range: beforeRange) != nil {
                        return      // father's / husband's name on a party, not the advocate
                    }
                    spans.append(range)
                }
            }
            guard !spans.isEmpty else { continue }
            let merged = NameMatcher.merge(spans)
            found.append(Hit(display: display,
                             matched: ns.substring(with: merged[0]),
                             count: merged.count))
        }
        return found
    }

    static func merge(_ spans: [NSRange]) -> [NSRange] {
        let sorted = spans.sorted { $0.location < $1.location }
        var out: [NSRange] = []
        for span in sorted {
            if var last = out.last, span.location <= last.location + last.length {
                last.length = max(last.length, span.location + span.length - last.location)
                out[out.count - 1] = last
            } else {
                out.append(span)
            }
        }
        return out
    }
}

public extension Array where Element == BoardRow {
    /// Keep only the matters where a watched name appears **in the counsel column**.
    ///
    /// Restricting the search to the counsel column is structural, not cosmetic: it is
    /// what stops a party who happens to share the advocate's surname from producing a
    /// false listing. A matter whose counsel column is blank can never match.
    func filtered(by matcher: NameMatcher) -> [BoardRow] {
        guard !matcher.isEmpty else { return self }
        return compactMap { row in
            // The counsel column first. A hit here is the clean case and is not flagged.
            let counselHits = matcher.hits(in: row.counsels)
            if !counselHits.isEmpty {
                var copy = row
                copy.matchedNames = counselHits.map(\.display)
                copy.matchedOutsideCounselColumn = false
                return copy
            }

            // Then everything else on the row. This exists because searching the counsel
            // column ALONE trades the permitted error for the forbidden one: it is a
            // precision optimisation, and the moment a parse defect misfiles counsel text
            // into the party column the advocate gets a clean, empty, wrong answer. So the
            // row is kept and flagged rather than dropped. The S/O–D/O–W/O guard inside
            // `hits(in:)` still suppresses a party's father's or husband's name, which is
            // what stops this from becoming noise.
            let elsewhere = matcher.hits(in: row.textOutsideCounselColumn)
            guard !elsewhere.isEmpty else { return nil }
            var copy = row
            copy.matchedNames = elsewhere.map(\.display)
            copy.matchedOutsideCounselColumn = true
            return copy
        }
    }
}
