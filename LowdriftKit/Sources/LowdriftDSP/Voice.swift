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
    private var airHighpass = StateVariableFilter()
    private var whooshBand = StateVariableFilter()
    private var presenceBand = StateVariableFilter()
    private var lowpass1 = StateVariableFilter()
    private var lowpass2 = StateVariableFilter()
    private var rumbleLowpass1 = StateVariableFilter()
    private var rumbleLowpass2 = StateVariableFilter()
    private var rumbleHighpass = StateVariableFilter()
    private var humNoiseBand = StateVariableFilter()
    private var humNoiseBand2 = StateVariableFilter()
    private var humOscillator = QuadratureOscillator()
    private var bladeOscillator = QuadratureOscillator()

    // Slow, independent, non-periodic drifts (tens of seconds) and a faster
    // flutter for air turbulence.
    private var driftA = SlowDrift()
    private var driftB = SlowDrift()
    private var driftC = SlowDrift()
    private var flutter = SlowDrift()

    private var whooshGain = Ramp()
    private var presenceGain = Ramp()
    private var airLevel = Ramp()
    private var rumbleLevel = Ramp()
    private var bladeDepth = Ramp()
    private var humNoiseLevel = Ramp()
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
        airHighpass.reset(); whooshBand.reset(); presenceBand.reset()
        lowpass1.reset(); lowpass2.reset()
        rumbleLowpass1.reset(); rumbleLowpass2.reset(); rumbleHighpass.reset()
        humNoiseBand.reset()
        humNoiseBand2.reset()
        humOscillator.reset()
        bladeOscillator.reset()
        whooshGain.snap(to: targets.whooshGain)
        presenceGain.snap(to: targets.presenceGain)
        airLevel.snap(to: targets.airLevel)
        rumbleLevel.snap(to: targets.rumbleLevel)
        bladeDepth.snap(to: targets.bladeDepth)
        humNoiseLevel.snap(to: targets.humNoiseLevel)
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

        airHighpass.setCoefficients(g: warpedCoefficient(hz: exp2(current.airHighpass), sampleRate: fs),
                                    q: VoiceModel.airHighpassQ)
        lowpass1.setCoefficients(g: warpedCoefficient(hz: exp2(current.lowpass1 + 0.07 * a), sampleRate: fs),
                                 q: current.lowpassQ)
        lowpass2.setCoefficients(g: warpedCoefficient(hz: exp2(current.lowpass2 + 0.07 * a), sampleRate: fs),
                                 q: current.lowpassQ)
        whooshBand.setCoefficients(g: warpedCoefficient(hz: exp2(current.whoosh + 0.05 * b), sampleRate: fs),
                                   q: current.whooshQ)
        presenceBand.setCoefficients(g: warpedCoefficient(hz: exp2(current.presence), sampleRate: fs),
                                     q: current.presenceQ)
        let rumbleG = warpedCoefficient(hz: exp2(current.rumble), sampleRate: fs)
        rumbleLowpass1.setCoefficients(g: rumbleG, q: 1 / VoiceModel.rumbleK)
        rumbleLowpass2.setCoefficients(g: rumbleG, q: 1 / VoiceModel.rumbleK)
        rumbleHighpass.setCoefficients(g: warpedCoefficient(hz: VoiceModel.rumbleHighpassHz, sampleRate: fs),
                                       q: 1 / VoiceModel.rumbleK)

        bladeOscillator.setFrequency(exp2(current.blade) * (1 + 0.01 * b), sampleRate: fs)
        bladeOscillator.renormalize()

        let flutterGain = 1 + current.turbulence * turbulence
        whooshGain.ramp(to: current.whooshGain * flutterGain, frames: frames)
        presenceGain.ramp(to: current.presenceGain * flutterGain, frames: frames)
        airLevel.ramp(to: current.airLevel * (1 + 0.035 * b), frames: frames)
        rumbleLevel.ramp(to: current.rumbleLevel * (1 + 0.08 * a), frames: frames)
        bladeDepth.ramp(to: current.bladeDepth, frames: frames)

        let humTarget = current.humAmplitudes * (1 + 0.06 * c)
        humStep = (humTarget - humAmplitudes) / Float(frames)
        humActive = (humTarget + humAmplitudes).max() > 1e-7
        if humActive {
            humOscillator.setFrequency(exp2(current.humFundamental) * (1 + 0.0015 * c), sampleRate: fs)
            humOscillator.renormalize()
            let whirrG = warpedCoefficient(hz: exp2(current.humNoise) * (1 + 0.0015 * c), sampleRate: fs)
            humNoiseBand.setCoefficients(g: whirrG, q: current.humNoiseQ)
            humNoiseBand2.setCoefficients(g: whirrG, q: current.humNoiseQ)
        }
        humNoiseLevel.ramp(to: current.humNoiseLevel, frames: frames)
    }

    /// Generates one sample. Called `frames` times after `beginBlock`.
    @inline(__always)
    mutating func renderSample() -> Float {
        // Airflow: pink-ish noise, high-passed, with two resonant bands, low-passed.
        let shaped = airHighpass.highpass(pink.process(noise.nextBipolar()))
        let body = whooshBand.bandpass(shaped)
        let presence = presenceBand.bandpass(shaped)
        var air = lowpass2.lowpass(lowpass1.lowpass(shaped + whooshGain.value * body + presenceGain.value * presence))
        bladeOscillator.advance()
        air *= 1 + bladeDepth.value * bladeOscillator.sine

        // Low body: independent noise, low-passed to a bounded rumble.
        let rumble = rumbleHighpass.highpass(rumbleLowpass2.lowpass(rumbleLowpass1.lowpass(noise.nextBipolar())))

        var y = air * airLevel.value + rumble * rumbleLevel.value

        if humActive {
            // Motor: phase-locked harmonics from one oscillator (angle-addition
            // recursion, no trig per sample), plus a narrow whirr.
            humOscillator.advance()
            let s1 = humOscillator.sine
            let c1 = humOscillator.cosine
            var partials = SIMD8<Float>.zero
            var sk = s1
            var ck = c1
            partials[0] = s1
            for k in 1..<8 {
                let s = sk * c1 + ck * s1
                ck = ck * c1 - sk * s1
                sk = s
                partials[k] = s
            }
            y += (humAmplitudes * partials).sum()
            // Two cascaded band-passes keep the whirr's skirts from leaking upward.
            y += humNoiseBand2.bandpass(humNoiseBand.bandpass(noise.nextBipolar())) * humNoiseLevel.value
            humAmplitudes += humStep
        }

        whooshGain.tick()
        presenceGain.tick()
        airLevel.tick()
        rumbleLevel.tick()
        bladeDepth.tick()
        humNoiseLevel.tick()
        return y
    }
}
