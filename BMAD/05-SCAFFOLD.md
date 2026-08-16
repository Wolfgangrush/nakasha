# 05 — SCAFFOLD  ·  NAKASHA

**Date:** 2026-08-16

The tree exists before features. Empty folders and barely-drafted files included: the point
is to hand the builder a bounded scope before asking it to fill anything in.

## Tree

```
nakasha/
├── BMAD/                          <- the plan. 01..06
│   ├── 01-PRD.md
│   ├── 02-ARCHITECTURE.md
│   ├── 03-ARCHITECTURE-ESSENTIALS.md
│   ├── 04-BMAD-SPEC.md
│   ├── 05-SCAFFOLD.md
│   └── 06-FILTER.md                 <- written AFTER the code
├── CLAUDE.md                        <- agent instructions
├── AGENTS.md                        <- one line -> CLAUDE.md
├── README.md  PRIVACY.md  CHANGELOG.md  LICENSE
├── Package.swift
├── build.sh                         <- universal .app + DMG
├── entitlements.plist               <- sandbox ON, NO network entitlement
├── Resources/AppIcon.icns
├── Sources/
│   ├── NakashaCore/                  <- no UI, no network, fully testable
│   │   ├── Model/          BoardRow.swift · ParsedBoard.swift
│   │   ├── Extract/        LayoutGrid.swift · PDFTextExtractor.swift · OCRFallback.swift
│   │   ├── Format/         BoardFormat.swift · FormatDetector.swift
│   │   │                   BarBoardParser.swift · MainCauselistParser.swift
│   │   ├── Match/          NameMatcher.swift
│   │   ├── Merge/          BoardMerger.swift
│   │   ├── Render/         BoardPDFRenderer.swift · CSVExporter.swift · Palette.swift
│   │   └── BoardService.swift
│   ├── NakashaApp/                   <- SwiftUI
│   │   ├── NakashaApp.swift · ContentView.swift · AppModel.swift
│   │   ├── LeftPane.swift · ResultsTable.swift · PDFPane.swift
│   │   └── SettingsView.swift · AboutView.swift
│   └── NakashaCLI/          main.swift
└── Tests/NakashaCoreTests/
    ├── Fixtures/           *_synthetic.txt   <- SYNTHETIC ONLY. never a real cause list.
    └── *Tests.swift
```

## File-by-file intent

| path | holds | created empty? |
|---|---|---|
| `Extract/LayoutGrid.swift` | glyphs -> baseline-grouped, word-placed character grid; gutter detection | no — carry forward, calibrated |
| `Extract/PDFTextExtractor.swift` | PDFKit glyph walk with the drawn-glyph cursor | no — carry forward |
| `Extract/OCRFallback.swift` | Tesseract tier 2, one page at a time, cancellable | **yes** |
| `Format/BarBoardParser.swift` | format A, `#`/`:` grammar, hard-wrap rejoin | no — carry forward |
| `Format/MainCauselistParser.swift` | format B, column anchors, flush-left note vs centred band | no — carry forward |
| `Match/NameMatcher.swift` | LOOSE surname match + alias syntax + S/O guard | no — needs loose-mode work |
| `Render/Palette.swift` | warm rust tokens, light + dark | **yes** |
| `App/PDFPane.swift` | PDFView, search, highlight, jump-to-page | **yes** |
| `App/ResultsTable.swift` | editable table — per-row keep/delete | **yes** |
| `App/SettingsView.swift` | appearance + font size | **yes** |
| `App/AboutView.swift` | the legal/security statements | **yes** |

## Build order

1. Scaffold — this file. No logic.
2. Rename the carried-forward core: `BoardParserCore` -> `NakashaCore`,
   `HCBADailyBoardParser` -> `BarBoardParser`. Suite must stay green.
3. **Loose matching** in `NameMatcher` — the narrowest thing that proves the wedge.
4. `PDFPane` + jump-and-highlight — the verification surface.
5. `ResultsTable` prune.
6. Export PDF to the exact spec (Trebuchet MS 12 / spacing 1.0 / A4 / warm rust).
7. Settings + About.
8. `OCRFallback` tier 2, with the thermal discipline.
9. `build.sh` -> DMG, README install steps including the Gatekeeper right-click-Open.

## Verify the scaffold

```
swift build && swift test
```
Green on an empty tree before step 3 begins.
