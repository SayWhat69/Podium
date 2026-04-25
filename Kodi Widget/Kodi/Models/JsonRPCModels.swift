import Foundation

// MARK: - Player.GetActivePlayers

struct ActivePlayersResponse: Codable {
    let id: Int
    let jsonrpc: String
    let result: [ActivePlayer]
}

struct ActivePlayer: Codable {
    let playerId: Int
    let playerType: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case playerId   = "playerid"
        case playerType = "playertype"
        case type
    }
}

// MARK: - Player.GetProperties

struct PlayerPropertiesResponse: Codable {
    let id: Int
    let jsonrpc: String
    let result: PlayerProperties
}

struct PlayerProperties: Codable {
    let currentAudioStream: AudioStream
    let audioStreams: [AudioStream]
    let currentSubtitle: SubtitleTrack
    let subtitles: [SubtitleTrack]
    let percentage: Double
    let speed: Int
    let subtitleEnabled: Bool
    let time: KodiTime
    let totalTime: KodiTime

    enum CodingKeys: String, CodingKey {
        case currentAudioStream = "currentaudiostream"
        case audioStreams        = "audiostreams"
        case currentSubtitle    = "currentsubtitle"
        case subtitles, percentage, speed
        case subtitleEnabled    = "subtitleenabled"
        case time
        case totalTime          = "totaltime"
    }
}

struct AudioStream: Codable {
    let bitrate: Int
    let channels: Int
    let codec: String
    let index: Int
    let isDefault: Bool
    let isImpaired: Bool
    let isOriginal: Bool
    let language: String
    let name: String
    let sampleRate: Int

    enum CodingKeys: String, CodingKey {
        case bitrate, channels, codec, index, language, name
        case isDefault  = "isdefault"
        case isImpaired = "isimpaired"
        case isOriginal = "isoriginal"
        case sampleRate = "samplerate"
    }
}

struct SubtitleTrack: Codable {
    let index: Int
    let isDefault: Bool
    let isForced: Bool
    let isImpaired: Bool
    let language: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case index, language, name
        case isDefault  = "isdefault"
        case isForced   = "isforced"
        case isImpaired = "isimpaired"
    }
}

struct KodiTime: Codable {
    let hours: Int
    let milliseconds: Int
    let minutes: Int
    let seconds: Int

    var totalSeconds: Double {
        Double(hours * 3600 + minutes * 60 + seconds)
    }
}

// MARK: - Player.GetItem

struct PlayerItemResponse: Codable {
    let id: Int
    let jsonrpc: String
    let result: PlayerItemResult
}

struct PlayerItemResult: Codable {
    let item: PlayerItem
}

struct PlayerItem: Codable {
    let id: Int?
    let label: String
    let type: String
    let title: String?
    let thumbnail: String?
    let art: MediaArt?
    let runtime: Int?
    let director: [String]?
    let genre: [String]?
    let studio: [String]?
    let year: Int?
    let file: String?
    let imdbNumber: String?

    enum CodingKeys: String, CodingKey {
        case id, label, type, title, thumbnail, art, runtime, director, genre, studio, year, file
        case imdbNumber = "imdbnumber"
    }
}

// MARK: - VideoLibrary.GetMovieDetails

struct MovieDetailsResponse: Codable {
    let id: Int
    let jsonrpc: String
    let result: MovieDetailsResult
}

struct MovieDetailsResult: Codable {
    let movieDetails: MovieDetails

    enum CodingKeys: String, CodingKey {
        case movieDetails = "moviedetails"
    }
}

struct MovieDetails: Codable {
    let art: MediaArt
    let director: [String]
    let genre: [String]
    let studio: [String]
    let label: String
    let title: String
    let movieId: Int
    let plot: String
    let rating: Double
    let year: Int
    let imdbNumber: String
    let runtime: Int?

    enum CodingKeys: String, CodingKey {
        case art, director, genre, studio, label, title, plot, rating, year, runtime
        case movieId    = "movieid"
        case imdbNumber = "imdbnumber"
    }
}

struct MediaArt: Codable {
    let banner: String?
    let clearArt: String?
    let clearLogo: String?
    let discArt: String?
    let fanart: String?
    let icon: String?
    let keyArt: String?
    let landscape: String?
    let thumb: String?
    let poster: String?

    enum CodingKeys: String, CodingKey {
        case banner, fanart, icon, landscape, thumb, poster
        case clearArt  = "clearart"
        case clearLogo = "clearlogo"
        case discArt   = "discart"
        case keyArt    = "keyart"
    }
}

// MARK: - Player.PlayPause

struct PlayPauseResponse: Codable {
    let id: Int
    let jsonrpc: String
    let result: PlayPauseResult
}

struct PlayPauseResult: Codable {
    let speed: Int
}

// MARK: - Player.Seek

/// Response body is unused; the type exists only to satisfy `Decodable` in `sendRequest`.
struct SeekResponse: Codable {}

// MARK: - XBMC.GetInfoLabels

struct InfoLabelsResponse: Codable {
    let result: [String: String]
}

// MARK: - Addons.GetAddons

struct AddonsResponse: Codable {
    let id: Int
    let jsonrpc: String
    let result: AddonsResult
}

struct AddonsResult: Codable {
    let addons: [KodiAddon]
    let limits: KodiLimits
}

struct KodiAddon: Codable {
    let addonId: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case addonId = "addonid"
        case type
    }
}

struct KodiLimits: Codable {
    let end: Int
    let start: Int
    let total: Int
}
