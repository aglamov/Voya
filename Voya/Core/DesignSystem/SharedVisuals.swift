import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct AlertCard: View {
    let alert: TravelAlert

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: alert.severity.symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(alert.severity.color)
                .frame(width: 42, height: 42)
                .background(alert.severity.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(alert.title)
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let sourceText {
                    Label(sourceText, systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(alert.severity.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 14, y: 8)
    }

    private var sourceText: String? {
        guard let sourceTitle = alert.sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        if let sourceDetail = alert.sourceDetail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "\(sourceTitle): \(sourceDetail)"
        }

        return sourceTitle
    }
}

struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.voyaLine, lineWidth: 5)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.voyaTeal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))")
                .font(.caption.bold())
                .foregroundStyle(Color.voyaInk)
        }
        .frame(width: 48, height: 48)
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.98, blue: 0.97),
                Color(red: 0.98, green: 0.96, blue: 0.93),
                Color(red: 0.94, green: 0.97, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension AlertSeverity {
    var symbol: String {
        switch self {
        case .calm: "checkmark.circle.fill"
        case .watch: "clock.badge.exclamationmark"
        case .action: "exclamationmark.triangle.fill"
        }
    }
}

extension Color {
    static let voyaInk = Color(red: 0.08, green: 0.12, blue: 0.16)
    static let voyaMuted = Color(red: 0.34, green: 0.39, blue: 0.43)
    static let voyaTeal = Color(red: 0.00, green: 0.52, blue: 0.48)
    static let voyaMint = Color(red: 0.85, green: 0.96, blue: 0.92)
    static let voyaCoral = Color(red: 0.92, green: 0.32, blue: 0.26)
    static let voyaGold = Color(red: 0.76, green: 0.56, blue: 0.12)
    static let voyaSky = Color(red: 0.16, green: 0.43, blue: 0.88)
    static let voyaPlum = Color(red: 0.45, green: 0.28, blue: 0.68)
    static let voyaSurface = Color(red: 0.95, green: 0.96, blue: 0.95)
    static let voyaLine = Color(red: 0.86, green: 0.89, blue: 0.88)
}

extension ItineraryKind {
    var timelineAccent: Color {
        switch self {
        case .flight: Color.voyaSky
        case .hotel: Color.voyaPlum
        case .event: Color.voyaCoral
        case .transit: Color.voyaTeal
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(VoyaStore())
    }
}
