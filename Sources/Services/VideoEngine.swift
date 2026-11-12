import AVFoundation
import CoreImage
import CoreTransferable
import UniformTypeIdentifiers

struct ImportedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType:.movie) { video in SentTransferredFile(video.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at:received.file,to:destination)
            return ImportedVideo(url:destination)
        }
    }
}

final class VideoEngine {
    let pipeline = ImagePipeline()
    func composition(asset: AVAsset, settings: EditSettings) -> AVVideoComposition {
        AVVideoComposition(asset:asset) { [pipeline] request in
            // Photo-specific face effects are deliberately excluded from video.
            let source = request.sourceImage
            let output = pipeline.crop(pipeline.color(source,settings:settings),settings:settings)
            request.finish(with:output,context:pipeline.context)
        }
    }
    func export(url: URL, settings: EditSettings, progress: @escaping @Sendable (Float) -> Void) async throws -> URL {
        let asset = AVURLAsset(url:url)
        let tracks = try await asset.loadTracks(withMediaType:.video)
        guard !tracks.isEmpty else { throw ProcessingError(message:"В файле нет видеодорожки") }
        // AVVideoComposition filtering must preserve renderSize. Crop is handled by
        // fitting the cropped CI image into a matching explicit composition size.
        guard let session = AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetHighestQuality) else { throw ProcessingError(message:"Формат видео не поддерживается") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        session.outputURL = output; session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = try await makeComposition(asset:asset,settings:settings)
        let monitor = Task {
            while !Task.isCancelled { progress(session.progress); try? await Task.sleep(nanoseconds:200_000_000) }
        }
        defer { monitor.cancel() }
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
        },onCancel:{ session.cancelExport() })
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at:output)
            throw session.error ?? ProcessingError(message:"Экспорт видео отменён")
        }
        progress(1); return output
    }
    func makeComposition(asset: AVAsset, settings: EditSettings) async throws -> AVVideoComposition {
        guard let track = try await asset.loadTracks(withMediaType:.video).first else { throw ProcessingError(message:"Видеодорожка не найдена") }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin:.zero,size:natural).applying(transform)
        let oriented = CGSize(width:abs(rect.width),height:abs(rect.height))
        let blank = CIImage(color:.black).cropped(to:CGRect(origin:.zero,size:oriented))
        let cropped = pipeline.crop(blank,settings:settings).extent
        let width = max(2,Int(cropped.width)/2*2), height = max(2,Int(cropped.height)/2*2)
        let renderSize = CGSize(width:width,height:height)
        let composition = AVMutableVideoComposition(asset:asset) { [pipeline] request in
            let output = pipeline.crop(pipeline.color(request.sourceImage,settings:settings),settings:settings)
            let scaled = output.transformed(by:CGAffineTransform(scaleX:CGFloat(width)/output.extent.width,y:CGFloat(height)/output.extent.height))
            request.finish(with:scaled.cropped(to:CGRect(origin:.zero,size:renderSize)),context:pipeline.context)
        }
        composition.renderSize = renderSize
        return composition
    }
}
