import LowdriftAnalysis
import LowdriftCore
import LowdriftDSP
import XCTest

/// The three controls are meaningful and independent, presets are distinct, and
/// perceived loudness stays matched.
final class SoundDesignTests: XCTestCase {
    func testAnalyticModelMatchesRenderedLoudness() {
        for preset in Preset.allCases {
            let c = preset.defaultControls
            let predicted = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100,
                                                  airflow: c.airflow / 100, hum: c.hum / 100)
            let measured = PowerSpectrum(renderPreset(preset, seconds: 6), sampleRate: 48_000)
            XCTAssertEqual(decibels(measured.weightedRMS), decibels(Double(predicted.weightedRMS)), accuracy: 0.75,
                           "\(preset) weighted level differs from the model")
            XCTAssertEqual(decibels(Signal.rms(renderPreset(preset, seconds: 6))), decibels(Double(predicted.rms)),
                           accuracy: 0.75, "\(preset) raw level differs from the model")
        }
    }

    func testPresetsAreLoudnessMatched() {
        let levels = Preset.allCases.map { decibels(PowerSpectrum(renderPreset($0, seconds: 5), sampleRate: 48_000).weightedRMS) }
        XCTAssertLessThan(levels.max()! - levels.min()!, 2.0, "Preset levels: \(levels)")
    }

    func testSliderSweepsDoNotChangeLoudnessMuch() {
        for preset in Preset.allCases {
            var levels: [Double] = []
            for depth in [0.0, 50, 100] {
                for airflow in [0.0, 100] {
                    let s = renderPreset(preset, depth: depth, airflow: airflow, seconds: 2)
                    levels.append(decibels(PowerSpectrum(s, sampleRate: 48_000).weightedRMS))
                }
            }
            // Airflow intentionally adds ±0.75 dB; the darkest corners may sit slightly
            // lower where the headroom guard engages.
            XCTAssertLessThan(levels.max()! - levels.min()!, 3.0, "\(preset): \(levels)")
        }
    }

    func testDepthShiftsTheSpectrumDownward() {
        for preset in Preset.allCases {
            let centroids = [0.0, 50, 100].map {
                PowerSpectrum(renderPreset(preset, depth: $0, seconds: 2), sampleRate: 48_000).centroid
            }
            XCTAssertGreaterThan(centroids[0], centroids[1], "\(preset) Depth 0→50 did not darken")
            XCTAssertGreaterThan(centroids[1], centroids[2], "\(preset) Depth 50→100 did not darken")
            XCTAssertLessThan(centroids[2] / centroids[0], 0.75, "\(preset) Depth range is too subtle")
        }
    }

    func testAirflowChangesTextureNotOnlyLevel() {
        for preset in Preset.allCases {
            let gentle = renderPreset(preset, airflow: 0, seconds: 3)
            let strong = renderPreset(preset, airflow: 100, seconds: 3)
            let gentleLevel = decibels(PowerSpectrum(gentle, sampleRate: 48_000).weightedRMS)
            let strongLevel = decibels(PowerSpectrum(strong, sampleRate: 48_000).weightedRMS)
            XCTAssertLessThan(abs(strongLevel - gentleLevel), 2.5, "\(preset) Airflow is acting as a volume control")
            let shape = rmsDistance(normalizedBandLevels(gentle), normalizedBandLevels(strong))
            XCTAssertGreaterThan(shape, 1.2, "\(preset) Airflow barely changes the sound (\(shape) dB)")
            // Texture: stronger airflow means more turbulent flutter, more blade texture
            // and a fuller rush band, with almost no change in darkness.
            let c = preset.defaultControls
            let low = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100, airflow: 0, hum: c.hum / 100)
            let high = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100, airflow: 1, hum: c.hum / 100)
            XCTAssertGreaterThan(high.turbulence, low.turbulence * 2, "\(preset)")
            XCTAssertGreaterThanOrEqual(high.bladeDepth, low.bladeDepth, "\(preset)")
            XCTAssertGreaterThan(high.whooshGain, low.whooshGain * 2, "\(preset)")
            XCTAssertLessThan(abs(log2(high.lowpassHz / low.lowpassHz)), 0.15, "\(preset) Airflow acts like Depth")
        }
    }

    func testDepthAndAirflowAreIndependent() {
        for preset in Preset.allCases {
            let base = normalizedBandLevels(renderPreset(preset, depth: 50, airflow: 50, seconds: 2))
            let deeper = normalizedBandLevels(renderPreset(preset, depth: 100, airflow: 50, seconds: 2))
            let stronger = normalizedBandLevels(renderPreset(preset, depth: 50, airflow: 100, seconds: 2))
            let depthChange = zip(deeper, base).map { $0 - $1 }
            let airflowChange = zip(stronger, base).map { $0 - $1 }
            let dot = zip(depthChange, airflowChange).map { $0 * $1 }.reduce(0, +)
            let norms = (depthChange.map { $0 * $0 }.reduce(0, +) * airflowChange.map { $0 * $0 }.reduce(0, +)).squareRoot()
            // Deeper should not simply mean "the same as stronger" (or its inverse).
            XCTAssertLessThan(abs(dot / norms), 0.9, "\(preset) Depth and Airflow move the spectrum the same way")
        }
    }

    func testHumAddsAndRemovesTonalCharacter() {
        for preset in Preset.allCases {
            let f0 = Double(preset.soundProfile.character.humHz)
            let none = PowerSpectrum(renderPreset(preset, hum: 0, seconds: 6), sampleRate: 48_000, segment: 32_768)
            let more = PowerSpectrum(renderPreset(preset, hum: 100, seconds: 6), sampleRate: 48_000, segment: 32_768)
            let partials = (1...8).map { f0 * Double($0) }.filter { $0 < 1_000 }
            let noneProminence = partials.map { none.tonalProminence(at: $0) }.max()!
            let moreProminence = partials.map { more.tonalProminence(at: $0) }.max()!
            XCTAssertLessThan(noneProminence, 6, "\(preset) has tones with Hum at 0")
            XCTAssertGreaterThan(moreProminence, 12, "\(preset) Hum at 100 is inaudible")
            // Restrained: even at 100 no partial towers over the noise (≈ +10 dB TNR max).
            XCTAssertLessThan(moreProminence, 34, "\(preset) Hum at 100 is a whine")
        }
    }

    func testHumDoesNotChangeOverallLoudness() {
        for preset in [Preset.boxFan, .basementAC, .towerFan, .windowAC, .deskFan] {
            let none = decibels(PowerSpectrum(renderPreset(preset, hum: 0, seconds: 3), sampleRate: 48_000).weightedRMS)
            let more = decibels(PowerSpectrum(renderPreset(preset, hum: 100, seconds: 3), sampleRate: 48_000).weightedRMS)
            XCTAssertEqual(none, more, accuracy: 1.0, "\(preset)")
        }
    }

    func testPresetsAreAudiblyDistinct() {
        let spectra = Preset.allCases.map { ($0, normalizedBandLevels(renderPreset($0, seconds: 4))) }
        for i in spectra.indices {
            for j in spectra.indices where j > i {
                let distance = rmsDistance(spectra[i].1, spectra[j].1)
                XCTAssertGreaterThan(distance, 2.0, "\(spectra[i].0) and \(spectra[j].0) sound too alike (\(distance) dB)")
            }
        }
    }

    func testDeepPresetsAreDarkerThanAiryOnes() {
        func centroid(_ preset: Preset) -> Double { PowerSpectrum(renderPreset(preset, seconds: 3), sampleRate: 48_000).centroid }
        XCTAssertLessThan(centroid(.deepDrift), centroid(.basementAC))
        XCTAssertLessThan(centroid(.basementAC), centroid(.softFan))
        XCTAssertLessThan(centroid(.cabinAir), centroid(.ceilingFan))
        XCTAssertLessThan(centroid(.ceilingFan), centroid(.windowAC))
        XCTAssertLessThan(centroid(.windowAC), centroid(.deskFan))
    }
}

/// Flutter and Drift: texture over time, never level or tone.
final class TextureControlTests: XCTestCase {
    /// Power of the envelope's spectral line at the blade rate, from 2 ms blocks.
    private func bladeLine(_ samples: [Float], hz: Double) -> Double {
        let block = 96
        let envelope = stride(from: 0, to: samples.count - block, by: block).map { start -> Double in
            Signal.rms(samples[start ..< start + block])
        }
        let mean = envelope.reduce(0, +) / Double(envelope.count)
        let spectrum = PowerSpectrum(envelope.map { Float($0 / mean - 1) }, sampleRate: 500, segment: 8_192)
        return spectrum.power(from: hz * 0.995, to: hz * 1.005)
    }

    /// Spread of the level measured over consecutive 2-second windows, in dB.
    private func slowLevelSpread(_ samples: [Float]) -> Double {
        let window = 96_000
        let levels = stride(from: 0, to: samples.count - window + 1, by: window / 2).map {
            decibels(Signal.rms(samples[$0 ..< $0 + window]))
        }
        return levels.max()! - levels.min()!
    }

    func testFlutterAndDriftAtNeutralLeaveTheSoundUnchanged() {
        for preset in Preset.allCases {
            let c = preset.defaultControls
            XCTAssertEqual(c.flutter, SoundControls.neutral)
            XCTAssertEqual(c.drift, SoundControls.neutral)
            let a = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100, airflow: c.airflow / 100, hum: c.hum / 100)
            let b = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100, airflow: c.airflow / 100,
                                          hum: c.hum / 100, flutter: 0.5, drift: 0.5)
            XCTAssertEqual(a.weightedRMS, b.weightedRMS)
            XCTAssertEqual(a.bladeDepth, b.bladeDepth)
            XCTAssertEqual(a.turbulence, b.turbulence)
        }
    }

    func testFlutterGoesFromSmoothToChoppy() {
        for preset in Preset.allCases {
            let c = preset.defaultControls
            let smooth = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100, airflow: c.airflow / 100,
                                               hum: c.hum / 100, flutter: 0)
            let choppy = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100, airflow: c.airflow / 100,
                                               hum: c.hum / 100, flutter: 1)
            XCTAssertEqual(smooth.bladeDepth, 0, "\(preset) Smooth still has blade texture")
            XCTAssertGreaterThan(choppy.bladeDepth, 0.03, "\(preset) Choppy is too subtle")
            XCTAssertLessThanOrEqual(choppy.bladeDepth, 0.09, "\(preset) Choppy pumps")
            XCTAssertGreaterThan(choppy.turbulence, smooth.turbulence * 3, "\(preset)")
        }
        // Sounds without their own blade rate use a 26 Hz one when Choppy. Drift is
        // held at Steady so the blade rate stays exact for the narrow measurement, and
        // Hum is off because motor partials also beat at the blade rate.
        for preset in [Preset.boxFan, .ceilingFan, .bedroomFan] {
            let character = preset.soundProfile.character
            let hz = Double(character.bladeHz > 0 ? character.bladeHz : 26)
            let smooth = bladeLine(renderPreset(preset, hum: 0, flutter: 0, drift: 0, seconds: 20), hz: hz)
            let choppy = bladeLine(renderPreset(preset, hum: 0, flutter: 100, drift: 0, seconds: 20), hz: hz)
            XCTAssertGreaterThan(10 * log10(choppy / smooth), 6, "\(preset) Flutter is not audible in the envelope")
        }
    }

    func testDriftGoesFromSteadyToWandering() {
        for preset in Preset.allCases {
            let c = preset.defaultControls
            let steady = NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100, airflow: c.airflow / 100,
                                               hum: c.hum / 100, drift: 0)
            XCTAssertEqual(steady.weightedRMS, NoiseRenderer.predict(preset.soundProfile, depth: c.depth / 100,
                                                                     airflow: c.airflow / 100, hum: c.hum / 100,
                                                                     drift: 1).weightedRMS)
        }
        let steady = slowLevelSpread(renderPreset(.basementAC, drift: 0, seconds: 60))
        let wandering = slowLevelSpread(renderPreset(.basementAC, drift: 100, seconds: 60))
        XCTAssertGreaterThan(wandering, steady, "Drift does not add slow variation")
        XCTAssertLessThan(wandering, 2.5, "Wandering is pumping (\(wandering) dB)")
    }

    func testFlutterAndDriftAreNotVolumeOrToneControls() {
        for preset in Preset.allCases {
            var levels: [Double] = []
            var centroids: [Double] = []
            for (flutter, drift) in [(0.0, 0.0), (100.0, 100.0), (0.0, 100.0), (100.0, 0.0)] {
                let spectrum = PowerSpectrum(renderPreset(preset, flutter: flutter, drift: drift, seconds: 3), sampleRate: 48_000)
                levels.append(decibels(spectrum.weightedRMS))
                centroids.append(spectrum.centroid)
            }
            XCTAssertLessThan(levels.max()! - levels.min()!, 1.5, "\(preset): \(levels)")
            XCTAssertLessThan(centroids.max()! / centroids.min()!, 1.15, "\(preset) changes tone: \(centroids)")
        }
    }

    func testExtremeTextureStaysBounded() {
        for preset in Preset.allCases {
            for (depth, airflow) in [(0.0, 100.0), (100.0, 100.0)] {
                let samples = renderPreset(preset, depth: depth, airflow: airflow, hum: 100, flutter: 100, drift: 100, seconds: 2)
                XCTAssertTrue(samples.allSatisfy(\.isFinite))
                XCTAssertLessThan(Signal.peak(samples), 0.97, "\(preset) d\(depth) a\(airflow)")
            }
        }
    }
}
