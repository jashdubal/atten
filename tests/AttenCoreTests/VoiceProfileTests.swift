import AttenCore
import XCTest

final class VoiceProfileTests: XCTestCase {
    func testEveryBundledVoiceHasANameAndADescriptor() {
        for voice in VoiceCatalog.bundled {
            let profile = VoiceProfile(voice: voice)
            XCTAssertFalse(profile.displayName.isEmpty, voice.id)
            XCTAssertFalse(profile.descriptor.isEmpty, voice.id)
        }
    }

    func testHuesAreDeterministic() {
        for voice in VoiceCatalog.bundled {
            let first = VoiceProfile(voice: voice).hue
            let second = VoiceProfile(voice: voice).hue
            XCTAssertEqual(first, second, voice.id)
            XCTAssertTrue((0..<360).contains(first), voice.id)
        }
    }

    func testDisplayNameStripsTheParentheticalLanguage() {
        let voice = Voice(
            id: "af_heart", name: "Heart (English US)", language: "English (US)",
            languageCode: "a", gender: "Female", traits: ["warm"], quality: "A"
        )
        XCTAssertEqual(VoiceProfile(voice: voice).displayName, "Heart")
    }

    func testAccentReordersARegionInParentheses() {
        let voice = Voice(
            id: "bf_emma", name: "Emma", language: "English (UK)",
            languageCode: "b", gender: "Female", traits: ["warm"], quality: "B"
        )
        XCTAssertEqual(VoiceProfile(voice: voice).accent, "UK English")
    }

    func testDescriptorDoesNotRepeatATraitThatIsAlreadyTheAccent() {
        let voice = Voice(
            id: "ef_dora", name: "Dora", language: "Spanish",
            languageCode: "e", gender: "Female", traits: ["Spanish"], quality: "Unrated"
        )
        XCTAssertEqual(VoiceProfile(voice: voice).descriptor, "Spanish")
        XCTAssertEqual(VoiceProfile(voice: voice).traits, "")
    }

    /// The narrator card sets traits and accent on lines of their own (#98).
    func testTraitsLeaveTheAccentForItsOwnLine() {
        let voice = Voice(
            id: "af_test", name: "Test", language: "English (US)",
            languageCode: "a", gender: "Female", traits: ["warm", "expressive"], quality: "A"
        )
        let profile = VoiceProfile(voice: voice)
        XCTAssertEqual(profile.traits, "Warm · Expressive")
        XCTAssertEqual(profile.accent, "US English")
    }

    /// Voices lists each voice by this name alone, with the accent on the
    /// line below (#108), so no bundled name may keep its language.
    func testNoBundledDisplayNameCarriesItsLanguage() {
        for voice in VoiceCatalog.bundled {
            let profile = VoiceProfile(voice: voice)
            XCTAssertFalse(profile.displayName.contains("("), voice.id)
            XCTAssertFalse(profile.displayName.localizedCaseInsensitiveContains(voice.language), voice.id)
        }
        let arabic = Voice(
            id: "ar_mariam", name: "Mariam (مريم - Arabic)", language: "Arabic",
            languageCode: "ar", gender: "Female", traits: ["natural", "Arabic"], quality: "Unrated"
        )
        XCTAssertEqual(VoiceProfile(voice: arabic).displayName, "Mariam")
    }

    /// "Natural · Chinese · Mandarin Chinese" said where the voice is from
    /// twice; the accent says it once.
    func testDescriptorLeavesWhereAVoiceIsFromToTheAccent() {
        let mandarin = Voice(
            id: "zf_xiaoyan", name: "Xiaoyan (Mandarin)", language: "Chinese (Mandarin)",
            languageCode: "z", gender: "Female", traits: ["natural", "Chinese"], quality: "Unrated"
        )
        XCTAssertEqual(VoiceProfile(voice: mandarin).descriptor, "Natural · Mandarin Chinese")
        let british = Voice(
            id: "bf_emma", name: "Emma", language: "English (UK)",
            languageCode: "b", gender: "Female", traits: ["warm", "British"], quality: "B-"
        )
        XCTAssertEqual(VoiceProfile(voice: british).descriptor, "Warm · UK English")
        XCTAssertEqual(VoiceProfile(voice: british).traits, "Warm")
    }
}
