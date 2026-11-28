import Foundation

/// One continuously running sound generator. The renderer owns two so presets
/// can crossfade. All state is inline value types; nothing here allocates.
struct Voice {
    var profile = -1
    var target = VoiceTargets()
    var current = VoiceTargets()
    /// Equal-power crossfade gain of this voice.
    var level = Ramp()

    private var noise: NoiseSource
    private var controlNoise: NoiseSource

    private var pink = PinkingFilter()
    // The voice's filters, grouped into stages that run side by side:
    //   stage 1: air high-pass       | rumble low-pass 1  | whirr band 1 | —
    //   stage 2: whoosh band         | rumble low-pass 2  | whirr band 2 | presence band
    //   stage 3: air low-pass 1      | rumble high-pass   | presence-open band | —
    // followed by the scalar air low-pass 2.
    private var stage1 = FilterBank4()
    private var stage2 = FilterBank4()
    private var stage3 = FilterBank4()
    private var lowpass2 = StateVariableFilter()
    private var humOscillator = HarmonicOscillator()
    private var bladeOscillator = QuadratureOscillator()

    // Slow, independent, non-periodic drifts (tens of seconds) and a faster
    // flutter for air turbulence.
    private var driftA = SlowDrift()
    private var driftB = SlowDrift()
    private var driftC = SlowDrift()
    private var flutter = SlowDrift()

    /// Per-sample gains, ramped together; lanes named in `Gain`.
    private var gains = RampBank()
    private var humAmplitudes = SIMD8<Float>.zero
    private var humStep = SIMD8<Float>.zero
    private var humActive = false

    init(seed: UInt64) {
        noise = NoiseSource(seed: seed)
        controlNoise = NoiseSource(seed: seed ^ 0xA5A5_5A5A_C3C3_3C3C)
    }

    /// Prepares sample-rate dependent pieces. Real-time safe.
    mutating func configure(sampleRate fs: Float, controlRate: Float) {
        pink.configure(sampleRate: fs)
        let rate = Double(controlRate)
        driftA.configure(cutoffHz: 0.031, controlRate: rate)
        driftB.configure(cutoffHz: 0.053, controlRate: rate)
        driftC.configure(cutoffHz: 0.087, controlRate: rate)
        flutter.configure(cutoffHz: 7, controlRate: rate)
    }

    /// Jumps straight to the targets and clears filter memory. Only used while
    /// the voice is inaudible.
    mutating func snap(to targets: VoiceTargets) {
        target = targets
        current = targets
        pink.reset()
        stage1.reset(); stage2.reset(); stage3.reset()
        lowpass2.reset()
        humOscillator.reset()
        bladeOscillator.reset()
        gains.snap(Gain.whoosh, to: targets.whooshGain)
        gains.snap(Gain.presence, to: targets.presenceGain * (1 - targets.presenceOpen))
        gains.snap(Gain.presenceOpen, to: targets.presenceGain * targets.presenceOpen)
        gains.snap(Gain.air, to: targets.airLevel)
        gains.snap(Gain.rumble, to: targets.rumbleLevel)
        gains.snap(Gain.blade, to: targets.bladeDepth)
        gains.snap(Gain.whirr, to: targets.humNoiseLevel)
        humAmplitudes = targets.humAmplitudes
        humStep = .zero
    }

    /// Control-rate update at the start of each block of `frames` samples.
    mutating func beginBlock(frames: Int, glide: Float, sampleRate fs: Float) {
        current.approach(target, amount: glide)

        let drift = current.drift
        let a = driftA.nextBounded(controlNoise.nextBipolar()) * drift
        let b = driftB.nextBounded(controlNoise.nextBipolar()) * drift
        let c = driftC.nextBounded(controlNoise.nextBipolar())
        let turbulence = min(max(flutter.nextGaussian(controlNoise.nextBipolar()), -2.5), 2.5)

        stage1.setLane(0, g: warpedCoefficient(hz: exp2(current.airHighpass), sampleRate: fs),
                       q: VoiceModel.airHighpassQ, response: .highpass)
        stage3.setLane(0, g: warpedCoefficient(hz: exp2(current.lowpass1 + 0.07 * a), sampleRate: fs),
                       q: current.lowpassQ, response: .lowpass)
        lowpass2.setCoefficients(g: warpedCoefficient(hz: exp2(current.lowpass2 + 0.07 * a), sampleRate: fs),
                                 q: current.lowpassQ)
        stage2.setLane(0, g: warpedCoefficient(hz: exp2(current.whoosh + 0.05 * b), sampleRate: fs),
                       q: current.whooshQ, response: .bandpass)
        let presenceG = warpedCoefficient(hz: exp2(current.presence), sampleRate: fs)
        stage2.setLane(3, g: presenceG, q: current.presenceQ, response: .bandpass)
        stage3.setLane(2, g: presenceG, q: current.presenceQ, response: .bandpass)
        let rumbleG = warpedCoefficient(hz: exp2(current.rumble), sampleRate: fs)
        stage1.setLane(1, g: rumbleG, q: 1 / VoiceModel.rumbleK, response: .lowpass)
        stage2.setLane(1, g: rumbleG, q: 1 / VoiceModel.rumbleK, response: .lowpass)
        stage3.setLane(1, g: warpedCoefficient(hz: VoiceModel.rumbleHighpassHz, sampleRate: fs),
                       q: 1 / VoiceModel.rumbleK, response: .highpass)

        bladeOscillator.setFrequency(exp2(current.blade) * (1 + 0.01 * b), sampleRate: fs)
        bladeOscillator.renormalize()

        let flutterGain = 1 + current.turbulence * turbulence
        gains.ramp(Gain.whoosh, to: current.whooshGain * flutterGain, frames: frames)
        gains.ramp(Gain.presence, to: current.presenceGain * (1 - current.presenceOpen) * flutterGain, frames: frames)
        gains.ramp(Gain.presenceOpen, to: current.presenceGain * current.presenceOpen * flutterGain, frames: frames)
        gains.ramp(Gain.air, to: current.airLevel * (1 + 0.035 * b), frames: frames)
        gains.ramp(Gain.rumble, to: current.rumbleLevel * (1 + 0.08 * a), frames: frames)
        gains.ramp(Gain.blade, to: current.bladeDepth, frames: frames)

        let humTarget = current.humAmplitudes * (1 + 0.06 * c)
        humStep = (humTarget - humAmplitudes) / Float(frames)
        humActive = (humTarget + humAmplitudes).max() > 1e-7
        if humActive {
            humOscillator.setFrequency(exp2(current.humFundamental) * (1 + 0.0015 * c), sampleRate: fs)
            humOscillator.resynchronize()
            let whirrG = warpedCoefficient(hz: exp2(current.humNoise) * (1 + 0.0015 * c), sampleRate: fs)
            stage1.setLane(2, g: whirrG, q: current.humNoiseQ, response: .bandpass)
            stage2.setLane(2, g: whirrG, q: current.humNoiseQ, response: .bandpass)
        }
        gains.ramp(Gain.whirr, to: current.humNoiseLevel, frames: frames)
    }

    /// Generates one sample. Called `frames` times after `beginBlock`.
    @inline(__always)
    mutating func renderSample() -> Float {
        // Airflow: pink-ish noise, high-passed, with two resonant bands, low-passed.
        // Low body: independent noise, low-passed to a bounded rumble.
        // Motor whirr: a third noise through two cascaded band-passes, which keep
        // its skirts from leaking upward. (Noise is drawn in this order every
        // sample; the whirr's only while the motor is audible.)
        let g = gains.values
        let pinked = pink.process(noise.nextBipolar())
        let rumbleNoise = noise.nextBipolar()
        let whirrNoise = humActive ? noise.nextBipolar() : 0
        let s1 = stage1.process(SIMD4(pinked, rumbleNoise, whirrNoise, 0))
        let shaped = s1[0]
        let s2 = stage2.process(SIMD4(shaped, s1[1], s1[2], shaped))
        let presence = s2[3]
        let s3 = stage3.process(SIMD4(shaped + g[Gain.whoosh] * s2[0] + g[Gain.presence] * presence,
                                      s2[1], presence, 0))
        var air = lowpass2.lowpass(s3[0]) + g[Gain.presenceOpen] * s3[2]
        bladeOscillator.advance()
        air *= 1 + g[Gain.blade] * bladeOscillator.sine

        var y = air * g[Gain.air] + s3[1] * g[Gain.rumble]

        if humActive {
            // Motor: eight phase-locked harmonics (one vector rotation, no trig
            // per sample), plus the whirr.
            humOscillator.advance()
            y += (humAmplitudes * humOscillator.sine).sum()
            y += s2[2] * g[Gain.whirr]
            humAmplitudes += humStep
        }
        gains.tick()
        return y
    }
}

/// Lanes of the voice's gain bank. (Computed constants, so the render thread
/// never touches lazily initialised globals.)
private enum Gain {
    static var whoosh: Int { 0 }
    static var presence: Int { 1 }
    static var presenceOpen: Int { 2 }
    static var air: Int { 3 }
    static var rumble: Int { 4 }
    static var blade: Int { 5 }
    static var whirr: Int { 6 }
}
