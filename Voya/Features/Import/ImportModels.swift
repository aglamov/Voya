import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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

    init(fileName: String, contentType: String, dataBase64: String) {
        self.fileName = fileName
        self.contentType = contentType
        self.dataBase64 = dataBase64
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

    static func imported(from url: URL) throws -> SourceDocumentFile {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        return SourceDocumentFile(
            fileName: url.lastPathComponent,
            contentType: UTType(filenameExtension: url.pathExtension)?.identifier ?? "application/octet-stream",
            data: data
        )
    }
}

extension SourceDocument {
    convenience init(sourceName: String, sourceFile: SourceDocumentFile, importedAt: Date = Date()) {
        self.init(
            sourceName: sourceName,
            fileName: sourceFile.fileName,
            contentType: sourceFile.contentType,
            dataBase64: sourceFile.dataBase64,
            importedAt: importedAt
        )
    }

    var sourceFile: SourceDocumentFile {
        SourceDocumentFile(fileName: fileName, contentType: contentType, dataBase64: dataBase64)
    }

    func matches(_ sourceFile: SourceDocumentFile) -> Bool {
        fileName == sourceFile.fileName
            && contentType == sourceFile.contentType
            && dataBase64 == sourceFile.dataBase64
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

enum ImportPreparationStepState: Equatable {
    case pending
    case running
    case completed
    case skipped
    case failed
}

enum ImportPreparationStepKind: String, CaseIterable, Identifiable {
    case source
    case recognition
    case flightAware
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            String(localized: "Source loaded")
        case .recognition:
            String(localized: "Recognition")
        case .flightAware:
            String(localized: "FlightAware check")
        case .preview:
            String(localized: "Preview prepared")
        }
    }

    var symbol: String {
        switch self {
        case .source:
            "doc.text"
        case .recognition:
            "text.viewfinder"
        case .flightAware:
            "antenna.radiowaves.left.and.right"
        case .preview:
            "checklist.checked"
        }
    }
}

struct ImportPreparationStep: Identifiable, Equatable {
    let id: ImportPreparationStepKind
    var title: String
    var detail: String
    var state: ImportPreparationStepState

    init(kind: ImportPreparationStepKind, detail: String, state: ImportPreparationStepState = .pending) {
        self.id = kind
        self.title = kind.title
        self.detail = detail
        self.state = state
    }
}

struct ImportPreparationStatus: Identifiable, Equatable {
    let id = UUID()
    var sourceName: String
    var summary: String
    var steps: [ImportPreparationStep]

    var completedStepCount: Int {
        steps.filter { $0.state == .completed || $0.state == .skipped }.count
    }

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(completedStepCount) / Double(steps.count)
    }

    var isActive: Bool {
        steps.contains { $0.state == .running || $0.state == .pending }
    }

    var hasFailure: Bool {
        steps.contains { $0.state == .failed }
    }
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
