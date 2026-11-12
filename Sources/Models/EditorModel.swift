import SwiftUI
import PhotosUI
import AVFoundation

actor PhotoWorker {
    let pipeline = ImagePipeline()
    private var data: Data?
    private var source: CIImage?
    private var faces: [FaceGeometry] = []
    func load(_ data: Data) throws -> (UIImage,[CGRect]) {
        let image = try MediaIO.decode(data,maxDimension:1280)
        let detected = try FaceAnalyzer().detect(in:image)
        self.data = data; source = image; faces = detected
        return (try pipeline.bitmap(image),detected.map { CGRect(x:$0.bounds.minX/image.extent.width,y:$0.bounds.minY/image.extent.height,width:$0.bounds.width/image.extent.width,height:$0.bounds.height/image.extent.height) })
    }
    func clear() { data = nil; source = nil; faces = [] }
    func render(_ settings: EditSettings) throws -> UIImage? {
        guard let source else { return nil }
        return try autoreleasepool { try pipeline.bitmap(pipeline.render(source,settings:settings,faces:faces)) }
    }
    func save(_ settings: EditSettings) async throws {
        guard let data else { return }
        let output: CIImage = try autoreleasepool {
            let image = try MediaIO.decode(data,maxDimension:4096)
            let faces = try FaceAnalyzer().detect(in:image)
            return try pipeline.render(image,settings:settings,faces:faces)
        }
        try await MediaIO.savePhoto(output,pipeline:pipeline)
    }
}

@MainActor final class EditorModel: ObservableObject {
    @Published var settings = EditSettings()
    @Published var original: UIImage?
    @Published var preview: UIImage?
    @Published var lookThumbnails: [BeautyLook:UIImage] = [:]
    @Published var styleThumbnails: [PhotoStyle:UIImage] = [:]
    @Published var thumbnailsLoading = false
    @Published var faceCount = 0
    @Published var faceRects: [CGRect] = []
    @Published var busy = false
    @Published var rendering = false
    @Published var message = ""
    @Published var player: AVPlayer?
    @Published var videoURL: URL?
    @Published var progress: Float = 0
    @Published private(set) var history = EditHistory()
    private var gestureStart: EditSettings?
    private let photo = PhotoWorker()
    private let video = VideoEngine()
    private var renderTask: Task<Void,Never>?
    private var thumbnailTask: Task<Void,Never>?
    private var thumbnailGeneration = UUID()
    var isVideo: Bool { videoURL != nil }
    var hasMedia: Bool { original != nil || isVideo }

    func beginEdit() { gestureStart = settings }
    func endEdit() {
        if let old = gestureStart, old != settings { history.record(old) }
        gestureStart = nil
    }
    func change(_ edit: (inout EditSettings) -> Void) {
        let old = settings; edit(&settings)
        if old != settings { history.record(old) }
    }
    func undo() { if let s = history.undo(settings) { settings = s } }
    func redo() { if let s = history.redo(settings) { settings = s } }
    func reset() { change { $0 = EditSettings() } }

    func loadPhoto(_ data: Data) async {
        guard !busy else { return }
        busy = true; message = "Анализ фотографии…"; renderTask?.cancel()
        defer { busy = false }
        do {
            let (image,rects) = try await photo.load(data)
            let count = rects.count
            clearVideo(); original = image; preview = image; faceCount = count; faceRects = rects
            settings = EditSettings(); history = EditHistory()
            makeThumbnails(data)
            message = count == 0 ? "Лицо не найдено. Доступны фильтры, свет и кадрирование." : "Лиц найдено: \(count). Обработка выполняется на iPhone."
        } catch { message = error.localizedDescription }
    }
    func loadVideo(_ url: URL) async {
        guard !busy else { try? FileManager.default.removeItem(at:url); return }
        busy = true; renderTask?.cancel()
        defer { busy = false }
        do {
            let asset = AVURLAsset(url:url)
            guard !(try await asset.loadTracks(withMediaType:.video)).isEmpty else { throw ProcessingError(message:"Не удалось прочитать видео") }
            thumbnailTask?.cancel(); thumbnailGeneration = UUID(); lookThumbnails = [:]; styleThumbnails = [:]; thumbnailsLoading = false
            await photo.clear()
            clearVideo(); original = nil; preview = nil; faceCount = 0; faceRects = []
            settings = EditSettings(); history = EditHistory(); videoURL = url
            player = AVPlayer(playerItem:AVPlayerItem(asset:asset))
            message = "Видео: цвет и кадрирование. Для обработки лица включи «Ретушь видео»; экспорт до 1280 px."
        } catch { try? FileManager.default.removeItem(at:url); message = error.localizedDescription }
    }
    private func makeThumbnails(_ data: Data) {
        thumbnailTask?.cancel()
        let generation = UUID(); thumbnailGeneration = generation
        lookThumbnails = [:]; styleThumbnails = [:]; thumbnailsLoading = true
        thumbnailTask = Task { [weak self] in
            do {
                let result = try await ThumbnailWorker().generate(data)
                try Task.checkCancellation()
                guard let self, self.thumbnailGeneration == generation else { return }
                self.lookThumbnails = result.0; self.styleThumbnails = result.1; self.thumbnailsLoading = false
            } catch {
                guard let self, self.thumbnailGeneration == generation else { return }
                self.thumbnailsLoading = false
            }
        }
    }
    private func clearVideo() {
        player?.pause(); player = nil
        if let videoURL { try? FileManager.default.removeItem(at:videoURL) }
        videoURL = nil
    }
    func cancelExport() { video.cancelExport() }
    func scheduleRender() {
        renderTask?.cancel()
        guard hasMedia, !busy else { return }
        let snapshot = settings
        renderTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds:100_000_000)
                guard let self else { return }
                self.rendering = true
                defer { self.rendering = false }
                if let url = self.videoURL {
                    let time = self.player?.currentTime() ?? .zero
                    let item = AVPlayerItem(url:url)
                    item.videoComposition = try await self.video.makeComposition(asset:AVURLAsset(url:url),settings:snapshot)
                    try Task.checkCancellation()
                    self.player?.replaceCurrentItem(with:item)
                    await self.player?.seek(to:time,toleranceBefore:.zero,toleranceAfter:.zero)
                } else {
                    let result = try await self.photo.render(snapshot)
                    try Task.checkCancellation()
                    self.preview = result
                    if snapshot.beautyLook != .none {
                        self.message = "Применён образ «\(snapshot.beautyLook.rawValue)» · \(Int(snapshot.beautyAmount*100))% · Лиц: \(self.faceCount)"
                    } else if snapshot.filter != .natural {
                        self.message = "Применён фильтр «\(snapshot.filter.title)» · \(Int(snapshot.filterAmount*100))%"
                    } else {
                        self.message = "Обработка обновлена · Лиц: \(self.faceCount)"
                    }
                }
            } catch is CancellationError {} catch { self?.message = error.localizedDescription }
        }
    }
    func addDab(unit: CGPoint, radius: Double, strength: Double, mode: BrushMode) {
        guard let original, settings.dabs.count < 80 else { return }
        let size = original.size
        let plan = CropPlan.make(extent:CGRect(origin:.zero,size:size),settings:settings)
        let source = plan.sourcePoint(displayUnit:unit,source:size)
        let outputRadius = radius*Double(min(plan.output.width,plan.output.height))/Double(min(size.width,size.height))
        settings.dabs.append(RetouchDab(x:Double(source.x),y:Double(source.y),radius:outputRadius,strength:strength,mode:mode))
    }
    func save() async {
        guard hasMedia, !busy else { return }
        busy = true; progress = 0; renderTask?.cancel(); player?.pause()
        let snapshot = settings
        defer { busy = false }
        do {
            if let url = videoURL {
                message = "Экспорт видео…"
                let output = try await video.export(url:url,settings:snapshot) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                defer { try? FileManager.default.removeItem(at:output) }
                try await MediaIO.saveVideo(output)
                message = "Видео сохранено в Фото с исходным звуком (если он был)."
            } else {
                message = "Сохранение фотографии…"
                try await photo.save(snapshot)
                message = "Фотография сохранена в Фото. Без водяного знака."
            }
        } catch { message = error.localizedDescription }
    }
}
