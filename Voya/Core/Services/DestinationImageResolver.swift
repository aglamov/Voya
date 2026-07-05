import Foundation
import SwiftData
import SwiftUI

enum VoyaPreferenceKey {
    static let homeLocationName = "voya.homeLocationName"
    static let homeLocationAddress = "voya.homeLocationAddress"
}

struct DestinationHeroImage {
    let url: URL
    let credit: String
}

struct DestinationImageResolver {
    func image(for destination: String) async throws -> DestinationHeroImage {
        let pageTitle = Self.normalizedDestination(destination)
            .replacingOccurrences(of: "Trip to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "_")

        guard let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Voya travel companion", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let summary = try JSONDecoder().decode(WikipediaPageSummary.self, from: data)
        guard let imageURL = summary.originalimage?.source ?? summary.thumbnail?.source else {
            throw URLError(.fileDoesNotExist)
        }

        return DestinationHeroImage(url: imageURL, credit: "Image: Wikipedia")
    }

    private static func normalizedDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: #"\s*\([A-Z]{3}\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WikipediaPageSummary: Decodable {
    struct PageImage: Decodable {
        let source: URL
    }

    let thumbnail: PageImage?
    let originalimage: PageImage?
}
