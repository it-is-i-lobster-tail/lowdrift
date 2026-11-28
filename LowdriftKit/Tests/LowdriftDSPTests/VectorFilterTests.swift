@testable import LowdriftDSP
import XCTest

/// The vectorised building blocks must compute exactly what their scalar
/// counterparts did, so the speed-up never changes the sound.
final class VectorFilterTests: XCTestCase {
    func testFilterBankLanesMatchScalarFilters() {
        let fs: Float = 48_000
        let settings: [(hz: Float, q: Float, response: FilterBank4.Response)] = [
            (90, 0.7, .highpass), (180, 0.707, .lowpass), (420, 3.5, .bandpass), (2_600, 1.2, .bandpass),
        ]
        var bank = FilterBank4()
        var scalars = [StateVariableFilter](repeating: StateVariableFilter(), count: 4)
        for (lane, s) in settings.enumerated() {
            let g = warpedCoefficient(hz: s.hz, sampleRate: fs)
            bank.setLane(lane, g: g, q: s.q, response: s.response)
            scalars[lane].setCoefficients(g: g, q: s.q)
        }
        var noise = NoiseSource(seed: 42)
        var worst: Float = 0
        for _ in 0 ..< 200_000 {
            let x = SIMD4(noise.nextBipolar(), noise.nextBipolar(), noise.nextBipolar(), noise.nextBipolar())
            let y = bank.process(x)
            for lane in 0 ..< 4 {
                let expected: Float
                switch settings[lane].response {
                case .lowpass: expected = scalars[lane].lowpass(x[lane])
                case .bandpass: expected = scalars[lane].bandpass(x[lane])
                case .highpass: expected = scalars[lane].highpass(x[lane])
                }
                worst = max(worst, abs(y[lane] - expected))
            }
        }
        XCTAssertLessThan(worst, 1e-5, "A filter bank lane drifted from the scalar filter")
    }

    func testUnsetFilterBankLanesAreSilent() {
        var bank = FilterBank4()
        bank.setLane(0, g: warpedCoefficient(hz: 500, sampleRate: 48_000), q: 1, response: .bandpass)
        for _ in 0 ..< 1_000 {
            let y = bank.process(SIMD4(repeating: 0.5))
            XCTAssertEqual(y[1], 0)
            XCTAssertEqual(y[2], 0)
            XCTAssertEqual(y[3], 0)
        }
    }

    func testHarmonicsStayPhaseLockedAndBounded() {
        // Resynchronised every 64-sample control block as the voice does, with the
        // fundamental gliding the whole time: an hour in optimised builds.
        let fs: Float = 48_000
        let minutes = isOptimizedBuild ? 60 : 2
        var oscillator = HarmonicOscillator()
        var worstLock: Float = 0
        var worstMagnitude: Float = 0
        for block in 0 ..< 48_000 * 60 * minutes / 64 {
            oscillator.setFrequency(60 + 3 * sin(Float(block) * 1e-4), sampleRate: fs)
            oscillator.resynchronize()
            for _ in 0 ..< 64 { oscillator.advance() }
            if block % 997 == 0 {
                let angle = atan2(oscillator.sine[0], oscillator.cosine[0])
                for k in 0 ..< 8 {
                    worstLock = max(worstLock, abs(oscillator.sine[k] - sin(Float(k + 1) * angle)))
                }
                let magnitude = oscillator.sine * oscillator.sine + oscillator.cosine * oscillator.cosine
                let one = SIMD8<Float>(repeating: 1)
                worstMagnitude = max(worstMagnitude, (magnitude - one).max(), (one - magnitude).max())
            }
        }
        XCTAssertLessThan(worstLock, 1e-4, "Harmonics drifted out of phase with the fundamental")
        XCTAssertLessThan(worstMagnitude, 1e-4, "Harmonic amplitude drifted")
    }

    func testRampBankMatchesScalarRamps() {
        var bank = RampBank()
        var ramps = [Ramp](repeating: Ramp(), count: 8)
        var noise = NoiseSource(seed: 3)
        for _ in 0 ..< 2_000 {
            for lane in 0 ..< 8 {
                let target = noise.nextBipolar()
                bank.ramp(lane, to: target, frames: 64)
                ramps[lane].ramp(to: target, frames: 64)
            }
            for _ in 0 ..< 64 {
                bank.tick()
                for lane in 0 ..< 8 { ramps[lane].tick() }
            }
            for lane in 0 ..< 8 { XCTAssertEqual(bank.values[lane], ramps[lane].value) }
        }
    }
}
