import Foundation
import LowdriftAudio
import LowdriftCore
import UIKit

/// Owns the single playback controller and the system integrations around it.
/// Shared by the UI and by App Intents, which may launch the app in the background.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let controller: PlaybackController
    private let output: AudioEngineOutput
    private let session: AudioSessionCoordinator
    private let nowPlaying: NowPlayingCenter

    private init() {
        let output = AudioEngineOutput()
        let controller = PlaybackController(store: SettingsStore(storage: Self.makeStorage()), output: output)
        let nowPlaying = NowPlayingCenter(controller: controller, artworkImage: UIImage(named: "NowPlayingArtwork"))
        self.output = output
        self.controller = controller
        self.nowPlaying = nowPlaying
        session = AudioSessionCoordinator(controller: controller, output: output)

        controller.onStateChange = { [weak nowPlaying] in
            nowPlaying?.update()
        }
        session.startObserving()
        nowPlaying.registerCommands()
    }

    /// Settings live in the standard defaults. UI tests launch with a private,
    /// optionally cleared domain so they never touch real settings.
    private static func makeStorage() -> UserDefaults {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-LowdriftUITesting") else { return .standard }
        let suite = "lowdrift.uitesting"
        guard let defaults = UserDefaults(suiteName: suite) else { return .standard }
        if arguments.contains("-LowdriftResetSettings") {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
