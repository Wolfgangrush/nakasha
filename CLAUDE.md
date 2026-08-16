# NAKASHA — High Court Board Parser · agent instructions

**Read `BMAD/03-ARCHITECTURE-ESSENTIALS.md` before touching code.** Full record:
`BMAD/02-ARCHITECTURE.md`. Scope contract: `BMAD/01-PRD.md`. Falsifier and cut-over:
`BMAD/04-BMAD-SPEC.md`. Build order: `BMAD/05-SCAFFOLD.md`.

## Scope

Build only what `01-PRD.md` lists. Its **banned scope** section is not a suggestion —
anything on it is deferred, not debated. If a feature seems obviously needed and is on that
list, that is the list doing its job.

## Authorship

- Where AI coding assistance is used, **one person owns each file** and reviews every line
  before it lands. The assistant writes code; it never owns a file.
- **Tests are always written by hand.** They are the verification surface, and a test written
  by the same process that wrote the code verifies nothing.

## Rules for this codebase

1. **Zero third-party dependencies.** Foundation, PDFKit, CoreGraphics, CoreText, AppKit,
   SwiftUI, UniformTypeIdentifiers only, plus a bundled Tesseract binary for tier 2. If a
   problem seems to need a package, it needs a simpler solution instead.
2. **No network code. Ever, in v1.** `entitlements.plist` grants no network entitlement, so
   the sandbox denies sockets regardless of what any code tries. Do not add the entitlement.
   Do not import anything that opens a connection. The absence is the product promise.
3. **Never lose a matter.** This is the one failure the app cannot have. Prefer
   over-inclusion at every fork: in matching, in parsing, in pagination. When a choice is
   between dropping an ambiguous row and showing a wrong-looking one, show it.
4. **Fixtures are synthetic, always.** Real cause lists carry live litigant names and this
   repo is public. Reproduce column geometry to the character; invent every name.
5. **Never write a bench or city name into product identity** — not the name, tagline, repo, or author
   line. It may appear once in the supported-formats table as a board the app reads. This is
   a de-anonymisation rule for the publisher, not a style preference.
6. **The source PDF is read-only.** Never copy it, never modify it, never write beside it.
   Outputs go only where the user chose.

## Facts about the input, measured — do not re-derive

- Court board PDFs are **proportional, not monospaced**, despite looking fixed-width.
- PDFKit's `characterBounds(at:)` indexes **drawn glyphs**; `page.string` also contains the
  newlines PDFKit inserts, which draw nothing. Walking them in lockstep desynchronises the
  text from its positions and shuffles the output. Keep a separate glyph cursor.
- Group lines by **baseline**, never by glyph top; merge tiny raised groups (the apostrophe
  in `HON'BLE`, the `th` in `17th`) back into their line.
- The bar board hard-wraps **mid-word without a hyphen**; rejoin by whether the line filled
  its field box, not by inserting a space.
- Format B's office note is **flush left**; a centred `FOR ...` line is a section band. Tell
  them apart by column, never by the word.

## What must never happen here

An advocate is listed on the board, runs NAKASHA, and does not see the matter. That is the
falsifier in `04-BMAD-SPEC.md` and it ends the design.

## Verify

```
swift build && swift test
```

Then the real check: run the CLI against a real board and hand-count the matters for one
surname against the printed page.

## Before calling anything done

Run the FILTER — `BMAD/06-FILTER.md`. Read the code back against `02`/`03`, restructure
until it obeys, fix what that exposes, sweep the banned-scope list. Verdict written:
CONVERGED, or ANOTHER PASS naming the divergence. Nothing ships unfiltered.
