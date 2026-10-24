import Foundation
import Testing
@testable import Grade

@Suite("Recipe: values, strength and combining")
struct RecipeTests {
    @Test("Unset settings read 0 and a fresh recipe is neutral")
    func defaults() {
        let recipe = Recipe()
        #expect(recipe.isNeutral)
        for parameter in Parameter.allCases { #expect(recipe[parameter] == 0) }
    }

    @Test("Writes are clamped to each setting's range, and 0 is not stored", arguments: Parameter.allCases)
    func clamping(parameter: Parameter) {
        var recipe = Recipe()
        recipe[parameter] = 5
        #expect(recipe[parameter] == parameter.range.upperBound)
        recipe[parameter] = -5
        #expect(recipe[parameter] == parameter.range.lowerBound)
        recipe[parameter] = 0
        #expect(recipe == .neutral)
    }

    @Test("A zero-strength tone is still neutral")
    func zeroTone() {
        #expect(Recipe(shadowTone: Tone(color: "#000000", strength: 0)).isNeutral)
        #expect(!Recipe(shadowTone: Tone(color: "#000000", strength: 0.1)).isNeutral)
    }

    @Test("Scaling multiplies every setting and tone strength")
    func scaling() {
        let recipe = Recipe([.exposure: -0.4, .grain: 0.6], shadowTone: Tone(color: "#0B5C66", strength: 0.8))
        let half = recipe.scaled(by: 0.5)
        #expect(abs(half[.exposure] - -0.2) < 1e-9)
        #expect(abs(half[.grain] - 0.3) < 1e-9)
        #expect(abs((half.shadowTone?.strength ?? 0) - 0.4) < 1e-9)
        #expect(half.shadowTone?.color == "#0B5C66")
        #expect(recipe.scaled(by: 0).isNeutral)
        #expect(recipe.scaled(by: 1) == recipe)
    }

    @Test("Adding sums settings, clamps, and keeps the look's tones")
    func adding() {
        let look = Recipe([.exposure: 0.8, .warmth: 0.2], shadowTone: Tone(color: "#111111", strength: 0.5))
        let extra = Recipe([.exposure: 0.5, .contrast: 0.3], shadowTone: Tone(color: "#222222", strength: 1), highlightTone: Tone(color: "#333333", strength: 1))
        let combined = look.adding(extra)
        #expect(combined[.exposure] == 1)
        #expect(abs(combined[.warmth] - 0.2) < 1e-9)
        #expect(abs(combined[.contrast] - 0.3) < 1e-9)
        #expect(combined.shadowTone?.color == "#111111")
        #expect(combined.highlightTone?.color == "#333333")
    }

    @Test("Opposite adjustments cancel back to neutral")
    func cancelling() {
        #expect(Recipe([.exposure: 0.5]).adding(Recipe([.exposure: -0.5])).isNeutral)
    }

    @Test("JSON round trip")
    func roundTrip() throws {
        let recipe = Recipe([.exposure: -0.45, .skyDarken: 0.75], shadowTone: Tone(color: "#0B5C66", strength: 0.65))
        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(Recipe.self, from: data) == recipe)
    }

    @Test("Unknown keys are rejected")
    func unknownKey() {
        let json = Data(#"{"exposur": 0.2}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Recipe.self, from: json) }
    }

    @Test("Out-of-range values are rejected")
    func outOfRange() {
        let json = Data(#"{"grain": -0.5}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Recipe.self, from: json) }
    }

    struct HexCase: Sendable, CustomTestStringConvertible {
        let input: String
        let bytes: [Double]
        var testDescription: String { input }
    }

    static let hexCases: [HexCase] = [
        HexCase(input: "#FF8000", bytes: [255, 128, 0]),
        HexCase(input: "0b5c66", bytes: [11, 92, 102]),
    ]

    @Test("Hex colours parse", arguments: hexCases)
    func hex(_ testCase: HexCase) throws {
        let color = try #require(RGBColor(hex: testCase.input))
        let channels = [color.red, color.green, color.blue].map { $0 * 255 }
        for (channel, expected) in zip(channels, testCase.bytes) {
            #expect(abs(channel - expected) < 1e-9)
        }
    }

    @Test("Bad hex colours are rejected", arguments: ["", "#FFF", "#GGGGGG", "#1234567"])
    func badHex(input: String) {
        #expect(RGBColor(hex: input) == nil)
    }
}
