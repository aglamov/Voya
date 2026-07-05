import Foundation
import SwiftData
import SwiftUI

struct ImportedDocument: Identifiable {
    let id = UUID()
    var name: String
    var text: String
    var importedAt: Date
    var sourceFile: SourceDocumentFile?
}

struct SourceDocumentFile: Codable, Equatable {
    private static let storageKind = "voya.source-document"

    var kind = Self.storageKind
    var fileName: String
    var contentType: String
    var dataBase64: String

    init(fileName: String, contentType: String, data: Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.dataBase64 = data.base64EncodedString()
    }

    var data: Data? {
        Data(base64Encoded: dataBase64)
    }

    var storageString: String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func stored(in rawData: String?) -> SourceDocumentFile? {
        guard let rawData,
              let data = rawData.data(using: .utf8),
              let source = try? JSONDecoder().decode(SourceDocumentFile.self, from: data),
              source.kind == storageKind else {
            return nil
        }

        return source
    }
}

struct ExtractedField: Identifiable {
    let id = UUID()
    var label: String
    var value: String
}

struct ExtractionPreview: Identifiable {
    let id = UUID()
    var sourceName: String
    var sourceFile: SourceDocumentFile?
    var type: String
    var title: String
    var normalizedDestination: String?
    var primaryTime: String
    var confidence: Double
    var fields: [ExtractedField]
    var items: [ItineraryItem]
    var warnings: [String]
}

struct ImportSuccess: Identifiable {
    let id = UUID()
    var tripTitle: String
    var itemCount: Int
    var sourceName: String
    var didCreateTrip: Bool
}

enum ImportErrorMessage: Identifiable {
    case emptyInput
    case unreadableFile(String)

    var id: String { message }

    var message: String {
        switch self {
        case .emptyInput:
            String(localized: "Paste or choose a confirmation first.")
        case .unreadableFile(let name):
            String(localized: "Could not read text from \(name). Try a text-based PDF or paste the confirmation.")
        }
    }
}
