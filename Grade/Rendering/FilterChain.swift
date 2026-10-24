import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns a `Recipe` into a Core Image graph. Pure and synchronous: it only builds the graph,
/// the pixels are produced later by a `CIContext`.
///
/// Lengths (glow radius, grain size, vignette) are relative to the image's short side, so a
/// 2048 px preview and a 48 MP export look the same.
enum FilterChain {
    static func apply(_ recipe: Recipe, to input: CIImage) -> CIImage {
        guard !recipe.isNeutral else { return input }
        let extent = input.extent
        // One "unit" is a thousandth of the short side.
        let unit = min(extent.width, extent.height) / 1000
        var image = input

        // Linear light: exposure, white balance and glow behave like light does.
        if recipe[.exposure] != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(recipe[.exposure] * 1.5)
            image = filter.outputImage ?? image
        }
        if recipe[.warmth] != 0 || recipe[.tint] != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            // Telling Core Image the light was bluer than it was warms the picture, and vice versa.
            filter.neutral = CIVector(x: 6500 + recipe[.warmth] * 2500, y: recipe[.tint] * 60)
            filter.targetNeutral = CIVector(x: 6500, y: 0)
            image = filter.outputImage ?? image
        }
        // CIToneCurve converts to a perceptual curve space itself, so it runs on linear input.
        // It also lifts the empty area outside the photo, so crop straight away.
        image = toneCurve(image, recipe).cropped(to: extent)
        if recipe[.glow] > 0 {
            image = glow(image, amount: recipe[.glow], unit: unit)
        }

        // Perceptual (gamma-encoded) space: curves, colour and texture feel right to the eye here.
        if needsPerceptualStage(recipe) {
            image = image.applyingFilter("CILinearToSRGBToneCurve")
            if recipe[.contrast] != 0 || recipe[.saturation] != 0 {
                let filter = CIFilter.colorControls()
                filter.inputImage = image
                filter.contrast = Float(1 + recipe[.contrast] * 0.35)
                filter.saturation = Float(1 + recipe[.saturation])
                filter.brightness = 0
                image = filter.outputImage ?? image
            }
            if recipe[.vibrance] != 0 {
                let filter = CIFilter.vibrance()
                filter.inputImage = image
                filter.amount = Float(recipe[.vibrance])
                image = filter.outputImage ?? image
            }
            if let tone = recipe.shadowTone, tone.strength > 0 {
                image = splitTone(image, tone: tone, inHighlights: false)
            }
            if let tone = recipe.highlightTone, tone.strength > 0 {
                image = splitTone(image, tone: tone, inHighlights: true)
            }
            if recipe[.skyDarken] > 0 {
                image = darkenSky(image, amount: recipe[.skyDarken])
            }
            if recipe[.sharpen] > 0 {
                let filter = CIFilter.sharpenLuminance()
                filter.inputImage = image.clampedToExtent()
                filter.sharpness = Float(recipe[.sharpen] * 1.2)
                filter.radius = Float(max(1, 1.2 * unit))
                image = filter.outputImage?.cropped(to: extent) ?? image
            }
            if recipe[.vignette] > 0 {
                image = vignette(image, amount: recipe[.vignette])
            }
            if recipe[.grain] > 0 {
                image = grain(image, amount: recipe[.grain], unit: unit)
            }
            image = image.applyingFilter("CISRGBToneCurveToLinear")
        }

        return image.cropped(to: extent)
    }

    private static func needsPerceptualStage(_ recipe: Recipe) -> Bool {
        let perceptual: [Parameter] = [.contrast, .saturation, .vibrance, .skyDarken, .sharpen, .vignette, .grain]
        return perceptual.contains { recipe[$0] != 0 }
            || (recipe.shadowTone?.strength ?? 0) > 0
            || (recipe.highlightTone?.strength ?? 0) > 0
    }

    /// Fade lifts the blacks (and softens the whites); highlights and shadows bend the curve's upper and lower quarters.
    private static func toneCurve(_ image: CIImage, _ recipe: Recipe) -> CIImage {
        let fade = recipe[.fade], shadows = recipe[.shadows], highlights = recipe[.highlights]
        guard fade != 0 || shadows != 0 || highlights != 0 else { return image }
        var ys = [
            fade * 0.2,
            0.25 + shadows * 0.12 + fade * 0.06,
            0.5 + (shadows + highlights) * 0.025,
            0.75 + highlights * 0.12,
            1 - fade * 0.05,
        ]
        // Keep the curve rising so tones never swap places.
        for index in 1..<ys.count {
            ys[index] = min(max(ys[index], ys[index - 1] + 0.01), 1)
        }
        let filter = CIFilter.toneCurve()
        filter.inputImage = image
        filter.point0 = CGPoint(x: 0, y: ys[0])
        filter.point1 = CGPoint(x: 0.25, y: ys[1])
        filter.point2 = CGPoint(x: 0.5, y: ys[2])
        filter.point3 = CGPoint(x: 0.75, y: ys[3])
        filter.point4 = CGPoint(x: 1, y: ys[4])
        return filter.outputImage ?? image
    }

    /// Pushes the shadows or highlights towards a colour without changing their brightness,
    /// weighted by how dark or bright each pixel is.
    private static func splitTone(_ image: CIImage, tone: Tone, inHighlights: Bool) -> CIImage {
        guard let rgb = tone.rgb else { return image }
        let extent = image.extent
        let luma = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
        let push = 0.8
        let shift = CIFilter.colorMatrix()
        shift.inputImage = image
        shift.biasVector = CIVector(
            x: CGFloat((rgb.red - luma) * push), y: CGFloat((rgb.green - luma) * push), z: CGFloat((rgb.blue - luma) * push), w: 0
        )

        let luminance = CIFilter.colorControls()
        luminance.inputImage = image
        luminance.saturation = 0
        luminance.contrast = 1
        luminance.brightness = 0
        var mask = luminance.outputImage ?? image
        if !inHighlights {
            mask = mask.applyingFilter("CIColorInvert")
        }
        // Concentrate the push at the ends of the range, then scale by strength.
        mask = scaled(mask.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 1.6]), by: CGFloat(tone.strength))

        let blend = CIFilter.blendWithMask()
        blend.inputImage = shift.outputImage
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// Halation: bright areas bleed a soft halo, like street lights at night.
    private static func glow(_ image: CIImage, amount: Double, unit: CGFloat) -> CIImage {
        let extent = image.extent
        let threshold: CGFloat = 0.45
        let gain = 1 / (1 - threshold)
        let highlights = CIFilter.colorMatrix()
        // Extend the photo's own edge pixels outwards so the blur never pulls in anything from outside it.
        highlights.inputImage = image.cropped(to: extent).clampedToExtent()
        highlights.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        highlights.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        highlights.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        highlights.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        highlights.biasVector = CIVector(x: -threshold * gain, y: -threshold * gain, z: -threshold * gain, w: 1)
        guard let bright = highlights.outputImage?.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 4, y: 4, z: 4, w: 1),
        ]) else { return image }

        let halo = bright
            .applyingGaussianBlur(sigma: Double(24 * unit))
            .cropped(to: extent)
        let add = CIFilter.additionCompositing()
        add.inputImage = scaled(halo, by: CGFloat(amount * 1.4))
        add.backgroundImage = image
        return add.outputImage.map { opaqueSum($0, layers: 2) }?.cropped(to: extent) ?? image
    }

    /// A cool, dark gradient from the top: turns a flat daytime sky into a night one.
    private static func darkenSky(_ image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        guard let top = stageColor(1 - 0.78 * amount, 1 - 0.72 * amount, 1 - 0.6 * amount),
              let clear = stageColor(1, 1, 1) else { return image }
        let gradient = CIFilter.smoothLinearGradient()
        gradient.point0 = CGPoint(x: extent.midX, y: extent.maxY)
        gradient.point1 = CGPoint(x: extent.midX, y: extent.maxY - extent.height * 0.6)
        gradient.color0 = top
        gradient.color1 = clear
        guard let shade = gradient.outputImage?.cropped(to: extent) else { return image }
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = shade
        multiply.backgroundImage = image
        return multiply.outputImage ?? image
    }

    private static func vignette(_ image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        let halfDiagonal = hypot(extent.width, extent.height) / 2
        let edge = 1 - 0.85 * amount
        guard let clear = stageColor(1, 1, 1), let dark = stageColor(edge, edge, edge) else { return image }
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: extent.midX, y: extent.midY)
        gradient.radius0 = Float(halfDiagonal * 0.4)
        gradient.radius1 = Float(halfDiagonal * 1.05)
        gradient.color0 = clear
        gradient.color1 = dark
        guard let shade = gradient.outputImage?.cropped(to: extent) else { return image }
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = shade
        multiply.backgroundImage = image
        return multiply.outputImage ?? image
    }

    /// Monochrome film grain: multiplies each pixel by noise averaging 1, so brightness is unchanged.
    private static func grain(_ image: CIImage, amount: Double, unit: CGFloat) -> CIImage {
        let extent = image.extent
        let size = max(1, 1.1 * unit)
        let tile = CIFilter.affineTile()
        tile.inputImage = GrainTexture.image
        tile.transform = CGAffineTransform(scaleX: size, y: size)
        guard let noise = tile.outputImage else { return image }
        let spread = CGFloat(amount * 0.35)
        let factor = CIFilter.colorMatrix()
        factor.inputImage = noise
        factor.rVector = CIVector(x: spread, y: 0, z: 0, w: 0)
        factor.gVector = CIVector(x: spread, y: 0, z: 0, w: 0)
        factor.bVector = CIVector(x: spread, y: 0, z: 0, w: 0)
        factor.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        factor.biasVector = CIVector(x: 1 - spread / 2, y: 1 - spread / 2, z: 1 - spread / 2, w: 1)
        guard let texture = factor.outputImage?.cropped(to: extent) else { return image }
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = texture
        multiply.backgroundImage = image
        return multiply.outputImage ?? image
    }

    /// Multiplies RGB by a factor and makes the result opaque.
    private static func scaled(_ image: CIImage, by factor: CGFloat) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: factor, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: factor, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: factor, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
    }

    /// Makes the sum of `layers` opaque images opaque again. Addition sums alpha too, so the sum has
    /// alpha `layers`; colour filters see the colour divided by that alpha, so multiply it back.
    static func opaqueSum(_ image: CIImage, layers: Int) -> CIImage {
        let gain = CGFloat(layers)
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
    }

    /// A colour for blending in the perceptual stage. There the pixel values are already gamma-encoded,
    /// so the sRGB numbers are passed through unconverted by tagging them as the (linear) working space.
    private static func stageColor(_ red: Double, _ green: Double, _ blue: Double) -> CIColor? {
        guard let space = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        return CIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1, colorSpace: space)
    }
}

/// A tileable grain pattern with values centred on 0.5. It is built from bytes and has no colour space,
/// so Core Image uses the values exactly as written (`CIRandomGenerator` output is not neutral once
/// colour-managed). The pattern is seeded, so the same photo always gets the same grain.
enum GrainTexture {
    static let size = 256

    static var image: CIImage {
        CIImage(bitmapData: bytes, bytesPerRow: size, size: CGSize(width: size, height: size), format: .L8, colorSpace: nil)
    }

    private static let bytes: Data = {
        var state: UInt32 = 0x9E37_79B9
        func next() -> Int {
            // xorshift32
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return Int(state & 0xFF)
        }
        // The average of two uniform samples gives a softer, film-like distribution.
        return Data((0..<(size * size)).map { _ in UInt8((next() + next()) / 2) })
    }()
}
