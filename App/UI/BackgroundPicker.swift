import SwiftUI

/// Grid of backgrounds: the empty-room snapshot, built-in presets, user images and an "add" tile.
struct BackgroundPicker: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var library: BackgroundLibrary
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            tile(id: nil, name: String(localized: "Room snapshot")) {
                if let thumb = model.roomThumbnail {
                    Image(nsImage: thumb).resizable().scaledToFill()
                } else {
                    placeholder(systemImage: "camera.viewfinder", text: "Not captured")
                }
            }
            ForEach(library.all) { item in
                tile(id: item.id, name: item.name) {
                    if let thumb = library.thumbnail(for: item.id) {
                        Image(nsImage: thumb).resizable().scaledToFill()
                    } else {
                        placeholder(systemImage: "exclamationmark.triangle", text: "Can’t load")
                    }
                }
                .contextMenu {
                    if item.isCustom {
                        Button("Remove", role: .destructive) { model.removeBackground(item.id) }
                    }
                }
            }
            addTile
        }
    }

    private func tile<Content: View>(id: String?, name: String, @ViewBuilder content: () -> Content) -> some View {
        let selected = settings.backgroundID == id
        return Button {
            model.selectBackground(id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                content()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Brand.violet : Color.primary.opacity(0.1),
                                          lineWidth: selected ? 2.5 : 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, Brand.violet)
                                .padding(5)
                        }
                    }
                Text(name)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(name))
    }

    private var addTile: some View {
        Button {
            model.addBackgroundFromFile()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                placeholder(systemImage: "plus", text: "Add image…")
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                    )
                Text(" ").font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeholder(systemImage: String, text: LocalizedStringKey) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5))
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 18))
                Text(text).font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// Compact menu for the menu-bar popover.
struct BackgroundMenu: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var library: BackgroundLibrary
    var openSettings: () -> Void

    var body: some View {
        Menu {
            pick(nil, String(localized: "Room snapshot"))
            Divider()
            ForEach(library.presets) { pick($0.id, $0.name) }
            if !library.custom.isEmpty {
                Divider()
                ForEach(library.custom) { pick($0.id, $0.name) }
            }
            Divider()
            Button("Add image…") { model.addBackgroundFromFile() }
            Button("All backgrounds…") { openSettings() }
        } label: {
            Text(model.backgroundName).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func pick(_ id: String?, _ name: String) -> some View {
        Button {
            model.selectBackground(id)
        } label: {
            if settings.backgroundID == id {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }
}
