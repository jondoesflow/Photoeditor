import CoreGraphics
import Foundation

/// Repairs and improvements applied to the photo before the look: light, colour, noise, detail,
/// faces, dust, background and upscaling. Unlike a look, these belong to one photo, so they reset
/// when another photo is opened.
struct Enhancement: Equatable, Sendable {
    enum Background: String, CaseIterable, Sendable {
        case keep
        case blur
        case remove
    }

    /// 0…1 for every tool.
    var light: Double = 0
    var colour: Double = 0
    var denoise: Double = 0
    var detail: Double = 0
    var faces: Double = 0
    var dust: Double = 0
    var background = Background.keep
    var backgroundBlur: Double = 0.5
    var upscale = UpscaleFactor.none

    static let none = Enhancement()

    /// True when nothing changes the preview (upscaling only happens when saving).
    var isNeutralForPreview: Bool {
        light == 0 && colour == 0 && denoise == 0 && detail == 0 && faces == 0 && dust == 0 && background != .blur
    }

    var isNeutral: Bool { isNeutralForPreview && background == .keep && upscale == .none }

    /// The settings that change the cached, enhanced preview (background removal and upscaling are applied later).
    var previewKey: Enhancement {
        var key = self
        key.upscale = .none
        if key.background == .remove { key.background = .keep }
        if key.background != .blur { key.backgroundBlur = 0 }
        return key
    }

    subscript(_ tool: EnhanceTool) -> Double {
        get {
            switch tool {
            case .light: light
            case .colour: colour
            case .denoise: denoise
            case .detail: detail
            case .faces: faces
            case .dust: dust
            case .background: backgroundBlur
            case .upscale: 0
            }
        }
        set {
            let value = newValue.clamped(to: 0...1)
            switch tool {
            case .light: light = value
            case .colour: colour = value
            case .denoise: denoise = value
            case .detail: detail = value
            case .faces: faces = value
            case .dust: dust = value
            case .background: backgroundBlur = value
            case .upscale: break
            }
        }
    }

    func isActive(_ tool: EnhanceTool) -> Bool {
        switch tool {
        case .background: background != .keep
        case .upscale: upscale != .none
        default: self[tool] > 0
        }
    }
}

/// How much bigger the saved photo is.
enum UpscaleFactor: Int, CaseIterable, Sendable {
    case none = 1
    case double = 2
    case quadruple = 4

    /// The largest photo Grade will produce, to keep memory and processing time reasonable on a phone.
    static let maxOutputPixels: Double = 48_000_000

    var label: String {
        switch self {
        case .none: "Off"
        case .double: "2×"
        case .quadruple: "4×"
        }
    }

    func outputSize(for size: CGSize) -> CGSize {
        CGSize(width: size.width * CGFloat(rawValue), height: size.height * CGFloat(rawValue))
    }

    func isAvailable(for size: CGSize) -> Bool {
        let output = outputSize(for: size)
        return Double(output.width * output.height) <= Self.maxOutputPixels
    }
}

/// The tools in the Enhance panel, in the order they're shown.
enum EnhanceTool: String, CaseIterable, Identifiable, Sendable {
    case light
    case colour
    case denoise
    case detail
    case faces
    case dust
    case background
    case upscale

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: "Light"
        case .colour: "Colour"
        case .denoise: "Denoise"
        case .detail: "Detail"
        case .faces: "Faces"
        case .dust: "Dust"
        case .background: "Background"
        case .upscale: "Upscale"
        }
    }

    var symbol: String {
        switch self {
        case .light: "sun.max.fill"
        case .colour: "circle.lefthalf.striped.horizontal"
        case .denoise: "aqi.medium"
        case .detail: "scope"
        case .faces: "face.smiling"
        case .dust: "sparkle"
        case .background: "person.crop.rectangle"
        case .upscale: "arrow.up.left.and.arrow.down.right"
        }
    }

    var explanation: String {
        switch self {
        case .light: "Balances exposure, shadows and highlights."
        case .colour: "Removes colour casts so whites look white."
        case .denoise: "Smooths grain and colour speckles from low light."
        case .detail: "Sharpens edges and brings out texture."
        case .faces: "Softens skin and lifts light and detail on faces."
        case .dust: "Removes small specks, dust and scratches."
        case .background: "Blurs or removes everything behind the subject."
        case .upscale: "Enlarges the saved photo with on-device AI."
        }
    }
}
