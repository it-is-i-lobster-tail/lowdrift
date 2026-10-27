#if canImport(AVFoundation)
import AVFoundation
import LowdriftAudio
import LowdriftDSP
import XCTest

/// Runs the real source node inside a real AVAudioEngine (offline manual
/// rendering), so the render block and graph are exercised without hardware.
final class EngineRenderingTests: XCTestCase {
    private struct Harness {
        let engine: AVAudioEngine
        let renderer: NoiseRenderer
        let buffer: AVAudioPCMBuffer

        /// An engine whose output has `outputChannels` channels, with the source
        /// node built the way `AudioEngineOutput` builds it for that output.
        init(sampleRate: Double, outputChannels: AVAudioChannelCount = 2, seed: UInt64 = 9) throws {
            renderer = NoiseRenderer(sampleRate: sampleRate, seed: seed)
            engine = AVAudioEngine()
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: outputChannels))
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
            let node = try XCTUnwrap(ProceduralSource.makeNode(
                renderer: renderer,
                sampleRate: sampleRate,
                channels: ProceduralSource.channelCount(forOutputChannels: outputChannels)
            ))
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: node.outputFormat(forBus: 0))
            try engine.start()
            buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096))
        }

        /// Renders `seconds` of output, one array per output channel.
        func render(seconds: Double) throws -> [[Float]] {
            let channelCount = Int(engine.manualRenderingFormat.channelCount)
            var output = [[Float]](repeating: [], count: channelCount)
            let total = Int(seconds * engine.manualRenderingFormat.sampleRate)
            while output[0].count < total {
                let status = try engine.renderOffline(AVAudioFrameCount(min(4_096, total - output[0].count)), to: buffer)
                XCTAssertEqual(status, .success)
                let channels = try XCTUnwrap(buffer.floatChannelData)
                let n = Int(buffer.frameLength)
                for channel in 0 ..< channelCount {
                    output[channel] += UnsafeBufferPointer(start: channels[channel], count: n)
                }
            }
            return output
        }
    }

    /// The renderer's own output, in the same block sizes the harness uses.
    private func renderDirectly(_ renderer: NoiseRenderer, seconds: Double, sampleRate: Double) -> [Float] {
        let total = Int(seconds * sampleRate)
        var output: [Float] = []
        var block = [Float](repeating: 0, count: 4_096)
        while output.count < total {
            let n = min(4_096, total - output.count)
            block.withUnsafeMutableBufferPointer { _ = renderer.render(into: $0.baseAddress!, frameCount: n) }
            output += block.prefix(n)
        }
        return output
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        (samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(samples.count, 1))).squareRoot()
    }

    private func decibels(_ samples: ArraySlice<Float>) -> Double {
        20 * log10(max(rms(samples), 1e-12))
    }

    func testSourceNodePlaysThroughTheEngine() throws {
        for rate in [44_100.0, 48_000] {
            for outputChannels: AVAudioChannelCount in [2, 1] {
                let context = "\(rate) Hz, \(outputChannels) channel(s)"
                let harness = try Harness(sampleRate: rate, outputChannels: outputChannels)
                let reference = NoiseRenderer(sampleRate: rate, seed: 9)
                for renderer in [harness.renderer, reference] {
                    renderer.setSound(.basementAC, depth: 0.8, airflow: 0.7, hum: 0.35)
                }

                let before = try harness.render(seconds: 0.5)
                _ = renderDirectly(reference, seconds: 0.5, sampleRate: rate)
                XCTAssertTrue(before.allSatisfy { $0.allSatisfy { $0 == 0 } }, "Silent until Play (\(context))")

                harness.renderer.fadeIn()
                reference.fadeIn()
                let playing = try harness.render(seconds: 3)
                let direct = renderDirectly(reference, seconds: 3, sampleRate: rate)
                XCTAssertEqual(playing.count, Int(outputChannels))
                for (index, channel) in playing.enumerated() {
                    XCTAssertTrue(channel.allSatisfy { $0.isFinite && abs($0) < 1 }, "Channel \(index) bounded (\(context))")
                    let level = decibels(channel.suffix(Int(rate)))
                    XCTAssertGreaterThan(level, -40, "Channel \(index) audible through the mixer (\(context))")
                    XCTAssertLessThan(level, -10, "Channel \(index) (\(context))")
                    // The mixer must pass the sound at unity gain, so the
                    // loudness model's calibration holds on every channel.
                    XCTAssertEqual(level, decibels(direct.suffix(Int(rate))), accuracy: 0.5, "Channel \(index) at unity gain (\(context))")
                }
                XCTAssertTrue(playing.allSatisfy { $0 == playing[0] }, "Every channel carries the same signal (\(context))")

                harness.renderer.fadeOut()
                let paused = try harness.render(seconds: 1)
                XCTAssertTrue(paused.allSatisfy { $0.suffix(4_096).allSatisfy { $0 == 0 } }, "Fades to true silence (\(context))")
                XCTAssertFalse(harness.renderer.isAudible)
                harness.engine.stop()
            }
        }
    }

    func testOddRenderSizesThroughTheEngine() throws {
        let harness = try Harness(sampleRate: 48_000)
        harness.renderer.setSound(.towerFan, depth: 0.45, airflow: 0.55, hum: 0.25)
        harness.renderer.fadeIn()
        for frames in [1, 15, 512, 4_096, 333] {
            let status = try harness.engine.renderOffline(AVAudioFrameCount(frames), to: harness.buffer)
            XCTAssertEqual(status, .success)
            XCTAssertEqual(Int(harness.buffer.frameLength), frames)
        }
        harness.engine.stop()
    }

    func testChannelCountFollowsTheRoute() {
        XCTAssertEqual(ProceduralSource.channelCount(forOutputChannels: 1), 1)
        XCTAssertEqual(ProceduralSource.channelCount(forOutputChannels: 2), 2)
        // Multichannel outputs (HDMI, USB interfaces) get the stereo pair.
        XCTAssertEqual(ProceduralSource.channelCount(forOutputChannels: 6), 2)
        XCTAssertEqual(ProceduralSource.channelCount(forOutputChannels: 0), 2)
    }
}
#endif
