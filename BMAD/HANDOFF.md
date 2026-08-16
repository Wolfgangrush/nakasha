You are continuing a build that is already specified. Do not re-plan it. Do not ask me what
to build. Read the plan, then build it.

PROJECT: NAKASHA — High Court Board Parser. macOS 13+, Swift 5.9 / SwiftUI, universal binary.
CWD: the repository root

STEP 1 — READ THESE IN FULL, IN THIS ORDER, BEFORE ANYTHING ELSE:
  CLAUDE.md
  BMAD/03-ARCHITECTURE-ESSENTIALS.md
  BMAD/01-PRD.md
  BMAD/02-ARCHITECTURE.md
  BMAD/04-BMAD-SPEC.md
  BMAD/05-SCAFFOLD.md
  BMAD/06-FILTER.md

STEP 2 — THE HARD-QUESTION PASS. This has NOT been done and is mandatory before you write a
line of code. Put 01, 02 and 03 to yourself in one pass and answer, in writing, at the foot
of 03-ARCHITECTURE-ESSENTIALS.md:
    What will break? What edge cases are we missing? What is over-engineered?
Then update 01, 02 and 03 from your own answers and tell me what you changed. Cutting scope
here is a success, not a failure.

STEP 3 — BUILD, in the order given by 05-SCAFFOLD.md §Build order. Working code already
exists under Sources/ from a pre-plan prototype: ~4,000 lines, 54 of 60 tests green, the bar
board parser verified end-to-end on a real 87-page board (717 matters read, name filter
working, PDF and CSV export working). KEEP IT. Rename and reshape it onto the architecture;
do not start from zero.

Known-good and calibrated against real documents — carry forward, do not rewrite from
scratch: LayoutGrid, PDFTextExtractor, BarBoardParser (was HCBADailyBoardParser),
MainCauselistParser, NameMatcher, BoardMerger, BoardPDFRenderer, CSVExporter.

Known-incomplete, needs work: 6 failing tests in MainCauselistParser · NameMatcher has no
LOOSE surname mode yet (this is requirement #1, see 01-PRD) · no PDF viewer pane · results
table is not prunable · export does not yet match the exact spec (Trebuchet MS 12, spacing
1.0, A4, warm rust) · no Settings · no About · no OCR fallback.

AUTHORSHIP — non-negotiable:
  - One person owns each file and reviews every line before it lands. Where AI coding
    assistance is used it writes code; it never owns a file.
  - EVERY TEST IS WRITTEN BY HAND. A test written by the same process that wrote the code
    verifies nothing.
  - Watch for structs mutated through `let` bindings (`if let x = opt { x.field = ... }`,
    `array.last.field = ...`) — it is the most common defect class in this codebase.

TESTING:
  swift build && swift test
  Fixtures are SYNTHETIC and must stay that way — this repo is public and real cause lists
  carry live litigant names. Reproduce column geometry to the character; invent every name.
  Keep real board PDFs OUTSIDE the repository and verify against them by running the CLI in
  place. Never copy one into the tree; `.gitignore` blocks `*.pdf` as a second line of defence.

STEP 4 — THE FILTER. When the code exists, fill BMAD/06-FILTER.md properly: read the code
back against 02/03, restructure until it obeys the architecture, then fix what that exposes,
then sweep the 01-PRD banned-scope list. Write the verdict. Nothing ships unfiltered.

STEP 5 — Fill the A and D sections of 04-BMAD-SPEC.md. Decide SHIP, ITERATE or KILL in
writing.

DO NOT: add third-party dependencies · add any network entitlement or network code ·
notarise or code-sign · copy real board PDFs into the repo · write a bench or city name into the product
name, tagline, repo name or author line · build anything on the banned-scope list.

Start with STEP 1. Tell me what you changed in STEP 2 before you begin STEP 3.
