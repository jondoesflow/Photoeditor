import Foundation
import Photos

/// Somewhere to put a finished photo.
protocol PhotoSaving: Sendable {
    func save(_ data: Data) async throws
}

enum SaveError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        "Grade isn't allowed to add photos. Turn it on in Settings → Privacy & Security → Photos → Grade."
    }
}

/// Adds the photo to the camera roll as a new item. Asks only for add-only access,
/// so the app never sees the rest of the library.
struct PhotoLibrarySaver: PhotoSaving {
    func save(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAuthorized }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}

/// Used in demo mode (UI tests): keeps saved photos in memory instead of touching the library.
actor DemoSaver: PhotoSaving {
    private(set) var saved: [Data] = []

    func save(_ data: Data) async throws {
        saved.append(data)
    }
}
