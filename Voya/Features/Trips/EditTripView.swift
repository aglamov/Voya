import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct EditTripView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TripDraft
    @State private var isShowingDeleteConfirmation = false
    let trip: Trip
    let onSave: (TripDraft) -> Void
    let onDelete: () -> Void

    init(
        trip: Trip,
        onSave: @escaping (TripDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: TripDraft(trip: trip))
        self.trip = trip
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit trip")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.voyaInk)
                            Text("Trip details")
                                .font(.subheadline.weight(.medium))
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
                        ClearableTextField("Title", text: $draft.title, prompt: "Trip to Rome")
                        ClearableTextField("Destination", text: $draft.destination, prompt: "Rome")
                        ClearableTextField("Summary", text: $draft.summary, prompt: "Confirmed flights and stay")
                        ClearableTextField("Notes", text: $draft.notes, prompt: "Anything useful for this trip", lineLimit: 3...6)
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "location.north.line.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.voyaTeal)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Trip start point")
                                    .font(.headline)
                                    .foregroundStyle(Color.voyaInk)
                                Text("Overrides Home for this trip")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                            }

                            Spacer()
                        }

                        ClearableTextField("Place name", text: $draft.startLocationName, prompt: "Home, Office, Hotel")
                        ClearableTextField("Address", text: $draft.startLocationAddress, prompt: "Leave empty to use Home", lineLimit: 2...4)

                        Text("Leave this blank when the trip starts from your default Home base.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "house.and.flag.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.voyaGold)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Trip end point")
                                    .font(.headline)
                                    .foregroundStyle(Color.voyaInk)
                                Text("Overrides Home for the return")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.voyaMuted)
                            }

                            Spacer()
                        }

                        ClearableTextField("Place name", text: $draft.endLocationName, prompt: "Home, Office, Hotel")
                        ClearableTextField("Address", text: $draft.endLocationAddress, prompt: "Leave empty to return Home", lineLimit: 2...4)

                        Text("Leave this blank when the trip should end at your default Home base.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.voyaMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.white)
                    .foregroundStyle(Color.voyaInk)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 16, y: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    onSave(draft)
                    dismiss()
                } label: {
                    Label("Save trip", systemImage: "checkmark")
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
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete trip", systemImage: "trash")
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .voyaKeyboardDismissToolbar()
        .alert("Delete trip?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var isSaveDisabled: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
