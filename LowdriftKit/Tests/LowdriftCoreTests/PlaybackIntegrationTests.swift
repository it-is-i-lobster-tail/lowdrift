import LowdriftCore
import LowdriftDSP
import XCTest

/// Drives the real procedural renderer the way the app's AVAudioEngine output
/// does, with the render thread simulated by `pull(seconds:)`.
@MainActor
final class RenderingOutput: AudioOutput {
    let renderer = NoiseRenderer(sampleRate: 48_000, seed: 5)
    private(set) var isRunning = false
    private var stopPending = false

    func setSound(_ preset: Preset, controls: SoundControls) {
        renderer.setSound(preset.soundProfile, depth: controls.depth / 100,
                          airflow: controls.airflow / 100, hum: controls.hum / 100)
    }

    func start() throws {
        if !isRunning { renderer.prepareForRestart() }
        isRunning = true
        stopPending = false
        renderer.fadeIn()
    }

    func stop(fade: Bool) {
        renderer.fadeOut(seconds: fade ? NoiseRenderer.defaultFadeOut : NoiseRenderer.quickFadeOut)
        stopPending = true
    }

    func resetAfterSystemStop() {
        isRunning = false
        stopPending = false
    }

    /// Renders like the audio thread; stops the "engine" once a pause fade is done.
    func pull(seconds: Double) -> [Float] {
        guard isRunning else { return [] }
        var samples = [Float](repeating: 0, count: Int(seconds * 48_000))
        samples.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = min(512, buffer.count - offset)
                renderer.render(into: buffer.baseAddress! + offset, frameCount: n)
                offset += n
            }
        }
        if stopPending, !renderer.isAudible {
            isRunning = false
            stopPending = false
        }
        return samples
    }
}

@MainActor
final class PlaybackIntegrationTests: XCTestCase {
    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)).squareRoot()
    }

    nonisolated func testPlayPauseAndSelectionDriveTheRealEngine() {
        onMainActor {
            let output = RenderingOutput()
            let controller = PlaybackController(store: SettingsStore(storage: InMemoryStorage()), output: output)

            XCTAssertTrue(output.pull(seconds: 1).isEmpty, "Nothing renders before Play")

            controller.play()
            let playing = output.pull(seconds: 2)
            XCTAssertLessThan(abs(playing[0]), 1e-4, "Starts from silence")
            XCTAssertGreaterThan(rms(playing.suffix(24_000)), 0.01, "Audible after the fade-in")
            XCTAssertTrue(playing.allSatisfy { $0.isFinite && abs($0) < 0.97 })

            controller.pause()
            let pausing = output.pull(seconds: 1)
            XCTAssertTrue(pausing.suffix(4_800).allSatisfy { $0 == 0 }, "Fades to true silence")
            XCTAssertFalse(output.isRunning, "The engine stops once silent (no work while paused)")

            controller.select(.airVent)
            XCTAssertTrue(output.pull(seconds: 1).isEmpty, "Selecting while paused stays silent")
            XCTAssertFalse(controller.isPlaying)

            controller.play()
            let resumed = output.pull(seconds: 2)
            XCTAssertGreaterThan(rms(resumed.suffix(24_000)), 0.01)
            controller.select(.deepDrift)
            let crossfade = output.pull(seconds: 2)
            XCTAssertGreaterThan(rms(crossfade[0 ..< 48_000]), 0.005, "No gap while switching presets")
            XCTAssertTrue(controller.isPlaying)
        }
    }

    nonisolated func testInterruptedPlaybackRestartsFromSilence() {
        onMainActor {
            let output = RenderingOutput()
            let controller = PlaybackController(store: SettingsStore(storage: InMemoryStorage()), output: output)
            controller.play()
            _ = output.pull(seconds: 2)
            // The system stops the engine mid-signal.
            output.resetAfterSystemStop()
            controller.interruptionBegan()
            controller.interruptionEnded(shouldResume: true)
            let resumed = output.pull(seconds: 0.5)
            XCTAssertLessThan(abs(resumed[0]), 1e-4, "Resuming must fade in, not jump back to full level")
            XCTAssertGreaterThan(rms(resumed.suffix(4_800)), 0.002)
        }
    }
}
