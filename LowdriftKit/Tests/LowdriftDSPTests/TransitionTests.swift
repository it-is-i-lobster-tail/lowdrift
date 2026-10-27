import LowdriftAnalysis
import LowdriftCore
import LowdriftDSP
import XCTest

/// Starts, stops, slider moves and preset changes never click, pop, gap or jump.
final class TransitionTests: XCTestCase {
    private let rate = 48_000.0

    func testFadeInStartsFromSilenceAndRisesSmoothly() {
        let renderer = NoiseRenderer(sampleRate: rate, seed: 11)
        renderer.setSound(.basementAC, depth: 0.8, airflow: 0.7, hum: 0.35)
        renderer.fadeIn()
        let samples = render(renderer, frames: Int(rate * 2))
        XCTAssertLessThan(abs(samples[0]), 1e-4, "Playback must not start with a step")
        XCTAssertLessThan(Signal.peak(Array(samples.prefix(480))), 0.002, "First 10 ms must be nearly silent")
        let envelope = Signal.envelope(samples, window: 2_400).map(decibels)
        let steady = envelope.suffix(10).reduce(0, +) / 10
        // Audible quickly (within 0.3 s) but never overshooting the steady level.
        XCTAssertGreaterThan(envelope[6], steady - 20)
        XCTAssertLessThan(envelope.max()!, steady + 4)
        XCTAssertTrue(renderer.isAudible)
    }

    func testFadeOutReachesTrueSilenceAndReportsIt() {
        let renderer = playingRenderer(.boxFan)
        renderer.fadeOut()
        let samples = render(renderer, frames: Int(rate * 0.8))
        XCTAssertTrue(samples.suffix(2_000).allSatisfy { $0 == 0 })
        XCTAssertFalse(renderer.isAudible)
        // Decay is smooth and one-directional: each 100 ms is quieter than the last.
        let envelope = Signal.envelope(Array(samples.prefix(Int(rate * 0.6))), window: 4_800).map(decibels)
        for (a, b) in zip(envelope, envelope.dropFirst()) { XCTAssertLessThan(b - a, 0.5) }
    }

    func testPauseThenQuickResumeDoesNotDip() {
        let renderer = playingRenderer(.airVent)
        let before = Signal.rms(render(renderer, frames: 9_600))
        renderer.fadeOut()
        _ = render(renderer, frames: 4_800)
        renderer.fadeIn()
        let after = render(renderer, frames: Int(rate * 1.5))
        XCTAssertTrue(after.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(Signal.rms(after.suffix(9_600)), before * 0.7, "Resuming mid-fade must come back up")
    }

    func testPresetCrossfadeHasNoGapOrJump() {
        let pairs: [(Preset, Preset)] = [(.basementAC, .airVent), (.softFan, .deepDrift), (.towerFan, .boxFan)]
        for (from, to) in pairs {
            let renderer = playingRenderer(from)
            let before = PowerSpectrum(render(renderer, frames: Int(rate)), sampleRate: rate).weightedRMS
            let c = to.defaultControls
            renderer.setSound(to.soundProfile, depth: c.depth / 100, airflow: c.airflow / 100, hum: c.hum / 100)
            let transition = render(renderer, frames: Int(rate * 2))
            let after = PowerSpectrum(render(renderer, frames: Int(rate)), sampleRate: rate).weightedRMS
            XCTAssertTrue(transition.allSatisfy(\.isFinite))
            XCTAssertLessThan(Signal.peak(transition), 0.97)
            XCTAssertEqual(decibels(after), decibels(before), accuracy: 1.5, "\(from)→\(to) changed loudness")
            // Never a gap: every 50 ms of the transition carries substantial signal.
            let quietest = Signal.envelope(transition, window: 2_400).min()!
            let lowerSteady = min(Signal.rms(renderPreset(from, seconds: 1)), Signal.rms(renderPreset(to, seconds: 1)))
            XCTAssertGreaterThan(decibels(quietest), decibels(lowerSteady) - 6, "\(from)→\(to) dips toward silence")
            // Smooth: weighted level in 250 ms windows moves gradually.
            let windows = stride(from: 0, to: transition.count - 12_000, by: 12_000).map {
                decibels(PowerSpectrum(Array(transition[$0 ..< $0 + 12_000]), sampleRate: rate, segment: 4_096).weightedRMS)
            }
            for (a, b) in zip(windows, windows.dropFirst()) {
                XCTAssertLessThan(abs(b - a), 2.5, "\(from)→\(to) has a sudden level step")
            }
        }
    }

    func testRapidPresetChangesStayStable() {
        let renderer = playingRenderer(.softFan)
        var noise = NoiseSource(seed: 99)
        var samples: [Float] = []
        for step in 0..<200 {
            let profile = SoundProfile(rawValue: Int(noise.next() % 6))!
            renderer.setSound(profile, depth: Double(noise.next() % 101) / 100,
                              airflow: Double(noise.next() % 101) / 100, hum: Double(noise.next() % 101) / 100)
            if step % 37 == 0 { renderer.fadeOut(seconds: 0.2) }
            if step % 37 == 5 { renderer.fadeIn() }
            samples += render(renderer, frames: 480)
        }
        samples += render(renderer, frames: Int(rate * 2))
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertLessThan(Signal.peak(samples), 0.97)
        XCTAssertGreaterThan(decibels(Signal.rms(Array(samples.suffix(24_000)))), -40, "Got stuck silent")
    }

    func testSliderJumpGlidesInsteadOfStepping() {
        let renderer = playingRenderer(.boxFan)
        _ = render(renderer, frames: 4_800)
        renderer.setSound(.boxFan, depth: 1, airflow: 0, hum: 1)
        let samples = render(renderer, frames: Int(rate * 1.5))
        XCTAssertLessThan(Signal.peak(samples), 0.97)
        let envelope = Signal.envelope(samples, window: 480).map(decibels)
        let smoothed = stride(from: 0, to: envelope.count - 5, by: 5).map { envelope[$0 ..< $0 + 5].reduce(0, +) / 5 }
        for (a, b) in zip(smoothed, smoothed.dropFirst()) {
            XCTAssertLessThan(abs(b - a), 2.5, "Slider change produced a jump")
        }
        // The new sound has arrived after the glide.
        let early = PowerSpectrum(Array(samples.prefix(9_600)), sampleRate: rate, segment: 4_096).centroid
        let late = PowerSpectrum(Array(samples.suffix(19_200)), sampleRate: rate, segment: 4_096).centroid
        XCTAssertLessThan(late, early * 0.85)
    }

    func testRestartAfterAbruptStopFadesInAgain() {
        let renderer = playingRenderer(.deepDrift)
        // The engine was stopped by the system mid-signal; on restart the renderer
        // must not resume at full level.
        renderer.prepareForRestart()
        renderer.fadeIn()
        let samples = render(renderer, frames: 4_800)
        XCTAssertLessThan(abs(samples[0]), 1e-4)
        XCTAssertLessThan(Signal.peak(Array(samples.prefix(240))), 0.002)
    }

    func testRouteChangeToSpeakerIsSmooth() {
        let renderer = playingRenderer(.basementAC)
        renderer.setCompactSpeaker(true)
        let samples = render(renderer, frames: Int(rate))
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        XCTAssertLessThan(Signal.peak(samples), 0.97)
        let envelope = Signal.envelope(samples, window: 2_400).map(decibels)
        for (a, b) in zip(envelope, envelope.dropFirst()) { XCTAssertLessThan(abs(b - a), 6) }
    }
}
