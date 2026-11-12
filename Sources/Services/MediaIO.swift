import UIKit
import ImageIO
import Photos
import UniformTypeIdentifiers

struct MediaIO {
    static func decode(_ data: Data, maxDimension: Int) throws -> CIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:maxDimension,
                kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {
            throw ProcessingError(message:"Не удалось открыть фото. Выбери JPEG, HEIC или PNG.")
        }
        return CIImage(cgImage:cg)
    }
    static func authorizeSave() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for:.addOnly)
        guard status == .authorized || status == .limited else { throw ProcessingError(message:"Разреши сохранение в Фото: Настройки → personaж → Фото") }
    }
    static func savePhoto(_ image: CIImage, pipeline: ImagePipeline) async throws {
        try await authorizeSave()
        // No source EXIF/GPS copied into output.
        guard let data = pipeline.context.jpegRepresentation(of:image,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!,options:[CIImageRepresentationOption(rawValue:kCGImageDestinationLossyCompressionQuality as String):0.96]) else {
            throw ProcessingError(message:"Ошибка кодирования JPEG")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with:.photo,data:data,options:nil)
        }
    }
    static func saveVideo(_ url: URL) async throws {
        try await authorizeSave()
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:url) }
    }
}
