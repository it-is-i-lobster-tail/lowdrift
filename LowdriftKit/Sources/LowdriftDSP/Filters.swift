import Foundation

// Lightweight, modulation-friendly filters. Everything here is a value type with
// a handful of Float fields so the render loop can keep its state inline and
// never allocate.

/// Prewarped bilinear-transform frequency coefficient, g = tan(π f / fs).
@inline(__always)
func warpedCoefficient(hz: Float, sampleRate: Float) -> Float {
    let limited = min(max(hz, 5), sampleRate * 0.45)
    return tan(Float.pi * limited / sampleRate)
}

/// Trapezoidal (topology-preserving) state-variable filter after Andrew Simper.
/// It stays numerically well behaved at very low cutoffs in Float32 and tolerates
/// coefficient changes while running, which matters for smooth slider glides.
struct StateVariableFilter: Sendable {
    private var ic1: Float = 0
    private var ic2: Float = 0
    private var a1: Float = 1
    private var a2: Float = 0
    private var a3: Float = 0
    private(set) var k: Float = 1.414_213_6

    mutating func setCoefficients(g: Float, q: Float) {
        let damping = 1 / min(max(q, 0.2), 20)
        k = damping
        a1 = 1 / (1 + g * (g + damping))
        a2 = g * a1
        a3 = g * a2
    }

    @inline(__always)
    private mutating func tick(_ x: Float) -> (low: Float, band: Float) {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, v1)
    }

    @inline(__always)
    mutating func lowpass(_ x: Float) -> Float { tick(x).low }

    @inline(__always)
    mutating func highpass(_ x: Float) -> Float {
        let (low, band) = tick(x)
        return x - k * band - low
    }

    /// Band-pass normalised to unity gain at the centre frequency.
    @inline(__always)
    mutating func bandpass(_ x: Float) -> Float { k * tick(x).band }

    mutating func reset() {
        ic1 = 0
        ic2 = 0
    }
}

/// First-order trapezoidal low-pass.
struct OnePoleLowpass: Sendable {
    private var state: Float = 0
    private var gain: Float = 0

    mutating func setCoefficient(g: Float) { gain = g / (1 + g) }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let v = (x - state) * gain
        let y = v + state
        state = y + v
        return y
    }

    mutating func reset() { state = 0 }
}

/// Approximately −3 dB/octave ("pink-ish") tilt between 25 Hz and 13 kHz built from
/// five first-order shelving sections, each with a pole and a zero one octave
/// apart. Designed from the actual sample rate so the slope does not shift when
/// the hardware rate changes.
struct PinkingFilter: Sendable {
    /// Pole frequencies in Hz; each section's zero sits at twice its pole.
    static var poleFrequencies: (Float, Float, Float, Float, Float) { (25, 100, 400, 1_600, 6_400) }
    /// High-frequency gain of each section (zero/pole ratio of 2).
    static var sectionRatio: Float { 0.5 }

    private var p0 = OnePoleLowpass()
    private var p1 = OnePoleLowpass()
    private var p2 = OnePoleLowpass()
    private var p3 = OnePoleLowpass()
    private var p4 = OnePoleLowpass()

    mutating func configure(sampleRate: Float) {
        let poles = Self.poleFrequencies
        p0.setCoefficient(g: warpedCoefficient(hz: poles.0, sampleRate: sampleRate))
        p1.setCoefficient(g: warpedCoefficient(hz: poles.1, sampleRate: sampleRate))
        p2.setCoefficient(g: warpedCoefficient(hz: poles.2, sampleRate: sampleRate))
        p3.setCoefficient(g: warpedCoefficient(hz: poles.3, sampleRate: sampleRate))
        p4.setCoefficient(g: warpedCoefficient(hz: poles.4, sampleRate: sampleRate))
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        // Each section: H(s) = (1 + r·s/ωp) / (1 + s/ωp) = r + (1 − r)·LP(s), r = 0.5.
        var y = x
        y = 0.5 * (y + p0.process(y))
        y = 0.5 * (y + p1.process(y))
        y = 0.5 * (y + p2.process(y))
        y = 0.5 * (y + p3.process(y))
        y = 0.5 * (y + p4.process(y))
        return y
    }

    mutating func reset() {
        p0.reset(); p1.reset(); p2.reset(); p3.reset(); p4.reset()
    }
}

/// Sine/cosine pair advanced by complex rotation: four multiplies per sample, no
/// trig calls in the sample loop, and a phase that never loses precision over an
/// eight-hour session because the magnitude is renormalised every control block.
struct QuadratureOscillator: Sendable {
    private(set) var cosine: Float = 1
    private(set) var sine: Float = 0
    private var rotationCos: Float = 1
    private var rotationSin: Float = 0

    mutating func setFrequency(_ hz: Float, sampleRate: Float) {
        let w = 2 * Float.pi * min(max(hz, 0), sampleRate * 0.45) / sampleRate
        rotationCos = cos(w)
        rotationSin = sin(w)
    }

    @inline(__always)
    mutating func advance() {
        let c = cosine * rotationCos - sine * rotationSin
        let s = sine * rotationCos + cosine * rotationSin
        cosine = c
        sine = s
    }

    mutating func renormalize() {
        let m = 1.5 - 0.5 * (cosine * cosine + sine * sine)
        cosine *= m
        sine *= m
    }

    mutating func reset() {
        cosine = 1
        sine = 0
    }
}

/// Very slow, smooth, non-periodic wandering in [-1, 1]: white noise through two
/// cascaded one-pole low-passes, normalised and softly bounded. Runs at control
/// rate, so its cost is negligible.
struct SlowDrift: Sendable {
    private var y1: Double = 0
    private var y2: Double = 0
    private var coefficient: Double = 0.999
    private var normalization: Double = 1

    mutating func configure(cutoffHz: Double, controlRate: Double) {
        let c = exp(-2 * Double.pi * cutoffHz / controlRate)
        coefficient = c
        // Variance gain of two cascaded one-poles: (1 − c)(1 + c²)/(1 + c)³.
        let varianceGain = (1 - c) * (1 + c * c) / pow(1 + c, 3)
        normalization = 1 / (varianceGain * Double(NoiseSource.bipolarVariance)).squareRoot()
    }

    /// Advances one control step and returns a unit-variance value (unbounded).
    @inline(__always)
    mutating func nextGaussian(_ white: Float) -> Float {
        let c = coefficient
        y1 = c * y1 + (1 - c) * Double(white)
        y2 = c * y2 + (1 - c) * y1
        return Float(y2 * normalization)
    }

    /// Advances one control step and returns a value softly limited to (-1, 1).
    @inline(__always)
    mutating func nextBounded(_ white: Float) -> Float {
        tanh(0.55 * nextGaussian(white))
    }

    mutating func reset() {
        y1 = 0
        y2 = 0
    }
}

/// Per-sample linear ramp used to interpolate control-rate values.
struct Ramp: Sendable {
    private(set) var value: Float = 0
    private var step: Float = 0

    @inline(__always)
    mutating func ramp(to target: Float, frames: Int) {
        step = (target - value) / Float(frames)
    }

    mutating func snap(to target: Float) {
        value = target
        step = 0
    }

    @inline(__always)
    mutating func tick() { value += step }

    var isIdleAtZero: Bool { value == 0 && step == 0 }
}

/// Gentle rational soft-knee limiter: transparent below `threshold`, approaches
/// `ceiling` asymptotically above it. With the engine's headroom it only touches
/// rare noise peaks, which keeps it inaudible while guaranteeing no hard clipping.
@inline(__always)
func softLimit(_ x: Float) -> Float {
    let threshold: Float = 0.7
    let ceiling: Float = 0.97
    let magnitude = abs(x)
    if magnitude <= threshold { return x }
    let over = (magnitude - threshold) / (ceiling - threshold)
    let y = threshold + (ceiling - threshold) * (over / (1 + over))
    return x < 0 ? -y : y
}

@inline(__always)
func smoothstep(_ x: Float) -> Float {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

@inline(__always)
func decibelsToGain(_ db: Float) -> Float { pow(10, db / 20) }
