import Foundation

enum BeautyLook: String, CaseIterable, Codable, Identifiable {
    case none = "Без образа", natural = "Естественный", fresh = "Свежесть", studio = "Студия", nude = "Нюд", evening = "Вечер", glow = "Сияние", sculpt = "Скульптура"
    var id: String { rawValue }
    var icon: String {
        switch self { case .none:return "circle.slash";case .natural:return "leaf";case .fresh:return "sun.haze";case .studio:return "camera.aperture";case .nude:return "drop";case .evening:return "moon.stars";case .glow:return "sparkles";case .sculpt:return "person.crop.circle" }
    }
    var recipe: EditSettings {
        var s = EditSettings()
        switch self {
        case .none: break
        case .natural: s.smoothing=0.25; s.blemishes=0.15; s.redness=0.1; s.underEyes=0.25; s.eyeLight=0.15; s.teethWhitening=0.2
        case .fresh: s.smoothing=0.3; s.underEyes=0.5; s.redness=0.2; s.blush=0.22; s.eyeLight=0.3; s.skinGlow=0.2
        case .studio: s.smoothing=0.4; s.blemishes=0.3; s.skinEvenness=0.3; s.eyeContrast=0.2; s.teethWhitening=0.4; s.faceWidth=0.15; s.sharpness=0.12
        case .nude: s.smoothing=0.3; s.lipstick=0.25; s.blush=0.15; s.brows=0.18; s.eyeshadow=0.12; s.makeupColor=1; s.skinEvenness=0.2
        case .evening: s.smoothing=0.4; s.lipstick=0.65; s.eyeshadow=0.45; s.eyeliner=0.6; s.brows=0.35; s.blush=0.25; s.makeupColor=2
        case .glow: s.smoothing=0.25; s.skinGlow=0.5; s.underEyes=0.3; s.blush=0.18; s.eyeLight=0.25; s.lipGloss=0.3
        case .sculpt: s.faceWidth=0.3; s.cheeks=0.25; s.jaw=0.3; s.chin=0.1; s.smoothing=0.2; s.eyeContrast=0.15
        }
        return s
    }
}

extension EditSettings {
    /// Independent local recipes. These are not Persona's proprietary neural masks.
    func effective() -> EditSettings {
        guard beautyLook != .none, beautyAmount > 0 else { return self }
        var result = self
        let recipe = beautyLook.recipe
        let keys: [WritableKeyPath<EditSettings,Double>] = [\.smoothing,\.blemishes,\.redness,\.underEyes,\.eyeLight,\.teethWhitening,\.blush,\.skinGlow,\.skinEvenness,\.eyeContrast,\.faceWidth,\.sharpness,\.lipstick,\.brows,\.eyeshadow,\.eyeliner,\.lipGloss,\.cheeks,\.jaw,\.chin]
        for key in keys { result[keyPath:key] = min(1,max(-1,result[keyPath:key]+recipe[keyPath:key]*beautyAmount)) }
        if beautyLook == .nude || beautyLook == .evening { result.makeupColor = recipe.makeupColor }
        result.beautyLook = .none
        return result
    }
}

enum BrushMode: String, CaseIterable, Codable, Identifiable {
    case heal = "Убрать пятно", smooth = "Сгладить", lighten = "Осветлить", darken = "Затемнить"
    var id: String { rawValue }
}
struct RetouchDab: Equatable, Codable {
    var x: Double
    var y: Double
    var radius: Double
    var strength: Double
    var mode: BrushMode
}
