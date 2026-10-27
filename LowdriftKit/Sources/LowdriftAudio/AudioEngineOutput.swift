#if os(iOS)
import AVFoundation
import LowdriftCore
import LowdriftDSP

/// Plays the procedural renderer through AVAudioEngine.
///
/// The engine only runs while sound is wanted: after a pause fade finishes it is
/// stopped, so a paused Lowdrift does no audio work at all. The graph is a single
/// source node at the hardware sample rate feeding the main mixer. It carries the
/// mono sound on both channels (or one, on a mono route).
@MainActor
public final class AudioEngineOutput: AudioOutput {
    private let session = AVAudioSession.sharedInstance()
    private let renderer: NoiseRenderer
    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var graphSampleRate: Double = 0
    private var graphChannels: AVAudioChannelCount = 0
    private var categoryConfigured = false
    private var stopTask: Task<Void, Never>?

    public init() {
        renderer = NoiseRenderer(sampleRate: AVAudioSession.sharedInstance().sampleRate)
    }

    public var isRunning: Bool { engine.isRunning }

    public func setSound(_ preset: Preset, controls: SoundControls) {
        renderer.setSound(
            preset.soundProfile,
            depth: controls.depth / 100,
            airflow: controls.airflow / 100,
            hum: controls.hum / 100
        )
    }

    public func start() throws {
        stopTask?.cancel()
        stopTask = nil
        if engine.isRunning {
            // Resuming during a pause fade: simply fade back in.
            renderer.fadeIn()
            return
        }
        try activateSession()
        updateRoute()
        try buildGraphIfNeeded()
        // The engine is stopped, so the renderer may hold state from an abrupt
        // stop; always begin from silence.
        renderer.prepareForRestart()
        renderer.fadeIn()
        do {
            engine.prepare()
            try engine.start()
        } catch {
            renderer.fadeOut(seconds: NoiseRenderer.quickFadeOut)
            throw PlaybackFailure.couldNotStart
        }
    }

    public func stop(fade: Bool) {
        stopTask?.cancel()
        let seconds = fade ? NoiseRenderer.defaultFadeOut : NoiseRenderer.quickFadeOut
        renderer.fadeOut(seconds: seconds)
        guard engine.isRunning else {
            stopTask = nil
            return
        }
        stopTask = Task { [weak self] in
            // Let the render thread finish the fade, then stop the engine.
            try? await Task.sleep(nanoseconds: UInt64((Double(seconds) + 0.15) * 1_000_000_000))
            for _ in 0 ..< 10 {
                guard !Task.isCancelled, let self else { return }
                if !self.renderer.isAudible { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            self.engine.stop()
            self.stopTask = nil
        }
    }

    public func resetAfterSystemStop() {
        stopTask?.cancel()
        stopTask = nil
        resetEngine()
        // A media services reset invalidates the session configuration too.
        categoryConfigured = false
    }

    /// Lets the renderer know whether sound is coming from the phone's built-in
    /// speaker, so it can leave out deep bass that the speaker cannot reproduce.
    public func updateRoute() {
        let speaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        renderer.setCompactSpeaker(speaker)
    }

    // MARK: - Private

    private func activateSession() throws {
        do {
            if !categoryConfigured {
                try session.setCategory(.playback, mode: .default, options: [])
                // Large hardware buffers mean fewer wake-ups overnight; latency
                // only affects how quickly a slider move is heard (~50 ms).
                try? session.setPreferredIOBufferDuration(0.05)
                categoryConfigured = true
            }
            try session.setActive(true)
        } catch {
            throw Self.failure(for: error)
        }
    }

    private func buildGraphIfNeeded() throws {
        var hardware = engine.outputNode.outputFormat(forBus: 0)
        if sourceNode != nil, hardware.sampleRate == graphSampleRate,
           ProceduralSource.channelCount(forOutputChannels: hardware.channelCount) == graphChannels {
            return
        }
        if sourceNode != nil {
            // The hardware format changed while stopped: start over with a fresh engine.
            resetEngine()
            hardware = engine.outputNode.outputFormat(forBus: 0)
        }
        let rate = hardware.sampleRate > 0 ? hardware.sampleRate : session.sampleRate
        let channels = ProceduralSource.channelCount(forOutputChannels: hardware.channelCount)
        renderer.setSampleRate(rate)
        guard let node = ProceduralSource.makeNode(renderer: renderer, sampleRate: rate, channels: channels) else {
            throw PlaybackFailure.couldNotStart
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: node.outputFormat(forBus: 0))
        sourceNode = node
        graphSampleRate = rate
        graphChannels = channels
    }

    private func resetEngine() {
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
        }
        sourceNode = nil
        graphSampleRate = 0
        graphChannels = 0
        engine = AVAudioEngine()
        renderer.prepareForRestart()
    }

    private static func failure(for error: Error) -> PlaybackFailure {
        let code = (error as NSError).code
        let busy: [AVAudioSession.ErrorCode] = [.isBusy, .cannotInterruptOthers, .insufficientPriority]
        return busy.contains { $0.rawValue == code } ? .audioBusy : .couldNotStart
    }
}
#endif
