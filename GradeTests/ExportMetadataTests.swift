import Foundation
import ImageIO
import Testing
@testable import Grade

@Suite("ExportMetadata: what the saved copy keeps")
struct ExportMetadataTests {
    private var source: [String: Any] { [
        kCGImagePropertyOrientation as String: 6,
        kCGImagePropertyPixelWidth as String: 4032,
        kCGImagePropertyPixelHeight as String: 3024,
        kCGImagePropertyTIFFDictionary as String: [
            kCGImagePropertyTIFFOrientation as String: 6,
            kCGImagePropertyTIFFModel as String: "iPhone",
        ] as [String: Any],
        kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifDateTimeOriginal as String: "2026:10:24 07:06:00",
            kCGImagePropertyExifPixelXDimension as String: 4032,
        ] as [String: Any],
        kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 51.5],
        kCGImagePropertyMakerAppleDictionary as String: ["33": 0.5],
    ] }

    @Test("Orientation is reset because the pixels are already upright")
    func orientation() {
        let result = ExportMetadata.properties(from: source)
        #expect(result[kCGImagePropertyOrientation as String] as? Int == 1)
        let tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        #expect(tiff?[kCGImagePropertyTIFFOrientation as String] as? Int == 1)
    }

    @Test("Date, camera and location are kept")
    func kept() {
        let result = ExportMetadata.properties(from: source)
        let exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gps = result[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2026:10:24 07:06:00")
        #expect(tiff?[kCGImagePropertyTIFFModel as String] as? String == "iPhone")
        #expect(gps?[kCGImagePropertyGPSLatitude as String] as? Double == 51.5)
    }

    @Test("Stale sizes and Apple's maker note are dropped; software is set")
    func dropped() {
        let result = ExportMetadata.properties(from: source)
        let exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        #expect(result[kCGImagePropertyPixelWidth as String] == nil)
        #expect(result[kCGImagePropertyMakerAppleDictionary as String] == nil)
        #expect(exif?[kCGImagePropertyExifPixelXDimension as String] == nil)
        #expect(tiff?[kCGImagePropertyTIFFSoftware as String] as? String == "Grade")
    }

    @Test("Works for photos with no metadata at all")
    func empty() {
        let result = ExportMetadata.properties(from: [:])
        #expect(result[kCGImagePropertyOrientation as String] as? Int == 1)
    }
}
