import SwiftUI
import SwiftData

struct ContentView: View {

    // MARK: - State

    @State private var state = NowPlayingState()
    @State private var path = [SettingsDestination]()
    @StateObject private var networkMonitor = NetworkMonitorService()

    private let nowPlayingSession = NowPlayingSession()

    // MARK: - SwiftData

    @Environment(\.modelContext) private var modelContext
    @Query private var devices: [Device]
    @Query private var settingsQuery: [AppSettings]

    private var settings: AppSettings {
        if let existing = settingsQuery.first { return existing }
        let settings = AppSettings()
        modelContext.insert(settings)
        return settings
    }

    // MARK: - Derived state

    private var shouldShowDeviceSheet: Bool {
        devices.isEmpty || settings.selectedDevice == nil
    }

    private var isDebugModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debug_mode")
    }

    // MARK: - Body

    var body: some View {
        playerView()
            .sheet(isPresented: .constant(shouldShowDeviceSheet)) {
                NavigationStack(path: $path) {
                    SelectDeviceView(settings: settings, path: $path)
                        .navigationDestination(for: String.self) { destination in
                            if destination == "addDevice" {
                                AddDeviceView(settings: settings, path: $path)
                            }
                        }
                }
                .interactiveDismissDisabled(devices.isEmpty)
            }
            .onChange(of: networkMonitor.isConnectedToWiFi) { _, _ in
                if networkMonitor.isConnectedToWiFi || isDebugModeEnabled {
                    WindowManager.shared.hideNoWiFi()
                } else {
                    WindowManager.shared.showNoWiFi()
                }
            }
            .onAppear {
                if !networkMonitor.isConnectedToWiFi && !isDebugModeEnabled {
                    WindowManager.shared.showNoWiFi()
                }
                if let device = settings.selectedDevice {
                    KodiService.configure(host: device.ip, port: device.port)
                }
            }
            .onChange(of: settings.selectedDevice) {
                guard let device = settings.selectedDevice else { return }
                KodiService.configure(host: device.ip, port: device.port)
            }
            .environment(settings)
    }

    // MARK: - Player view

    @ViewBuilder
    private func playerView() -> some View {
        FullscreenPlayerView()
            .onAppear {
                nowPlayingSession.setHandlers(
                    onPlayPause: { Task { await state.togglePlayPause() } },
                    onBackward:  { Task { await state.seekBackward() } },
                    onForward:   { Task { await state.seekForward() } },
                    onSubtitleSelected: { id in
                        Task { await state.setSubtitle(index: id.flatMap { Int($0) }) }
                    },
                    onAudioTrackSelected: { id in
                        guard let index = Int(id) else { return }
                        Task { await state.setAudioTrack(index: index) }
                    }
                )
            }
            .task {
                while !Task.isCancelled {
                    await fetchDataFromKodi()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .task {
                while !Task.isCancelled {
                    if state.isPlaying { state.progress += 1 }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .onChange(of: state.isPlaying) {
                if state.isPlaying { nowPlayingSession.startSilentAudio() }
                else               { nowPlayingSession.stopSilentAudio() }
            }
            .onChange(of: state.progress) {
                nowPlayingSession.update(
                    title:      state.title,
                    subtitle:   state.director,
                    artworkURL: state.artworkURL,
                    isPlaying:  state.isPlaying,
                    progress:   state.progress,
                    duration:   state.duration,
                    studio:     state.studio
                )
            }
            .environment(state)
    }

    // MARK: - Data fetching

    private func fetchDataFromKodi() async {
        if isDebugModeEnabled {
            populateDebugState()
            return
        }

        guard let playerId = (await KodiService.getActivePlayers())?
                .first(where: { $0.type == "video" })?
                .playerId
        else {
            state = NowPlayingState() // Reset state when there are no active players
            return
        }
        state.playerId = playerId

        guard let props = await KodiService.getPlayerProperties(playerId: playerId) else { return }

        let kodiProgress = props.time.totalSeconds
        if abs(kodiProgress - state.progress) > 2 {
            state.progress = kodiProgress
        }
        state.duration               = props.totalTime.totalSeconds
        state.isPlaying              = props.speed != 0
        state.atmosEnabled           = props.currentAudioStream.codec == "truehd_atmos"
        state.dtsxEnabled            = props.currentAudioStream.codec == "dtshd_ma_x"
        state.subtitles              = props.subtitles.map { (id: String($0.index), name: $0.language) }
        state.audiotracks            = props.audioStreams.map { (id: String($0.index), name: $0.name) }
        state.subtitleEnabled        = props.subtitleEnabled
        state.currentSubtitleTrackId = String(props.currentSubtitle.index)

        nowPlayingSession.updateLanguageOptions(
            subtitleTracks:    state.subtitles,
            audioTracks:       state.audiotracks,
            currentSubtitleId: String(props.currentSubtitle.index),
            currentAudioId:    String(props.currentAudioStream.index)
        )

        guard let meta = await KodiService.fetchNowPlayingMetadata(playerId: playerId) else { return }
        state.title        = meta.title
        state.director     = meta.subtitle ?? ""
        state.artworkURL   = meta.artworkURL
        state.fanartURL    = meta.fanartURL
        state.clearLogoURL = meta.clearLogoURL
        state.studio       = meta.studio ?? ""
        state.imdbId       = meta.imdbId ?? ""
    }

    /// Fills the state with hard-coded data for UI development without a Kodi instance.
    private func populateDebugState() {
        state.title           = "Avengers: Endgame"
        state.director        = "Anthony Russo, Joe Russo"
        state.artworkURL      = "image://https%3a%2f%2fassets.fanart.tv%2ffanart%2favengers-infinity-war---part-ii-5c8c28d2aae85.jpg/".kodiImageURL
        state.fanartURL       = "image://https%3a%2f%2fassets.fanart.tv%2ffanart%2favengers-endgame-5c979f35948c7.jpg/".kodiImageURL
        state.clearLogoURL    = "image://https%3a%2f%2fimage.tmdb.org%2ft%2fp%2foriginal%2fpjZSBgMDYjEhyanp8aahfE1KcAn.png/".kodiImageURL
        state.atmosEnabled    = true
        state.dtsxEnabled     = false
        state.subtitleEnabled = true
        state.isPlaying       = true
        state.progress        = 120
        state.duration        = 7200
        state.studio          = "Marvel Studios"
        state.imdbId          = "299534"
        state.subtitles       = [("0", "English"), ("1", "Spanish")]
        state.audiotracks     = [("0", "English"), ("1", "Spanish")]
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
