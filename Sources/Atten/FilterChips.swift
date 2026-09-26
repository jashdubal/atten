import SwiftUI

/// One labelled row of filter chips — "All" and then each option — the way
/// the casting sheet and Voices narrow a list of voices. Choosing the chip
/// that is already on clears it.
struct FilterChipRow: View {
    let title: String
    let options: [String]
    var label: (String) -> String = { $0 }
    @Binding var selection: String?

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            Text(title)
                .attenText(.label)
                .foregroundStyle(AttenColor.text3)
                .frame(width: 72, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AttenSpacing.xxs) {
                    FilterChip(title: "All", isSelected: selection == nil) { selection = nil }
                    ForEach(options, id: \.self) { option in
                        FilterChip(title: label(option), isSelected: selection == option) {
                            selection = selection == option ? nil : option
                        }
                    }
                }
                .padding(.vertical, AttenSpacing.xxs)
            }
        }
    }

    /// Most common first, so the chips a person is likeliest to want lead.
    static func ranked(_ values: [String]) -> [String] {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
    }
}

struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shape = Capsule()
        Button(action: action) {
            HStack(spacing: AttenSpacing.xxs) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .attenText(.callout)
            .foregroundStyle(isSelected ? AttenColor.text1 : AttenColor.text2)
            .padding(.horizontal, AttenSpacing.sm)
            .frame(height: 26)
            .background(
                AttenColor.text1.opacity(isSelected ? AttenState.pressedFill / 2 : (isHovering ? AttenState.hoverFill / 2 : 0)),
                in: shape
            )
            .overlay { shape.strokeBorder(AttenColor.hairline, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .attenFocusRing(cornerRadius: 13)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: AttenMotion.hover), value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
