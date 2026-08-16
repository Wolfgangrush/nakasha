# NAKASHA — Product Requirements Document

Version 1. Offline macOS application. Authoritative scope for v1.

> **Amended 2026-08-16 by the hard-question pass recorded in `03-ARCHITECTURE-ESSENTIALS.md`.**
> Four scope cuts and one correction landed in this file: Tier 2 OCR deferred to v2 (§8), the
> generic fallback narrowed to a case-number sweeper (§6), the interface font-size control
> narrowed to the results table (§10), Vision removed (§4), and the signing posture corrected
> from "unsigned" to **ad-hoc signed** (§9) — because entitlements do not apply to an unsigned
> binary, which would have left the offline guarantee unenforceable. Every cut is argued in 03.

## 1. Product identity

- Name: NAKASHA — High Court Board Parser. The word "nakasha" means the sanctioned building plan. It is not the name of any court.
- Publisher: wolfgang_rush.
- Copyright notice (every distribution): "Rushikesh R. Mahajan (publishing as wolfgang_rush)".
- Licence: **Apache License 2.0** (changed from MIT on 2026-08-16 by the owner's decision). Chosen
  over MIT for three reasons that bear on a tool used in legal practice: §3 grants users an
  express patent licence (MIT is silent on patents); §6 expressly grants no right to the
  author's name or marks, which matters because the publisher's identity is deliberately
  managed; and §§7–8 set out warranty and liability properly rather than in one sentence,
  which is the clause that would actually be read if an advocate ever claimed the tool caused
  them to miss a listing. `LICENSE` carries the unmodified licence text; `NOTICE` carries the
  attribution. Public GitHub repository. Advocates download and install on their own Mac.
- Distribution artefacts: a `.app` bundle and a DMG. Universal binary (arm64 and x86_64).
- Naming rule. The product name, tagline, repository name, and author attribution must never contain the name of a specific court, bench, or city as part of the identity. That is a de-anonymisation vector for the publisher. The name of a board the app can read (for example "a named bar association's daily board") may appear once, inside the supported-formats table, because it is a product feature.

## 2. Problem

An Indian High Court advocate must find their own matters in a daily board PDF that can run to 87 pages and 700 or more matters. Today that is done by eye, every morning, under time pressure, and matters get missed. NAKASHA reduces the task to: drop in the PDF, type the names, get the advocate's own list, export it. The advocate remains the human in the loop; the app only narrows the field.

## 3. Target user

Indian High Court advocates, particularly at the bar-association and High Court level where daily boards are published as PDF. The user is technically capable enough to download a DMG, drag an app to Applications, and right-click Open to bypass Gatekeeper. The user is not necessarily a power user of macOS.

## 4. Platforms and dependencies

- Platform: macOS 13 and later.
- Language and UI: Swift 5.9 and SwiftUI.
- Binary: universal, arm64 and x86_64.
- Third-party dependencies: **zero, literally**. The binary links only Foundation, PDFKit, CoreGraphics, CoreText, AppKit, SwiftUI and UniformTypeIdentifiers. Vision is NOT linked — it was previously declared-but-unused "to keep the link surface stable", which costs launch time and buys a question that has to be answered in every privacy review. No Tesseract binary is bundled in v1 (see §8), so the zero-dependency claim is now true on its face rather than true-with-an-asterisk. No Swift Package Manager dependencies. No CocoaPods. No Carthage. No embedded web view.

## 5. User flow

1. The user opens the app and uploads one board PDF for a given date.
2. The PDF renders on the right-hand side of the window, scrollable and readable, with its own text search.
3. On the left-hand side, upper area, the user types advocate names: their own plus chamber colleagues. Four names is a typical case. One per line.
4. The user clicks Process.
5. The lower-left area, previously empty, fills with the matching matters as a table.
6. The user verifies: clicking a result row jumps the right-hand PDF to that page and highlights the matched text, so the advocate sees the exact printed line the app read. The user can also search the PDF by hand.
7. The user prunes: every result row can be deselected or deleted.
8. The user clicks Export to PDF, chooses a location, and the surviving rows are written as an A4 table.

Layout:

- Left, upper: upload, name list, Process, Export, search-in-PDF field.
- Left, lower: results table, editable, with a checkbox and a delete per row.
- Right: PDF viewer with scroll, search, highlight, and jump-to-page.

## 6. Supported formats

The app supports two measured formats and a generic fallback. The two named formats are documented because they were measured against real documents; they cover the common case for High Court advocates.

- Format A — bar-association daily board. Row grammar: `<item no>` then `<CASE/NO/YEAR>` then `<PETITIONER>` then `#` then `<RESPONDENT>:<OFFICE NOTE>`, with counsel text in a right-hand column on the same lines. Both columns are hard-wrapped at a fixed character width, mid-word, with no hyphen. Party and advocate names are truncated by the export; that loss is in the source and is reproduced as printed, never guessed at. Connected matters (CAW or APPA applications) follow as indented case rows and belong to the matter above. Row shape as measured on a live board (page 5), shown with invented names:

  `11   WP/7042/2091 FIKTUS TESTOR # MOKARA DEMOS :ORDERS TO FILE CIVIL APPLICATION CORRECT & DETAIL ADD OF R-SOLE.(3RD DEFAULT)`

- Format B — High Court daily main causelist. COURT NO. X header, then centred coram lines (HON'BLE ... JUSTICE ...), then rows of item, case number, parties, counsel-A, counsel-B, word-wrapped, not character-chopped. The office note is the flush-left "FOR ..." block after each matter. A centred "FOR ..." line is a section band, not an office note; they are told apart by indentation column, never by the leading word, since both begin with "FOR". A centred "WITH" binds the following matter to the previous one.

- Generic fallback — a **case-number sweeper**, not a third parser. For a board that is neither Format A nor Format B, NAKASHA emits one row per detected case number carrying the whole printed line as its text, and nothing else. It has no columns, so it cannot mis-column anything; it keys on the case number, so it cannot lose a matter that prints one. Results carry a banner saying the board is not a known format and every row must be verified against the PDF.

  Rejected: a third hand-written parser that guesses at columns it has never been calibrated against. Under this product's falsifier a mis-columned table is worse than no table, because it *looks* like an answer and the advocate stops reading the board.

Cross-source repair. Format B carries full counsel names for the same case numbers that Format A truncates. When the user loads both boards for one date, joining on case number and taking the fuller reading per field produces a board that neither source publishes alone. This is offered as an explicit workflow, not a hidden side effect: **the join runs only when more than one source is loaded**, and never on a single-file open.

  The join key is case number **plus court**, never case number alone. The same matter is routinely listed before two courts on one day — that is what a part-heard day looks like — and collapsing those two listings into one row would hide a listing, which is the failure this product exists to prevent.

## 7. Loose matching and pruning

A first-class requirement, not a nicety. Real advocates will not type "firstname lastname". They will type a surname, "Samplekar" or "Vernekar", because surnames repeat heavily in this profession and the advocate does not remember the exact printed form.

- Matching is loose by default. A surname matches every advocate carrying it.
- The result set is therefore deliberately over-inclusive.
- The user prunes the rows they do not want, keeping the ones they do.
- Export writes only the surviving rows.

This design inverts a real defect. The bar-association board truncates advocate names at a fixed field width. The measured behaviour, illustrated throughout this document with invented names, is "ANANTRAO VITHALRAO VANK OLE", where the surname is cut mid-word. Exact matching would silently return nothing, and the advocate would conclude, wrongly, that they are not listed. A tool that silently misses a matter is worse than no tool. Loose match plus human prune plus visible verification against the PDF removes that failure mode entirely.

What "loose" means concretely, because "loose" on its own is not implementable:

1. **Any token, not all tokens.** Typing `Anantrao Vernekar` matches a row carrying only
   `VERNEKAR`, and also a row carrying only `ANANTRAO`. Tokens need not be adjacent or in order.
2. **Whitespace inside a token is absorbed.** The board hard-wraps mid-word without a hyphen,
   so `VANKOLE` prints as `VANK OLE`. Typing the surname must find both spellings.
3. **The tail may be truncated.** The board cuts every name at a fixed field width, so the
   printed form is frequently a strict prefix of the real one — `VERNEKAR` prints as `VERNEKA`.
   A leading word boundary is enforced (a field is cut at its END, never its start, so `Tarkel`
   must not match `STARKEL`); a trailing boundary is deliberately NOT enforced, because that is
   exactly what makes a truncated form fail to match.
4. **Consequence, stated plainly: `Tarkel` matches `TARKELE`.** That is correct. The extra row
   costs one click to prune. The row that strict matching would have dropped is a matter the
   advocate never learns they are listed in, and that is unrecoverable.
5. **Initials, honorifics and joining words are never search terms.** A one-letter pattern, or
   `AND` out of a firm name, matches hundreds of unrelated rows and drowns the result set —
   which fails the advocate the same way a miss does, by making the list untrustworthy.

An optional alias syntax is retained for users who want precision: `A. S. Tarkel; Tarkel` —
semicolon-separated alternates on one line. Supplying alternates is the explicit opt-in to
strict, bounded matching for that entry.

The interface always displays the count as "N of M matters matched", so silence is visibly silence.

## 8. Text extraction — one tier in v1, plus an honest refusal

Tier 1 is the only tier that ships in v1.

- Tier 1: native PDF text layer via PDFKit. Default. Offline, free, exact. Both real boards are 100 percent text-native. Measured:
  - Bar board: 87 pages, 261,655 extractable characters, 7 embedded fonts, 0 pages needing OCR.
  - HC causelist: 22 pages, 31,918 extractable characters, 12 embedded fonts, 0 pages needing OCR.
  Running OCR on these would rasterise a perfect text layer, re-recognise it with errors, and destroy the column geometry the parser depends on. OCR is therefore not the primary path.
- **No-text-layer refusal (replaces Tier 2 in v1).** When a page yields no text, NAKASHA does not guess and does not silently return an empty page. It names the page: *"page 4 has no text layer — NAKASHA cannot read it. Check that page against the board by eye."* Roughly twenty lines of code, no dependency, and it never loses a matter silently.
- Tier 2: bundled Tesseract OCR. **Deferred to v2** by the 2026-08-16 hard-question pass. The measurement above is the reason: across both real boards, 109 pages, **zero pages needed OCR**. In exchange for a case that has not occurred in the measured corpus it would have added a bundled third-party binary, a universal-binary-versus-Homebrew architecture conflict, subprocess execution from inside the App Sandbox, thermal discipline, a cancellation protocol and a progress UI. When it does ship, the thermal discipline stands as previously written: never OCR a page that already has text; one page at a time; single worker thread; visible progress; user-cancellable; never run automatically on a whole document without telling the user the page count first.
- Tier 3: external API (Google, Gemini, Anthropic, or other), user-supplied key. Not in version 1. Deferred to v2. The intent is documented, nothing is shipped.

## 9. Privacy and legal posture

This is the core promise. Treat it as a requirement.

- Version 1 is completely offline. The app sandbox is enabled with user-selected-files read-write and no network entitlement at all, neither client nor server. The absence of the entitlement is the enforcement: the sandbox denies any socket regardless of code. The README tells advocates how to verify this themselves.
- No telemetry, no analytics, no crash reporting, no accounts.
- The source PDF is never copied anywhere. Outputs are written only where the user chooses.
- Watched names are stored only in local user defaults on that Mac.
- **Ad-hoc signed; not notarised, no Developer ID.** Corrected 2026-08-16. The build applies an ad-hoc signature (`codesign --sign -`) carrying `entitlements.plist`. This is not a cosmetic detail: **an unsigned Mach-O carries no entitlement dictionary at all**, so on a genuinely unsigned build the sandbox would not be applied, `codesign -d --entitlements` would print nothing, and the offline guarantee above would be a promise with no enforcement behind it. An ad-hoc signature costs nothing, needs no Apple certificate and no notarisation, and makes the sandbox real.
- Install consequence, documented as step 1: because the app is not notarised, Gatekeeper blocks first launch. The reliable path on current macOS is `xattr -dr com.apple.quarantine /Applications/NAKASHA.app`, or System Settings → Privacy & Security → **Open Anyway**. Right-click → Open is documented as the secondary route: it is no longer dependable for unsigned and ad-hoc-signed apps on recent macOS, and leading with it means users conclude the app is broken.

The About screen states, in plain language:

- This application accesses nothing and sends nothing.
- It is consistent with Bar Council of India rules for advocates.
- It is a tool: the advocate remains responsible for verifying every listing against the board itself before acting on it.

## 10. Settings

Required, not optional.

- Appearance: Dark, Light, or System.
- Text-size control **for the results table**. Reason: advocates use Macs from 13-inch laptops to 27-inch displays at very different scalings, and an unreadable table is a useless table. Narrowed 2026-08-16 from a whole-interface font-scale token — macOS already scales the interface system-wide, and the table is the one place the reason actually bites.
- About screen with the content above.

## 11. Export PDF specification

- A4, tabular.
- Columns in this order: Name of Court, Serial No., Case Number, Name of Case, Name of the Counsel, Office note given.
- Font: Trebuchet MS, 12 pt. Line spacing 1.0.
- Heading: the board's own date.
- Only rows surviving the user's prune are written.
- Cells word-wrap. A row taller than the remaining page continues on the next page. A matter must never be clipped or lost.
- Column headers repeat on every page. Page N of M in the footer.
- Colour: a restrained warm rust or terracotta accent for headers and rules; muted grey for the office-note column so the eye lands on case number and counsel first. Readable in both light and dark. Do not copy any third party's brand palette; define our own tokens.

## 12. Non-negotiable constraints

- Offline-only operation. No network entitlement. No telemetry. No analytics.
- Zero third-party dependencies. Apple frameworks only.
- Universal binary on macOS 13 or later.
- Loose matching by default, with visible verification against the source PDF.
- The advocate remains the human in the loop. Every result is verified by clicking through to the PDF.

## 13. Banned scope for v1

Prominently stated. These are not deferred features; they are deliberately excluded from v1 to preserve the privacy posture and the focused scope.

- No external API calls of any kind. Deferred to v2.
- No OCR, and no bundled OCR binary. Deferred to v2 (§8). A page with no text layer is reported, never guessed at.
- No notarisation or signing pipeline.
- No cloud sync, no accounts, no multi-device.
- No case-management features, no calendar, no reminders, no notifications.
- No editing or annotating the source PDF.
- No scraping court websites. The user supplies the file.
- No support for court formats beyond the two named above plus a generic fallback.
- No analytics of any kind.

## 14. Inputs

- One PDF file selected by the user via the standard macOS file picker. The user-selected-files entitlement governs read access.
- A list of advocate names typed by the user, one per line, with optional semicolon-separated aliases.

## 15. Outputs

- A results table in the lower-left pane, editable, with a checkbox and a delete per row.
- An exported A4 PDF at the location the user chooses, containing only the rows the user has kept.

## 16. Observable "done looks like"

A version 1 build is accepted when all of the following are independently verifiable on a clean Mac running macOS 13 or later with no network:

1. The user can launch the app by right-click Open (no developer signature required).
2. The user can verify, by reading the README and the entitlements, that the app has no network entitlement.
3. The user can load a bar-association daily board PDF and a High Court causelist PDF and see both rendered on the right side with working text search.
4. Typing a surname produces, on click of Process, a results table whose every row can be clicked to jump the PDF to the matching page with the matched text highlighted.
5. The results table shows "N of M matters matched" at all times.
6. Editing the results table (deleting rows, toggling checkboxes) changes the export output accordingly.
7. Export to PDF writes an A4 file with the specified columns, font, line spacing, header repetition, and "Page N of M" footer. A row that would overflow the page is carried to the next page whole; nothing is clipped.
8. The About screen states the privacy posture in plain language.
9. With a PDF containing a page that has no text layer, that page is named to the user as unreadable rather than silently contributing nothing, and the rest of the document still parses.
10. The app does not make any outbound network connection during the full flow. This is observable in the macOS network monitor.
