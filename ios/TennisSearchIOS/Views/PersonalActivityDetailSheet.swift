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

struct PersonalActivityUpcomingCard: View {
    let activity: PersonalActivity
    let isUpdating: Bool
    let onAddPhotoReport: (() -> Void)?
    let onCompleteWithoutPhoto: (() async -> Void)?
    let onCancel: (() async -> Void)?
    let onOpenCourt: () -> Void
    let onOpenDetails: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var gallery: ActivityMediaGalleryItem?
    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)
    private var media: [PlayerMediaItem] { ActivityMediaGalleryItem.media(photos: activity.photoUrls, videos: activity.videoUrls) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onOpenDetails) {
                HStack(alignment: .top, spacing: 14) {
                    SportIconView(sport: activity.sport, color: lime, size: 30)
                        .frame(width: 54, height: 54).background(lime.opacity(0.09), in: Circle())
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.string("PERSONAL VISIT", "ЛИЧНЫЙ ВИЗИТ"))
                            .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(lime)
                        Text(activity.sport.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                        Text(activity.scheduledAt.formattedDateTime()).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        Text(personalVisitStatus(activity)).font(.caption.weight(.medium)).foregroundStyle(lime)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("personal-activity-details-\(activity.id)")
            Button(action: onOpenCourt) {
                Label(activity.court?.name ?? L10n.string("Sports center", "Спортивный центр"), systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8)).frame(minHeight: 44)
            }.buttonStyle(.plain)
            if let minutes = activity.durationMinutes {
                Label(L10n.string("Recorded duration: \(minutes) min", "Длительность в записи: \(minutes) мин"), systemImage: "clock")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            if let note = activity.reportComment ?? activity.comment, !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !media.isEmpty {
                ActivityMediaStrip(media: media, identifierPrefix: "personal-activity-\(activity.id)-media") { index in
                    gallery = ActivityMediaGalleryItem(media: media, initialIndex: index, title: activity.sport.title, subtitle: activity.scheduledAt.formattedDateTime(), comment: activity.reportComment)
                }
            }
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                if let onAddPhotoReport {
                    Button(action: onAddPhotoReport) {
                        Label(activity.status.lowercased() == "completed" ? L10n.string("Edit result · photos and videos", "Изменить итог · фото и видео") : L10n.string("Add photos or videos", "Добавить фото и видео"), systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).frame(minHeight: 48)
                            .background(lime, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).disabled(isUpdating)
                }
                if let onCompleteWithoutPhoto {
                    Button { Task { await onCompleteWithoutPhoto() } } label: {
                        if isUpdating { ProgressView().tint(.white) }
                        else { Text(L10n.string("Without media", "Без медиа")).font(.subheadline.weight(.medium)) }
                    }
                    .foregroundStyle(.white).frame(minHeight: 48).disabled(isUpdating)
                }
            }
            if activity.status.lowercased() == "planned" && !activity.hasEnded {
                Text(L10n.string("Your personal plan, not a venue booking. Open the card to edit or cancel.", "Личный план, не бронирование. Открой карточку, чтобы изменить или отменить визит."))
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.09, green: 0.15, blue: 0.10), Color(red: 0.045, green: 0.06, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.09), lineWidth: 1))
        .sheet(item: $gallery) { ActivityMediaGallerySheet(item: $0) }
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
    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)
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
                    if let duration = activity.durationMinutes { detail("clock", title: L10n.string("Recorded duration: \(duration) min", "Длительность в записи: \(duration) мин")) }
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
            PersonalActivityPlanEditor(activity: activity) { updated in activity = updated; await onUpdated() }
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

private struct PersonalActivityPlanEditor: View {
    let activity: PersonalActivity
    let onSaved: (PersonalActivity) async -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var date = Date()
    @State private var duration = 60
    @State private var comment = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var commentLength: Int { comment.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.string("Date and time", "Дата и время"), selection: $date, in: Date()...)
                Stepper(L10n.string("Duration: \(duration) min", "Длительность: \(duration) мин"), value: $duration, in: 15...360, step: 15)
                TextField(L10n.string("Plan note", "Заметка к плану"), text: $comment, axis: .vertical)
                Text("\(commentLength)/240").font(.caption).foregroundStyle(commentLength > 240 ? .red : .secondary)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(L10n.string("Edit visit", "Изменить визит")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.string("Cancel", "Отмена")) { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Save", "Сохранить")) { Task { await save() } }
                        .disabled(isSaving || commentLength > 240)
                }
            }
        }
        .preferredColorScheme(.dark).interactiveDismissDisabled(isSaving)
        .onAppear { date = max(activity.scheduledDate ?? Date(), Date().addingTimeInterval(60)); duration = min(max(activity.durationMinutes ?? 60, 15), 360); comment = activity.comment ?? "" }
        .onChange(of: appModel.sessionGeneration) { _ in dismiss() }
    }

    @MainActor private func save() async {
        let generation = appModel.sessionGeneration
        guard appModel.currentUser?.id == activity.userId, activity.status.lowercased() == "planned", !isSaving,
              appModel.isCurrentSession(generation), commentLength <= 240 else { return }
        guard date > Date() else {
            errorMessage = L10n.string("Choose a future date and time.", "Выбери будущую дату и время.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await appModel.repository.updatePersonalActivity(activityId: activity.id, draft: PersonalActivityUpdateDraft(scheduledAt: date, durationMinutes: duration, comment: comment, status: nil, reportComment: nil, photoUrls: nil))
            guard appModel.isCurrentSession(generation), appModel.currentUser?.id == activity.userId else { return }
            dismiss()
            await onSaved(updated)
        } catch {
            guard appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
            errorMessage = error.localizedDescription
        }
    }
}
