import Foundation
import NakashaCore

// Hand-rolled argument parser. Deliberately tiny: every flag is positional state
// we either remember or set.

struct CLIOptions {
    var names: String = ""
    var namesExplicit: Bool = false
    var pdfOut: String? = nil
    var csvOut: String? = nil
    var showSerial: Bool = true
    var showSection: Bool = true
    var inputs: [String] = []
    var dumpLines: Int = 0
}

func parseArgs(_ argv: [String]) -> CLIOptions {
    var o = CLIOptions()
    var i = 1
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--names":
            o.namesExplicit = true
            if i + 1 < argv.count {
                let next = argv[i + 1]
                if next.hasPrefix("--") {
                    // Missing value; treat as empty
                    o.names = ""
                } else {
                    o.names = next
                    i += 1
                }
            }
        case "--pdf-out":
            if i + 1 < argv.count { o.pdfOut = argv[i + 1]; i += 1 }
        case "--csv-out":
            if i + 1 < argv.count { o.csvOut = argv[i + 1]; i += 1 }
        case "--dump-lines":
            // Calibration aid. 02-ARCHITECTURE names the CLI's second job as "calibrating a
            // new court format"; this is that job. It prints the layout grid a parser
            // actually sees — the first ink column of each line and the column at which each
            // run of text begins — because a parser that mis-slices a real board looks fine
            // in its own output and only the geometry shows why.
            if i + 1 < argv.count, let n = Int(argv[i + 1]) { o.dumpLines = n; i += 1 }
            else { o.dumpLines = 40 }
        case "--no-serial":
            o.showSerial = false
        case "--no-sections":
            o.showSection = false
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            if a.hasPrefix("--") {
                FileHandle.standardError.write(Data("Unknown flag: \(a)\n".utf8))
            } else {
                o.inputs.append(a)
            }
        }
        i += 1
    }
    return o
}

func printUsage() {
    let usage = """
    boardparser --names <file-or-inline> [--pdf-out out.pdf] [--csv-out out.csv]
                [--no-serial] [--no-sections] <input1.pdf> [input2.pdf ...]

      --names      Either a path to a UTF-8 text file (one name per line), or a literal
                   semicolon/comma separated list. With no --names, no filtering.
      --pdf-out    Write the matched PDF to this path.
      --csv-out    Write the matched CSV to this path.
      --dump-lines <n>  Print the raw layout grid for the first n lines and stop.
                   Use it to calibrate a court format that comes out mis-sliced.
      --no-serial  Omit the serial column in the PDF.
      --no-sections  Omit board sections in the PDF.

    Exit codes: 0 success, 1 usage error, 2 all inputs failed.
    """
    print(usage)
}

func resolveNames(_ raw: String) -> String {
    // If it looks like a file and the file exists, load it; otherwise treat as inline.
    var isDir: ObjCBool = false
    let fm = FileManager.default
    if fm.fileExists(atPath: raw, isDirectory: &isDir), !isDir.boolValue {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: raw)),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
    }
    // Normalize inline separators to newlines so NameMatcher sees one name per line.
    let normalized = raw.replacingOccurrences(of: ";", with: "\n")
                       .replacingOccurrences(of: ",", with: "\n")
    return normalized
}

func todayString() -> String {
    let f = DateFormatter()
    f.dateFormat = "dd.MM.yyyy"
    return f.string(from: Date())
}

func run(_ opts: CLIOptions) -> Int {
    if opts.inputs.isEmpty {
        FileHandle.standardError.write(Data("Error: no input PDFs supplied.\n".utf8))
        return 1
    }

    let namesText = opts.namesExplicit ? resolveNames(opts.names) : ""

    if opts.dumpLines > 0 {
        for path in opts.inputs {
            let url = URL(fileURLWithPath: path)
            guard let lines = try? PDFTextExtractor.lines(of: url) else {
                print("could not read \(path)")
                continue
            }
            // CSO audit 2026-08-16, finding #9: this prints the board verbatim, names and
            // all. A user diagnosing a mis-parse could paste it into a public bug report and
            // publish litigant data. Warn on stderr, where it will not pollute piped output.
            FileHandle.standardError.write(Data(
                "warning: this prints the board's raw text, including party and advocate names.\n"
                .utf8))
            FileHandle.standardError.write(Data(
                "         Do not paste it into a public bug report.\n".utf8))
            print("== \(url.lastPathComponent): \(lines.count) layout lines ==")
            let resolved = Anchors(for: lines)
            print("RESOLVED ANCHORS item=\(resolved.item) case=\(resolved.caseNumber) "
                  + "parties=\(resolved.parties) counselA=\(resolved.counselA) "
                  + "counselB=\(resolved.counselB)")
            print("PLAN " + Anchors.debugPlan(for: lines))
            for line in lines.prefix(opts.dumpLines) {
                let starts = Anchors.segmentStarts(of: line, minimumGap: 3)
                print(String(format: "p%-3d first=%-4d starts=%@",
                             line.page,
                             line.firstInkColumn ?? -1,
                             starts.map(String.init).joined(separator: ",")))
                print("      |\(line.text)|")
            }
        }
        return 0
    }

    let urls: [URL] = opts.inputs.map { URL(fileURLWithPath: $0) }
    let input = BoardService.Input(
        pdfURLs: urls,
        watchedNamesText: namesText,
        showSerial: opts.showSerial,
        showSection: opts.showSection,
        boardDate: todayString()
    )

    let result: BoardService.Result
    do {
        result = try BoardService().run(input)
    } catch {
        FileHandle.standardError.write(Data("Fatal: \(error.localizedDescription)\n".utf8))
        return 2
    }

    // Warnings to stderr.
    for w in result.warnings {
        FileHandle.standardError.write(Data("warning: \(w)\n".utf8))
    }

    let totalRead = result.boards.reduce(0) { $0 + $1.rows.count }
    print("Matched \(result.rows.count) of \(totalRead) matters across \(result.boards.count) file(s).")

    // Plain-text summary table.
    printTable(result.rows, showSerial: opts.showSerial)

    // Outputs.
    if let out = opts.pdfOut {
        do {
            try BoardService().writePDF(result, input: input,
                                        to: URL(fileURLWithPath: out))
            print("PDF written: \(out)")
        } catch {
            FileHandle.standardError.write(Data("PDF write failed: \(error.localizedDescription)\n".utf8))
            return 2
        }
    }
    if let out = opts.csvOut {
        do {
            try BoardService().writeCSV(result, to: URL(fileURLWithPath: out))
            print("CSV written: \(out)")
        } catch {
            FileHandle.standardError.write(Data("CSV write failed: \(error.localizedDescription)\n".utf8))
            return 2
        }
    }

    // Exit 2 if every input failed to produce rows AND there were warnings for each.
    if !result.boards.isEmpty && result.boards.allSatisfy({ $0.rows.isEmpty }) && result.warnings.count == result.boards.count {
        return 2
    }
    return 0
}

private func printTable(_ rows: [BoardRow], showSerial: Bool) {
    // Truncating plain-text formatter. Good enough for a CLI eyeball.
    func col(_ s: String, _ w: Int) -> String {
        let trimmed = s.replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= w { return trimmed.padding(toLength: w, withPad: " ", startingAt: 0) }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: max(0, w - 1))
        return String(trimmed[..<idx]) + "\u{2026}"
    }

    print(col("Court", 16) + " " + (showSerial ? col("Sr.", 5) + " " : "") + col("Case No.", 14) + " " + col("Case", 26) + " " + col("Counsels", 22))
    print(String(repeating: "-", count: 16 + 1 + (showSerial ? 5 + 1 : 0) + 14 + 1 + 26 + 1 + 22))
    for r in rows {
        let line = col(r.court, 16) + " "
            + (showSerial ? col(r.serial, 5) + " " : "")
            + col(r.numberColumn, 14) + " "
            + col(r.caseName, 26) + " "
            + col(r.counsels, 22)
        print(line)
    }
}

let opts = parseArgs(CommandLine.arguments)
let code = run(opts)
exit(Int32(code))
