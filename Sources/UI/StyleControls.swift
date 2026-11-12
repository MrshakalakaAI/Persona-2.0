import SwiftUI

struct StyleControls: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(model.settings.filter.title).font(.headline)
                Spacer()
                Text("\(Int(model.settings.filterAmount*100))%").monospacedDigit()
            }
            Text(model.settings.filter.detail).font(.caption).foregroundStyle(.secondary)
            Slider(value:$model.settings.filterAmount,in:0...1,onEditingChanged:{ active in
                if active { model.beginEdit() } else { model.endEdit() }
            }).disabled(model.settings.filter == .natural).accessibilityLabel("Сила фильтра")
            Text("12 цветовых рецептов + оригинал. Можно сочетать с образом из «Красоты».").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:100))],spacing:10) {
                ForEach(PhotoStyle.allCases) { style in
                    Button {
                        model.change { $0.filter = style; if $0.filterAmount == 0 { $0.filterAmount = 1 } }
                    } label: {
                        VStack(spacing:8) {
                            if let thumbnail = model.styleThumbnails[style] {
                                Image(uiImage:thumbnail).resizable().scaledToFill().frame(height:100).clipped().accessibilityHidden(true)
                            } else { Image(systemName:"camera.filters").font(.title2).frame(height:60) }
                            Text(style.title).font(.caption.weight(.medium)).padding(.bottom,10)
                        }.frame(maxWidth:.infinity)
                            .background(model.settings.filter == style ? Color.pink.opacity(0.2) : .white.opacity(0.05),in:RoundedRectangle(cornerRadius:14))
                            .clipShape(RoundedRectangle(cornerRadius:14))
                    }.buttonStyle(.plain).accessibilityIdentifier("style_\(style.id)")
                        .accessibilityLabel(style.title).accessibilityAddTraits(model.settings.filter == style ? .isSelected : [])
                }
            }
        }
    }
}
