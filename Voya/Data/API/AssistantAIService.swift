import Foundation
import SwiftData
import SwiftUI

struct AssistantAIAdvice: Codable {
    var summary: String
    var assessmentTitle: String
    var assessmentDetail: String
    var answer: String
    var packingAdvice: String
    var nextActions: [String]
    var nextItemDescription: String?
    var riskOverview: String?
    var additionalRisks: [AssistantAIRisk]?
    var confidence: Double
    var usedAI: Bool
}

struct AssistantAIRisk: Codable {
    var title: String
    var description: String
    var severity: String
}

struct AssistantAIRequest: Encodable {
    var locale: String
    var languageCode: String
    var languageName: String
    var question: String?
    var trip: TripContext
    var assessment: AssessmentContext
    var nextItem: ItineraryItemContext?
    var itinerary: [ItineraryItemContext]
    var alerts: [AlertContext]
    var weather: WeatherContext
    var sources: [SourceContext]

    struct TripContext: Encodable {
        var title: String
        var dates: String
        var summary: String
        var destination: String?
        var startsAt: Date?
        var endsAt: Date?
        var notes: String?
        var sourceName: String
        var startLocationName: String?
        var startLocationAddress: String?
        var endLocationName: String?
        var endLocationAddress: String?
    }

    struct AssessmentContext: Encodable {
        var score: Int
        var riskLabel: String
        var readyCount: Int
        var watchCount: Int
        var actionCount: Int
    }

    struct ItineraryItemContext: Encodable {
        var kind: String
        var title: String
        var location: String
        var status: String
        var startsAt: Date?
        var endsAt: Date?
        var confirmationCode: String?
        var providerName: String?
        var sourceName: String?
        var extractedBookingData: String?
        var hasBoardingPass: Bool
        var hasSourceDocument: Bool
    }

    struct AlertContext: Encodable {
        var title: String
        var message: String
        var severity: String
        var sourceTitle: String?
        var sourceDetail: String?
    }

    struct WeatherContext: Encodable {
        var title: String
        var summary: String
        var recommendation: String
        var items: [String]
        var severity: String
    }

    struct SourceContext: Encodable {
        var title: String
        var detail: String
        var count: Int
        var severity: String
    }
}

struct VercelAssistantAIService {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func advise(request body: AssistantAIRequest) async throws -> AssistantAIAdvice {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/assistant"))
        VoyaAPIConfiguration.authorize(&request)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        return try JSONDecoder().decode(AssistantAIAdvice.self, from: data)
    }
}
