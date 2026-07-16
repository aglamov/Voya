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
    var suggestedQuestions: [String]?
    var answerSources: [String]?
    var confidence: Double
    var usedAI: Bool
}

extension AssistantAIAdvice {
    var isReliableEnoughToOverrideFacts: Bool {
        !usedAI || confidence >= 0.55
    }

    var confidencePercent: Int {
        Int((max(0, min(1, confidence)) * 100).rounded())
    }
}

struct AssistantAIRisk: Codable {
    var title: String
    var description: String
    var severity: String
}

struct AssistantConversationTurn: Codable, Hashable {
    var role: String
    var content: String
}

struct AssistantAIRequest: Encodable {
    var locale: String
    var languageCode: String
    var languageName: String
    var question: String?
    var trip: TripContext
    var assessment: AssessmentContext
    var journey: JourneyContext
    var nextItem: ItineraryItemContext?
    var itinerary: [ItineraryItemContext]
    var alerts: [AlertContext]
    var weather: WeatherContext
    var environment: [EnvironmentContext]
    var sources: [SourceContext]
    var conversation: [AssistantConversationTurn]

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
        var endLocationName: String?
    }

    struct AssessmentContext: Encodable {
        var score: Int
        var riskLabel: String
        var readyCount: Int
        var watchCount: Int
        var actionCount: Int
    }

    struct JourneyContext: Encodable {
        var phase: String
        var phaseLabel: String
        var title: String
        var detail: String
        var progress: Double
        var completedItems: Int
        var totalItems: Int
        var location: String?
        var status: String?
        var timeSummary: String?
        var timingContext: String?
    }

    struct ItineraryItemContext: Encodable {
        var kind: String
        var title: String
        var location: String
        var status: String
        var startsAt: Date?
        var endsAt: Date?
        var providerName: String?
        var sourceName: String?
        var hasConfirmationCode: Bool
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

    struct EnvironmentContext: Encodable {
        var kind: String
        var title: String
        var value: String
        var detail: String?
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
