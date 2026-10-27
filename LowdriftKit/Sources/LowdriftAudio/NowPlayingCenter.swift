#if os(iOS)
import LowdriftCore
import MediaPlayer
import UIKit

/// Lock Screen, Control Center and headphone controls. Lowdrift is an endless
/// generator, so only Play/Pause are offered: no duration, progress, scrubbing
/// or skipping.
@MainActor
public final class NowPlayingCenter {
    private let controller: PlaybackController
    private let artwork: MPMediaItemArtwork?

    public init(controller: PlaybackController, artworkImage: UIImage?) {
        self.controller = controller
        if let image = artworkImage {
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            artwork = nil
        }
    }

    public func registerCommands() {
        let commands = MPRemoteCommandCenter.shared()
        let controller = controller

        commands.playCommand.isEnabled = true
        commands.playCommand.addTarget { _ in
            Self.onMainActor {
                controller.play()
                return controller.isPlaying ? .success : .commandFailed
            }
        }
        commands.pauseCommand.isEnabled = true
        commands.pauseCommand.addTarget { _ in
            Self.onMainActor {
                controller.pause()
                return .success
            }
        }
        commands.stopCommand.isEnabled = true
        commands.stopCommand.addTarget { _ in
            Self.onMainActor {
                controller.pause()
                return .success
            }
        }
        commands.togglePlayPauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.addTarget { _ in
            Self.onMainActor {
                let wasPlaying = controller.isPlaying
                controller.togglePlayback()
                return wasPlaying || controller.isPlaying ? .success : .commandFailed
            }
        }

        let unsupported: [MPRemoteCommand] = [
            commands.nextTrackCommand, commands.previousTrackCommand,
            commands.skipForwardCommand, commands.skipBackwardCommand,
            commands.seekForwardCommand, commands.seekBackwardCommand,
            commands.changePlaybackPositionCommand, commands.changePlaybackRateCommand,
            commands.changeRepeatModeCommand, commands.changeShuffleModeCommand,
            commands.likeCommand, commands.dislikeCommand, commands.bookmarkCommand,
        ]
        for command in unsupported {
            command.isEnabled = false
        }
    }

    /// Publishes the selected preset and play state.
    public func update() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: controller.selectedPreset.name,
            MPMediaItemPropertyArtist: "Lowdrift",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: controller.isPlaying ? 1.0 : 0.0,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Remote command handlers are delivered on the main thread; if one ever is
    /// not, hop there and report success optimistically.
    nonisolated private static func onMainActor(
        _ body: @escaping @MainActor @Sendable () -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body() }
        }
        Task { @MainActor in _ = body() }
        return .success
    }
}
#endif
