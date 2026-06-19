import AttenCore
import SwiftUI

struct VoicesView: View {
    @Bindable var model: AppModel
    let openStudio: () -> Void
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var language = "All languages"

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                    header
                    statusArea
                    filters

                    if filteredVoices.isEmpty {
                        AttenEmptyState(
                            title: "No voices found",
                            systemImage: "person.2",
                            detail: "Try another search or show all languages."
                        )
                        .attenSurface()
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredVoices) { voice in
                                VoiceRow(
                                    voice: voice,
                                    availableWidth: proxy.size.width,
                                    isSelected: model.selectedVoiceID == voice.id,
                                    isFavorite: model.settings.favoriteVoiceIDs.contains(voice.id),
                                    isPreviewing: model.voicePreviewID == voice.id,
                                    select: {
                                        model.selectVoice(voice)
                                        openStudio()
                                    },
                                    favorite: { model.toggleFavorite(voice) },
                                    preview: { model.previewVoice(voice) }
                                )
                                if voice.id != filteredVoices.last?.id {
                                    Divider()
                                        .padding(.leading, 58)
                                        .overlay(AttenColor.separator.opacity(0.8))
                                }
                            }
                        }
                        .padding(.vertical, AttenSpacing.xxs)
                        .background(AttenColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AttenRadius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: AttenRadius.card)
                                .stroke(AttenColor.separator.opacity(0.72), lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, proxy.size.width < 700 ? AttenSpacing.lg : AttenSpacing.xl)
                .padding(.vertical, AttenSpacing.lg)
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search voices")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            PageHeader(
                eyebrow: "Voices",
                title: "Voice library",
                detail: "Preview Kokoro voices and keep favorites close."
            )
            Spacer()
            Text("\(filteredVoices.count) voices")
                .font(AttenTypography.metadata)
                .foregroundStyle(AttenColor.textSecondary)
        }
    }

    private var filters: some View {
        HStack(spacing: AttenSpacing.sm) {
            Picker("Language", selection: $language) {
                Text("All languages").tag("All languages")
                ForEach(languages, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 210)

            Toggle("Favorites", systemImage: "heart.fill", isOn: $favoritesOnly)
                .toggleStyle(.button)
                .tint(AttenColor.accentSecondary)

            Spacer()
        }
    }

    @ViewBuilder private var statusArea: some View {
        if let success = model.successMessage {
            StatusBanner(kind: .success, message: success, dismiss: model.dismissStatus)
        }
        if case let .failed(message) = model.generationState {
            StatusBanner(kind: .error, message: message, dismiss: model.dismissStatus)
        }
    }

    private var languages: [String] {
        Array(Set(VoiceCatalog.all.map(\.language))).sorted()
    }

    private var filteredVoices: [Voice] {
        VoiceCatalog.all.filter { voice in
            let searchable = ([voice.name, voice.id, voice.language, voice.gender] + voice.traits)
                .joined(separator: " ")
            let matchesQuery = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            let matchesFavorite = !favoritesOnly || model.settings.favoriteVoiceIDs.contains(voice.id)
            let matchesLanguage = language == "All languages" || voice.language == language
            return matchesQuery && matchesFavorite && matchesLanguage
        }
    }
}

private struct VoiceRow: View {
    let voice: Voice
    let availableWidth: CGFloat
    let isSelected: Bool
    let isFavorite: Bool
    let isPreviewing: Bool
    let select: () -> Void
    let favorite: () -> Void
    let preview: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            VoiceAvatar(voice: voice, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AttenSpacing.xs) {
                    Text(voice.name)
                        .font(AttenTypography.control.weight(.semibold))
                        .foregroundStyle(AttenColor.textPrimary)
                    if isSelected {
                        Label("Selected", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(AttenColor.accent)
                    }
                }
                Text("\(voice.language) · \(voice.gender)")
                    .font(AttenTypography.caption)
                    .foregroundStyle(AttenColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, alignment: .leading)

            if availableWidth >= 820 {
                HStack(spacing: AttenSpacing.xs) {
                    ForEach(voice.traits.prefix(2), id: \.self) { trait in
                        Text(trait.capitalized)
                            .font(AttenTypography.caption)
                            .foregroundStyle(AttenColor.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AttenColor.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: AttenRadius.small))
                    }
                }
            }

            Spacer(minLength: AttenSpacing.xs)

            Button(action: preview) {
                if isPreviewing {
                    ProgressView().controlSize(.small).frame(width: 30, height: 30)
                } else {
                    Image(systemName: "play.fill").frame(width: 30, height: 30)
                }
            }
            .buttonStyle(.borderless)
            .disabled(isPreviewing)
            .help("Preview \(voice.name)")
            .accessibilityLabel("Preview \(voice.name)")

            Button(action: favorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(
                        isFavorite ? AttenColor.accentSecondary : AttenColor.textSecondary
                    )
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(
                isFavorite ? "Remove \(voice.name) from favorites" : "Favorite \(voice.name)"
            )

            if isSelected {
                Button("Open", action: select)
                    .buttonStyle(.bordered)
                    .tint(AttenColor.accent)
                    .controlSize(.small)
                    .frame(minWidth: 58)
            } else {
                Button("Use", action: select)
                    .buttonStyle(.borderedProminent)
                    .tint(AttenColor.accent)
                    .controlSize(.small)
                    .frame(minWidth: 58)
            }
        }
        .padding(.horizontal, AttenSpacing.sm)
        .frame(minHeight: 58)
        .background(
            isSelected
                ? AttenColor.accent.opacity(0.09)
                : (isHovering ? AttenColor.surfaceMuted.opacity(0.65) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(isSelected ? "Open in Studio" : "Use in Studio", action: select)
            Button("Preview", systemImage: "play.fill", action: preview)
            Button(
                isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "heart.slash" : "heart",
                action: favorite
            )
        }
        .accessibilityElement(children: .contain)
    }
}
