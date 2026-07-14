import Foundation
import SwiftData
import SwiftUI

enum VoyaAPIConfiguration {
    private static let installIDKey = "voya.install-id"

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

    static var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey) {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: installIDKey)
        return value
    }

    static func authorize(_ request: inout URLRequest) {
        request.setValue(installID, forHTTPHeaderField: "X-Voya-Install-ID")
        if let value = Bundle.main.object(forInfoDictionaryKey: "VOYA_CLIENT_API_KEY") as? String {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !key.hasPrefix("$(") {
                request.setValue(key, forHTTPHeaderField: "X-Voya-Client-Key")
            }
        }
    }
}
