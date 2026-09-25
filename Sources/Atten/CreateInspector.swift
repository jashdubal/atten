import AttenCore
import SwiftUI

/// The column beside the editor: who narrates, the two real options, and
/// what generating will cost — then, while it runs, how far it has got.
struct CreateInspector: View {
    @Bindable var model: AppModel
    @Bindable var flow: CreateFlowModel
    @State private var showsAdvanced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isGenerating: Bool { flow.state == .generating }
    private var isQueued: Bool { flow.state == .queued }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AttenSpacing.lg) {
                NarratorCard(model: model, flow: flow, isLocked: isGenerating || isQueued)
                if !isGenerating && !isQueued { advanced }
                Spacer(minLength: 0)
            }
            .padding(AttenSpacing.lg)
            Rectangle().fill(AttenColor.hairline).frame(height: 1)
            Group {
                if isGenerating { generatingFooter } else if isQueued { queuedFooter } else { footer }
            }
            .padding(AttenSpacing.lg)
            // Clear of the player's ring, which floats at the bottom.
            .padding(.bottom, model.playerTitle == nil ? 0 : AttenMetrics.playerHeight)
        }
        .animation(AttenMotion.transitionAnimation(AttenMotion.state, reduceMotion: reduceMotion), value: flow.state)
    }

    private var advanced: some View {
        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: AttenSpacing.md) {
                VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                    Text("Chapters")
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                    Picker("Chapters", selection: $flow.chapterDetection) {
                        ForEach(ChapterDetection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: AttenSpacing.xs) {
                    Text("Pauses")
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                    Picker("Pauses", selection: $flow.pauseLength) {
                        ForEach(PauseLength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                PronunciationList(pronunciations: $flow.pronunciations)
                Toggle("Metal acceleration", isOn: $model.settings.useMPS)
                    .attenText(.callout)
                    .onChange(of: model.settings.useMPS) { _, _ in model.applySettings() }
            }
            .padding(.top, AttenSpacing.sm)
        } label: {
            Text("Advanced")
                .attenText(.callout)
                .foregroundStyle(AttenColor.text2)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Label("Runs on this Mac · Nothing uploaded", systemImage: "lock.fill")
                .attenText(.label)
                .foregroundStyle(AttenColor.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if flow.wordCount > 0 {
                Text("\(ListenEstimator.audioLabel(flow.listenDuration)) · \(ListenEstimator.generationLabel(flow.generationDuration))")
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.text2)
                    .monospacedDigit()
            }
            if let failure = flow.failure {
                Text(failure)
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: flow.generate) {
                Text("Generate").frame(maxWidth: .infinity)
            }
            .buttonStyle(AttenPrimaryButtonStyle(disabledReason: flow.generateDisabledReason))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!flow.canGenerate)
        }
    }

    /// Waiting behind another narration: where in line, what it will take,
    /// and the way out of the line.
    private var queuedFooter: some View {
        let status = "\(flow.isQueuePaused ? "Paused" : "Queued") · position \(flow.queuePosition ?? 1)"
        return VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            Label(status, systemImage: flow.isQueuePaused ? "pause.circle" : "clock")
                .attenText(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(AttenColor.text1)
            Text("\(ListenEstimator.audioLabel(flow.listenDuration)) · \(ListenEstimator.generationLabel(flow.generationDuration))")
                .attenText(.callout)
                .foregroundStyle(AttenColor.text2)
                .monospacedDigit()
            Button("Remove from Queue", action: flow.removeFromQueue)
                .buttonStyle(AttenTertiaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(status)
    }

    private var generatingFooter: some View {
        let extent = flow.spokenExtent
        let progress = flow.narrationProgress
        let remainingWords = max(0, (extent?.totalWords ?? 0) - (extent?.words ?? 0))
        let estimator = model.settings.listenEstimator
        let remaining = estimator.generationTime(
            audioSeconds: estimator.listenDuration(words: remainingWords, voiceID: flow.voice.id)
        )
        return VStack(alignment: .leading, spacing: AttenSpacing.sm) {
            if let player = flow.progressivePlayer, player.duration > 0 {
                ProgressivePlaybackRow(player: player)
            }
            GenerationWaveform(fraction: extent?.fraction ?? 0, seed: flow.draftID?.uuidString ?? "")
            HStack {
                Text("Chapters \(progress?.completed ?? 0) / \(progress?.total ?? 0)")
                Spacer()
                Text(progress?.isCombining == true ? "Finishing" : ListenEstimator.remainingLabel(remaining))
            }
            .attenText(.label)
            .foregroundStyle(AttenColor.text2)
            Button("Cancel", action: flow.cancel)
                .buttonStyle(AttenTertiaryButtonStyle())
        }
    }
}

/// The narrator, shown once: who they are, how they sound, and the way to
/// hear them say this draft's first sentence or cast someone else.
private struct NarratorCard: View {
    @Bindable var model: AppModel
    let flow: CreateFlowModel
    let isLocked: Bool

    var body: some View {
        let voice = flow.voice
        let profile = VoiceProfile(voice: voice)
        VStack(alignment: .leading, spacing: AttenSpacing.md) {
            HStack(spacing: AttenSpacing.sm) {
                VoiceWaveformAvatar(profile: profile, size: 48, isSpeaking: isPlayingPreview(of: voice))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .attenText(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AttenColor.text1)
                    // Traits and accent on lines of their own, so neither
                    // wraps into the other at the inspector's width.
                    if !profile.traits.isEmpty {
                        Text(profile.traits)
                            .attenText(.callout)
                            .foregroundStyle(AttenColor.text2)
                            .lineLimit(1)
                    }
                    Text(profile.accent)
                        .attenText(.callout)
                        .foregroundStyle(AttenColor.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !isLocked {
                HStack(spacing: AttenSpacing.xs) {
                    PreviewButton(model: model, flow: flow, voice: voice)
                    Spacer()
                    Button("Change") { flow.isCasting = true }
                        .buttonStyle(AttenSecondaryButtonStyle())
                }
            }
        }
        .padding(AttenSpacing.md)
        .background(AttenColor.surface1, in: RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AttenRadius.card, style: .continuous)
                .strokeBorder(AttenColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Narrator: \(profile.displayName)")
    }

    private func isPlayingPreview(of voice: Voice) -> Bool {
        model.isPlaying && model.activeAudioURL == flow.previewURL(for: voice)
    }
}

/// Plays how `voice` says the draft's first sentence, making it the first
/// time it is asked for.
struct PreviewButton: View {
    @Bindable var model: AppModel
    let flow: CreateFlowModel
    let voice: Voice
    var showsTitle = true

    var body: some View {
        let isMaking = model.voicePreviewID == voice.id
        let isPlaying = model.isPlaying && model.activeAudioURL == flow.previewURL(for: voice)
        Button {
            flow.preview(voice)
        } label: {
            HStack(spacing: AttenSpacing.xxs) {
                if isMaking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                if showsTitle { Text("Preview") }
            }
        }
        .buttonStyle(AttenSecondaryButtonStyle())
        .disabled(isMaking || model.requiredModelID(for: voice.id) != nil || (model.synthesis.isBusy && !isPlaying && !hasCachedPreview))
        .accessibilityLabel(isPlaying ? "Pause preview of \(voice.name)" : "Preview \(voice.name)")
    }

    private var hasCachedPreview: Bool {
        flow.previewURL(for: voice).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
}

/// Listening to a draft as it narrates: play or pause what has landed so
/// far, and scrub anywhere within it. Shows up as soon as the first segment
/// is ready.
private struct ProgressivePlaybackRow: View {
    let player: ProgressivePlayer

    var body: some View {
        HStack(spacing: AttenSpacing.sm) {
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(AttenColor.text1)
                    .background(AttenColor.text1.opacity(AttenState.hoverFill), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause" : "Listen as it narrates")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play narration so far")

            ScrubBar(position: player.position, duration: player.duration, seek: player.seek(to:), neutral: true)

            Text(player.state == .catchingUp ? "Catching up…" : PlaybackFormat.timeText(player.position))
                .attenText(.label)
                .foregroundStyle(AttenColor.text2)
                .monospacedDigit()
                .frame(minWidth: 78, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Narration so far")
    }
}
