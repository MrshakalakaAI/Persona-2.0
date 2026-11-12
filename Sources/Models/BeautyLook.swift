import Foundation

enum BeautyLook: String, CaseIterable, Codable, Identifiable {
    case none = "Без образа", natural = "Естественный", fresh = "Свежесть", studio = "Студия", nude = "Нюд", evening = "Вечер", glow = "Сияние", sculpt = "Скульптура"
    case clean = "Чистая кожа", roseBeauty = "Розовый нюд", bronze = "Бронза", velvet = "Бархат", focus = "Акцент"
    var id: String { rawValue }
    var icon: String {
        switch self { case .none:return "circle.slash";case .natural:return "leaf";case .fresh:return "sun.haze";case .studio:return "camera.aperture";case .nude:return "drop";case .evening:return "moon.stars";case .glow:return "sparkles";case .sculpt:return "person.crop.circle";case .clean:return "drop.degreesign";case .roseBeauty:return "heart";case .bronze:return "sun.max";case .velvet:return "moon";case .focus:return "eye" }
    }
    var detail: String {
        switch self {
        case .none:return "Ручные настройки сохраняются. Выбери образ для ретуши в одно касание."
        case .natural:return "Мягкая кожа, ровный тон и свет под глазами. Без изменения формы лица."
        case .fresh:return "Светлый взгляд, меньше красноты и лёгкий румянец."
        case .studio:return "Ровная кожа, контраст глаз и немного более узкое лицо."
        case .nude:return "Спокойные губы, мягкие тени и подчёркнутые брови."
        case .evening:return "Выразительные губы, тени, подводка и сияние кожи."
        case .glow:return "Сияние кожи, свет под глазами и блеск губ."
        case .sculpt:return "Более узкое лицо, акцент на скулах и линии челюсти."
        case .clean:return "Только кожа: сглаживание, ровный тон и уменьшение красноты. Без макияжа и геометрии."
        case .roseBeauty:return "Розовые губы, заметный румянец и свежий взгляд."
        case .bronze:return "Тёплый оттенок кожи, губы какао и лёгкое сияние."
        case .velvet:return "Бархатная кожа, приглушённый макияж и тёмная линия ресниц."
        case .focus:return "Свет и контраст глаз, мягкая подводка и небольшой подъём области глаз."
        }
    }
    var recipe: EditSettings {
        var s = EditSettings()
        switch self {
        case .none: break
        case .natural: s.smoothing=0.8; s.blemishes=0.5; s.skinEvenness=0.5; s.skinGlow=0.45; s.redness=0.2; s.underEyes=0.55; s.eyeLight=0.3; s.eyeContrast=0.15; s.teethWhitening=0.4
        case .fresh: s.smoothing=0.55; s.underEyes=0.7; s.redness=0.3; s.blush=0.35; s.eyeLight=0.4; s.skinGlow=0.5; s.skinEvenness=0.25
        case .studio: s.smoothing=0.85; s.blemishes=0.65; s.skinEvenness=0.65; s.eyeContrast=0.35; s.teethWhitening=0.6; s.faceWidth=0.35; s.sharpness=0.08
        case .nude: s.smoothing=0.6; s.lipstick=0.5; s.blush=0.3; s.brows=0.3; s.eyeshadow=0.25; s.makeupColor=1; s.skinEvenness=0.35
        case .evening: s.smoothing=0.85; s.lipstick=0.9; s.eyeshadow=0.65; s.eyeliner=0.8; s.brows=0.45; s.blush=0.4; s.makeupColor=2; s.skinEvenness=0.55; s.skinGlow=0.45; s.underEyes=0.5; s.teethWhitening=0.3; s.eyeLight=0.2
        case .glow: s.smoothing=0.6; s.skinGlow=0.8; s.underEyes=0.5; s.blush=0.3; s.eyeLight=0.35; s.lipGloss=0.6
        case .clean: s.smoothing=0.8; s.blemishes=0.6; s.skinEvenness=0.6; s.redness=0.45; s.underEyes=0.4
        case .roseBeauty: s.smoothing=0.6; s.skinEvenness=0.35; s.lipstick=0.65; s.blush=0.65; s.eyeLight=0.3; s.makeupColor=0
        case .bronze: s.smoothing=0.55; s.skinTone=0.4; s.skinGlow=0.35; s.lipstick=0.6; s.blush=0.35; s.eyeshadow=0.35; s.makeupColor=4
        case .velvet: s.smoothing=0.9; s.skinEvenness=0.65; s.lipstick=0.7; s.brows=0.5; s.eyeliner=0.5; s.eyeshadow=0.5; s.makeupColor=1
        case .focus: s.smoothing=0.4; s.underEyes=0.6; s.eyeLight=0.6; s.eyeContrast=0.65; s.eyeSaturation=0.2; s.eyeliner=0.4; s.brows=0.35; s.eyeLift=0.2
        case .sculpt: s.faceWidth=0.65; s.cheeks=0.5; s.jaw=0.65; s.chin=0.25; s.smoothing=0.45; s.eyeContrast=0.3
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
        let keys: [WritableKeyPath<EditSettings,Double>] = [\.smoothing,\.blemishes,\.redness,\.underEyes,\.eyeLight,\.teethWhitening,\.blush,\.skinGlow,\.skinEvenness,\.eyeContrast,\.faceWidth,\.sharpness,\.lipstick,\.brows,\.eyeshadow,\.eyeliner,\.lipGloss,\.cheeks,\.jaw,\.chin,\.skinTone,\.eyeSaturation,\.eyeLift]
        for key in keys { result[keyPath:key] = min(1,max(-1,result[keyPath:key]+recipe[keyPath:key]*beautyAmount)) }
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
