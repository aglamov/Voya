import Foundation
import SwiftData
import SwiftUI

enum VoyaAPIConfiguration {
    static var baseURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "VOYA_API_BASE_URL") as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }

        return URL(string: trimmed)
    }
}
