import CoreImage
import Foundation
import Testing
@testable import Grade

@Suite("FilterChain: what each setting does to real pixels")
struct FilterChainTests {
    private var grey: CIImage { TestImages.solid(0.5, 0.5, 0.5) }

    @Test("A neutral recipe returns the input untouched")
    func neutralIsIdentity() {
        let image = TestImages.gradient()
        #expect(FilterChain.apply(.neutral, to: image) === image)
    }

    @Test("Exposure brightens and darkens")
    func exposure() {
        let before = TestImages.bitmap(grey).mean().brightness
        #expect(TestImages.render(.only(.exposure, 0.5), on: grey).mean().brightness > before + 0.08)
        #expect(TestImages.render(.only(.exposure, -0.5), on: grey).mean().brightness < before - 0.08)
    }

    @Test("Warmth adds red and removes blue; negative does the opposite")
    func warmth() {
        let warm = TestImages.render(.only(.warmth, 0.6), on: grey).mean()
        let cool = TestImages.render(.only(.warmth, -0.6), on: grey).mean()
        #expect(warm.red - warm.blue > 0.04)
        #expect(cool.blue - cool.red > 0.04)
    }

    @Test("Positive tint is magenta, negative is green")
    func tint() {
        let magenta = TestImages.render(.only(.tint, 0.8), on: grey).mean()
        let green = TestImages.render(.only(.tint, -0.8), on: grey).mean()
        #expect((magenta.red + magenta.blue) / 2 - magenta.green > 0.02)
        #expect(green.green - (green.red + green.blue) / 2 > 0.02)
    }

    @Test("Saturation −1 is black and white; +0.6 is more colourful")
    func saturation() {
        let colourful = TestImages.solid(0.8, 0.35, 0.2)
        let before = TestImages.bitmap(colourful).mean().spread
        #expect(TestImages.render(.only(.saturation, -1), on: colourful).mean().spread < 0.02)
        #expect(TestImages.render(.only(.saturation, 0.6), on: colourful).mean().spread > before + 0.05)
    }

    @Test("Contrast pushes darks down and lights up")
    func contrast() {
        let dark = TestImages.solid(0.25, 0.25, 0.25), light = TestImages.solid(0.75, 0.75, 0.75)
        #expect(TestImages.render(.only(.contrast, 1), on: dark).mean().brightness < 0.22)
        #expect(TestImages.render(.only(.contrast, 1), on: light).mean().brightness > 0.78)
    }

    @Test("Fade lifts pure black")
    func fade() {
        let black = TestImages.solid(0, 0, 0)
        #expect(TestImages.render(.only(.fade, 1), on: black).mean().brightness > 0.08)
    }

    @Test("Highlights −1 darkens bright tones; shadows +1 lifts dark tones")
    func highlightsAndShadows() {
        let bright = TestImages.solid(0.8, 0.8, 0.8), dark = TestImages.solid(0.22, 0.22, 0.22)
        #expect(TestImages.render(.only(.highlights, -1), on: bright).mean().brightness < 0.76)
        #expect(TestImages.render(.only(.shadows, 1), on: dark).mean().brightness > 0.26)
    }

    @Test("Vibrance boosts muted colours")
    func vibrance() {
        let muted = TestImages.solid(0.55, 0.45, 0.4)
        let before = TestImages.bitmap(muted).mean().spread
        #expect(TestImages.render(.only(.vibrance, 1), on: muted).mean().spread > before + 0.02)
    }

    @Test("A shadow tone tints dark areas towards its colour")
    func shadowTone() {
        let dark = TestImages.solid(0.18, 0.18, 0.18)
        let recipe = Recipe(shadowTone: Tone(color: "#0B5C66", strength: 1))
        let result = TestImages.render(recipe, on: dark).mean()
        #expect(result.blue > result.red + 0.02)
        #expect(result.green > result.red + 0.02)
    }

    @Test("A highlight tone tints bright areas towards its colour")
    func highlightTone() {
        let bright = TestImages.solid(0.82, 0.82, 0.82)
        let recipe = Recipe(highlightTone: Tone(color: "#FF9E4A", strength: 1))
        let result = TestImages.render(recipe, on: bright).mean()
        #expect(result.red > result.blue + 0.03)
    }

    @Test("Night sky darkens the top of the frame, not the bottom")
    func skyDarken() {
        let image = TestImages.solid(0.7, 0.7, 0.7, size: CGSize(width: 64, height: 128))
        let bitmap = TestImages.render(.only(.skyDarken, 1), on: image)
        let top = bitmap.mean(CGRect(x: 0, y: 0, width: 64, height: 12)).brightness
        let bottom = bitmap.mean(CGRect(x: 0, y: 116, width: 64, height: 12)).brightness
        #expect(top < bottom - 0.25)
        #expect(abs(bottom - 0.7) < 0.02)
    }

    @Test("Vignette darkens corners more than the centre")
    func vignette() {
        let image = TestImages.solid(0.6, 0.6, 0.6, size: CGSize(width: 200, height: 200))
        let bitmap = TestImages.render(.only(.vignette, 1), on: image)
        let corner = bitmap.mean(CGRect(x: 0, y: 0, width: 10, height: 10)).brightness
        let centre = bitmap.mean(CGRect(x: 95, y: 95, width: 10, height: 10)).brightness
        #expect(corner < centre - 0.15)
        #expect(abs(centre - 0.6) < 0.02)
    }

    @Test("Glow spreads light around bright spots")
    func glow() {
        let size = CGSize(width: 200, height: 200)
        let spot = TestImages.solid(1, 1, 1, size: CGSize(width: 20, height: 20)).transformed(by: CGAffineTransform(translationX: 90, y: 90))
        let image = spot.composited(over: TestImages.solid(0.05, 0.05, 0.05, size: size))
        let before = TestImages.bitmap(image).mean(CGRect(x: 112, y: 95, width: 5, height: 10)).brightness
        let after = TestImages.render(.only(.glow, 1), on: image).mean(CGRect(x: 112, y: 95, width: 5, height: 10)).brightness
        #expect(after > before + 0.05)
    }

    @Test("Glow leaves areas away from bright spots exactly as they were")
    func glowKeepsBrightness() {
        let image = TestImages.solid(0.4, 0.3, 0.2, size: CGSize(width: 100, height: 100))
        let before = TestImages.bitmap(image).mean()
        let after = TestImages.render(.only(.glow, 1), on: image).mean()
        #expect(abs(after.red - before.red) < 0.01 && abs(after.green - before.green) < 0.01 && abs(after.blue - before.blue) < 0.01,
                "\(before) → \(after)")
    }

    @Test("Grain adds texture to a flat image without changing its brightness")
    func grain() {
        let image = TestImages.solid(0.5, 0.5, 0.5, size: CGSize(width: 128, height: 128))
        let bitmap = TestImages.render(.only(.grain, 1), on: image)
        #expect(TestImages.bitmap(image).brightnessDeviation < 0.005)
        #expect(bitmap.brightnessDeviation > 0.02)
        #expect(abs(bitmap.mean().brightness - 0.5) < 0.03)
    }

    @Test("Sharpen increases contrast at an edge")
    func sharpen() {
        let size = CGSize(width: 64, height: 64)
        let half = TestImages.solid(0.7, 0.7, 0.7, size: CGSize(width: 32, height: 64))
        let image = half.composited(over: TestImages.solid(0.3, 0.3, 0.3, size: size))
        let before = TestImages.bitmap(image).pixel(x: 30, y: 32).brightness
        let after = TestImages.render(.only(.sharpen, 1), on: image).pixel(x: 30, y: 32).brightness
        #expect(after > before + 0.01)
    }

    @Test("Every bundled preset keeps the image size and produces valid pixels")
    func presetsRender() throws {
        let library = try PresetLibrary.loadBundled()
        let image = TestImages.gradient()
        for preset in library.presets {
            let output = FilterChain.apply(preset.recipe, to: image)
            #expect(output.extent == image.extent, "\(preset.id) changed the extent")
            let mean = TestImages.bitmap(output).mean()
            #expect(mean.brightness > 0.02 && mean.brightness < 0.98, "\(preset.id) renders blank: \(mean)")
        }
    }

    @Test("Presets with a vignette darken the corners, never brighten them")
    func presetCorners() throws {
        let library = try PresetLibrary.loadBundled()
        let image = TestImages.solid(0.5, 0.5, 0.5, size: CGSize(width: 300, height: 200))
        for preset in library.presets where preset.recipe[.vignette] > 0 {
            let bitmap = TestImages.render(preset.recipe, on: image)
            let corner = bitmap.mean(CGRect(x: 0, y: 180, width: 20, height: 20)).brightness
            let centre = bitmap.mean(CGRect(x: 140, y: 90, width: 20, height: 20)).brightness
            #expect(corner < centre, "\(preset.id): corner \(corner) vs centre \(centre)")
        }
    }

    @Test("Fade and glow together leave a flat image flat to its edges")
    func fadeAndGlowEdges() {
        let image = TestImages.solid(0.5, 0.5, 0.5, size: CGSize(width: 300, height: 200))
        let bitmap = TestImages.render(Recipe([.fade: 0.3, .glow: 1]), on: image)
        let edge = bitmap.mean(CGRect(x: 0, y: 0, width: 300, height: 4)).brightness
        let centre = bitmap.mean(CGRect(x: 140, y: 90, width: 20, height: 20)).brightness
        #expect(abs(edge - centre) < 0.02)
    }

    @Test("Grain is centred: it doesn't change a preset's overall brightness")
    func grainIsNeutralInPresets() {
        let image = TestImages.gradient()
        let without = TestImages.render(Recipe([.contrast: 0.2]), on: image).mean().brightness
        let with = TestImages.render(Recipe([.contrast: 0.2, .grain: 1]), on: image).mean().brightness
        #expect(abs(with - without) < 0.02)
    }

    @Test("A preset looks the same on a small preview and a large export")
    func resolutionIndependent() throws {
        let preset = try #require(PresetLibrary.loadBundled().preset(id: "neon-nights"))
        let small = TestImages.render(preset.recipe, on: TestImages.gradient(size: CGSize(width: 300, height: 200))).mean()
        let large = TestImages.render(preset.recipe, on: TestImages.gradient(size: CGSize(width: 1500, height: 1000))).mean()
        #expect(abs(small.red - large.red) < 0.03)
        #expect(abs(small.green - large.green) < 0.03)
        #expect(abs(small.blue - large.blue) < 0.03)
    }
}
