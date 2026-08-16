import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import NakashaCore

/// The window: controls and results on the left, the board itself on the right.
///
/// The two panes are the product. Matching is deliberately over-inclusive, so the advocate
/// has to be able to check each row against the printed page without leaving the app —
/// click a row on the left, the right-hand pane jumps to that page and highlights the
/// matter. A result the advocate cannot verify in one click is a result they will not trust.
struct ContentView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 460, idealWidth: 580)
                .padding(Theme.gutter)
            PDFPane(document: model.pdfDocument,
                    target: model.jumpTarget,
                    searchText: model.pdfSearchText)
                .frame(minWidth: 380)
        }
        // An IDEAL size is required, not just a minimum. `resultsArea` declares
        // `maxHeight: .infinity` so it can fill the pane, which makes the content's
        // ideal size unbounded — and an unbounded ideal makes the window open at the
        // full size of the display and ignore `.defaultSize` entirely.
        .frame(minWidth: 1060, idealWidth: 1180,
               minHeight: 680,  idealHeight: 780)
        // Vibrancy behind the whole window, then material cards on top of it.
        // This is the macOS 13 way to get depth; Liquid Glass would raise the
        // deployment target to macOS 26 and cut off exactly the older Macs the
        // product promises to run on.
        .background(VisualEffectBackground())

        .onAppear {
            settings.apply()
            InitialWindow.applyOnce(size: CGSize(width: 1180, height: 780))
        }
        .onCommand(.openBoard)    { model.choosePDFs() }
        .onCommand(.clearBoards)  { model.removeAll() }
        .onCommand(.run)          { model.run() }
        .onCommand(.exportPDF)    { model.savePDF() }
        .onCommand(.exportCSV)    { model.saveCSV() }
        .onCommand(.openSettings) { model.showSettings = true }
        .onCommand(.openAbout)    { model.showAbout = true }
        .alert("Something went wrong", isPresented: $model.alertVisible, presenting: model.alertMessage) { _ in
            Button("OK") { model.alertMessage = nil }
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $model.showSettings) {
            sheet(title: "Settings") { SettingsView(store: settings) }
        }
        .sheet(isPresented: $model.showAbout) {
            sheet(title: "About NAKASHA") { AboutView() }
        }
    }

    private func sheet<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    model.showSettings = false
                    model.showAbout = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 460)
    }

    // MARK: - Left pane

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: Theme.stack) {
            header
            dropZone.card()
            namesEditor.card()
            pdfSearchField
            actionRow
            resultsArea
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("NAKASHA")
                .font(.system(size: 20, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.ink)
            Text("Make tomorrow's board tonight")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button { model.showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Settings")
            Button { model.showAbout = true } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("About")
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(model.isDropTargeted ? Theme.accent : Theme.rule)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .fill(model.isDropTargeted
                                  ? Theme.accent.opacity(0.07)
                                  : Color.clear)
                    )
                VStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(model.isDropTargeted ? Theme.accent : Theme.muted)
                    Text("Drop tonight's board here, or click to choose")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("Open both boards for the same date to complete truncated names.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .contentShape(Rectangle())
            .onTapGesture { model.choosePDFs() }
            .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTargeted) { providers in
                model.handleDrop(providers: providers)
            }

            if !model.pdfs.isEmpty {
                HStack {
                    SectionLabel(text: "\(model.pdfs.count) board\(model.pdfs.count == 1 ? "" : "s") open")
                    Spacer()
                    Button("Remove all") { model.removeAll() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(model.pdfs, id: \.self) { url in
                        HStack(spacing: 6) {
                            Image(systemName: model.isShowing(url) ? "eye.fill" : "doc.richtext")
                                .foregroundStyle(model.isShowing(url) ? Color.accentColor : .secondary)
                            Text(url.lastPathComponent)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { model.remove(url: url) } label: {
                                Label("Remove", systemImage: "xmark.circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this board — you can then add the right one")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.show(url: url) }
                        .help("Show this PDF in the viewer")
                    }
                }
            }
        }
    }

    private var namesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Names to watch")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.watchedNamesText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackgroundHidden()
                    .frame(minHeight: 66)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.rule.opacity(0.8)))
                if model.watchedNamesText.isEmpty {
                    Text("Vernekar\nTarkel")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.muted.opacity(0.6))
                        .padding(.horizontal, 6).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            Text("The surname on its own is the right thing to type. Matching is loose on "
                 + "purpose, so you will see extra rows — delete the ones that are not yours.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }

    private var pdfSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search inside the PDF", text: $model.pdfSearchText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var actionRow: some View {
        HStack {
            Button {
                model.run()
            } label: {
                HStack(spacing: 6) {
                    if model.isRunning { ProgressView().controlSize(.small) }
                    Text(model.isRunning ? "Reading…" : "Find my matters")
                }
                .frame(minWidth: 130)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(AccentButtonStyle())
            .disabled(model.isRunning || model.pdfs.isEmpty)

            Spacer()

            Button("Export PDF…") { model.savePDF() }
                .disabled(model.isRunning || model.keptRows.isEmpty)
            Button("Export CSV…") { model.saveCSV() }
                .disabled(model.isRunning || model.keptRows.isEmpty)
        }
    }

    private var resultsArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = model.summaryLine {
                Text(summary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            if !model.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, w in
                        Text(w).font(.caption).foregroundStyle(Color.orange)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.orange.opacity(0.4)))
            }
            if !model.rows.isEmpty {
                ResultsTable(rows: $model.rows,
                             textSize: settings.tableTextSize,
                             onReveal: { model.reveal($0) })
            } else if !model.isRunning && model.hasRun {
                Text("No matters matched. Check the spelling, or try just the surname.")
                    .foregroundStyle(.secondary).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Model

@MainActor
final class AppModel: ObservableObject {

    @Published var pdfs: [URL] = []
    @Published var watchedNamesText: String = ""
    @Published var isDropTargeted = false
    @Published var isRunning = false
    @Published var hasRun = false

    @Published var rows: [ResultRow] = []
    @Published var warnings: [String] = []
    @Published var summaryLine: String?

    @Published var pdfDocument: PDFDocument?
    @Published var jumpTarget: PDFJumpTarget?
    @Published var pdfSearchText: String = ""

    @Published var showSettings = false
    @Published var showAbout = false
    @Published var alertMessage: String?

    var alertVisible: Bool {
        get { alertMessage != nil }
        set { if !newValue { alertMessage = nil } }
    }

    /// Only the rows the advocate kept. This is what gets exported — pruning that did not
    /// change the output would be pruning that did nothing.
    var keptRows: [BoardRow] { rows.filter(\.keep).map(\.row) }

    private let service = BoardService()
    private let defaults = UserDefaults.standard
    private enum Keys { static let names = "NAKASHA.watchedNamesText" }

    /// Boards from the last run. Cached because re-deriving them meant re-extracting and
    /// re-parsing every PDF on each save — 87 pages of work to fill in a subtitle.
    private var cachedBoards: [ParsedBoard] = []
    private var shownURL: URL?
    private var jumpNonce = 0

    init() {
        watchedNamesText = defaults.string(forKey: Keys.names) ?? ""
    }

    // MARK: Files

    func choosePDFs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose the board PDF"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let u = url, u.pathExtension.lowercased() == "pdf" { collected.append(u) }
                group.leave()
            }
        }
        group.notify(queue: .main) { self.add(urls: collected) }
        return true
    }

    private func add(urls: [URL]) {
        var seen = Set(pdfs.map(\.standardizedFileURL))
        for u in urls where seen.insert(u.standardizedFileURL).inserted { pdfs.append(u) }
        if shownURL == nil, let first = pdfs.first { show(url: first) }
    }

    /// Drops every loaded board. The obvious recovery when the wrong file was
    /// opened, and the reason it is on the File menu as well as the pane.
    func removeAll() {
        pdfs.removeAll()
        shownURL = nil
        pdfDocument = nil
        rows = []
        summaryLine = nil
        warnings = []
        hasRun = false
    }

    func remove(url: URL) {
        pdfs.removeAll { $0 == url }
        if shownURL == url {
            shownURL = nil
            pdfDocument = nil
            if let next = pdfs.first { show(url: next) }
        }
    }

    func isShowing(_ url: URL) -> Bool { shownURL == url }

    func show(url: URL) {
        guard shownURL != url else { return }
        shownURL = url
        pdfDocument = PDFDocument(url: url)
    }

    // MARK: Run

    func run() {
        guard !pdfs.isEmpty, !isRunning else { return }
        defaults.set(watchedNamesText, forKey: Keys.names)

        let input = BoardService.Input(pdfURLs: pdfs,
                                       watchedNamesText: watchedNamesText,
                                       boardDate: Self.todayString())
        isRunning = true
        warnings = []
        summaryLine = "Reading…"

        Task.detached(priority: .userInitiated) { [service] in
            let outcome: Result<BoardService.Result, Error>
            do { outcome = .success(try service.run(input)) }
            catch { outcome = .failure(error) }

            await MainActor.run {
                self.isRunning = false
                self.hasRun = true
                switch outcome {
                case .success(let r):
                    self.cachedBoards = r.boards
                    // Everything arrives kept. The advocate removes; they should never have
                    // to tick a hundred boxes to get the list they asked for.
                    self.rows = r.rows.map { ResultRow(id: $0.id, row: $0, keep: true) }
                    self.warnings = r.warnings
                    let total = r.boards.reduce(0) { $0 + $1.rows.count }
                    self.summaryLine = "\(r.rows.count) of \(total) matters matched"
                    if total == 0 && !r.warnings.isEmpty {
                        self.alertMessage = "No board could be read. See the warnings below."
                    }
                case .failure(let err):
                    self.rows = []
                    self.summaryLine = "Could not read the board."
                    self.alertMessage = err.localizedDescription
                }
            }
        }
    }

    /// Show this matter on the printed page. The verification surface in one click.
    func reveal(_ row: BoardRow) {
        // Open the document the row actually came from. With two boards loaded, jumping in
        // whichever PDF happens to be on screen would show a different matter at the same
        // page number, which reads as the app being wrong.
        if let owner = pdfs.first(where: { $0.lastPathComponent == row.sourceFile }) {
            show(url: owner)
        }
        jumpNonce += 1
        // Highlight the CASE NUMBER, not the matched name. The case number is printed
        // exactly as we read it; the advocate's name may be truncated or split mid-word on
        // the page, which is the whole reason matching is loose in the first place.
        jumpTarget = PDFJumpTarget(pageNumber: row.sourcePage,
                                   highlight: row.caseNumber,
                                   nonce: jumpNonce)
    }

    // MARK: Export

    func savePDF() {
        let input = BoardService.Input(pdfURLs: pdfs,
                                       watchedNamesText: watchedNamesText,
                                       boardDate: Self.todayString())
        let result = BoardService.Result(rows: keptRows, boards: cachedBoards, warnings: warnings)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "My Board.pdf"
        if panel.runModal() == .OK, let url = panel.url {
            do { try service.writePDF(result, input: input, to: url) }
            catch { alertMessage = "Couldn't save the PDF: \(error.localizedDescription)" }
        }
    }

    func saveCSV() {
        let result = BoardService.Result(rows: keptRows, boards: cachedBoards, warnings: warnings)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "My Board.csv"
        if panel.runModal() == .OK, let url = panel.url {
            do { try service.writeCSV(result, to: url) }
            catch { alertMessage = "Couldn't save the CSV: \(error.localizedDescription)" }
        }
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: Date())
    }
}
