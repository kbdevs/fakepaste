import Foundation

public enum TypingAction: Equatable {
    case character(String)
    case backspace
    case delay(TimeInterval)
}

public struct HumanTypingModel {
    public var targetWPM: Double
    public var typoRate: Double
    public var wordPauseChance: Double
    public var wordPauseMin: TimeInterval
    public var wordPauseMax: TimeInterval

    public init(
        targetWPM: Double = 120.0,
        typoRate: Double = 0.04,
        wordPauseChance: Double = 0.18,
        wordPauseMin: TimeInterval = 0.08,
        wordPauseMax: TimeInterval = 0.22
    ) {
        self.targetWPM = targetWPM
        self.typoRate = typoRate
        self.wordPauseChance = wordPauseChance
        self.wordPauseMin = wordPauseMin
        self.wordPauseMax = wordPauseMax
    }

    public func baseDelay() -> TimeInterval {
        let charsPerSecond = max(1.0, (targetWPM * 5.0) / 60.0)
        return 1.0 / charsPerSecond
    }

    public func typingPlan<R: RandomNumberGenerator>(for text: String, rng: inout R) -> [TypingAction] {
        var actions: [TypingAction] = []
        let base = baseDelay()
        let characters = Array(text).map(String.init)

        for index in characters.indices {
            let ch = characters[index]
            let next = (index + 1) < characters.count ? characters[index + 1] : nil

            if shouldTypo(for: ch, rng: &rng) {
                let typo = chooseTypo(for: ch, rng: &rng)
                actions.append(.character(typo))
                actions.append(.delay(delay(for: typo, base: base, rng: &rng)))
                actions.append(.backspace)
                actions.append(.delay(delay(for: ch, base: base * 0.7, rng: &rng)))
            }

            actions.append(.character(ch))
            actions.append(.delay(delay(for: ch, base: base, rng: &rng)))

            if shouldAddWordPause(after: ch, next: next, rng: &rng) {
                let lower = min(wordPauseMin, wordPauseMax)
                let upper = max(wordPauseMin, wordPauseMax)
                actions.append(.delay(random(in: lower...upper, rng: &rng)))
            }
        }

        return actions
    }

    public func delay<R: RandomNumberGenerator>(for character: String, base: TimeInterval, rng: inout R) -> TimeInterval {
        let multiplier = clamp(gaussian(mean: 1.0, stdev: 0.22, rng: &rng), min: 0.4, max: 1.8)
        var value = base * multiplier

        if ",.;:".contains(character) {
            value += random(in: 0.04...0.12, rng: &rng)
        } else if "!?".contains(character) {
            value += random(in: 0.08...0.18, rng: &rng)
        } else if character == "\n" {
            value += random(in: 0.12...0.24, rng: &rng)
        }

        return max(0.01, value)
    }

    public func chooseTypo<R: RandomNumberGenerator>(for character: String, rng: inout R) -> String {
        guard let scalar = character.unicodeScalars.first else { return "x" }

        let lower = Character(String(scalar).lowercased())
        if let neighbors = Self.neighborKeys[lower] {
            let picked = neighbors.randomElement(using: &rng) ?? "x"
            return scalar.properties.isUppercase ? String(picked).uppercased() : String(picked)
        }

        if scalar.properties.numericType != nil, let value = Int(character) {
            var replacement = Int(random(in: 0...9, rng: &rng))
            if replacement == value {
                replacement = (value + 1) % 10
            }
            return String(replacement)
        }

        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var picked = letters.randomElement(using: &rng) ?? "x"
        if String(picked) == character.lowercased() {
            picked = letters.randomElement(using: &rng) ?? "z"
        }
        return scalar.properties.isUppercase ? String(picked).uppercased() : String(picked)
    }

    private func shouldTypo<R: RandomNumberGenerator>(for character: String, rng: inout R) -> Bool {
        guard !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard character.unicodeScalars.allSatisfy({ !$0.properties.isEmojiPresentation }) else { return false }
        return random(in: 0.0...1.0, rng: &rng) < typoRate
    }

    private func shouldAddWordPause<R: RandomNumberGenerator>(after character: String, next: String?, rng: inout R) -> Bool {
        guard isWordCharacter(character) else { return false }

        if let next, isWordCharacter(next) {
            return false
        }

        return random(in: 0.0...1.0, rng: &rng) < wordPauseChance
    }

    private func isWordCharacter(_ value: String) -> Bool {
        guard let scalar = value.unicodeScalars.first else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private func random<R: RandomNumberGenerator>(in range: ClosedRange<Double>, rng: inout R) -> Double {
        let t = Double.random(in: 0...1, using: &rng)
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }

    private func random<R: RandomNumberGenerator>(in range: ClosedRange<Int>, rng: inout R) -> Int {
        Int.random(in: range, using: &rng)
    }

    private func gaussian<R: RandomNumberGenerator>(mean: Double, stdev: Double, rng: inout R) -> Double {
        var u1 = Double.random(in: 0..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        if u1 < 0.000_001 {
            u1 = 0.000_001
        }
        let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        return mean + stdev * z0
    }

    static let neighborKeys: [Character: [Character]] = [
        "a": Array("qwsz"),
        "b": Array("vghn"),
        "c": Array("xdfv"),
        "d": Array("serfcx"),
        "e": Array("wsdr"),
        "f": Array("drtgvc"),
        "g": Array("ftyhbv"),
        "h": Array("gyujnb"),
        "i": Array("ujko"),
        "j": Array("huikmn"),
        "k": Array("jiolm"),
        "l": Array("kop"),
        "m": Array("njk"),
        "n": Array("bhjm"),
        "o": Array("iklp"),
        "p": Array("ol"),
        "q": Array("wa"),
        "r": Array("edft"),
        "s": Array("awedxz"),
        "t": Array("rfgy"),
        "u": Array("yhji"),
        "v": Array("cfgb"),
        "w": Array("qase"),
        "x": Array("zsdc"),
        "y": Array("tghu"),
        "z": Array("asx"),
    ]
}
