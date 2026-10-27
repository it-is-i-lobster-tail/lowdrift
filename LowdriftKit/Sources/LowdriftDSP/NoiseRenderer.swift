import Foundation
import LDAtomics

/// Procedural fan / airflow / HVAC sound generator.
///
/// Threading model:
/// - The control methods (`setSound`, `fadeIn`, `fadeOut`, …) may be called from
///   any non-real-time thread. They only write 32-bit words with atomic stores.
/// - `render(into:frameCount:)` must be called from a single real-time thread
///   (the AVAudioSourceNode render block). It never allocates, locks, logs,
///   blocks, or touches the main thread; it reads the control words once per
///   callback and keeps all DSP state inline.
public final class NoiseRenderer: @unchecked Sendable {
    private let control = ControlWords()
    private var core: RenderCore

    /// - Parameters:
    ///   - sampleRate: Initial hardware rate. Update with `setSampleRate` on route changes.
    ///   - characters: One character per `SoundProfile`, in `SoundProfile` order.
    ///   - seed: Fixed seed for reproducible tests; random by default.
    public init(
        sampleRate: Double,
        characters: [SoundCharacter] = SoundProfile.allCases.map(\.character),
        seed: UInt64? = nil
    ) {
        precondition(characters.count == SoundProfile.allCases.count, "One character per profile")
        let resolvedSeed = seed ?? UInt64.random(in: 1 ... UInt64.max)
        let rate = Float(Self.sanitizedSampleRate(sampleRate))
        core = RenderCore(sampleRate: rate, characters: characters, seed: resolvedSeed, control: control)
        control.storeFloat(rate, .sampleRate)
        control.storeFloat(0.5, .depth)
        control.storeFloat(0.5, .airflow)
        control.storeFloat(0, .hum)
        control.store(UInt32(SoundProfile.basementAC.rawValue), .profile)
        control.storeFloat(Self.defaultFadeIn, .fadeInSeconds)
        control.storeFloat(Self.defaultFadeOut, .fadeOutSeconds)
        control.bumpVersion()
    }

    // Computed constants rather than stored globals, so the render thread never
    // triggers lazy global initialisation.
    public static var defaultFadeIn: Float { 1.1 }
    public static var defaultFadeOut: Float { 0.6 }
    public static var quickFadeOut: Float { 0.06 }
    /// Length of the equal-power crossfade between presets.
    public static var crossfadeSeconds: Float { 1.4 }

    // MARK: - Control (any non-real-time thread)

    /// Sets the sound to generate. Controls are 0…1. If audible, the change glides
    /// (same profile) or crossfades (new profile); if silent it applies instantly.
    public func setSound(_ profile: SoundProfile, depth: Double, airflow: Double, hum: Double) {
        control.store(UInt32(profile.rawValue), .profile)
        control.storeFloat(Float(depth), .depth)
        control.storeFloat(Float(airflow), .airflow)
        control.storeFloat(Float(hum), .hum)
        control.bumpVersion()
    }

    /// Tells the renderer the actual hardware sample rate. Call while the engine is stopped.
    public func setSampleRate(_ sampleRate: Double) {
        control.storeFloat(Float(Self.sanitizedSampleRate(sampleRate)), .sampleRate)
        control.bumpVersion()
    }

    /// Removes deep sub-bass that a phone's built-in speaker cannot reproduce, so
    /// the system's speaker protection is never driven by inaudible energy.
    public func setCompactSpeaker(_ isCompact: Bool) {
        control.store(isCompact ? 1 : 0, .compactSpeaker)
        control.bumpVersion()
    }

    /// Starts (or resumes) a smooth fade toward full level.
    public func fadeIn(seconds: Float = NoiseRenderer.defaultFadeIn) {
        control.storeFloat(seconds, .fadeInSeconds)
        control.store(1, .playing)
        control.bumpVersion()
    }

    /// Starts a smooth fade to silence. `isAudible` turns false once it completes.
    public func fadeOut(seconds: Float = NoiseRenderer.defaultFadeOut) {
        control.storeFloat(seconds, .fadeOutSeconds)
        control.store(0, .playing)
        control.bumpVersion()
    }

    /// The next render starts from silence (call before restarting an engine that
    /// was stopped abruptly, e.g. by an interruption or a configuration change).
    public func prepareForRestart() {
        control.bumpStartGeneration()
    }

    /// True while the renderer outputs signal (including fades). Written by the
    /// render thread; safe to read anywhere.
    public var isAudible: Bool { control.load(.audible) != 0 }

    // MARK: - Render (real-time thread only)

    /// Fills `buffer` with `frameCount` mono samples. Returns true when the
    /// buffer is pure silence (lets the caller set AVAudioSourceNode's isSilence).
    @discardableResult
    public func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        core.render(into: buffer, frameCount: frameCount)
    }

    // MARK: - Analysis (non-real-time; tests and tools)

    /// What the engine will output for a sound, from the same analytic model it uses
    /// to match loudness.
    public static func predict(
        _ profile: SoundProfile,
        character: SoundCharacter? = nil,
        depth: Double,
        airflow: Double,
        hum: Double,
        compactSpeaker: Bool = false,
        sampleRate: Double = 48_000
    ) -> SoundPrediction {
        let grid = ResponseGrid(sampleRate: Float(sampleRate))
        var prediction = SoundPrediction(rms: 0, weightedRMS: 0, humAmplitudes: .zero, humFundamentalHz: 0)
        _ = withUnsafeMutablePointer(to: &prediction) { pointer in
            VoiceModel.derive(character ?? profile.character, depth: Float(depth), airflow: Float(airflow),
                              hum: Float(hum), compactSpeaker: compactSpeaker, grid: grid, prediction: pointer)
        }
        return prediction
    }

    static func sanitizedSampleRate(_ rate: Double) -> Double {
        guard rate.isFinite, rate >= 8_000, rate <= 384_000 else { return 48_000 }
        return rate
    }
}

// MARK: - Control words

/// Fixed block of 32-bit words shared between the control side and the render thread.
final class ControlWords {
    enum Slot: Int, CaseIterable {
        case version
        case profile
        case depth
        case airflow
        case hum
        case compactSpeaker
        case sampleRate
        case playing
        case fadeInSeconds
        case fadeOutSeconds
        case startGeneration
        case audible
    }

    private let words: UnsafeMutablePointer<UInt32>

    init() {
        words = .allocate(capacity: Slot.allCases.count)
        words.initialize(repeating: 0, count: Slot.allCases.count)
    }

    deinit { words.deallocate() }

    @inline(__always) func load(_ slot: Slot) -> UInt32 { ld_atomic_load_u32(words + slot.rawValue) }
    @inline(__always) func store(_ value: UInt32, _ slot: Slot) { ld_atomic_store_u32(words + slot.rawValue, value) }
    @inline(__always) func loadFloat(_ slot: Slot) -> Float { Float(bitPattern: load(slot)) }
    @inline(__always) func storeFloat(_ value: Float, _ slot: Slot) { store(value.bitPattern, slot) }
    func bumpVersion() { _ = ld_atomic_fetch_add_u32(words + Slot.version.rawValue, 1) }
    func bumpStartGeneration() {
        _ = ld_atomic_fetch_add_u32(words + Slot.startGeneration.rawValue, 1)
        bumpVersion()
    }
}

// MARK: - Render core

/// Preset characters copied once at creation so the render thread only reads plain memory.
final class CharacterTable {
    let pointer: UnsafeMutablePointer<SoundCharacter>
    let count: Int

    init(_ source: [SoundCharacter]) {
        count = source.count
        pointer = .allocate(capacity: source.count)
        pointer.initialize(from: source, count: source.count)
    }

    deinit {
        pointer.deinitialize(count: count)
        pointer.deallocate()
    }
}

/// All render-thread state, kept in one struct so the render call mutates it in
/// place with a single access.
struct RenderCore {
    private let control: ControlWords
    private let characters: CharacterTable
    private let grid: ResponseGrid

    private var sampleRate: Float
    private var voiceA: Voice
    private var voiceB: Voice
    private var activeIsA = true
    private var crossfading = false
    private var crossfadeProgress: Float = 0

    private var masterPosition: Float = 0
    private var masterGain = Ramp()
    private var playing = false
    private var fadeInSeconds = NoiseRenderer.defaultFadeIn
    private var fadeOutSeconds = NoiseRenderer.defaultFadeOut

    private var outputHighpass = StateVariableFilter()
    private var outputHighpassCutoff = log2(VoiceModel.outputHighpassHz)
    private var outputHighpassTarget = log2(VoiceModel.outputHighpassHz)

    private var lastVersion: UInt32 = .max
    private var lastStartGeneration: UInt32 = 0
    private var requestedProfile = SoundProfile.basementAC.rawValue
    private var requestedDepth: Float = 0.5
    private var requestedAirflow: Float = 0.5
    private var requestedHum: Float = 0
    private var compactSpeaker = false

    private static var blockSize: Int { 64 }

    init(sampleRate: Float, characters source: [SoundCharacter], seed: UInt64, control: ControlWords) {
        self.control = control
        characters = CharacterTable(source)
        self.sampleRate = sampleRate
        grid = ResponseGrid(sampleRate: sampleRate)
        voiceA = Voice(seed: seed)
        voiceB = Voice(seed: seed &* 0x2545_F491_4F6C_DD1D &+ 1)
        configureForSampleRate()
    }

    mutating func render(into out: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        guard frameCount > 0 else { return true }
        readControls()

        // Fully faded out: emit silence and do no DSP work at all.
        if !playing, masterPosition <= 0 {
            out.update(repeating: 0, count: frameCount)
            control.store(0, .audible)
            return true
        }
        control.store(1, .audible)

        var produced = 0
        var needsRecovery = false
        while produced < frameCount {
            let frames = min(Self.blockSize, frameCount - produced)
            beginBlock(frames: frames)
            let aActive = activeIsA || crossfading
            let bActive = !activeIsA || crossfading
            let output = out + produced
            for i in 0..<frames {
                var y: Float = 0
                if aActive {
                    y += voiceA.renderSample() * voiceA.level.value
                    voiceA.level.tick()
                }
                if bActive {
                    y += voiceB.renderSample() * voiceB.level.value
                    voiceB.level.tick()
                }
                y *= masterGain.value
                masterGain.tick()
                y = softLimit(outputHighpass.highpass(y))
                if !y.isFinite {
                    y = 0
                    needsRecovery = true
                }
                output[i] = y
            }
            produced += frames
            finishCrossfadeIfDone()
        }

        if needsRecovery { recoverFromInvalidState() }
        if !playing, masterPosition <= 0 {
            // Faded out: clear the output filter so a later start begins from true zero.
            outputHighpass.reset()
            control.store(0, .audible)
        }
        return false
    }

    // MARK: Control intake

    private mutating func readControls() {
        let generation = control.load(.startGeneration)
        let restart = generation != lastStartGeneration
        if restart {
            lastStartGeneration = generation
            masterPosition = 0
            masterGain.snap(to: 0)
            outputHighpass.reset()
        }

        let version = control.load(.version)
        guard version != lastVersion || restart else { return }
        lastVersion = version

        let rate = control.loadFloat(.sampleRate)
        if rate.isFinite, rate >= 8_000, rate <= 384_000, abs(rate - sampleRate) > 0.5 {
            sampleRate = rate
            configureForSampleRate()
        }

        let rawProfile = Int(control.load(.profile))
        requestedProfile = min(max(rawProfile, 0), characters.count - 1)
        requestedDepth = sanitizedControl(control.loadFloat(.depth), fallback: requestedDepth)
        requestedAirflow = sanitizedControl(control.loadFloat(.airflow), fallback: requestedAirflow)
        requestedHum = sanitizedControl(control.loadFloat(.hum), fallback: requestedHum)

        playing = control.load(.playing) != 0
        fadeInSeconds = sanitizedDuration(control.loadFloat(.fadeInSeconds), fallback: NoiseRenderer.defaultFadeIn)
        fadeOutSeconds = sanitizedDuration(control.loadFloat(.fadeOutSeconds), fallback: NoiseRenderer.defaultFadeOut)
        compactSpeaker = control.load(.compactSpeaker) != 0
        outputHighpassTarget = log2(compactSpeaker ? VoiceModel.compactOutputHighpassHz : VoiceModel.outputHighpassHz)

        applyRequestedSound()
    }

    private mutating func applyRequestedSound() {
        let targets = VoiceModel.derive(characters.pointer[requestedProfile], depth: requestedDepth,
                                        airflow: requestedAirflow, hum: requestedHum,
                                        compactSpeaker: compactSpeaker, grid: grid)
        let silent = masterPosition <= 0 && masterGain.value == 0

        if silent {
            // Nothing audible: apply immediately to a single voice.
            crossfading = false
            activeIsA = true
            voiceA.profile = requestedProfile
            voiceA.snap(to: targets)
            voiceA.level.snap(to: 1)
            voiceB.level.snap(to: 0)
            outputHighpassCutoff = outputHighpassTarget
            return
        }

        if crossfading {
            // A newer choice during a crossfade: the incoming voice glides to it.
            if activeIsA {
                voiceA.profile = requestedProfile
                voiceA.target = targets
            } else {
                voiceB.profile = requestedProfile
                voiceB.target = targets
            }
            return
        }

        let activeProfile = activeIsA ? voiceA.profile : voiceB.profile
        if activeProfile == requestedProfile {
            // Slider edit or reset: glide.
            if activeIsA { voiceA.target = targets } else { voiceB.target = targets }
            return
        }

        // New preset while audible: start an equal-power crossfade into the idle voice.
        crossfading = true
        crossfadeProgress = 0
        activeIsA.toggle()
        if activeIsA {
            voiceA.profile = requestedProfile
            voiceA.snap(to: targets)
            voiceA.level.snap(to: 0)
        } else {
            voiceB.profile = requestedProfile
            voiceB.snap(to: targets)
            voiceB.level.snap(to: 0)
        }
    }

    // MARK: Block processing

    private mutating func beginBlock(frames: Int) {
        let fs = sampleRate
        let glide = min(Float(frames) / (VoiceModel.glideSeconds * fs), 1)

        // Master fade (smoothstep curve, sampled per block, ramped per sample).
        if playing {
            masterPosition = min(masterPosition + Float(frames) / (fadeInSeconds * fs), 1)
        } else {
            masterPosition = max(masterPosition - Float(frames) / (fadeOutSeconds * fs), 0)
        }
        masterGain.ramp(to: smoothstep(masterPosition), frames: frames)

        // Preset crossfade.
        if crossfading {
            crossfadeProgress = min(crossfadeProgress + Float(frames) / (NoiseRenderer.crossfadeSeconds * fs), 1)
            let angle = smoothstep(crossfadeProgress) * (Float.pi / 2)
            let incoming = sin(angle)
            let outgoing = cos(angle)
            if activeIsA {
                voiceA.level.ramp(to: incoming, frames: frames)
                voiceB.level.ramp(to: crossfadeProgress >= 1 ? 0 : outgoing, frames: frames)
            } else {
                voiceB.level.ramp(to: incoming, frames: frames)
                voiceA.level.ramp(to: crossfadeProgress >= 1 ? 0 : outgoing, frames: frames)
            }
        }

        outputHighpassCutoff += (outputHighpassTarget - outputHighpassCutoff) * glide
        outputHighpass.setCoefficients(g: warpedCoefficient(hz: exp2(outputHighpassCutoff), sampleRate: fs),
                                       q: VoiceModel.outputHighpassQ)

        if activeIsA || crossfading { voiceA.beginBlock(frames: frames, glide: glide, sampleRate: fs) }
        if !activeIsA || crossfading { voiceB.beginBlock(frames: frames, glide: glide, sampleRate: fs) }
    }

    /// Ends a finished crossfade once the outgoing voice has ramped to zero.
    private mutating func finishCrossfadeIfDone() {
        guard crossfading, crossfadeProgress >= 1 else { return }
        let outgoingSilent = activeIsA ? voiceB.level.value <= 1e-6 : voiceA.level.value <= 1e-6
        if outgoingSilent {
            crossfading = false
            if activeIsA { voiceB.level.snap(to: 0) } else { voiceA.level.snap(to: 0) }
        }
    }

    private mutating func configureForSampleRate() {
        grid.configure(sampleRate: sampleRate)
        let controlRate = sampleRate / Float(Self.blockSize)
        voiceA.configure(sampleRate: sampleRate, controlRate: controlRate)
        voiceB.configure(sampleRate: sampleRate, controlRate: controlRate)
        outputHighpass.reset()
        // Force the next control read to re-derive targets for the new rate.
        lastVersion = lastVersion &- 1
    }

    private mutating func recoverFromInvalidState() {
        outputHighpass.reset()
        let targets = VoiceModel.derive(characters.pointer[requestedProfile], depth: requestedDepth,
                                        airflow: requestedAirflow, hum: requestedHum,
                                        compactSpeaker: compactSpeaker, grid: grid)
        crossfading = false
        activeIsA = true
        voiceA.profile = requestedProfile
        voiceA.snap(to: targets)
        voiceA.level.snap(to: 1)
        voiceB.level.snap(to: 0)
        // Come back in softly rather than jumping to full level.
        masterPosition = 0
        masterGain.snap(to: 0)
    }

    private func sanitizedControl(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, 0), 1)
    }

    private func sanitizedDuration(_ value: Float, fallback: Float) -> Float {
        guard value.isFinite, value > 0 else { return fallback }
        return min(max(value, 0.005), 10)
    }
}
