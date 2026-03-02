import FakePasteCore
import XCTest

struct FixedRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}

final class HumanTypingModelTests: XCTestCase {
    func testBaseDelayMatchesExpected() {
        let model = HumanTypingModel(targetWPM: 120)
        XCTAssertEqual(model.baseDelay(), 0.1, accuracy: 0.000_001)
    }

    func testTypingPlanProducesOutput() {
        let model = HumanTypingModel(targetWPM: 120, typoRate: 0)
        var rng = FixedRNG(seed: 42)
        let plan = model.typingPlan(for: "abc", rng: &rng)
        XCTAssertGreaterThanOrEqual(plan.count, 6)
        XCTAssertTrue(plan.contains(.character("a")))
        XCTAssertTrue(plan.contains(.character("b")))
        XCTAssertTrue(plan.contains(.character("c")))
    }

    func testDelayAlwaysPositive() {
        let model = HumanTypingModel(targetWPM: 120)
        var rng = FixedRNG(seed: 7)
        let value = model.delay(for: "x", base: 0.1, rng: &rng)
        XCTAssertGreaterThan(value, 0)
    }
}
