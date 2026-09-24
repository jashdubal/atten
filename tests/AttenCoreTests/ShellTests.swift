import AttenCore
import Foundation
import XCTest
@testable import Atten

/// The shell is three places — Library, Voices, Settings — and Create, a flow
/// over them. The risk is a place that quietly stops being reachable, or a
/// stored section from an older shell that restores to nowhere.
@MainActor
final class ShellTests: XCTestCase {

    // MARK: - Library, Voices, Settings

    func testTheSidebarHoldsOnlyLibraryVoicesAndSettings() {
        XCTAssertEqual(SidebarItem.primaryItems, [.library, .voices, .settings])
    }

    /// `@SceneStorage("Atten.selectedSection")` holds whatever raw value an
    /// earlier shell wrote. Every one of them has to land somewhere that
    /// still exists, and none of them lands in Create, which only "+ New"
    /// opens.
    func testEveryLegacyStoredSectionRestoresToADestination() {
        let expected: [String: SidebarItem] = [
            "home": .library,
            "library": .library,
            "nowPlaying": .library,
            "studio": .library,
            "playground": .library,
            "projects": .library,
            "exports": .library,
            "voices": .voices,
            "models": .settings,
            "settings": .settings,
            "": .library,
            "unknown": .library,
        ]
        for (raw, destination) in expected {
            let restored = SidebarItem.restored(raw)
            XCTAssertEqual(restored, destination, "restoring \"\(raw)\"")
            XCTAssertTrue(SidebarItem.primaryItems.contains(restored), "\"\(raw)\" restored off the sidebar")
        }
    }

    // MARK: - Create is a flow

    func testLeavingCreateReturnsToWhereItWasOpened() throws {
        let model = try makeModel()
        model.section = .voices
        model.section = .studio

        XCTAssertTrue(model.canGoBack)
        model.goBack()

        XCTAssertEqual(model.section, .voices)
    }

    func testLeavingCreateKeepsTheOpenBook() throws {
        let model = try makeModel()
        let book = UUID()
        model.openInLibrary(.book(book))
        model.section = .studio

        model.leaveCreate()

        XCTAssertEqual(model.section, .library)
        XCTAssertEqual(model.libraryPath, [.book(book)])
    }

    /// Create opened from inside Create (⌘N while drafting) must not forget
    /// where the first one came from.
    func testReopeningCreateKeepsTheOriginalOrigin() throws {
        let model = try makeModel()
        model.section = .settings
        model.section = .studio
        model.section = .studio

        model.leaveCreate()

        XCTAssertEqual(model.section, .settings)
    }

    func testAttenOpensOnLibrary() throws {
        let model = try makeModel()

        XCTAssertEqual(model.section, .library)
    }

    func testReturningToShelfFromCreateSelectsLibraryEvenWithEmptyPath() throws {
        let model = try makeModel()
        model.section = .studio
        model.returnToShelf()
        XCTAssertEqual(model.section, .library)
        XCTAssertTrue(model.libraryPath.isEmpty)
    }

    // MARK: - The route survives the sidebar

    /// The acceptance criterion this issue was written around: leaving an open
    /// book for another section and coming back returns to the book, because
    /// the route belongs to the model rather than to whichever view was on
    /// screen.
    func testLeavingAnOpenBookAndComingBackKeepsTheRoute() throws {
        let model = try makeModel()
        let book = UUID()
        model.section = .library
        model.openInLibrary(.book(book))
        model.openInLibrary(.reader(book))

        model.section = .studio
        model.section = .voices
        model.section = .library

        XCTAssertEqual(model.libraryPath, [.book(book), .reader(book)])
    }

    /// Home routes into the Library's stack rather than keeping a second one.
    func testOpeningAReaderFromHomeUsesTheLibrarysOwnRoute() throws {
        let model = try makeModel()
        let book = UUID()

        model.section = .library
        model.openInLibrary(.reader(book))

        XCTAssertEqual(model.libraryPath, [.reader(book)])
        XCTAssertTrue(model.canGoBack)
    }

    // MARK: -

    private func makeModel() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenShellTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenShellTests.\(UUID().uuidString)"))
        return AppModel(
            directories: AppDirectories(
                applicationSupport: directory.appendingPathComponent("Application Support")
            ),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
    }
}
