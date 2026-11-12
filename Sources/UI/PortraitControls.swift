import SwiftUI

struct AdjustmentTool: Identifiable {
    let name: String
    let key: WritableKeyPath<EditSettings,Double>
    var range: ClosedRange<Double> = 0...1
    var id: String { name }
    static func signed(_ name: String,_ key: WritableKeyPath<EditSettings,Double>) -> AdjustmentTool { AdjustmentTool(name:name,key:key,range:-1...1) }
    static func tools(_ group: String) -> [AdjustmentTool] {
        switch group {
        case "Кожа": return [AdjustmentTool(name:"Гладкость",key:\.smoothing),AdjustmentTool(name:"Текстура",key:\.texture),AdjustmentTool(name:"Мелкие неровности",key:\.blemishes),AdjustmentTool(name:"Ровный тон",key:\.skinEvenness),AdjustmentTool(name:"Краснота",key:\.redness),.signed("Тон кожи",\.skinTone),AdjustmentTool(name:"Сияние",key:\.skinGlow),AdjustmentTool(name:"Под глазами",key:\.underEyes),AdjustmentTool(name:"Линии лба",key:\.wrinkles)]
        case "Лицо": return [.signed("Ширина лица",\.faceWidth),.signed("Высота лица",\.faceHeight),.signed("Подбородок",\.chin),.signed("Линия челюсти",\.jaw),.signed("Скулы",\.cheeks),.signed("Лоб",\.forehead),.signed("Изгиб бровей",\.browShape),.signed("Расстояние бровей",\.browDistance),.signed("Наклон бровей",\.browTilt)]
        case "Глаза": return [.signed("Размер глаз",\.eyes),.signed("Ширина глаз",\.eyeWidth),.signed("Высота глаз",\.eyeHeight),.signed("Расстояние глаз",\.eyeDistance),.signed("Подъём глаз",\.eyeLift),.signed("Радужка",\.irisSize),AdjustmentTool(name:"Свет глаз",key:\.eyeLight),AdjustmentTool(name:"Контраст глаз",key:\.eyeContrast),.signed("Насыщенность глаз",\.eyeSaturation)]
        case "Нос": return [.signed("Ширина носа",\.nose),.signed("Длина носа",\.noseLength),.signed("Переносица",\.noseBridge),.signed("Кончик носа",\.noseTip)]
        case "Улыбка": return [AdjustmentTool(name:"Отбеливание зубов",key:\.teethWhitening),.signed("Улыбка",\.smile),.signed("Объём губ",\.lips),.signed("Ширина губ",\.lipsWidth),.signed("Положение губ",\.lipsPosition),AdjustmentTool(name:"Блеск губ",key:\.lipGloss)]
        case "Макияж": return [AdjustmentTool(name:"Помада",key:\.lipstick),AdjustmentTool(name:"Румяна",key:\.blush),AdjustmentTool(name:"Тени",key:\.eyeshadow),AdjustmentTool(name:"Подводка",key:\.eyeliner),AdjustmentTool(name:"Брови",key:\.brows)]
        default: return []
        }
    }
}

struct PortraitControls: View {
    @ObservedObject var model: EditorModel
    let group: String
    @State private var selected = ""
    private var tools: [AdjustmentTool] { AdjustmentTool.tools(group) }
    private var current: AdjustmentTool? { tools.first(where:{$0.id == selected}) ?? tools.first }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(group).font(.headline)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:100))],spacing:9) {
                ForEach(tools) { tool in
                    Button { selected = tool.id } label: {
                        Text(tool.name).font(.caption.weight(.medium)).frame(maxWidth:.infinity,minHeight:42)
                            .background(current?.id == tool.id ? Color.pink.opacity(0.16) : .white.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
                    }.accessibilityIdentifier("tool_\(tool.id)")
                }
            }
            if let tool = current {
                HStack {
                    Text(tool.name).font(.subheadline)
                    Spacer()
                    Text(String(format:"%.0f%%",model.settings[keyPath:tool.key]*100)).font(.caption.monospacedDigit())
                    Button { model.change { $0[keyPath:tool.key] = EditSettings()[keyPath:tool.key] } } label: { Image(systemName:"arrow.counterclockwise") }.accessibilityLabel("Сбросить \(tool.name)")
                }
                Slider(value:Binding(get:{model.settings[keyPath:tool.key]},set:{model.settings[keyPath:tool.key] = $0}),in:tool.range,onEditingChanged:{ active in if active { model.beginEdit() } else { model.endEdit() } }).accessibilityLabel(tool.name)
            }
            if group == "Улыбка" { Text("Зубы осветляются только внутри открытого рта и по маске светлых пикселей.").font(.caption).foregroundStyle(.secondary) }
            if group == "Кожа" { Text("Гладкость с сохранением высокочастотной текстуры. Для отдельного пятна используй «Кисть».").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct BeautyLooksPanel: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Красота в одно касание").font(.headline)
            Text("Локальные образы: кожа, взгляд, губы и мягкая геометрия. Настройки можно дополнить вручную.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:110))],spacing:10) {
                ForEach(BeautyLook.allCases) { look in
                    Button { model.change { $0.beautyLook = look } } label: {
                        VStack(spacing:8) {
                            Image(systemName:look.icon).font(.title2)
                            Text(look.rawValue).font(.caption.weight(.medium))
                        }.frame(maxWidth:.infinity,minHeight:76)
                            .background(model.settings.beautyLook == look ? Color.pink.opacity(0.2) : .white.opacity(0.05),in:RoundedRectangle(cornerRadius:16))
                    }.accessibilityIdentifier("look_\(look.id)")
                }
            }
            HStack { Text("Сила образа"); Spacer(); Text(String(format:"%.0f%%",model.settings.beautyAmount*100)).monospacedDigit() }.font(.subheadline)
            Slider(value:$model.settings.beautyAmount,in:0...1,onEditingChanged:{ active in if active { model.beginEdit() } else { model.endEdit() } }).accessibilityLabel("Сила образа")
        }
    }
}
