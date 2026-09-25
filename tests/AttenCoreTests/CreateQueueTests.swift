import AttenCore
import Foundation
import XCTest
@testable import Atten

/// Generate in Create while another book narrates: the draft joins the
/// narration queue instead of being refused.
@MainActor
final class CreateQueueTests: XCTestCase {
    private var root: URL!
    private var suite: String!
    private var generator: GatedGenerator!
    private var model: AppModel!

    private var flow: CreateFlowModel { model.createFlow }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AttenCreateQueue-\(UUID().uuidString)")
        suite = "AttenCreateQueueTests.\(UUID().uuidString)"
        generator = GatedGenerator()
        model = AppModel(
            directories: AppDirectories(applicationSupport: root),
            settingsStore: SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite))),
            generator: generator
        )
        model.settings.defaultFormat = .wav
        await model.bookshelf.load()
    }

    override func tearDown() async throws {
        generator.open()
        try? await model.bookshelf.stopAndSave()
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testGenerateWhileAnotherNarratesQueuesTheDraft() async throws {
        let running = try model.bookshelf.saveDraft(
            title: "Running", text: "Already narrating.", voiceID: "af_heart", defaults: model.settings
        )
        model.bookshelf.narrate(running.id, useMPS: false)
        XCTAssertEqual(model.bookshelf.narratingBookID, running.id)

        model.section = .studio
        flow.text = "# One\n\nThe first part.\n\n# Two\n\nThe second part."
        XCTAssertNil(flow.generateDisabledReason)
        XCTAssertTrue(flow.canGenerate)
        flow.generate()

        let draftID = try XCTUnwrap(flow.draftID)
        XCTAssertEqual(flow.state, .queued)
        XCTAssertEqual(flow.queuePosition, 1)
        XCTAssertEqual(model.bookshelf.queue.map(\.bookID), [running.id, draftID])
        XCTAssertNil(flow.failure)
        XCTAssertFalse(flow.canGenerate, "A queued draft is not generated twice")
        // Queued with the chapters Create divided it into, and kept that way.
        XCTAssertEqual(model.bookshelf.book(id: draftID)?.chapters.map(\.title), ["One", "Two"])
        flow.saveNow()
        XCTAssertEqual(model.bookshelf.book(id: draftID)?.chapters.map(\.title), ["One", "Two"])

        // Its turn comes once the running narration ends.
        generator.open()
        try await waitUntil { !self.model.bookshelf.isNarrating && self.model.bookshelf.queue.isEmpty }
        XCTAssertTrue(try XCTUnwrap(model.bookshelf.book(id: draftID)).isFullyNarrated)
        XCTAssertEqual(flow.state, .done)
        XCTAssertEqual(flow.toastBookID, draftID)
    }

    func testTheQueuedPositionCountsOnlyWhatIsWaiting() throws {
        let running = try model.bookshelf.saveDraft(title: "Running", text: "One.", voiceID: "af_heart", defaults: model.settings)
        let waiting = try model.bookshelf.saveDraft(title: "Waiting", text: "Two.", voiceID: "af_heart", defaults: model.settings)
        model.bookshelf.narrate(running.id, useMPS: false)
        model.bookshelf.narrate(waiting.id, useMPS: false)

        flow.text = "Third in line."
        flow.generate()
        XCTAssertEqual(flow.state, .queued)
        XCTAssertEqual(flow.queuePosition, 2)

        model.bookshelf.removeFromQueue(waiting.id)
        XCTAssertEqual(flow.queuePosition, 1)
        model.bookshelf.pauseNarration(try XCTUnwrap(flow.draftID))
        XCTAssertTrue(flow.isQueuePaused)
        XCTAssertEqual(flow.state, .queued)
    }

    func testRemovingFromTheQueueReturnsToEditing() throws {
        let running = try model.bookshelf.saveDraft(title: "Running", text: "One.", voiceID: "af_heart", defaults: model.settings)
        model.bookshelf.narrate(running.id, useMPS: false)
        flow.text = "Changed my mind."
        flow.generate()
        let draftID = try XCTUnwrap(flow.draftID)
        XCTAssertEqual(flow.state, .queued)

        flow.removeFromQueue()
        XCTAssertEqual(flow.state, .editing)
        XCTAssertNil(flow.queuePosition)
        XCTAssertFalse(model.bookshelf.isQueued(draftID))
        XCTAssertEqual(model.bookshelf.narratingBookID, running.id, "The running narration is left alone")
        XCTAssertNotNil(model.bookshelf.book(id: draftID), "The draft stays on the shelf")
        XCTAssertTrue(flow.canGenerate)
    }

    func testSomethingOtherThanNarrationHoldingTheEngineStillBlocksGenerate() throws {
        let lease = try XCTUnwrap(model.synthesis.acquire("Previewing"))
        defer { model.synthesis.release(lease) }
        flow.text = "Wait for the preview."
        XCTAssertEqual(flow.generateDisabledReason, "Another narration is running")
        XCTAssertFalse(flow.canGenerate)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting")
    }
}
