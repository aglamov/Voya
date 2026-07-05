import Foundation
import SwiftData
import SwiftUI

struct ItemEnrichment: Codable {
    var summary: String
    var cards: [ItemEnrichmentCard]
    var warnings: [String]
    var briefMarkdown: String
    var sections: [TravelBriefSection]
    var actions: [TravelAction]
    var routeLegs: [TravelRouteLeg]
    var imageURLs: [URL]
}

struct ItemEnrichmentCard: Codable, Identifiable {
    var id: String { "\(title)-\(value)-\(kind)" }
    var title: String
    var value: String
    var detail: String?
    var actionURL: URL?
    var kind: String
}

struct TravelBriefSection: Codable, Identifiable {
    var id: String { "\(title)-\(kind)" }
    var title: String
    var body: String
    var kind: String
}

struct TravelAction: Codable, Identifiable {
    var id: String { "\(title)-\(priority)-\(kind)" }
    var title: String
    var detail: String
    var priority: String
    var kind: String
    var actionURL: URL?
}

struct TravelRouteLeg: Codable, Identifiable {
    var id: String { "\(title)-\(destination ?? "")" }
    var title: String
    var origin: String?
    var destination: String?
    var guidance: String
    var bufferMinutes: Int?
    var mapURL: URL?
}
