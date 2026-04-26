//  FullscreenPlayerView.swift
//
//  Apple Music–style fullscreen player.
//
//  Dependencies (SPM):
//    - Kingfisher  https://github.com/onevcat/Kingfisher
//
//  Additional target files:
//    - FPGradient.metal  (animated multicolor gradient shader)
//
//  Replace the placeholder below with your own TMDB API key:
//    https://developer.themoviedb.org/docs/getting-started

import Combine
import Kingfisher
import SwiftUI
import SwiftData

/// Reads the TMDB API key from `credentials.plist` (not committed to source control).
/// Falls back to an empty string if the file or key is missing.
private let tmdbAPIKey: String = {
    guard let path = Bundle.main.path(forResource: "credentials", ofType: "plist"),
          let dict = NSDictionary(contentsOfFile: path),
          let key  = dict["tmdbApiKey"] as? String
    else { return "" }
    return key
}()

// MARK: - FullscreenPlayerView

struct FullscreenPlayerView: View {
    @Environment(NowPlayingState.self) private var state

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safe = proxy.safeAreaInsets
            ZStack {
                PlayerBackground()
                VStack(spacing: 0) {
                    Capsule()
                        .fill(.white.secondary)
                        .frame(width: 40, height: 5)
                        .blendMode(.overlay)
                        .padding(.top, safe.top + 8)

                    PlayerArtwork()
                        .frame(height: size.width - 50)
                        .padding(.vertical, size.height < 700 ? 10 : 30)
                        .padding(.horizontal, 25)
                        .padding(.top, 40)

                    PlayerControls()
                        .padding(.bottom, safe.bottom)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - PlayerBackground

private struct PlayerBackground: View {
    @Environment(NowPlayingState.self) private var state
    @State private var colors: [Color] = [Color(hex: 0x1f2937), Color(hex: 0xffffff), Color(hex: 0x17b2e7)]

    var body: some View {
        ZStack {
            Rectangle().fill(.thickMaterial)
            AnimatedColorBackground(colors: colors)
                .overlay(Color.black.opacity(0.3))
        }
        .ignoresSafeArea()
        .task(id: state.artworkURL) {
            guard let url = state.artworkURL,
                  let image = try? await KingfisherManager.shared.retrieveImage(with: url).image,
                  let samples = image.dominantColorsClean()
            else { return }
            let extracted = samples.prefix(5).map { Color($0.color) }
            if !extracted.isEmpty {
                withAnimation { colors = Array(extracted) }
            }
        }
    }
}

// MARK: - PlayerArtwork

private struct PlayerArtwork: View {
    @Environment(NowPlayingState.self) private var state

    var body: some View {
        GeometryReader { proxy in
            let size      = proxy.size
            let isPlaying = state.isPlaying
            let url       = state.artworkURL
            if url != nil {
                KFImage.url(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .background(Color(PlayerPalette.artworkBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(isPlaying ? 48 : 72)
                    .shadow(
                        color: Color(.sRGBLinear, white: 0, opacity: isPlaying ? 0.33 : 0.13),
                        radius: isPlaying ? 8 : 3,
                        y: isPlaying ? 10 : 3
                    )
                    .frame(width: size.width, height: size.height)
                    .animation(.smooth, value: isPlaying)
            } else {
                let padding: CGFloat = isPlaying ? 48 : 72
                let posterWidth  = size.width - padding * 2
                let posterHeight = posterWidth * 3 / 2

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .glassEffect(in: .rect(cornerRadius: 10))
                }
                .frame(width: posterWidth, height: posterHeight)
                .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.13), radius: 3, y: 3)
                .frame(width: size.width, height: size.height)
            }
        }
    }
}

// MARK: - PlayerControls

private struct PlayerControls: View {
    private let cardPadding: CGFloat = 32
    private let sliderGrowth: CGFloat = 9

    var body: some View {
        GeometryReader { proxy in
            let size    = proxy.size
            let spacing = size.height * 0.02

            VStack(spacing: 10) {
                VStack(spacing: spacing) {
                    TrackInfoRow(padding: cardPadding)
                    TimingSlider()
                        .padding(.top, spacing)
                        .padding(.horizontal, cardPadding - sliderGrowth)
                }
                .frame(height: size.height / 2.5, alignment: .bottom)

                PlaybackButtonsView(spacing: size.width * 0.14)
                    .padding(.horizontal, cardPadding)
                    .padding(.bottom, 10)

                PlayerFooter()
                    .padding(.horizontal, cardPadding)
                    .frame(height: size.height / 4.5, alignment: .bottom)
            }
            .frame(height: size.height, alignment: .bottom)
        }
    }
}

// MARK: - TrackInfoRow

private struct TrackInfoRow: View {
    let padding: CGFloat

    @Environment(NowPlayingState.self) private var state
    @State private var showInfoSheet = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                let config = MarqueeConfig(startDelay: 5, leftFade: 20, rightFade: padding, spacing: 20)
                MarqueeText(state.title, config: config)
                    .font(.title3).fontWeight(.semibold)
                    .foregroundStyle(Color(PlayerPalette.opaque))
                    .id(state.title)
                    .onTapGesture {
                        if let url = letterboxdURL(for: state.imdbId), UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                MarqueeText(state.director, config: config)
                    .foregroundStyle(Color(PlayerPalette.opaque))
                    .blendMode(.overlay)
                    .id(state.director)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padding)

            GlassInfoButton { showInfoSheet = true }
                .padding(.trailing, padding)
        }
        .onAppear {
            guard let url = state.fanartURL else { return }
            ImagePrefetcher(urls: [url]).start()
        }
        .sheet(isPresented: $showInfoSheet) {
            MovieInfoSheet(
                fanartURL:    state.fanartURL,
                clearLogoURL: state.clearLogoURL,
                imdbId:       state.imdbId
            )
            .presentationDetents([.medium, .large])
        }
    }

    /// Returns the Letterboxd URL for an IMDb or TMDB identifier.
    private func letterboxdURL(for id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        if id.hasPrefix("tt") {
            return URL(string: "https://letterboxd.com/imdb/\(id)/")
        } else {
            return URL(string: "https://letterboxd.com/tmdb/\(id)/")
        }
    }
}

// MARK: - MovieInfoSheet

struct MovieInfoSheet: View {
    let fanartURL: URL?
    let clearLogoURL: URL?
    let imdbId: String

    @State private var movieDetails: TMDBMovieDetails?
    @State private var credits: TMDBCredits?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let fanart = fanartURL {
                    ZStack(alignment: .bottom) {
                        KFImage.url(fanart)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .mask(
                                LinearGradient(
                                    colors: [.white, .white, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        KFImage.url(clearLogoURL)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 42)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    if let details = movieDetails {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if let date = details.releaseDate {
                                    Text(String(date.prefix(4)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let runtime = details.runtime, runtime > 0 {
                                    Text("·").foregroundStyle(.tertiary).font(.caption)
                                    Text(formatRuntime(runtime))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·").foregroundStyle(.tertiary).font(.caption)
                                }
                                ForEach(details.genres, id: \.id) { genre in
                                    Text(genre.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                            }
                        }
                    }

                    if let overview = movieDetails?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let details = movieDetails {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            if let rating = details.voteAverage {
                                StatCard(label: "Rating") {
                                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                                        Text(String(format: "%.1f", rating)).font(.headline)
                                        Text("/ 10").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxHeight: 80)
                            }
                            if let tagline = details.tagline, !tagline.isEmpty {
                                StatCard(label: "Tagline") {
                                    FittingText(tagline)
                                }
                                .frame(maxHeight: 80)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            if let budget = details.budget, budget > 0 {
                                StatCard(label: "Budget") {
                                    Text(formatMoney(budget))
                                        .font(.subheadline).fontWeight(.medium)
                                }
                                .frame(maxHeight: 80)
                            }
                            if let revenue = details.revenue, revenue > 0 {
                                StatCard(label: "Revenue") {
                                    Text(formatMoney(revenue))
                                        .font(.subheadline).fontWeight(.medium)
                                }
                                .frame(maxHeight: 80)
                            }
                        }
                    }

                    let directors = credits?.crew.filter { $0.job == "Director" } ?? []
                    if !directors.isEmpty {
                        PeopleRow(title: "Direction", people: directors.map {
                            PersonEntry(id: $0.id, name: $0.name, profileURL: $0.profileURL)
                        })
                    }

                    let topCast = Array((credits?.cast ?? []).prefix(10))
                    if !topCast.isEmpty {
                        PeopleRow(title: "Cast", people: topCast.map {
                            PersonEntry(id: $0.id, name: $0.name, profileURL: $0.profileURL)
                        })
                    }

                    if let companies = movieDetails?.productionCompanies, !companies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Production")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .textCase(.uppercase).kerning(0.5)
                            Divider()
                            ForEach(companies, id: \.id) { company in
                                HStack(spacing: 12) {
                                    if let url = company.logoURL {
                                        KFImage.url(url)
                                            .resizable().scaledToFit()
                                            .frame(height: 18).opacity(0.7)
                                    }
                                    Text(company.name)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .task { await fetchMovieDetails() }
        .onChange(of: fanartURL) { Task { await fetchMovieDetails() } }
    }

    // MARK: - Fetch

    private func fetchMovieDetails() async {
        guard !imdbId.isEmpty else { return }

        let tmdbId: Int?

        if imdbId.hasPrefix("tt") {
            guard let url = URL(string: "https://api.themoviedb.org/3/find/\(imdbId)?api_key=\(tmdbAPIKey)&external_source=imdb_id"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let movies = json["movie_results"] as? [[String: Any]],
                  let id = movies.first?["id"] as? Int
            else { return }
            tmdbId = id
        } else {
            tmdbId = Int(imdbId)
        }

        guard let id = tmdbId,
              let detailURL  = URL(string: "https://api.themoviedb.org/3/movie/\(id)?api_key=\(tmdbAPIKey)"),
              let creditsURL = URL(string: "https://api.themoviedb.org/3/movie/\(id)/credits?api_key=\(tmdbAPIKey)")
        else { return }

        async let detailsTask = URLSession.shared.data(from: detailURL)
        async let creditsTask = URLSession.shared.data(from: creditsURL)

        if let (detailData, _) = try? await detailsTask {
            movieDetails = try? JSONDecoder().decode(TMDBMovieDetails.self, from: detailData)
        }
        if let (creditsData, _) = try? await creditsTask {
            credits = try? JSONDecoder().decode(TMDBCredits.self, from: creditsData)
        }
    }

    // MARK: - Formatters

    private func formatRuntime(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func formatMoney(_ amount: Int) -> String {
        let billions = Double(amount) / 1_000_000_000
        let millions = Double(amount) / 1_000_000
        return billions >= 1
            ? String(format: "$%.1fB", billions)
            : String(format: "$%.0fM", millions)
    }
}

// MARK: - Supporting views for MovieInfoSheet

private struct PersonEntry: Identifiable {
    let id: Int
    let name: String
    let profileURL: URL?
}

private struct PeopleRow: View {
    let title: String
    let people: [PersonEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption2).foregroundStyle(.tertiary)
                .textCase(.uppercase).kerning(0.5)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(people) { person in
                        VStack(spacing: 6) {
                            Group {
                                if let url = person.profileURL {
                                    KFImage.url(url).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.title2).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.ultraThinMaterial)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))

                            Text(person.name)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).lineLimit(2)
                                .frame(width: 64)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

private struct FittingText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 500))
            .minimumScaleFactor(0.01)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatCard<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label   = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2).foregroundStyle(.tertiary)
            content.foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - GlassInfoButton

struct GlassInfoButton: View {
    @Environment(NowPlayingState.self) private var state
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: "info")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .glassEffect(.clear, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(state.title.isEmpty)
    }
}

// MARK: - TimingSlider

private struct TimingSlider: View {
    @Environment(NowPlayingState.self) private var state

    var body: some View {
        @Bindable var state = state
        ElasticSlider(
            value: $state.progress,
            in: 0 ... max(state.duration, 0.001),
            leadingLabel:  { timeLabel(state.progress) },
            trailingLabel: { timeLabel((state.duration - state.progress) * -1) },
            atmosEnabled:  state.atmosEnabled,
            dtsxEnabled:   state.dtsxEnabled,
            onCommit:      { seconds in Task { await state.seekTo(seconds: seconds) } }
        )
        .elasticSliderStyle(ElasticSliderConfig(
            labelLocation:             .bottom,
            maxStretch:                0,
            minimumTrackActiveColor:   Color(PlayerPalette.opaque),
            minimumTrackInactiveColor: Color(PlayerPalette.translucent),
            maximumTrackColor:         Color(PlayerPalette.translucent),
            blendMode:                 .overlay,
            syncLabelsStyle:           true
        ))
        .frame(height: 60)
    }

    private func timeLabel(_ seconds: Double) -> some View {
        if(!state.title.isEmpty) {
            Text(formatTimeInterval(seconds))
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 11)
        } else {
            Text("--:--")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 11)
        }
    }
}

private func formatTimeInterval(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits       = [.hour, .minute, .second]
    formatter.unitsStyle         = .positional
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: TimeInterval(seconds)) ?? "0:00"
}

// MARK: - PlaybackButtonsView

private struct PlaybackButtonsView: View {
    let spacing: CGFloat

    @Environment(NowPlayingState.self) private var state
    @State private var backTrigger = false
    @State private var fwdTrigger  = false
    private let imageSize: CGFloat = 34

    var body: some View {
        HStack(spacing: spacing) {
            SeekButton(systemImage: "gobackward.10", trigger: backTrigger) {
                backTrigger.toggle()
                Task { await state.seekBackward() }
            }
            PlayerButton(onEnded: { Task { await state.togglePlayPause() } }) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: imageSize, height: imageSize)
                    .contentTransition(.symbolEffect(.replace))
            }
            SeekButton(systemImage: "goforward.10", trigger: fwdTrigger) {
                fwdTrigger.toggle()
                Task { await state.seekForward() }
            }
        }
        .environment(\.playerButtonStyle, PlayerButtonConfig(
            labelColor:   Color(PlayerPalette.opaque),
            tint:         Color(PlayerPalette.translucent.withAlphaComponent(0.3)),
            pressedColor: Color(PlayerPalette.opaque)
        ))
    }
}

// MARK: - PlayerFooter

private struct PlayerFooter: View {
    @Environment(NowPlayingState.self) private var state
    @Environment(AppSettings.self) private var settings

    @State private var showSubtitlePicker = false
    @State private var showSettingsSheet  = false

    @Query private var devices: [Device]

    var body: some View {
        HStack {
            Spacer()

            // MARK: Subtitle button
            VStack(spacing: 6) {
                Button {} label: {
                    Image(systemName: state.subtitleEnabled ? "quote.bubble.fill" : "quote.bubble")
                        .font(.title2)
                        .opacity(state.title.isEmpty ? 0.35 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: state.title.isEmpty)
                }
                Text("").font(.caption)
            }
            .disabled(state.title.isEmpty)
            .highPriorityGesture(
                TapGesture().onEnded { _ in
                    guard !state.title.isEmpty else { return }
                    let currentId = state.currentSubtitleTrackId.flatMap(Int.init)
                    Task { await state.setSubtitle(index: currentId == nil ? 1 : nil) }
                }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    guard !state.title.isEmpty else { return }
                    showSubtitlePicker = true
                }
            )
            .confirmationDialog("Subtitles", isPresented: $showSubtitlePicker) {
                ForEach(state.subtitles, id: \.id) { track in
                    Button("\(track.name.languageFlag)  \(track.name.languageName ?? track.name)") {
                        Task { await state.setSubtitle(index: Int(track.id)) }
                    }
                }
                Button("Off", role: .destructive) {
                    Task { await state.setSubtitle(index: nil) }
                }
                Button("Cancel", role: .cancel) {}
            }

            Spacer()

            // MARK: Device picker
            VStack(spacing: 6) {
                let currentDevice = settings.selectedDevice
                Menu {
                    ForEach(devices) { device in
                        Button {
                            settings.selectedDevice = device
                        } label: {
                            Text(device.name.isEmpty ? "\(device.ip):\(device.port)" : device.name)
                            if device.id == currentDevice?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Button {} label: {
                        Image(systemName: currentDevice?.name.isEmpty ?? true ? "tv.badge.wifi" : "tv.badge.wifi.fill")
                            .font(.title2)
                    }
                }
                let cfg = MarqueeConfig(startDelay: 5, leftFade: 20, rightFade: 20, spacing: 30, staticAlignment: .center)
                MarqueeText(currentDevice?.name ?? "-", config: cfg)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 100)
                    .id(currentDevice?.name)
            }

            Spacer()

            // MARK: Settings button
            VStack(spacing: 6) {
                Button { showSettingsSheet = true } label: {
                    Image(systemName: "gearshape").font(.title2)
                }
                Text("").font(.caption)
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
            }

            Spacer()
        }
        .foregroundStyle(Color(PlayerPalette.opaque))
        .blendMode(.overlay)
    }
}

// MARK: - PlayerPalette

private enum PlayerPalette {
    static let opaque: UIColor = .white
    static let translucent = UIColor(white: 0.784, alpha: 0.816)
    static let artworkBackground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.525, green: 0.525, blue: 0.545, alpha: 1)
            : UIColor(red: 0.898, green: 0.898, blue: 0.913, alpha: 1)
    }
}

// MARK: - PlayerButton

private struct PlayerButtonConfig {
    var size: CGFloat       = 68
    var labelColor: Color   = .white
    var tint: Color         = Color(UIColor(white: 0.784, alpha: 0.3))
    var pressedColor: Color = .white
}

private struct PlayerButtonConfigKey: EnvironmentKey {
    static let defaultValue = PlayerButtonConfig()
}

extension EnvironmentValues {
    fileprivate var playerButtonStyle: PlayerButtonConfig {
        get { self[PlayerButtonConfigKey.self] }
        set { self[PlayerButtonConfigKey.self] = newValue }
    }
}

private struct PlayerButton<Label: View>: View {
    @Environment(\.playerButtonStyle) private var config
    @Environment(NowPlayingState.self) private var state
    @State private var showCircle = false
    @State private var pressed    = false

    let onEnded: () -> Void
    let label: Label

    init(onEnded: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.onEnded = onEnded
        self.label   = label()
    }

    var body: some View {
        label
            .scaleEffect(pressed ? 0.9 : 1)
            .frame(width: config.size, height: config.size)
            .foregroundStyle(showCircle ? config.pressedColor : config.labelColor)
            .background(showCircle ? config.tint : .clear)
            .clipShape(Ellipse())
            .scaleEffect(pressed ? 0.85 : 1)
            .opacity(state.title.isEmpty ? 0.35 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: state.title.isEmpty)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        withAnimation { pressed = true; showCircle = true }
                    }
                    .onEnded { _ in
                        withAnimation { pressed = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation { showCircle = false }
                        }
                        onEnded()
                    }
            )
            .disabled(state.title.isEmpty)
    }
}

// MARK: - SeekButton

/// Seek ±10 s button with a compress-and-spring icon animation.
private struct SeekButton: View {
    let systemImage: String
    let trigger: Bool
    let onTap: () -> Void

    @Environment(\.playerButtonStyle) private var config
    @Environment(NowPlayingState.self) private var state
    @State private var pressed    = false
    @State private var showCircle = false

    private let iconSize: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(showCircle ? config.pressedColor : config.labelColor)
            .frame(width: config.size, height: config.size)
            .background(showCircle ? config.tint : .clear)
            .clipShape(Circle())
            .symbolEffect(.rotate, options: .speed(2).nonRepeating, value: pressed)
            .opacity(state.title.isEmpty ? 0.35 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: state.title.isEmpty)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed.toggle() }
            )
            .disabled(state.title.isEmpty)
    }
}

// MARK: - ElasticSlider

private struct ElasticSliderConfig {
    enum LabelLocation { case bottom, side }

    var labelLocation: LabelLocation          = .side
    var activeHeight: CGFloat                 = 17
    var inactiveHeight: CGFloat               = 7
    var growth: CGFloat                       = 9
    var stretchNarrowing: CGFloat             = 4
    var maxStretch: CGFloat                   = 9
    var pushStretchRatio: CGFloat             = 0.2
    var pullStretchRatio: CGFloat             = 0.5
    var minimumTrackActiveColor: Color        = .accentColor
    var minimumTrackInactiveColor: Color      = Color(UIColor.systemGray3)
    var maximumTrackColor: Color              = Color(UIColor.systemGray6)
    var blendMode: BlendMode                  = .normal
    var syncLabelsStyle: Bool                 = false

    init(
        labelLocation: LabelLocation = .side,
        activeHeight: CGFloat = 17,
        inactiveHeight: CGFloat = 7,
        growth: CGFloat = 9,
        stretchNarrowing: CGFloat = 4,
        maxStretch: CGFloat = 9,
        pushStretchRatio: CGFloat = 0.2,
        pullStretchRatio: CGFloat = 0.5,
        minimumTrackActiveColor: Color   = .accentColor,
        minimumTrackInactiveColor: Color = Color(UIColor.systemGray3),
        maximumTrackColor: Color         = Color(UIColor.systemGray6),
        blendMode: BlendMode             = .normal,
        syncLabelsStyle: Bool            = false
    ) {
        self.labelLocation             = labelLocation
        self.activeHeight              = activeHeight
        self.inactiveHeight            = inactiveHeight
        self.growth                    = growth
        self.stretchNarrowing          = stretchNarrowing
        self.maxStretch                = maxStretch
        self.pushStretchRatio          = pushStretchRatio
        self.pullStretchRatio          = pullStretchRatio
        self.minimumTrackActiveColor   = minimumTrackActiveColor
        self.minimumTrackInactiveColor = minimumTrackInactiveColor
        self.maximumTrackColor         = maximumTrackColor
        self.blendMode                 = blendMode
        self.syncLabelsStyle           = syncLabelsStyle
    }
}

private struct ElasticSliderConfigKey: EnvironmentKey {
    static let defaultValue = ElasticSliderConfig()
}

extension EnvironmentValues {
    fileprivate var elasticSliderStyle: ElasticSliderConfig {
        get { self[ElasticSliderConfigKey.self] }
        set { self[ElasticSliderConfigKey.self] = newValue }
    }
}

extension View {
    fileprivate func elasticSliderStyle(_ config: ElasticSliderConfig) -> some View {
        environment(\.elasticSliderStyle, config)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct ElasticSlider<Leading: View, Trailing: View>: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let leadingLabel: Leading?
    private let trailingLabel: Trailing?
    private let atmosEnabled: Bool
    private let dtsxEnabled: Bool
    /// Called with the final value when the user lifts their finger.
    private let onCommit: ((Double) -> Void)?

    @Environment(\.elasticSliderStyle) private var config
    @State private var lastStored: Double
    @State private var stretchVal: CGFloat = 0
    @State private var trackSize: CGSize   = .zero
    @GestureState private var isActive: Bool = false
    
    @Environment(NowPlayingState.self) private var state

    fileprivate init(
        _value: Binding<Double>,
        range: ClosedRange<Double>,
        leading: Leading?,
        trailing: Trailing?,
        atmosEnabled: Bool,
        dtsxEnabled: Bool,
        onCommit: ((Double) -> Void)? = nil
    ) {
        self._value       = _value
        self.range        = range
        lastStored        = _value.wrappedValue
        leadingLabel      = leading
        trailingLabel     = trailing
        self.atmosEnabled = atmosEnabled
        self.dtsxEnabled  = dtsxEnabled
        self.onCommit     = onCommit
    }

    var body: some View {
        Group {
            if config.labelLocation == .bottom { bottomLayout } else { sideLayout }
        }
        .animation(.smooth(duration: 0.3, extraBounce: 0.3), value: isActive)
    }

    // MARK: Layouts

    private var sideLayout: some View {
        HStack(spacing: 0) {
            let pad = (isActive ? 0 : config.growth) + config.maxStretch
            styledLabel(leadingLabel).offset(x: pad - leadingStretch)
            track
            styledLabel(trailingLabel).offset(x: trailingStretch - pad)
        }
    }

    private var bottomLayout: some View {
        VStack(spacing: 0) {
            track
            HStack(spacing: 0) {
                let pad = (isActive ? 0 : config.growth) + config.maxStretch
                styledLabel(leadingLabel).padding(.leading, pad - leadingStretch)
                Spacer()
                if atmosEnabled {
                    Image("DolbyAtmosLogo")
                        .resizable().scaledToFit().frame(height: 16)
                        .foregroundColor(.secondary).blendMode(config.blendMode)
                        .padding(.top, 8)
                }
                if dtsxEnabled {
                    Image("dtsxLogo")
                        .resizable().scaledToFit().frame(height: 16)
                        .foregroundColor(.secondary).blendMode(config.blendMode)
                        .padding(.top, 8)
                }
                Spacer()
                styledLabel(trailingLabel).padding(.trailing, pad - trailingStretch)
            }
        }
    }

    @ViewBuilder
    private func styledLabel<C: View>(_ view: C?) -> some View {
        if config.syncLabelsStyle, let view {
            ZStack {
                view.foregroundStyle(config.maximumTrackColor).blendMode(config.blendMode)
                view.foregroundStyle(isActive ? config.minimumTrackActiveColor : config.minimumTrackInactiveColor)
            }
            .animation(nil, value: isActive)
            .blendMode(isActive ? .normal : config.blendMode)
            .transformEffect(.identity)
        } else {
            view
        }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Capsule()
                    .fill(config.maximumTrackColor)
                    .blendMode(config.blendMode)
                let filled = max(0,
                    normalized(value) * trackWidth(w, active: isActive)
                        - leadingStretch + trailingStretch
                )
                Capsule()
                    .fill(isActive ? config.minimumTrackActiveColor : config.minimumTrackInactiveColor)
                    .blendMode(isActive ? .normal : config.blendMode)
                    .mask(
                        Rectangle()
                            .frame(width: filled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
            }
            .disabled(state.title.isEmpty)
            .preference(key: SizePreferenceKey.self, value: geo.size)
            .frame(height: isActive
                ? max(0, config.activeHeight - abs(normStretch) * config.stretchNarrowing)
                : config.inactiveHeight)
            .padding(.horizontal, isActive ? 0 : config.growth)
            .padding(.leading,    config.maxStretch - leadingStretch)
            .padding(.trailing,   config.maxStretch - trailingStretch)
            .onPreferenceChange(SizePreferenceKey.self) { trackSize = $0 }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isActive) { _, state, _ in state = true }
                    .onChanged { drag in
                        let projected = (drag.translation.width / trackWidth(w, active: true))
                            * range.span + lastStored
                        value = projected.clamped(to: range)
                        if projected < range.lowerBound {
                            stretchVal = CGFloat(normalized(projected - range.lowerBound))
                        } else if projected > range.upperBound {
                            stretchVal = CGFloat(normalized(projected - range.upperBound))
                        }
                    }
                    .onEnded { _ in
                        onCommit?(value)
                        lastStored = value
                        stretchVal = 0
                    }
            )
        }
        .frame(height: max(0, isActive
            ? config.activeHeight - abs(normStretch) * config.stretchNarrowing
            : config.inactiveHeight))
    }

    // MARK: Stretch helpers

    private var normStretch: CGFloat {
        guard config.maxStretch != 0 else { return 0 }
        let tw = trackWidth(trackSize.width, active: true)
        guard tw != 0, trackSize.width > config.maxStretch * 2 else { return 0 }
        let m = config.maxStretch / tw / config.pushStretchRatio
        return stretchVal.clamped(to: -m ... m) / m
    }

    private var leadingStretch: CGFloat {
        let v = normStretch, s = abs(v) * config.maxStretch
        return v < 0 ? s : -s * config.pullStretchRatio
    }

    private var trailingStretch: CGFloat {
        let v = normStretch, s = abs(v) * config.maxStretch
        return stretchVal > 0 ? s : -s * config.pullStretchRatio
    }

    private func normalized(_ v: Double) -> CGFloat {
        CGFloat((v - range.lowerBound) / range.span)
    }

    private func normalized(_ v: CGFloat) -> CGFloat {
        (v - CGFloat(range.lowerBound)) / CGFloat(range.span)
    }

    private func trackWidth(_ w: CGFloat, active: Bool) -> CGFloat {
        max(0, w - config.maxStretch * 2 - (active ? 0 : config.growth * 2))
    }
}

// MARK: ElasticSlider convenience initialisers

extension ElasticSlider where Leading == EmptyView, Trailing == EmptyView {
    init(value: Binding<Double>, in range: ClosedRange<Double>, onCommit: ((Double) -> Void)? = nil) {
        self.init(_value: value, range: range, leading: nil, trailing: nil, atmosEnabled: false, dtsxEnabled: false, onCommit: onCommit)
    }
}

extension ElasticSlider where Trailing == EmptyView {
    init(value: Binding<Double>, in range: ClosedRange<Double>, leadingLabel: () -> Leading, onCommit: ((Double) -> Void)? = nil) {
        self.init(_value: value, range: range, leading: leadingLabel(), trailing: nil, atmosEnabled: false, dtsxEnabled: false, onCommit: onCommit)
    }
}

extension ElasticSlider where Leading == EmptyView {
    init(value: Binding<Double>, in range: ClosedRange<Double>, trailingLabel: () -> Trailing, onCommit: ((Double) -> Void)? = nil) {
        self.init(_value: value, range: range, leading: nil, trailing: trailingLabel(), atmosEnabled: false, dtsxEnabled: false, onCommit: onCommit)
    }
}

extension ElasticSlider {
    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        leadingLabel: () -> Leading,
        trailingLabel: () -> Trailing,
        atmosEnabled: Bool,
        dtsxEnabled: Bool,
        onCommit: ((Double) -> Void)? = nil
    ) {
        self.init(
            _value:       value,
            range:        range,
            leading:      leadingLabel(),
            trailing:     trailingLabel(),
            atmosEnabled: atmosEnabled,
            dtsxEnabled:  dtsxEnabled,
            onCommit:     onCommit
        )
    }
}

// MARK: - Range / numeric helpers

private extension ClosedRange where Bound == Double {
    var span: Double { upperBound - lowerBound }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - MarqueeText

private struct MarqueeConfig {
    var startDelay: Double        = 1
    var leftFade: CGFloat         = 40
    var rightFade: CGFloat        = 40
    var spacing: CGFloat          = 100
    var staticAlignment: Alignment = .leading
}

private struct MarqueeText: View {
    let text: String
    let config: MarqueeConfig

    @State private var textSize: CGSize = .zero
    @State private var animate = false

    init(_ text: String, config: MarqueeConfig = .init()) {
        self.text   = text
        self.config = config
    }

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textSize.width > geo.size.width
            ZStack {
                if needsScroll { scrollingText(width: geo.size.width) }
                else           { staticText }
            }
        }
        .frame(height: textSize.height)
        .overlay(
            Text(text).lineLimit(1).fixedSize()
                .padding(.leading,  config.leftFade)
                .padding(.trailing, config.rightFade)
                .hidden()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: SizePreferenceKey.self, value: geo.size)
                    }
                )
        )
        .onPreferenceChange(SizePreferenceKey.self) { textSize = $0 }
        .onAppear { withAnimation(marqueeAnimation) { animate = true } }
    }

    private func scrollingText(width: CGFloat) -> some View {
        let lineWidth = textSize.width - (config.leftFade + config.rightFade) + config.spacing
        let offset    = animate ? lineWidth : 0
        return Group {
            Text(text).offset(x: -offset)
            Text(text).offset(x: -offset + lineWidth)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(width: width)
        .offset(x: config.leftFade)
        .mask(fadeMask)
    }

    private var staticText: some View {
        Text(text)
            .padding(.leading,  config.leftFade)
            .padding(.trailing, config.rightFade)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: config.staticAlignment)
    }

    private var marqueeAnimation: Animation {
        .linear(duration: Double(textSize.width) / 30)
            .delay(config.startDelay)
            .repeatForever(autoreverses: false)
    }

    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: config.leftFade)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: config.rightFade)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - AnimatedColorBackground
//
// Uses FPGradient.metal for a GPU-rendered inverse-distance-weighted gradient.
// GradientBackgroundModel shuffles colour-point positions every ~18 s.
// AnimatedGradient conforms to Animatable — all 40 floats (8 pts × 5 components)
// are its animatableData, so SwiftUI tweens them on every display-link tick.

private struct AnimatedColorBackground: View {
    @State private var model = GradientBackgroundModel()
    let colors: [Color]

    var body: some View {
        AnimatedGradient(points: model.points)
            .onAppear { model.set(colors); model.start() }
            .onChange(of: colors) { model.set(colors) }
            .allowsHitTesting(false)
    }
}

// MARK: - AnimatedGradient

private struct AnimatedGradient: View, Animatable {
    var points: [GradientPoint]   // always exactly 8 elements

    typealias AnimatableData = AnimatablePair<Animatable4GradientPoints, Animatable4GradientPoints>

    var animatableData: AnimatableData {
        get {
            AnimatableData(
                Animatable4GradientPoints(points[0], points[1], points[2], points[3]),
                Animatable4GradientPoints(points[4], points[5], points[6], points[7])
            )
        }
        set {
            points[0] = newValue.first.p0;  points[1] = newValue.first.p1
            points[2] = newValue.first.p2;  points[3] = newValue.first.p3
            points[4] = newValue.second.p0; points[5] = newValue.second.p1
            points[6] = newValue.second.p2; points[7] = newValue.second.p3
        }
    }

    var body: some View {
        Rectangle()
            .colorEffect(ShaderLibrary.fp_gradient(
                .boundingRect,
                .fp_uniforms(GradientUniforms(points: points))
            ))
    }
}

// MARK: - Animatable type aliases

// One point: ((x, y), (r, (g, b)))
private typealias AnimatableGradientPoint = AnimatablePair<
    AnimatablePair<Float, Float>,
    AnimatablePair<Float, AnimatablePair<Float, Float>>
>

private extension AnimatableGradientPoint {
    init(_ p: GradientPoint) {
        self.init(.init(p.x, p.y), .init(p.r, .init(p.g, p.b)))
    }
    var asPoint: GradientPoint {
        GradientPoint(x: first.first, y: first.second,
                      r: second.first, g: second.second.first, b: second.second.second)
    }
}

// Four points as a nested pair
private typealias Animatable4GradientPoints = AnimatablePair<
    AnimatablePair<AnimatableGradientPoint, AnimatableGradientPoint>,
    AnimatablePair<AnimatableGradientPoint, AnimatableGradientPoint>
>

private extension Animatable4GradientPoints {
    init(_ a: GradientPoint, _ b: GradientPoint, _ c: GradientPoint, _ d: GradientPoint) {
        self.init(
            .init(AnimatableGradientPoint(a), AnimatableGradientPoint(b)),
            .init(AnimatableGradientPoint(c), AnimatableGradientPoint(d))
        )
    }
    var p0: GradientPoint { first.first.asPoint }
    var p1: GradientPoint { first.second.asPoint }
    var p2: GradientPoint { second.first.asPoint }
    var p3: GradientPoint { second.second.asPoint }
}

// MARK: - GradientUniforms
// Flat struct — layout must match FPGradient.metal exactly.

private struct GradientUniforms {
    var px0, py0: Float;  var px1, py1: Float;  var px2, py2: Float;  var px3, py3: Float
    var px4, py4: Float;  var px5, py5: Float;  var px6, py6: Float;  var px7, py7: Float
    var cr0, cg0, cb0, ca0: Float;  var cr1, cg1, cb1, ca1: Float
    var cr2, cg2, cb2, ca2: Float;  var cr3, cg3, cb3, ca3: Float
    var cr4, cg4, cb4, ca4: Float;  var cr5, cg5, cb5, ca5: Float
    var cr6, cg6, cb6, ca6: Float;  var cr7, cg7, cb7, ca7: Float

    init(points p: [GradientPoint]) {
        px0=p[0].x; py0=p[0].y; cr0=p[0].r; cg0=p[0].g; cb0=p[0].b; ca0=1
        px1=p[1].x; py1=p[1].y; cr1=p[1].r; cg1=p[1].g; cb1=p[1].b; ca1=1
        px2=p[2].x; py2=p[2].y; cr2=p[2].r; cg2=p[2].g; cb2=p[2].b; ca2=1
        px3=p[3].x; py3=p[3].y; cr3=p[3].r; cg3=p[3].g; cb3=p[3].b; ca3=1
        px4=p[4].x; py4=p[4].y; cr4=p[4].r; cg4=p[4].g; cb4=p[4].b; ca4=1
        px5=p[5].x; py5=p[5].y; cr5=p[5].r; cg5=p[5].g; cb5=p[5].b; ca5=1
        px6=p[6].x; py6=p[6].y; cr6=p[6].r; cg6=p[6].g; cb6=p[6].b; ca6=1
        px7=p[7].x; py7=p[7].y; cr7=p[7].r; cg7=p[7].g; cb7=p[7].b; ca7=1
    }
}

extension Shader.Argument {
    fileprivate static func fp_uniforms(_ u: GradientUniforms) -> Shader.Argument {
        var copy = u
        return .data(Data(bytes: &copy, count: MemoryLayout<GradientUniforms>.stride))
    }
}

// MARK: - GradientPoint

private struct GradientPoint {
    var x, y: Float
    var r, g, b: Float

    static var zero: GradientPoint { GradientPoint(x: 0, y: 0, r: 0, g: 0, b: 0) }

    static func makeInitial() -> [GradientPoint] {
        positions.map { GradientPoint(x: Float($0.x), y: Float($0.y), r: 0.3, g: 0.2, b: 0.5) }
    }

    static let positions: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.0, y: 0.0), CGPoint(x: 1.0, y: 0.0),
        CGPoint(x: 0.0, y: 0.5), CGPoint(x: 1.0, y: 0.5),
        CGPoint(x: 0.5, y: 1.0), CGPoint(x: 0.0, y: 1.0), CGPoint(x: 1.0, y: 1.0)
    ]

    static func recolored(_ points: [GradientPoint], colors: [Color]) -> [GradientPoint] {
        guard !colors.isEmpty else { return points }
        let palette = buildColorPalette(from: colors, count: 8)
        return points.enumerated().map { i, p in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(palette[i]).getRed(&r, green: &g, blue: &b, alpha: &a)
            return GradientPoint(x: p.x, y: p.y, r: Float(r), g: Float(g), b: Float(b))
        }
    }

    /// Shuffles positions while keeping colours, producing a slow warping drift.
    static func shuffled(_ points: [GradientPoint]) -> [GradientPoint] {
        let newPositions = positions.shuffled()
        return points.enumerated().map { i, p in
            GradientPoint(x: Float(newPositions[i].x), y: Float(newPositions[i].y), r: p.r, g: p.g, b: p.b)
        }
    }
}

// MARK: - Color palette helpers

private func buildColorPalette(from colors: [Color], count: Int) -> [Color] {
    guard !colors.isEmpty else { return [] }
    return (0..<count).map { i in boostColorForGradient(colors[i % colors.count]) }
}

/// Slightly boosts saturation and prevents near-black colours from disappearing in the gradient.
private func boostColorForGradient(_ color: Color) -> Color {
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(UIColor(
        hue:        h,
        saturation: min(1, s + 0.12),
        brightness: max(b, 0.25),
        alpha:      a
    ))
}

// MARK: - GradientBackgroundModel

@MainActor
@Observable
private final class GradientBackgroundModel {
    static let animationDuration: Double = 20

    var points: [GradientPoint]        = GradientPoint.makeInitial()
    private var targetPoints: [GradientPoint] = GradientPoint.makeInitial()
    private var colors: [Color]        = []
    private var timer: AnyCancellable?

    func start() {
        shuffle()
        timer = Timer.publish(every: Self.animationDuration * 0.9, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.shuffle() }
    }

    func set(_ newColors: [Color]) {
        guard newColors != colors else { return }
        colors = newColors
        let updated = GradientPoint.recolored(targetPoints, colors: newColors)
        withAnimation(.easeInOut(duration: 1)) { points = updated }
        targetPoints = updated
    }

    private func shuffle() {
        let next = GradientPoint.shuffled(points)
        withAnimation(.linear(duration: Self.animationDuration)) { points = next }
        targetPoints = next
    }
}

// MARK: - LABColor

private struct LABColor {
    let l, a, b: Float

    /// Converts sRGB (0…1 each) to CIE L*a*b*.
    init(r: Float, g: Float, b: Float) {
        func linearise(_ v: Float) -> Float {
            v > 0.04045 ? powf((v + 0.055) / 1.055, 2.4) : v / 12.92
        }
        let R = linearise(r) * 100, G = linearise(g) * 100, B = linearise(b) * 100
        let x = R * 0.4124 + G * 0.3576 + B * 0.1805
        let y = R * 0.2126 + G * 0.7152 + B * 0.0722
        let z = R * 0.0193 + G * 0.1192 + B * 0.9505
        func f(_ v: Float) -> Float {
            v > 0.008856 ? powf(v, 1.0 / 3.0) : 7.787 * v + 16.0 / 116.0
        }
        let fx = f(x / 95.047), fy = f(y / 100.0), fz = f(z / 108.883)
        l      = 116 * fy - 16
        a      = 500 * (fx - fy)
        self.b = 200 * (fy - fz)
    }

    /// CIEDE94 perceptual colour difference.
    func delta(_ other: LABColor) -> Float {
        let c1  = sqrtf(a * a + b * b),        c2  = sqrtf(other.a * other.a + other.b * other.b)
        let sC  = 1 + 0.045 * c1,              sH  = 1 + 0.015 * c1
        let dC  = c1 - c2
        let dH2 = max(0, (a - other.a) * (a - other.a) + (b - other.b) * (b - other.b) - dC * dC)
        return sqrtf((l - other.l) * (l - other.l) + (dC / sC) * (dC / sC) + dH2 / (sH * sH))
    }
}

// MARK: - Dominant colour extraction

private struct ColorSample {
    let color: UIColor
    let frequency: Double
}

extension UIImage {
    /// Extracts up to `maxColors` perceptually distinct dominant colours from the image.
    fileprivate func dominantColorsClean(
        maxColors: Int = 6,
        minLabDelta: Float = 12
    ) -> [ColorSample]? {
        guard let cgImage = self.cgImage else { return nil }

        // Downsample to a fixed square for speed
        let side = 150
        guard let ctx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }

        // Count 5-bit quantised colour buckets
        var counts: [UInt32: Int] = [:]
        counts.reserveCapacity(2048)
        let ptr = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for i in stride(from: 0, to: side * side * 4, by: 4) {
            guard ptr[i + 3] >= 10 else { continue }
            let rq = UInt32(ptr[i]     >> 3)
            let gq = UInt32(ptr[i + 1] >> 3)
            let bq = UInt32(ptr[i + 2] >> 3)
            counts[(rq << 10) | (gq << 5) | bq, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }

        struct Candidate {
            let key: UInt32
            let count: Int
            let lab: LABColor
            var color: UIColor {
                UIColor(
                    red:   CGFloat(((key >> 10) & 0x1F) << 3 | 4) / 255,
                    green: CGFloat(((key >>  5) & 0x1F) << 3 | 4) / 255,
                    blue:  CGFloat(( key        & 0x1F) << 3 | 4) / 255,
                    alpha: 1
                )
            }
        }

        let minCount  = max(2, (side * side) / 800)
        let candidates: [Candidate] = counts
            .filter { $0.value >= minCount }
            .sorted { $0.value > $1.value }
            .prefix(200)
            .map { key, count in
                let r = Float(((key >> 10) & 0x1F) << 3 | 4) / 255
                let g = Float(((key >>  5) & 0x1F) << 3 | 4) / 255
                let b = Float(( key        & 0x1F) << 3 | 4) / 255
                return Candidate(key: key, count: count, lab: LABColor(r: r, g: g, b: b))
            }
        guard !candidates.isEmpty else { return nil }

        // Greedy farthest-point selection for perceptual diversity
        var palette: [Candidate] = [candidates[0]]
        while palette.count < maxColors {
            var bestIndex: Int?
            var bestDistance: Float = 0
            for (i, candidate) in candidates.enumerated() {
                guard !palette.contains(where: { $0.key == candidate.key }) else { continue }
                let minDist = palette.map { candidate.lab.delta($0.lab) }.min() ?? 0
                if minDist > bestDistance {
                    bestDistance = minDist
                    bestIndex = i
                }
            }
            guard let idx = bestIndex, bestDistance >= minLabDelta else { break }
            palette.append(candidates[idx])
        }

        let total = Double(palette.reduce(0) { $0 + $1.count })
        return palette.map { ColorSample(color: $0.color, frequency: Double($0.count) / total) }
    }
}

// MARK: - Preview

#Preview {
    let state = NowPlayingState()
    state.title          = "Midsommar"
    state.director       = "Ari Aster"
    state.artworkURL     = URL(string: "https://assets.fanart.tv/fanart/midsommer-5d8addc30c4fe.jpg")
    state.atmosEnabled   = true
    state.dtsxEnabled    = false
    state.imdbId         = "979"
    state.isPlaying      = false
    state.progress       = 60.0
    state.duration       = 8400
    state.subtitles      = [("0", "English"), ("1", "German")]
    state.audiotracks    = [("0", "English TrueHD Atmos")]

    return FullscreenPlayerView()
        .environment(state)
}
