import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

extension ItemEnrichment {
    var hasPlanDetails: Bool {
        !sections.isEmpty || !briefMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageURLs.isEmpty
    }
}

struct TravelBriefCard: View {
    @Environment(\.openURL) private var openURL
    let enrichment: ItemEnrichment

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Plan details", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Spacer()
            }

            if !enrichment.sections.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(enrichment.sections) { section in
                        TravelBriefSectionView(section: section)
                    }
                }
            } else if !enrichment.briefMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownBriefText(markdown: enrichment.briefMarkdown)
            }

            if !enrichment.imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(enrichment.imageURLs, id: \.self) { url in
                            Button {
                                openURL(url)
                            } label: {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        ZStack {
                                            Color.voyaSurface
                                            Image(systemName: "photo")
                                                .font(.title3.weight(.bold))
                                                .foregroundStyle(Color.voyaMuted)
                                        }
                                    }
                                }
                                .frame(width: 132, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct MarkdownBriefText: View {
    let markdown: String

    var body: some View {
        Text(attributedText)
            .font(.subheadline)
            .foregroundStyle(Color.voyaInk)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct TravelBriefSectionView: View {
    let section: TravelBriefSection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(section.title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(displayLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var displayLines: [String] {
        let normalized = section.body
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let protected = normalized
            .replacingOccurrences(of: ". ", with: ".\n")
            .replacingOccurrences(of: "; ", with: ";\n")

        let lines = protected
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? [normalized] : lines
    }

    private var symbol: String {
        switch section.kind {
        case "route": "map"
        case "weather": "cloud.sun"
        case "event": "ticket"
        case "flight": "airplane"
        case "risk": "exclamationmark.triangle"
        case "action": "checklist"
        default: "sparkles"
        }
    }

    private var tint: Color {
        switch section.kind {
        case "risk": Color.voyaCoral
        case "route": Color.voyaTeal
        case "weather": Color.voyaSky
        case "event": Color.voyaCoral
        case "flight": Color.voyaSky
        default: Color.voyaGold
        }
    }
}
