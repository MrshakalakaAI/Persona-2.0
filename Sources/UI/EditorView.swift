import SwiftUI
import PhotosUI
import AVKit
import AVFoundation

private enum ToolCategory: String, CaseIterable, Identifiable {
    case beauty = "Красота", skin = "Кожа", face = "Лицо", eyes = "Глаза", nose = "Нос", mouth = "Улыбка", makeup = "Макияж", brush = "Кисть", filters = "Фильтры", light = "Свет", crop = "Кадр", video = "Видео"
    var id: String { rawValue }
    var icon: String {
        switch self { case .beauty:return "wand.and.stars";case .eyes:return "eye";case .nose:return "triangle";case .mouth:return "mouth";case .brush:return "bandage";case .skin:return "sparkles"; case .face:return "face.smiling"; case .makeup:return "paintbrush.pointed"; case .filters:return "camera.filters"; case .light:return "sun.max"; case .crop:return "crop.rotate"; case .video:return "video" }
    }
    var needsFace: Bool { [ToolCategory.beauty,.skin,.face,.eyes,.nose,.mouth,.makeup].contains(self) }
}

struct EditorView: View {
    @StateObject private var model = EditorModel()
    @State private var selection: PhotosPickerItem?
    @State private var category: ToolCategory = .beauty
    @State private var brushMode: BrushMode = .heal
    @State private var brushRadius = 0.035
    @State private var brushStrength = 1.0
    @State private var painting = false
    @State private var lastBrushPoint: CGPoint?
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
                        else if category.needsFace && (model.isVideo ? !model.settings.videoRetouch : model.faceCount == 0) {
                            Label(model.isVideo ? "Включи ретушь видео" : "Лицо не найдено",systemImage:"face.dashed").font(.headline)
                            Text(model.isVideo ? "В разделе «Видео» включи ретушь. Обработка каждого кадра выполняется на устройстве; экспорт ограничен 1280 px." : "Выбери чёткую фотографию анфас без перекрытия лица. Для текущего файла доступны свет, фильтры и кадрирование.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            if model.faceCount > 1 && category.needsFace {
                                Picker("Лицо слева направо",selection:Binding(get:{model.settings.selectedFace ?? -1},set:{ index in model.change { $0.selectedFace = index < 0 ? nil : index } })) {
                                    Text("Все лица").tag(-1)
                                    ForEach(0..<model.faceCount,id:\.self) { Text("Лицо \($0+1)").tag($0) }
                                }.pickerStyle(.menu)
                            }
                            controls
                        }
                    }.padding(20)
                }.scrollIndicators(.hidden).accessibilityIdentifier("editorTools")
                importBar
            }
            .background(background)
            .tint(accent)
            .disabled(model.busy)
            .overlay(alignment:.top) {
                if model.busy && model.isVideo {
                    Button("Отменить экспорт") { model.cancelExport() }.buttonStyle(.borderedProminent).padding(.top,60)
                }
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-photo") {
                await model.loadPhoto(DebugFixture.photo())
            }
            #endif
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
                        await model.loadPhoto(data); category = .beauty
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
                GeometryReader { proxy in
                    let scale = min(proxy.size.width/image.size.width,proxy.size.height/image.size.height)
                    let width = image.size.width*scale, height = image.size.height*scale
                    ZStack {
                        Image(uiImage:image).resizable().scaledToFit()
                            .accessibilityIdentifier("photoPreview").accessibilityLabel("Предпросмотр фотографии")
                        if category == .brush && !comparing {
                            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                                let unit = CGPoint(x:min(1,max(0,value.location.x/width)),y:min(1,max(0,value.location.y/height)))
                                if !painting { model.beginEdit(); painting = true; lastBrushPoint = nil }
                                if let last = lastBrushPoint, hypot(unit.x-last.x,unit.y-last.y) < brushRadius*0.45 { return }
                                model.addDab(unit:unit,radius:brushRadius,strength:brushStrength,mode:brushMode)
                                lastBrushPoint = unit
                            }.onEnded { _ in model.endEdit(); painting = false; lastBrushPoint = nil })
                        }
                    }.frame(width:width,height:height).position(x:proxy.size.width/2,y:proxy.size.height/2)
                }.padding(4)
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
        }.accessibilityIdentifier("toolTabs")
    }
    private var welcome: some View {
        VStack(alignment:.leading,spacing:9) {
            Text("Начни с одного кадра").font(.title3.weight(.semibold))
            Text("Открой фото или видео из галереи либо сделай снимок. Исходник остаётся нетронутым.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var controls: some View {
        switch category {
        case .beauty:
            BeautyLooksPanel(model:model)
        case .skin,.face,.eyes,.nose,.mouth:
            PortraitControls(model:model,group:category.rawValue).id(category)
        case .makeup:
            HStack(spacing:18) {
                ForEach(0..<5) { index in
                    Button { model.change { $0.makeupColor = index } } label: {
                        Circle().fill([Color(red:0.72,green:0.13,blue:0.28),Color(red:0.65,green:0.26,blue:0.29),Color(red:0.54,green:0.15,blue:0.38),Color(red:0.85,green:0.35,blue:0.29),Color(red:0.45,green:0.25,blue:0.23)][index])
                            .frame(width:32,height:32).padding(4).overlay(Circle().stroke(model.settings.makeupColor == index ? accent : .clear,lineWidth:2))
                    }.accessibilityLabel(["Роза","Нюд","Слива","Коралл","Какао"][index])
                }
            }
            PortraitControls(model:model,group:category.rawValue)
        case .brush:
            if model.isVideo { title("Кисти доступны для фото", "Рисуй по изображению после выбора инструмента.") }
            else {
                title("Точечная ретушь", "Проведи по фото. «Убрать пятно» переносит соседнюю текстуру с мягкими краями. До 80 точек; один жест — один шаг отмены.")
                Picker("Кисть",selection:$brushMode) { ForEach(BrushMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                HStack { Text("Размер"); Slider(value:$brushRadius,in:0.01...0.1); Text(String(format:"%.0f",brushRadius*100)) }
                HStack { Text("Сила"); Slider(value:$brushStrength,in:0.1...1); Text(String(format:"%.0f%%",brushStrength*100)) }
                Button("Очистить точки (\(model.settings.dabs.count)/80)") { model.change { $0.dabs = [] } }.disabled(model.settings.dabs.isEmpty)
            }
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
                title("Видеостудия","Исходный звук сохраняется. Обработка лица выполняется покадрово, не в реальном времени. При ретуши экспорт до 1280 px; возможны колебания точек лица.")
                Toggle("Ретушь видео",isOn:Binding(get:{model.settings.videoRetouch},set:{ value in model.change { $0.videoRetouch = value } }))
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
            slider("Шумоподавление кадра",\.noiseReduction)
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
            } else { Spacer(); Button("Пример") { Task { if let url = Bundle.main.url(forResource:"DemoPortrait",withExtension:"jpg"), let data = try? Data(contentsOf:url) { await model.loadPhoto(data) } } }.font(.caption) }
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
                    Text("Фото: JPEG sRGB до 4096 px, без GPS. Видео: MP4 с исходным звуком. Покадровая ретушь включается отдельно, ограничивает экспорт 1280 px и может быть медленной. Точки лица могут колебаться. HDR может перейти в SDR. Пример: фотография Eileen Collins, NASA / scikit-image, public domain; используется для демонстрации, без одобрения приложения изображённым человеком.")
                    Text("Конфиденциальность").font(.headline)
                    Text("Файлы обрабатываются на устройстве. Приложение не содержит сетевых сервисов, аналитики и рекламы. Импортированные видео временно копируются в песочницу приложения.")
                }.font(.subheadline).padding(24)
            }.toolbar { Button("Готово") { showInfo = false } }
        }.tint(accent)
    }
}
