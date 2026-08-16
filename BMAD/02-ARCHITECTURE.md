# NAKASHA — Architecture

The full architectural record for v1. The intent is that any contributor can rebuild this app from this document alone, given the constraints in `01-PRD.md`.

> **Amended 2026-08-16 by the hard-question pass in `03-ARCHITECTURE-ESSENTIALS.md`.** The data model in §3 was replaced by the one the code actually has; Tier 2 OCR left §2.6; the generic parser became a sweeper in §2.9; §2.12's provenance UI was deferred; §1 and §7 were corrected to ad-hoc signing and to the SwiftPM package that exists instead of an Xcode project; §5 gained three failure modes; and §8's instruction to commit real boards was **deleted as a privacy defect**.

## 1. Tech stack and the reasons

- Language: Swift 5.9. Static, memory-safe, the only first-class language for native macOS in 2026.
- UI: SwiftUI for the chrome and AppKit (NSViewRepresentable) only where SwiftUI does not give us a first-class PDF viewer with text search and programmatic highlight. PDFKit is wrapped in AppKit because that is the path of least resistance for the jump-to-page and highlight contract.
- Distribution: a `.app` bundle built by Xcode and packaged into a DMG by a shell script. No installer. No Sparkle. No auto-update.
- Sandboxing: App Sandbox enabled, with `com.apple.security.files.user-selected.read-write`. The network entitlement is deliberately absent. The absence is the enforcement: any attempt to open a socket is denied by the kernel-level sandbox regardless of what the code does.
- Code signing: **ad-hoc** (`codesign --sign -`) with `entitlements.plist` applied. Notarisation: none. Developer ID: none. Corrected 2026-08-16: entitlements are carried in the code signature, so a truly unsigned binary would have no sandbox and no verifiable entitlement list — §9 of the PRD would then be unenforceable. Ad-hoc signing needs no Apple certificate and makes the sandbox real. The README documents `xattr -dr com.apple.quarantine` as the primary first-launch route and right-click-Open as the secondary one.
- PDF text: PDFKit for native text extraction, page rendering, text search, and selection. PDFKit is the only viable choice on macOS without a third-party dependency.
- PDF writing: PDFKit (`PDFDocument` and `PDFPage`) for the export. Apple frameworks only.
- OCR: **none in v1** (deferred to v2 — PRD §8). A page with no text layer is reported to the user by page number, not guessed at. There is therefore no bundled binary, no subprocess, and no `Process` invocation anywhere in the app.
- Fonts: Trebuchet MS for the export PDF; it ships with macOS. System font for the UI (San Francisco).
- Persistence: `UserDefaults` for the watched-name list and appearance. The source PDF is never copied; only the path held in memory. Outputs are written to a user-selected location.
- Testing: XCTest for unit tests on the parsers. No UI tests in v1. No snapshot tests.
- Build: a single Xcode project. Two targets: the app and a unit-test bundle.

What this stack rules out, deliberately:

- No third-party Swift packages. SPM is enabled only to verify that no third-party packages are linked.
- No CocoaPods, no Carthage, no homebrew dependency.
- No web view. No JavaScript bridge. No HTML rendering of the PDF.
- No network framework, no URLSession, no CloudKit, no GameKit, no push notifications.
- No CoreML and no Vision. Vision was previously declared-but-unused; it is not linked at all.
- No external update channel.

## 2. Components

Each component has one responsibility and a narrow interface. Components communicate by passing value types.

### 2.1 AppDelegate / App entry

- Responsibilities: launch the window, set the activation policy, and wire the root SwiftUI scene.
- Boundaries: no business logic.

### 2.2 WindowView (SwiftUI)

- Responsibilities: render the three-pane layout (left upper, left lower, right), host the toolbar, and forward user actions to the controller layer.
- Boundaries: does not parse PDF, does not match names, does not write export.

### 2.3 PDFViewer (NSViewRepresentable wrapping PDFView)

- Responsibilities: render the loaded PDF, expose text search, expose programmatic selection (highlight a substring on a page), expose page-jump by index.
- Boundaries: read-only over the loaded PDF; does not persist annotations.

### 2.4 NameListView (SwiftUI)

- Responsibilities: maintain the watched-name list in memory and in UserDefaults. Parse the optional alias syntax (`A; B`).
- Boundaries: no PDF awareness.

### 2.5 ProcessingController

- Responsibilities: orchestrate extraction (Tier 1 or Tier 2) and parsing, then matching, then publish the result set to the results view. Owns the cancellable progress token.
- Boundaries: does not know about SwiftUI views. Emits `@Published` state that views observe.

### 2.6 ExtractionService

- Responsibilities: given a PDF and a page set, return the native text layer per page. Decides per page whether text was yielded; when a page yields none, it marks that page unreadable so the UI can name it to the user. No OCR in v1.
- Boundaries: returns a `PageText` value per page. Does not parse, does not match. Opens no subprocess.

### 2.7 FormatAParser

- Responsibilities: parse Format A (bar-association daily board) into a `Board` of `Matter` rows. Hand-written, line-based, measured against real documents.
- Boundaries: pure function of input text.

### 2.8 FormatBParser

- Responsibilities: parse Format B (High Court daily main causelist) into a `Board` of `Matter` rows. Hand-written, line-based.
- Boundaries: pure function of input text.

### 2.9 CaseNumberSweeper (was GenericFallbackParser)

- Responsibilities: for a board matching neither A nor B, emit one row per detected case number carrying the whole printed line as its text. It has no column model, so it cannot mis-column; it keys on the case number, so it cannot drop a matter that prints one. Emits a banner so the UI warns the user to verify every row.
- Boundaries: pure function of input text. Explicitly NOT a third parser — an uncalibrated parser that guesses at columns produces a table that looks like an answer and is wrong, which is worse than no table under this product's falsifier.

### 2.10 FormatDetector

- Responsibilities: pick A, B, or generic fallback based on measured heuristics (e.g. presence of "COURT NO.", presence of "#" in the expected column position, presence of "FOR" blocks).
- Boundaries: returns a `BoardFormat` enum; does not parse.

### 2.11 Matcher

- Responsibilities: given a `Board` and a list of watched names (with optional aliases), return a `MatchResult` of `(matterIndex, matchedSubstring, pageIndex)` triples. Loose by default; alias-precise when aliases are given.
- Boundaries: pure function of inputs.

### 2.12 BoardMerger (was CrossSourceJoiner)

- Responsibilities: when more than one source is loaded, join their rows and take the fuller reading per field, so a name truncated by one board is completed by the other. Office notes from both sources are kept and joined, never overwritten.
- Join key: case number **plus court**. Never case number alone — the same matter is routinely listed before two courts on one day (a part-heard day), and a case-number-only key silently collapses two listings into one, hiding one of them.
- Gating: runs only when more than one source is loaded. On a single-file open it is a no-op, per PRD §6 ("an explicit workflow, not a hidden side effect").
- Deferred to v2: the per-field provenance record and the expandable "from second board" detail in the UI. The repair itself ships; the provenance surface does not.
- Boundaries: pure function of inputs.

### 2.13 ResultsViewModel

- Responsibilities: hold the editable result set. Persist prune state (checkbox, deleted) in memory only. Emit a count summary.
- Boundaries: does not know about the parser.

### 2.14 ExportService

- Responsibilities: render the surviving rows to an A4 PDF with the specified columns, font, line spacing, header repetition, footer "Page N of M", and warm rust accent.
- Boundaries: does not read from the user interface directly. Takes a value type.

### 2.15 SettingsStore

- Responsibilities: read and write UserDefaults for appearance, font scale, and watched names.
- Boundaries: no PDF awareness.

### 2.16 AboutView

- Responsibilities: render the About screen with the privacy and legal posture text.
- Boundaries: static.

### 2.17 Entitlements / sandbox configuration

- File: `NAKASHA.entitlements`.
- Contents:
  - `com.apple.security.app-sandbox = true`
  - `com.apple.security.files.user-selected.read-write = true`
  - Network entitlements: deliberately absent.

## 3. Data models

All value types. `Codable` only where persistence is required.

> **§3 replaced 2026-08-16.** What follows is the model the code actually has and that the
> parsers, matcher, merger, CSV writer and PDF renderer are all calibrated against. The
> previous nested model (`Matter` / `Party` / `Counsel` / `OfficeNote` / `Board`) was never
> built; rebuilding onto it would have been a multi-day refactor of the one proven part of
> the system, delivering no user-visible behaviour and risking the calibration. `Party.side`
> was consumed by nothing — the export has a single "Name of Case" column — and
> `Counsel.aliases` existed only to feed the provenance UI that §2.12 defers.

### 3.1 `PageText`

- `pageIndex: Int`
- `text: String`
- `source: ExtractionSource` (`.native`; a page with no text layer is flagged unreadable)

### 3.2 `ExtractionSource`

- `case native`
- `case ocr`

### 3.3–3.6 `Counsel` / `Party` / `PartySide` / `OfficeNote` — **cut, not built**

Counsel, parties and the office note are plain `String` fields on `BoardRow`. See the note at
the head of §3 for why. Section-band-versus-office-note is not a flag on a value type; it is a
parsing decision taken by column position at read time (flush left is a note, centred is a
band) and it is resolved before a row exists.

### 3.7 `BoardRow` — one matter, as built

Field names mirror the printed board, not a database schema.

- `court: String` — the court head as the board printed it, never inferred.
- `serial: String` — may be empty on a connected matter that shares its parent's serial.
- `caseNumber: String`
- `connectedCaseNumbers: [String]` — matters tagged WITH this one, in board order.
- `caseName: String` — parties as printed, including the source's own truncation.
- `counsels: String` — full counsel text for the matter, both sides, as printed.
- `officeNote: String`
- `section: String` — the band the matter sat under (PART HEARD / FOR ADMISSION / …).
- `category: String` — `Civil` / `Criminal` where the board prints it.
- `sourcePage: Int` — 1-based, for jump-to-page.
- `matchedNames: [String]` — which watched names matched. Empty when no filter ran.
- `matchedOutsideCounselColumn: Bool` — **added by the hard-question pass.** True when the
  watched name was found somewhere other than the counsel column. The row is still returned;
  the UI marks it "verify". Dropping it would trade the permitted error (over-inclusion) for
  the forbidden one (a miss) every time a parse defect misfiles counsel text.
- `id` — `court | serial | caseNumber | sourcePage | ordinal`. The ordinal is required: two
  connected rows under one court on one page both carry an empty serial and the same case
  number, and a SwiftUI `ForEach` silently drops duplicate identities — the falsifier
  arriving from the view layer, where no parser test is looking.

### 3.8 `BoardFormat`

- `case formatA`
- `case formatB`
- `case generic`

### 3.9 `ParsedBoard` — everything read out of one source PDF

- `formatName: String` — e.g. "HCBA Daily Board".
- `title: String`
- `boardDate: String` — as printed, if the document states one.
- `sourceName: String` — file name only. Never the full path: paths leak the user's disk layout.
- `rows: [BoardRow]`

### 3.10 `WatchedName`

- `raw: String`
- `aliases: [String]`
- The raw string is split on `;` into aliases. Empty entries are discarded.

### 3.11 `MatchHit`

- `matterIndex: Int`
- `pageIndex: Int`
- `matchedSubstring: String`
- `matchedName: String`

### 3.12 `MatchResult`

- `hits: [MatchHit]`
- `totalMatters: Int`

### 3.13 `EditableResultRow`

- `matter: Matter`
- `selected: Bool`
- `deleted: Bool`
- `sourceHit: MatchHit`

### 3.14 `ExportTheme`

- `accent: CGColor` — warm rust / terracotta.
- `muted: CGColor` — muted grey for the office-note column.
- Tokens are defined locally; no third-party brand palette is copied.

### 3.15 `ExportRequest`

- `rows: [EditableResultRow]` (only those not deleted)
- `date: String?`
- `courtName: String?`
- `theme: ExportTheme`

## 4. Data flow (ASCII diagram)


              +----------------------+
              |        User          |
              +----------+-----------+
                         |
                         v
              +----------+-----------+
              |      WindowView       |
              |  (SwiftUI chrome)     |
              +----+-----------+------+
                   |           |
       name list   |           |   PDF selection
                   v           v
              +----+----+   +--+----------------+
              | Name    |   |  PDFViewer        |
              | List    |   |  (PDFKit via AppKit)|
              | View    |   +---+---------------+
              +----+----+       |
                   |            | pages
                   v            v
              +----+--------+---+----------------+
              |   ProcessingController           |
              |   (orchestrator, cancellable)    |
              +----+--------------+--------------+
                   |              |
                   |              | per-page text
                   |              v
                   |     +--------+------------+
                   |     | ExtractionService    |
                   |     |  Tier1: PDFKit text  |
                   |     |  Tier2: Tesseract    |
                   |     +---------+------------+
                   |               |
                   |               v
                   |     +---------+------------+
                   |     |   PageText[]         |
                   |     +---------+------------+
                   |               |
                   |               v
                   |     +---------+------------+        +-------------------+
                   |     | FormatDetector      |<------>|  Watched names    |
                   |     +---------+------------+        +-------------------+
                   |               |
                   |               v
                   |     +---------+------------+        +-------------------+
                   |     |  FormatAParser  OR   |        | CrossSourceJoiner |
                   |     |  FormatBParser  OR   |<-------| (optional, on 2nd)|
                   |     |  GenericFallback     |        +-------------------+
                   |     +---------+------------+
                   |               |
                   |               v
                   |     +---------+------------+
                   |     |       Board          |
                   |     +---------+------------+
                   |               |
                   |               v
                   |     +---------+------------+
                   |     |      Matcher         |
                   |     +---------+------------+
                   |               |
                   |               v
                   |     +---------+------------+
                   |     |    MatchResult       |
                   |     +---------+------------+
                   |               |
                   |               v
                   |     +---------+------------+       +----------------------+
                   |     | ResultsViewModel     |<----->| ResultsTable (UI)    |
                   |     |  (editable rows)     |       |  checkbox / delete   |
                   |     +---------+------------+       +----------------------+
                   |               |
                   |               |  Export click
                   |               v
                   |     +---------+------------+
                   |     |   ExportService      |
                   |     |   (PDFKit writer)    |
                   |     +---------+------------+
                   |               |
                   v               v
              +----+---------------+----+
              |   SettingsStore          |
              |   (UserDefaults)         |
              +--------------------------+

Click-through verification: a row in `ResultsTable` carries the `MatchHit`. On click, the view sends `(pageIndex, matchedSubstring)` to the `PDFViewer`, which calls `PDFView.go(to:)` and `PDFView.setCurrentSelection` with a `PDFSelection` constructed from the substring on that page.

## 5. Failure modes

| Failure | Detection | Behaviour |
|---|---|---|
| No text on any page | `ExtractionService` returns empty `PageText` for all pages | Banner: "This PDF appears to be image-only. OCR will run on N pages. The Mac will warm up. You can cancel." Then Tier 2 with visible progress. |
| Mixed native and scanned pages | Some pages return text, some do not | Tier 1 for the native pages; Tier 2 only for the pages without text; per-page progress. |
| OCR cancelled mid-document | User cancels | Cancellation token propagated; partial text retained only for already-processed pages; UI clearly labels which pages were OCR'd. |
| Format detector returns `.generic` | Heuristic score below threshold | Banner: "This board is not in the two known formats. Results may be incomplete. Please verify every row." |
| Both boards loaded for the same date | User loads the second PDF for a date that already has one | `CrossSourceJoiner` runs automatically; UI shows "Fields completed from a second board" with the case-number count. |
| Watched names list is empty | User clicks Process | Every row is returned — this is the "show me the whole board" mode, and it is what the code does. Status line reports "M of M matters". |
| Loose match returns zero hits | `Matcher` returns empty `hits` | Status line: "0 of N matters matched." (Visible silence, not silent silence.) |
| Truncated advocate names in source | `Counsel.display` ends mid-word and a longer `Counsel.aliases` exists from cross-source join | The table shows the printed form by default; an expandable detail shows the fuller form with the source labelled "from second board". |
| Export row overflows the page | Row height exceeds remaining space | Row is moved whole to the next page. Nothing is clipped. |
| Export row is taller than a WHOLE page | Row height exceeds a full page's content box | The row cannot be moved whole — no page can hold it. It is split across pages with a "(contd.)" marker and the case number repeated. "Move it whole" is unsatisfiable here, and silently clipping would trip the secondary falsifier. |
| Column anchors did not resolve | `Anchors` fell through to the gutter fallback, or fewer than three matter rows yielded five segments | Widen matching from the counsel column to the whole row, and warn the user that column detection was uncertain. A geometry misread otherwise becomes a clean, wrong, empty result set. |
| Same case listed before two courts on one day | Two rows share a case number but differ in court | Two rows, always. Never merged — the merge key is case number plus court. |
| Export to user-selected location fails | PDFKit write returns error | Banner with the underlying error; user can pick a different location. |
| App launched without right-click Open | macOS Gatekeeper refuses | README documents the right-click Open flow and `xattr -dr com.apple.quarantine`. The app does not retry. |
| Sandbox denies a write | Sandboxed app attempts to write outside user-selected locations | The user-selected-files entitlement covers the chosen location; outside it, the write is denied. The UI surfaces the error. |
| Network call attempted | Any URLSession, socket, or `Process` invocation not on the bundled Tesseract | The sandbox denies it because no network entitlement is present. (This is the enforcement of the privacy posture.) |
| Tesseract binary missing | Bundle resource not found | Banner: "OCR component missing. Reinstall the app." Tier 2 is disabled. Tier 1 continues. |
| User clears watched names | `NameListView` empties | Persisted as empty array; on next launch the list is empty. |

## 6. Rejected designs and reasons

- Third-party PDF library (PDFbox, PSPDFKit). Rejected: third-party dependency, licensing cost, and PDFKit is sufficient.
- Web view for the PDF. Rejected: third-party feel, search and highlight fidelity is worse, and adds attack surface.
- Cloud OCR (Google Document AI, AWS Textract, Azure Form Recogniser). Rejected for v1: violates offline-only posture. Deferred to v2 as the "Tier 3" hook.
- Local CoreML OCR. Rejected: CoreML/Vision is already declared for link stability, but a real CoreML OCR pipeline requires a model whose accuracy and thermal profile we have not measured against real boards. Deferred.
- Exact matching only. Rejected: would silently miss matters when the source truncates names. Documented in PRD section 7.
- SQLite-backed case management. Rejected: out of scope. Banned.
- Auto-update via Sparkle. Rejected: third-party dependency and a network call. Out of scope. Banned.
- Notarisation. Rejected: explicit owner decision; the README documents the right-click-Open flow.
- Cross-source join as a hidden side effect. Rejected: must be an explicit user-visible workflow because field provenance matters to the advocate.
- CoreData for results. Rejected: no persistence requirement for results in v1. Results live in memory and are pruned live.
- Server-side anything. Rejected. Categorically.

## 7. Build and packaging

- **A SwiftPM package, not an Xcode project** (corrected 2026-08-16 — `Package.swift` and `build.sh` are what exist). Targets: `NakashaCore` (library, no UI, no network), `NakashaApp` (SwiftUI executable), `NakashaCLI` (headless, for calibrating a new court format), and one test target.
- `build.sh` does six steps: build a universal release binary (`--arch arm64 --arch x86_64`), assemble the `.app` bundle and its `Info.plist`, **ad-hoc codesign with `entitlements.plist`**, verify the signature and that the binary launches, build the DMG with `hdiutil`, and report. No Tesseract embedding — there is none in v1.
- DMG layout: `NAKASHA.app`, a `/Applications` symlink, a one-page plain-text README.
- README contents: install instructions including right-click-Open, how to verify no network entitlement via `codesign -d --entitlements`, the privacy and legal posture, the offline guarantee, and a link to the repository.

## 8. Test strategy

- Unit tests for `BarBoardParser` (format A), `MainCauselistParser` (format B), the case-number sweeper, `FormatDetector`, `NameMatcher`, `BoardMerger`, `CSVExporter` and `BoardPDFRenderer`. Each test takes a **synthetic** fixture from `Tests/NakashaCoreTests/Fixtures/` — plain text reproducing a real board's column geometry to the character, with every name, case number and party invented — and asserts on the parsed `ParsedBoard`. **Never a real board sample.** (Corrected 2026-08-16: this line previously said "a real board sample", which contradicted CLAUDE.md rule 4 and the paragraph below it, and is exactly the instruction that put live case numbers into the fixtures in the first place.)
- Regression fixtures are **SYNTHETIC, always**. (Corrected 2026-08-16: this line previously read "real boards saved once and committed", which contradicted CLAUDE.md rule 4, PRD §6 and 04-BMAD-SPEC, and would have committed live litigant names into a public repository.) Fixtures reproduce the column geometry of a real board to the character and invent every party, advocate and judge. Real boards are used for verification by running the CLI against them in place, never by copying them into the tree.
- Thermal test: a manual smoke that OCR on a 50-page scan-only PDF can be cancelled and does not run more than one Tesseract process at a time.
- Manual acceptance checklist mirrored from PRD section 16.
