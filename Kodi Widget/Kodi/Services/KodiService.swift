import Foundation
import OSLog

// MARK: - JSONValue

/// A type-erased JSON value used to build flexible JSON-RPC request parameters.
enum JSONValue: Codable {
    case string(String)
    case dictionary([String: JSONValue])
    case array([JSONValue])
    case number(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v):     try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .array(let v):      try container.encode(v)
        case .number(let v):     try container.encode(v)
        case .bool(let v):       try container.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self)              { self = .string(v);     return }
        if let v = try? container.decode(Double.self)              { self = .number(v);     return }
        if let v = try? container.decode(Bool.self)                { self = .bool(v);       return }
        if let v = try? container.decode([String: JSONValue].self) { self = .dictionary(v); return }
        if let v = try? container.decode([JSONValue].self)         { self = .array(v);      return }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Unknown JSON type"
        )
    }
}

// MARK: - RequestBody

private struct RequestBody: Codable {
    var jsonrpc = "2.0"
    let method: String
    let params: [String: JSONValue]?
    var id = 1
}

// MARK: - NowPlayingMetadata

/// Unified metadata container returned by `fetchNowPlayingMetadata`.
struct NowPlayingMetadata {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let fanartURL: URL?
    let clearLogoURL: URL?
    let duration: Double
    let studio: String?
    let imdbId: String?
}

// MARK: - KodiService

/// Communicates with a Kodi instance via the JSON-RPC API over HTTP.
///
/// Call `configure(host:port:)` whenever the target device changes before
/// making any other requests.
final class KodiService {

    private static let logger = Logger(subsystem: "com.kodiwidget", category: "KodiService")

    // MARK: - Configuration

    /// Set to `nil` until `configure(host:port:)` is called.
    private static var baseURL: URL?

    static func configure(host: String, port: String) {
        baseURL = URL(string: "http://\(host):\(port)/jsonrpc")
    }

    // MARK: - Core transport

    private static func sendRequest<T: Decodable>(
        method: String,
        params: [String: JSONValue]?
    ) async throws -> T {
        guard let url = baseURL else {
            throw URLError(.badURL)
        }
        let body = RequestBody(method: method, params: params)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Convenience wrapper that returns `nil` on any error and logs the failure.
    private static func fetch<T: Decodable>(
        method: String,
        params: [String: JSONValue]? = nil
    ) async -> T? {
        do {
            return try await sendRequest(method: method, params: params)
        } catch {
            logger.warning("[\(method)] request failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fire-and-forget request; network errors are logged and silently ignored.
    private static func send(method: String, params: [String: JSONValue]?) async {
        let _: SeekResponse? = await fetch(method: method, params: params)
    }

    // MARK: - Player

    static func getActivePlayers() async -> [ActivePlayer]? {
        let response: ActivePlayersResponse? = await fetch(method: "Player.GetActivePlayers")
        return response?.result
    }

    static func getPlayerProperties(playerId: Int) async -> PlayerProperties? {
        let params: [String: JSONValue] = [
            "playerid": .number(Double(playerId)),
            "properties": .array([
                .string("percentage"),
                .string("currentsubtitle"),
                .string("subtitleenabled"),
                .string("speed"),
                .string("time"),
                .string("totaltime"),
                .string("currentaudiostream"),
                .string("audiostreams"),
                .string("subtitles")
            ])
        ]
        let response: PlayerPropertiesResponse? = await fetch(method: "Player.GetProperties", params: params)
        return response?.result
    }

    static func getItem(playerId: Int) async -> PlayerItemResult? {
        let params: [String: JSONValue] = [
            "playerid": .number(Double(playerId)),
            "properties": .array([
                .string("title"),
                .string("art"),
                .string("thumbnail"),
                .string("file"),
                .string("runtime"),
                .string("director"),
                .string("genre"),
                .string("studio"),
                .string("year"),
                .string("imdbnumber")
            ])
        ]
        let response: PlayerItemResponse? = await fetch(method: "Player.GetItem", params: params)
        return response?.result
    }

    static func setPlayPause(playerId: Int, play: Bool) async -> PlayPauseResult? {
        let params: [String: JSONValue] = [
            "playerid": .number(Double(playerId)),
            "play": .bool(play)
        ]
        let response: PlayPauseResponse? = await fetch(method: "Player.PlayPause", params: params)
        return response?.result
    }

    static func seek(playerId: Int, to seconds: Double) async {
        let params: [String: JSONValue] = [
            "playerid": .number(Double(playerId)),
            "value": .dictionary(["seconds": .number(seconds)])
        ]
        await send(method: "Player.Seek", params: params)
    }

    static func seekToTime(playerId: Int, to seconds: Double) async {
        let h  = Int(seconds / 3600)
        let m  = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        let s  = Int(seconds.truncatingRemainder(dividingBy: 60))
        let ms = Int((seconds - seconds.rounded(.down)) * 1000)
        let params: [String: JSONValue] = [
            "playerid": .number(Double(playerId)),
            "value": .dictionary([
                "time": .dictionary([
                    "hours":        .number(Double(h)),
                    "minutes":      .number(Double(m)),
                    "seconds":      .number(Double(s)),
                    "milliseconds": .number(Double(ms))
                ])
            ])
        ]
        await send(method: "Player.Seek", params: params)
    }

    static func setSubtitle(playerId: Int, index: Int?) async {
        if let index {
            let params: [String: JSONValue] = [
                "playerid": .number(Double(playerId)),
                "subtitle": .number(Double(index)),
                "enable":   .bool(true)
            ]
            await send(method: "Player.SetSubtitle", params: params)
        } else {
            let params: [String: JSONValue] = [
                "playerid": .number(Double(playerId)),
                "subtitle": .string("off")
            ]
            await send(method: "Player.SetSubtitle", params: params)
        }
    }

    static func setAudioTrack(playerId: Int, index: Int) async {
        let params: [String: JSONValue] = [
            "playerid": .number(Double(playerId)),
            "stream":   .number(Double(index))
        ]
        await send(method: "Player.SetAudioStream", params: params)
    }

    // MARK: - Library

    static func getMovieDetails(movieId: Int) async -> MovieDetailsResult? {
        let params: [String: JSONValue] = [
            "movieid": .number(Double(movieId)),
            "properties": .array([
                .string("title"),
                .string("art"),
                .string("genre"),
                .string("year"),
                .string("director"),
                .string("rating"),
                .string("plot"),
                .string("studio"),
                .string("imdbnumber"),
                .string("runtime")
            ])
        ]
        let response: MovieDetailsResponse? = await fetch(method: "VideoLibrary.GetMovieDetails", params: params)
        return response?.result
    }

    // MARK: - InfoLabels (fallback for plugin / unknown streams)

    static func getInfoLabels() async -> [String: String]? {
        let labels: [JSONValue] = [
            .string("Player.Title"),
            .string("Player.Duration"),
            .string("VideoPlayer.Title"),
            .string("VideoPlayer.Year"),
            .string("VideoPlayer.Director"),
            .string("VideoPlayer.TVShowTitle"),
            .string("VideoPlayer.Season"),
            .string("VideoPlayer.Episode"),
            .string("VideoPlayer.Cover"),
            .string("VideoPlayer.Duration"),
            .string("VideoPlayer.Studio"),
            .string("VideoPlayer.IMDBNumber")
        ]
        let response: InfoLabelsResponse? = await fetch(
            method: "XBMC.GetInfoLabels",
            params: ["labels": .array(labels)]
        )
        return response?.result
    }

    // MARK: - Addons

    static func getAddons() async -> AddonsResult? {
        let response: AddonsResponse? = await fetch(method: "Addons.GetAddons", params: [:])
        return response?.result
    }

    // MARK: - Unified metadata fetch
    //
    // Strategy:
    //   1. Player.GetItem — works for library movies; includes artwork for all types.
    //   2. VideoLibrary.GetMovieDetails — richer metadata for known library movies.
    //   3. XBMC.GetInfoLabels — last resort for plugin / Real-Debrid streams.

    static func fetchNowPlayingMetadata(playerId: Int) async -> NowPlayingMetadata? {
        if let result = await getItem(playerId: playerId) {
            let item = result.item

            let artworkURL = (item.art?.poster
                           ?? item.art?.fanart
                           ?? item.art?.banner
                           ?? item.thumbnail)?
                            .kodiImageURL
            let fanartURL    = item.art?.fanart?.kodiImageURL
            let clearLogoURL = item.art?.clearLogo?.kodiImageURL

            // Known library movie — fetch full details for richer metadata.
            if item.type == "movie", let movieId = item.id, movieId > 0,
               let details = await getMovieDetails(movieId: movieId) {
                let movie   = details.movieDetails
                let richArt = (movie.art.poster ?? movie.art.fanart ?? movie.art.banner)?.kodiImageURL
                return NowPlayingMetadata(
                    title:        movie.title,
                    subtitle:     movie.director.joined(separator: ", "),
                    artworkURL:   richArt ?? artworkURL,
                    fanartURL:    fanartURL,
                    clearLogoURL: clearLogoURL,
                    duration:     Double(movie.runtime ?? item.runtime ?? 0),
                    studio:       movie.studio.first,
                    imdbId:       movie.imdbNumber
                )
            }

            // Any other item type (plugin stream, episode, etc.)
            let title = item.title?.nilIfEmpty ?? item.label
            if !title.isEmpty {
                return NowPlayingMetadata(
                    title:        title,
                    subtitle:     item.director?.joined(separator: ", ")
                                  ?? item.year.map { String($0) },
                    artworkURL:   artworkURL,
                    fanartURL:    fanartURL,
                    clearLogoURL: clearLogoURL,
                    duration:     Double(item.runtime ?? 0),
                    studio:       item.studio?.first,
                    imdbId:       item.imdbNumber
                )
            }
        }

        // Last resort: InfoLabels for plugin streams with no item metadata.
        guard let labels = await getInfoLabels(),
              let title = labels["VideoPlayer.Title"]?.nilIfEmpty
        else { return nil }

        let subtitle: String?
        if let show = labels["VideoPlayer.TVShowTitle"]?.nilIfEmpty {
            let s = labels["VideoPlayer.Season"] ?? "?"
            let e = labels["VideoPlayer.Episode"] ?? "?"
            subtitle = "\(show) · S\(s)E\(e)"
        } else {
            subtitle = labels["VideoPlayer.Director"]?.nilIfEmpty
                    ?? labels["VideoPlayer.Year"]?.nilIfEmpty
        }

        var artworkURL: URL?
        var fanartURL: URL?
        var clearLogoURL: URL?
        if let dbidString = labels["VideoPlayer.DBID"]?.nilIfEmpty,
           let dbid = Int(dbidString), dbid > 0,
           let details = await getMovieDetails(movieId: dbid) {
            let art  = details.movieDetails.art
            artworkURL   = (art.poster ?? art.fanart ?? art.banner)?.kodiImageURL
            fanartURL    = art.fanart?.kodiImageURL
            clearLogoURL = art.clearLogo?.kodiImageURL
        }

        return NowPlayingMetadata(
            title:        title,
            subtitle:     subtitle,
            artworkURL:   artworkURL,
            fanartURL:    fanartURL,
            clearLogoURL: clearLogoURL,
            duration:     parseDuration(labels["VideoPlayer.Duration"]),
            studio:       labels["VideoPlayer.Studio"]?.nilIfEmpty,
            imdbId:       labels["VideoPlayer.IMDBNumber"]?.nilIfEmpty
        )
    }

    // MARK: - Private helpers

    private static func parseDuration(_ string: String?) -> Double {
        guard let string, !string.isEmpty else { return 0 }
        let parts = string.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60   + parts[1]
        default: return 0
        }
    }
}

// MARK: - String helpers

extension String {
    /// Converts a Kodi `image://` URL string to a usable `URL`.
    var kodiImageURL: URL? {
        guard hasPrefix("image://") else { return nil }
        let inner = String(dropFirst("image://".count).dropLast())
        guard let decoded = inner.removingPercentEncoding else { return nil }
        return URL(string: decoded)
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}
