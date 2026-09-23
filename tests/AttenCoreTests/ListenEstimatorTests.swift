import AttenCore
import Foundation
import XCTest

final class ListenEstimatorTests: XCTestCase {
    func testSettingsWrittenBeforeCalibrationExistedStillLoad() throws {
        let json = #"{ "outputDirectory": "/tmp/atten" }"#

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.listenWordsPerMinuteByVoice, [:])
        XCTAssertEqual(settings.listenRealTimeFactor, ListenEstimator.defaultRealTimeFactor)
    }

    func testAppSettingsRoundTripsTheCalibratedEstimator() {
        var settings = AppSettings(outputDirectory: "/tmp/atten")
        var estimator = settings.listenEstimator
        estimator.record(voiceID: "af_heart", words: 300, audioSeconds: 60)
        estimator.recordGeneration(audioSeconds: 10, wallSeconds: 25)

        settings.listenEstimator = estimator

        XCTAssertEqual(settings.listenWordsPerMinuteByVoice, estimator.calibratedWordsPerMinute)
        XCTAssertEqual(settings.listenRealTimeFactor, estimator.realTimeFactor)
        XCTAssertEqual(settings.listenEstimator, estimator)
    }

    func testWordCountSplitsOnWhitespace() {
        XCTAssertEqual(ListenEstimator.wordCount("Hello,   world.\nThis is a test."), 6)
        XCTAssertEqual(ListenEstimator.wordCount(""), 0)
    }

    func testListenDurationUsesTheDefaultPaceForAnUncalibratedVoice() {
        let estimator = ListenEstimator()
        // 155 words per minute is 155/60 words per second.
        let duration = estimator.listenDuration(words: 155, voiceID: "af_heart")
        XCTAssertEqual(duration, 60, accuracy: 0.001)
    }

    func testRecordingNarrationsMovesTheCalibratedPaceTowardWhatWasObserved() {
        var estimator = ListenEstimator()
        let before = estimator.wordsPerMinute(forVoiceID: "af_heart")

        // 300 words in 60 real seconds is a real pace of 300 wpm, well above default.
        estimator.record(voiceID: "af_heart", words: 300, audioSeconds: 60)

        let after = estimator.wordsPerMinute(forVoiceID: "af_heart")
        XCTAssertGreaterThan(after, before)
        XCTAssertLessThan(after, 300) // a rolling average, not a jump straight to the sample
        // A different voice is unaffected.
        XCTAssertEqual(estimator.wordsPerMinute(forVoiceID: "af_bella"), ListenEstimator.defaultWordsPerMinute)
    }

    func testRepeatedIdenticalSamplesConverge() {
        var estimator = ListenEstimator()
        for _ in 0..<50 {
            estimator.record(voiceID: "af_heart", words: 300, audioSeconds: 60)
        }
        XCTAssertEqual(estimator.wordsPerMinute(forVoiceID: "af_heart"), 300, accuracy: 0.5)
    }

    func testGenerationTimeUsesTheRealTimeFactor() {
        let estimator = ListenEstimator(realTimeFactor: 2.0)
        XCTAssertEqual(estimator.generationTime(audioSeconds: 30), 60, accuracy: 0.001)
    }

    func testRecordingGenerationMovesTheRealTimeFactorTowardWhatWasObserved() {
        var estimator = ListenEstimator()
        let before = estimator.realTimeFactor

        estimator.recordGeneration(audioSeconds: 10, wallSeconds: 30) // observed RTF of 3.0

        XCTAssertGreaterThan(estimator.realTimeFactor, before)
        XCTAssertLessThan(estimator.realTimeFactor, 3.0)
    }

    func testFormattingHelpers() {
        XCTAssertEqual(ListenEstimator.listenLabel(16 * 60), "≈ 16 MIN LISTEN")
        XCTAssertEqual(ListenEstimator.generationLabel(2 * 60), "~2 min to generate")
        XCTAssertEqual(ListenEstimator.wordsLabel(2431), "2,431 WORDS")
    }

    func testFormattingRoundsUpToAtLeastOneMinute() {
        XCTAssertEqual(ListenEstimator.listenLabel(10), "≈ 1 MIN LISTEN")
    }
}
