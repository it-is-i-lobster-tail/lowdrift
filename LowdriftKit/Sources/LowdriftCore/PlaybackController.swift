import Foundation
import Observation

/// The sound engine as the playback controller sees it. The app implements it
/// with AVAudioEngine; tests use fakes. Every call happens on the main actor,
/// and implementations pass values to the render thread with atomics only.
@MainActor
public protocol AudioOutput: AnyObject {
    /// True while the engine is running (including a pause fade that has not
    /// finished yet). False once it has stopped, or after the system stopped it.
    var isRunning: Bool { get }

    /// Sets the sound to generate. While audible, the output glides to new control
    /// values and crossfades to a new preset.
    func setSound(_ preset: Preset, controls: SoundControls)

    /// Activates the audio session if needed, starts the engine and fades in.
    func start() throws

    /// Fades to silence and then stops the engine and releases the audio session.
    /// `fade: false` uses a very short fade (headphones removed, interruptions).
    func stop(fade: Bool)

    /// Rebuilds the engine after the system stopped it underneath us (hardware
    /// configuration change, media services reset). Leaves it stopped.
    func resetAfterSystemStop()
}

/// Why audio could not start or keep running, in words a person can act on.
public enum PlaybackFailure: Error, Equatable, Sendable {
    /// Another app or a call holds the audio hardware.
    case audioBusy
    /// The engine or audio session failed to start.
    case couldNotStart
    /// Playback stopped without the user asking (e.g. after a system audio reset).
    case stoppedUnexpectedly

    public var message: String {
        switch self {
        case .audioBusy: return "Audio is in use by another app or a call."
        case .couldNotStart: return "Lowdrift couldn’t start audio."
        case .stoppedUnexpectedly: return "Playback stopped unexpectedly."
        }
    }
}

/// The single source of truth for what is selected and whether sound is playing.
///
/// `isPlaying` is only true after the engine actually started, so the Play/Pause
/// button, Now Playing and Shortcuts always reflect real engine state rather
/// than an optimistic guess.
@MainActor
@Observable
public final class PlaybackController {
    public private(set) var selectedPreset: Preset
    /// Control values of the selected preset (0–100).
    public private(set) var controls: SoundControls
    public private(set) var isPlaying = false
    /// A short, human-readable problem to show inline with a Retry action.
    public private(set) var failure: PlaybackFailure?

    /// Called after play state or the selected preset changes (drives Now Playing).
    @ObservationIgnored public var onStateChange: (() -> Void)?

    private let store: SettingsStore
    private let output: AudioOutput
    /// Set when an interruption stopped audio the user was listening to.
    @ObservationIgnored private var resumeAfterInterruption = false

    public init(store: SettingsStore, output: AudioOutput) {
        self.store = store
        self.output = output
        let preset = store.selectedPreset
        selectedPreset = preset
        controls = store.controls(for: preset)
        output.setSound(preset, controls: controls)
    }

    /// True when the selected preset has been changed from its shipping values.
    public var isCustomized: Bool { controls != selectedPreset.defaultControls }

    // MARK: - User actions

    public func play() {
        resumeAfterInterruption = false
        startOutput()
    }

    public func pause() {
        resumeAfterInterruption = false
        stopOutput(fade: true)
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    /// Selects a preset. If playing, the sound crossfades; if paused, it stays paused.
    public func select(_ preset: Preset) {
        guard preset != selectedPreset else { return }
        selectedPreset = preset
        store.selectedPreset = preset
        controls = store.controls(for: preset)
        output.setSound(preset, controls: controls)
        onStateChange?()
    }

    public func setDepth(_ value: Double) { updateControls { $0.depth = value } }
    public func setAirflow(_ value: Double) { updateControls { $0.airflow = value } }
    public func setHum(_ value: Double) { updateControls { $0.hum = value } }

    /// Restores the selected preset's shipping values (only that preset).
    public func resetToDefault() {
        store.resetControls(for: selectedPreset)
        controls = selectedPreset.defaultControls
        output.setSound(selectedPreset, controls: controls)
    }

    public func retry() {
        failure = nil
        play()
    }

    public func dismissFailure() {
        failure = nil
    }

    // MARK: - System events

    /// A call, Siri, an alarm or another app took the audio session. The system
    /// has already silenced the engine.
    public func interruptionBegan() {
        guard isPlaying else { return }
        resumeAfterInterruption = true
        output.stop(fade: false)
        isPlaying = false
        onStateChange?()
    }

    /// Resumes only if the system says so and the user was listening before.
    public func interruptionEnded(shouldResume: Bool) {
        let resume = resumeAfterInterruption && shouldResume
        resumeAfterInterruption = false
        if resume { startOutput() }
    }

    /// The route the sound was playing on went away (headphones unplugged,
    /// Bluetooth disconnected). Pause instead of switching to the speaker.
    public func outputRouteLost() {
        guard isPlaying else { return }
        resumeAfterInterruption = false
        stopOutput(fade: false)
    }

    /// The engine stopped itself because the audio hardware changed (for example
    /// a new sample rate). Rebuild, and carry on if the user was listening.
    public func engineConfigurationChanged() {
        output.resetAfterSystemStop()
        if isPlaying { startOutput() }
    }

    /// The system's media services restarted; every audio object is invalid.
    public func mediaServicesWereReset() {
        output.resetAfterSystemStop()
        if isPlaying { startOutput() }
    }

    /// Brings the UI back in line with the engine (on returning to the foreground).
    public func reconcile() {
        guard isPlaying, !output.isRunning else { return }
        isPlaying = false
        failure = .stoppedUnexpectedly
        onStateChange?()
    }

    // MARK: - Private

    private func updateControls(_ change: (inout SoundControls) -> Void) {
        var next = controls
        change(&next)
        guard next != controls else { return }
        controls = next
        store.setControls(next, for: selectedPreset)
        output.setSound(selectedPreset, controls: next)
    }

    private func startOutput() {
        output.setSound(selectedPreset, controls: controls)
        do {
            try output.start()
            isPlaying = true
            failure = nil
        } catch {
            isPlaying = false
            failure = (error as? PlaybackFailure) ?? .couldNotStart
        }
        onStateChange?()
    }

    private func stopOutput(fade: Bool) {
        guard isPlaying || output.isRunning else { return }
        output.stop(fade: fade)
        let changed = isPlaying
        isPlaying = false
        if changed { onStateChange?() }
    }
}
