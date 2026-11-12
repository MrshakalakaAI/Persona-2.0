import SwiftUI
import PhotosUI
import AVFoundation

actor PhotoWorker {
    let pipeline = ImagePipeline()
    private var data: Data?
    private var source: CIImage?
    private var faces: [FaceGeometry] = []
    func load(_ data: Data) throws -> (UIImage,Int) {
        let image = try MediaIO.decode(data,maxDimension:1280)
        let detected = try FaceAnalyzer().detect(in:image)
        self.data = data; source = image; faces = detected
        return (try pipeline.bitmap(image),detected.count)
    }
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
    @Published var faceCount = 0
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
    private var importID = UUID()
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
            let (image,count) = try await photo.load(data)
            clearVideo(); original = image; preview = image; faceCount = count
            settings = EditSettings(); history = EditHistory()
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
            clearVideo(); original = nil; preview = nil; faceCount = 0
            settings = EditSettings(); history = EditHistory(); videoURL = url
            player = AVPlayer(playerItem:AVPlayerItem(asset:asset))
            message = "Видео: цвет, фильтры и кадрирование. Ретушь лица для видео пока недоступна."
        } catch { try? FileManager.default.removeItem(at:url); message = error.localizedDescription }
    }
    private func clearVideo() {
        player?.pause(); player = nil
        if let videoURL { try? FileManager.default.removeItem(at:videoURL) }
        videoURL = nil
    }
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
                }
            } catch is CancellationError {} catch { self?.message = error.localizedDescription }
        }
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
