import Foundation

/// Turns word counts and generation history into the numbers Atten shows
/// instead of instructions: how long a book takes to listen to, and how long
/// it takes to generate. Both improve as Atten actually narrates things, by
/// rolling real outcomes into a per-voice pace and a real-time factor.
public struct ListenEstimator: Equatable, Sendable {
    /// Assumed reading pace before any voice has been calibrated.
    public static let defaultWordsPerMinute: Double = 155
    /// Assumed generation time per second of audio before any run has been
    /// timed: generation is assumed to take about as long as the audio it makes.
    public static let defaultRealTimeFactor: Double = 1.0
    /// Weight given to each new sample in the rolling average. Low enough
    /// that one unusually short or long chapter doesn't swing the estimate.
    private static let smoothing = 0.2

    /// Words-per-minute learned per voice, from real narrations.
    public var calibratedWordsPerMinute: [String: Double]
    /// Generation seconds per second of audio, averaged across every voice —
    /// this ratio comes mostly from the machine running the model, not from
    /// which voice is speaking.
    public var realTimeFactor: Double

    public init(
        calibratedWordsPerMinute: [String: Double] = [:],
        realTimeFactor: Double = ListenEstimator.defaultRealTimeFactor
    ) {
        self.calibratedWordsPerMinute = calibratedWordsPerMinute
        self.realTimeFactor = realTimeFactor
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public func wordsPerMinute(forVoiceID voiceID: String) -> Double {
        calibratedWordsPerMinute[voiceID] ?? Self.defaultWordsPerMinute
    }

    public func listenDuration(words: Int, voiceID: String) -> TimeInterval {
        guard words > 0 else { return 0 }
        return Double(words) / wordsPerMinute(forVoiceID: voiceID) * 60
    }

    public func generationTime(audioSeconds: TimeInterval) -> TimeInterval {
        max(0, audioSeconds) * realTimeFactor
    }

    /// Rolls a real narration's outcome into that voice's calibrated pace.
    public mutating func record(voiceID: String, words: Int, audioSeconds: TimeInterval) {
        guard words > 0, audioSeconds > 0 else { return }
        let observed = Double(words) / (audioSeconds / 60)
        let previous = calibratedWordsPerMinute[voiceID] ?? Self.defaultWordsPerMinute
        calibratedWordsPerMinute[voiceID] = previous + (observed - previous) * Self.smoothing
    }

    /// Rolls a real generation's wall-clock time into the real-time-factor average.
    public mutating func recordGeneration(audioSeconds: TimeInterval, wallSeconds: TimeInterval) {
        guard audioSeconds > 0, wallSeconds > 0 else { return }
        let observed = wallSeconds / audioSeconds
        realTimeFactor += (observed - realTimeFactor) * Self.smoothing
    }

    // MARK: - Formatting

    public static func listenLabel(_ duration: TimeInterval) -> String {
        "≈ \(minutes(duration)) MIN LISTEN"
    }

    public static func generationLabel(_ duration: TimeInterval) -> String {
        "~\(minutes(duration)) min to generate"
    }

    public static func audioLabel(_ duration: TimeInterval) -> String {
        "≈ \(minutes(duration)) min of audio"
    }

    public static func remainingLabel(_ duration: TimeInterval) -> String {
        "~\(minutes(duration)) min remaining"
    }

    public static func wordsLabel(_ words: Int) -> String {
        "\(groupedNumber(words)) WORDS"
    }

    private static func minutes(_ duration: TimeInterval) -> Int {
        max(1, Int((duration / 60).rounded()))
    }

    /// A fixed locale, not the user's: these are compact, uppercase, mono
    /// readouts styled like a HUD, not prose translated for a market.
    /// Grouped by hand because `NumberFormatter`'s POSIX locale drops the
    /// separator on some macOS versions.
    private static func groupedNumber(_ value: Int) -> String {
        let digits = Array(String(value.magnitude))
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return value < 0 ? "-" + grouped : grouped
    }
}
