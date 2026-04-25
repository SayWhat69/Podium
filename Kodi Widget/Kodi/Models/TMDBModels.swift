import Foundation

// MARK: - Movie Details

struct TMDBMovieDetails: Codable {
    let id: Int
    let overview: String
    let tagline: String?
    let runtime: Int?
    let releaseDate: String?
    let voteAverage: Double?
    let budget: Int?
    let revenue: Int?
    let genres: [TMDBGenre]
    let productionCompanies: [TMDBProductionCompany]

    // TMDB uses snake_case in its JSON responses; CodingKeys maps them to Swift camelCase.
    enum CodingKeys: String, CodingKey {
        case id, overview, tagline, runtime, genres, budget, revenue
        case releaseDate         = "release_date"
        case voteAverage         = "vote_average"
        case productionCompanies = "production_companies"
    }
}

struct TMDBGenre: Codable {
    let id: Int
    let name: String
}

struct TMDBProductionCompany: Codable {
    let id: Int
    let name: String
    let logoPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
    }

    var logoURL: URL? {
        guard let path = logoPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(path)")
    }
}

// MARK: - Credits

struct TMDBCredits: Codable {
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
}

struct TMDBCastMember: Codable {
    let id: Int
    let name: String
    let character: String
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }

    var profileURL: URL? {
        guard let path = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }
}

struct TMDBCrewMember: Codable {
    let id: Int
    let name: String
    let job: String
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, job
        case profilePath = "profile_path"
    }

    var profileURL: URL? {
        guard let path = profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }
}
