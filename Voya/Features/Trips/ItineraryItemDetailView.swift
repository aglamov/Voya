import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct ItineraryItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft: ItineraryItemDraft
    @State private var isEditing = false
    @State private var didCopyLocation = false
    @State private var enrichment: ItemEnrichment?
    @State private var isLoadingEnrichment = false
    let item: ItineraryItem
    let onSave: (ItineraryItemDraft) -> Void
    let onDelete: () -> Void

    init(
        item: ItineraryItem,
        onSave: @escaping (ItineraryItemDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        _draft = State(initialValue: ItineraryItemDraft(item: item))
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader

                    ItemCompanionCard(
                        item: item,
                        phase: ItineraryPhase(item: item),
                        enrichment: enrichment,
                        didCopyLocation: didCopyLocation,
                        onOpenLocation: openMaps,
                        onCopyLocation: copyLocation
                    )
                    ItemInsightPanel(
                        item: item,
                        phase: ItineraryPhase(item: item),
                        enrichment: enrichment,
                        isLoading: isLoadingEnrichment,
                        onRefresh: {
                            Task {
                                await loadEnrichment(forceRefresh: true)
                            }
                        }
                    )

                    DisclosureGroup {
                        itemFormCard
                            .padding(.top, 10)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isEditing ? "square.and.pencil" : "doc.text.magnifyingglass")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.voyaTeal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isEditing ? "Edit booking details" : "Booking details")
                                    .font(.headline)
                                    .foregroundStyle(Color.voyaInk)
                                Text(isEditing ? "Update the source fields for this moment." : "Raw itinerary fields stay here when you need them.")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 7)
                    }
                    .tint(Color.voyaTeal)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, isEditing ? 128 : 30)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                editorActions
            }
        }
        .task(id: item.id) {
            await loadEnrichment()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Label(draft.kind.displayName, systemImage: draft.kind.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.voyaTeal)
                Text(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Untitled item") : draft.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyaInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(draft.displayTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.voyaMuted)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isEditing.toggle()
                    }
                } label: {
                    Image(systemName: isEditing ? "lock.open.fill" : "lock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(isEditing ? .white : Color.voyaInk)
                        .frame(width: 42, height: 42)
                        .background(isEditing ? Color.voyaTeal : .white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isEditing ? "Lock editing" : "Unlock editing")

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
        }
    }

    private var itemFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ItineraryKindPicker(selection: $draft.kind)
                .disabled(!isEditing)
            ClearableTextField("Title", text: $draft.title, prompt: "Flight BA2490, hotel stay, dinner reservation")
                .disabled(!isEditing)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Date", isOn: $draft.hasStartDate)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.voyaInk)
                    .tint(Color.voyaTeal)

                if draft.hasStartDate {
                    DatePicker("Start", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)

                    Toggle("End time", isOn: $draft.hasEndDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.voyaInk)
                        .tint(Color.voyaTeal)

                    if draft.hasEndDate {
                        DatePicker("End", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: [.date, .hourAndMinute])
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.voyaInk)
                    }
                }
            }
            .padding(12)
            .background(Color.voyaSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(!isEditing)
            .onChange(of: draft.startsAt) { _, startsAt in
                if draft.endsAt < startsAt {
                    draft.endsAt = startsAt
                }
            }
            .onChange(of: draft.hasStartDate) { _, hasStartDate in
                if !hasStartDate {
                    draft.hasEndDate = false
                }
            }

            ClearableTextField("Place / map link", text: $draft.location, prompt: "Hotel name, airport, venue, address, or Google Maps link")
                .disabled(!isEditing)
            ClearableTextField("Status", text: $draft.status, prompt: "Confirmed, needs review, ticket saved")
                .disabled(!isEditing)

            HStack(spacing: 8) {
                Label(item.sourceName ?? String(localized: "Manual entry"), systemImage: "doc.text")
                Spacer(minLength: 0)
                Label(isEditing ? String(localized: "Unlocked") : String(localized: "Locked"), systemImage: isEditing ? "lock.open.fill" : "lock.fill")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.voyaMuted)
            .padding(.top, 2)
        }
        .padding(18)
        .background(.white)
        .foregroundStyle(Color.voyaInk)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
    }

    private var locationActions: some View {
        HStack(spacing: 10) {
            Button {
                openMaps()
            } label: {
                Label(locationActionTitle, systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(.white)
                    .background(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)

            Button {
                copyLocation()
            } label: {
                Label(didCopyLocation ? "Copied" : "Copy", systemImage: didCopyLocation ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color.voyaInk)
                    .background(Color.voyaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var editorActions: some View {
        VStack(spacing: 10) {
            Button {
                onSave(draft)
                dismiss()
            } label: {
                Label("Save changes", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(isSaveDisabled ? Color.voyaMuted : Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaveDisabled)

            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: {
                Label("Delete item", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color.voyaCoral)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var isSaveDisabled: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var locationActionTitle: String {
        LocationLinkResolver.directURL(from: draft.location) == nil ? String(localized: "Open map") : String(localized: "Open link")
    }

    private func openMaps() {
        guard let url = LocationLinkResolver.mapURL(for: draft.location) else {
            return
        }
        openURL(url)
    }

    private func copyLocation() {
        let value = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        UIPasteboard.general.string = value
        withAnimation(.easeInOut(duration: 0.18)) {
            didCopyLocation = true
        }
    }

    private func loadEnrichment(forceRefresh: Bool = false) async {
        guard !isLoadingEnrichment else {
            return
        }

        isLoadingEnrichment = true
        defer { isLoadingEnrichment = false }

        do {
            enrichment = try await VercelItemEnricher().enrich(item: item, modelContext: modelContext, forceRefresh: forceRefresh)
        } catch {
            enrichment = nil
        }
    }
}
