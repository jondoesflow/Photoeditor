import CoreImage
import CoreML
import CoreVideo

enum UpscaleError: LocalizedError {
    case modelMissing
    case tooLarge
    case failed

    var errorDescription: String? {
        switch self {
        case .modelMissing: "The upscaling model is missing from the app."
        case .tooLarge: "This photo is already too large to upscale that much."
        case .failed: "Upscaling failed."
        }
    }
}

/// AI upscaling with Real-ESRGAN (general x4 v3, BSD-3-Clause), converted to Core ML by
/// `tools/upscaler/convert.py`. The model takes 256 px tiles and returns them 4× larger; tiles
/// overlap so their seams fall inside a margin that is thrown away. 2× runs the 4× model and
/// scales each tile down by half, which keeps the model's sharper detail.
final class Upscaler {
    static let tile = 256
    static let margin = 16
    static let modelScale = 4

    private let model: MLModel
    private let context: CIContext
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(context: CIContext, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "Upscaler", withExtension: "mlmodelc") else { throw UpscaleError.modelMissing }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
        self.context = context
    }

    /// Upscales `image` by `factor` (2 or 4). `progress` is called with 0…1 after each tile.
    func upscale(_ image: CIImage, factor: Int, progress: (Double) -> Void = { _ in }) throws -> CIImage {
        let extent = image.extent.integral
        let outputWidth = Int(extent.width) * factor, outputHeight = Int(extent.height) * factor
        guard Double(outputWidth * outputHeight) <= UpscaleFactor.maxOutputPixels else { throw UpscaleError.tooLarge }
        guard let canvas = CGContext(
            data: nil, width: outputWidth, height: outputHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw UpscaleError.failed }

        // Edge pixels are repeated outwards so border tiles have real context.
        let source = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)).clampedToExtent()
        let step = Self.tile - 2 * Self.margin
        let columns = Int((extent.width / CGFloat(step)).rounded(.up))
        let rows = Int((extent.height / CGFloat(step)).rounded(.up))
        let input = try makePixelBuffer(width: Self.tile, height: Self.tile)
        let scale = CGFloat(factor) / CGFloat(Self.modelScale)

        for row in 0..<rows {
            for column in 0..<columns {
                try Task.checkCancellation()
                let coreX = column * step, coreY = row * step
                // Render the tile, including its margin, into the model's input buffer.
                let tileOrigin = CGPoint(x: coreX - Self.margin, y: coreY - Self.margin)
                let tileImage = source.transformed(by: CGAffineTransform(translationX: -tileOrigin.x, y: -tileOrigin.y))
                context.render(tileImage, to: input, bounds: CGRect(x: 0, y: 0, width: Self.tile, height: Self.tile), colorSpace: sRGB)

                let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input)])
                guard let output = try model.prediction(from: features).featureValue(for: "upscaled")?.imageBufferValue else {
                    throw UpscaleError.failed
                }
                var upscaled = CIImage(cvPixelBuffer: output, options: [.colorSpace: sRGB])
                if scale != 1 {
                    upscaled = upscaled.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
                }
                // Keep only the core: drop the margin, and anything beyond the photo's edge.
                let placed = upscaled.transformed(by: CGAffineTransform(translationX: tileOrigin.x * CGFloat(factor), y: tileOrigin.y * CGFloat(factor)))
                let core = CGRect(x: coreX * factor, y: coreY * factor, width: step * factor, height: step * factor)
                    .intersection(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
                guard !core.isEmpty, let piece = context.createCGImage(placed, from: core, format: .RGBA8, colorSpace: sRGB) else { continue }
                // Core Graphics and Core Image both put the origin at the bottom left.
                canvas.draw(piece, in: core)
                progress(Double(row * columns + column + 1) / Double(rows * columns))
            }
        }
        guard let result = canvas.makeImage() else { throw UpscaleError.failed }
        return CIImage(cgImage: result)
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw UpscaleError.failed }
        return buffer
    }
}
