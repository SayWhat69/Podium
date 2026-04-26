import AVFoundation
import MediaPlayer

/// Manages the system Now Playing session: lock screen metadata, remote commands,
/// silent background audio (needed to keep remote commands responsive), and
/// language option menus for subtitles and audio tracks.
final class NowPlayingSession {
    private var player: AVAudioPlayer?
    private var languageOptionGroups: [MPNowPlayingInfoLanguageOptionGroup] = []
    private var currentLanguageOptions: [MPNowPlayingInfoLanguageOption] = []

    private var onPlayPause: (@Sendable () -> Void)?
    private var onBackward: (@Sendable () -> Void)?
    private var onForward: (@Sendable () -> Void)?
    private var onSubtitleSelected: (@Sendable (String?) -> Void)?
    private var onAudioTrackSelected: (@Sendable (String) -> Void)?

    init() {
        setupAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Silent audio

    /// Starts looping a near-silent audio file so the system keeps remote commands active.
    func startSilentAudio() {
        guard let url = Bundle.main.url(forResource: "silent", withExtension: "mp3") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 0.01
        player?.play()
    }

    func stopSilentAudio() {
        player?.stop()
    }

    // MARK: - Now Playing info

    func update(
        title: String,
        subtitle: String?,
        artworkURL: URL?,
        isPlaying: Bool,
        progress: Double,
        duration: Double,
        studio: String
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                    title,
            MPMediaItemPropertyArtist:                   subtitle ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPMediaItemPropertyPlaybackDuration:         duration,
            MPNowPlayingInfoPropertyPlaybackRate:        isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType:           MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyAlbumTitle:               studio
        ]

        if !languageOptionGroups.isEmpty {
            info[MPNowPlayingInfoPropertyAvailableLanguageOptions] = languageOptionGroups
            info[MPNowPlayingInfoPropertyCurrentLanguageOptions]   = currentLanguageOptions
        }

        if let url = artworkURL {
            Task {
                if let data = try? await URLSession.shared.data(from: url).0,
                   let image = UIImage(data: data) {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        stopSilentAudio()
    }

    // MARK: - Language options

    func updateLanguageOptions(
        subtitleTracks: [(id: String, name: String)],
        audioTracks: [(id: String, name: String)],
        currentSubtitleId: String?,
        currentAudioId: String?
    ) {
        let subtitleOptions = subtitleTracks.map {
            MPNowPlayingInfoLanguageOption(
                type: .legible,
                languageTag: $0.id,
                characteristics: nil,
                displayName: $0.name,
                identifier: $0.id
            )
        }
        let audioOptions = audioTracks.map {
            MPNowPlayingInfoLanguageOption(
                type: .audible,
                languageTag: $0.id,
                characteristics: nil,
                displayName: $0.name,
                identifier: $0.id
            )
        }

        languageOptionGroups = [
            MPNowPlayingInfoLanguageOptionGroup(
                languageOptions: subtitleOptions,
                defaultLanguageOption: subtitleOptions.first { $0.identifier == currentSubtitleId },
                allowEmptySelection: true
            ),
            MPNowPlayingInfoLanguageOptionGroup(
                languageOptions: audioOptions,
                defaultLanguageOption: audioOptions.first { $0.identifier == currentAudioId },
                allowEmptySelection: false
            )
        ]
        currentLanguageOptions = [
            subtitleOptions.first { $0.identifier == currentSubtitleId },
            audioOptions.first    { $0.identifier == currentAudioId }
        ].compactMap { $0 }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyAvailableLanguageOptions] = languageOptionGroups
        info[MPNowPlayingInfoPropertyCurrentLanguageOptions]   = currentLanguageOptions
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote command handlers

    func setHandlers(
        onPlayPause: @escaping @Sendable () -> Void,
        onBackward: @escaping @Sendable () -> Void,
        onForward: @escaping @Sendable () -> Void,
        onSubtitleSelected: @escaping @Sendable (String?) -> Void,
        onAudioTrackSelected: @escaping @Sendable (String) -> Void
    ) {
        self.onPlayPause          = onPlayPause
        self.onBackward           = onBackward
        self.onForward            = onForward
        self.onSubtitleSelected   = onSubtitleSelected
        self.onAudioTrackSelected = onAudioTrackSelected
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget  { [weak self] _ in self?.onPlayPause?(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.onPlayPause?(); return .success }

        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.onBackward?(); return .success }

        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget  { [weak self] _ in self?.onForward?(); return .success }

        center.enableLanguageOptionCommand.isEnabled = true
        center.enableLanguageOptionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangeLanguageOptionCommandEvent,
                  let id = e.languageOption.identifier
            else { return .commandFailed }
            if e.languageOption.languageOptionType == .legible {
                self?.onSubtitleSelected?(id)
            } else {
                self?.onAudioTrackSelected?(id)
            }
            return .success
        }

        center.disableLanguageOptionCommand.isEnabled = true
        center.disableLanguageOptionCommand.addTarget { [weak self] _ in
            self?.onSubtitleSelected?(nil)
            return .success
        }
    }
}
