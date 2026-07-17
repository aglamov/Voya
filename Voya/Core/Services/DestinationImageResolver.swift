import Foundation
import SwiftData
import SwiftUI

enum VoyaPreferenceKey {
    static let homeLocationName = "voya.homeLocationName"
    static let homeLocationAddress = "voya.homeLocationAddress"
    static let hiddenTransferIDs = "voya.hiddenTransferIDs"
    static let transferBufferOverrides = "voya.transferBufferOverrides"
    static let arrivalFormalitiesOverrides = "voya.arrivalFormalitiesOverrides"
}

struct DestinationHeroImage {
    let url: URL
    let credit: String
    let creditURL: URL?
    let source: DestinationImageSource
}

enum DestinationImageSource: String {
    case pexels
    case wikipedia
}

struct DestinationImageResolver {
    private let baseURL: URL?

    init(baseURL: URL? = VoyaAPIConfiguration.baseURL) {
        self.baseURL = baseURL
    }

    func image(for destination: String) async throws -> DestinationHeroImage {
        do {
            return try await pexelsImage(for: destination)
        } catch {
            try Task.checkCancellation()
            return try await wikipediaImage(for: destination)
        }
    }

    private func pexelsImage(for destination: String) async throws -> DestinationHeroImage {
        guard let baseURL else {
            throw URLError(.unsupportedURL)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/destination-image"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DestinationImageRequest(destination: destination))
        VoyaAPIConfiguration.authorize(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let image = try JSONDecoder().decode(DestinationImageResponse.self, from: data)
        return DestinationHeroImage(
            url: image.imageURL,
            credit: image.credit,
            creditURL: image.creditURL,
            source: .pexels
        )
    }

    private func wikipediaImage(for destination: String) async throws -> DestinationHeroImage {
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

        let creditURL = URL(string: "https://en.wikipedia.org/wiki/\(encodedTitle)")
        return DestinationHeroImage(
            url: imageURL,
            credit: "Image: Wikipedia",
            creditURL: creditURL,
            source: .wikipedia
        )
    }

    private static func normalizedDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: #"\s*\([A-Z]{3}\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DestinationImageRequest: Encodable {
    let destination: String
}

private struct DestinationImageResponse: Decodable {
    let imageURL: URL
    let credit: String
    let creditURL: URL
}

struct WikipediaPageSummary: Decodable {
    struct PageImage: Decodable {
        let source: URL
    }

    let thumbnail: PageImage?
    let originalimage: PageImage?
}
