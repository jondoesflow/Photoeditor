import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
@testable import Grade

/// An 8-bit sRGB copy of a rendered image, top row first.
struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    struct RGB {
        var red: Double
        var green: Double
        var blue: Double

        var spread: Double { max(red, green, blue) - min(red, green, blue) }
        var brightness: Double { (red + green + blue) / 3 }
    }

    func pixel(x: Int, y: Int) -> RGB {
        let index = (y * width + x) * 4
        return RGB(red: Double(bytes[index]) / 255, green: Double(bytes[index + 1]) / 255, blue: Double(bytes[index + 2]) / 255)
    }

    /// Alpha, 0…1.
    func alpha(x: Int, y: Int) -> Double {
        Double(bytes[(y * width + x) * 4 + 3]) / 255
    }

    /// Mean colour of a region (defaults to the whole image).
    func mean(_ rect: CGRect? = nil) -> RGB {
        let area = rect ?? CGRect(x: 0, y: 0, width: width, height: height)
        var sum = RGB(red: 0, green: 0, blue: 0)
        var count = 0.0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                let p = pixel(x: x, y: y)
                sum.red += p.red; sum.green += p.green; sum.blue += p.blue
                count += 1
            }
        }
        return RGB(red: sum.red / count, green: sum.green / count, blue: sum.blue / count)
    }

    /// Standard deviation of brightness, a measure of texture.
    var brightnessDeviation: Double {
        let values = (0..<(width * height)).map { pixel(x: $0 % width, y: $0 / width).brightness }
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }
}

enum TestImages {
    static let context = CIContext()
    static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    static func solid(_ red: Double, _ green: Double, _ blue: Double, size: CGSize = CGSize(width: 64, height: 64)) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1, colorSpace: sRGB)!)
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Hue changes left to right and brightness bottom to top, like a small colourful photo.
    static func gradient(size: CGSize = CGSize(width: 240, height: 160)) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        let hues = CIFilter.smoothLinearGradient()
        hues.point0 = CGPoint(x: 0, y: 0)
        hues.point1 = CGPoint(x: size.width, y: 0)
        hues.color0 = CIColor(red: 0.95, green: 0.45, blue: 0.15, alpha: 1, colorSpace: sRGB)!
        hues.color1 = CIColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1, colorSpace: sRGB)!
        let light = CIFilter.smoothLinearGradient()
        light.point0 = CGPoint(x: 0, y: 0)
        light.point1 = CGPoint(x: 0, y: size.height)
        light.color0 = CIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1, colorSpace: sRGB)!
        light.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1, colorSpace: sRGB)!
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = hues.outputImage!.cropped(to: rect)
        multiply.backgroundImage = light.outputImage!.cropped(to: rect)
        return multiply.outputImage!.cropped(to: rect)
    }

    /// A flat colour with seeded random noise: `luma` adds the same value to every channel,
    /// `chroma` adds a different value to each channel.
    static func noisy(
        _ red: Double, _ green: Double, _ blue: Double, luma: Double = 0, chroma: Double = 0,
        size: CGSize = CGSize(width: 128, height: 128)
    ) -> CIImage {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 33) / Double(1 << 31) - 0.5
        }
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let shared = random() * luma
            for (channel, base) in [red, green, blue].enumerated() {
                let value = base + shared + random() * chroma
                bytes[index * 4 + channel] = UInt8((value * 255).rounded().clamped(to: 0...255))
            }
        }
        return CIImage(
            bitmapData: Data(bytes), bytesPerRow: width * 4, size: size, format: .RGBA8, colorSpace: sRGB
        )
    }

    /// JPEG data for a small synthetic photo, for tests that go through the whole load and save path.
    static func jpegData(size: CGSize = CGSize(width: 120, height: 80)) -> Data {
        context.jpegRepresentation(of: gradient(size: size), colorSpace: sRGB, options: [:])!
    }

    static func bitmap(_ image: CIImage) -> Bitmap {
        let extent = image.extent
        let cgImage = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: sRGB)!
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let bitmapContext = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    static func render(_ recipe: Recipe, on image: CIImage) -> Bitmap {
        bitmap(FilterChain.apply(recipe, to: image))
    }

    static func demoPhotoData() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "DemoPhoto", withExtension: "jpg"))
        return try Data(contentsOf: url)
    }
}

extension Recipe {
    static func only(_ parameter: Parameter, _ value: Double) -> Recipe {
        Recipe([parameter: value])
    }
}

/// A saver that records what it was given, or fails on demand.
actor RecordingSaver: PhotoSaving {
    private(set) var saved: [Data] = []
    let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func save(_ data: Data) async throws {
        if shouldFail { throw SaveError.notAuthorized }
        saved.append(data)
    }
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("GradeTests-\(UUID().uuidString)", isDirectory: true)
}
