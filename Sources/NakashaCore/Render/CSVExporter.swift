import Foundation

public enum CSVExporter {
    /// Builds an RFC4180 CSV. Every field is quoted, internal quotes are doubled, and
    /// embedded newlines are preserved inside the quoted field.
    public static func csv(rows: [BoardRow], includeSerial: Bool = true) -> String {
        var out = ""
        // Header
        var headers: [String] = ["Court"]
        if includeSerial { headers.append("Sr.") }
        // Column ORDER matches the exported PDF and 01-PRD §11 exactly — Court · Sr. ·
        // Case No. · Party · Office note · Counsel — so the two exports can be read side by
        // side without the reader having to re-find a column.
        headers.append(contentsOf: ["Case No.", "Party", "Office note", "Counsel",
                                    "Section", "Category", "Source page", "Matched",
                                    "Verify"])
        out += headers.map { quote($0) }.joined(separator: ",") + "\r\n"

        for row in rows {
            var fields: [String] = [row.court]
            if includeSerial { fields.append(row.serial) }
            fields.append(contentsOf: [
                row.numberColumn,
                row.caseName,
                row.officeNote,
                row.counsels,
                row.section,
                row.category,
                String(row.sourcePage),
                row.matchedNames.joined(separator: "; "),
                // Carried into the export because the advocate reads the exported sheet in
                // court, away from the app, and a row matched outside the counsel column is
                // exactly the one they need to look twice at.
                row.matchedOutsideCounselColumn ? "verify" : ""
            ])
            out += fields.map { quote($0) }.joined(separator: ",") + "\r\n"
        }
        return out
    }

    public static func write(rows: [BoardRow], to url: URL, includeSerial: Bool = true) throws {
        let data = csv(rows: rows, includeSerial: includeSerial)
        guard let bytes = data.data(using: .utf8) else {
            throw NSError(domain: "CSVExporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Encoding to UTF-8 failed"])
        }
        try bytes.write(to: url, options: .atomic)
    }

    // MARK: - Quoting

    /// RFC4180: wrap in double quotes; escape internal double quotes by doubling them.
    private static func quote(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
