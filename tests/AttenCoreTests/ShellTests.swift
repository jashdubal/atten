import AttenCore
import Foundation
import XCTest
@testable import Atten

/// The shell gained a Home destination and put its sections into groups. The
/// risk in both is the same: a destination that quietly stops being reachable
/// because it fell out of a list somebody re-ordered.
@MainActor
final class ShellTests: XCTestCase {

    // MARK: - Every destination stays reachable

    /// The grouped sidebar draws from `Group.items`, not from `allCases`, so
    /// a destination added to the enum and forgotten in a group would compile,
    /// ship, and simply not exist.
    func testEveryDestinationAppearsInExactlyOneSidebarGroup() {
        let grouped = SidebarItem.Group.allCases.flatMap(\.items)

        XCTAssertEqual(
            Set(grouped), Set(SidebarItem.allCases),
            "a destination is missing from the sidebar, or one is in it twice"
        )
        XCTAssertEqual(
            grouped.count, SidebarItem.allCases.count,
            "a destination appears in more than one group"
        )
    }

    /// Everything Atten could reach before this issue it can still reach.
    func testTheDestinationsThatExistedBeforeStillExist() {
        let before: Set<SidebarItem> = [
            .studio, .playground, .library, .voices, .models, .projects, .exports,
        ]

        XCTAssertTrue(
            before.isSubset(of: Set(SidebarItem.allCases)),
            "the shell dropped a destination that used to be reachable"
        )
    }

    /// Arrow keys walk the sidebar with `allCases`, and the sidebar draws with
    /// groups. If those two orders disagree, keyboard focus jumps around the
    /// list instead of moving down it.
    func testKeyboardOrderMatchesTheOrderOnScreen() {
        XCTAssertEqual(
            SidebarItem.Group.allCases.flatMap(\.items),
            SidebarItem.allCases,
            "arrow-key order and visual order have come apart"
        )
    }

    func testAttenOpensOnHome() throws {
        let model = try makeModel()

        XCTAssertEqual(model.section, .home)
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
        model.section = .home
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
