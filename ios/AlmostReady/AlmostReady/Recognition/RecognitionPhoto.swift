import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct RecognitionPhoto: Sendable, Transferable {
    nonisolated enum InvalidImage: Error, Equatable {
        case unsupported, tooLarge
    }

    static let maxBytes = 10 * 1_024 * 1_024
    private static let maxPixels = 25_000_000

    let data: Data
    let contentType: String
    let fileName: String

    init(data: Data, convertHEIF: Bool = false) throws {
        guard data.count <= Self.maxBytes else { throw InvalidImage.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source),
            let type = UTType(identifier as String),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw InvalidImage.unsupported }

        guard width <= Self.maxPixels / height else { throw InvalidImage.tooLarge }
        if convertHEIF && (type == .heic || type == .heif) {
            // A native iPhone library photo may still arrive as HEIF despite the compatible picker encoding.
            try self.init(data: Self.makeJPEG(from: source, maxDimension: max(width, height)))
            return
        }

        let fileName: String
        let contentType: String
        switch type {
        case .jpeg:
            fileName = "photo.jpg"
            contentType = "image/jpeg"
        case .png:
            fileName = "photo.png"
            contentType = "image/png"
        default:
            throw InvalidImage.unsupported
        }
        guard CGImageSourceGetStatus(source) == .statusComplete,
            CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                != nil
        else { throw InvalidImage.unsupported }

        self.init(data: data, contentType: contentType, fileName: fileName)
    }

    private init(data: Data, contentType: String, fileName: String) {
        self.data = data
        self.contentType = contentType
        self.fileName = fileName
    }

    private static func makeJPEG(from source: CGImageSource, maxDimension: Int) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let output = CFDataCreateMutable(nil, 0),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw InvalidImage.unsupported }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw InvalidImage.unsupported }
        return output as Data
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: true) { received in
            // The picker owns the temporary file. Read it inside the transfer callback without copying it to disk.
            let file = try FileHandle(forReadingFrom: received.file)
            defer { try? file.close() }
            let data = try file.read(upToCount: maxBytes + 1) ?? Data()
            return try RecognitionPhoto(data: data, convertHEIF: true)
        }
    }
}
