import Foundation
import Photos
import UniformTypeIdentifiers

/// Somewhere to put a finished photo.
protocol PhotoSaving: Sendable {
    /// Adds the photo as a new item.
    func save(_ data: Data) async throws
    /// Saves the photo as an edit of an existing library photo. Photos keeps the original, so the
    /// edit can be reverted there.
    func replace(assetIdentifier: String, with data: Data, uniformType: String) async throws
}

enum SaveError: LocalizedError {
    case notAuthorized
    case editNotAuthorized
    case originalNotFound
    case originalNotEditable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Grade isn't allowed to add photos. Turn it on in Settings → Privacy & Security → Photos → Grade."
        case .editNotAuthorized:
            "To replace the original, Grade needs Full Access to your photos. Change it in Settings → Privacy & Security → Photos → Grade, or save as a new photo."
        case .originalNotFound:
            "The original photo couldn't be found. It may have been deleted, or isn't shared with Grade. Save as a new photo instead."
        case .originalNotEditable:
            "This photo can't be edited in place (for example, a shared or iCloud-only item). Save as a new photo instead."
        }
    }
}

/// Saves to the photo library. New photos only need add-only access; replacing an original asks
/// for read-write access the first time it's used.
struct PhotoLibrarySaver: PhotoSaving {
    static let adjustmentFormat = "com.jondoesflow.grade"

    func save(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAuthorized }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }

    func replace(assetIdentifier: String, with data: Data, uniformType: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw SaveError.editNotAuthorized }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject else {
            throw SaveError.originalNotFound
        }
        guard asset.canPerform(.content) else { throw SaveError.originalNotEditable }

        let input = try await contentEditingInput(for: asset)
        let output = PHContentEditingOutput(contentEditingInput: input)
        // Records that Grade made this edit; Photos shows "Edited" and offers Revert.
        output.adjustmentData = PHAdjustmentData(formatIdentifier: Self.adjustmentFormat, formatVersion: "1", data: Data("Grade".utf8))
        let type = UTType(uniformType) ?? .jpeg
        try data.write(to: try output.renderedContentURL(for: type), options: .atomic)

        // The change block runs once on Photos' own queue; the output isn't touched anywhere else.
        nonisolated(unsafe) let finishedOutput = output
        try await PHPhotoLibrary.shared().performChanges {
            guard let target = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject else { return }
            PHAssetChangeRequest(for: target).contentEditingOutput = finishedOutput
        }
    }

    /// Photos hands the input over once and doesn't keep using it, so passing it across is safe.
    private struct EditingInput: @unchecked Sendable {
        let value: PHContentEditingInput
    }

    private func contentEditingInput(for asset: PHAsset) async throws -> PHContentEditingInput {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        let input: EditingInput = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                if let input {
                    continuation.resume(returning: EditingInput(value: input))
                } else {
                    continuation.resume(throwing: SaveError.originalNotEditable)
                }
            }
        }
        return input.value
    }
}

/// Used in demo mode (UI tests): keeps saved photos in memory instead of touching the library.
actor DemoSaver: PhotoSaving {
    private(set) var saved: [Data] = []
    private(set) var replaced: [String: Data] = [:]

    func save(_ data: Data) async throws {
        saved.append(data)
    }

    func replace(assetIdentifier: String, with data: Data, uniformType: String) async throws {
        replaced[assetIdentifier] = data
    }
}
