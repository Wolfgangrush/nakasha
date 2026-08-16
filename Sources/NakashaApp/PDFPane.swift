import SwiftUI
import AppKit
import PDFKit

/// A request to show one page and highlight one printed substring on it.
///
/// `pageNumber` is 1-based as printed on the board so callers can pass through
/// the user-visible figure verbatim. `highlight` must be the exact substring
/// the advocate clicked; if it is empty the pane still jumps to the page.
/// `nonce` lets the same logical target be re-issued (for example after the
/// underlying PDF is reloaded) without the Coordinator deduplicating it.
struct PDFJumpTarget: Equatable {
    let pageNumber: Int
    let highlight: String
    let nonce: Int
}

/// The verification surface of NAKASHA.
///
/// The advocate must always verify. Loose matching is over-inclusive by
/// design; the user prunes. Never silently miss a matter: if a requested
/// highlight cannot be located on the printed page, the pane still shows the
/// page so the advocate can read it themselves.
struct PDFPane: NSViewRepresentable {
    let document: PDFDocument?
    let target: PDFJumpTarget?
    let searchText: String

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.controlBackgroundColor
        // The board is read-only evidence. Nothing here creates, edits or saves an
        // annotation, and the document is never written back — the only mutation this pane
        // performs is selecting text, which lives on the view, not on the file.
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator

        // Only swap the document when the instance has actually changed.
        // Reassigning the same PDFDocument on every SwiftUI update resets
        // scroll position and makes the pane jump while the user types in the
        // search field, which destroys the verification experience.
        if view.document !== document {
            view.document = document
        }

        if let target, target != coordinator.handledTarget {
            coordinator.handledTarget = target
            jump(to: target, in: view, document: document, coordinator: coordinator)
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch != coordinator.handledSearch {
            coordinator.handledSearch = trimmedSearch
            applySearch(trimmedSearch, in: view, document: document)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Jump

    /// Move to the requested page and select the requested substring on it.
    ///
    /// Jumping is dispatched asynchronously because SwiftUI invokes
    /// `updateNSView` mid-view-update, and driving PDFView scrolling
    /// synchronously from that path makes the view land on the wrong page or
    /// miss the selection. The `nonce` field of `PDFJumpTarget` lets the
    /// caller re-issue an identical jump after a document reload.
    private func jump(
        to target: PDFJumpTarget,
        in view: PDFView,
        document: PDFDocument?,
        coordinator: Coordinator
    ) {
        DispatchQueue.main.async {
            guard let document, document.pageCount > 0 else { return }

            let zeroBased = max(0, min(target.pageNumber - 1, document.pageCount - 1))
            guard let page = document.page(at: zeroBased) else { return }

            view.go(to: page)

            guard !target.highlight.isEmpty else { return }

            if let selection = Self.firstSelection(matching: target.highlight, on: page, in: document) {
                selection.color = NSColor.systemOrange
                view.setCurrentSelection(selection, animate: true)
                view.scrollSelectionToVisible(nil)
            }
            // If no prefix matched, the page from `view.go(to:)` is already
            // visible. The advocate can read it themselves. Never throw.
        }
    }

    /// Locate the requested substring on the target page, falling back to
    /// shorter leading prefixes so a hard-wrapped printed phrase can still be
    /// picked up.
    ///
    /// Hard-wrapping in the board PDF means PDFKit's extracted string often
    /// splits a phrase across a line break; without the prefix fallback the
    /// pane would silently miss legitimate matters. The page-equality check
    /// (`pages.first === page`) is what stops an off-page hit from being
    /// selected when the same substring also appears elsewhere.
    private static func firstSelection(
        matching highlight: String,
        on page: PDFPage,
        in document: PDFDocument
    ) -> PDFSelection? {
        let candidates: [Int] = [highlight.count, 24, 12, 6]
        for length in candidates {
            guard length > 0, length <= highlight.count else { continue }
            let prefix = String(highlight.prefix(length))
            guard !prefix.isEmpty else { continue }
            let matches = document.findString(prefix, withOptions: [.caseInsensitive])
            for selection in matches where selection.pages.first === page {
                return selection
            }
        }
        return nil
    }

    // MARK: - Search

    /// Paint every occurrence of `searchText` across the document without
    /// disturbing the click-through selection.
    ///
    /// `highlightedSelections` is independent of the current selection, so the
    /// orange click highlight and the yellow search highlights coexist. The
    /// search is recomputed only when the trimmed query changes, because
    /// running it on every keystroke is visibly janky on long boards.
    private func applySearch(_ trimmed: String, in view: PDFView, document: PDFDocument?) {
        guard let document, document.pageCount > 0 else {
            view.highlightedSelections = nil
            return
        }
        guard trimmed.count >= 2 else {
            view.highlightedSelections = nil
            return
        }
        let matches = document.findString(trimmed, withOptions: [.caseInsensitive])
        guard !matches.isEmpty else {
            view.highlightedSelections = nil
            return
        }
        for selection in matches {
            selection.color = NSColor.systemYellow
        }
        view.highlightedSelections = matches
    }

    final class Coordinator {
        var handledTarget: PDFJumpTarget?
        var handledSearch: String?
        weak var view: PDFView?
    }
}
