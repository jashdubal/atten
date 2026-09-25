import AttenCore
import SwiftUI

struct VoicesView: View {
    @Bindable var model: AppModel
    let openStudio: () -> Void
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var accent: String?
    @State private var engine: String?

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
                                    requiredModelID: model.requiredModelID(for: voice.id),
                                    isSelected: model.selectedVoiceID == voice.id,
                                    isFavorite: model.settings.favoriteVoiceIDs.contains(voice.id),
                                    isPreviewing: model.voicePreviewID == voice.id,
                                    isPlaying: isPlayingPreview(of: voice),
                                    canPreview: canPreview(voice),
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
                .attenScrollPadding()
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AttenSpacing.sm) {
            Text("Voices").font(AttenTypography.title2)
            Spacer()
            AttenSearchField(prompt: "Search voices", text: $query)
                .frame(maxWidth: 240)
            Text("\(filteredVoices.count) voices")
                .font(AttenTypography.callout)
                .foregroundStyle(AttenColor.textSecondary)
        }
    }

    /// Language as the casting sheet's chips. Engines are many — one per
    /// downloaded model — so they sit in a menu, as the Library's sort does.
    private var filters: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.xs) {
            FilterChipRow(title: "Language", options: accents, selection: $accent)
            HStack(spacing: AttenSpacing.md) {
                FilterChip(title: "Favorites", systemImage: "heart", isSelected: favoritesOnly) {
                    favoritesOnly.toggle()
                }
                HStack(spacing: AttenSpacing.xs) {
                    Text("Engine")
                        .foregroundStyle(AttenColor.textMuted)
                    Menu {
                        Picker("Engine", selection: $engine) {
                            Text("All engines").tag(String?.none)
                            ForEach(engines, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    } label: {
                        Text(engine ?? "All engines")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .font(AttenTypography.callout)
                Spacer()
            }
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

    private var accents: [String] {
        _ = model.voiceCatalogRevision
        return FilterChipRow.ranked(VoiceCatalog.all.map { VoiceProfile(voice: $0).accent })
    }

    private var engines: [String] {
        _ = model.voiceCatalogRevision
        return Array(Set(VoiceCatalog.all.map(\.provider))).sorted()
    }

    private func isPlayingPreview(of voice: Voice) -> Bool {
        model.isPlaying && model.activeAudioURL == model.voicePreviewURL(voice)
    }

    /// As `PreviewButton` decides: a preview can play once it exists, and
    /// can be made only while nothing else is being spoken.
    private func canPreview(_ voice: Voice) -> Bool {
        let previewURL = model.voicePreviewURL(voice)
        return model.voicePreviewID != voice.id
            && model.requiredModelID(for: voice.id) == nil
            && (!model.synthesis.isBusy || isPlayingPreview(of: voice)
                || FileManager.default.fileExists(atPath: previewURL.path))
    }

    private var filteredVoices: [Voice] {
        _ = model.voiceCatalogRevision
        return VoiceCatalog.all.filter { voice in
            let searchable = ([voice.name, voice.id, voice.language, voice.gender, voice.provider] + voice.traits)
                .joined(separator: " ")
            let matchesQuery = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            let matchesFavorite = !favoritesOnly || model.settings.favoriteVoiceIDs.contains(voice.id)
            let matchesLanguage = accent == nil || VoiceProfile(voice: voice).accent == accent
            let matchesEngine = engine == nil || voice.provider == engine
            return matchesQuery && matchesFavorite && matchesLanguage && matchesEngine
        }
    }
}

private struct VoiceRow: View {
    let voice: Voice
    /// Set when this voice needs a model the user has not downloaded yet.
    let requiredModelID: String?
    let isSelected: Bool
    let isFavorite: Bool
    let isPreviewing: Bool
    let isPlaying: Bool
    let canPreview: Bool
    let select: () -> Void
    let favorite: () -> Void
    let preview: () -> Void

    @State private var isHovering = false

    var body: some View {
        let profile = VoiceProfile(voice: voice)
        HStack(spacing: AttenSpacing.sm) {
            VoiceWaveformAvatar(profile: profile, size: 36, isSpeaking: isPlaying)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .attenText(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AttenColor.text1)
                Text(requiredModelID.map { "\(profile.descriptor) · Needs \($0)" } ?? profile.descriptor)
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.text2)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer(minLength: AttenSpacing.xs)

            Text(profile.gender)
                .attenText(.label)
                .foregroundStyle(AttenColor.text3)

            // Glows only while this voice is speaking.
            Button(action: preview) {
                Group {
                    if isPreviewing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(isPlaying ? AttenColor.signal : AttenColor.text2)
                    }
                }
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canPreview)
            .help(isPlaying ? "Pause preview" : "Preview \(profile.displayName)")
            .accessibilityLabel(isPlaying ? "Pause preview of \(profile.displayName)" : "Preview \(profile.displayName)")

            Button(action: favorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? AttenColor.text1 : AttenColor.text2)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(
                isFavorite ? "Remove \(profile.displayName) from favorites" : "Favorite \(profile.displayName)"
            )

            // The current voice is marked as the casting sheet marks it;
            // every other voice offers to take its place.
            Group {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AttenColor.text1)
                        .accessibilityLabel("Current voice")
                } else {
                    Button("Use", action: select)
                        .buttonStyle(AttenSecondaryButtonStyle())
                }
            }
            .frame(minWidth: 58)
        }
        .padding(.horizontal, AttenSpacing.sm)
        .frame(minHeight: 58)
        .background(
            AttenColor.text1.opacity(
                isSelected ? AttenState.pressedFill / 2 : (isHovering ? AttenState.hoverFill / 2 : 0)
            )
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(isSelected ? "Open Draft" : "Use in Draft", action: select)
            Button("Preview", systemImage: "play.fill", action: preview)
            Button(
                isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "heart.slash" : "heart",
                action: favorite
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
