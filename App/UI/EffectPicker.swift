import SwiftUI

/// Large cards for choosing the vanish effect (settings).
struct EffectPicker: View {
    @Binding var selection: EffectStyle

    var body: some View {
        HStack(spacing: 10) {
            ForEach(EffectStyle.allCases) { style in
                card(style)
            }
        }
    }

    private func card(_ style: EffectStyle) -> some View {
        let selected = style == selection
        return Button {
            selection = style
        } label: {
            VStack(spacing: 8) {
                Image(systemName: style.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Brand.vanishGradient))
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Brand.vanishGradient) : AnyShapeStyle(Brand.violet.opacity(0.12)))
                    )
                Text(style.title)
                    .font(.callout.weight(.semibold))
                Text(style.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Brand.violet.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.4)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Brand.violet : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Compact effect menu (menu bar, studio toolbar).
struct EffectMenu: View {
    @Binding var selection: EffectStyle

    var body: some View {
        Picker(selection: $selection) {
            ForEach(EffectStyle.allCases) { style in
                Label(style.title, systemImage: style.systemImage).tag(style)
            }
        } label: {
            Text("Effect")
        }
        .labelsHidden()
        .help(Text(selection.subtitle))
    }
}
