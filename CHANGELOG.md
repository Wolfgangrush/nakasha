# Changelog

All notable changes to NAKASHA are recorded here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - Initial release

### Added
- Drag-and-drop / file picker import of High Court board and cause-list
  PDFs.
- Calibrated parser for the Bar Association Daily Board format, with
  confidence scoring that surfaces low-confidence pages in the status bar.
- Calibrated parser for the High Court Daily Main Causelist format.
- Layout-based fallback parser for boards whose format is not yet
  calibrated, so unrecognised courts still produce a usable table.
- Name-matching engine with support for initials, aliases, and common
  Indian name orderings (e.g. `S. Kumar` matching `Fiktorne, Kumar`).
- Per-matter matching that records which of the advocate's names caused
  each row to be included, shown in the on-screen results table.
- Output PDF containing only the advocate's matters, formatted as a
  six-column table: Name of Court, Sr., Number, Name of Case, Name of
  the counsels, Office note given.
- Saved advocate name list, persisted in macOS user defaults and
  editable in the UI.
- Universal build (arm64 + x86_64) with ad-hoc codesigning.
- DMG distributable with an `/Applications` symlink for drag-and-drop
  install.

### Security
- App Sandbox enabled.
- `files.user-selected.read-write` entitlement granted.
- No network entitlement of any kind granted. Verified by source
  inspection and by the absence of network symbols in the shipped
  binary.

### Notes
- This is the first public build. Scanned image-only PDFs are not yet
  OCR'd by the app; pre-process them with `ocrmypdf` or Acrobat before
  opening.
