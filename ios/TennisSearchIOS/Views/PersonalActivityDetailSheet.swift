import SwiftUI

private func personalVisitStatus(_ activity: PersonalActivity) -> String {
    switch activity.status.lowercased() {
    case "completed": return L10n.string("Visit recorded", "Визит отмечен")
    case "canceled", "cancelled": return L10n.string("Canceled", "Отменено")
    default: return activity.hasEnded
        ? L10n.string("Waiting for your result", "Ждёт отметки о результате")
        : L10n.string("Planned", "Запланировано")
    }
}

struct PersonalActivityDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var activity: PersonalActivity
    let onUpdated: () async -> Void
    var onOpenCourt: ((Court) -> Void)?
    @State private var isReportPresented = false
    @State private var isPlanEditorPresented = false
    @State private var isCancelConfirmationPresented = false
    @State private var gallery: ActivityMediaGalleryItem?
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let lime = VisitStyle.accent
    private var media: [PlayerMediaItem] { ActivityMediaGalleryItem.media(photos: activity.photoUrls, videos: activity.videoUrls) }
    private var isOwner: Bool { appModel.currentUser?.id == activity.userId }

    init(activity: PersonalActivity, onUpdated: @escaping () async -> Void, onOpenCourt: ((Court) -> Void)? = nil) {
        _activity = State(initialValue: activity)
        self.onUpdated = onUpdated
        self.onOpenCourt = onOpenCourt
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        SportIconView(sport: activity.sport, color: lime, size: 40)
                            .frame(width: 76, height: 76).background(lime.opacity(0.08), in: Circle())
                        VStack(alignment: .leading, spacing: 7) {
                            Text(activity.sport.title).font(.title.weight(.semibold))
                            Text(personalVisitStatus(activity)).font(.subheadline).foregroundStyle(lime)
                        }
                    }
                    detail("calendar", title: activity.scheduledAt.formattedDateTime())
                    if let duration = activity.durationMinutes { detail("clock", title: PersonalVisitPlanner.durationLabel(duration, russian: L10n.string("en", "ru") == "ru")) }
                    if let court = activity.court {
                        Button {
                            onOpenCourt?(court)
                        } label: {
                            detail("mappin.and.ellipse", title: court.name, subtitle: court.address)
                        }
                        .buttonStyle(.plain).disabled(onOpenCourt == nil)
                    }
                    if let comment = activity.comment, !comment.isEmpty { note(L10n.string("Plan", "План"), text: comment) }
                    if let comment = activity.reportComment, !comment.isEmpty { note(L10n.string("How it went", "Как прошло занятие"), text: comment) }
                    if !media.isEmpty {
                        ActivityMediaStrip(media: media, identifierPrefix: "visit-detail-media") { index in
                            gallery = ActivityMediaGalleryItem(media: media, initialIndex: index, title: activity.sport.title, subtitle: activity.scheduledAt.formattedDateTime(), comment: activity.reportComment)
                        }
                    }
                    if isOwner {
                        if activity.canComplete || activity.status.lowercased() == "completed" {
                            Button { isReportPresented = true } label: {
                                Label(activity.status.lowercased() == "completed" ? L10n.string("Edit result · photos and videos", "Изменить итог · фото и видео") : L10n.string("Add photos or videos", "Добавить фото и видео"), systemImage: "photo.on.rectangle.angled")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                                    .padding(16).frame(maxWidth: .infinity, minHeight: 52)
                                    .background(lime, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityIdentifier("visit-detail-report")
                            Text(L10n.string("Media is optional. Add a note or simply mark the visit as completed.", "Медиа необязательно. Можно добавить заметку или просто отметить визит."))
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        if activity.status.lowercased() == "planned" {
                            Button { isPlanEditorPresented = true } label: {
                                Label(L10n.string("Edit plan", "Изменить план"), systemImage: "calendar.badge.clock")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                            }.accessibilityIdentifier("visit-detail-edit-plan")
                            Button(L10n.string("Cancel visit", "Отменить визит"), role: .destructive) { isCancelConfirmationPresented = true }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(VisitStyle.destructive)
                                .frame(minHeight: 44).disabled(isSaving)
                            Text(L10n.string("This is a personal plan. It does not book the venue.", "Это личный план. Он не бронирует место в центре."))
                                .font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }.padding(20)
            }
            .foregroundStyle(.white).background(Color.black.ignoresSafeArea())
            .navigationTitle(L10n.string("Personal visit", "Личный визит")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.string("Done", "Готово")) { dismiss() } } }
        }
        .preferredColorScheme(.dark).tint(lime)
        .sheet(isPresented: $isReportPresented) {
            PersonalActivityReportComposerSheet(activity: activity, onSaved: { activity = $0 }, onSubmitted: onUpdated)
        }
        .sheet(isPresented: $isPlanEditorPresented) {
            PersonalVisitComposer(mode: .edit(activity)) { updated in activity = updated; await onUpdated() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(item: $gallery) { ActivityMediaGallerySheet(item: $0) }
        .confirmationDialog(L10n.string("Cancel this visit?", "Отменить этот визит?"), isPresented: $isCancelConfirmationPresented, titleVisibility: .visible) {
            Button(L10n.string("Cancel visit", "Отменить визит"), role: .destructive) { Task { await cancelVisit() } }
        }
        .alert(L10n.string("Error", "Ошибка"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onChange(of: appModel.sessionGeneration) { _ in dismiss() }
    }

    private func detail(_ icon: String, title: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).foregroundStyle(lime).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6)) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }

    private func note(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(lime)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor private func cancelVisit() async {
        let generation = appModel.sessionGeneration
        guard isOwner, activity.status.lowercased() == "planned", !isSaving,
              appModel.isCurrentSession(generation) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await appModel.repository.updatePersonalActivity(activityId: activity.id, draft: PersonalActivityUpdateDraft(scheduledAt: nil, durationMinutes: nil, comment: nil, status: "canceled", reportComment: nil, photoUrls: nil))
            guard appModel.isCurrentSession(generation), isOwner else { return }
            activity = updated
            await onUpdated()
        } catch {
            guard appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
            errorMessage = error.localizedDescription
        }
    }
}
