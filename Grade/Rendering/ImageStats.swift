import Foundation

/// Measurements on an 8-bit RGBA bitmap (top row first). Pure functions, used by the analysis.
enum ImageStats {
    /// Rec. 709 luma for each pixel, in 8-bit levels.
    static func luma(rgba: [UInt8], width: Int, height: Int) -> [Float] {
        var result = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let offset = index * 4
            result[index] = 0.2126 * Float(rgba[offset]) + 0.7152 * Float(rgba[offset + 1]) + 0.0722 * Float(rgba[offset + 2])
        }
        return result
    }

    /// Immerkær's fast noise estimate: the response to a mask that cancels smooth gradients and edges
    /// largely cancel, leaving noise. Returns the noise standard deviation in 8-bit levels.
    static func noise(luma: [Float], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return 0 }
        // Mask:  1 -2  1 / -2  4 -2 / 1 -2 1
        var sum = 0.0
        var counted = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let up = i - width, down = i + width
                let value = luma[up - 1] - 2 * luma[up] + luma[up + 1]
                    - 2 * luma[i - 1] + 4 * luma[i] - 2 * luma[i + 1]
                    + luma[down - 1] - 2 * luma[down] + luma[down + 1]
                // Skip strong edges so detail isn't mistaken for noise; noise up to about σ 15 is barely affected.
                if abs(value) < 200 {
                    sum += Double(abs(value))
                    counted += 1
                }
            }
        }
        guard counted > 0 else { return 0 }
        return (Double.pi / 2).squareRoot() * sum / (6 * Double(counted))
    }

    /// Mean absolute 4-neighbour Laplacian: higher means crisper edges and texture.
    static func sharpness(luma: [Float], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return 0 }
        var sum = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let laplacian = 4 * luma[i] - luma[i - 1] - luma[i + 1] - luma[i - width] - luma[i + width]
                sum += Double(abs(laplacian))
            }
        }
        return sum / Double((width - 2) * (height - 2))
    }

    /// Mean colour (0…1 per channel).
    static func meanColour(rgba: [UInt8], width: Int, height: Int) -> (red: Double, green: Double, blue: Double) {
        var red = 0.0, green = 0.0, blue = 0.0
        let count = width * height
        for index in 0..<count {
            red += Double(rgba[index * 4])
            green += Double(rgba[index * 4 + 1])
            blue += Double(rgba[index * 4 + 2])
        }
        let scale = 255 * Double(max(count, 1))
        return (red / scale, green / scale, blue / scale)
    }

    /// Distance of a colour from the grey of the same brightness, 0…1.
    static func colourCast(_ colour: (red: Double, green: Double, blue: Double)) -> Double {
        let grey = (colour.red + colour.green + colour.blue) / 3
        return max(abs(colour.red - grey), abs(colour.green - grey), abs(colour.blue - grey))
    }
}
