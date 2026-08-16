# 06 — FILTER  ·  NAKASHA

**Date:** 2026-08-16 · **Run AFTER the code exists, BEFORE you call anything done.**

> The author, 2026-08-16, defining it: *"You assess your own work and distill it… Once you have
> built all the 6 files, what happens later? You see the code and restructure it in a way
> that is given in the architecture essentials or architecture.md. Once you do that you
> start to see if there is any mistake in it. If there is, you fix it. Filtering in my
> particular sense meant fixing it in a way that it is following the protocol of
> architecture.md. Once that happens you move on."*

**The filter is a convergence loop, not a selection loop.** It does not choose between
approaches — `01-PRD.md` already did that. It drags the code back onto the architecture it
was supposed to follow, and it is the difference between a codebase and a pile.

Nothing ships with this file unfilled.

---

## Pass 1 — read the code against the architecture

| # | Architecture says | Code actually does | Verdict |
|---|---|---|---|
| 1 | `WindowView` — three-pane SwiftUI layout | `ContentView` — **two**-pane `HSplitView`; the "third pane" is the results table stacked inside the left column | drifted → **02/03 amended** to two panes, which is what 01-PRD §5's own layout description actually specifies (left upper, left lower, right) |
| 2 | `PDFViewer` — NSViewRepresentable over PDFKit, search, highlight, jump | `PDFPane` — exactly that, plus a degrading prefix retry when the full phrase is not contiguous in the extracted text | matches (name updated in 02/03) |
| 3 | `NameListView` | folded into `ContentView.namesEditor` | drifted → recorded; a separate view for one `TextEditor` is not worth a file |
| 4 | `ProcessingController` with a cancellable progress token | `AppModel` orchestrates off the main thread; **no cancellation token** | **missing** — see Pass 3 #6 |
| 5 | `ExtractionService`, Tier 1/Tier 2 | `PDFTextExtractor`, Tier 1 only | matches post-cut (Tier 2 deferred to v2) |
| 6 | `FormatDetector` picks A, B or fallback | `FormatDetector` scores each `BoardFormat` and picks the highest | matches |
| 7 | `FormatAParser` / `FormatBParser` / `GenericFallbackParser` | `BarBoardParser` / `MainCauselistParser` / `GenericBoardParser` | matches (names updated in 02/03) |
| 8 | `CrossSourceJoiner` | `BoardMerger`, now source-aware and gated on >1 source | matches after Pass 3 #1 |
| 9 | `Matcher` — loose by default, alias-precise | `NameMatcher` — loose by default, `;` opts into precise | matches |
| 10 | `ResultsViewModel` — editable rows, checkbox, delete | `ResultRow` + `ResultsTable` hold it; there is no separate view-model type | drifted → acceptable; the state is `@Published` on `AppModel` |
| 11 | `ExportService` | `BoardPDFRenderer` + `CSVExporter` behind `BoardService.writePDF/writeCSV` | matches |
| 12 | `SettingsStore` | `SettingsStore` — appearance + results-table text size | matches post-cut |
| 13 | `AboutView` | `AboutView` | matches |
| 14 | Entitlements: sandbox on, no network | `entitlements.plist` exactly that, applied by an **ad-hoc signature** in `build.sh` | matches — after 01/02 were corrected; the docs had said "unsigned", which would have meant no sandbox at all |
| 15 | — (authorised by nothing) | `DumpTool` executable target | **extra** → removed |
| 16 | — | `Anchors`, `LayoutGrid`, `ColumnDetector` | **extra but load-bearing**; the architecture never named the layout-grid layer that both parsers stand on → **02/03 amended** to name it |

## Pass 2 — restructure to match

| # | Change made | Which architecture line it now obeys |
|---|---|---|
| 1 | `BoardParserCore/App/CLI` → `NakashaCore/NakashaApp/NakashaCLI`; `HCBADailyBoardParser` → `BarBoardParser` | 05-SCAFFOLD build order step 2 |
| 2 | Product/bundle identity → `NAKASHA`, `net.wolfgangrush.nakasha`; window title, export title, UserDefaults keys all follow | 01-PRD §1 |
| 3 | `DumpTool` target deleted | 01-PRD §13 — nothing in the tree that no document authorises |
| 4 | Its one useful capability re-homed as `nakasha-cli --dump-lines` | 02 §2, the CLI's stated second job: calibrating a new court format |
| 5 | Two copies of `columnSpecs()` (one in `TableDriver`, one in `PageEstimator`) collapsed into a single `ColumnPlan` | 02 §2.14 — one component, one responsibility |
| 6 | `BoardRow` gained `matchedOutsideCounselColumn`, `sourceFile`, `ordinal` | 02 §3.7 as amended |
| 7 | Export/CSV column order set to Court · Sr. · Case No. · Party · Office note · Counsel | 01-PRD §11, per the owner's decision of 2026-08-16 |

| # | Architecture amended | Why the code was right and the doc was wrong |
|---|---|---|
| 1 | 02 §1, §7 · 01 §9 — signing | The docs said "not signed". Entitlements live inside the code signature, so an unsigned binary would have **no sandbox and no verifiable entitlement list**, and the offline guarantee would be unenforceable. `build.sh` already ad-hoc signed. Code right, docs wrong. |
| 2 | 02 §3 — data model | The nested `Matter`/`Party`/`Counsel`/`OfficeNote` model was never built. The flat `BoardRow` is calibrated against two real boards and drives every consumer. Rebuilding onto the doc's model delivers no user-visible behaviour and risks the calibration. |
| 3 | 02 §7 — build | "A single Xcode project" does not exist and never did. It is a SwiftPM package plus `build.sh`. |
| 4 | 02 §5 — empty watched-name list | The doc said "no-op, ask for a name". The code returns every row, which is the more useful behaviour ("show me the whole board"). Doc moved to the code. |

## Pass 3 — now look for mistakes

With the shape correct, defects became visible that the mess was hiding.

| # | Mistake | How found | Fix | Test that now covers it |
|---|---|---|---|---|
| 1 | `BoardMerger` keyed on case number alone, and ran on single-file loads. The same matter listed before two courts on one day collapsed into one row — one of the two courts the advocate is due in silently disappears. `BoardRow.id`'s own doc-comment forbids exactly this. | Reading the merger against 01-PRD §6 | Merge only ACROSS sources; within one board a repeated case number is a second listing and is kept. Gated on >1 source. | `FalsifierTests.testTheSameCaseBeforeTwoCourtsInOneBoardStaysTwoRows`, `…SurviveEvenWhenASecondSourceIsLoaded` |
| 2 | `Anchors.segmentStarts` returned the column where a blank run *reached* the gap threshold — a position inside the gutter, not the start of the next field. Every anchor sat one zone left; the party column swallowed the case number. | The 6 pre-existing red tests | Return the first **inked** column of each run. | `MainCauselistParserTests` (all 12), and the 6 originally-red tests |
| 3 | **The anchor plan fitted one set of absolute columns to a whole document.** A real causelist prints page 1 at origin 0, later pages at 2, others at 5 — same template, three different origins. Whole-document anchors are therefore wrong for most of the file: the party column began inside `SECONDNAME`, the counsel column inside `NUKARI`. Because the matcher searches the counsel column, a surname split across a misplaced boundary is a **missed listing**. | Running the CLI against the real board — the synthetic fixture passed throughout | Learn the **shape** (offsets from the item column) once for the document, and the **origin** per page. Case-number column read from the `itemRow` regex, never guessed. Zone boundaries found with a wide gap so ordinary padding inside a party name is not mistaken for a column. | `MainCauselistParserTests.testParsingIsUnchangedWhenTheWholeBoardIsIndented` |
| 4 | Zone boundaries taken at the **mode** of a jittering cluster. Columns move ±1 between pages, and the error is asymmetric: one column late eats the first letter (`NUKARI` → `AVERI`); one column early picks up blank padding and costs nothing. | Real-board output after fix #3 | Place each boundary at the low edge of its cluster, trimmed to ±2 of the mode. | same as #3 |
| 5 | `filtered(by:)` searched the counsel column only. Any parse defect that misfiles counsel text elsewhere becomes a clean, empty, wrong answer. | Hard-question pass | Search counsel first; if the name appears elsewhere on the row, keep the row and flag it. The S/O guard still suppresses a party's father's name. | `FalsifierTests.testANameFoundOutsideTheCounselColumnStillProducesARowAndIsFlagged`, `…RelationshipGuardStillHolds…` |
| 6 | `BoardRow.id` could collide for two connected matters under one court on one page (both empty serial, same case number). SwiftUI drops duplicate identities — a matter vanishing in the view layer, where no parser test looks. | Hard-question pass | `ordinal` added to the identity, stamped by `BoardService`. | `FalsifierTests.testEveryRowInAResultSetHasAUniqueIdentity` |
| 7 | With several PDFs loaded, a result row could not say which document it came from, so click-through would open the wrong file at that page number. | Writing the integration | `BoardRow.sourceFile`, stamped at parse time; `reveal()` opens the owning document. | covered by the type; exercised by the CLI end-to-end run |
| 8 | `latestBoards` re-extracted and re-parsed **every PDF on every save** — 87 pages of work to fill in a subtitle. | Reading `AppModel` | Boards cached from the run. | — (performance, not correctness) |
| 9 | Click-through highlighted the matched *name*. The advocate's name is exactly the string the board truncates and wraps, so the highlight would often fail. | Writing `reveal()` | Highlight the **case number**, which is printed exactly as read. | — |
| 10 | `PDFPane` used two `PDFView` members that do not exist (`isEditing`, `isPageBreakModeEnabled`), and bound `findString`'s non-optional array with `guard let`. | Compiler, on landing the delegate's file | Removed / corrected. | build |
| 11 | Loose matching compiled a pattern for every token, so a firm name (`Vankole and Associates`) produced `\bAND` and matched most of the board. | Reviewing the delegate's noise list | Joining words added to `noiseTokens`. | `NameMatcherTests.testInitialsAndHonorificsAreNotSearchTerms` |
| 12 | **No cancellation token anywhere** (02 §2.5 requires one). `BoardService.run` is a synchronous loop. | Pass 1 #4 | **NOT FIXED — carried.** Measured cost: a real 87-page, 717-matter board parses in **2.4 s**, so there is nothing to cancel yet. Recorded as the one known divergence rather than silently dropped. | — |

## Pass 4 — banned-scope sweep

| # | Banned item | Present in code? | Removed / deferred to |
|---|---|---|---|
| 1 | External API calls of any kind | No. No `URLSession`, no socket, no `Process`. | — |
| 2 | OCR / bundled OCR binary | No | deferred to v2 (01-PRD §8) |
| 3 | Notarisation or signing pipeline | Ad-hoc signature only; no Developer ID, no notary submission unless the operator sets `DEVELOPER_ID` | as specified |
| 4 | Cloud sync, accounts, multi-device | No | — |
| 5 | Case management, calendar, reminders, notifications | No | — |
| 6 | Editing or annotating the source PDF | No. `PDFPane` selects text; it never writes, copies or annotates. | — |
| 7 | Scraping court websites | No | — |
| 8 | Court formats beyond the two named plus a fallback | Two parsers plus `GenericBoardParser` | — |
| 9 | Analytics of any kind | No | — |
| 10 | Real board PDFs in the repo | No. Fixtures are synthetic; the real boards were read in place from outside the repository. | — |
| 11 | Bench or city name in product identity | Not in the product name, tagline, bundle id, author line, README or any UI string. It appears only in `01-PRD.md`'s supported-formats note and in the rules that forbid it. | — |

Verification command run: a bench/city-name sweep across the tracked tree

## Verification against reality, not against ourselves

The suite is synthetic by law, so the suite alone cannot tell us the parser works. Run against
the real boards via the CLI on 2026-08-16:

| Check | Result |
|---|---|
| Bar board, 87 pages | **717 matters** read in **2.4 s** (target: under 3 minutes) |
| Causelist, format B | 74 matters, columns correct after Pass-3 #3/#4 |
| Both loaded together | 791 matters, cross-source repair active |
| **Zero-miss, matcher** | run with a real watched surname (not reproduced here — the boards carry live litigant data). Raw PDF text contained that surname **twice**; the parser produced 2 rows carrying it; the matcher returned **2 of 2** |
| **Zero-miss, the wedge** | on that run the surname was printed hard-wrapped mid-word, as `SURNA ME`. Exact matching scores `\bSURNAME\b` against that and returns **nothing**. This is the falsifier, reproduced on a real board, and closed. |
| Export | A4 landscape PDF written; header reads `COURT · SR. · CASE NO. · CASE · OFFICE NOTE · COUNSEL`; both matters present |

---

## Exit criteria

- [x] Every component in `02-ARCHITECTURE.md` maps to code, and every module in the code maps
      back to `02`. No orphans in either direction (`DumpTool` removed; `LayoutGrid`/`Anchors`
      added to the document).
- [x] `03-ARCHITECTURE-ESSENTIALS.md` still describes the code accurately; it was updated.
- [x] Nothing from the `01-PRD.md` banned-scope list survives in the tree.
- [x] Test suite green — **74 tests, 0 failures** — and every Pass-3 fix that is a correctness
      defect has a test that would catch it returning. The two exceptions are recorded above
      as performance (#8) and a carried divergence (#12).

## Verdict

- [x] **CONVERGED** — the code follows the architecture protocol. Move on to `04-BMAD-SPEC.md`
      A and D sections.
- [ ] ANOTHER PASS NEEDED — name the one thing still diverging: ______

**One divergence is carried knowingly, not silently:** there is no cancellation token
(Pass 3 #12). It is recorded here, in 02 §2.5, and in 04's ANALYZE section. At 2.4 seconds for
the largest real board it buys nothing today; it becomes necessary the day a slower path
appears, which in practice means the day Tier 2 OCR lands in v2.

---

*Where this sits: `01`–`05` are written before code. `06` is written after it. Together they
are the loop — plan, build, then drag the build back onto the plan.*
