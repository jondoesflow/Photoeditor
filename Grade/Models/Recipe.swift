import Foundation

/// An sRGB colour parsed from "#RRGGBB".
struct RGBColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

/// A colour wash for the shadows or highlights (split toning).
struct Tone: Codable, Equatable, Sendable {
    /// "#RRGGBB" in sRGB.
    var color: String
    /// 0…1.
    var strength: Double

    var rgb: RGBColor? { RGBColor(hex: color) }
}

/// A complete look: numeric settings plus optional split toning. Settings left at 0 are not stored,
/// so two recipes that look the same compare equal.
struct Recipe: Equatable, Sendable {
    private(set) var values: [Parameter: Double] = [:]
    var shadowTone: Tone?
    var highlightTone: Tone?

    static let neutral = Recipe()

    init(_ values: [Parameter: Double] = [:], shadowTone: Tone? = nil, highlightTone: Tone? = nil) {
        for (parameter, value) in values { self[parameter] = value }
        self.shadowTone = shadowTone
        self.highlightTone = highlightTone
    }

    /// Reads 0 for unset settings; writes are clamped to the setting's range.
    subscript(_ parameter: Parameter) -> Double {
        get { values[parameter] ?? 0 }
        set {
            let value = newValue.clamped(to: parameter.range)
            values[parameter] = value == 0 ? nil : value
        }
    }

    var isNeutral: Bool {
        values.isEmpty && (shadowTone?.strength ?? 0) == 0 && (highlightTone?.strength ?? 0) == 0
    }

    /// The same look at a fraction of its strength (the preset intensity slider).
    func scaled(by factor: Double) -> Recipe {
        let factor = factor.clamped(to: 0...1)
        var result = Recipe()
        for (parameter, value) in values { result[parameter] = value * factor }
        result.shadowTone = shadowTone.map { Tone(color: $0.color, strength: $0.strength * factor) }
        result.highlightTone = highlightTone.map { Tone(color: $0.color, strength: $0.strength * factor) }
        return result
    }

    /// Adds manual adjustments on top of this look. Tones from `self` win; the other's fill gaps.
    func adding(_ other: Recipe) -> Recipe {
        var result = self
        for (parameter, value) in other.values { result[parameter] = self[parameter] + value }
        result.shadowTone = shadowTone ?? other.shadowTone
        result.highlightTone = highlightTone ?? other.highlightTone
        return result
    }
}

/// Recipes are written flat in JSON: `{"exposure": -0.4, "shadowTone": {"color": "#0B5C66", "strength": 0.6}}`.
/// Unknown keys and out-of-range values are rejected so typos in `Presets.json` fail loudly in tests.
extension Recipe: Codable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static let shadowToneKey = Key(stringValue: "shadowTone")
    private static let highlightToneKey = Key(stringValue: "highlightTone")

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in container.allKeys {
            if let parameter = Parameter(rawValue: key.stringValue) {
                let value = try container.decode(Double.self, forKey: key)
                guard parameter.range.contains(value) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: key, in: container,
                        debugDescription: "\(key.stringValue) must be in \(parameter.range), got \(value)"
                    )
                }
                self[parameter] = value
            } else if key.stringValue == Self.shadowToneKey.stringValue {
                shadowTone = try container.decode(Tone.self, forKey: key)
            } else if key.stringValue == Self.highlightToneKey.stringValue {
                highlightTone = try container.decode(Tone.self, forKey: key)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: container, debugDescription: "Unknown recipe setting \"\(key.stringValue)\""
                )
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for parameter in Parameter.allCases {
            if let value = values[parameter] {
                try container.encode(value, forKey: Key(stringValue: parameter.rawValue))
            }
        }
        try container.encodeIfPresent(shadowTone, forKey: Self.shadowToneKey)
        try container.encodeIfPresent(highlightTone, forKey: Self.highlightToneKey)
    }
}
