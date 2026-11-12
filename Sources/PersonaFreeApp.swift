import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

@main struct PersonaFreeApp: App {
    var body: some Scene { WindowGroup { EditorView() } }
}

struct EditorView: View {
    @State private var selection: PhotosPickerItem?
    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var brightness = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var warmth = 0.0
    @State private var sharpness = 0.0
    @State private var smoothing = 0.0
    @State private var status = ""
    private let context = CIContext()
    private let ink = Color(red: 0.96, green: 0.79, blue: 0.85)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.07))
                        if let preview {
                            Image(uiImage: preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20)).padding(8)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "person.crop.square").font(.system(size: 54)).foregroundStyle(ink)
                                Text("Твоя красота. Твои правила.").font(.headline)
                                Text("Выбери фотографию для редактирования").foregroundStyle(.secondary).font(.subheadline)
                            }.padding()
                        }
                    }.frame(height: 370)
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(original == nil ? "Выбрать фото" : "Другое фото", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity).padding(14).background(ink, in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(.black).fontWeight(.semibold)
                    }
                    if original != nil {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("СТУДИЯ РЕТУШИ").font(.caption).tracking(2).foregroundStyle(ink)
                            control("Смягчение изображения", value: $smoothing, range: 0...1)
                            control("Свет", value: $brightness, range: -0.5...0.5)
                            control("Контраст", value: $contrast, range: 0.5...1.8)
                            control("Цвет", value: $saturation, range: 0...2)
                            control("Теплота", value: $warmth, range: -1...1)
                            control("Резкость", value: $sharpness, range: 0...1)
                        }.padding(18).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
                        HStack {
                            Button("Сбросить") { reset() }.buttonStyle(.bordered)
                            Spacer()
                            Button { save() } label: { Label("Сохранить", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).tint(ink).foregroundStyle(.black)
                        }
                    }
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }.padding(18)
            }
            .background(Color(red: 0.075, green: 0.07, blue: 0.10))
            .foregroundStyle(.white)
            .navigationTitle("Beauty Studio")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onChange(of: selection) { _, newValue in
                Task {
                    guard let data = try? await newValue?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    await MainActor.run { original = image; reset() }
                }
            }
            .onChange(of: brightness) { _, _ in render() }
            .onChange(of: contrast) { _, _ in render() }
            .onChange(of: saturation) { _, _ in render() }
            .onChange(of: warmth) { _, _ in render() }
            .onChange(of: sharpness) { _, _ in render() }
            .onChange(of: smoothing) { _, _ in render() }
        }
    }
    private func control(_ name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(name).font(.subheadline); Spacer(); Text(String(format: "%.0f", value.wrappedValue * 100)).font(.caption).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range).tint(ink)
        }
    }
    private func reset() {
        brightness = 0; contrast = 1; saturation = 1; warmth = 0; sharpness = 0; smoothing = 0
        render()
    }
    private func render() {
        guard let original, let ci = CIImage(image: original) else { return }
        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.brightness = Float(brightness)
        color.contrast = Float(contrast)
        color.saturation = Float(saturation)
        guard var output = color.outputImage else { return }
        if warmth != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = output
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 6500 + CGFloat(warmth) * 1800, y: 0)
            output = temp.outputImage ?? output
        }
        if smoothing > 0 {
            let noise = CIFilter.noiseReduction()
            noise.inputImage = output
            noise.noiseLevel = Float(smoothing * 0.06)
            noise.sharpness = 0
            output = noise.outputImage ?? output
        }
        if sharpness > 0 {
            let sharp = CIFilter.sharpenLuminance()
            sharp.inputImage = output
            sharp.sharpness = Float(sharpness)
            output = sharp.outputImage ?? output
        }
        if let cg = context.createCGImage(output, from: ci.extent) {
            preview = UIImage(cgImage: cg, scale: original.scale, orientation: original.imageOrientation)
        }
    }
    private func save() {
        guard let preview else { return }
        UIImageWriteToSavedPhotosAlbum(preview, nil, nil, nil)
        status = "Отправлено в Фото. Проверь разрешение на сохранение."
    }
}
