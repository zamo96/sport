import SwiftUI

struct ReportPhotoGalleryItem: Identifiable {
    let id: UUID
    let photoPaths: [String]
    let initialIndex: Int
    let title: String
    let subtitle: String?
    let comment: String?

    init(id: UUID = UUID(), photoPaths: [String], initialIndex: Int = 0, title: String, subtitle: String? = nil, comment: String? = nil) {
        self.id = id
        self.photoPaths = photoPaths
        self.initialIndex = min(max(initialIndex, 0), max(photoPaths.count - 1, 0))
        self.title = title
        self.subtitle = subtitle
        self.comment = comment
    }
}

struct ReportPhotoGallerySheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ReportPhotoGalleryItem
    @State private var selectedIndex: Int

    init(item: ReportPhotoGalleryItem) {
        self.item = item
        _selectedIndex = State(initialValue: item.initialIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Close photos", "Закрыть фотографии"))
                .accessibilityIdentifier("report-gallery-close")
            }
            .padding(16)

            if item.photoPaths.isEmpty {
                ReportGalleryUnavailableView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(item.photoPaths.indices, id: \.self) { index in
                        Group {
                            if abs(index - selectedIndex) <= 1 {
                                ReportGalleryPhoto(path: item.photoPaths[index], index: index, count: item.photoPaths.count)
                            } else {
                                Color.clear
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityIdentifier("report-gallery-pages")
            }

            VStack(alignment: .leading, spacing: 10) {
                if !item.photoPaths.isEmpty {
                    HStack {
                        Button { selectedIndex = max(0, selectedIndex - 1) } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }
                        .disabled(selectedIndex == 0)
                        .accessibilityLabel(L10n.string("Previous photo", "Предыдущее фото"))
                        .accessibilityIdentifier("report-gallery-previous")
                        Spacer()
                        Text("\(selectedIndex + 1) / \(item.photoPaths.count)")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel(L10n.string("Photo", "Фото"))
                            .accessibilityValue("\(selectedIndex + 1) / \(item.photoPaths.count)")
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: selectedIndex = min(item.photoPaths.count - 1, selectedIndex + 1)
                                case .decrement: selectedIndex = max(0, selectedIndex - 1)
                                @unknown default: break
                                }
                            }
                            .accessibilityIdentifier("report-gallery-count")
                        Spacer()
                        Button { selectedIndex = min(item.photoPaths.count - 1, selectedIndex + 1) } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44)
                        }
                        .disabled(selectedIndex == item.photoPaths.count - 1)
                        .accessibilityLabel(L10n.string("Next photo", "Следующее фото"))
                        .accessibilityIdentifier("report-gallery-next")
                    }
                    .buttonStyle(.plain)
                }
                if let comment = item.comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        Text(comment)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct ReportGalleryPhoto: View {
    let path: String
    let index: Int
    let count: Int
    @State private var retryID = UUID()

    var body: some View {
        Group {
            if let url = resolveAppRemoteURL(path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView(L10n.string("Loading photo", "Загружаем фото"))
                            .tint(.white)
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .accessibilityLabel(L10n.string("Photo \(index + 1) of \(count)", "Фото \(index + 1) из \(count)"))
                    case .failure:
                        VStack(spacing: 14) {
                            ReportGalleryUnavailableView()
                            Button(L10n.string("Try again", "Повторить")) { retryID = UUID() }
                                .frame(minHeight: 44)
                        }
                    @unknown default:
                        ReportGalleryUnavailableView()
                    }
                }
                .id(retryID)
            } else {
                ReportGalleryUnavailableView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }
}

private struct ReportGalleryUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
            Text(L10n.string("Photo unavailable", "Фото недоступно")).font(.headline)
        }
        .foregroundStyle(.white.opacity(0.75))
    }
}
