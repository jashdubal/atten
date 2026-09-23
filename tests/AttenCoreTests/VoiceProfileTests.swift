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
    }
}
