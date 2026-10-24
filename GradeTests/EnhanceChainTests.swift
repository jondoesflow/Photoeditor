import CoreImage
import Foundation
import Testing
@testable import Grade

@Suite("EnhanceChain: what each Enhance tool does to real pixels")
struct EnhanceChainTests {
    private func apply(_ enhancement: Enhancement, to image: CIImage, context: EnhanceContext = EnhanceContext()) -> Bitmap {
        TestImages.bitmap(EnhanceChain.apply(enhancement, context: context, to: image))
    }

    private func enhancement(_ tool: EnhanceTool, _ value: Double = 1) -> Enhancement {
        var result = Enhancement.none
        result[tool] = value
        return result
    }

    @Test("No enhancement returns the input untouched")
    func neutralIsIdentity() {
        let image = TestImages.gradient()
        #expect(EnhanceChain.apply(.none, context: EnhanceContext(), to: image) === image)
        var upscaleOnly = Enhancement.none
        upscaleOnly.upscale = .double
        #expect(EnhanceChain.apply(upscaleOnly, context: EnhanceContext(), to: image) === image)
    }

    @Test("Denoise smooths grain without changing brightness")
    func denoiseLuma() {
        let image = TestImages.noisy(0.5, 0.5, 0.5, luma: 0.25)
        let before = TestImages.bitmap(image)
        let after = apply(enhancement(.denoise), to: image)
        #expect(after.brightnessDeviation < before.brightnessDeviation * 0.6, "\(before.brightnessDeviation) → \(after.brightnessDeviation)")
        #expect(abs(after.mean().brightness - before.mean().brightness) < 0.02)
    }

    @Test("Denoise removes colour speckles and keeps the average colour")
    func denoiseChroma() {
        let image = TestImages.noisy(0.6, 0.4, 0.3, chroma: 0.3)
        let before = TestImages.bitmap(image)
        let after = apply(enhancement(.denoise), to: image)
        func meanSpread(_ bitmap: Bitmap) -> Double {
            var total = 0.0
            for y in 20..<100 { for x in 20..<100 { total += abs(bitmap.pixel(x: x, y: y).spread - 0.3) } }
            return total / 6400
        }
        #expect(meanSpread(after) < meanSpread(before) * 0.6, "\(meanSpread(before)) → \(meanSpread(after))")
        let b = before.mean(), a = after.mean()
        #expect(abs(a.red - b.red) < 0.03 && abs(a.green - b.green) < 0.03 && abs(a.blue - b.blue) < 0.03)
    }

    @Test("Dust removes small specks and leaves the rest alone")
    func dust() {
        let size = CGSize(width: 64, height: 64)
        var image = TestImages.solid(0.4, 0.4, 0.4, size: size)
        for (x, y) in [(10, 10), (40, 20), (25, 50)] {
            let speck = TestImages.solid(1, 1, 1, size: CGSize(width: 2, height: 2))
                .transformed(by: CGAffineTransform(translationX: CGFloat(x), y: CGFloat(y)))
            image = speck.composited(over: image)
        }
        let before = TestImages.bitmap(image)
        let after = apply(enhancement(.dust), to: image)
        // The speck at CI (40, 20) is at bitmap row 64 - 20 - 2 = 42.
        #expect(before.pixel(x: 40, y: 42).brightness > 0.9)
        #expect(after.pixel(x: 40, y: 42).brightness < 0.5)
        #expect(abs(after.pixel(x: 5, y: 30).brightness - 0.4) < 0.02)
    }

    @Test("Colour balance pulls a cast towards neutral")
    func colourBalance() {
        let image = TestImages.solid(0.4, 0.45, 0.62)
        let mean = TestImages.bitmap(image).mean()
        var context = EnhanceContext()
        context.colourGains = PhotoAnalyzer.gains(for: (mean.red, mean.green, mean.blue))
        let after = apply(enhancement(.colour), to: image, context: context).mean()
        #expect(after.spread < mean.spread * 0.5, "\(mean.spread) → \(after.spread)")
    }

    @Test("Colour gains are limited so a deliberately coloured photo isn't flattened")
    func gainLimits() {
        let gains = PhotoAnalyzer.gains(for: (0.9, 0.3, 0.05))
        for gain in [gains.red, gains.green, gains.blue] { #expect((0.6...1.6).contains(gain)) }
    }

    @Test("Light uses Apple's auto-adjust to brighten an underexposed photo")
    func light() throws {
        let photo = try #require(CIImage(data: try TestImages.demoPhotoData()))
        let dark = photo.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -2.5])
        var context = EnhanceContext()
        context.lightFilters = dark.autoAdjustmentFilters(options: [.redEye: false, .enhance: true])
            .filter { !["CIFaceBalance", "CIVibrance"].contains($0.name) }
        #expect(!context.lightFilters.isEmpty)
        let small = dark.transformed(by: CGAffineTransform(scaleX: 0.1, y: 0.1))
        let before = TestImages.bitmap(small).mean().brightness
        let after = apply(enhancement(.light), to: small, context: context).mean().brightness
        #expect(after > before + 0.05, "\(before) → \(after)")
    }

    @Test("Detail increases contrast at an edge")
    func detail() {
        let size = CGSize(width: 64, height: 64)
        let half = TestImages.solid(0.7, 0.7, 0.7, size: CGSize(width: 32, height: 64))
        let image = half.composited(over: TestImages.solid(0.3, 0.3, 0.3, size: size))
        let before = TestImages.bitmap(image).pixel(x: 30, y: 32).brightness
        let after = apply(enhancement(.detail), to: image).pixel(x: 30, y: 32).brightness
        #expect(after > before + 0.02)
    }

    @Test("Faces brightens and smooths inside the face only")
    func faces() {
        let image = TestImages.noisy(0.45, 0.35, 0.3, luma: 0.2, size: CGSize(width: 200, height: 200))
        var context = EnhanceContext()
        context.faces = [CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)]
        let before = TestImages.bitmap(image)
        let after = apply(enhancement(.faces), to: image, context: context)
        let face = CGRect(x: 90, y: 90, width: 20, height: 20), corner = CGRect(x: 0, y: 0, width: 20, height: 20)
        #expect(after.mean(face).brightness > before.mean(face).brightness + 0.03)
        #expect(abs(after.mean(corner).brightness - before.mean(corner).brightness) < 0.01)
        #expect(enhancementHasNoEffectWithoutFaces(image))
    }

    private func enhancementHasNoEffectWithoutFaces(_ image: CIImage) -> Bool {
        EnhanceChain.apply(enhancement(.faces), context: EnhanceContext(), to: image) === image
            || TestImages.bitmap(EnhanceChain.apply(enhancement(.faces), context: EnhanceContext(), to: image)).mean().brightness
            == TestImages.bitmap(image).mean().brightness
    }

    /// Stripes on the left half (subject) and right half (background), with a mask marking the left half.
    private func stripedScene() -> (image: CIImage, context: EnhanceContext) {
        let size = CGSize(width: 200, height: 100)
        var image = TestImages.solid(0.2, 0.2, 0.2, size: size)
        for x in stride(from: 0, to: 200, by: 8) {
            let stripe = TestImages.solid(0.8, 0.8, 0.8, size: CGSize(width: 4, height: 100))
                .transformed(by: CGAffineTransform(translationX: CGFloat(x), y: 0))
            image = stripe.composited(over: image)
        }
        let subject = TestImages.solid(1, 1, 1, size: CGSize(width: 100, height: 100))
            .composited(over: TestImages.solid(0, 0, 0, size: size))
        var context = EnhanceContext()
        context.subjectMask = subject
        return (image, context)
    }

    @Test("Background blur softens the background and keeps the subject sharp")
    func backgroundBlur() {
        let scene = stripedScene()
        var settings = Enhancement.none
        settings.background = .blur
        settings.backgroundBlur = 1
        let before = TestImages.bitmap(scene.image)
        let after = apply(settings, to: scene.image, context: scene.context)
        func deviation(_ bitmap: Bitmap, x: Int) -> Double {
            let values = (x..<(x + 40)).map { bitmap.pixel(x: $0, y: 50).brightness }
            let mean = values.reduce(0, +) / 40
            return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 40).squareRoot()
        }
        #expect(deviation(after, x: 150) < deviation(before, x: 150) * 0.4)
        #expect(abs(deviation(after, x: 20) - deviation(before, x: 20)) < 0.01)
    }

    @Test("Removing the background makes it transparent and keeps the subject")
    func removeBackground() throws {
        let scene = stripedScene()
        let mask = try #require(scene.context.scaledSubjectMask(for: scene.image.extent))
        let bitmap = TestImages.bitmap(EnhanceChain.removeBackground(scene.image, subjectMask: mask))
        #expect(bitmap.alpha(x: 20, y: 50) > 0.99)
        #expect(bitmap.alpha(x: 180, y: 50) < 0.01)
    }

    @Test("The subject mask stretches to any size, so the preview mask works for the full photo")
    func maskScaling() throws {
        let scene = stripedScene()
        let large = CGRect(x: 0, y: 0, width: 800, height: 400)
        let mask = try #require(scene.context.scaledSubjectMask(for: large))
        #expect(mask.extent == large)
        let bitmap = TestImages.bitmap(mask)
        #expect(bitmap.pixel(x: 100, y: 200).brightness > 0.99)
        #expect(bitmap.pixel(x: 700, y: 200).brightness < 0.01)
    }

    @Test("Every tool keeps the image size", arguments: EnhanceTool.allCases)
    func extent(tool: EnhanceTool) {
        let scene = stripedScene()
        var context = scene.context
        context.faces = [CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)]
        var settings = enhancement(tool)
        if tool == .background { settings.background = .blur }
        let output = EnhanceChain.apply(settings, context: context, to: scene.image)
        #expect(output.extent == scene.image.extent)
    }
}
