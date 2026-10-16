import AVFoundation
import XCTest
@testable import WhisperTranscriber

@MainActor
final class HoldToTalkTests: XCTestCase {

    private var originalHold = false
    private var originalLive = true
    private var originalAutoPaste = false
    private var originalAuthStatus = getAudioAuthStatus

    override func setUp() async throws {
        try await super.setUp()
        let settings = SettingsManager.shared
        originalHold = settings.holdToTalkEnabled
        originalLive = settings.liveTranscriptionEnabled
        originalAutoPaste = settings.autoPasteEnabled
        originalAuthStatus = getAudioAuthStatus

        settings.holdToTalkEnabled = true
        settings.liveTranscriptionEnabled = false
        settings.autoPasteEnabled = false  // never press ⌘V on the test machine
        getAudioAuthStatus = { .authorized }
    }

    override func tearDown() async throws {
        let settings = SettingsManager.shared
        settings.holdToTalkEnabled = originalHold
        settings.liveTranscriptionEnabled = originalLive
        settings.autoPasteEnabled = originalAutoPaste
        getAudioAuthStatus = originalAuthStatus
        try await super.tearDown()
    }

    /// Lets every block already queued on the main queue run, such as a pending recording start.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testPressReleasePressStartsOneRecording() async {
        let capture = FakeAudioCapture()
        let recorder = RecorderViewModel(engine: ScriptedEngine(), capture: capture, prewarm: false)

        recorder.hotkeyPressed()
        recorder.hotkeyReleased()
        recorder.hotkeyPressed()
        await drainMainQueue()

        XCTAssertEqual(capture.startCount, 1, "a second queued start must not open another capture")
        XCTAssertTrue(recorder.isRecording)

        recorder.hotkeyReleased()
        await recorder.finalizeTask?.value
    }

    func testTapReleasedBeforeStartRecordsNothing() async {
        let capture = FakeAudioCapture()
        let recorder = RecorderViewModel(engine: ScriptedEngine(), capture: capture, prewarm: false)

        recorder.hotkeyPressed()
        recorder.hotkeyReleased()
        await drainMainQueue()

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertFalse(recorder.isRecording)
    }
}
