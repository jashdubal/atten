import AttenCore
import Foundation
import XCTest
@testable import Atten

/// Going back, and leaving focus mode, used to be the business of whichever
/// view happened to be on screen — which is why they came apart the moment a
/// view was taken off screen by something other than itself.
@MainActor
final class NavigationTests: XCTestCase {
    func testGoingBackLeavesFocusModeBeforeItClosesTheBook() throws {
        let model = try makeModel()
        model.section = .library
        let book = UUID()
        model.openInLibrary(.book(book))
        model.openInLibrary(.reader(book))
        model.setReaderFocus(true)

        model.goBack()

        // The book is still open; only its surroundings came back.
        XCTAssertFalse(model.isReaderFocused)
        XCTAssertEqual(model.libraryPath, [.book(book), .reader(book)])

        model.goBack()

        XCTAssertEqual(model.libraryPath, [.book(book)])
    }

    func testGoingBackFromTheShelfDoesNothing() throws {
        let model = try makeModel()
        model.section = .library

        model.goBack()

        XCTAssertTrue(model.libraryPath.isEmpty)
        XCTAssertFalse(model.canGoBack)
    }

    func testLeavingFocusModeTwiceIsHarmless() throws {
        let model = try makeModel()
        model.setReaderFocus(true)

        model.setReaderFocus(false)
        model.setReaderFocus(false)

        XCTAssertFalse(model.isReaderFocused)
    }

    func testRepeatedFocusEntryAndExitAlwaysRestoresReaderState() throws {
        let model = try makeModel()
        model.section = .library
        let book = UUID()
        model.openInLibrary(.reader(book))

        for _ in 0..<3 {
            model.setReaderFocus(true)
            XCTAssertTrue(model.isReaderFocused)
            model.setReaderFocus(false)
            XCTAssertFalse(model.isReaderFocused)
        }

        // Focus is window chrome, not navigation. The reader route remains
        // exactly where it was after every enter/exit cycle.
        XCTAssertEqual(model.libraryPath, [.reader(book)])
    }

    func testSystemFullscreenExitRestoresFocusWithoutClosingTheBook() throws {
        let model = try makeModel()
        model.section = .library
        let book = UUID()
        model.openInLibrary(.reader(book))
        model.setReaderFocus(true)

        model.readerWindowDidExitFullScreen()

        XCTAssertFalse(model.isReaderFocused)
        XCTAssertEqual(model.libraryPath, [.reader(book)])
    }

    func testLeavingTheReaderSectionRestoresTheWindowBeforeShowingAnotherScreen() throws {
        let model = try makeModel()
        model.section = .library
        let book = UUID()
        model.openInLibrary(.reader(book))
        model.setReaderFocus(true)

        model.section = .studio

        XCTAssertFalse(model.isReaderFocused)
        XCTAssertEqual(model.section, .studio)
        XCTAssertEqual(model.libraryPath, [.reader(book)])
    }

    func testOpeningNowPlayingFromFocusRestoresTheShell() throws {
        let model = try makeModel()
        model.section = .library
        model.openInLibrary(.reader(UUID()))
        model.setReaderFocus(true)

        model.openNowPlaying()

        XCTAssertFalse(model.isReaderFocused)
        XCTAssertEqual(model.section, .nowPlaying)
    }

    func testOpeningTheScreenAlreadyOpenDoesNotStackIt() throws {
        let model = try makeModel()
        model.section = .library
        let book = UUID()

        model.openInLibrary(.book(book))
        model.openInLibrary(.book(book))

        XCTAssertEqual(model.libraryPath, [.book(book)])
    }

    /// A book can be removed while it is open, and a screen about a book that
    /// no longer exists is nowhere to leave someone.
    func testReturningToTheShelfClearsTheWholePath() throws {
        let model = try makeModel()
        model.section = .library
        let book = UUID()
        model.openInLibrary(.book(book))
        model.openInLibrary(.reader(book))
        model.setReaderFocus(true)

        model.returnToShelf()

        XCTAssertTrue(model.libraryPath.isEmpty)
        XCTAssertFalse(model.canGoBack)
        XCTAssertFalse(model.isReaderFocused)
    }

    /// Only the Library stacks screens. Pressing back anywhere else must not
    /// quietly unwind a Library the user cannot even see.
    func testBackDoesNothingOutsideTheLibrary() throws {
        let model = try makeModel()
        model.section = .library
        let book = UUID()
        model.openInLibrary(.book(book))

        model.section = .studio

        XCTAssertFalse(model.canGoBack)
        model.goBack()
        XCTAssertEqual(model.libraryPath, [.book(book)])
    }

    func testNowPlayingIsAReachableRouteWithoutChangingTheLibraryPath() throws {
        let model = try makeModel()
        let book = UUID()
        model.section = .library
        model.openInLibrary(.reader(book))

        model.openNowPlaying()

        XCTAssertEqual(model.section, .nowPlaying)
        XCTAssertEqual(model.libraryPath, [.reader(book)])
    }

    private func makeModel() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttenNavTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AttenNavTests.\(UUID().uuidString)"))
        return AppModel(
            directories: AppDirectories(
                applicationSupport: directory.appendingPathComponent("Application Support")
            ),
            settingsStore: SettingsStore(defaults: defaults),
            generator: ImmediateGenerator()
        )
    }
}
