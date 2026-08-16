<!-- Section list VERBATIM from brain/BMAD_DISCIPLINE.md §THE BMAD-SPEC.md TEMPLATE,
     locked 2026-06-07. This is file 04 of NAKASHA; it carries the falsifier and the
     cut-over criterion that the six-file workflow has no slot for. -->

# BMAD-SPEC — NAKASHA · High Court Board Parser

**Date:** 2026-08-16
**Owner:** the publisher
**Builder:** the publisher, with AI coding assistance for component drafts
**Review:** tests, verification and this spec written by hand; the About text reviewed for
legal-surface accuracy before release

## B — BUILD

### Problem

An advocate must locate their own matters in a daily board PDF running to 87 pages and 700+
matters, by eye, every morning, under time pressure. Matters get missed. A missed listing is
not an inconvenience — it is an absent advocate.

Observed incident grounding this build: on a real bar-association board, a watched surname is
printed hard-wrapped mid-word by the fixed-width export — `VANKOLE` comes out as `VANK OLE`.
Any tool relying on exact-name matching returns nothing and the advocate concludes, wrongly,
that they are not listed.

(The name above is invented. The real board that demonstrated this carries live litigant and
advocate names and is not reproduced, quoted or identified anywhere in this repository — and
neither is the person whose listing revealed the defect.)

### Solution shape

A single-window macOS app. The advocate drops in one board PDF; it renders on the right,
readable and searchable. On the left they type surnames; a deliberately loose match produces
an over-inclusive result table; they prune the rows that are not theirs, verifying each
against the PDF beside it — clicking a row jumps and highlights. Export writes the survivors
to an A4 table. Nothing leaves the Mac.

### Inputs

- Board PDF, user-selected via drag-drop or open panel · one per run (two when merging) ·
  read-only · no rate limit, no network.
- Watched names, free text, one per line, `;`-separated aliases permitted · persisted in
  local user defaults on that Mac only.

### Outputs

- Export PDF · user-chosen path · A4 · Trebuchet MS 12pt / spacing 1.0 · columns
  Court | Sr. | Case No. | Case | Counsel | Office note · heading = the board's own date.
- Export CSV · user-chosen path · RFC4180.
- Nothing else. No caches, no logs, no telemetry, no copies of the source PDF.

### Components

- **App** (SwiftUI, macOS 13+): two-pane window, Settings (appearance / font size), About.
- **Core** (no UI, no network): extract → detect format → parse → merge → match → render.
- **CLI** (`nakasha-cli`): same core headless, for calibrating a new court format.
- No engine, no daemon, no launchd job, no MCP server.

### Banned scope

No external API calls in v1 (deferred to v2) · no notarisation/signing pipeline · no cloud
sync, accounts or multi-device · no case-management, calendar, reminders or notifications ·
no editing or annotating the source PDF · no scraping court websites · no court formats
beyond the two named plus a generic fallback · no analytics of any kind.

## M — MEASURE

### Tests

- [ ] Unit: layout grid (baseline grouping, word-run placement, gutter detection) · name
      matcher (loose surname match, alias syntax, S/O guard, word boundaries) · both format
      parsers against SYNTHETIC fixtures · merger · CSV · PDF renderer.
- [ ] Integration: end-to-end on a real board via the CLI — extract, parse, filter, export.
- [ ] Smoke: app launches; drop a PDF; Process; click a row; PDF jumps and highlights;
      prune a row; Export; open the resulting PDF.

**Fixtures are SYNTHETIC.** Real cause lists carry live litigant names and this repository is
public. Fixtures reproduce the column geometry to the character and invent every name.

### Real-usage metrics

- **Zero-miss:** on a board hand-checked by the publisher, every matter carrying a watched surname
  appears in the result set before pruning. Target: 100%. Measured by hand-count against the
  printed board, not by the parser's own report.
- **No lost matters in export:** rows counted in = rows counted out, across a page break and
  with an office note longer than one page. Target: exact equality.
- **Thermal:** OCR never fires on a text-native board. Target: 0 Tesseract invocations on
  the two known formats. Measured by instrumenting the tier decision.
- **Time:** 87-page board processed in under 3 minutes on an M-series laptop.

### Observation window

Five consecutive court days of real boards before any metric is treated as valid, and at
least one board from each of the two formats.

## A — ANALYZE

*Filled 2026-08-16, at the end of the build session.*

### What worked

- **The hard-question pass before any code paid for itself immediately.** It cut Tier 2 OCR
  (the measurement was already in the PRD: 109 real pages, zero needing OCR), cut a data-model
  refactor that would have delivered no user-visible behaviour, and caught that the documents
  said "not signed" while the sandbox promise requires a signature. Three cuts and a
  correction, none of which needed code to discover.
- **Delegating components and keeping integration.** Component drafts (the loose matcher, the
  results table, the PDF pane, the chrome) were assisted; every test was written by hand, one
  person owned every file, and the wiring was done by hand. Where an assisted draft failed it
  failed *locally* and the compiler or a test caught it — invented `PDFView` members, a loop
  that never reset its flag, a noise list that let `\bAND` through.
- **Loose matching is the product.** Verified on the real board: the watched surname is
  printed hard-wrapped mid-word, as `VERNE KAR`. Exact matching returns nothing.
  (The other party and counsel names on that board are live litigant data and are not
  reproduced here, or anywhere in this repository.)
- **Speed was never a problem.** 87 pages, 717 matters, 2.4 seconds. The 3-minute target and
  the cancellation machinery designed around it were both solving a problem that does not
  exist at this scale.

### What didn't

- **The synthetic fixture passed the whole time the parser was broken on the real document.**
  This is the finding that matters most. Format B parsed the synthetic causelist perfectly and
  produced garbage on the real one — `<party column>` / `<counsel column>` — because the fixture has a
  single page origin and the real board has three (page 1 at column 0, later pages at 2 and 5).
  A synthetic corpus can only encode the variation its author already knows about. **Fixtures
  prove a parser has not regressed; only a real document proves it works.** The rule stands —
  fixtures stay synthetic, the repository is public — but every format needs a real-document
  run recorded in `06-FILTER.md` before it is believed.
- **Two agent round-trips were spent on one function** (`segmentStarts`) before it was correct,
  and a third on a variant. The handoff's two-round-trip rule was the right call.
- **Prose drafting did not delegate usefully.** Both README attempts came back empty; the
  README was written by hand in the end.
- **My own first fix for the merge was wrong.** Adding court to the join key protected the
  part-heard double listing and broke the cross-source repair, because the two sources print
  the court differently for the same matter. The existing test caught it in one run. The
  correct rule was not "a better key" but "merge only across sources".

### What user observed that spec didn't anticipate

- **Owner decision, 2026-08-16: advocates are "100% going to search with the surname."** The PRD hedged —
  loose matching with an alias syntax "for users who want precision". That is now inverted:
  surname-first is the design centre, and the alias syntax is the escape hatch.
- **The owner's column order differs from the PRD's.** He asked for office note BEFORE counsel;
  §11 had counsel fifth. His order shipped, in both the PDF and the CSV.
- **"The PDF we are going to process already has an OCR, that's not going to be an issue"** —
  independent confirmation of the cut that the hard-question pass had already made on measured
  grounds.
- **A4 needed an orientation.** §11 says "A4" and fixes Trebuchet MS 12, but does not say
  portrait or landscape. Six columns across portrait A4 is roughly ten characters per column
  at that size. Landscape shipped, and the reasoning is recorded in the renderer so nobody
  "corrects" it later.

## D — DECIDE

- [x] **SHIP** — as v1, to the publisher alone first, against the cut-over criterion below.
- [ ] ITERATE (specifically: <name the one failure to redesign>)
- [ ] KILL (specifically: <which falsifier proved this wrong>)

**Why SHIP and not ITERATE.** The falsifier was tested against a real board rather than
argued about, and it did not fire: the raw PDF text contains the watched surname twice, the
parser produced two rows carrying it, and the matcher returned two of two — including the
mid-word-wrapped `VERNE KAR` that exact matching cannot find. Both formats parse, both exports
carry the specified columns, the suite is 74 green, and nothing on the banned-scope list is in
the tree.

**What SHIP does not mean.** It does not mean public release. The cut-over criterion below is
untouched and unmet: ten consecutive court days of hand-verified output. Until then this is an
assistant to the manual read, the About screen says exactly that, and it goes to nobody but
The author. Publishing to GitHub is a separate decision that needs those ten days first.

**Known divergence carried into the ship, not hidden by it:** there is no cancellation token
(`06-FILTER.md` Pass 3 #12). At 2.4 seconds for the largest real board there is nothing to
cancel. It becomes necessary the day a slow path appears — in practice, the day Tier 2 OCR
lands in v2.

### Falsifier

**An advocate runs NAKASHA on a real board, prunes nothing, and a matter in which they are
actually listed does not appear in the result set.**

One such miss falsifies the design, because the entire product promise is that the advocate
can stop reading 87 pages by eye. A tool that is right most mornings is worse than no tool:
it replaces a reliable habit with an unreliable one. Over-inclusion is not a falsifier —
that is the design, and pruning is the user's job.

Secondary falsifier: a matter present in the result table is absent from the exported PDF.

### Cut-over criterion

The manual read of the board stops being authoritative only after **ten consecutive court
days on which the author has hand-verified the app's output against the printed board and found
zero misses**, across both formats. Until then the app is an assistant to the manual read,
and the About screen says so in those words.

For other advocates the cut-over is never asserted at all — the About screen states
permanently that the advocate remains responsible for verifying every listing against the
board itself. That is both a Bar-Council-facing and a liability-facing position, and it does
not expire.
