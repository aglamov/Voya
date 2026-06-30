import SwiftUI

struct ContentView: View {
    @State private var selectedTab: VoyaTab = .inspire

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .inspire:
                    InspireView()
                case .trips:
                    TripsView()
                case .import:
                    ImportView()
                case .assistant:
                    AssistantView()
                }
            }
            .safeAreaPadding(.bottom, 92)

            VoyaTabBar(selectedTab: $selectedTab)
        }
        .tint(.voyaTeal)
        .preferredColorScheme(.light)
    }
}

private enum VoyaTab: String, CaseIterable, Identifiable {
    case inspire = "Inspire"
    case trips = "Trips"
    case `import` = "Import"
    case assistant = "Assistant"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inspire: "sparkles"
        case .trips: "calendar"
        case .import: "tray.and.arrow.down"
        case .assistant: "message.badge"
        }
    }
}

private struct InspireView: View {
    @EnvironmentObject private var store: VoyaStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Voya", subtitle: "Tuesday, June 30")

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Plan the trip that actually fits.")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .lineSpacing(1)
                                .foregroundStyle(Color.voyaInk)

                            Text("Budget, weather, flights, hotels, events, and calm trade-offs in one place.")
                                .font(.subheadline)
                                .foregroundStyle(Color.voyaMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: "location.north.line.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                LinearGradient(colors: [.voyaInk, .voyaTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Color.voyaMuted)
                            TextField("Warm 4-day trip under $700", text: $store.inspirationText, axis: .vertical)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.voyaInk)
                                .lineLimit(2...4)
                        }
                        .padding(14)
                        .background(.white.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(TripMood.allCases) { mood in
                                    MoodChip(mood: mood, isSelected: mood == store.selectedMood) {
                                        store.selectedMood = mood
                                    }
                                }
                            }
                        }

                        Button {
                        } label: {
                            HStack {
                                Text("Find strong options")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(Color.voyaInk)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(colors: [.white, .voyaMint], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .foregroundStyle(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 14)

                SectionHeader(title: "Best matches", action: "See all")

                VStack(spacing: 14) {
                    ForEach(store.recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }
}

private struct RecommendationCard: View {
    let recommendation: TripRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                DestinationMark(destination: recommendation.destination, color: recommendation.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendation.destination)
                        .font(.title3.bold())
                        .foregroundStyle(Color.voyaInk)
                    Text("\(recommendation.dates) · \(recommendation.fit)")
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer()

                Text(recommendation.estimatedCost)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(recommendation.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(recommendation.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                ForEach(recommendation.details.prefix(3), id: \.self) { detail in
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.voyaInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            HStack(spacing: 12) {
                IconTextButton(title: "Compare", symbol: "slider.horizontal.3", style: .secondary)
                IconTextButton(title: "Booking links", symbol: "safari", style: .primary)
            }
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

private struct TripsView: View {
    @EnvironmentObject private var store: VoyaStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Trips", subtitle: "Rome, Aug 12-16")

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Next up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Text("BA2490 to Rome")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            Text("Leave at 06:50 · LHR Terminal 5")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Spacer()

                        Image(systemName: "airplane.departure")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(Color.voyaCoral)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        MetricPill(title: "Flight", value: "On time")
                        MetricPill(title: "Transit", value: "42 min")
                        MetricPill(title: "Buffer", value: "35 min")
                    }
                }
                .padding(18)
                .background(Color.voyaInk)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 22, y: 14)

                SectionHeader(title: "Timeline", action: "Add")

                VStack(spacing: 0) {
                    ForEach(Array(store.itinerary.enumerated()), id: \.element.id) { index, item in
                        TimelineRow(item: item, isLast: index == store.itinerary.count - 1)
                    }
                }
                .padding(.vertical, 8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }
}

private struct ImportView: View {
    @EnvironmentObject private var store: VoyaStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Import", subtitle: "Travel inbox")

                VStack(alignment: .leading, spacing: 16) {
                    Text("Drop confirmations here.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.voyaInk)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ImportOption(symbol: "doc.text", title: "PDF", tint: .voyaTeal)
                        ImportOption(symbol: "photo.on.rectangle", title: "Screenshot", tint: .voyaCoral)
                        ImportOption(symbol: "camera.viewfinder", title: "Photo", tint: .indigo)
                        ImportOption(symbol: "text.alignleft", title: "Paste", tint: .voyaGold)
                    }
                }
                .padding(18)
                .background(.white)
                .foregroundStyle(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Pasted confirmation")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)

                    TextEditor(text: $store.importText)
                        .scrollContentBackground(.hidden)
                        .font(.callout)
                        .foregroundStyle(Color.voyaInk)
                        .frame(minHeight: 126)
                        .padding(12)
                        .background(Color.voyaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                        store.runMockExtraction()
                    } label: {
                        HStack {
                            Label("Extract trip details", systemImage: "wand.and.stars")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .foregroundStyle(.white)
                        .background(Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(18)
                .background(.white)
                .foregroundStyle(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                if let preview = store.extractedPreview {
                    ExtractionReview(preview: preview)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }
}

private struct AssistantView: View {
    @EnvironmentObject private var store: VoyaStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Assistant", subtitle: "Live support")

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Trip looks calm.")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Voya is watching timing, route changes, and flight updates.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Spacer()

                        Image(systemName: "shield.checkered")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.voyaTeal)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        MetricPill(title: "Alerts", value: "3")
                        MetricPill(title: "Risk", value: "Low")
                        MetricPill(title: "Next", value: "06:50")
                    }
                    .foregroundStyle(.white)
                }
                .padding(18)
                .background(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 22, y: 14)

                VStack(spacing: 12) {
                    ForEach(store.alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }

                HStack(spacing: 12) {
                    Text("What if my flight is delayed?")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Color.voyaCoral)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }
}

private struct HeaderBar: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyaInk)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
            }

            Spacer()

            Button {
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(Color.voyaInk)
                    .frame(width: 44, height: 44)
                    .background(.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
            }
        }
    }
}

private struct VoyaTabBar: View {
    @Binding var selectedTab: VoyaTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VoyaTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .bold))
                        Text(tab.rawValue)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(selectedTab == tab ? Color.voyaInk : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

private struct MoodChip: View {
    let mood: TripMood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(mood.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Color.voyaInk)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? Color.voyaInk : .white.opacity(0.88))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct DestinationMark: View {
    let destination: String
    let color: Color

    var initials: String {
        String(destination.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.16))
            Text(initials)
                .font(.headline.bold())
                .foregroundStyle(color)
        }
        .frame(width: 54, height: 54)
    }
}

private struct SectionHeader: View {
    let title: String
    let action: String

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.voyaInk)
            Spacer()
            Text(action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.voyaTeal)
        }
    }
}

private enum ButtonChrome {
    case primary
    case secondary
}

private struct IconTextButton: View {
    let title: String
    let symbol: String
    let style: ButtonChrome

    var body: some View {
        Button {
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(style == .primary ? .white : Color.voyaInk)
                .background(style == .primary ? Color.voyaInk : Color.voyaSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .opacity(0.72)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TimelineRow: View {
    let item: ItineraryItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.voyaTeal)
                    .clipShape(Circle())

                if !isLast {
                    Rectangle()
                        .fill(Color.voyaLine)
                        .frame(width: 2, height: 46)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.time)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.voyaCoral)
                    Spacer()
                    Text(item.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.voyaMuted)
                }

                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color.voyaInk)

                Text(item.location)
                    .font(.subheadline)
                    .foregroundStyle(Color.voyaMuted)
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

private struct ImportOption: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.voyaInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 112)
        .padding(14)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ExtractionReview: View {
    let preview: ExtractionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to review")
                        .font(.title3.bold())
                        .foregroundStyle(Color.voyaInk)
                    Text("\(preview.type) · \(Int(preview.confidence * 100))% confidence")
                        .font(.subheadline)
                        .foregroundStyle(Color.voyaMuted)
                }

                Spacer()

                ProgressRing(value: preview.confidence)
            }

            VStack(spacing: 10) {
                ForEach(preview.fields, id: \.0) { field in
                    HStack(alignment: .top) {
                        Text(field.0)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.voyaMuted)
                            .frame(width: 72, alignment: .leading)
                        Text(field.1)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.voyaInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                IconTextButton(title: "Edit", symbol: "pencil", style: .secondary)
                IconTextButton(title: "Confirm", symbol: "checkmark", style: .primary)
            }
        }
        .padding(18)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

private struct AlertCard: View {
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
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 14, y: 8)
    }
}

private struct ProgressRing: View {
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

private struct AppBackground: View {
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

private extension AlertSeverity {
    var symbol: String {
        switch self {
        case .calm: "checkmark.circle.fill"
        case .watch: "clock.badge.exclamationmark"
        case .action: "exclamationmark.triangle.fill"
        }
    }
}

private extension Color {
    static let voyaInk = Color(red: 0.08, green: 0.12, blue: 0.16)
    static let voyaMuted = Color(red: 0.34, green: 0.39, blue: 0.43)
    static let voyaTeal = Color(red: 0.00, green: 0.52, blue: 0.48)
    static let voyaMint = Color(red: 0.85, green: 0.96, blue: 0.92)
    static let voyaCoral = Color(red: 0.92, green: 0.32, blue: 0.26)
    static let voyaGold = Color(red: 0.76, green: 0.56, blue: 0.12)
    static let voyaSurface = Color(red: 0.95, green: 0.96, blue: 0.95)
    static let voyaLine = Color(red: 0.86, green: 0.89, blue: 0.88)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(VoyaStore())
    }
}
