import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct InspireView: View {
    @EnvironmentObject private var store: VoyaStore
    @State private var mood = ""
    @State private var selectedStory: InspirationStory?
    @State private var createdMission: AgentMission?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(title: "Inspiration", subtitle: "Journeys worth wanting")

                if store.inspirationRelease?.status == "ready" {
                    InspirationReadyHeader(
                        mood: $mood,
                        curatorNote: store.inspirationCuratorNote,
                        isLoading: store.isLoadingInspiration
                    ) {
                        prepareCollection()
                    }
                } else {
                    InspirationAnnouncementCard(
                        mood: $mood,
                        release: store.inspirationRelease,
                        isLoading: store.isLoadingInspiration
                    ) {
                        prepareCollection()
                    }
                }

                if let createdMission {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mission started")
                                .font(.subheadline.weight(.bold))
                            Text(createdMission.title)
                                .font(.caption.weight(.medium))
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(Color.voyaTeal)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.voyaMint)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if !store.inspirationStories.isEmpty {
                    SectionHeader(title: "Selected by Voya", action: "")

                    LazyVStack(spacing: 16) {
                        ForEach(store.inspirationStories) { story in
                            InspirationStoryCard(story: story) {
                                selectedStory = story
                            } onWant: {
                                startMission(for: story)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .task {
            await store.refreshInspiration()
        }
        .task(id: store.inspirationRelease?.status) {
            guard store.inspirationRelease?.status == "preparing" else { return }
            while !Task.isCancelled && store.inspirationRelease?.status == "preparing" {
                try? await Task.sleep(for: .seconds(3))
                await store.refreshInspiration()
            }
        }
        .refreshable {
            await store.refreshInspiration()
        }
        .sheet(item: $selectedStory) { story in
            InspirationStoryDetail(story: story) {
                selectedStory = nil
                startMission(for: story)
            }
        }
    }

    private func prepareCollection() {
        Task {
            await store.prepareInspiration(mood: mood)
        }
    }

    private func startMission(for story: InspirationStory) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            createdMission = store.startMission(
                kind: .inspiration,
                title: String(localized: "Shape a trip to \(story.destination)"),
                detail: String(localized: "Turn “\(story.title)” into a realistic journey, verify the best timing, and surface the decisions that matter."),
                inspirationID: story.id
            )
        }
    }
}

private struct InspirationAnnouncementCard: View {
    @Binding var mood: String
    let release: InspirationRelease?
    let isLoading: Bool
    let onPrepare: () -> Void

    private var isPreparing: Bool { release?.status == "preparing" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.white.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer()
                if isPreparing {
                    Text("\(Int((release?.progress ?? 0) * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    Text("FIRST EDITION")
                        .font(.caption2.weight(.black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer(minLength: 42)

            VStack(alignment: .leading, spacing: 10) {
                Text(isPreparing ? "Voya is preparing your collection" : "Some journeys begin before you know where to go.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isPreparing
                     ? "Scout is finding the possibilities. Verifier checks the facts. The editor and curator will turn the strongest ones into a small travel edition."
                     : "Tell us what you want to feel. Voya's agents will search for real moments, rare places, and beautiful reasons to leave home.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isPreparing {
                VStack(spacing: 12) {
                    ProgressView(value: release?.progress ?? 0)
                        .tint(.white)
                    ForEach(release?.agents ?? []) { agent in
                        HStack(spacing: 10) {
                            Image(systemName: agent.state == "complete" ? "checkmark.circle.fill" : agent.state == "working" ? "circle.dotted.circle.fill" : "circle")
                                .foregroundStyle(agent.state == "complete" ? Color.voyaMint : .white.opacity(agent.state == "working" ? 1 : 0.42))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name).font(.caption.weight(.bold))
                                Text(agent.detail).font(.caption2).foregroundStyle(.white.opacity(0.62))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    TextField("Awe, silence, music, the ocean…", text: $mood)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(.white.opacity(0.94))
                        .foregroundStyle(Color.voyaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .submitLabel(.go)
                        .onSubmit(onPrepare)

                    Button(action: onPrepare) {
                        HStack {
                            Text(release?.status == "failed" ? "Try again" : "Prepare my first collection")
                            Spacer()
                            if isLoading {
                                ProgressView().tint(Color.voyaInk)
                            } else {
                                Image(systemName: "arrow.right")
                            }
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.voyaInk)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color.voyaMint)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(isLoading)

                    if let error = release?.error {
                        Text(error)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 520, alignment: .topLeading)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.035, green: 0.09, blue: 0.16), Color(red: 0.03, green: 0.34, blue: 0.31)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.voyaTeal.opacity(0.28))
                    .frame(width: 280, height: 280)
                    .blur(radius: 2)
                    .offset(x: 130, y: -190)
                Circle()
                    .fill(Color.voyaPlum.opacity(0.28))
                    .frame(width: 220, height: 220)
                    .blur(radius: 18)
                    .offset(x: -160, y: 250)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 18)
    }
}

private struct InspirationReadyHeader: View {
    @Binding var mood: String
    let curatorNote: String
    let isLoading: Bool
    let onPrepare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("YOUR VOYA EDITION", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.black))
                .tracking(1.1)
                .foregroundStyle(Color.voyaTeal)
            Text(curatorNote)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.voyaInk)
            HStack(spacing: 10) {
                TextField("A different mood…", text: $mood)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                Button(action: onPrepare) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

private struct InspirationEditorCard: View {
    @Binding var mood: String
    let curatorNote: String
    let isLoading: Bool
    let onCurate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Color.voyaInk)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("What do you want to feel?")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.voyaInk)
            Text("Voya looks for real reasons to travel — a natural phenomenon, a cultural moment, or simply a beautiful state of the world.")
                .font(.subheadline)
                .foregroundStyle(Color.voyaMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("Awe, silence, music, the ocean…", text: $mood)
                    .font(.body.weight(.medium))
                    .submitLabel(.go)
                    .onSubmit(onCurate)
                Button(action: onCurate) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isLoading)
            }
            .padding(8)
            .padding(.leading, 8)
            .background(.white.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(curatorNote)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.voyaTeal)
        }
        .padding(20)
        .background(LinearGradient(colors: [.white, .voyaMint], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 22, y: 12)
    }
}

private struct InspirationStoryCard: View {
    let story: InspirationStory
    let onOpen: () -> Void
    let onWant: () -> Void

    private var colors: [Color] {
        switch story.theme {
        case .music: [.voyaPlum, .voyaCoral]
        case .nature: [Color(red: 0.05, green: 0.34, blue: 0.32), .voyaTeal]
        case .culture: [Color(red: 0.28, green: 0.16, blue: 0.12), .voyaGold]
        case .phenomenon: [Color(red: 0.05, green: 0.13, blue: 0.25), .voyaTeal]
        case .seasonal: [.voyaPlum, Color(red: 0.94, green: 0.61, blue: 0.58)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(story.timing, systemImage: "calendar")
                        Spacer()
                        Text("\(story.idealDays) days")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.84))

                    Spacer(minLength: 46)

                    Image(systemName: story.symbol)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    Text(story.title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Text("\(story.destination) · \(story.country)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 292, alignment: .leading)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 14) {
                Text(story.hook)
                    .font(.subheadline)
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: onOpen) {
                        Label("Explore", systemImage: "book.pages")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaInk)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.voyaSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button(action: onWant) {
                        Label("I want this", systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.voyaInk)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 12)
    }
}

private struct InspirationStoryDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let story: InspirationStory
    let onWant: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: story.symbol)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Color.voyaTeal)
                        Text(story.title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.voyaInk)
                        Text(story.hook)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)

                        InspirationDetailSection(title: "Why this journey", lines: [story.whyNow])
                        InspirationDetailSection(title: "The experience", lines: story.experience)
                        InspirationDetailSection(title: "Know before you go", lines: story.practicalNotes + [story.mainRisk])

                        if let place = story.place {
                            InspirationDetailSection(
                                title: "Place context",
                                lines: [
                                    place.name,
                                    place.address,
                                    place.rating.map { rating in
                                        let count = place.userRatingCount.map { " · \($0) ratings" } ?? ""
                                        return String(format: "%.1f", rating) + count
                                    }
                                ].compactMap { $0 }
                            )
                            if let mapsURL = place.mapsURL {
                                Button { openURL(mapsURL) } label: {
                                    Label("Open in Google Maps", systemImage: "map")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.voyaTeal)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button { openURL(story.sourceURL) } label: {
                            Label(story.sourceTitle, systemImage: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.voyaTeal)
                        }
                        .buttonStyle(.plain)

                        Button(action: onWant) {
                            Label("Turn this into a mission", systemImage: "sparkles")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(Color.voyaInk)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct InspirationDetailSection: View {
    let title: LocalizedStringKey
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Color.voyaInk)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.voyaTeal).frame(width: 6, height: 6).padding(.top, 6)
                    Text(line).font(.subheadline).foregroundStyle(Color.voyaMuted)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct RecommendationCard: View {
    @Environment(\.openURL) private var openURL
    let recommendation: TripRecommendation
    let onCompare: () -> Void

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
                IconTextButton(title: "Compare", symbol: "slider.horizontal.3", style: .secondary, action: onCompare)
                IconTextButton(title: "Booking links", symbol: "safari", style: .primary) {
                    if let url = bookingSearchURL {
                        openURL(url)
                    }
                }
            }
        }
        .padding(16)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var bookingSearchURL: URL? {
        let query = "\(recommendation.destination) flights hotels events \(recommendation.dates)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}

struct InspirationBriefCard: View {
    let intent: String
    let mood: TripMood

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "checklist.checked")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.voyaTeal)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Search brief")
                        .font(.headline)
                        .foregroundStyle(Color.voyaInk)
                    Text(intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Flexible trip") : intent)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.voyaMuted)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                InspirationSignal(title: "Style", value: mood.displayName, symbol: "sparkles")
                InspirationSignal(title: "Compare", value: "Full trip", symbol: "slider.horizontal.3")
                InspirationSignal(title: "Booking", value: "External", symbol: "safari")
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }
}

struct InspirationSignal: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaTeal)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaInk)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.voyaSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct RecommendationComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let recommendation: TripRecommendation

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recommendation.destination)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text("\(recommendation.dates) · \(recommendation.fit)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.voyaInk)
                                .frame(width: 42, height: 42)
                                .background(.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Trip fit")
                            .font(.headline)
                            .foregroundStyle(Color.voyaInk)

                        ForEach(recommendation.details, id: \.self) { detail in
                            Label(detail, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        HStack(spacing: 8) {
                            MomentMetric(title: "Estimate", value: recommendation.estimatedCost, symbol: "creditcard", tint: recommendation.accent)
                            MomentMetric(title: "Booking", value: "External", symbol: "safari", tint: Color.voyaTeal)
                        }

                        Button {
                            if let url = bookingSearchURL {
                                openURL(url)
                            }
                        } label: {
                            Label("Open booking search", systemImage: "safari")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .foregroundStyle(.white)
                                .background(Color.voyaInk)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var bookingSearchURL: URL? {
        let query = "\(recommendation.destination) flights hotels events \(recommendation.dates)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}
