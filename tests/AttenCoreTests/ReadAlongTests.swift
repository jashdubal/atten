import XCTest
@testable import Atten
@testable import AttenCore

final class ReadAlongTests: XCTestCase {
    /// Two sentences in one segment, as Kokoro times them: a word each for
    /// "It", "was", "late", a punctuation token, and so on.
    private func paragraph(start: Double = 10) -> TimedSegment {
        TimedSegment(index: 0, text: "It was late. The rain had stopped.", start: start, duration: 4, words: [
            TimedWord(text: "It", start: 0.0, end: 0.2),
            TimedWord(text: "was", start: 0.2, end: 0.5),
            TimedWord(text: "late", start: 0.5, end: 1.0),
            TimedWord(text: ".", start: 1.0, end: 1.2),
            TimedWord(text: "The", start: 1.6, end: 1.8),
            TimedWord(text: "rain", start: 1.8, end: 2.2),
            TimedWord(text: "had", start: 2.2, end: 2.5),
            TimedWord(text: "stopped", start: 2.5, end: 3.4),
            TimedWord(text: ".", start: 3.4, end: 3.6),
        ])
    }

    func testTimedSegmentsSplitIntoSentencesStartingOnTheirFirstWord() {
        let script = ReadAlongScript(timings: NarrationTimings(segments: [paragraph()]))
        XCTAssertEqual(script.sentences.map(\.text), ["It was late.", "The rain had stopped."])
        XCTAssertEqual(script.sentences.map(\.start), [10.0, 11.6])
        XCTAssertTrue(script.hasWordTimings)
    }

    func testTheWordBeingSpokenIsFoundInsideItsSentence() throws {
        let script = ReadAlongScript(timings: NarrationTimings(segments: [paragraph()]))
        let place = try XCTUnwrap(script.locate(time: 10.3))
        XCTAssertEqual(place.sentence, 0)
        let sentence = Array(script.sentences[0].text)
        XCTAssertEqual(String(sentence[try XCTUnwrap(place.word)]), "was")

        let later = try XCTUnwrap(script.locate(time: 12.0))
        XCTAssertEqual(later.sentence, 1)
        XCTAssertEqual(String(Array(script.sentences[1].text)[try XCTUnwrap(later.word)]), "rain")
    }

    /// Between words — the pause after a full stop — the sentence stays lit
    /// and no word is underlined.
    func testSilenceKeepsTheSentenceWithoutAWord() throws {
        let script = ReadAlongScript(timings: NarrationTimings(segments: [paragraph()]))
        let place = try XCTUnwrap(script.locate(time: 11.4))
        XCTAssertEqual(place.sentence, 0)
        XCTAssertNil(place.word)
        XCTAssertEqual(script.locate(time: 0)?.sentence, 0, "before the first word")
    }

    /// A token the engine timed that is not in the text cannot move the
    /// cursor past words that are.
    func testAWordMissingFromTheTextIsSkipped() throws {
        let segment = TimedSegment(index: 0, text: "Hello there.", start: 0, duration: 2, words: [
            TimedWord(text: "Hullo", start: 0, end: 0.5),
            TimedWord(text: "there", start: 0.6, end: 1.2),
        ])
        let script = ReadAlongScript(timings: NarrationTimings(segments: [segment]))
        XCTAssertNil(script.locate(time: 0.2)?.word)
        let word = try XCTUnwrap(script.locate(time: 0.8)?.word)
        XCTAssertEqual(String(Array(script.sentences[0].text)[word]), "there")
    }

    func testSegmentsAreParagraphs() {
        let script = ReadAlongScript(timings: NarrationTimings(segments: [
            paragraph(start: 0),
            TimedSegment(index: 1, text: "Morning came.", start: 5, duration: 1, words: []),
        ]))
        XCTAssertEqual(script.sentences.map(\.paragraph), [0, 0, 1])
        XCTAssertEqual(script.sentences.map(\.id), [0, 1, 2])
    }

    /// Without word timings each passage is spread over its stretch of the
    /// recording by length, and only sentences are ever lit.
    func testWithoutTimingsSentencesAreEstimatedFromTheirLength() throws {
        let script = ReadAlongScript(estimating: [
            (text: "One two. Three four five six.", start: 0, end: 30),
            (text: "Next chapter.", start: 30, end: 40),
        ])
        XCTAssertFalse(script.hasWordTimings)
        XCTAssertEqual(script.sentences.map(\.text), ["One two.", "Three four five six.", "Next chapter."])
        XCTAssertEqual(script.sentences[0].start, 0)
        XCTAssertEqual(script.sentences[2].start, 30)
        XCTAssertLessThan(script.sentences[1].start, 30)
        XCTAssertEqual(script.locate(time: 35), ReadAlongPlace(sentence: 2))
        XCTAssertNil(script.locate(time: 1)?.word)
    }

    func testNewlinesStartNewParagraphs() {
        let script = ReadAlongScript(estimating: [(text: "First.\n\nSecond.\nThird.", start: 0, end: 3)])
        XCTAssertEqual(script.sentences.map(\.paragraph), [0, 1, 2])
    }

    func testAnEmptyScriptLocatesNothing() {
        XCTAssertNil(ReadAlongScript.empty.locate(time: 1))
        XCTAssertNil(ReadAlongScript(timings: NarrationTimings(segments: [paragraph()])).locate(time: .nan))
    }

    // MARK: - Ambient contrast

    func testCompositeBlendsTowardTheTopColour() {
        XCTAssertEqual(AmbientContrast.composite(0xFFFFFF, over: 0x000000, opacity: 0), 0x000000)
        XCTAssertEqual(AmbientContrast.composite(0xFFFFFF, over: 0x000000, opacity: 1), 0xFFFFFF)
        XCTAssertEqual(AmbientContrast.composite(0xFF0000, over: 0x0000FF, opacity: 0.5), 0x800080)
    }

    /// A white cover behind white text is turned down until the text reads.
    func testOpacityIsLoweredUntilTextReadsOnEverySample() {
        let palette = AttenPalette.atten
        let opacity = AmbientContrast.opacity(
            samples: [0xFFFFFF, 0x336699], ground: palette.bg.dark, text: palette.text1.dark, preferred: 0.8
        )
        XCTAssertLessThan(opacity, 0.8)
        for sample in [UInt(0xFFFFFF), 0x336699] {
            let behind = AmbientContrast.composite(sample, over: palette.bg.dark, opacity: opacity)
            XCTAssertGreaterThanOrEqual(WCAG.contrast(palette.text1.dark, behind), 4.5)
        }
    }

    func testAQuietFieldKeepsItsPreferredOpacity() {
        let palette = AttenPalette.atten
        XCTAssertEqual(AmbientContrast.opacity(
            samples: [0x3A4A5A], ground: palette.bg.dark, text: palette.text1.dark, preferred: 0.5
        ), 0.5)
    }

    /// Any field, built from any cover, holds text1 at 4.5:1 in both
    /// appearances at the opacity it will be drawn with.
    @MainActor
    func testEveryFieldPassesTheContrastCheckInBothAppearances() throws {
        let palette = AttenPalette.atten
        for hash in ["a", "The Alchemist", "0f3c", "Moby Dick", "zz-top"] {
            let field = try XCTUnwrap(AmbientField.make(id: hash, cover: nil, seed: CoverSeed(contentHash: hash)))
            XCTAssertGreaterThan(field.darkOpacity, 0)
            XCTAssertGreaterThan(field.lightOpacity, 0)
            let pixels = try pixels(of: field.image)
            for pixel in pixels {
                XCTAssertGreaterThanOrEqual(WCAG.contrast(palette.text1.dark, AmbientContrast.composite(
                    pixel, over: palette.bg.dark, opacity: field.darkOpacity)), 4.5)
                XCTAssertGreaterThanOrEqual(WCAG.contrast(palette.text1.light, AmbientContrast.composite(
                    pixel, over: palette.bg.light, opacity: field.lightOpacity)), 4.5)
            }
        }
    }

    private func pixels(of image: CGImage) throws -> [UInt] {
        let width = image.width, height = image.height
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        return (0..<(width * height)).map {
            UInt(bytes[$0 * 4]) << 16 | UInt(bytes[$0 * 4 + 1]) << 8 | UInt(bytes[$0 * 4 + 2])
        }
    }

    // MARK: - Level

    /// Quick to rise, slow to fall: after 30ms of speech the level is most of
    /// the way up, and 30ms of silence barely brings it down.
    func testEnvelopeAttacksFastAndReleasesSlowly() {
        var envelope = LevelEnvelope()
        let risen = envelope.follow(1, elapsed: 0.03)
        XCTAssertGreaterThan(risen, 0.6)
        let fallen = envelope.follow(0, elapsed: 0.03)
        XCTAssertGreaterThan(fallen, risen * 0.8)
    }

    func testDecibelsMapOntoZeroToOne() {
        XCTAssertEqual(LevelEnvelope.normalized(decibels: 0), 1)
        XCTAssertEqual(LevelEnvelope.normalized(decibels: -160), 0)
        XCTAssertEqual(LevelEnvelope.normalized(decibels: -25), 0.5)
        XCTAssertEqual(LevelEnvelope.normalized(decibels: -.infinity), 0)
    }
}
