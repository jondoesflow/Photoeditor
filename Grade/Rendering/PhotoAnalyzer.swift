import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

/// Looks at a photo once when it opens: faces and the main subject (Apple Vision, on device),
/// noise, sharpness, brightness and colour cast, and Apple's auto-adjust settings.
enum PhotoAnalyzer {
    /// Side of the square crop measured for noise and sharpness. Taken from the preview at its own scale.
    static let sampleSize = 512

    static func analyze(_ image: CIImage, pixelSize: CGSize, context: CIContext) -> (PhotoInsights, EnhanceContext) {
        var enhance = EnhanceContext()
        enhance.faces = detectFaces(in: image, context: context)
        enhance.subjectMask = subjectMask(for: image, context: context)
        enhance.lightFilters = image.autoAdjustmentFilters(options: [.redEye: false, .enhance: true])
            .filter { !["CIFaceBalance", "CIVibrance"].contains($0.name) }

        var insights = PhotoInsights.empty
        insights.pixelSize = pixelSize
        insights.faceCount = enhance.faces.count
        insights.hasSubject = enhance.subjectMask != nil

        if let crop = bitmap(of: centreCrop(of: image), context: context) {
            let luma = ImageStats.luma(rgba: crop.bytes, width: crop.width, height: crop.height)
            insights.noise = ImageStats.noise(luma: luma, width: crop.width, height: crop.height)
            insights.sharpness = ImageStats.sharpness(luma: luma, width: crop.width, height: crop.height)
        }
        if let small = bitmap(of: image.transformed(by: scaleTransform(for: image.extent, to: 256)), context: context) {
            let mean = ImageStats.meanColour(rgba: small.bytes, width: small.width, height: small.height)
            insights.brightness = (mean.red + mean.green + mean.blue) / 3
            insights.colourCast = ImageStats.colourCast(mean)
            enhance.colourGains = gains(for: mean)
        }
        return (insights, enhance)
    }

    /// Gains that bring the mean colour (given in sRGB) to grey without changing its brightness, limited
    /// so a photo that is meant to be one colour (a sunset) isn't flattened. The gains are applied in
    /// Core Image's linear working space, so they're worked out in linear light.
    static func gains(for mean: (red: Double, green: Double, blue: Double)) -> (red: Double, green: Double, blue: Double) {
        func linear(_ value: Double) -> Double { pow(max(value, 0), 2.2) }
        let red = linear(mean.red), green = linear(mean.green), blue = linear(mean.blue)
        let grey = (red + green + blue) / 3
        func gain(_ channel: Double) -> Double { (grey / max(channel, 0.0001)).clamped(to: 0.6...1.6) }
        return (gain(red), gain(green), gain(blue))
    }

    // MARK: - Vision

    private static func detectFaces(in image: CIImage, context: CIContext) -> [CGRect] {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return [] }
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            return []
        }
        // Vision's bounding boxes are normalised with the origin at the bottom left, like Core Image.
        return (request.results ?? []).filter { $0.confidence > 0.5 }.map(\.boundingBox)
    }

    /// The foreground subject (people, pets, objects); falls back to person segmentation where the
    /// subject model isn't available (it needs the Neural Engine, so some simulators lack it).
    private static func subjectMask(for image: CIImage, context: CIContext) -> CIImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage)

        let foreground = VNGenerateForegroundInstanceMaskRequest()
        if (try? handler.perform([foreground])) != nil,
           let observation = foreground.results?.first,
           let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) {
            return CIImage(cvPixelBuffer: buffer)
        }

        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .accurate
        if (try? handler.perform([person])) != nil, let buffer = person.results?.first?.pixelBuffer,
           maskHasContent(buffer) {
            return CIImage(cvPixelBuffer: buffer)
        }
        return nil
    }

    /// Person segmentation returns a mask even with nobody in the photo; treat a near-empty one as no subject.
    private static func maskHasContent(_ buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return true }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var covered = 0
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) where pixels[y * rowBytes + x] > 128 {
                covered += 1
            }
        }
        return covered * 16 > width * height / 50
    }

    // MARK: - Pixels

    private static func centreCrop(of image: CIImage) -> CIImage {
        let extent = image.extent
        let side = CGFloat(min(sampleSize, Int(min(extent.width, extent.height))))
        return image.cropped(to: CGRect(x: extent.midX - side / 2, y: extent.midY - side / 2, width: side, height: side).integral)
    }

    private static func scaleTransform(for extent: CGRect, to maxSide: CGFloat) -> CGAffineTransform {
        let scale = min(1, maxSide / max(extent.width, extent.height))
        return CGAffineTransform(scaleX: scale, y: scale)
    }

    private static func bitmap(of image: CIImage, context: CIContext) -> (bytes: [UInt8], width: Int, height: Int)? {
        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress {
                context.render(image, toBitmap: base, rowBytes: width * 4, bounds: extent, format: .RGBA8, colorSpace: space)
            }
        }
        return (bytes, width, height)
    }
}
