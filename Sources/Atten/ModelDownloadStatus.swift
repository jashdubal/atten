import AttenCore
import SwiftUI

/// A model download under its row in Settings → Models: how far it has got,
/// or in one line why it stopped. Progress is voice-adjacent, so it may use
/// `signal`; a stopped download stays quiet.
struct ModelDownloadStatus: View {
    let state: ModelLibrary.DownloadState
    let retry: () -> Void

    var body: some View {
        switch state.phase {
        case let .failed(failure):
            HStack(spacing: AttenSpacing.xs) {
                Image(systemName: failure == .offline ? "wifi.slash" : "exclamationmark.circle")
                    .foregroundStyle(failure == .offline ? AttenColor.text2 : AttenColor.destructive)
                    .accessibilityHidden(true)
                Text(failure.message)
                    .foregroundStyle(AttenColor.text2)
                Button("Retry", action: retry)
                    .buttonStyle(AttenTertiaryButtonStyle())
            }
            .attenText(.callout)
            .accessibilityElement(children: .contain)
        case .downloading, .paused:
            VStack(alignment: .leading, spacing: AttenSpacing.xxs) {
                ModelDownloadBar(state: state)
                Text(Self.summary(of: state))
                    .attenText(.callout)
                    .foregroundStyle(AttenColor.text2)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(state.phase == .downloading ? .updatesFrequently : [])
        }
    }

    /// "42% · 122 MB / 290 MB · 3.1 MB/s · 52s left", or where it stands
    /// before the first byte arrives.
    static func summary(of state: ModelLibrary.DownloadState) -> String {
        let progress = state.progress
        let isPaused = state.phase == .paused
        guard !progress.sizeText.isEmpty else { return isPaused ? "Paused" : "Connecting…" }
        let eta = progress.eta == "--" ? "" : progress.eta
        return [
            isPaused ? "Paused" : "",
            progress.fraction == nil ? "" : "\(progress.percent)%",
            progress.sizeText,
            progress.speed,
            eta.isEmpty ? "" : "\(eta) left",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

/// The bar itself: `signal` while bytes arrive, `text3` while paused. Drawn
/// rather than a `ProgressView`, which AppKit greys out in an inactive window.
struct ModelDownloadBar: View {
    let state: ModelLibrary.DownloadState

    var body: some View {
        if let fraction = state.progress.fraction {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AttenColor.text1.opacity(AttenState.hoverFill))
                    Capsule()
                        .fill(state.phase == .paused ? AttenColor.text3 : AttenColor.signal)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }
}

extension ModelLibrary {
    /// How a voice whose model isn't installed yet describes itself.
    func needsDownloadLabel(for modelID: String) -> String {
        switch downloads[modelID]?.phase {
        case .downloading: "Downloading"
        case .paused: "Download paused"
        case let .failed(failure): failure.message
        case nil: "Needs download"
        }
    }
}

/// Where a voice that needs a model is offered it — in Create, the casting
/// sheet and Voices — so no one has to go to Settings → Models first.
/// Download, then how far it has got, then Retry if it stopped.
struct VoiceModelDownloadButton: View {
    let library: ModelLibrary
    let modelID: String
    /// The casting card's slot is the size of its Preview button.
    var isCompact = false

    var body: some View {
        let state = library.downloads[modelID]
        switch state?.phase {
        case .downloading:
            let percent = state?.progress.fraction.map { "\(Int($0 * 100))%" }
            Group {
                if isCompact {
                    ZStack {
                        Circle().stroke(AttenColor.text1.opacity(AttenState.hoverFill), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: state?.progress.fraction ?? 0)
                            .stroke(AttenColor.signal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 18, height: 18)
                    .frame(width: 32, height: 32)
                } else if let state {
                    HStack(spacing: AttenSpacing.xs) {
                        ModelDownloadBar(state: state).frame(width: 56)
                        if let percent {
                            Text(percent)
                                .attenText(.label)
                                .foregroundStyle(AttenColor.text2)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Downloading \(modelID)\(percent.map { ", \($0)" } ?? "")")
        case .paused:
            action("Resume", systemImage: "arrow.down.circle", help: "Resume downloading \(modelID)")
        case let .failed(failure):
            action("Retry", systemImage: "arrow.clockwise", help: "\(failure.message). Retry \(modelID)")
        case nil:
            action("Download", systemImage: "arrow.down.circle", help: "Download \(modelID)")
        }
    }

    @ViewBuilder private func action(_ title: String, systemImage: String, help: String) -> some View {
        if isCompact {
            Button { library.download(modelID) } label: { Image(systemName: systemImage) }
                .buttonStyle(AttenSecondaryButtonStyle())
                .help(help)
                .accessibilityLabel(help)
        } else {
            Button(title, systemImage: systemImage) { library.download(modelID) }
                .buttonStyle(AttenTertiaryButtonStyle())
                .help(help)
        }
    }
}
