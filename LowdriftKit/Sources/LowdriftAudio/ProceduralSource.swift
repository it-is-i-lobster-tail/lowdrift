#if canImport(AVFoundation)
import AVFoundation
import LowdriftDSP

/// Builds the AVAudioSourceNode that feeds the procedural renderer to the system.
public enum ProceduralSource {
    /// How many channels the source node should carry for an output with
    /// `outputChannels` channels: mono for a mono route, otherwise stereo.
    ///
    /// The sound is mono, but it is written to both channels explicitly rather
    /// than left to the mixer to upmix: a mono input to `mainMixerNode` can
    /// reach only the left channel of a stereo output.
    public static func channelCount(forOutputChannels outputChannels: AVAudioChannelCount) -> AVAudioChannelCount {
        outputChannels == 1 ? 1 : 2
    }

    /// A non-interleaved Float32 source node at `sampleRate` carrying the same
    /// mono signal on each of its `channels`.
    ///
    /// The render block captures only the renderer and calls nothing but
    /// `NoiseRenderer.render` and a copy: no allocation, locks, logging, I/O,
    /// Objective-C messaging, async work or main-actor calls happen on the audio
    /// thread.
    public static func makeNode(
        renderer: NoiseRenderer,
        sampleRate: Double,
        channels: AVAudioChannelCount = 2
    ) -> AVAudioSourceNode? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: max(channels, 1)) else {
            return nil
        }
        return AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList in
            render(renderer, isSilence: isSilence, frameCount: frameCount, bufferList: bufferList)
        }
    }

    static func render(
        _ renderer: NoiseRenderer,
        isSilence: UnsafeMutablePointer<ObjCBool>,
        frameCount: AVAudioFrameCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard buffers.count > 0, let first = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }
        let stride = MemoryLayout<Float>.stride
        let frames = min(Int(frameCount), Int(buffers[0].mDataByteSize) / stride)
        let silent = renderer.render(into: first, frameCount: frames)
        // The format is non-interleaved: one buffer per channel, each a copy of the first.
        if buffers.count > 1 {
            for index in 1 ..< buffers.count {
                let count = min(frames, Int(buffers[index].mDataByteSize) / stride)
                buffers[index].mData?.copyMemory(from: first, byteCount: count * stride)
            }
        }
        isSilence.pointee = ObjCBool(silent)
        return noErr
    }
}
#endif
