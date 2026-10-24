import CoreImage
import CoreImage.CIFilterBuiltins

/// What the analysis found, in a form the filters can use. Positions are normalised (0…1, origin
/// bottom-left) so the same context works for the preview and the full-resolution photo.
struct EnhanceContext {
    /// Face rectangles from Vision, normalised.
    var faces: [CGRect] = []
    /// The subject mask (white = subject) at its own resolution, or nil if no subject was found.
    var subjectMask: CIImage?
    /// Apple's auto-adjust filters for exposure and tone, computed once on the preview.
    var lightFilters: [CIFilter] = []
    /// Per-channel gains that neutralise the photo's average colour.
    var colourGains: (red: Double, green: Double, blue: Double) = (1, 1, 1)

    /// The subject mask stretched over `extent`, with the subject in the red, green and blue channels.
    func scaledSubjectMask(for extent: CGRect) -> CIImage? {
        guard let mask = subjectMask, !mask.extent.isEmpty else { return nil }
        let scaled = mask
            .transformed(by: CGAffineTransform(translationX: -mask.extent.minX, y: -mask.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        // Vision's mask has one channel; copy it into all three so any blend reads it.
        let grey = CIFilter.colorMatrix()
        grey.inputImage = scaled.clampedToExtent()
        grey.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        grey.gVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        grey.bVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return grey.outputImage?.cropped(to: extent)
    }
}

/// Turns an `Enhancement` into a Core Image graph. Like `FilterChain`, lengths are relative to the
/// image's short side so the preview matches the saved photo.
enum EnhanceChain {
    static func apply(_ enhancement: Enhancement, context: EnhanceContext, to input: CIImage) -> CIImage {
        guard !enhancement.isNeutralForPreview else { return input }
        let extent = input.extent
        let unit = min(extent.width, extent.height) / 1000
        var image = input

        // Repairs first, so later steps don't amplify specks and noise.
        if enhancement.dust > 0 { image = removeDust(image, amount: enhancement.dust) }
        if enhancement.denoise > 0 { image = denoise(image, amount: enhancement.denoise, unit: unit) }
        if enhancement.colour > 0 { image = balanceColour(image, gains: context.colourGains, amount: enhancement.colour) }
        if enhancement.light > 0 { image = adjustLight(image, filters: context.lightFilters, amount: enhancement.light) }
        if enhancement.faces > 0, !context.faces.isEmpty {
            image = enhanceFaces(image, faces: context.faces, amount: enhancement.faces, unit: unit)
        }
        if enhancement.detail > 0 { image = addDetail(image, amount: enhancement.detail, unit: unit) }
        if enhancement.background == .blur, let mask = context.scaledSubjectMask(for: extent) {
            image = blurBackground(image, subjectMask: mask, amount: enhancement.backgroundBlur, unit: unit)
        }
        return image.cropped(to: extent)
    }

    /// Makes everything outside the subject transparent.
    static func removeBackground(_ image: CIImage, subjectMask: CIImage) -> CIImage {
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage.empty()
        blend.maskImage = subjectMask
        return blend.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: - Tools

    /// Replaces pixels that differ sharply from their neighbourhood's median (specks, dust) with that median.
    private static func removeDust(_ image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        var median = image.clampedToExtent()
        for _ in 0..<(amount > 0.6 ? 3 : amount > 0.3 ? 2 : 1) {
            median = median.applyingFilter("CIMedianFilter")
        }
        median = median.cropped(to: extent)

        let difference = CIFilter.colorAbsoluteDifference()
        difference.inputImage = image
        difference.inputImage2 = median
        guard let diff = difference.outputImage else { return image }
        // Only clear outliers count as dust: threshold the brightest channel difference.
        let threshold = CGFloat(0.16 - 0.1 * amount)
        let gain: CGFloat = 12
        let mask = CIFilter.colorMatrix()
        mask.inputImage = diff
        mask.rVector = CIVector(x: gain, y: gain, z: gain, w: 0)
        mask.gVector = CIVector(x: gain, y: gain, z: gain, w: 0)
        mask.bVector = CIVector(x: gain, y: gain, z: gain, w: 0)
        mask.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mask.biasVector = CIVector(x: -threshold * gain, y: -threshold * gain, z: -threshold * gain, w: 1)
        let clamped = mask.outputImage?.applyingFilter("CIColorClamp")

        let blend = CIFilter.blendWithMask()
        blend.inputImage = median
        blend.backgroundImage = image
        blend.maskImage = clamped
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// Luminance noise is smoothed gently (detail lives there); colour noise is blurred hard
    /// (the eye barely sees colour resolution).
    private static func denoise(_ image: CIImage, amount: Double, unit: CGFloat) -> CIImage {
        let extent = image.extent
        let reduction = CIFilter.noiseReduction()
        reduction.inputImage = image.clampedToExtent()
        reduction.noiseLevel = Float(0.01 + 0.07 * amount)
        reduction.sharpness = Float(0.5 * (1 - amount))
        var luminanceSource = reduction.outputImage?.cropped(to: extent) ?? image
        if amount > 0.5 {
            // Strong settings add a median pass for heavier grain.
            let median = luminanceSource.clampedToExtent().applyingFilter("CIMedianFilter").cropped(to: extent)
            luminanceSource = dissolve(from: luminanceSource, to: median, amount: (amount - 0.5) * 1.2)
        }
        let colourSource = image.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(1, 4 * unit) * CGFloat(0.5 + amount)))
            .cropped(to: extent)
        return combine(luminanceOf: luminanceSource, colourOf: colourSource)
    }

    /// Multiplies each channel by the gain that would make the average colour grey.
    private static func balanceColour(_ image: CIImage, gains: (red: Double, green: Double, blue: Double), amount: Double) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: CGFloat(1 + (gains.red - 1) * amount), y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: CGFloat(1 + (gains.green - 1) * amount), z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: CGFloat(1 + (gains.blue - 1) * amount), w: 0)
        return filter.outputImage ?? image
    }

    /// Runs Apple's auto-adjust chain and mixes it in by `amount`.
    private static func adjustLight(_ image: CIImage, filters: [CIFilter], amount: Double) -> CIImage {
        guard !filters.isEmpty else { return image }
        var adjusted = image
        for template in filters {
            guard let filter = template.copy() as? CIFilter else { continue }
            filter.setValue(adjusted, forKey: kCIInputImageKey)
            adjusted = filter.outputImage ?? adjusted
        }
        return dissolve(from: image, to: adjusted.cropped(to: image.extent), amount: amount)
    }

    /// Inside each face: smoother skin, a touch more light, then fine detail for eyes and lashes.
    private static func enhanceFaces(_ image: CIImage, faces: [CGRect], amount: Double, unit: CGFloat) -> CIImage {
        let extent = image.extent
        let smoothing = CIFilter.noiseReduction()
        smoothing.inputImage = image.clampedToExtent()
        smoothing.noiseLevel = Float(0.04 + 0.06 * amount)
        smoothing.sharpness = 0
        let softened = smoothing.outputImage?.cropped(to: extent) ?? image
        var face = dissolve(from: image, to: softened, amount: 0.6 * amount)

        let light = CIFilter.exposureAdjust()
        light.inputImage = face
        light.ev = Float(0.3 * amount)
        face = light.outputImage ?? face

        let crisp = CIFilter.unsharpMask()
        crisp.inputImage = face.clampedToExtent()
        crisp.radius = Float(max(1, 1.5 * unit))
        crisp.intensity = Float(0.6 * amount)
        face = crisp.outputImage?.cropped(to: extent) ?? face

        guard let mask = faceMask(faces, extent: extent) else { return image }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = face
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// Fine sharpening plus a wide, gentle "clarity" boost for mid-tone texture.
    private static func addDetail(_ image: CIImage, amount: Double, unit: CGFloat) -> CIImage {
        let extent = image.extent
        let fine = CIFilter.unsharpMask()
        fine.inputImage = image.clampedToExtent()
        fine.radius = Float(max(1, 1.6 * unit))
        fine.intensity = Float(1.2 * amount)
        let clarity = CIFilter.unsharpMask()
        clarity.inputImage = fine.outputImage
        clarity.radius = Float(max(4, 25 * unit))
        clarity.intensity = Float(0.35 * amount)
        return clarity.outputImage?.cropped(to: extent) ?? image
    }

    /// Blurs the background more the further it is from the subject's edge, like a wide aperture.
    private static func blurBackground(_ image: CIImage, subjectMask: CIImage, amount: Double, unit: CGFloat) -> CIImage {
        let extent = image.extent
        let background = subjectMask.applyingFilter("CIColorInvert")
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = background.clampedToExtent()
        blur.radius = Float(max(1, 40 * unit * CGFloat(0.25 + amount)))
        guard let blurred = blur.outputImage?.cropped(to: extent) else { return image }
        // Keep the subject exactly as it was, so its edges stay crisp.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = blurred
        blend.maskImage = subjectMask
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: - Helpers

    /// Soft ellipses over each face (white inside), merged into one mask.
    private static func faceMask(_ faces: [CGRect], extent: CGRect) -> CIImage? {
        var mask: CIImage?
        for face in faces {
            let rect = CGRect(
                x: extent.minX + face.minX * extent.width, y: extent.minY + face.minY * extent.height,
                width: face.width * extent.width, height: face.height * extent.height
            )
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: rect.midX, y: rect.midY)
            gradient.radius0 = Float(max(rect.width, rect.height) * 0.45)
            gradient.radius1 = Float(max(rect.width, rect.height) * 0.8)
            gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
            gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
            guard let ellipse = gradient.outputImage?.cropped(to: extent) else { continue }
            if let existing = mask {
                let maximum = CIFilter.maximumCompositing()
                maximum.inputImage = ellipse
                maximum.backgroundImage = existing
                mask = maximum.outputImage?.cropped(to: extent)
            } else {
                mask = ellipse
            }
        }
        return mask
    }

    /// Luma (Rec. 709) of `luminanceOf` with the colour of `colourOf`: out = colour + (Y(lum) − Y(colour)).
    private static func combine(luminanceOf luminance: CIImage, colourOf colour: CIImage) -> CIImage {
        func lumaDelta(_ image: CIImage, sign: CGFloat) -> CIImage? {
            let weights = CIVector(x: 0.2126 * sign, y: 0.7152 * sign, z: 0.0722 * sign, w: 0)
            let filter = CIFilter.colorMatrix()
            filter.inputImage = image
            filter.rVector = weights
            filter.gVector = weights
            filter.bVector = weights
            // Opaque, because Core Image drops colour from zero-alpha pixels; the sum is made opaque again below.
            filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return filter.outputImage
        }
        guard let plus = lumaDelta(luminance, sign: 1), let minus = lumaDelta(colour, sign: -1) else { return luminance }
        let delta = CIFilter.additionCompositing()
        delta.inputImage = plus
        delta.backgroundImage = minus
        let sum = CIFilter.additionCompositing()
        sum.inputImage = delta.outputImage
        sum.backgroundImage = colour
        guard let total = sum.outputImage else { return luminance }
        return FilterChain.opaqueSum(total, layers: 3).cropped(to: luminance.extent)
    }

    private static func dissolve(from: CIImage, to: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = from
        filter.targetImage = to
        filter.time = Float(amount.clamped(to: 0...1))
        return filter.outputImage?.cropped(to: from.extent) ?? from
    }

}
