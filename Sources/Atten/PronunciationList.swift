import AttenCore
import SwiftUI

/// The words this draft's voice should say differently: what the text has,
/// and what to say instead.
struct PronunciationList: View {
    @Binding var pronunciations: [Pronunciation]
    @FocusState private var focusedRow: Int?

    /// Past this many rows the list scrolls, so the Generate button below it
    /// never leaves the column.
    private static let visibleRows = 4
    private static let rowHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            Text("Pronunciations")
                .attenText(.callout)
                .foregroundStyle(AttenColor.text2)
            if pronunciations.count > Self.visibleRows {
                // A box inside the inspector, which already clears the player,
                // so it takes none of `attenScrollPadding`'s room.
                ScrollView(.vertical) { rows }
                    .frame(height: (Self.rowHeight + AttenSpacing.xs) * (CGFloat(Self.visibleRows) + 0.5))
            } else {
                rows
            }
            Button {
                pronunciations.append(Pronunciation(match: "", say: ""))
                focusedRow = pronunciations.count - 1
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(AttenTertiaryButtonStyle())
            .accessibilityLabel("Add pronunciation")
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            ForEach(pronunciations.indices, id: \.self) { index in
                HStack(spacing: AttenSpacing.xs) {
                    field("Word", text: binding(index, \.match))
                        .focused($focusedRow, equals: index)
                    Image(systemName: "arrow.right")
                        .font(AttenTypography.label)
                        .foregroundStyle(AttenColor.text3)
                        .accessibilityHidden(true)
                    field("Say", text: binding(index, \.say))
                    Button {
                        guard pronunciations.indices.contains(index) else { return }
                        pronunciations.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(AttenTertiaryButtonStyle())
                    .accessibilityLabel("Remove pronunciation")
                }
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text, prompt: Text(prompt).foregroundStyle(AttenColor.text3))
            .textFieldStyle(.plain)
            .font(AttenTypography.callout)
            .padding(.horizontal, AttenSpacing.xs)
            .frame(height: Self.rowHeight)
            .attenInput()
    }

    /// A row's field, read and written through its index so a row removed
    /// while one of its fields is still on screen is never reached.
    private func binding(_ index: Int, _ field: WritableKeyPath<Pronunciation, String>) -> Binding<String> {
        Binding(
            get: { pronunciations.indices.contains(index) ? pronunciations[index][keyPath: field] : "" },
            set: { if pronunciations.indices.contains(index) { pronunciations[index][keyPath: field] = $0 } }
        )
    }
}
