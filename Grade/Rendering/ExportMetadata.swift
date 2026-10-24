import Foundation
import ImageIO

/// Prepares the original photo's metadata for the edited copy.
enum ExportMetadata {
    static let software = "Grade"

    /// Keeps date, camera and location, but resets orientation (the pixels are already upright)
    /// and drops values that no longer describe the new image.
    static func properties(from source: [String: Any]) -> [String: Any] {
        var properties = source
        properties[kCGImagePropertyOrientation as String] = 1
        properties.removeValue(forKey: kCGImagePropertyPixelWidth as String)
        properties.removeValue(forKey: kCGImagePropertyPixelHeight as String)
        // Apple's maker note carries HDR and depth hints for the original pixels.
        properties.removeValue(forKey: kCGImagePropertyMakerAppleDictionary as String)

        var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        tiff[kCGImagePropertyTIFFSoftware as String] = software
        properties[kCGImagePropertyTIFFDictionary as String] = tiff

        if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
            properties[kCGImagePropertyExifDictionary as String] = exif
        }
        return properties
    }
}
