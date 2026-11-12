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
    private let sessionLock = NSLock()
    private var currentExport: AVAssetExportSession?
    func cancelExport() { sessionLock.withLock { currentExport }?.cancelExport() }
    func export(url: URL, settings: EditSettings, progress: @escaping @Sendable (Float) -> Void) async throws -> URL {
        let asset = AVURLAsset(url:url)
        let tracks = try await asset.loadTracks(withMediaType:.video)
        guard !tracks.isEmpty else { throw ProcessingError(message:"В файле нет видеодорожки") }
        // AVVideoComposition filtering must preserve renderSize. Crop is handled by
        // fitting the cropped CI image into a matching explicit composition size.
        guard let session = AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetHighestQuality) else { throw ProcessingError(message:"Формат видео не поддерживается") }
        sessionLock.withLock { currentExport = session }
        defer { sessionLock.withLock { currentExport = nil } }
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
        let cap = settings.videoRetouch ? min(1,1280/max(cropped.width,cropped.height)) : 1
        let width = max(2,Int(cropped.width*cap)/2*2), height = max(2,Int(cropped.height*cap)/2*2)
        let renderSize = CGSize(width:width,height:height)
        let analyzer = VideoFaceAnalyzer()
        let composition = AVMutableVideoComposition(asset:asset) { [pipeline] request in
            do {
            var source = request.sourceImage
            if settings.videoRetouch {
                let scale = min(1,1280/max(source.extent.width,source.extent.height))
                source = source.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            }
            let faces = settings.videoRetouch ? try analyzer.faces(in:source) : []
            let output = settings.videoRetouch ? try pipeline.render(source,settings:settings,faces:faces) : pipeline.crop(pipeline.color(source,settings:settings),settings:settings)
            let scaled = output.transformed(by:CGAffineTransform(scaleX:CGFloat(width)/output.extent.width,y:CGFloat(height)/output.extent.height))
            request.finish(with:scaled.cropped(to:CGRect(origin:.zero,size:renderSize)),context:pipeline.context)
            } catch { request.finish(with:error) }
        }
        composition.renderSize = renderSize
        return composition
    }
}
