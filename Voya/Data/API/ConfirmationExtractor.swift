import Foundation
import SwiftData
import SwiftUI

struct VercelConfirmationExtractor {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func extract(from document: ImportedDocument) async throws -> ExtractionPreview {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/extract"))
        VoyaAPIConfiguration.authorize(&request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 35
        request.httpBody = try JSONEncoder().encode(
            VercelExtractionRequest(
                sourceName: document.name,
                text: document.text,
                locale: VoyaAppLocale.currentIdentifier,
                languageCode: VoyaAppLocale.currentLanguageCode,
                languageName: VoyaAppLocale.currentLanguageName
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        let decoded = try JSONDecoder().decode(VercelExtractionResponse.self, from: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let items = decoded.items.map { extractedItem in
            let item = extractedItem.itineraryItem
            if let normalizedData = try? encoder.encode(extractedItem) {
                item.normalizedData = String(data: normalizedData, encoding: .utf8)
            }
            return item
        }

        return ExtractionPreview(
            sourceName: document.name,
            sourceFile: document.sourceFile,
            type: decoded.type,
            title: decoded.title,
            normalizedDestination: decoded.normalizedDestination,
            primaryTime: decoded.primaryTime,
            confidence: decoded.confidence,
            fields: ConfirmationParser.fields(for: items, sourceName: document.name),
            items: items,
            warnings: decoded.warnings
        )
    }
}
