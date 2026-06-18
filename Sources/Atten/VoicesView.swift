import AttenCore
import SwiftUI

struct VoicesView: View {
    @Bindable var model: AppModel
    let openStudio: () -> Void
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var language = "All languages"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                HStack(alignment: .bottom) {
                    SectionHeader(
                        eyebrow: "Voices",
                        title: "Meet the woodland chorus",
                        detail: "Browse the voices installed with Kokoro, preview them, and keep favorites close."
                    )
                    Spacer()
                    Toggle("Favorites", systemImage: "heart.fill", isOn: $favoritesOnly)
                        .toggleStyle(.button)
                        .tint(AttenColor.berry)
                }

                HStack {
                    Picker("Language", selection: $language) {
                        Text("All languages").tag("All languages")
                        ForEach(languages, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 210)
                    Text("\(filteredVoices.count) voices")
                        .font(.caption)
                        .foregroundStyle(AttenColor.secondaryInk)
                    Spacer()
                }

                if filteredVoices.isEmpty {
                    ContentUnavailableView(
                        "No voices found",
                        systemImage: "person.wave.2",
                        description: Text("Try another search or show all languages.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .attenCard()
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 245, maximum: 330), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(filteredVoices) { voice in
                            VoiceCard(
                                voice: voice,
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
                        }
                    }
                }
            }
            .padding(AttenSpacing.xl)
            .frame(maxWidth: 1180, alignment: .topLeading)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search voices, traits, or languages")
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

private struct VoiceCard: View {
    let voice: Voice
    let isSelected: Bool
    let isFavorite: Bool
    let isPreviewing: Bool
    let select: () -> Void
    let favorite: () -> Void
    let preview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            HStack(alignment: .top) {
                VoiceAvatar(voice: voice, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(voice.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AttenColor.ink)
                    Text("\(voice.language) • \(voice.gender)")
                        .font(.caption)
                        .foregroundStyle(AttenColor.secondaryInk)
                }
                Spacer()
                Button(action: favorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? AttenColor.berry : AttenColor.secondaryInk)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                .accessibilityLabel(isFavorite ? "Remove \(voice.name) from favorites" : "Favorite \(voice.name)")
            }

            HStack(spacing: 6) {
                ForEach(voice.traits.prefix(3), id: \.self) { trait in
                    Text(trait.capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AttenColor.moss.opacity(0.13))
                        .clipShape(Capsule())
                }
                Spacer()
                Text("Quality \(voice.quality)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(action: preview) {
                    if isPreviewing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Preview", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isPreviewing)

                Spacer()
                Button(isSelected ? "Selected" : "Use Voice", action: select)
                    .buttonStyle(.borderedProminent)
                    .tint(isSelected ? AttenColor.moss : AttenColor.forest)
            }
        }
        .attenCard()
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AttenColor.forest, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
