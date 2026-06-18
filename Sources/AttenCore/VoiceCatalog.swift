import Foundation

public enum VoiceCatalog {
    public static let all: [Voice] = [
        voice("af_heart", "Heart", "English (US)", "a", "Female", ["warm", "expressive"], "A"),
        voice("af_bella", "Bella", "English (US)", "a", "Female", ["bright", "confident"], "A-"),
        voice("af_nicole", "Nicole", "English (US)", "a", "Female", ["calm", "studio"], "B-"),
        voice("af_aoede", "Aoede", "English (US)", "a", "Female", ["clear"], "C+"),
        voice("af_kore", "Kore", "English (US)", "a", "Female", ["clear"], "C+"),
        voice("af_sarah", "Sarah", "English (US)", "a", "Female", ["natural"], "C+"),
        voice("af_alloy", "Alloy", "English (US)", "a", "Female", ["balanced"], "C"),
        voice("af_nova", "Nova", "English (US)", "a", "Female", ["bright"], "C"),
        voice("af_sky", "Sky", "English (US)", "a", "Female", ["light"], "C-"),
        voice("af_river", "River", "English (US)", "a", "Female", ["soft"], "D"),
        voice("af_jessica", "Jessica", "English (US)", "a", "Female", ["conversational"], "D"),
        voice("am_fenrir", "Fenrir", "English (US)", "a", "Male", ["grounded"], "C+"),
        voice("am_michael", "Michael", "English (US)", "a", "Male", ["natural"], "C+"),
        voice("am_puck", "Puck", "English (US)", "a", "Male", ["playful"], "C+"),
        voice("am_echo", "Echo", "English (US)", "a", "Male", ["steady"], "D"),
        voice("am_eric", "Eric", "English (US)", "a", "Male", ["direct"], "D"),
        voice("am_liam", "Liam", "English (US)", "a", "Male", ["soft"], "D"),
        voice("am_onyx", "Onyx", "English (US)", "a", "Male", ["deep"], "D"),
        voice("am_santa", "Santa", "English (US)", "a", "Male", ["character"], "D-"),
        voice("am_adam", "Adam", "English (US)", "a", "Male", ["plainspoken"], "F+"),
        voice("bf_emma", "Emma", "English (UK)", "b", "Female", ["warm", "British"], "B-"),
        voice("bf_isabella", "Isabella", "English (UK)", "b", "Female", ["bright", "British"], "C"),
        voice("bf_alice", "Alice", "English (UK)", "b", "Female", ["gentle", "British"], "D"),
        voice("bf_lily", "Lily", "English (UK)", "b", "Female", ["light", "British"], "D"),
        voice("bm_fable", "Fable", "English (UK)", "b", "Male", ["storytelling", "British"], "C"),
        voice("bm_george", "George", "English (UK)", "b", "Male", ["steady", "British"], "C"),
        voice("bm_lewis", "Lewis", "English (UK)", "b", "Male", ["conversational", "British"], "D+"),
        voice("bm_daniel", "Daniel", "English (UK)", "b", "Male", ["direct", "British"], "D"),
        voice("ef_dora", "Dora", "Spanish", "e", "Female", ["Spanish"], "Unrated"),
        voice("em_alex", "Alex", "Spanish", "e", "Male", ["Spanish"], "Unrated"),
        voice("em_santa", "Santa", "Spanish", "e", "Male", ["character", "Spanish"], "Unrated"),
        voice("ff_siwis", "Siwis", "French", "f", "Female", ["clear", "French"], "B-"),
        voice("if_sara", "Sara", "Italian", "i", "Female", ["warm", "Italian"], "C"),
        voice("im_nicola", "Nicola", "Italian", "i", "Male", ["steady", "Italian"], "C"),
        voice("pf_dora", "Dora", "Portuguese (Brazil)", "p", "Female", ["Brazilian"], "Unrated"),
        voice("pm_alex", "Alex", "Portuguese (Brazil)", "p", "Male", ["Brazilian"], "Unrated"),
        voice("pm_santa", "Santa", "Portuguese (Brazil)", "p", "Male", ["character", "Brazilian"], "Unrated"),
    ]

    public static func voice(id: String) -> Voice? {
        all.first { $0.id == id }
    }

    private static func voice(
        _ id: String,
        _ name: String,
        _ language: String,
        _ languageCode: String,
        _ gender: String,
        _ traits: [String],
        _ quality: String
    ) -> Voice {
        Voice(
            id: id,
            name: name,
            language: language,
            languageCode: languageCode,
            gender: gender,
            traits: traits,
            quality: quality
        )
    }
}
