import Foundation

/// A numeric setting in a recipe. Values are normalised so that 0 always means "no change";
/// `FilterChain` maps them to Core Image units. Every setting can also be adjusted by hand.
enum Parameter: String, CaseIterable, Codable, Sendable, Identifiable {
    case exposure
    case contrast
    case highlights
    case shadows
    case warmth
    case tint
    case saturation
    case vibrance
    case fade
    case skyDarken
    case glow
    case sharpen
    case vignette
    case grain

    var id: String { rawValue }

    var range: ClosedRange<Double> {
        switch self {
        case .fade, .skyDarken, .glow, .sharpen, .vignette, .grain: 0...1
        default: -1...1
        }
    }

    var displayName: String {
        switch self {
        case .exposure: "Exposure"
        case .contrast: "Contrast"
        case .highlights: "Highlights"
        case .shadows: "Shadows"
        case .warmth: "Warmth"
        case .tint: "Tint"
        case .saturation: "Saturation"
        case .vibrance: "Vibrance"
        case .fade: "Fade"
        case .skyDarken: "Night Sky"
        case .glow: "Glow"
        case .sharpen: "Sharpen"
        case .vignette: "Vignette"
        case .grain: "Grain"
        }
    }

    var symbol: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .contrast: "circle.lefthalf.filled"
        case .highlights: "sun.max"
        case .shadows: "moon"
        case .warmth: "thermometer.medium"
        case .tint: "drop"
        case .saturation: "paintpalette"
        case .vibrance: "wand.and.stars"
        case .fade: "cloud.fog"
        case .skyDarken: "cloud.moon"
        case .glow: "sparkles"
        case .sharpen: "triangle"
        case .vignette: "camera.aperture"
        case .grain: "circle.grid.3x3"
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
