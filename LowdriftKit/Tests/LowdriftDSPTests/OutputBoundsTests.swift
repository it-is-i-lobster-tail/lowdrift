import LowdriftAnalysis
import LowdriftCore
import LowdriftDSP
import XCTest

/// Output is always finite, inside full scale, free of DC and clearly audible.
final class OutputBoundsTests: XCTestCase {
    func testEveryPresetProducesBoundedNonSilentOutput() {
        for preset in Preset.allCases {
            let samples = renderPreset(preset, seconds: 4)
            XCTAssertTrue(samples.allSatisfy(\.isFinite), "\(preset) produced a non-finite sample")
            XCTAssertLessThan(Signal.peak(samples), 0.97, "\(preset) exceeded the limiter ceiling")
            let level = decibels(Signal.rms(samples))
            XCTAssertGreaterThan(level, -40, "\(preset) is nearly silent")
            XCTAssertLessThan(level, -12, "\(preset) is too hot")
            XCTAssertLessThan(abs(Signal.mean(samples)), 1e-3, "\(preset) has a DC offset")
        }
    }

    func testExtremeControlCombinationsStayBoundedAndPleasant() {
        let corners: [(Double, Double, Double)] = [
            (0, 0, 0), (100, 100, 100), (0, 100, 100), (100, 0, 0), (100, 100, 0), (0, 0, 100),
        ]
        for preset in Preset.allCases {
            for (depth, airflow, hum) in corners {
                let samples = renderPreset(preset, depth: depth, airflow: airflow, hum: hum, seconds: 2)
                let label = "\(preset) d\(depth) a\(airflow) h\(hum)"
                XCTAssertTrue(samples.allSatisfy(\.isFinite), label)
                XCTAssertLessThan(Signal.peak(samples), 0.97, label)
                let spectrum = PowerSpectrum(samples, sampleRate: 48_000)
                // No harsh top end: energy above 8 kHz stays far below the total.
                let air = spectrum.power(from: 8_000, to: 24_000) / spectrum.power(from: 20, to: 24_000)
                XCTAssertLessThan(10 * log10(air), -20, "\(label) has excessive hiss")
                // No uncontrolled sub-bass: energy below 25 Hz stays small.
                let sub = spectrum.power(from: 1, to: 25) / spectrum.power(from: 20, to: 24_000)
                XCTAssertLessThan(10 * log10(sub), -12, "\(label) has excessive sub-bass")
            }
        }
    }

    func testInvalidControlValuesAreRejected() {
        let renderer = NoiseRenderer(sampleRate: 48_000, seed: 3)
        renderer.setSound(.boxFan, depth: .nan, airflow: .infinity, hum: -5)
        renderer.fadeIn()
        var samples = render(renderer, frames: 48_000)
        renderer.setSound(.towerFan, depth: 500, airflow: -.infinity, hum: .nan)
        samples += render(renderer, frames: 48_000)
        renderer.setSampleRate(.nan)
        samples += render(renderer, frames: 24_000)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertLessThan(Signal.peak(samples), 0.97)
        XCTAssertGreaterThan(decibels(Signal.rms(Array(samples.suffix(24_000)))), -40)
    }

    func testSilentUntilStarted() {
        let renderer = NoiseRenderer(sampleRate: 48_000, seed: 1)
        var buffer = [Float](repeating: 1, count: 512)
        let silent = buffer.withUnsafeMutableBufferPointer { renderer.render(into: $0.baseAddress!, frameCount: 512) }
        XCTAssertTrue(silent)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 })
        XCTAssertFalse(renderer.isAudible)
    }

    func testOddAndLargeBufferSizes() {
        let renderer = playingRenderer(.basementAC)
        var all: [Float] = []
        for size in [1, 7, 64, 333, 1_024, 4_096, 4_097, 15] {
            all += render(renderer, frames: size, slice: size)
        }
        XCTAssertTrue(all.allSatisfy(\.isFinite))
        XCTAssertLessThan(Signal.peak(all), 0.97)
        XCTAssertGreaterThan(decibels(Signal.rms(all)), -40)
    }

    func testSampleRatesProduceTheSameSound() {
        let reference = renderPreset(.boxFan, seconds: 3, sampleRate: 48_000)
        let referenceSpectrum = PowerSpectrum(reference, sampleRate: 48_000)
        for rate in [44_100.0, 32_000, 96_000] {
            let samples = renderPreset(.boxFan, seconds: 3, sampleRate: rate)
            let spectrum = PowerSpectrum(samples, sampleRate: rate, segment: rate > 50_000 ? 32_768 : 16_384)
            XCTAssertEqual(decibels(spectrum.weightedRMS), decibels(referenceSpectrum.weightedRMS), accuracy: 0.6,
                           "Level changed at \(rate) Hz")
            XCTAssertEqual(spectrum.centroid / referenceSpectrum.centroid, 1, accuracy: 0.07,
                           "Tone changed at \(rate) Hz")
        }
    }

    func testCompactSpeakerRouteRemovesSubBass() {
        let full = PowerSpectrum(renderPreset(.basementAC, seconds: 3), sampleRate: 48_000)
        let compact = PowerSpectrum(renderPreset(.basementAC, seconds: 3, compactSpeaker: true), sampleRate: 48_000)
        let fullShare = full.power(from: 20, to: 80) / full.power(from: 20, to: 24_000)
        let compactShare = compact.power(from: 20, to: 80) / compact.power(from: 20, to: 24_000)
        XCTAssertLessThan(10 * log10(compactShare / fullShare), -15)
        XCTAssertLessThan(Signal.peak(renderPreset(.deepDrift, depth: 100, seconds: 3, compactSpeaker: true)), 0.97)
    }

    func testNoiseSourceStatistics() {
        var source = NoiseSource(seed: 42)
        var sum = 0.0, squares = 0.0, low: Float = 1, high: Float = -1
        let n = 1_000_000
        for _ in 0..<n {
            let v = source.nextBipolar()
            sum += Double(v); squares += Double(v * v)
            low = min(low, v); high = max(high, v)
        }
        XCTAssertEqual(sum / Double(n), 0, accuracy: 0.002)
        XCTAssertEqual(squares / Double(n), Double(NoiseSource.bipolarVariance), accuracy: 0.002)
        XCTAssertGreaterThanOrEqual(low, -1)
        XCTAssertLessThan(high, 1)

        var a = NoiseSource(seed: 1), b = NoiseSource(seed: 1), c = NoiseSource(seed: 2)
        let first = (0..<16).map { _ in a.next() }
        XCTAssertEqual(first, (0..<16).map { _ in b.next() }, "Same seed must reproduce")
        XCTAssertNotEqual(first, (0..<16).map { _ in c.next() }, "Different seeds must differ")
    }
}
