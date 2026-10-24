import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// A rendered bitmap. `CGImage` is immutable, so sharing it across actors is safe.
struct RenderedImage: @unchecked Sendable, Equatable {
    let cgImage: CGImage

    var size: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }

    static func == (lhs: RenderedImage, rhs: RenderedImage) -> Bool { lhs.cgImage === rhs.cgImage }
}

enum RenderError: LocalizedError, Equatable {
    case unreadableImage
    case noPhoto
    case renderFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That photo couldn't be opened."
        case .noPhoto: "Choose a photo first."
        case .renderFailed: "The photo couldn't be rendered."
        case .encodeFailed: "The edited photo couldn't be saved."
        }
    }
}

/// Owns the Core Image context and the loaded photo. Edits are previewed on a downscaled copy;
/// only `export` touches the full-resolution original.
actor PhotoRenderer {
    static let previewMaxDimension: CGFloat = 2048
    static let thumbnailMaxDimension: CGFloat = 320

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let displaySpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    private var full: CIImage?
    private var preview: CIImage?
    private var thumbnail: CIImage?
    private var metadata: [String: Any] = [:]

    /// Decodes a photo (HEIC, JPEG, PNG, RAW…), applying its EXIF orientation. Returns its pixel size.
    @discardableResult
    func load(_ data: Data) throws -> CGSize {
        guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true]),
              !decoded.extent.isInfinite, !decoded.extent.isEmpty else {
            throw RenderError.unreadableImage
        }
        // Move the origin to zero so gradients and crops line up with the picture.
        let image = decoded.transformed(by: CGAffineTransform(translationX: -decoded.extent.minX, y: -decoded.extent.minY))
        let preview = try downscaled(image, maxDimension: Self.previewMaxDimension)
        let thumbnail = try downscaled(image, maxDimension: Self.thumbnailMaxDimension)
        full = image
        self.preview = preview
        self.thumbnail = thumbnail
        metadata = decoded.properties
        return image.extent.size
    }

    func renderPreview(_ recipe: Recipe) throws -> RenderedImage {
        // Slider drags queue many renders; skip the ones that are already out of date.
        try Task.checkCancellation()
        return try render(recipe, source: preview)
    }

    /// Renders each look on the small thumbnail copy, keyed by the caller's IDs.
    func renderThumbnails(_ recipes: [String: Recipe]) throws -> [String: RenderedImage] {
        try recipes.mapValues { try render($0, source: thumbnail) }
    }

    /// Renders the full-resolution photo and encodes it as HEIC (JPEG if HEIC isn't available),
    /// keeping the original's metadata such as date and location.
    func export(_ recipe: Recipe) throws -> Data {
        guard let full else { throw RenderError.noPhoto }
        let output = FilterChain.apply(recipe, to: full)
            .settingProperties(ExportMetadata.properties(from: metadata))
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        if let heic = context.heifRepresentation(of: output, format: .RGBA8, colorSpace: displaySpace, options: [quality: 0.92]) {
            return heic
        }
        guard let jpeg = context.jpegRepresentation(of: output, colorSpace: displaySpace, options: [quality: 0.95]) else {
            throw RenderError.encodeFailed
        }
        return jpeg
    }

    private func render(_ recipe: Recipe, source: CIImage?) throws -> RenderedImage {
        guard let source else { throw RenderError.noPhoto }
        let output = FilterChain.apply(recipe, to: source)
        guard let cgImage = context.createCGImage(output, from: source.extent, format: .RGBA8, colorSpace: displaySpace) else {
            throw RenderError.renderFailed
        }
        return RenderedImage(cgImage: cgImage)
    }

    /// Scales down with Lanczos and renders once, so later edits start from cached pixels
    /// instead of re-decoding and re-scaling the original every time.
    private func downscaled(_ image: CIImage, maxDimension: CGFloat) throws -> CIImage {
        let longSide = max(image.extent.width, image.extent.height)
        var scaled = image
        if longSide > maxDimension {
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = image
            filter.scale = Float(maxDimension / longSide)
            filter.aspectRatio = 1
            scaled = filter.outputImage ?? image
        }
        let bounds = CGRect(origin: .zero, size: CGSize(width: floor(scaled.extent.width), height: floor(scaled.extent.height)))
        guard let cgImage = context.createCGImage(scaled, from: bounds, format: .RGBA8, colorSpace: displaySpace) else {
            throw RenderError.unreadableImage
        }
        return CIImage(cgImage: cgImage)
    }
}
