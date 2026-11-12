import SwiftUI
import PhotosUI
import AVKit
import AVFoundation

private enum ToolCategory: String, CaseIterable, Identifiable {
    case skin = "Кожа", face = "Лицо", makeup = "Макияж", filters = "Фильтры", light = "Свет", crop = "Кадр", video = "Видео"
    var id: String { rawValue }
    var icon: String {
        switch self { case .skin:return "sparkles"; case .face:return "face.smiling"; case .makeup:return "paintbrush.pointed"; case .filters:return "camera.filters"; case .light:return "sun.max"; case .crop:return "crop.rotate"; case .video:return "video" }
    }
    var needsFace: Bool { self == .skin || self == .face || self == .makeup }
}

struct EditorView: View {
    @StateObject private var model = EditorModel()
    @State private var selection: PhotosPickerItem?
    @State private var category: ToolCategory = .skin
    @State private var camera = false
    @State private var comparing = false
    @State private var showInfo = false
    @State private var confirmReset = false
    private let accent = Color(red:0.94,green:0.65,blue:0.79)
    private let background = Color(red:0.055,green:0.055,blue:0.075)

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing:0) {
                header
                preview(height:max(210,min(proxy.size.height*0.47,500)))
                if !model.message.isEmpty {
                    Text(model.message).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).padding(.vertical,8)
                        .accessibilityIdentifier("status")
                }
                if model.busy {
                    ProgressView(value:model.isVideo ? Double(model.progress) : nil).tint(accent).padding(.horizontal,20)
                }
                toolTabs
                ScrollView {
                    VStack(alignment:.leading,spacing:19) {
                        if !model.hasMedia { welcome }
                        else if category.needsFace && (model.isVideo || model.faceCount == 0) {
                            Label(model.isVideo ? "Ретушь лица доступна только для фото" : "Лицо не найдено",systemImage:"face.dashed").font(.headline)
                            Text("Выбери чёткую фотографию анфас без перекрытия лица. Для текущего файла доступны свет, фильтры и кадрирование.").font(.subheadline).foregroundStyle(.secondary)
                        } else { controls }
                    }.padding(20)
                }.scrollIndicators(.hidden)
                importBar
            }
            .background(background)
            .tint(accent)
            .disabled(model.busy)
            .overlay { if model.busy { Color.clear.allowsHitTesting(false) } }
        }
        .sheet(isPresented:$camera) {
            CameraPicker { image in
                camera = false
                if let data = image.jpegData(compressionQuality:0.98) { Task { await model.loadPhoto(data) } }
                else { model.message = "Не удалось прочитать снимок камеры" }
            } onCancel: { camera = false }.ignoresSafeArea()
        }
        .alert("Сбросить обработку?",isPresented:$confirmReset) {
            Button("Сбросить",role:.destructive) { model.reset() }
            Button("Отмена",role:.cancel) {}
        } message: { Text("Исходный файл сохранится. Сброс можно отменить стрелкой назад.") }
        .sheet(isPresented:$showInfo) { info }
        .onChange(of:selection) { _, item in
            guard let item else { return }
            Task {
                do {
                    if item.supportedContentTypes.contains(where:{ $0.conforms(to:.movie) }) {
                        guard let video = try await item.loadTransferable(type:ImportedVideo.self) else { throw ProcessingError(message:"Не удалось загрузить видео") }
                        await model.loadVideo(video.url); category = .video
                    } else {
                        guard let data = try await item.loadTransferable(type:Data.self) else { throw ProcessingError(message:"Не удалось загрузить фотографию") }
                        await model.loadPhoto(data); category = .skin
                    }
                } catch { model.message = error.localizedDescription }
                selection = nil
            }
        }
        .onChange(of:model.settings) { _, _ in model.scheduleRender() }
    }
    private var header: some View {
        HStack(spacing:14) {
            VStack(alignment:.leading,spacing:1) {
                Text("personaж").font(.system(size:28,weight:.bold,design:.rounded)).tracking(-1)
                Text("ТВОЯ ЛИЧНАЯ СТУДИЯ").font(.system(size:8,weight:.semibold)).tracking(2).foregroundStyle(accent)
            }
            Spacer()
            Button { model.undo() } label: { Image(systemName:"arrow.uturn.backward") }.disabled(model.history.undoStack.isEmpty).accessibilityLabel("Отменить")
            Button { model.redo() } label: { Image(systemName:"arrow.uturn.forward") }.disabled(model.history.redoStack.isEmpty).accessibilityLabel("Повторить")
            Button { showInfo = true } label: { Image(systemName:"info.circle") }.accessibilityLabel("О приложении")
        }.font(.system(size:19)).padding(.horizontal,20).padding(.vertical,12)
    }
    private func preview(height: CGFloat) -> some View {
        ZStack(alignment:.bottom) {
            RoundedRectangle(cornerRadius:26).fill(.white.opacity(0.035))
            if let player = model.player {
                VideoPlayer(player:player).clipShape(RoundedRectangle(cornerRadius:26))
            } else if let image = comparing ? model.original : model.preview {
                Image(uiImage:image).resizable().scaledToFit().padding(4)
                    .accessibilityIdentifier("photoPreview")
            } else {
                VStack(spacing:18) {
                    ZStack {
                        Circle().fill(LinearGradient(colors:[accent.opacity(0.2),.purple.opacity(0.1)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:135,height:135)
                        Image(systemName:"person.crop.rectangle").font(.system(size:56,weight:.ultraLight)).foregroundStyle(accent)
                    }
                    Text("Твоя красота. Твои правила.").font(.title3.weight(.medium))
                    Text("Фото и видео · Локально · Бесплатно").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.original != nil {
                HStack {
                    Label("\(model.faceCount)",systemImage:"face.smiling").font(.caption).padding(9).background(.ultraThinMaterial,in:Capsule())
                    Spacer()
                    Text(comparing ? "Оригинал" : "Удерживай: до / после")
                        .font(.caption.weight(.medium)).padding(10).background(.ultraThinMaterial,in:Capsule())
                        .gesture(DragGesture(minimumDistance:0).onChanged { _ in comparing = true }.onEnded { _ in comparing = false })
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { comparing.toggle() }
                }.padding(14)
            }
            if model.rendering { ProgressView().padding(14).background(.ultraThinMaterial,in:Capsule()).frame(maxHeight:.infinity,alignment:.top) }
        }.frame(height:height).clipShape(RoundedRectangle(cornerRadius:26)).padding(.horizontal,12)
    }
    private var toolTabs: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                ForEach(ToolCategory.allCases) { tool in
                    Button { withAnimation(.easeInOut(duration:0.18)) { category = tool } } label: {
                        VStack(spacing:6) {
                            Image(systemName:tool.icon).font(.system(size:20,weight:.regular))
                            Text(tool.rawValue).font(.caption2.weight(.medium))
                        }.frame(width:67,height:64)
                            .foregroundStyle(category == tool ? accent : .secondary)
                            .background(category == tool ? accent.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:16))
                    }.buttonStyle(.plain).accessibilityIdentifier("tab_\(tool.id)")
                }
            }.padding(.horizontal,16).padding(.vertical,8)
        }
    }
    private var welcome: some View {
        VStack(alignment:.leading,spacing:9) {
            Text("Начни с одного кадра").font(.title3.weight(.semibold))
            Text("Открой фото или видео из галереи либо сделай снимок. Исходник остаётся нетронутым.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var controls: some View {
        switch category {
        case .skin:
            title("Естественная текстура","Мягкая обработка по контуру лица с исключением глаз, бровей и губ.")
            slider("Разглаживание",\.smoothing)
            slider("Мелкие неровности",\.blemishes)
            slider("Уменьшение красноты",\.redness)
            slider("Тон кожи",\.skinTone,range:-1...1)
            slider("Свет под глазами",\.underEyes)
            slider("Смягчение морщин",\.wrinkles)
        case .face:
            title("Тонкая геометрия","Небольшие локальные изменения. Сильный профиль и перекрытые лица снижают точность.")
            slider("Ширина лица",\.faceWidth,range:-1...1)
            slider("Подбородок",\.chin,range:-1...1)
            slider("Скулы",\.cheeks,range:-1...1)
            slider("Ширина носа",\.nose,range:-1...1)
            slider("Размер глаз",\.eyes,range:-1...1)
            slider("Объём губ",\.lips,range:-1...1)
            slider("Изгиб бровей",\.browShape,range:-1...1)
        case .makeup:
            title("Твой оттенок","Макияж следует точкам лица и сохраняет фактуру.")
            HStack(spacing:18) {
                ForEach(0..<5) { index in
                    Button { model.change { $0.makeupColor = index } } label: {
                        Circle().fill([Color(red:0.72,green:0.13,blue:0.28),Color(red:0.65,green:0.26,blue:0.29),Color(red:0.54,green:0.15,blue:0.38),Color(red:0.85,green:0.35,blue:0.29),Color(red:0.45,green:0.25,blue:0.23)][index])
                            .frame(width:36,height:36).padding(4).overlay(Circle().stroke(model.settings.makeupColor == index ? accent : .clear,lineWidth:2))
                    }.accessibilityLabel(["Роза","Нюд","Слива","Коралл","Какао"][index])
                }
            }
            slider("Помада",\.lipstick); slider("Румяна",\.blush)
            slider("Тени",\.eyeshadow); slider("Подводка",\.eyeliner); slider("Брови",\.brows)
        case .filters:
            title("Настроение кадра","Восемь вариантов с регулируемой силой.")
            LazyVGrid(columns:[GridItem(.adaptive(minimum:95))],spacing:10) {
                ForEach(PhotoStyle.allCases) { style in
                    Button { model.change { $0.filter = style } } label: {
                        Text(style.rawValue).font(.caption.weight(.medium)).frame(maxWidth:.infinity).padding(.vertical,14)
                            .background(model.settings.filter == style ? accent.opacity(0.20) : .white.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
                    }
                }
            }
            slider("Сила фильтра",\.filterAmount)
        case .light:
            title("Свет и цвет","")
            colorSliders
        case .crop:
            title("Композиция","Сдвиг и масштаб задают область кадра. Сравнение показывает полный исходник.")
            HStack {
                Button { model.change { $0.quarterTurns += 1 } } label: { Label("90°",systemImage:"rotate.right") }.buttonStyle(.bordered)
                Picker("Пропорции",selection:Binding(get:{model.settings.aspect},set:{ value in model.change { $0.aspect = value } })) {
                    ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu)
            }
            slider("Выравнивание",\.straighten,range:-15...15,unit:"°",factor:1)
            slider("Масштаб",\.cropZoom,range:1...3,unit:"×",factor:1)
            slider("Сдвиг по горизонтали",\.cropX,range:-1...1)
            slider("Сдвиг по вертикали",\.cropY,range:-1...1)
        case .video:
            if model.isVideo {
                title("Видеостудия","Исходный звук сохраняется. Ретушь лица для видео недоступна.")
                Picker("Формат",selection:Binding(get:{model.settings.aspect},set:{ value in model.change { $0.aspect = value } })) {
                    ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
                }
                colorSliders
            } else { title("Открой видео из галереи","Цветокоррекция, фильтры, вертикальный кадр и экспорт со звуком.") }
        }
    }
    private var colorSliders: some View {
        Group {
            slider("Экспозиция",\.exposure,range:-2...2,unit:" EV",factor:1)
            slider("Яркость",\.brightness,range:-0.3...0.3)
            slider("Контраст",\.contrast,range:0.5...1.8)
            slider("Насыщенность",\.saturation,range:0...2)
            slider("Температура",\.warmth,range:-1...1)
            slider("Резкость",\.sharpness)
            slider("Света",\.highlights,range:0...1)
            slider("Тени",\.shadows,range:-1...1)
            slider("Виньетка",\.vignette)
        }
    }
    private func title(_ text: String, _ detail: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(text).font(.headline)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func slider(_ name: String,_ key: WritableKeyPath<EditSettings,Double>,range: ClosedRange<Double> = 0...1,unit: String = "%",factor: Double = 100) -> some View {
        VStack(spacing:6) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text(String(format:factor == 100 ? "%.0f%@" : "%.1f%@",model.settings[keyPath:key]*factor,unit)).font(.caption.monospacedDigit()).foregroundStyle(accent)
            }
            Slider(value:Binding(get:{model.settings[keyPath:key]},set:{model.settings[keyPath:key] = $0}),in:range,onEditingChanged:{ active in
                if active { model.beginEdit() } else { model.endEdit() }
            }).accessibilityLabel(name)
        }
    }
    private var importBar: some View {
        HStack(spacing:16) {
            PhotosPicker(selection:$selection,matching:.any(of:[.images,.videos]),photoLibrary:.shared()) {
                Image(systemName:"photo.on.rectangle.angled").font(.title3).frame(width:44,height:46)
            }.accessibilityLabel("Открыть фото или видео").accessibilityIdentifier("importMedia")
            Button { openCamera() } label: { Image(systemName:"camera").font(.title3).frame(width:40,height:46) }.accessibilityLabel("Камера")
            if model.hasMedia {
                Button { confirmReset = true } label: { Image(systemName:"arrow.counterclockwise").font(.title3) }.accessibilityLabel("Сбросить")
                Spacer(minLength:0)
                Button { Task { await model.save() } } label: {
                    Label("Сохранить",systemImage:"square.and.arrow.down").font(.subheadline.weight(.semibold)).padding(.horizontal,16).frame(height:46)
                        .foregroundStyle(.black).background(LinearGradient(colors:[accent,Color(red:0.73,green:0.61,blue:0.94)],startPoint:.leading,endPoint:.trailing),in:Capsule())
                }.accessibilityIdentifier("saveMedia")
            } else { Spacer(); Text("Без подписки").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal,18).padding(.vertical,10).background(.white.opacity(0.035))
    }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.message = "Камера недоступна на этом устройстве"; return }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for:.video)
            if granted { camera = true } else { model.message = "Разреши камеру: Настройки → personaж → Камера" }
        }
    }
    private var info: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("personaж").font(.largeTitle.bold())
                    Text("Локальный редактор фото и видео. Без учётной записи, подписок и водяных знаков.")
                    Text("Точность лица").font(.headline)
                    Text("Vision находит контуры лица. Маски кожи приблизительные: это не нейросетевая сегментация. Лучший результат — на чётких фронтальных портретах. Профиль, очки, волосы и несколько перекрывающихся лиц могут вызвать артефакты.")
                    Text("Ретушь").font(.headline)
                    Text("Разглаживание использует шумоподавление внутри маски лица. Мелкие неровности подавляются медианным фильтром; глубокие дефекты и морщины автоматически не восстанавливаются. Геометрия имеет ограниченную силу, но у границы лица возможны изменения фона.")
                    Text("Экспорт").font(.headline)
                    Text("Фото: JPEG, sRGB, длинная сторона до 4096 пикселей, без переноса GPS. Видео: MP4, исходный звук, цвет и кадрирование. Ретушь и макияж в видео не применяются. HDR-видео может быть преобразовано в SDR.")
                    Text("Конфиденциальность").font(.headline)
                    Text("Файлы обрабатываются на устройстве. Приложение не содержит сетевых сервисов, аналитики и рекламы. Импортированные видео временно копируются в песочницу приложения.")
                }.font(.subheadline).padding(24)
            }.toolbar { Button("Готово") { showInfo = false } }
        }.tint(accent)
    }
}
