import Foundation
import SwiftData
import SwiftUI

struct VercelItemEnricher {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    @MainActor
    func enrich(item: ItineraryItem, modelContext: ModelContext? = nil, forceRefresh: Bool = false) async throws -> ItemEnrichment {
        if forceRefresh {
            ItemEnrichmentCache.clear(for: item)
            try? modelContext?.save()
        } else if let cached = ItemEnrichmentCache.freshCachedEnrichment(for: item) {
            #if DEBUG
            print("[Voya] Enrichment cache hit item=\(item.id)")
            #endif
            return cached
        }

        #if DEBUG
        if ItemEnrichmentCache.cachedEnrichment(for: item) != nil {
            print("[Voya] Enrichment cache stale item=\(item.id)")
        } else {
            print("[Voya] Enrichment cache miss item=\(item.id)")
        }
        #endif

        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/enrich"))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 25
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(
            ItemEnrichmentRequest(
                kind: item.kind.rawValue,
                title: item.title,
                location: item.location,
                startsAt: item.startsAt,
                endsAt: item.endsAt,
                status: item.status,
                locale: VoyaAppLocale.currentIdentifier,
                languageCode: VoyaAppLocale.currentLanguageCode,
                languageName: VoyaAppLocale.currentLanguageName
            )
        )

        #if DEBUG
        if let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) {
            print("[Voya] Enrichment request \(request.url?.absoluteString ?? "<nil>") body=\(body)")
        } else {
            print("[Voya] Enrichment request \(request.url?.absoluteString ?? "<nil>")")
        }
        #endif

        let (data, response) = try await session.data(for: request)
        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            print("[Voya] Enrichment response status=\(httpResponse.statusCode)")
        }
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("[Voya] Enrichment response body=\(rawResponse)")
        }
        #endif
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        do {
            let enrichment = try JSONDecoder().decode(ItemEnrichment.self, from: data)
            ItemEnrichmentCache.store(enrichment, for: item)
            try? modelContext?.save()
            return enrichment
        } catch {
            #if DEBUG
            print("[Voya] Enrichment decode failed: \(error)")
            #endif
            throw error
        }
    }
}
