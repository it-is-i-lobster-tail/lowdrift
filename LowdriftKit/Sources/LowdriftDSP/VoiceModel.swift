import Foundation

/// Target parameters for one voice, derived from a `SoundCharacter` plus the
/// user's three controls. Frequencies are stored as log2(Hz) so glides move
/// evenly in pitch; gains are linear amplitudes with loudness matching folded in.
struct VoiceTargets: Sendable, Equatable {
    var airHighpass: Float = 6
    var lowpass1: Float = 10
    var lowpass2: Float = 10.5
    var lowpassQ: Float = 0.6
    var whoosh: Float = 8
    var whooshQ: Float = 0.7
    var whooshGain: Float = 0
    var presence: Float = 11
    var presenceQ: Float = 0.9
    var presenceGain: Float = 0
    var airLevel: Float = 0

    var rumble: Float = 6
    var rumbleLevel: Float = 0

    var humFundamental: Float = 6
    var humAmplitudes: SIMD8<Float> = .zero
    var humNoise: Float = 7
    var humNoiseQ: Float = 6
    var humNoiseLevel: Float = 0

    var blade: Float = 5
    var bladeDepth: Float = 0
    var turbulence: Float = 0
    var drift: Float = 0

    /// One-pole glide toward `target`; `amount` is the fraction of the remaining
    /// distance covered this control block.
    mutating func approach(_ t: VoiceTargets, amount a: Float) {
        airHighpass += (t.airHighpass - airHighpass) * a
        lowpass1 += (t.lowpass1 - lowpass1) * a
        lowpass2 += (t.lowpass2 - lowpass2) * a
        lowpassQ += (t.lowpassQ - lowpassQ) * a
        whoosh += (t.whoosh - whoosh) * a
        whooshQ += (t.whooshQ - whooshQ) * a
        whooshGain += (t.whooshGain - whooshGain) * a
        presence += (t.presence - presence) * a
        presenceQ += (t.presenceQ - presenceQ) * a
        presenceGain += (t.presenceGain - presenceGain) * a
        airLevel += (t.airLevel - airLevel) * a
        rumble += (t.rumble - rumble) * a
        rumbleLevel += (t.rumbleLevel - rumbleLevel) * a
        humFundamental += (t.humFundamental - humFundamental) * a
        humAmplitudes += (t.humAmplitudes - humAmplitudes) * a
        humNoise += (t.humNoise - humNoise) * a
        humNoiseQ += (t.humNoiseQ - humNoiseQ) * a
        humNoiseLevel += (t.humNoiseLevel - humNoiseLevel) * a
        blade += (t.blade - blade) * a
        bladeDepth += (t.bladeDepth - bladeDepth) * a
        turbulence += (t.turbulence - turbulence) * a
        drift += (t.drift - drift) * a
    }
}

/// Frequency grid for the analytic loudness model, sized once and refilled in
/// place whenever the sample rate changes (no allocation on the audio thread).
final class ResponseGrid {
    static var capacity: Int { 160 }

    let frequency: UnsafeMutablePointer<Float>
    /// tan(π f / fs): the bilinear-transform frequency for each grid point.
    let warped: UnsafeMutablePointer<Float>
    /// Trapezoidal integration width in Hz.
    let width: UnsafeMutablePointer<Float>
    /// Perceptual power weighting (see `loudnessWeightPower`) including the output
    /// high-pass, for full-range outputs (headphones, external speakers).
    let weight: UnsafeMutablePointer<Float>
    /// The same for a phone's built-in speaker: includes a small-speaker response
    /// model and the raised output high-pass used on that route.
    let compactWeight: UnsafeMutablePointer<Float>
    /// Output high-pass power response for each route type.
    let outputPower: UnsafeMutablePointer<Float>
    let compactOutputPower: UnsafeMutablePointer<Float>
    private(set) var count = 0
    private(set) var sampleRate: Float = 0

    init(sampleRate: Float) {
        let n = Self.capacity
        frequency = .allocate(capacity: n)
        warped = .allocate(capacity: n)
        width = .allocate(capacity: n)
        weight = .allocate(capacity: n)
        compactWeight = .allocate(capacity: n)
        outputPower = .allocate(capacity: n)
        compactOutputPower = .allocate(capacity: n)
        for table in [frequency, warped, width, weight, compactWeight, outputPower, compactOutputPower] {
            table.initialize(repeating: 0, count: n)
        }
        configure(sampleRate: sampleRate)
    }

    deinit {
        frequency.deallocate()
        warped.deallocate()
        width.deallocate()
        weight.deallocate()
        compactWeight.deallocate()
        outputPower.deallocate()
        compactOutputPower.deallocate()
    }

    /// Real-time safe: only writes into the preallocated tables.
    func configure(sampleRate fs: Float) {
        sampleRate = fs
        let n = Self.capacity
        count = n
        let low: Float = 12
        let high = min(16_000, fs * 0.47)
        let ratio = log(high / low) / Float(n - 1)
        for i in 0..<n {
            let f = low * exp(ratio * Float(i))
            frequency[i] = f
            let t = tan(Float.pi * f / fs)
            warped[i] = t
            outputPower[i] = outputHighpassPower(t, compact: false, sampleRate: fs)
            compactOutputPower[i] = outputHighpassPower(t, compact: true, sampleRate: fs)
            weight[i] = loudnessWeightPower(f) * outputPower[i]
            compactWeight[i] = loudnessWeightPower(f) * compactSpeakerPower(f) * compactOutputPower[i]
        }
        for i in 0..<n {
            let lower = i > 0 ? frequency[i - 1] : frequency[i]
            let upper = i < n - 1 ? frequency[i + 1] : frequency[i]
            width[i] = 0.5 * (upper - lower)
        }
    }
}

/// Perceptual power weighting used to keep presets and slider positions at a
/// matched perceived level. In dB it is 1.25 × A − 0.25 × C: slightly steeper
/// than A-weighting at the low end. That curve was fitted so equal weighted
/// level gives equal ISO 532-1 (Zwicker) loudness across all six presets and
/// their slider extremes at sleep listening levels (about 50 dB SPL); for these
/// smooth noises it matched within ±1 phon (std) where A-weighting alone left
/// the darkest settings about 3 phon quieter.
public func loudnessWeightPower(_ hz: Float) -> Float {
    let f2 = Double(hz) * Double(hz)
    let p1 = 20.598_997 * 20.598_997
    let p2 = 107.652_65 * 107.652_65
    let p3 = 737.862_23 * 737.862_23
    let p4 = 12_194.217 * 12_194.217
    let ra = p4 * f2 * f2 / ((f2 + p1) * ((f2 + p2) * (f2 + p3)).squareRoot() * (f2 + p4))
    let rc = p4 * f2 / ((f2 + p1) * (f2 + p4))
    let aGain = ra * 1.258_925_4 // +2.00 dB normalises A to 0 dB at 1 kHz
    let cGain = rc * 1.007_163_2 // +0.062 dB normalises C
    // Power: (A²)^1.25 · (C²)^-0.25.
    return Float(pow(aGain, 2.5) / cGain.squareRoot())
}

/// Rough power response of a phone's built-in speaker (2nd-order high-pass at
/// 300 Hz and 1st-order at 180 Hz), so loudness stays matched on that route too.
func compactSpeakerPower(_ hz: Float) -> Float {
    let o2 = (hz / 300) * (hz / 300)
    let re = 1 - o2
    let second = o2 * o2 / (re * re + o2 / (0.7 * 0.7))
    let p2 = (hz / 180) * (hz / 180)
    return second * p2 / (1 + p2)
}

/// Power response of the renderer's output high-pass at warped frequency t.
func outputHighpassPower(_ t: Float, compact: Bool, sampleRate: Float) -> Float {
    let g = warpedCoefficient(hz: compact ? VoiceModel.compactOutputHighpassHz : VoiceModel.outputHighpassHz,
                              sampleRate: sampleRate)
    let o2 = (t / g) * (t / g)
    let re = 1 - o2
    let k = 1 / VoiceModel.outputHighpassQ
    return o2 * o2 / (re * re + k * k * o2)
}

/// Critical bandwidth (Zwicker) in Hz, used to express hum as a tone-to-noise ratio.
@inline(__always)
func criticalBandwidth(_ hz: Float) -> Float {
    let k = hz / 1_000
    return 25 + 75 * pow(1 + 1.4 * k * k, 0.69)
}

// MARK: - Analytic responses (match the trapezoidal filters exactly)

@inline(__always)
private func lowpass2Power(_ omega: Float, k: Float) -> Float {
    let o2 = omega * omega
    let re = 1 - o2
    return 1 / (re * re + k * k * o2)
}

@inline(__always)
private func highpass2Power(_ omega: Float, k: Float) -> Float {
    let o2 = omega * omega
    let re = 1 - o2
    return o2 * o2 / (re * re + k * k * o2)
}

/// Unity-peak band-pass as a complex value.
@inline(__always)
private func bandpassComplex(_ omega: Float, k: Float) -> (re: Float, im: Float) {
    let o2 = omega * omega
    let re = 1 - o2
    let d = re * re + k * k * o2
    return (k * k * o2 / d, k * omega * re / d)
}

@inline(__always)
private func pinkShelfPower(_ t: Float, poleG: Float) -> Float {
    let o = t / poleG
    let o2 = o * o
    return (1 + 0.25 * o2) / (1 + o2)
}

/// Filter coefficients of one voice in the form the analytic model needs.
struct AirSpec {
    var pink: (Float, Float, Float, Float, Float)
    var highpassG: Float, highpassK: Float
    var whooshG: Float, whooshK: Float, whooshGain: Float
    var presenceG: Float, presenceK: Float, presenceGain: Float
    var lowpass1G: Float, lowpass2G: Float, lowpassK: Float
    var rumbleG: Float, rumbleHighpassG: Float

    /// Power response of the air layer, and of its resonant bands alone, at warped frequency t.
    @inline(__always)
    func airPower(_ t: Float) -> (total: Float, bands: Float) {
        let pink = pinkShelfPower(t, poleG: pink.0) * pinkShelfPower(t, poleG: pink.1)
            * pinkShelfPower(t, poleG: pink.2) * pinkShelfPower(t, poleG: pink.3)
            * pinkShelfPower(t, poleG: pink.4)
        let hp = highpass2Power(t / highpassG, k: highpassK)
        let w = bandpassComplex(t / whooshG, k: whooshK)
        let p = bandpassComplex(t / presenceG, k: presenceK)
        let bandsRe = whooshGain * w.re + presenceGain * p.re
        let bandsIm = whooshGain * w.im + presenceGain * p.im
        let sumRe = 1 + bandsRe
        let lp = lowpass2Power(t / lowpass1G, k: lowpassK) * lowpass2Power(t / lowpass2G, k: lowpassK)
        let common = pink * hp * lp
        return (common * (sumRe * sumRe + bandsIm * bandsIm), common * (bandsRe * bandsRe + bandsIm * bandsIm))
    }

    @inline(__always)
    func rumblePower(_ t: Float) -> Float {
        let lp = lowpass2Power(t / rumbleG, k: VoiceModel.rumbleK)
        return lp * lp * highpass2Power(t / rumbleHighpassG, k: VoiceModel.rumbleK)
    }
}

/// Result of the analytic model, exposed for tests and tooling.
public struct SoundPrediction: Sendable {
    /// Predicted unweighted output RMS (linear, full scale = 1).
    public var rms: Float
    /// Predicted perceptually weighted output RMS (equals the engine's loudness target).
    public var weightedRMS: Float
    /// Amplitudes of the eight hum partials at the output.
    public var humAmplitudes: SIMD8<Float>
    public var humFundamentalHz: Float
    /// Main air low-pass cutoff in Hz.
    public var lowpassHz: Float = 0
    /// Linear amount of the whoosh band.
    public var whooshGain: Float = 0
    /// Flutter of the resonant bands (standard deviation of their gain).
    public var turbulence: Float = 0
    /// Blade-pass modulation depth.
    public var bladeDepth: Float = 0
}

enum VoiceModel {
    /// Perceptually weighted output RMS every preset and slider position is matched to.
    static var targetWeightedRMS: Float { 0.03 }
    /// The same on a phone's built-in speaker, where the raised output high-pass
    /// frees headroom for a higher level.
    static var compactTargetWeightedRMS: Float { 0.05 }
    /// Highest permitted output RMS (about −15.5 dBFS): with Gaussian-like noise
    /// that keeps peaks below the soft limiter's threshold for all practical purposes.
    static var maximumRMS: Float { 0.168 }
    static var compactMaximumRMS: Float { 0.2 }
    static var outputHighpassHz: Float { 22 }
    static var compactOutputHighpassHz: Float { 200 }
    static var outputHighpassQ: Float { 0.6 }
    /// Glide time constant for slider and reset changes, in seconds.
    static var glideSeconds: Float { 0.28 }
    static var rumbleK: Float { 1.414_213_6 }
    static var rumbleHighpassHz: Float { 24 }

    /// Derives voice targets. Real-time safe: scalar math over a preallocated grid.
    static func derive(
        _ c: SoundCharacter,
        depth: Float,
        airflow: Float,
        hum: Float,
        compactSpeaker: Bool = false,
        grid: ResponseGrid,
        prediction: UnsafeMutablePointer<SoundPrediction>? = nil
    ) -> VoiceTargets {
        let fs = grid.sampleRate
        let d = min(max(depth, 0), 1) - 0.5
        let a = min(max(airflow, 0), 1) - 0.5
        let humAmount = min(max(hum, 0), 1)
        let nyquistLimit = log2(fs * 0.45)

        var t = VoiceTargets()
        t.airHighpass = log2(c.airHighpassHz) - c.depthHighpassOctaves * d
        t.lowpass1 = min(max(log2(c.lowpassHz) - c.depthLowpassOctaves * d + c.airflowLowpassOctaves * a,
                             log2(Float(200))), min(log2(Float(6_800)), nyquistLimit))
        t.lowpass2 = min(t.lowpass1 + log2(max(c.lowpassSpread, 1)), nyquistLimit)
        t.lowpassQ = c.lowpassQ
        t.whoosh = min(log2(c.whooshHz) - c.depthWhooshOctaves * d + 0.2 * a, nyquistLimit)
        t.whooshQ = min(max(c.whooshQ * exp2(-c.airflowWidthOctaves * a), 0.35), 2.5)
        t.whooshGain = max(c.whooshBoost * decibelsToGain(c.airflowWhooshDb * a), 0)
        t.presence = min(log2(c.presenceHz) + 0.25 * a, nyquistLimit)
        t.presenceQ = c.presenceQ
        t.presenceGain = min(c.presenceBoost * decibelsToGain(c.airflowPresenceDb * a - c.depthPresenceDb * d), 0.6)
        t.rumble = log2(c.rumbleHz) - 0.35 * d
        t.blade = log2(max(c.bladeHz, 1))
        t.bladeDepth = c.bladeHz > 0 ? min(max(c.bladeDepth * (1 + 1.2 * a), 0), 0.09) : 0
        t.turbulence = min(max(c.turbulence * (1 + 1.6 * a), 0), 0.35)
        t.drift = min(max(c.drift, 0), 1)
        t.humFundamental = log2(c.humHz)
        t.humNoise = log2(c.humHz * c.humNoiseRatio)
        t.humNoiseQ = c.humNoiseQ
        let rumbleDb = min(c.rumbleLevelDb + c.depthRumbleDb * d + c.airflowRumbleDb * a, 3)

        let spec = AirSpec(
            pink: (
                warpedCoefficient(hz: PinkingFilter.poleFrequencies.0, sampleRate: fs),
                warpedCoefficient(hz: PinkingFilter.poleFrequencies.1, sampleRate: fs),
                warpedCoefficient(hz: PinkingFilter.poleFrequencies.2, sampleRate: fs),
                warpedCoefficient(hz: PinkingFilter.poleFrequencies.3, sampleRate: fs),
                warpedCoefficient(hz: PinkingFilter.poleFrequencies.4, sampleRate: fs)
            ),
            highpassG: warpedCoefficient(hz: exp2(t.airHighpass), sampleRate: fs),
            highpassK: 1 / VoiceModel.airHighpassQ,
            whooshG: warpedCoefficient(hz: exp2(t.whoosh), sampleRate: fs),
            whooshK: 1 / t.whooshQ,
            whooshGain: t.whooshGain,
            presenceG: warpedCoefficient(hz: exp2(t.presence), sampleRate: fs),
            presenceK: 1 / t.presenceQ,
            presenceGain: t.presenceGain,
            lowpass1G: warpedCoefficient(hz: exp2(t.lowpass1), sampleRate: fs),
            lowpass2G: warpedCoefficient(hz: exp2(t.lowpass2), sampleRate: fs),
            lowpassK: 1 / t.lowpassQ,
            rumbleG: warpedCoefficient(hz: exp2(t.rumble), sampleRate: fs),
            rumbleHighpassG: warpedCoefficient(hz: rumbleHighpassHz, sampleRate: fs)
        )

        // Integrate the layer power spectra: raw (to balance layers), at the output
        // (after the output high-pass, for headroom) and perceptually weighted.
        let weights = compactSpeaker ? grid.compactWeight : grid.weight
        let output = compactSpeaker ? grid.compactOutputPower : grid.outputPower
        var air: Float = 0, airOut: Float = 0, airW: Float = 0, bandsW: Float = 0
        var rumble: Float = 0, rumbleOut: Float = 0, rumbleW: Float = 0
        for i in 0..<grid.count {
            let tf = grid.warped[i]
            let df = grid.width[i]
            let w = weights[i] * df
            let o = output[i] * df
            let p = spec.airPower(tf)
            let r = spec.rumblePower(tf)
            air += p.total * df
            airOut += p.total * o
            airW += p.total * w
            bandsW += p.bands * w
            rumble += r * df
            rumbleOut += r * o
            rumbleW += r * w
        }
        // White noise of variance σ² has a one-sided density of 2σ²/fs per Hz.
        let density = 2 * NoiseSource.bipolarVariance / fs
        air *= density; airOut *= density; airW *= density; bandsW *= density
        rumble *= density; rumbleOut *= density; rumbleW *= density

        let rumbleGain = rumble > 0 ? (air * pow(10, rumbleDb / 10) / rumble).squareRoot() : 0
        let bladePower = 1 + 0.5 * t.bladeDepth * t.bladeDepth
        let noisePower = air * bladePower + rumbleGain * rumbleGain * rumble
        var weightedPower = airW * bladePower + t.turbulence * t.turbulence * bandsW
            + rumbleGain * rumbleGain * rumbleW
        var unweightedPower = airOut * bladePower + rumbleGain * rumbleGain * rumbleOut

        // Hum partials sized as tone-to-noise ratios within their critical band, so
        // "Hum" means the same audible prominence whatever the noise spectrum is.
        var amplitudes = SIMD8<Float>.zero
        var humNoiseGain: Float = 0
        if humAmount > 0.001 {
            let amountDb = 20 * log10(pow(humAmount, 0.9))
            let f0 = c.humHz
            for k in 0..<8 {
                let fk = f0 * Float(k + 1)
                guard fk < fs * 0.45 else { continue }
                let tnr = c.humPeakTNR + c.humHarmonicsDb[k] + amountDb
                guard tnr > -60 else { continue }
                let tk = tan(Float.pi * fk / fs)
                let noiseDensity = density * (spec.airPower(tk).total * bladePower
                    + rumbleGain * rumbleGain * spec.rumblePower(tk))
                // Bounded so a low partial under a strong rumble never dominates the mix.
                let tone = min(pow(10, tnr / 10) * noiseDensity * criticalBandwidth(fk), 0.25 * noisePower)
                amplitudes[k] = (2 * tone).squareRoot()
                let passed = outputHighpassPower(tk, compact: compactSpeaker, sampleRate: fs)
                weightedPower += tone * passed * loudnessWeightPower(fk) * (compactSpeaker ? compactSpeakerPower(fk) : 1)
                unweightedPower += tone * passed
            }
            let fn = f0 * c.humNoiseRatio
            let tnrNoise = c.humPeakTNR + c.humNoiseDb + amountDb
            if fn < fs * 0.45, tnrNoise > -40 {
                let tn = tan(Float.pi * fn / fs)
                let noiseDensity = density * (spec.airPower(tn).total * bladePower
                    + rumbleGain * rumbleGain * spec.rumblePower(tn))
                let power = min(pow(10, tnrNoise / 10) * noiseDensity * criticalBandwidth(fn), 0.05 * noisePower)
                // Two cascaded unity-peak band-passes pass an equivalent noise
                // bandwidth of about (π/4)·f/Q.
                let passed = density * (Float.pi / 4) * fn / max(c.humNoiseQ, 0.5)
                humNoiseGain = (power / passed).squareRoot()
                let out = outputHighpassPower(tn, compact: compactSpeaker, sampleRate: fs)
                weightedPower += power * out * loudnessWeightPower(fn) * (compactSpeaker ? compactSpeakerPower(fn) : 1)
                unweightedPower += power * out
            }
        }

        let target = compactSpeaker ? compactTargetWeightedRMS : targetWeightedRMS
        let level = target * decibelsToGain(c.levelTrimDb + 1.5 * a)
        var outputGain = weightedPower > 0 ? level / weightedPower.squareRoot() : 0
        // Headroom guard: the darkest extreme settings need far more raw energy for
        // the same loudness; cap their output RMS so peaks stay clear of the limiter.
        let cap = compactSpeaker ? compactMaximumRMS : maximumRMS
        if unweightedPower > 0, outputGain * unweightedPower.squareRoot() > cap {
            outputGain = cap / unweightedPower.squareRoot()
        }
        t.airLevel = outputGain
        t.rumbleLevel = outputGain * rumbleGain
        t.humAmplitudes = amplitudes * outputGain
        t.humNoiseLevel = humNoiseGain * outputGain

        if let prediction {
            prediction.pointee = SoundPrediction(
                rms: unweightedPower.squareRoot() * outputGain,
                weightedRMS: weightedPower.squareRoot() * outputGain,
                humAmplitudes: t.humAmplitudes,
                humFundamentalHz: c.humHz,
                lowpassHz: exp2(t.lowpass1),
                whooshGain: t.whooshGain,
                turbulence: t.turbulence,
                bladeDepth: t.bladeDepth
            )
        }
        return t
    }

    static var airHighpassQ: Float { 0.6 }
}
