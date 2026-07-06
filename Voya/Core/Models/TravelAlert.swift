import Foundation
import SwiftData
import SwiftUI

struct TravelAlert: Identifiable {
    let id: String
    let title: String
    let message: String
    let severity: AlertSeverity
    let sourceTitle: String?
    let sourceDetail: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        message: String,
        severity: AlertSeverity,
        sourceTitle: String? = nil,
        sourceDetail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.sourceTitle = sourceTitle
        self.sourceDetail = sourceDetail
    }
}

enum AlertSeverity {
    case calm
    case watch
    case action

    var color: Color {
        switch self {
        case .calm: .teal
        case .watch: .orange
        case .action: .red
        }
    }
}
