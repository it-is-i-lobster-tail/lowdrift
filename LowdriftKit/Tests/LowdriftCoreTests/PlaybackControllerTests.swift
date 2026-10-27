import LowdriftCore
import XCTest

/// Records what the controller asks of the engine.
@MainActor
final class FakeOutput: AudioOutput {
    var isRunning = false
    var nextStartError: Error?
    private(set) var sound: (preset: Preset, controls: SoundControls)?
    private(set) var startCount = 0
    private(set) var stops: [Bool] = []
    private(set) var resetCount = 0

    func setSound(_ preset: Preset, controls: SoundControls) { sound = (preset, controls) }

    func start() throws {
        if let error = nextStartError {
            nextStartError = nil
            throw error
        }
        startCount += 1
        isRunning = true
    }

    func stop(fade: Bool) {
        stops.append(fade)
        isRunning = false
    }

    func resetAfterSystemStop() {
        resetCount += 1
        isRunning = false
    }
}

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private var storage = InMemoryStorage()
    private var output = FakeOutput()

    override func setUp() async throws {
        storage = InMemoryStorage()
        output = await FakeOutput()
    }

    private func makeController() -> PlaybackController {
        PlaybackController(store: SettingsStore(storage: storage), output: output)
    }

    func testFreshInstallOpensOnBasementACPaused() {
        let controller = makeController()
        XCTAssertEqual(controller.selectedPreset, .basementAC)
        XCTAssertEqual(controller.controls, Preset.basementAC.defaultControls)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isCustomized)
        XCTAssertEqual(output.startCount, 0, "Opening the app must never start audio")
        XCTAssertEqual(output.sound?.preset, .basementAC, "The engine is primed with the selected sound")
    }

    func testRelaunchRestoresLastPresetButStaysPaused() {
        let first = makeController()
        first.select(.airVent)
        first.setDepth(12)
        first.play()
        XCTAssertTrue(first.isPlaying)

        output = FakeOutput()
        let relaunched = makeController()
        XCTAssertEqual(relaunched.selectedPreset, .airVent)
        XCTAssertEqual(relaunched.controls.depth, 12)
        XCTAssertFalse(relaunched.isPlaying, "Playback never resumes on a cold launch")
        XCTAssertEqual(output.startCount, 0)
    }

    func testPlayAndPause() {
        let controller = makeController()
        var notifications = 0
        controller.onStateChange = { notifications += 1 }
        controller.play()
        XCTAssertTrue(controller.isPlaying)
        XCTAssertTrue(output.isRunning)
        controller.pause()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(output.stops, [true], "Pause fades out")
        controller.togglePlayback()
        XCTAssertTrue(controller.isPlaying)
        controller.togglePlayback()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(notifications, 4)
    }

    func testSelectingWhilePausedStaysPaused() {
        let controller = makeController()
        controller.select(.softFan)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(output.startCount, 0)
        XCTAssertEqual(output.sound?.preset, .softFan)
        XCTAssertEqual(output.sound?.controls, Preset.softFan.defaultControls)
    }

    func testSelectingWhilePlayingKeepsPlaying() {
        let controller = makeController()
        controller.play()
        controller.select(.towerFan)
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(output.startCount, 1, "The engine keeps running and crossfades")
        XCTAssertEqual(output.stops, [])
        XCTAssertEqual(output.sound?.preset, .towerFan)
    }

    func testSlidersApplyLiveAndPersistPerPreset() {
        let controller = makeController()
        controller.play()
        controller.setDepth(10)
        controller.setAirflow(90)
        controller.setHum(0)
        XCTAssertEqual(output.sound?.controls, SoundControls(depth: 10, airflow: 90, hum: 0))
        XCTAssertTrue(controller.isCustomized)

        controller.select(.boxFan)
        XCTAssertEqual(controller.controls, Preset.boxFan.defaultControls, "Edits belong to one preset")
        controller.select(.basementAC)
        XCTAssertEqual(controller.controls, SoundControls(depth: 10, airflow: 90, hum: 0))

        let reopened = SettingsStore(storage: storage)
        XCTAssertEqual(reopened.controls(for: .basementAC), SoundControls(depth: 10, airflow: 90, hum: 0))
    }

    func testResetRestoresOnlyTheSelectedPreset() {
        let controller = makeController()
        controller.select(.boxFan)
        controller.setHum(100)
        controller.select(.deepDrift)
        controller.setDepth(0)
        controller.resetToDefault()
        XCTAssertEqual(controller.controls, Preset.deepDrift.defaultControls)
        XCTAssertEqual(output.sound?.controls, Preset.deepDrift.defaultControls, "Reset is audible at once")
        XCTAssertFalse(controller.isCustomized)
        controller.select(.boxFan)
        XCTAssertEqual(controller.controls.hum, 100)
    }

    func testStartFailureIsReportedHonestlyAndRetryWorks() {
        let controller = makeController()
        output.nextStartError = PlaybackFailure.audioBusy
        controller.play()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.failure, .audioBusy)

        controller.retry()
        XCTAssertTrue(controller.isPlaying)
        XCTAssertNil(controller.failure)

        struct Unexpected: Error {}
        controller.pause()
        output.nextStartError = Unexpected()
        controller.play()
        XCTAssertEqual(controller.failure, .couldNotStart)
        XCTAssertFalse(controller.isPlaying)
    }

    func testSettingsSurviveAudioFailure() {
        let controller = makeController()
        output.nextStartError = PlaybackFailure.couldNotStart
        controller.play()
        controller.setAirflow(3)
        XCTAssertEqual(SettingsStore(storage: storage).controls(for: .basementAC).airflow, 3)
    }

    func testInterruptionResumesOnlyWhenAllowedAndWasPlaying() {
        let controller = makeController()
        controller.play()
        controller.interruptionBegan()
        XCTAssertFalse(controller.isPlaying)
        controller.interruptionEnded(shouldResume: true)
        XCTAssertTrue(controller.isPlaying)

        controller.interruptionBegan()
        controller.interruptionEnded(shouldResume: false)
        XCTAssertFalse(controller.isPlaying, "No resume without the system's go-ahead")
        controller.interruptionEnded(shouldResume: true)
        XCTAssertFalse(controller.isPlaying, "A stale interruption cannot resume later")
    }

    func testInterruptionNeverStartsAudioTheUserPaused() {
        let controller = makeController()
        controller.interruptionBegan()
        controller.interruptionEnded(shouldResume: true)
        XCTAssertFalse(controller.isPlaying)

        controller.play()
        controller.interruptionBegan()
        controller.pause()
        controller.interruptionEnded(shouldResume: true)
        XCTAssertFalse(controller.isPlaying, "Pausing during an interruption wins")
        XCTAssertEqual(output.startCount, 1)
    }

    func testHeadphonesRemovedPauses() {
        let controller = makeController()
        controller.play()
        controller.outputRouteLost()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(output.stops, [false], "Quick fade, not a long tail on the speaker")
        controller.interruptionEnded(shouldResume: true)
        XCTAssertFalse(controller.isPlaying)
    }

    func testEngineConfigurationChangeRestartsOnlyIfPlaying() {
        let controller = makeController()
        controller.engineConfigurationChanged()
        XCTAssertEqual(output.resetCount, 1)
        XCTAssertEqual(output.startCount, 0)

        controller.play()
        controller.engineConfigurationChanged()
        XCTAssertEqual(output.resetCount, 2)
        XCTAssertEqual(output.startCount, 2)
        XCTAssertTrue(controller.isPlaying)

        output.nextStartError = PlaybackFailure.couldNotStart
        controller.mediaServicesWereReset()
        XCTAssertFalse(controller.isPlaying, "A failed restart must not claim playback")
        XCTAssertEqual(controller.failure, .couldNotStart)
    }

    func testReconcileReflectsTheRealEngineState() {
        let controller = makeController()
        controller.play()
        controller.reconcile()
        XCTAssertTrue(controller.isPlaying)

        output.isRunning = false
        controller.reconcile()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.failure, .stoppedUnexpectedly)
        controller.dismissFailure()
        XCTAssertNil(controller.failure)
    }

    func testRapidTappingStaysConsistent() {
        let controller = makeController()
        for i in 0 ..< 500 {
            switch i % 5 {
            case 0: controller.togglePlayback()
            case 1: controller.select(Preset.allCases[i % 6])
            case 2: controller.setDepth(Double(i % 101))
            case 3: controller.togglePlayback()
            default: controller.select(Preset.allCases[(i / 5) % 6])
            }
            XCTAssertEqual(controller.isPlaying, output.isRunning)
        }
    }
}
