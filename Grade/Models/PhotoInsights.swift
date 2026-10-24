import CoreGraphics
import Foundation

/// What the analysis found in a photo. Drives Autopilot and tells the UI which tools apply.
struct PhotoInsights: Equatable, Sendable {
    var pixelSize: CGSize
    var faceCount: Int
    var hasSubject: Bool
    /// Estimated noise, as a standard deviation in 8-bit levels (0…255). Clean photos are below about 2.
    var noise: Double
    /// Mean absolute Laplacian response in 8-bit levels. Soft photos are below about 4.
    var sharpness: Double
    /// Mean brightness, 0…1.
    var brightness: Double
    /// How far the average colour is from neutral grey, 0…1.
    var colourCast: Double

    static let empty = PhotoInsights(pixelSize: .zero, faceCount: 0, hasSubject: false, noise: 0, sharpness: 0, brightness: 0.5, colourCast: 0)

    /// A short description for the Enhance panel, such as "1 face · subject · noisy".
    var summary: String {
        var parts: [String] = []
        if faceCount > 0 { parts.append(faceCount == 1 ? "1 face" : "\(faceCount) faces") }
        if hasSubject { parts.append("subject") }
        if noise >= Autopilot.noisyThreshold { parts.append("noisy") }
        if sharpness < Autopilot.softThreshold { parts.append("soft") }
        if brightness < 0.3 { parts.append("dark") } else if brightness > 0.75 { parts.append("bright") }
        if colourCast >= Autopilot.castThreshold { parts.append("colour cast") }
        let megapixels = pixelSize.width * pixelSize.height / 1_000_000
        parts.append(String(format: "%.1f MP", megapixels))
        return parts.joined(separator: " · ")
    }
}

/// Chooses enhancement settings from what the analysis found, like Topaz's Autopilot.
/// Pure, so the choices are unit-tested.
enum Autopilot {
    static let noisyThreshold = 3.0
    static let softThreshold = 4.0
    static let castThreshold = 0.04
    /// Photos smaller than this are offered 2× upscaling.
    static let smallPhotoPixels = 4_000_000.0

    static func recommend(for insights: PhotoInsights, keeping current: Enhancement = .none) -> Enhancement {
        var result = current
        // Apple's auto-adjust is already adaptive; use more of it when the exposure is clearly off.
        result.light = insights.brightness < 0.3 || insights.brightness > 0.75 ? 0.8 : 0.5
        result.colour = insights.colourCast >= castThreshold ? min(0.9, 0.4 + insights.colourCast * 4) : 0
        result.denoise = ((insights.noise - 1.5) / 6).clamped(to: 0...0.9)
        if insights.sharpness < softThreshold {
            result.detail = 0.5
        } else if insights.sharpness < softThreshold * 2 {
            result.detail = 0.25
        } else {
            result.detail = 0
        }
        // Sharpening noise makes it worse, so hold detail back on noisy photos.
        if result.denoise > 0.4 { result.detail = min(result.detail, 0.2) }
        result.faces = insights.faceCount > 0 ? 0.5 : 0
        let pixels = Double(insights.pixelSize.width * insights.pixelSize.height)
        if pixels > 0, pixels < smallPhotoPixels, UpscaleFactor.double.isAvailable(for: insights.pixelSize) {
            result.upscale = .double
        }
        return result
    }
}
