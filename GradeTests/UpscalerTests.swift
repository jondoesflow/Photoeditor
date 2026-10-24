import CoreImage
import Foundation
import Testing
@testable import Grade

@Suite("Upscaler: AI upscaling with the bundled Core ML model")
struct UpscalerTests {
    private let context = CIContext()

    @Test("2× and 4× give the right size and keep the colours", arguments: [2, 4])
    func sizeAndColour(factor: Int) throws {
        let upscaler = try Upscaler(context: context)
        let image = TestImages.gradient(size: CGSize(width: 96, height: 64))
        let output = try upscaler.upscale(image, factor: factor)
        #expect(output.extent.size == CGSize(width: 96 * factor, height: 64 * factor))
        let before = TestImages.bitmap(image).mean(), after = TestImages.bitmap(output).mean()
        #expect(abs(before.red - after.red) < 0.04)
        #expect(abs(before.green - after.green) < 0.04)
        #expect(abs(before.blue - after.blue) < 0.04)
    }

    @Test("Tiles join without seams or gaps")
    func tiling() throws {
        let upscaler = try Upscaler(context: context)
        // Wider and taller than one tile's core, so several tiles meet.
        let image = TestImages.gradient(size: CGSize(width: 300, height: 260))
        var reported: [Double] = []
        let output = try upscaler.upscale(image, factor: 2) { reported.append($0) }
        #expect(output.extent.size == CGSize(width: 600, height: 520))
        #expect(reported.count == 4)
        #expect(reported.last == 1)
        let bitmap = TestImages.bitmap(output)
        // No transparent or black gaps anywhere, including along tile edges (core is 224 px → 448 px at 2×).
        for y in stride(from: 0, to: 520, by: 7) {
            for x in [0, 446, 447, 448, 449, 599] {
                #expect(bitmap.alpha(x: x, y: y) > 0.99)
            }
        }
        // Across a seam, neighbouring columns stay similar.
        let left = bitmap.mean(CGRect(x: 446, y: 100, width: 2, height: 300))
        let right = bitmap.mean(CGRect(x: 448, y: 100, width: 2, height: 300))
        #expect(abs(left.brightness - right.brightness) < 0.03)
    }

    @Test("Refuses output above the 48 MP limit")
    func limit() throws {
        let upscaler = try Upscaler(context: context)
        let huge = TestImages.solid(0.5, 0.5, 0.5, size: CGSize(width: 4100, height: 3000))
        #expect(throws: UpscaleError.self) { try upscaler.upscale(huge, factor: 2) }
    }

    @Test("Upscaling adds detail: edges are crisper than simple resizing")
    func crisperThanResize() throws {
        let upscaler = try Upscaler(context: context)
        let photo = try #require(CIImage(data: try TestImages.demoPhotoData()))
        let small = photo.transformed(by: CGAffineTransform(scaleX: 0.05, y: 0.05))
        let smallBitmap = CIImage(cgImage: context.createCGImage(small, from: small.extent.integral)!)
        let ai = TestImages.bitmap(try upscaler.upscale(smallBitmap, factor: 4))
        let resized = TestImages.bitmap(smallBitmap.transformed(by: CGAffineTransform(scaleX: 4, y: 4)))
        func sharpness(_ bitmap: Bitmap) -> Double {
            let luma = ImageStats.luma(rgba: bitmap.bytes, width: bitmap.width, height: bitmap.height)
            return ImageStats.sharpness(luma: luma, width: bitmap.width, height: bitmap.height)
        }
        #expect(sharpness(ai) > sharpness(resized) * 1.2, "AI \(sharpness(ai)) vs resize \(sharpness(resized))")
    }
}

@Suite("PhotoAnalyzer: what a real photo contains")
struct PhotoAnalyzerTests {
    private func portraitData() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "DemoPortrait", withExtension: "jpg"))
        return try Data(contentsOf: url)
    }

    @Test("Finds the face in the demo portrait, and measures it as clean and sharp enough")
    func portrait() async throws {
        let insights = try await PhotoRenderer().load(try portraitData())
        #expect(insights.faceCount >= 1)
        #expect(insights.pixelSize == CGSize(width: 1600, height: 2400))
        #expect(insights.noise < Autopilot.noisyThreshold)
        #expect((0.05...0.95).contains(insights.brightness))
    }

    @Test("Finds the subject in the demo portrait (needs the Neural Engine or person segmentation)")
    func subject() async throws {
        let insights = try await PhotoRenderer().load(try portraitData())
        withKnownIssue("Subject masks may be unavailable on the simulator", isIntermittent: true) {
            #expect(insights.hasSubject)
        }
    }

    @Test("No faces in the car photo")
    func noFaces() async throws {
        let insights = try await PhotoRenderer().load(try TestImages.demoPhotoData())
        #expect(insights.faceCount == 0)
    }

    @Test("Noise is detected in a noisy photo")
    func noisy() async throws {
        let noisy = TestImages.noisy(0.5, 0.45, 0.4, luma: 0.2, chroma: 0.05, size: CGSize(width: 600, height: 600))
        let data = try #require(TestImages.context.jpegRepresentation(of: noisy, colorSpace: TestImages.sRGB, options: [:]))
        let insights = try await PhotoRenderer().load(data)
        #expect(insights.noise >= Autopilot.noisyThreshold)
        #expect(Autopilot.recommend(for: insights).denoise > 0.3)
    }
}
