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
    case noSubject

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That photo couldn't be opened."
        case .noPhoto: "Choose a photo first."
        case .renderFailed: "The photo couldn't be rendered."
        case .encodeFailed: "The edited photo couldn't be saved."
        case .noSubject: "No subject was found to separate from the background."
        }
    }
}

/// Owns the Core Image context and the loaded photo. Edits are previewed on a downscaled copy;
/// only `export` touches the full-resolution original.
actor PhotoRenderer {
    static let previewMaxDimension: CGFloat = 2048
    static let thumbnailMaxDimension: CGFloat = 320

    /// A finished photo and how it's encoded.
    struct Export: Sendable {
        let data: Data
        /// "public.heic", or "public.png" when the background was removed (transparency).
        let uniformType: String
        let pixelSize: CGSize
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let displaySpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    private var full: CIImage?
    private var preview: CIImage?
    private var thumbnail: CIImage?
    private var metadata: [String: Any] = [:]
    private var enhanceContext = EnhanceContext()
    /// The preview with the current enhancement applied, so changing the look doesn't redo the repairs.
    private var enhancedPreview: (key: Enhancement, image: CIImage)?
    private var upscaler: Upscaler?

    /// Decodes a photo (HEIC, JPEG, PNG, RAW…), applying its EXIF orientation, and analyses it.
    @discardableResult
    func load(_ data: Data) throws -> PhotoInsights {
        guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true]),
              !decoded.extent.isInfinite, !decoded.extent.isEmpty else {
            throw RenderError.unreadableImage
        }
        // Move the origin to zero so gradients and crops line up with the picture.
        let image = decoded.transformed(by: CGAffineTransform(translationX: -decoded.extent.minX, y: -decoded.extent.minY))
        let preview = try downscaled(image, maxDimension: Self.previewMaxDimension)
        let thumbnail = try downscaled(image, maxDimension: Self.thumbnailMaxDimension)
        let (insights, enhanceContext) = PhotoAnalyzer.analyze(preview, pixelSize: image.extent.size, context: context)
        full = image
        self.preview = preview
        self.thumbnail = thumbnail
        self.enhanceContext = enhanceContext
        enhancedPreview = nil
        metadata = decoded.properties
        return insights
    }

    func renderPreview(_ recipe: Recipe, enhancement: Enhancement = .none) throws -> RenderedImage {
        // Slider drags queue many renders; skip the ones that are already out of date.
        try Task.checkCancellation()
        guard let preview else { throw RenderError.noPhoto }
        var output = FilterChain.apply(recipe, to: try enhanced(preview, enhancement))
        if enhancement.background == .remove {
            guard let mask = enhanceContext.scaledSubjectMask(for: output.extent) else { throw RenderError.noSubject }
            output = EnhanceChain.removeBackground(output, subjectMask: mask)
        }
        return try render(output, extent: preview.extent)
    }

    /// Renders each look on the small thumbnail copy, keyed by the caller's IDs.
    func renderThumbnails(_ recipes: [String: Recipe]) throws -> [String: RenderedImage] {
        guard let thumbnail else { throw RenderError.noPhoto }
        return try recipes.mapValues { try render(FilterChain.apply($0, to: thumbnail), extent: thumbnail.extent) }
    }

    /// Renders the full-resolution photo: enhancements, then AI upscaling, then the look, then background
    /// removal. Encodes HEIC (JPEG if HEIC isn't available), or PNG when the background is transparent,
    /// keeping the original's metadata such as date and location.
    func export(_ recipe: Recipe, enhancement: Enhancement = .none, progress: @Sendable (Double) -> Void = { _ in }) throws -> Export {
        guard let full else { throw RenderError.noPhoto }
        var image = EnhanceChain.apply(enhancement, context: enhanceContext, to: full)
        if enhancement.upscale != .none {
            image = try loadedUpscaler().upscale(image, factor: enhancement.upscale.rawValue, progress: progress)
        }
        image = FilterChain.apply(recipe, to: image)
        let extent = image.extent
        let properties = ExportMetadata.properties(from: metadata)

        if enhancement.background == .remove {
            guard let mask = enhanceContext.scaledSubjectMask(for: extent) else { throw RenderError.noSubject }
            image = EnhanceChain.removeBackground(image, subjectMask: mask).settingProperties(properties)
            guard let png = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: displaySpace) else {
                throw RenderError.encodeFailed
            }
            return Export(data: png, uniformType: "public.png", pixelSize: extent.size)
        }

        image = image.settingProperties(properties)
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        if let heic = context.heifRepresentation(of: image, format: .RGBA8, colorSpace: displaySpace, options: [quality: 0.92]) {
            return Export(data: heic, uniformType: "public.heic", pixelSize: extent.size)
        }
        guard let jpeg = context.jpegRepresentation(of: image, colorSpace: displaySpace, options: [quality: 0.95]) else {
            throw RenderError.encodeFailed
        }
        return Export(data: jpeg, uniformType: "public.jpeg", pixelSize: extent.size)
    }

    private func enhanced(_ preview: CIImage, _ enhancement: Enhancement) throws -> CIImage {
        let key = enhancement.previewKey
        guard !key.isNeutralForPreview else { return preview }
        if let cached = enhancedPreview, cached.key == key { return cached.image }
        let output = EnhanceChain.apply(key, context: enhanceContext, to: preview)
        // Render once and keep the pixels, so later look changes start from here.
        guard let cgImage = context.createCGImage(output, from: preview.extent, format: .RGBA8, colorSpace: displaySpace) else {
            throw RenderError.renderFailed
        }
        let image = CIImage(cgImage: cgImage)
        enhancedPreview = (key, image)
        return image
    }

    private func loadedUpscaler() throws -> Upscaler {
        if let upscaler { return upscaler }
        let loaded = try Upscaler(context: context)
        upscaler = loaded
        return loaded
    }

    private func render(_ output: CIImage, extent: CGRect) throws -> RenderedImage {
        guard let cgImage = context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: displaySpace) else {
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
