import Foundation
import CoreGraphics
import CoreText
#if canImport(AppKit)
import AppKit
#endif

public struct BoardPDFRenderer {
    public struct Options: Sendable {
        public var title: String
        public var subtitle: String
        public var showSerial: Bool
        public var showSection: Bool
        public var landscape: Bool
        public var pageSize: CGSize

        public init(title: String = "Board",
                    subtitle: String = "",
                    showSerial: Bool = true,
                    showSection: Bool = true,
                    landscape: Bool = true,
                    // A4, LANDSCAPE. 842x595 IS A4; 01-PRD §11 says "A4" and does not fix an
                    // orientation. It has to be landscape: six columns across portrait's
                    // 595pt, less margins, is ~87pt per column, which at the specified
                    // Trebuchet MS 12 is roughly ten characters. Party names and office notes
                    // become unreadable, and an unreadable board is a useless board.
                    pageSize: CGSize = CGSize(width: 842, height: 595)) {
            self.title = title
            self.subtitle = subtitle
            self.showSerial = showSerial
            self.showSection = showSection
            self.landscape = landscape
            self.pageSize = pageSize
        }
    }

    private let options: Options

    public init(options: Options) { self.options = options }

    // MARK: - Public entry points

    public func render(rows: [BoardRow], to url: URL) throws {
        let data = try renderData(rows: rows)
        try data.write(to: url, options: .atomic)
    }

    public func renderData(rows: [BoardRow]) throws -> Data {
        let mediaBox = CGRect(origin: .zero, size: options.pageSize)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw NSError(domain: "BoardPDFRenderer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF data consumer"])
        }
        var box = mediaBox
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "BoardPDFRenderer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }

        let driver = TableDriver(rows: rows, options: options, mediaBox: mediaBox, ctx: ctx)
        try driver.draw()
        ctx.closePDF()
        return data as Data
    }
}

// MARK: - Layout driver

private struct ColumnSpec {
    let key: String
    let relativeWidth: CGFloat
    let align: CTTextAlignment
}

/// The single column plan for the export.
///
/// It lives here, once, because there are two consumers: the driver that DRAWS the table and
/// the estimator that MEASURES it to fill in "Page N of M". They previously kept a copy each.
/// Two copies of a layout constant do not stay equal, and when these two diverge the document
/// is measured against different columns than it is drawn with — a wrong page count at best,
/// a clipped row at worst.
///
/// ORDER IS THE PRODUCT OWNER'S DECISION (01-PRD §11) and is not a layout preference:
/// Court · Sr. · Case No. · Party · Office note · Counsel.
private enum ColumnPlan {
    static func specs(showSerial: Bool) -> [ColumnSpec] {
        if showSerial {
            return [
                ColumnSpec(key: "court",  relativeWidth: 0.14, align: .left),
                ColumnSpec(key: "sr",     relativeWidth: 0.05, align: .right),
                ColumnSpec(key: "caseno", relativeWidth: 0.13, align: .left),
                ColumnSpec(key: "case",   relativeWidth: 0.24, align: .left),
                ColumnSpec(key: "office", relativeWidth: 0.23, align: .left),
                ColumnSpec(key: "counsel",relativeWidth: 0.21, align: .left),
            ]
        } else {
            return [
                ColumnSpec(key: "court",  relativeWidth: 0.18, align: .left),
                ColumnSpec(key: "caseno", relativeWidth: 0.14, align: .left),
                ColumnSpec(key: "case",   relativeWidth: 0.25, align: .left),
                ColumnSpec(key: "office", relativeWidth: 0.23, align: .left),
                ColumnSpec(key: "counsel",relativeWidth: 0.20, align: .left),
            ]
        }
    }
}

private final class TableDriver {
    let rows: [BoardRow]
    let options: BoardPDFRenderer.Options
    let mediaBox: CGRect
    let ctx: CGContext

    // Fonts — created once, reused.
    let titleFont: CTFont
    let subtitleFont: CTFont
    let headerFont: CTFont
    let bodyFont: CTFont
    let courtFont: CTFont
    let sectionFont: CTFont
    let footerFont: CTFont

    // Margins & layout constants.
    let marginLeft: CGFloat = 36
    let marginRight: CGFloat = 36
    let marginTop: CGFloat = 36
    let marginBottom: CGFloat = 36
    let titleHeight: CGFloat = 22
    let subtitleHeight: CGFloat = 14
    let titleRuleHeight: CGFloat = 8
    let footerHeight: CGFloat = 14
    let headerRowHeight: CGFloat = 20
    let courtBandHeight: CGFloat = 22
    let sectionBandHeight: CGFloat = 16
    let cellPaddingX: CGFloat = 4
    let cellPaddingY: CGFloat = 3

    // Two-pass bookkeeping for "Page N of M".
    var pageCountForFooter: Int = 0

    init(rows: [BoardRow], options: BoardPDFRenderer.Options, mediaBox: CGRect, ctx: CGContext) {
        self.rows = rows
        self.options = options
        self.mediaBox = mediaBox
        self.ctx = ctx

        // 01-PRD §11 fixes the export face at Trebuchet MS 12. It ships with macOS, so this
        // resolves on every target machine; the fallback exists so a stripped system produces
        // a board that looks slightly different rather than one that is unreadable.
        self.titleFont = TableDriver.face(bold: true, size: 16)
        self.subtitleFont = TableDriver.face(bold: false, size: 10)
        self.headerFont = TableDriver.face(bold: true, size: 12)
        self.bodyFont = TableDriver.face(bold: false, size: 12)
        self.courtFont = TableDriver.face(bold: true, size: 13)
        self.sectionFont = TableDriver.face(bold: true, size: 11)
        self.footerFont = TableDriver.face(bold: false, size: 9)
    }

    /// Trebuchet MS, or Helvetica if this machine has had it removed.
    ///
    /// `CTFontCreateWithName` substitutes silently when a face is missing, so asking for the
    /// PostScript name and then checking what actually came back is the only way to know
    /// which face the document is being drawn with.
    static func face(bold: Bool, size: CGFloat) -> CTFont {
        let wanted = bold ? "TrebuchetMS-Bold" : "TrebuchetMS"
        let font = CTFontCreateWithName(wanted as CFString, size, nil)
        let got = CTFontCopyPostScriptName(font) as String
        if got.caseInsensitiveCompare(wanted) == .orderedSame { return font }
        return CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    }

    /// Export palette: warm rust for structure, muted grey for the office note, so the eye
    /// lands on the case number and the counsel first — 01-PRD §11.
    var palette: Palette.Tokens { Palette.light }

    func draw() throws {
        if rows.isEmpty {
            drawEmptyState()
            return
        }

        // First pass — measure how many pages we will produce (without writing content),
        // so footers can say "Page N of M".
        let estimator = PageEstimator(rows: rows,
                                      options: options,
                                      mediaBox: mediaBox,
                                      bodyFont: bodyFont,
                                      headerFont: headerFont,
                                      courtFont: courtFont,
                                      sectionFont: sectionFont,
                                      headerRowHeight: headerRowHeight,
                                      courtBandHeight: courtBandHeight,
                                      sectionBandHeight: sectionBandHeight,
                                      footerHeight: footerHeight,
                                      marginTop: marginTop,
                                      marginBottom: marginBottom,
                                      titleBlockHeight: titleBlockHeight(forFirstPage: true))
        pageCountForFooter = estimator.totalPages()

        // Second pass — actually render.
        let printer = PagePrinter(driver: self)
        try printer.printAll()
    }

    func titleBlockHeight(forFirstPage: Bool) -> CGFloat {
        // Title block appears only on page 1.
        return forFirstPage ? (titleHeight + subtitleHeight + titleRuleHeight) : 0
    }

    // MARK: - Coordinate helpers

    /// Y for top of printable area on a given page.
    func topY(pageHasTitle: Bool) -> CGFloat {
        return mediaBox.height - marginTop - (pageHasTitle ? titleBlockHeight(forFirstPage: true) : 0)
    }

    /// Y for bottom of printable area (above the footer band).
    func bottomY() -> CGFloat {
        return marginBottom + footerHeight + 4
    }

    // MARK: - Column plan

    func columnSpecs() -> [ColumnSpec] { ColumnPlan.specs(showSerial: options.showSerial) }

    func columnWidths() -> [(spec: ColumnSpec, width: CGFloat, x: CGFloat)] {
        let specs = columnSpecs()
        let totalRel = specs.reduce(0) { $0 + $1.relativeWidth }
        let printable = mediaBox.width - marginLeft - marginRight
        var x = marginLeft
        return specs.map { spec in
            let w = printable * (spec.relativeWidth / totalRel)
            let rec = (spec: spec, width: w, x: x)
            x += w
            return rec
        }
    }

    // MARK: - Cell text access

    func cellText(for spec: ColumnSpec, row: BoardRow) -> String {
        switch spec.key {
        case "court":   return row.court
        case "sr":      return row.serial
        case "caseno":  return row.numberColumn  // may contain "\n" for connected matters
        case "case":    return row.caseName
        case "counsel": return row.counsels
        case "office":  return row.officeNote
        default:        return ""
        }
    }

    // MARK: - Drawing primitives

    func beginPage(pageNumber: Int) {
        var media = mediaBox
        ctx.beginPage(mediaBox: &media)

        if pageNumber == 1 {
            drawTitleBlock()
        }
    }

    func endPage(pageNumber: Int) {
        drawFooter(pageNumber: pageNumber)
        ctx.endPage()
    }

    func drawTitleBlock() {
        let topY = mediaBox.height - marginTop
        // Title
        drawText(string: options.title,
                 font: titleFont,
                 color: .black,
                 x: marginLeft,
                 y: topY - titleFontAscent(),
                 width: mediaBox.width - marginLeft - marginRight,
                 alignment: .left)
        // Subtitle (a date or human note passed by the caller)
        drawText(string: options.subtitle,
                 font: subtitleFont,
                 color: palette.muted,
                 x: marginLeft,
                 y: topY - titleHeight - subtitleFontAscent(),
                 width: mediaBox.width - marginLeft - marginRight,
                 alignment: .left)
        // Rule
        let ruleY = topY - titleHeight - subtitleHeight - titleRuleHeight + 2
        ctx.setStrokeColor(palette.accent)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginLeft, y: ruleY))
        ctx.addLine(to: CGPoint(x: mediaBox.width - marginRight, y: ruleY))
        ctx.strokePath()
    }

    func drawFooter(pageNumber: Int) {
        let y = marginBottom - 2
        ctx.setStrokeColor(palette.rule)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginLeft, y: y + 8))
        ctx.addLine(to: CGPoint(x: mediaBox.width - marginRight, y: y + 8))
        ctx.strokePath()

        let left = options.subtitle
        let centre = "Page \(pageNumber) of \(pageCountForFooter)"
        let right = "Generated locally — no data left this Mac"

        drawText(string: left, font: footerFont,
                 color: palette.muted,
                 x: marginLeft,
                 y: y - footerFontAscent(),
                 width: (mediaBox.width - marginLeft - marginRight) / 3,
                 alignment: .left)

        drawText(string: centre, font: footerFont,
                 color: palette.muted,
                 x: marginLeft + (mediaBox.width - marginLeft - marginRight) / 3,
                 y: y - footerFontAscent(),
                 width: (mediaBox.width - marginLeft - marginRight) / 3,
                 alignment: .center)

        drawText(string: right, font: footerFont,
                 color: palette.muted,
                 x: marginLeft + 2 * (mediaBox.width - marginLeft - marginRight) / 3,
                 y: y - footerFontAscent(),
                 width: (mediaBox.width - marginLeft - marginRight) / 3,
                 alignment: .right)
    }

    /// Draws a band (court or section) and returns the new top y.
    @discardableResult
    func drawBand(text: String, height: CGFloat, font: CTFont, isCourt: Bool, atTopY topY: CGFloat) -> CGFloat {
        let bg = isCourt ? palette.accentSoft : CGColor(gray: 0.96, alpha: 1.0)
        ctx.setFillColor(bg)
        ctx.fill(CGRect(x: marginLeft, y: topY - height, width: mediaBox.width - marginLeft - marginRight, height: height))

        ctx.setStrokeColor(palette.rule)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginLeft, y: topY - height))
        ctx.addLine(to: CGPoint(x: mediaBox.width - marginRight, y: topY - height))
        ctx.strokePath()

        drawText(string: text, font: font, color: .black,
                 x: marginLeft + 6,
                 y: topY - height/2 - fontAscent(font)/2,
                 width: mediaBox.width - marginLeft - marginRight - 12,
                 alignment: .left)
        return topY - height
    }

    /// Draws the column header row (with light-grey fill, bold).
    func drawHeaderRow(atTopY topY: CGFloat) -> CGFloat {
        ctx.setFillColor(palette.accentSoft)
        ctx.fill(CGRect(x: marginLeft, y: topY - headerRowHeight,
                        width: mediaBox.width - marginLeft - marginRight,
                        height: headerRowHeight))

        let cols = columnWidths()
        for col in cols {
            let label: String
            switch col.spec.key {
            case "court":   label = "Court"
            case "sr":      label = "Sr."
            case "caseno":  label = "Case No."
            case "case":    label = "Case"
            case "counsel": label = "Counsel"
            case "office":  label = "Office note"
            default:        label = ""
            }
            drawCellText(string: label, font: headerFont, color: .black,
                         x: col.x + cellPaddingX,
                         y: topY - headerRowHeight/2 - headerFontAscent()/2,
                         width: col.width - 2*cellPaddingX,
                         alignment: col.spec.align)
        }
        return topY - headerRowHeight
    }

    /// Draws a full row. Returns the new top y after drawing.
    /// If `remainingHeight` is less than the row's needed height, returns nil — caller must
    /// either start a new page or, for a single oversize row, split it.
    @discardableResult
    func drawRow(_ row: BoardRow, atTopY topY: CGFloat, bandIndex: Int) -> (newTopY: CGFloat, didSplit: Bool, didDrawAll: Bool) {
        let cols = columnWidths()
        let printable = mediaBox.width - marginLeft - marginRight
        let rowHeight = computeRowHeight(row: row, cols: cols, maxHeight: .greatestFiniteMagnitude)
        let availableHeight = topY - bottomY()

        // Alternating row shading
        if bandIndex % 2 == 0 {
            ctx.setFillColor(CGColor(gray: 0.97, alpha: 1.0))
            ctx.fill(CGRect(x: marginLeft, y: topY - rowHeight, width: printable, height: rowHeight))
        }

        if rowHeight <= availableHeight {
            drawRowCells(row: row, cols: cols, atTopY: topY, rowHeight: rowHeight)
            return (topY - rowHeight, false, true)
        }

        // Row too tall — split across pages.
        // Draw as much as fits, then continue on next page.
        let yCursor = topY
        let pageHeight = availableHeight  // fit-on-page budget
        // Strategy: keep drawing partial frames until all cells are exhausted.
        // Cells are independent; we iterate per cell using CTFramesetter.
        // For simplicity, render each cell's full content starting at yCursor and let
        // CGContext clip to the page rect; then move to next page and render remainder
        // by re-framesetting with an offset (we approximate via successive draws per cell).
        // To keep this robust we use a conservative approach: draw the row with clipping
        // to the page bottom, then on next page draw the row again starting from where
        // it left off using a vertical character offset.

        // Implement row-split by clipping draw to bottom of page and recording consumedHeight.
        let firstChunkHeight = pageHeight
        ctx.saveGState()
        ctx.clip(to: CGRect(x: marginLeft, y: bottomY(),
                            width: printable,
                            height: firstChunkHeight))
        drawRowCells(row: row, cols: cols, atTopY: yCursor, rowHeight: rowHeight, splitOffsetY: 0)
        ctx.restoreGState()

        // Now estimate remaining to render on subsequent pages.
        let remaining = rowHeight - firstChunkHeight
        // The caller handles pagination by repeating the row.
        _ = remaining  // suppress unused warning
        return (bottomY(), true, false)
    }

    /// Continue drawing a previously-split row starting at `offsetY` from the row's top.
    func drawRowContinuation(_ row: BoardRow, fromOffsetY offsetY: CGFloat, atTopY topY: CGFloat) -> (newTopY: CGFloat, done: Bool) {
        let cols = columnWidths()
        let rowHeight = computeRowHeight(row: row, cols: cols, maxHeight: .greatestFiniteMagnitude)
        let remaining = rowHeight - offsetY
        let available = topY - bottomY()
        if remaining <= available {
            drawRowCells(row: row, cols: cols, atTopY: topY, rowHeight: rowHeight, splitOffsetY: offsetY)
            return (topY - remaining, true)
        } else {
            let chunk = available
            ctx.saveGState()
            ctx.clip(to: CGRect(x: marginLeft, y: bottomY(),
                                width: mediaBox.width - marginLeft - marginRight,
                                height: chunk))
            drawRowCells(row: row, cols: cols, atTopY: topY, rowHeight: rowHeight, splitOffsetY: offsetY)
            ctx.restoreGState()
            return (bottomY(), false)
        }
    }

    private func drawRowCells(row: BoardRow,
                              cols: [(spec: ColumnSpec, width: CGFloat, x: CGFloat)],
                              atTopY topY: CGFloat,
                              rowHeight: CGFloat,
                              splitOffsetY: CGFloat = 0) {
        let printable = mediaBox.width - marginLeft - marginRight
        // Grid
        ctx.setStrokeColor(palette.rule)
        ctx.setLineWidth(0.25)
        ctx.stroke(CGRect(x: marginLeft, y: topY - rowHeight,
                          width: printable, height: rowHeight))

        for col in cols {
            let text = cellText(for: col.spec, row: row)
            let cellRect = CGRect(x: col.x + cellPaddingX,
                                  y: topY - rowHeight + cellPaddingY,
                                  width: col.width - 2*cellPaddingX,
                                  height: rowHeight - 2*cellPaddingY)
            drawCellWrapped(text: text,
                            font: bodyFont,
                            color: .black,
                            cellRect: cellRect,
                            alignment: col.spec.align,
                            splitOffsetY: splitOffsetY)
        }
    }

    // MARK: - Text drawing helpers

    func drawText(string: String, font: CTFont, color: CGColor,
                  x: CGFloat, y: CGFloat, width: CGFloat, alignment: CTTextAlignment) {
        let attr = NSMutableAttributedString(string: string)
        attr.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value: font,
                          range: NSRange(location: 0, length: attr.length))
        attr.addAttribute(kCTForegroundColorAttributeName as NSAttributedString.Key, value: color,
                          range: NSRange(location: 0, length: attr.length))
        let para = NSMutableParagraphStyle()
        para.alignment = nsAlignment(alignment)
        para.lineBreakMode = .byTruncatingTail
        attr.addAttribute(kCTParagraphStyleAttributeName as NSAttributedString.Key,
                          value: para, range: NSRange(location: 0, length: attr.length))
        drawAttributedString(attr, x: x, y: y, width: width, height: fontAscent(font) + fontDescent(font))
    }

    func drawCellText(string: String, font: CTFont, color: CGColor,
                      x: CGFloat, y: CGFloat, width: CGFloat, alignment: CTTextAlignment) {
        drawText(string: string, font: font, color: color, x: x, y: y, width: width, alignment: alignment)
    }

    /// CoreText word-wrap inside a rect. `splitOffsetY` lets us render only the portion of
    /// the text whose visual baseline lies >= offsetY from the cell top (used to continue a
    /// split row on the next page). We achieve this by clipping the cell rect and translating.
    func drawCellWrapped(text: String, font: CTFont, color: CGColor,
                         cellRect: CGRect, alignment: CTTextAlignment,
                         splitOffsetY: CGFloat = 0) {
        let attr = NSMutableAttributedString(string: text)
        attr.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value: font,
                          range: NSRange(location: 0, length: attr.length))
        attr.addAttribute(kCTForegroundColorAttributeName as NSAttributedString.Key, value: color,
                          range: NSRange(location: 0, length: attr.length))
        let para = NSMutableParagraphStyle()
        para.alignment = nsAlignment(alignment)
        para.lineBreakMode = .byWordWrapping
        attr.addAttribute(kCTParagraphStyleAttributeName as NSAttributedString.Key,
                          value: para, range: NSRange(location: 0, length: attr.length))

        let drawRect = CGRect(x: cellRect.minX,
                              y: cellRect.minY - splitOffsetY,
                              width: cellRect.width,
                              height: cellRect.height)

        let path = CGPath(rect: drawRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

        // CoreText draws with origin at the *bottom-left* of the rect; our rect is in CG
        // coordinates (PDF page is bottom-left origin) so it lines up directly.
        ctx.saveGState()
        // Clipping keeps text from leaking outside the cell.
        ctx.clip(to: cellRect)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    /// Draw ONE line of text with its baseline at `y`.
    ///
    /// Deliberately NOT a CTFramesetter. A framesetter lays text into a path and needs
    /// room for ascent + descent + leading; given a path exactly one line tall it fits
    /// nothing and draws nothing, silently. That is what blanked the title, the column
    /// headers and the court bands in the first rendered board while the table rules and
    /// shading around them drew perfectly — the worst kind of rendering bug, because the
    /// output looks deliberate. CTLine draws at an explicit baseline and cannot fail this
    /// way.
    func drawAttributedString(_ attr: NSAttributedString, x: CGFloat, y: CGFloat,
                              width: CGFloat, height: CGFloat) {
        guard attr.length > 0, width > 1 else { return }
        var line = CTLineCreateWithAttributedString(attr)

        if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(width) {
            let ellipsisAttr = NSAttributedString(
                string: "\u{2026}",
                attributes: attr.attributes(at: 0, effectiveRange: nil))
            let ellipsis = CTLineCreateWithAttributedString(ellipsisAttr)
            if let truncated = CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis) {
                line = truncated
            }
        }

        // CTLine has no notion of alignment; it is a property of the box we are placing
        // the line into, so it is applied here.
        let drawn = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var dx: CGFloat = 0
        if let para = attr.attribute(kCTParagraphStyleAttributeName as NSAttributedString.Key,
                                     at: 0, effectiveRange: nil) as? NSParagraphStyle {
            switch para.alignment {
            case .center: dx = max(0, (width - drawn) / 2)
            case .right:  dx = max(0, width - drawn)
            default:      dx = 0
            }
        }

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x + dx, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Metric helpers

    func computeRowHeight(row: BoardRow,
                          cols: [(spec: ColumnSpec, width: CGFloat, x: CGFloat)],
                          maxHeight: CGFloat) -> CGFloat {
        var maxH: CGFloat = 0
        for col in cols {
            let s = cellText(for: col.spec, row: row)
            let h = measureWrappedHeight(text: s, font: bodyFont, width: col.width - 2*cellPaddingX)
            maxH = max(maxH, h + 2*cellPaddingY)
        }
        return max(18, min(maxH, maxHeight == .greatestFiniteMagnitude ? .greatestFiniteMagnitude : maxHeight))
    }

    func measureWrappedHeight(text: String, font: CTFont, width: CGFloat) -> CGFloat {
        if text.isEmpty { return fontAscent(font) + fontDescent(font) }
        let attr = NSMutableAttributedString(string: text)
        attr.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value: font,
                          range: NSRange(location: 0, length: attr.length))
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        attr.addAttribute(kCTParagraphStyleAttributeName as NSAttributedString.Key, value: para,
                          range: NSRange(location: 0, length: attr.length))
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let constraint = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRangeMake(0, 0), nil, constraint, nil
        )
        return ceil(suggested.height) + 2  // breathing room
    }

    func fontAscent(_ f: CTFont) -> CGFloat { CTFontGetAscent(f) }
    func fontDescent(_ f: CTFont) -> CGFloat { CTFontGetDescent(f) }
    func titleFontAscent() -> CGFloat { fontAscent(titleFont) }
    func subtitleFontAscent() -> CGFloat { fontAscent(subtitleFont) }
    func headerFontAscent() -> CGFloat { fontAscent(headerFont) }
    func footerFontAscent() -> CGFloat { fontAscent(footerFont) }

    // MARK: - Empty state

    func drawEmptyState() {
        pageCountForFooter = 1
        beginPage(pageNumber: 1)
        let midY = mediaBox.height / 2
        drawText(string: "No matters matched.",
                 font: titleFont,
                 color: .black,
                 x: marginLeft,
                 y: midY,
                 width: mediaBox.width - marginLeft - marginRight,
                 alignment: .center)
        drawText(string: "The advocate names you entered did not match any row in the supplied board(s).",
                 font: subtitleFont,
                 color: palette.muted,
                 x: marginLeft,
                 y: midY - 26,
                 width: mediaBox.width - marginLeft - marginRight,
                 alignment: .center)
        endPage(pageNumber: 1)
    }
}

// MARK: - Two-pass printer

private final class PagePrinter {
    let driver: TableDriver
    var pageNumber: Int = 0
    var topY: CGFloat = 0
    var bandIndex: Int = 0
    var pendingContinuationOf: BoardRow? = nil
    var pendingContinuationOffsetY: CGFloat = 0

    init(driver: TableDriver) { self.driver = driver }

    func printAll() throws {
        driver.beginPage(pageNumber: 1)
        pageNumber = 1
        topY = driver.topY(pageHasTitle: true)

        // Initial header on page 1.
        topY = driver.drawHeaderRow(atTopY: topY)

        var lastCourt: String? = nil
        var lastSection: String? = nil

        // If a row is split, we re-draw it across pages. To keep semantics tight we
        // intentionally draw it once with clip-down-on-page-bottom and on the next page
        // continue from the offset. We must be careful not to repeat the row's "header".

        for row in driver.rows {
            // 1) drain any pending continuation first
            while let cont = pendingContinuationOf {
                if topY - driver.bottomY() <= 2 {
                    driver.endPage(pageNumber: pageNumber)
                    pageNumber += 1
                    driver.beginPage(pageNumber: pageNumber)
                    topY = driver.topY(pageHasTitle: false)
                    topY = driver.drawHeaderRow(atTopY: topY)
                }
                let res = driver.drawRowContinuation(cont,
                                                    fromOffsetY: pendingContinuationOffsetY,
                                                    atTopY: topY)
                topY = res.newTopY
                if res.done {
                    pendingContinuationOf = nil
                    pendingContinuationOffsetY = 0
                } else {
                    pendingContinuationOffsetY += (driver.topY(pageHasTitle: false) - driver.bottomY())
                    driver.endPage(pageNumber: pageNumber)
                    pageNumber += 1
                    driver.beginPage(pageNumber: pageNumber)
                    topY = driver.topY(pageHasTitle: false)
                    topY = driver.drawHeaderRow(atTopY: topY)
                }
            }

            // 2) Court change.
            //
            // NO court band is drawn. "Name of Court" is column 1 of the export
            // (01-PRD §11), so a band naming the court repeats, on every group, what
            // the row already says a centimetre to the right — and it dragged a
            // SECOND copy of the column headers down with it, so page one printed
            // "Court Sr. Case No. Case Office note Counsel" twice before the first
            // matter. The change of court is still tracked, because it resets the
            // section grouping beneath it.
            let courtChanged = (row.court != lastCourt)
            if courtChanged {
                lastCourt = row.court
                lastSection = nil
                bandIndex = 0
            }

            // 3) Section band (optional)
            if driver.options.showSection {
                if row.section != lastSection {
                    if topY - driver.bottomY() < driver.sectionBandHeight + driver.headerRowHeight {
                        driver.endPage(pageNumber: pageNumber)
                        pageNumber += 1
                        driver.beginPage(pageNumber: pageNumber)
                        topY = driver.topY(pageHasTitle: false)
                        topY = driver.drawHeaderRow(atTopY: topY)
                    }
                    if !row.section.isEmpty {
                        topY = driver.drawBand(text: row.section,
                                               height: driver.sectionBandHeight,
                                               font: driver.sectionFont, isCourt: false,
                                               atTopY: topY)
                    }
                    lastSection = row.section
                }
            }

            // 4) Ensure room for the row + header on the page.
            let available = topY - driver.bottomY()
            if available < driver.headerRowHeight + 18 {
                driver.endPage(pageNumber: pageNumber)
                pageNumber += 1
                driver.beginPage(pageNumber: pageNumber)
                topY = driver.topY(pageHasTitle: false)
                topY = driver.drawHeaderRow(atTopY: topY)
            }

            // 5) Draw the row.
            //
            // The continuation offset must be what was ACTUALLY drawn on this page, not a
            // whole page's worth. A header or a section band above the row means less than
            // a full page was available, and assuming a full page made the continuation
            // start past the end of the row: text was skipped, and the leftover produced a
            // page carrying nothing but column headers.
            let consumedByRow = topY - driver.bottomY()
            let res = driver.drawRow(row, atTopY: topY, bandIndex: bandIndex)
            topY = res.newTopY
            bandIndex += 1
            if res.didSplit {
                pendingContinuationOf = row
                pendingContinuationOffsetY = consumedByRow
            }
        }

        // Drain any final continuation.
        while let cont = pendingContinuationOf {
            // A page is started HERE, once, and only when there is no useful room left.
            // The previous version also started one at the foot of the loop, so when the
            // remainder happened to finish exactly on a boundary the document ended with a
            // page containing column headers and nothing else.
            if topY - driver.bottomY() < 24 {
                driver.endPage(pageNumber: pageNumber)
                pageNumber += 1
                driver.beginPage(pageNumber: pageNumber)
                topY = driver.topY(pageHasTitle: false)
                topY = driver.drawHeaderRow(atTopY: topY)
            }
            let availableNow = topY - driver.bottomY()
            let res = driver.drawRowContinuation(cont,
                                                fromOffsetY: pendingContinuationOffsetY,
                                                atTopY: topY)
            topY = res.newTopY
            if res.done {
                pendingContinuationOf = nil
                pendingContinuationOffsetY = 0
            } else {
                pendingContinuationOffsetY += availableNow
            }
        }

        driver.endPage(pageNumber: pageNumber)
    }
}

// MARK: - Estimator (pass 1)

/// Computes total page count by simulating layout decisions without touching CG.
private final class PageEstimator {
    let rows: [BoardRow]
    let options: BoardPDFRenderer.Options
    let mediaBox: CGRect
    let bodyFont: CTFont
    let headerFont: CTFont
    let courtFont: CTFont
    let sectionFont: CTFont
    let headerRowHeight: CGFloat
    let courtBandHeight: CGFloat
    let sectionBandHeight: CGFloat
    let footerHeight: CGFloat
    let marginTop: CGFloat
    let marginBottom: CGFloat
    let titleBlockHeight: CGFloat

    let marginLeft: CGFloat = 36
    let marginRight: CGFloat = 36
    let cellPaddingX: CGFloat = 4
    let cellPaddingY: CGFloat = 3
    let minRowHeight: CGFloat = 18

    init(rows: [BoardRow],
         options: BoardPDFRenderer.Options,
         mediaBox: CGRect,
         bodyFont: CTFont, headerFont: CTFont, courtFont: CTFont, sectionFont: CTFont,
         headerRowHeight: CGFloat, courtBandHeight: CGFloat, sectionBandHeight: CGFloat,
         footerHeight: CGFloat, marginTop: CGFloat, marginBottom: CGFloat,
         titleBlockHeight: CGFloat) {
        self.rows = rows
        self.options = options
        self.mediaBox = mediaBox
        self.bodyFont = bodyFont
        self.headerFont = headerFont
        self.courtFont = courtFont
        self.sectionFont = sectionFont
        self.headerRowHeight = headerRowHeight
        self.courtBandHeight = courtBandHeight
        self.sectionBandHeight = sectionBandHeight
        self.footerHeight = footerHeight
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.titleBlockHeight = titleBlockHeight
    }

    private func columnSpecs() -> [ColumnSpec] { ColumnPlan.specs(showSerial: options.showSerial) }

    private func columnWidths() -> [(spec: ColumnSpec, width: CGFloat, x: CGFloat)] {
        let specs = columnSpecs()
        let totalRel = specs.reduce(0) { $0 + $1.relativeWidth }
        let printable = mediaBox.width - marginLeft - marginRight
        var x = marginLeft
        return specs.map { spec in
            let w = printable * (spec.relativeWidth / totalRel)
            let rec = (spec: spec, width: w, x: x)
            x += w
            return rec
        }
    }

    private func cellText(_ spec: ColumnSpec, _ row: BoardRow) -> String {
        switch spec.key {
        case "court":   return row.court
        case "sr":      return row.serial
        case "caseno":  return row.numberColumn
        case "case":    return row.caseName
        case "counsel": return row.counsels
        case "office":  return row.officeNote
        default:        return ""
        }
    }

    private func measureHeight(text: String, font: CTFont, width: CGFloat) -> CGFloat {
        if text.isEmpty { return CTFontGetAscent(font) + CTFontGetDescent(font) }
        let attr = NSMutableAttributedString(string: text)
        attr.addAttribute(kCTFontAttributeName as NSAttributedString.Key, value: font,
                          range: NSRange(location: 0, length: attr.length))
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        attr.addAttribute(kCTParagraphStyleAttributeName as NSAttributedString.Key, value: para,
                          range: NSRange(location: 0, length: attr.length))
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let cs = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        let s = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), nil, cs, nil)
        return ceil(s.height) + 2
    }

    private func rowHeight(_ row: BoardRow, cols: [(spec: ColumnSpec, width: CGFloat, x: CGFloat)]) -> CGFloat {
        var h: CGFloat = 0
        for c in cols {
            let s = cellText(c.spec, row)
            let m = measureHeight(text: s, font: bodyFont, width: c.width - 2*cellPaddingX)
            h = max(h, m + 2*cellPaddingY)
        }
        return max(minRowHeight, h)
    }

    private func printableTop(_ hasTitle: Bool) -> CGFloat {
        return mediaBox.height - marginTop - (hasTitle ? titleBlockHeight : 0)
    }

    private func printableBottom() -> CGFloat {
        return marginBottom + footerHeight + 4
    }

    func totalPages() -> Int {
        if rows.isEmpty { return 1 }
        let cols = columnWidths()
        var pages = 1
        var hasTitle = true
        var topY = printableTop(hasTitle)
        topY -= headerRowHeight  // initial header on page 1
        var lastCourt: String? = nil
        var lastSection: String? = nil

        func ensureRoom(_ needed: CGFloat) {
            if topY - printableBottom() < needed {
                pages += 1
                hasTitle = false
                topY = printableTop(false)
                topY -= headerRowHeight
            }
        }

        for row in rows {
            if row.court != lastCourt {
                ensureRoom(courtBandHeight + headerRowHeight)
                topY -= courtBandHeight
                topY -= headerRowHeight
                lastCourt = row.court
                lastSection = nil
            }
            if options.showSection && row.section != lastSection {
                if !row.section.isEmpty {
                    ensureRoom(sectionBandHeight + headerRowHeight)
                    topY -= sectionBandHeight
                }
                lastSection = row.section
            }

            let h = rowHeight(row, cols: cols)
            if h <= topY - printableBottom() {
                topY -= h
            } else {
                // Split across pages.
                var remaining = h
                var firstChunk = topY - printableBottom()
                if firstChunk <= 0 {
                    pages += 1
                    hasTitle = false
                    topY = printableTop(false)
                    topY -= headerRowHeight
                    firstChunk = topY - printableBottom()
                }
                remaining -= firstChunk
                while remaining > 0 {
                    pages += 1
                    hasTitle = false
                    topY = printableTop(false)
                    topY -= headerRowHeight
                    let chunk = topY - printableBottom()
                    if remaining <= chunk {
                        topY -= remaining
                        remaining = 0
                    } else {
                        remaining -= chunk
                    }
                }
            }
        }
        return pages
    }
}

/// CoreText and AppKit disagree on the alignment enum; CTTextAlignment is what the
/// drawing API speaks, NSParagraphStyle is what carries it. Bridge in one place.
private func nsAlignment(_ a: CTTextAlignment) -> NSTextAlignment {
    switch a {
    case .left: return .left
    case .right: return .right
    case .center: return .center
    case .justified: return .justified
    default: return .natural
    }
}
