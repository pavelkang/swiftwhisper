import Foundation
import XCTest
@testable import SwiftWhisperCore

final class WakeBindingTests: XCTestCase {
    func testDefaultBindingSurvivesCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(WakeBinding.defaultBinding)
        let decoded = try JSONDecoder().decode(WakeBinding.self, from: encoded)
        XCTAssertEqual(decoded, .modifierOnly(.rightOption))
    }

    func testChordModifierMaskSurvivesCodableRoundTrip() throws {
        let original = WakeBinding.chord(keyCode: 49, modifiers: [.command, .option])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WakeBinding.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }
}
