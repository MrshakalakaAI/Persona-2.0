import Foundation

struct EditSettings: Equatable, Codable {
    var videoRetouch = false
    var beautyLook: BeautyLook = .none
    var beautyAmount = 0.7
    var selectedFace: Int? = nil
    var texture = 0.65
    var skinEvenness = 0.0
    var skinGlow = 0.0
    var teethWhitening = 0.0
    var eyeLight = 0.0
    var eyeContrast = 0.0
    var eyeSaturation = 0.0
    var eyeWidth = 0.0
    var eyeHeight = 0.0
    var eyeDistance = 0.0
    var eyeLift = 0.0
    var irisSize = 0.0
    var noseLength = 0.0
    var noseTip = 0.0
    var noseBridge = 0.0
    var lipsWidth = 0.0
    var lipsPosition = 0.0
    var smile = 0.0
    var lipGloss = 0.0
    var jaw = 0.0
    var forehead = 0.0
    var faceHeight = 0.0
    var browDistance = 0.0
    var browTilt = 0.0
    var dabs: [RetouchDab] = []
    var exposure = 0.0
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var warmth = 0.0
    var sharpness = 0.0
    var noiseReduction = 0.0
    var highlights = 1.0
    var shadows = 0.0
    var vignette = 0.0
    var smoothing = 0.0
    var blemishes = 0.0
    var redness = 0.0
    var skinTone = 0.0
    var underEyes = 0.0
    var wrinkles = 0.0
    var faceWidth = 0.0
    var chin = 0.0
    var cheeks = 0.0
    var nose = 0.0
    var eyes = 0.0
    var lips = 0.0
    var browShape = 0.0
    var lipstick = 0.0
    var blush = 0.0
    var eyeshadow = 0.0
    var eyeliner = 0.0
    var brows = 0.0
    var makeupColor = 0
    var filter: PhotoStyle = .natural
    var filterAmount = 1.0
    var quarterTurns = 0
    var straighten = 0.0
    var aspect: CropAspect = .original
    var cropZoom = 1.0
    var cropX = 0.0
    var cropY = 0.0
}

enum PhotoStyle: String, CaseIterable, Codable, Identifiable {
    case natural = "Natural", portrait = "Portrait", softBeauty = "Soft Beauty"
    case cinematic = "Cinematic", vintage = "Vintage", warm = "Warm", cold = "Cold", monochrome = "Black & White"
    var id: String { rawValue }
}

enum CropAspect: String, CaseIterable, Codable, Identifiable {
    case original = "Оригинал", square = "1:1", portrait = "4:5", story = "9:16", wide = "16:9"
    var id: String { rawValue }
    var ratio: Double? {
        switch self { case .original: return nil; case .square: return 1; case .portrait: return 0.8; case .story: return 9.0/16; case .wide: return 16.0/9 }
    }
}

struct EditHistory {
    private(set) var undoStack: [EditSettings] = []
    private(set) var redoStack: [EditSettings] = []
    mutating func record(_ old: EditSettings) {
        undoStack.append(old)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    mutating func undo(_ current: EditSettings) -> EditSettings? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current); return previous
    }
    mutating func redo(_ current: EditSettings) -> EditSettings? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current); return next
    }
}
