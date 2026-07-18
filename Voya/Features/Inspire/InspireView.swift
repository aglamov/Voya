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
    @Binding var selectedTab: VoyaTab
    @State private var mood = ""
    @State private var selectedStory: InspirationStory?
    @State private var storyToBuild: InspirationStory?
    @State private var createdMission: AgentMission?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderBar(
                    title: "Inspiration",
                    subtitle: String(localized: "Tell Voya a feeling. Agents find a real reason to go.")
                )

                if store.inspirationRelease?.status == "ready" {
                    InspirationReadyHeader(
                        mood: $mood,
                        originalMood: store.inspirationRelease?.mood ?? "",
                        curatorNote: store.inspirationCuratorNote,
                        storyCount: store.inspirationStories.count,
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
                            Text("Agents are turning this idea into a trip")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start with these")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.voyaInk)
                        Text("Each idea has a reason to travel, a timing window, a source, and a risk worth knowing.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                    }

                    LazyVStack(spacing: 16) {
                        ForEach(store.inspirationStories) { story in
                            InspirationStoryCard(story: story) {
                                selectedStory = story
                            } onWant: {
                                storyToBuild = story
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
                Task { @MainActor in
                    await Task.yield()
                    storyToBuild = story
                }
            }
        }
        .sheet(item: $storyToBuild) { story in
            InspirationTripBuilderSheet(story: story) {
                createTrip(from: story)
            }
        }
    }

    private func prepareCollection() {
        Task {
            let brief = mood.trimmingCharacters(in: .whitespacesAndNewlines)
            await store.prepareInspiration(
                mood: brief.isEmpty ? String(localized: "Surprise me with something worth travelling for") : brief
            )
        }
    }

    private func createTrip(from story: InspirationStory) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            let trip = store.createDraftTrip(from: story)
            createdMission = store.agentMissions.first(where: {
                $0.tripId == trip.id
                    && $0.inspirationId == story.id
                    && $0.status != .failed
                    && $0.status != .cancelled
            }) ?? store.startMission(
                    kind: .planning,
                    title: String(localized: "Prepare the first plan for \(story.destination)"),
                    detail: String(localized: "Build a realistic \(story.idealDays)-day plan around “\(story.title)”. Use \(story.timing) as the timing window. Preserve the reason to travel, verify the route, and surface the decisions the traveller must confirm. Main known risk: \(story.mainRisk)"),
                    tripID: trip.id,
                    inspirationID: story.id
                )
            storyToBuild = nil
            selectedTab = .trips
        }
    }
}

private struct InspirationAnnouncementCard: View {
    @Binding var mood: String
    let release: InspirationRelease?
    let isLoading: Bool
    let onPrepare: () -> Void

    private var isPreparing: Bool { release?.status == "preparing" }
    private var suggestions: [String] {
        [
            String(localized: "Surprise me"),
            String(localized: "See something extraordinary"),
            String(localized: "Live music in a new city"),
            String(localized: "Ocean and silence"),
            String(localized: "Art, design and architecture")
        ]
    }

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
                    Text("START HERE")
                        .font(.caption2.weight(.black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(isPreparing
                     ? String(localized: "Agents are finding real reasons to travel")
                     : String(localized: "What kind of journey do you want to feel?"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isPreparing
                     ? String(localized: "Your brief is saved. You can leave this tab — the finished shortlist will appear here and Voya can notify you when it is ready.")
                     : String(localized: "Describe a mood or occasion, not a destination. Voya searches events, natural moments, culture, and remarkable places, then returns a short verified collection."))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isPreparing {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("YOUR BRIEF")
                            .font(.caption2.weight(.black))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.55))
                        Text(release?.mood.nilIfEmpty ?? String(localized: "Surprise me with something worth travelling for"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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

                    Label("No booking or budget estimate is created at this stage.", systemImage: "info.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    InspirationHowItWorks()

                    Text("Try a direction")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.68))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button { mood = suggestion } label: {
                                    Text(suggestion)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .frame(height: 36)
                                        .background(.white.opacity(mood == suggestion ? 0.24 : 0.11))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    TextField("For example: wonder, jazz, the ocean…", text: $mood)
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
                            Text(release?.status == "failed"
                                 ? String(localized: "Ask the agents again")
                                 : String(localized: "Ask agents to find ideas"))
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

                    Text("First we find a compelling reason to go. Dates, routes, and price decisions come after you choose an idea.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))

                    if let error = release?.error {
                        Text(error)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

private struct InspirationHowItWorks: View {
    private var steps: [(String, String)] {
        [
            ("1", String(localized: "You describe a feeling or occasion")),
            ("2", String(localized: "Agents search and verify real possibilities")),
            ("3", String(localized: "You receive a small shortlist and choose what becomes a trip"))
        ]
    }

    var body: some View {
        VStack(spacing: 9) {
            ForEach(steps, id: \.0) { step in
                HStack(spacing: 11) {
                    Text(step.0)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.voyaInk)
                        .frame(width: 28, height: 28)
                        .background(Color.voyaMint)
                        .clipShape(Circle())
                    Text(step.1)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct InspirationReadyHeader: View {
    @Binding var mood: String
    let originalMood: String
    let curatorNote: String
    let storyCount: Int
    let isLoading: Bool
    let onPrepare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("COLLECTION READY", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.black))
                .tracking(1.1)
                .foregroundStyle(Color.voyaTeal)
            Text("\(storyCount) ideas checked by Voya's agents")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.voyaInk)
            if !originalMood.isEmpty {
                Text("Your brief: “\(originalMood)”")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
            }
            Text(curatorNote)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voyaMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                InspirationReadyCheck(title: String(localized: "Source"))
                InspirationReadyCheck(title: String(localized: "Timing"))
                InspirationReadyCheck(title: String(localized: "Place"))
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Text("How an idea becomes a trip")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                Text("Choose an idea → Voya creates a draft and starts the planning agents → you confirm dates and add real bookings.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Want a different direction?")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaMuted)
            HStack(spacing: 10) {
                TextField("Describe another feeling…", text: $mood)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                Button(action: onPrepare) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Refine")
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
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

private struct InspirationReadyCheck: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.voyaTeal)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Color.voyaMint)
            .clipShape(Capsule())
    }
}

private struct InspirationTripBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let story: InspirationStory
    let onCreate: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("TURN THIS IDEA INTO A TRIP", systemImage: "arrow.triangle.branch")
                                .font(.caption.weight(.black))
                                .tracking(0.8)
                                .foregroundStyle(Color.voyaTeal)
                            Text(story.title)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text("Nothing will be booked. Voya will create a working draft you can shape before spending anything.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.voyaMuted)
                        }

                        VStack(spacing: 0) {
                            InspirationBuildStep(
                                number: "1",
                                title: "Create a draft trip",
                                detail: "The destination, reason to travel, suggested duration, timing window, source, and known risk are saved in Trips.",
                                symbol: "doc.badge.plus"
                            )
                            InspirationBuildStep(
                                number: "2",
                                title: "Let planning agents prepare it",
                                detail: "They turn the idea into a route, check the order of places, and identify the decisions that need your approval.",
                                symbol: "point.3.connected.trianglepath.dotted"
                            )
                            InspirationBuildStep(
                                number: "3",
                                title: "Confirm dates and bookings",
                                detail: "You choose the final dates and import real tickets or reservations. Only then does the draft become a confirmed itinerary.",
                                symbol: "checkmark.seal"
                            )
                        }
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                        VStack(alignment: .leading, spacing: 10) {
                            Label("WHAT VOYA ALREADY KNOWS", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.black))
                                .tracking(0.8)
                                .foregroundStyle(Color.voyaTeal)
                            buildFact("Destination", value: "\(story.destination), \(story.country)")
                            buildFact("Timing window", value: story.timing)
                            buildFact("Suggested length", value: String(localized: "\(story.idealDays) days"))
                            buildFact("Reason", value: story.clearSelectionReason)
                        }
                        .padding(18)
                        .background(Color.voyaMint)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                        Button(action: onCreate) {
                            Label("Create draft and start agents", systemImage: "sparkles")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(Color.voyaInk)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }

    private func buildFact(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.voyaInk)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.voyaMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InspirationBuildStep: View {
    let number: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                Circle().fill(Color.voyaMint)
                Text(number)
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.voyaInk)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaInk)
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.voyaMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
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

private extension InspirationStory {
    var clearSelectionReason: String {
        if let selectionReason = selectionReason?.nilIfEmpty {
            return selectionReason
        }
        switch theme {
        case .music:
            return String(localized: "A real performance gives the trip a clear centre and leaves room to discover the city around it.")
        case .nature:
            return String(localized: "The place supports a complete journey even if wildlife or conditions do not behave exactly as hoped.")
        case .culture:
            return String(localized: "A cultural programme gives this journey a stronger point of view than a generic city break.")
        case .phenomenon:
            return String(localized: "A natural phenomenon creates a genuine reason to travel now, not just another destination on a list.")
        case .seasonal:
            return String(localized: "The experience depends on a limited season, so timing shapes the whole journey.")
        }
    }

    var clearVerificationSummary: String {
        verificationSummary?.nilIfEmpty
            ?? String(localized: "\(timing) · \(sourceTitle) · \(Int((confidence * 100).rounded()))% source confidence")
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
                        Label("Verified", systemImage: "checkmark.seal.fill")
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("WHY VOYA PICKED IT")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(Color.voyaTeal)
                    Text(story.clearSelectionReason)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.voyaInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.voyaMint)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 6) {
                    Label("\(story.idealDays) days", systemImage: "calendar.badge.clock")
                    Label(story.agentChecks?.last ?? String(localized: "Source verified"), systemImage: "checkmark.circle")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.voyaMuted)

                HStack(spacing: 10) {
                    Button(action: onOpen) {
                        Label("See why", systemImage: "book.pages")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.voyaInk)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.voyaSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button(action: onWant) {
                        Label("Turn into a trip", systemImage: "arrow.triangle.branch")
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

                        InspirationDetailSection(title: "Agent verdict", lines: [story.clearSelectionReason])
                        InspirationDetailSection(title: "What was checked", lines: [story.clearVerificationSummary])

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
                            Label("Turn into a trip", systemImage: "arrow.triangle.branch")
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
