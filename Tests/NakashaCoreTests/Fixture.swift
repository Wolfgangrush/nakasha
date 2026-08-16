import Foundation
import XCTest
@testable import NakashaCore

/// Fixtures are SYNTHETIC. They copy the column geometry of real published boards to the
/// character, but every party, advocate, judge and matter in them is invented. A real
/// cause list must never enter this repository: it carries live litigant names, and this
/// project is published.
enum Fixture {
    static func text(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "txt")
                ?? Bundle.module.url(forResource: name, withExtension: "txt",
                                     subdirectory: "Fixtures")
        else {
            throw XCTSkip("fixture \(name).txt not found in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func lines(_ name: String) throws -> [LayoutLine] {
        LayoutGrid.lines(fromPlainText: try text(name))
    }

    static let hcba = "hcba_daily_board_synthetic"
    static let causelist = "main_causelist_synthetic"
}
