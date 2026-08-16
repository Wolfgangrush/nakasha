# NAKASHA — Architecture Essentials

Short enough to hold in context every session.

## Stack

- macOS 13+, Swift 5.9, SwiftUI chrome with an AppKit-wrapped PDFKit viewer. PDFKit for native text and export. **No OCR in v1** — a page with no text layer is named to the user, not guessed at (deferred to v2). Apple frameworks only, zero third-party packages, literally. App Sandbox on, user-selected-files read-write, network entitlement absent. **Ad-hoc signed** so the entitlement actually applies; no Developer ID, not notarised.

## Components (one line each)

Names below are the ones in the tree. `NakashaCore` has no UI and no network and is where
everything testable lives; `NakashaApp` is SwiftUI; `NakashaCLI` is the same core, headless.

- ContentView — two-pane SwiftUI layout (left: names + controls + results; right: PDF).
- PDFPane — NSViewRepresentable wrapping PDFKit, with text search, programmatic highlight, jump-to-page. **The verification surface**: it is how the advocate checks the app against the printed board.
- LeftPane — watched names with optional `;`-separated aliases; persisted in UserDefaults.
- AppModel — orchestrator, cancellable; emits `@Published` state.
- PDFTextExtractor — per-page native text via a PDFKit glyph walk with a separate drawn-glyph cursor. Flags a page that yields no text as unreadable.
- LayoutGrid — glyphs to a baseline-grouped, word-placed character grid; gutter detection. Calibrated; carried forward.
- FormatDetector — scores each format and picks the highest; falls through to the sweeper.
- BarBoardParser (format A) / MainCauselistParser (format B) / CaseNumberSweeper (fallback) — line-based, measured against real documents.
- BoardMerger — joins rows across sources on case number **plus court**; takes the fuller reading per field; runs only when more than one source is loaded.
- NameMatcher — loose by default (any-token, wrap-tolerant, truncation-tolerant), alias-precise when `;` alternates are given; pure function.
- ResultsTable — editable rows, in-memory, with a checkbox and a delete per row.
- BoardPDFRenderer / CSVExporter — write the A4 PDF to the §11 spec, and RFC4180 CSV.
- Palette — warm rust and muted grey tokens, light and dark. Our own tokens, no third-party brand palette.
- SettingsView / AboutView — appearance and results-table text size; static privacy and legal text.

## Key types (one line each)

- `PageText` — page index, text, whether the page had a readable text layer.
- `LayoutLine` — one grid row: padded text, first/last ink column, page, width, `slice(from:to:)`.
- `BoardRow` — court, serial, case number, connected case numbers, case name, counsels, office note, section, category, source page, matched names, `matchedOutsideCounselColumn`. Flat by decision, not by accident — see 02 §3.
- `ParsedBoard` — format name, title, board date, source file name, rows.
- `Anchors` — the five column zones of a matter row: item, caseNumber, parties, counselA, counselB.
- `NameMatcher.Entry` — display plus aliases split on `;`. More than one alias = opt into precise mode.
- `NameMatcher.Hit` — display, the exact matched span, occurrence count.
- `BoardService.Input` / `.Result` — the front door: PDFs in, filtered rows plus warnings out.
- `BoardPDFRenderer.Options` — title, subtitle, page size, column visibility.

## The three rules a contributor must not break

1. The app must never make a network call. No network entitlement, no URLSession, no socket, no subprocess that opens a network connection. The Tesseract binary is the only subprocess, and it does not network.
2. The advocate must always verify. Every result is presented with a click-through to the exact printed line. Loose matching is over-inclusive by design; the user prunes. Never silently miss a matter.
3. The source PDF is never copied. Hold it as a reference in memory. Outputs go only where the user picks. Watched names live in UserDefaults on that Mac and nowhere else.

## HARD-QUESTION PASS

Run 2026-08-16, before any code was written, against the prototype as it stood: `swift build`
green, 60 tests, 6 red. Ranked hardest-first. Every claim below was read off the code or the
documents, not assumed.

### What will break

**1. A column-geometry misread silently becomes a zero-result search. This is the falsifier,
and it is live in the tree right now.**
`Anchors` derives the five column zones from item rows, then `Matter.absorb` slices the
counsel columns out of the grid by those anchors, and `filtered(by:)` searches *only*
`row.counsels`. So the chain is: anchors wrong → counsel column sliced from the wrong
character range → the advocate's name is not in the field being searched → **zero hits on a
board the advocate is actually listed on.** No banner, no warning, no exception — a clean
empty table that looks like an answer. The 6 failing tests are exactly this failure in
miniature: `segmentStarts` returns gutter positions instead of run starts, so `parties`
resolved to column 3 instead of 23 and `caseName` came back as the literal string
`WP/7143/2091`. It was caught here only because a test asserted on the party name. Nothing
in the design would have caught it on a real board.
→ Three defences required, not one: fix the anchors; **widen the search to the whole row
whenever anchor detection did not resolve cleanly**; and make the parser say so.

**2. Searching the counsel column only is a precision optimisation guarding the one thing the
app may not get wrong.**
`filtered(by:)`'s doc-comment defends the restriction as "what stops a party who happens to
share the advocate's surname from producing a false listing". But 01 §7 and the 04 falsifier
both say over-inclusion is *the design* and a miss *ends the design*. The restriction trades
the forbidden error for the permitted one. Any parse defect that puts counsel text into
`caseName` — anchor drift, an unseen board, the fallback path — becomes a silent miss.
→ Search the counsel column first; if a watched name appears anywhere else in the row, still
return the row, flagged, so the UI can mark it "matched outside the counsel column — verify".
Never drop it.

**3. `NameMatcher` does not implement loose matching. Requirement #1 of the PRD is absent, and
the test suite currently locks in the opposite behaviour.**
`regex(for:)` joins every token with `\.?\s*` and wraps the lot in `\b…\b`, so it is
exact-match-with-flexible-initials. Measured against the PRD's own worked example,
`ANANTRAO VITHALRAO VANK OLE`:
  - typing `Vankole` → no match (the printed surname has a space inside it)
  - typing `Anantrao Vankole` → no match (token order plus an intervening token)
  - typing `Vernekar` where the board printed `VERNEKA` (field-width truncation) → no match
  - `testSurnameDoesNotBleedIntoALongerSurname` asserts `Tarkel` must NOT match `Tarkele`
That last one is the doctrine inverted: to protect Tarkele from an over-inclusive row that the
user could prune in one click, it drops Tarkel's matter, which is the unrecoverable error.
→ Loose mode is three things, and it needs all three: **any-token** match rather than
all-tokens; **intra-token whitespace tolerance** (`VANK OLE` ≡ `VANKOLE`); and **prefix
tolerance** for truncation (printed `VANKO` is a prefix of typed `VANKOLE`). The
`Tarkel`/`Tarkele` test must be re-specified as a *pass*, not a bar.

**4. The sandbox promise and the signing posture contradict each other in the documents.**
01 §9 and 02 §1 both say "not signed". Entitlements only take effect through a code
signature — an unsigned Mach-O carries no entitlement dictionary, so `com.apple.security.
app-sandbox` would simply not apply and the README's "verify with `codesign -d
--entitlements`" would print nothing. As written, the central product promise is
unenforceable. The *code* already resolves this correctly and the *documents* never caught
up: `build.sh` step 3 ad-hoc signs (`codesign --sign -`) with `--entitlements`, which does
apply the sandbox without any paid certificate and without notarisation.
→ The code is right, the docs are wrong. Amend 01 and 02 to state ad-hoc signature
explicitly, and keep "no Developer ID, no notarisation".

**5. `BoardMerger.merge` collapses on case number, unconditionally, on every load — and the
same case listed before two courts on one day is one key.**
`merge` keys on `normalise(row.caseNumber)` alone. `BoardRow.id`'s own doc-comment says the
opposite in as many words: *"the same matter can be listed before two courts on one day (and
is, on part-heard days), and collapsing those into one identity would hide a listing."* The
merger does precisely that, and it runs on a single-file load too, so it is not gated behind
the two-boards workflow. Court + serial from the second listing are discarded (`row.court =
row.court.isEmpty ? …` keeps the incumbent). **A part-heard matter listed in Court A and
Court B loses one of its two listings.**
→ Key on case number **plus court**, and gate the cross-source repair behind "more than one
source loaded", as 01 §6 requires ("an explicit workflow, not a hidden side effect").

**6. `BoardRow.id` can collide, and a SwiftUI `ForEach` deduplicates collisions by dropping
rows.**
`id` is `court|serial|caseNumber|sourcePage`. A connected/WITH matter carries an empty
serial, and two connected rows under one court on one page therefore produce identical ids.
The UI layer would then drop a matter that the parser read correctly — the falsifier arriving
from the view, where no test is looking.
→ Include the row's ordinal in the identity.

**7. Export diverges from 01 §11 on almost every specified attribute.**
Read off `BoardPDFRenderer` and `BoardService.writePDF`: page is 842×595 **landscape**, spec
says A4; fonts are **Helvetica** 8.5–16pt, spec says **Trebuchet MS 12 / spacing 1.0**;
accents are `CGColor(gray:)`, spec says **warm rust with a muted-grey office column**; the
title string is hardcoded `"HC Board Parser - My Matters"`, and the spec's heading is **the
board's own date**. The column set is the one thing already correct — court · sr · caseno ·
case · counsel · office matches 01 §11 in order.

**8. `sourcePage` is a single page, captured at the item row, but a Format B matter routinely
spans a page break.** The synthetic fixture itself has a footer mid-matter. Click-through will
jump to the first page; a counsel name printed on the matter's *second* page will highlight
nothing, and the advocate will read that as the app having matched the wrong thing.

**9. Tier 2 OCR is the largest unbuilt risk in the plan and nothing about it has been
tested.** `OCRFallback.swift` does not exist. Bundling a `tesseract` binary plus
`eng.traineddata`, executing it as a subprocess from *inside* an App Sandbox, in a build that
must be a **universal** binary — while Homebrew's tesseract is single-architecture — is a
packaging problem, a sandbox-exec problem and an architecture problem stacked on each other.
It also makes "zero third-party dependencies" untrue on its face.

**10. The install instruction may not work on current macOS.** 01 §9 makes right-click →
Open step 1. On macOS 15 and later that path is unreliable for unsigned/ad-hoc apps; the
dependable route is Settings → Privacy & Security → "Open Anyway", or `xattr -dr
com.apple.quarantine`. `build.sh` already prints the `xattr` line, but as the *fallback*.
Getting this wrong means users conclude the app is broken at first launch.

**11. 02 §8 contradicts the synthetic-fixtures law.** It says *"Regression fixtures: real
boards saved once and committed."* CLAUDE.md rule 4, 01 §6, 04's Tests section and the
handoff all say fixtures are synthetic, always, because the repo is public and real cause
lists carry live litigant names. A contributor following 02 would commit a live board into a
public repo.

**12. There is no cancellation token anywhere in Core.** 02 §2.5 makes the cancellable
progress token the `ProcessingController`'s defining responsibility. `BoardService.run` is a
synchronous `for` loop over URLs. On an 87-page board the UI will simply block.

### Edge cases missed

1. **The advocate is the Government Pleader / Addl. P.P.** The counsel column prints `GP` or
   `ADDL. P.P.` with no name at all, so no watched name can ever match, on every matter they
   are actually in. Nothing in the design addresses this, and it is a whole category of user.
2. **A matter with the same advocate on both sides**, and matters where the counsel column is
   blank entirely — currently unmatchable by construction.
3. **A row taller than a whole page.** 02 §5 says an overflowing row "is moved whole to the
   next page. Nothing is clipped." A row taller than a *full* page can never satisfy that
   rule; it must split with a "(contd.)" marker or it is lost. This is the secondary
   falsifier and the stated rule is impossible as written.
4. **Devanagari / Marathi party names.** Several benches print them. Every regex here is
   anchored on `[A-Z]` and uppercase Latin.
5. **The board date is not detected** → the export heading falls back to "Date not detected",
   but 01 §11 makes the date the heading. There is no user-editable date field.
6. **The same PDF loaded twice** — duplicate rows, and the merger cannot tell it from a
   genuine second source.
7. **A watched name typed with a leading `#`** is silently discarded as a comment. `#` is
   Format A's own party separator, so a user pasting a board line in loses it without being
   told.
8. **Empty watched-name list**: 02 §5 says status "Type at least one name"; `BoardService`
   returns *every* row unfiltered. The code's behaviour is the better product (it is the
   "show me the whole board" mode) — the document should move, not the code.
9. **Connected/WITH matters carry no serial**, so the export's "Sr." column is blank for them
   and sorting by serial reorders them away from their parent.

### Over-engineered — cut before building

**CUT 1 — Tier 2 OCR / bundled Tesseract → v2.** This is the biggest available scope cut and
it costs nothing measured. 01 §8 records the measurement itself: both real boards are 100%
text-native, 87 pages and 22 pages, **0 pages needing OCR**. In exchange for a case that has
never occurred in the corpus we would take on a bundled third-party binary, a universal-vs-
Homebrew architecture conflict, sandbox exec, thermal discipline, a cancellation protocol and
a progress UI. Replace the whole tier with: **detect a page with no text layer and say so
plainly** — "page 4 has no text layer; NAKASHA cannot read it, check that page by eye". That
is honest, it is ~20 lines, it never loses a matter silently, and it makes "zero third-party
dependencies" literally true.

**CUT 2 — the `Matter` / `Party` / `Counsel` / `OfficeNote` / `Board` model in 02 §3.** The
code has a flat `BoardRow` / `ParsedBoard` that is calibrated against two real documents and
already drives the parsers, matcher, merger, CSV and PDF renderer. Rebuilding onto the
document's nested model is a multi-day refactor of the one part of the system that is proven,
it delivers zero user-visible behaviour, and it puts the calibration at risk. `Party.side` is
consumed by nothing — the export has one "Name of Case" column, a single string.
`Counsel.aliases` exists only to display cross-source provenance, which is CUT 3.
→ **Amend 02 §3 to document `BoardRow`/`ParsedBoard` as built.** Add only the one field that
earns its place: `matchedOutsideCounselColumn`, which is falsifier defence (§What will break
#2).

**CUT 3 — the cross-source provenance UI.** Keep `BoardMerger` (it repairs truncated names,
which is real value). Cut 02 §5's "expandable detail showing the fuller form labelled *from
second board*" and the per-field provenance record in 02 §2.12. That is a whole UI surface
for a workflow that needs the advocate to hold two different PDFs for the same date.

**CUT 4 — `GenericFallbackParser` as a third parser.** A third uncalibrated parser whose
output the user is told not to trust is a liability under this falsifier: a mis-columned
table is worse than no table, because it *looks* like an answer. Cut it down to a **case-
number sweeper** — one row per detected case number carrying the whole raw line as text. It
cannot mis-column anything because it does not have columns, and it cannot lose a matter that
prints a case number. That is ~30 lines instead of a parser.

**CUT 5 — Vision.framework "declared, not used, to keep the link surface stable".** Linking a
framework you never call costs launch time and buys a question you then have to answer in
every privacy review. Cut it.

**CUT 6 — the general UI font-size control → narrow, don't delete.** 01 §10's reason is real
(13-inch to 27-inch). But threading a font-scale token through every view is a day's work for
something macOS already does system-wide. Narrow it to a **table text-size stepper on the
results table only**, which is the one place the reason actually bites.

**CUT 7 — `showSerial` / `showSection` toggles on `BoardService.Input`.** 01 §11 fixes the
export columns. Two switches that reshape the export are scope that arrived without a
decision. Keep them internal or drop them.

**CUT 8 — the `DumpTool` executable target.** A third binary in `Package.swift` that appears
nowhere in 02 or 05. Fold it into the CLI as a subcommand, or delete it.

### Changes made to 01, 02, 03 as a result

| # | File | Change |
|---|---|---|
| 1 | 01 §4, §8, §12, §13, §16 | Tier 2 OCR and the bundled Tesseract deferred to v2; v1 detects and reports a page with no text layer. Dependency list becomes Apple frameworks only — "zero third-party dependencies" now literally true. Acceptance item 9 rewritten accordingly. |
| 2 | 01 §4, 02 §1 | Vision.framework removed (CUT 5). |
| 3 | 01 §6 | Generic fallback narrowed from a third parser to a case-number sweeper (CUT 4). |
| 4 | 01 §6, 02 §2.12 | Cross-source repair gated behind "more than one source loaded"; provenance UI deferred (CUT 3). |
| 5 | 01 §7 | Loose matching specified concretely — any-token, intra-token whitespace, prefix/truncation tolerance — and the `Tarkel`/`Tarkele` doctrine inverted to over-inclusion. |
| 6 | 01 §9, 02 §1, §7 | Signing corrected to **ad-hoc signature** so the sandbox entitlement actually applies; still no Developer ID, still no notarisation. Install step 1 corrected for current macOS: `xattr -dr com.apple.quarantine` / "Open Anyway" is primary, right-click-Open secondary. |
| 7 | 01 §10 | Font-size control narrowed to the results table (CUT 6). |
| 8 | 02 §3 | Nested `Matter`/`Party`/`Counsel`/`OfficeNote`/`Board` model replaced by the built `BoardRow`/`ParsedBoard`, plus `matchedOutsideCounselColumn` (CUT 2). |
| 9 | 02 §2.6 | `ExtractionService` Tier 2 replaced by "reports a page with no text layer". |
| 10 | 02 §5 | Three failure modes added: anchor detection unresolved → widen the search to the whole row and warn; a row taller than a page → split with "(contd.)"; the same case listed before two courts → two rows, never merged. |
| 11 | 02 §7 | "Single Xcode project" corrected to the SwiftPM package + `build.sh` that actually exists. |
| 12 | 02 §8 | **"Regression fixtures: real boards saved once and committed" deleted** — it contradicted CLAUDE.md rule 4, 01 §6 and 04, and would have put live litigant names in a public repo. |
| 13 | 03 | This pass recorded; Components and Key types below rewritten to the names that exist in the tree and to the post-cut scope. |
| 14 | 01, 02, 03 | Stray `<content>` wrapper tags removed from the head and foot of the files. |
