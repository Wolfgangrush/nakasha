import Foundation
import CoreGraphics
import PDFKit

public enum PDFTextExtractor {
    public enum ExtractError: Error, LocalizedError {
        case unreadable(String)
        case imageOnly(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let m): return "Could not open PDF: \(m)"
            case .imageOnly(let m):  return m
            }
        }
    }

    /// Reads every page and returns a layout-aware page stream.
    public static func pages(of url: URL) throws -> [LayoutPage] {
        guard let doc = PDFDocument(url: url) else {
            throw ExtractError.unreadable(url.lastPathComponent)
        }
        guard doc.pageCount > 0 else {
            throw ExtractError.unreadable("\(url.lastPathComponent) has no pages")
        }

        var pages: [LayoutPage] = []
        var anyInk = false

        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            let glyphs = positionedGlyphs(on: page)
            if !glyphs.isEmpty { anyInk = true }
            // PDFKit page space is bottom-left origin; pass originTopLeft: false to match.
            let lines = LayoutGrid.lines(
                from: glyphs,
                page: pageIndex + 1,
                pageHeight: uprightHeight(of: page),
                originTopLeft: false
            )
            pages.append(LayoutPage(number: pageIndex + 1, lines: lines))
        }

        if !anyInk {
            throw ExtractError.imageOnly(
                "\(url.lastPathComponent) contains no extractable text. It appears to be a scanned image — please run OCR on it first."
            )
        }
        return pages
    }

    /// Convenience: flatten all pages to a single `[LayoutLine]` with sequential page numbers.
    public static func lines(of url: URL) throws -> [LayoutLine] {
        let p = try pages(of: url)
        return p.flatMap { page in
            page.lines.map { line in
                // Re-tag page number (defensive: LayoutGrid already tags, but this makes the
                // contract explicit if callers slice/reshuffle).
                LayoutLine(text: line.text, page: page.number, y: line.y)
            }
        }
    }

    // MARK: - Glyph extraction with rotation handling

    private static func positionedGlyphs(on page: PDFPage) -> [PositionedGlyph] {
        let media = page.bounds(for: .mediaBox)
        let rotation = page.rotation  // 0/90/180/270

        // PDFKit indexes characters by UTF-16 code unit: `numberOfCharacters` and
        // `characterBounds(at:)` both speak UTF-16. Swift's `String.count` and
        // `index(_:offsetBy:)` speak grapheme clusters. Mixing the two desynchronises the
        // character stream from the position stream the moment the page contains anything
        // outside the basic set, and every glyph after that point lands in the wrong
        // column — the text comes out shuffled rather than obviously broken, which is the
        // worst kind of wrong for a cause list.
        //
        // Walking an NSString by code unit also removes an O(n^2): `index(startIndex,
        // offsetBy: i)` re-walks the whole string on every character.
        guard let raw = page.string, !raw.isEmpty else { return [] }
        let ns = raw as NSString
        guard ns.length > 0 else { return [] }

        var glyphs: [PositionedGlyph] = []
        glyphs.reserveCapacity(ns.length)

        // PDFKit indexes `characterBounds(at:)` by DRAWN GLYPH, but `page.string` also
        // contains the newlines PDFKit inserts between lines — and a newline draws
        // nothing, so it consumes no box. `numberOfCharacters` counts the newlines, which
        // makes the two look aligned when they are not.
        //
        // Verified against a real registry export: string index 41 is 'Y' (last letter of
        // DAILY) but bounds slot 41 is the SPACE that follows it, and by the third line
        // the drift had moved word-final letters onto the next line entirely. The text
        // came back shuffled, not obviously broken — the worst failure mode for a cause
        // list, because it looks like a parsing quirk rather than corrupt input.
        //
        // So the glyph cursor advances only for characters that actually draw.
        var glyphIndex = 0
        var stringIndex = 0
        while stringIndex < ns.length {
            let unit = ns.character(at: stringIndex)
            // A surrogate pair is one glyph spread over two code units.
            let isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF
            let step = isHighSurrogate ? 2 : 1
            let piece = ns.substring(with: NSRange(location: stringIndex, length: step))
            stringIndex += step

            guard let ch = piece.first else { continue }
            if ch.isNewline { continue }          // draws nothing: no glyph slot consumed

            defer { glyphIndex += 1 }
            guard glyphIndex < page.numberOfCharacters else { break }

            let rect = page.characterBounds(at: glyphIndex)
            if rect.isNull || rect.isInfinite || rect.isEmpty
                || rect.width <= 0 || rect.height <= 0 { continue }

            glyphs.append(PositionedGlyph(character: ch,
                                          rect: transform(rect: rect,
                                                          rotation: rotation,
                                                          page: media)))
        }
        return glyphs
    }

    /// Upright page height after the page's own rotation is undone — a 90/270 page's
    /// upright height is the media box's WIDTH. The grid builder flips y against this, so
    /// getting it wrong turns the page upside down.
    static func uprightHeight(of page: PDFPage) -> CGFloat {
        let media = page.bounds(for: .mediaBox)
        return (page.rotation == 90 || page.rotation == 270) ? media.width : media.height
    }

    /// Brings a glyph rect from rotated page space into upright page space (origin bottom-left).
    /// PDFPage.rotation is the angle (CCW) applied to the page; we invert it.
    private static func transform(rect: CGRect, rotation: Int, page: CGRect) -> CGRect {
        switch rotation {
        case 0:
            return rect
        case 90:
            // Rotated 90 CCW in display; undo by swapping x/y around the media box.
            return CGRect(x: rect.minY,
                           y: page.height - rect.maxX,
                           width: rect.height,
                           height: rect.width)
        case 180:
            return CGRect(x: page.width - rect.maxX,
                          y: page.height - rect.maxY,
                          width: rect.width,
                          height: rect.height)
        case 270:
            return CGRect(x: page.width - rect.maxY,
                          y: rect.minX,
                          width: rect.height,
                          height: rect.width)
        default:
            return rect
        }
    }
}

private extension CGRect {
    var isNull: Bool {
        // CGRect.null has infinite origin; catch degenerate rectangles too.
        return isInfinite || isEmpty || width <= 0 || height <= 0
    }
}
