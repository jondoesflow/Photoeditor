import CoreGraphics
import Foundation
import Testing
@testable import Grade

@Suite("ImageStats: noise, sharpness and colour measurements")
struct ImageStatsTests {
    private func noisyLuma(sigma: Double, width: Int = 200, height: Int = 200) -> [Float] {
        var state: UInt64 = 42
        func gaussian() -> Double {
            // Sum of 12 uniforms minus 6 approximates a standard normal.
            var sum = 0.0
            for _ in 0..<12 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                sum += Double(state >> 11) / Double(1 << 53)
            }
            return sum - 6
        }
        return (0..<(width * height)).map { _ in Float(128 + gaussian() * sigma) }
    }

    @Test("A flat image has no noise", arguments: [0.0, 64.0, 200.0])
    func flat(level: Double) {
        let luma = [Float](repeating: Float(level), count: 100 * 100)
        #expect(ImageStats.noise(luma: luma, width: 100, height: 100) < 0.01)
    }

    @Test("Noise is estimated within 20%", arguments: [3.0, 8.0, 15.0])
    func noise(sigma: Double) {
        let estimate = ImageStats.noise(luma: noisyLuma(sigma: sigma), width: 200, height: 200)
        #expect(abs(estimate - sigma) / sigma < 0.2, "σ \(sigma) estimated as \(estimate)")
    }

    @Test("A smooth gradient isn't mistaken for noise")
    func gradient() {
        let luma = (0..<(100 * 100)).map { Float(($0 % 100) * 2) }
        #expect(ImageStats.noise(luma: luma, width: 100, height: 100) < 0.5)
    }

    @Test("Fine checks score sharper than broad checks")
    func sharpness() {
        func checks(_ size: Int) -> [Float] {
            (0..<(100 * 100)).map { index in ((index % 100) / size + (index / 100) / size).isMultiple(of: 2) ? 40 : 200 }
        }
        let fine = ImageStats.sharpness(luma: checks(2), width: 100, height: 100)
        let broad = ImageStats.sharpness(luma: checks(25), width: 100, height: 100)
        #expect(fine > broad * 5)
    }

    @Test("Mean colour and cast")
    func colour() {
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255]
        let mean = ImageStats.meanColour(rgba: pixels, width: 2, height: 1)
        #expect(abs(mean.red - 0.5) < 1e-9 && mean.green == 0 && abs(mean.blue - 0.5) < 1e-9)
        #expect(ImageStats.colourCast((0.5, 0.5, 0.5)) == 0)
        #expect(abs(ImageStats.colourCast((0.6, 0.5, 0.4)) - 0.1) < 1e-9)
    }
}

@Suite("Autopilot: choosing enhancements from the analysis")
struct AutopilotTests {
    private func insights(
        size: CGSize = CGSize(width: 4032, height: 3024), faces: Int = 0, noise: Double = 1,
        sharpness: Double = 10, brightness: Double = 0.5, cast: Double = 0
    ) -> PhotoInsights {
        PhotoInsights(pixelSize: size, faceCount: faces, hasSubject: faces > 0, noise: noise, sharpness: sharpness, brightness: brightness, colourCast: cast)
    }

    @Test("A clean, sharp, well-exposed photo gets only a light touch")
    func cleanPhoto() {
        let result = Autopilot.recommend(for: insights())
        #expect(result.denoise == 0)
        #expect(result.detail == 0)
        #expect(result.colour == 0)
        #expect(result.faces == 0)
        #expect(result.upscale == .none)
        #expect(result.light == 0.5)
    }

    @Test("Noise is denoised, and detail is held back on noisy photos")
    func noisyPhoto() {
        let result = Autopilot.recommend(for: insights(noise: 6, sharpness: 2))
        #expect(result.denoise > 0.5)
        #expect(result.detail <= 0.2)
    }

    @Test("A soft but clean photo gets detail")
    func softPhoto() {
        #expect(Autopilot.recommend(for: insights(sharpness: 2)).detail == 0.5)
        #expect(Autopilot.recommend(for: insights(sharpness: 6)).detail == 0.25)
    }

    @Test("Dark or bright photos get more light correction")
    func exposure() {
        #expect(Autopilot.recommend(for: insights(brightness: 0.15)).light == 0.8)
        #expect(Autopilot.recommend(for: insights(brightness: 0.9)).light == 0.8)
    }

    @Test("A colour cast is balanced, more for a stronger cast")
    func cast() {
        let mild = Autopilot.recommend(for: insights(cast: 0.05)).colour
        let strong = Autopilot.recommend(for: insights(cast: 0.15)).colour
        #expect(mild > 0 && strong > mild && strong <= 0.9)
    }

    @Test("Faces are enhanced when there are faces")
    func faces() {
        #expect(Autopilot.recommend(for: insights(faces: 2)).faces == 0.5)
    }

    @Test("Small photos are upscaled 2×; large ones aren't")
    func upscale() {
        #expect(Autopilot.recommend(for: insights(size: CGSize(width: 1600, height: 1200))).upscale == .double)
        #expect(Autopilot.recommend(for: insights(size: CGSize(width: 4032, height: 3024))).upscale == .none)
    }

    @Test("Autopilot leaves the background choice alone")
    func keepsBackground() {
        var current = Enhancement.none
        current.background = .remove
        #expect(Autopilot.recommend(for: insights(), keeping: current).background == .remove)
    }

    @Test("Upscale limits keep the output at or below 48 MP")
    func upscaleLimits() {
        #expect(UpscaleFactor.double.isAvailable(for: CGSize(width: 4032, height: 3024)) == false)
        #expect(UpscaleFactor.double.isAvailable(for: CGSize(width: 3000, height: 2000)))
        #expect(UpscaleFactor.quadruple.isAvailable(for: CGSize(width: 1600, height: 1200)))
        #expect(UpscaleFactor.quadruple.isAvailable(for: CGSize(width: 2000, height: 1600)) == false)
        #expect(UpscaleFactor.none.outputSize(for: CGSize(width: 10, height: 20)) == CGSize(width: 10, height: 20))
    }

    @Test("The summary describes what was found")
    func summary() {
        let text = insights(size: CGSize(width: 2000, height: 1000), faces: 1, noise: 5, sharpness: 2, brightness: 0.2, cast: 0.1).summary
        for part in ["1 face", "subject", "noisy", "soft", "dark", "colour cast", "2.0 MP"] {
            #expect(text.contains(part), "\(text) is missing \(part)")
        }
    }
}
