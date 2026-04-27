import Foundation

// MARK: - Now Playing State

/// The single source of truth for the currently playing item.
/// Populated by polling Kodi every second in `ContentView` and injected
/// into the view hierarchy via `.environment(state)`.
@MainActor
@Observable
final class NowPlayingState {
    var title: String = ""
    var director: String = ""
    /// The current subtitle track index as returned by Kodi (e.g. "0", "1").
    var currentSubtitleTrackId: String? = nil
    var artworkURL: URL? = nil
    var fanartURL: URL? = nil
    var clearLogoURL: URL? = nil
    var atmosEnabled: Bool = false
    var dtsxEnabled: Bool = false
    var subtitleEnabled: Bool = false
    var isPlaying: Bool = false
    var progress: Double = 0
    var duration: Double = 0
    var volume: Double = 0.5
    var playerId: Int = -1
    var studio: String = ""
    var subtitles: [(id: String, name: String)] = []
    var audiotracks: [(id: String, name: String)] = []
    var imdbId: String = ""

    // MARK: - Player Actions

    func togglePlayPause() async {
        isPlaying.toggle()
        let speed = await KodiService.setPlayPause(playerId: playerId, play: isPlaying)?.speed
        isPlaying = (speed ?? 0) != 0
    }

    func seekBackward() async {
        print("Seeking backward by 10 seconds")
        await KodiService.seek(playerId: playerId, to: -10)
    }

    func seekForward() async {
        print("Seeking forward by 10 seconds")
        await KodiService.seek(playerId: playerId, to: 10)
    }

    /// Enables a specific subtitle track, or passes `nil` to turn subtitles off.
    func setSubtitle(index: Int?) async {
        currentSubtitleTrackId = index.map { String($0) }
        subtitleEnabled = index != nil
        await KodiService.setSubtitle(playerId: playerId, index: index)
    }

    func setAudioTrack(index: Int) async {
        await KodiService.setAudioTrack(playerId: playerId, index: index)
    }

    /// Seeks to an absolute position. Uses the current `playerId`.
    func seekTo(seconds: Double) async {
        await KodiService.seekToTime(playerId: playerId, to: seconds)
    }
}
