import SwiftUI

/// The personal-visit look: one accent for "yours", dark surfaces stepping up from the sheet.
enum VisitStyle {
    static let accent = MatchMomentPalette.ball
    static let onAccent = AppTheme.ink
    static let sheet = Color(red: 0.047, green: 0.067, blue: 0.055)
    static let card = Color(red: 0.06, green: 0.082, blue: 0.07)
    static let surface = Color(red: 0.075, green: 0.10, blue: 0.086)
    static let control = Color(red: 0.10, green: 0.137, blue: 0.118)
    static let line = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.64)
    static let destructive = Color(red: 1, green: 0.48, blue: 0.42)
}

/// Plans a visit or changes one, on one screen: the day, a time the club can actually
/// take (inside its hours, never in the past), how long, and an optional note.
struct PersonalVisitComposer: View {
    enum Mode {
        case create(court: Court, initialSport: Sport?)
        case edit(PersonalActivity)
    }

    let mode: Mode
    let onSaved: (PersonalActivity) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel

    @State private var sport: Sport
    @State private var day: Date
    @State private var part: VisitDayPart
    @State private var startMinute: Int?
    @State private var durationMinutes: Int
    @State private var comment: String
    @State private var isNoteVisible: Bool
    @State private var isDatePickerPresented = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var now = Date()

    private let hours: ClubHours?

    init(mode: Mode, onSaved: @escaping (PersonalActivity) async -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        let now = Date()
        let calendar = Calendar.current

        switch mode {
        case .create(let court, let initialSport):
            let sports = court.supportedSports ?? []
            let sport = initialSport.flatMap { sports.isEmpty || sports.contains($0) ? $0 : nil } ?? sports.first ?? .tennis
            let hours = ClubHours.parse(court.workingHours)
            let start = PersonalVisitPlanner.defaultStart(hours: hours, durationMinutes: sport.defaultDurationMinutes, now: now)
            let fallbackDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            self.hours = hours
            _sport = State(initialValue: sport)
            _durationMinutes = State(initialValue: sport.defaultDurationMinutes)
            _day = State(initialValue: start?.day ?? fallbackDay)
            _startMinute = State(initialValue: start?.minute)
            _part = State(initialValue: VisitDayPart.containing(minute: start?.minute ?? PersonalVisitPlanner.preferredStartMinute))
            _comment = State(initialValue: "")
            _isNoteVisible = State(initialValue: false)
        case .edit(let activity):
            let start = activity.scheduledDate ?? now
            let minute = PersonalVisitPlanner.minuteOfDay(start)
            self.hours = ClubHours.parse(activity.court?.workingHours)
            _sport = State(initialValue: activity.sport)
            _durationMinutes = State(initialValue: activity.durationMinutes ?? activity.sport.defaultDurationMinutes)
            _day = State(initialValue: calendar.startOfDay(for: start))
            _startMinute = State(initialValue: start > now ? minute : nil)
            _part = State(initialValue: VisitDayPart.containing(minute: minute))
            _comment = State(initialValue: activity.comment ?? "")
            _isNoteVisible = State(initialValue: !(activity.comment ?? "").isEmpty)
        }
    }

    private var court: Court? {
        switch mode {
        case .create(let court, _): return court
        case .edit(let activity): return activity.court
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var availableSports: [Sport] {
        let sports = court?.supportedSports ?? []
        return sports.isEmpty ? [sport] : sports
    }

    private var quickDays: [Date] {
        PersonalVisitPlanner.quickDays(from: now)
    }

    private var isCustomDay: Bool {
        !quickDays.contains { Calendar.current.isDate($0, inSameDayAs: day) }
    }

    private var dayStarts: [Int] {
        PersonalVisitPlanner.allStartMinutes(on: day, hours: hours, durationMinutes: durationMinutes, now: now)
    }

    /// The part's slots, plus an edited visit's own off-grid time while it is still ahead.
    private var slots: [Int] {
        var minutes = dayStarts.filter { part.minutes.contains($0) }
        if isEditing, let startMinute, part.minutes.contains(startMinute), !minutes.contains(startMinute),
           let start = PersonalVisitPlanner.date(on: day, minute: startMinute), start > now {
            minutes.append(startMinute)
            minutes.sort()
        }
        return minutes
    }

    private var selectedStart: Date? {
        guard let startMinute, let start = PersonalVisitPlanner.date(on: day, minute: startMinute), start > now else { return nil }
        return start
    }

    private var commentLength: Int {
        comment.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
    }

    private var canSave: Bool {
        selectedStart != nil && !isSaving && commentLength <= 240
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    courtRow
                    if !isEditing, availableSports.count > 1 {
                        sportRow
                    }
                    whenSection
                    durationSection
                    noteSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            footer
        }
        .foregroundStyle(.white)
        .background(VisitStyle.sheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $isDatePickerPresented) {
            datePickerSheet
        }
        .alert(
            L10n.string("Could not save", "Не удалось сохранить"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            // Keep "today" honest while the sheet stays open.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                refreshNow()
            }
        }
        .onChange(of: appModel.sessionGeneration) { _ in dismiss() }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel(L10n.string("Close", "Закрыть"))

            Spacer()
            Text(isEditing ? L10n.string("Edit visit", "Изменить визит") : L10n.string("Club visit", "Визит в клуб"))
                .font(.headline.weight(.semibold))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var courtRow: some View {
        HStack(spacing: 14) {
            PersonalVisitArtwork(court: court, sport: sport, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(court?.name ?? L10n.string("Sports center", "Спортивный центр"))
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                if let subtitle = courtSubtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(VisitStyle.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEditing || availableSports.count == 1 {
                Text(sport.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VisitStyle.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(VisitStyle.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(12)
        .background(VisitStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(VisitStyle.line, lineWidth: 1))
    }

    private var courtSubtitle: String? {
        let place = court?.metroDisplayName ?? localizedDistrictName(court?.district)
        let open = hours.map { L10n.string("open \($0.label)", "открыто \($0.label)") }
        let parts = [place, open].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? court?.displayAddress : parts.joined(separator: " · ")
    }

    private var sportRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.string("What", "Что"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableSports) { option in
                        let selected = option == sport
                        Button {
                            guard option != sport else { return }
                            sport = option
                            durationMinutes = option.defaultDurationMinutes
                            reconcileSelection()
                            AppHaptics.selection()
                        } label: {
                            HStack(spacing: 8) {
                                SportIconView(sport: option, color: selected ? VisitStyle.onAccent : .white, size: 15)
                                Text(option.title)
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? VisitStyle.onAccent : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(selected ? VisitStyle.accent : VisitStyle.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.string("When", "Когда"))

            HStack(spacing: 8) {
                ForEach(quickDays, id: \.self) { option in
                    dayChip(option)
                }
                calendarChip
            }

            partPicker
                .padding(.top, 4)

            if slots.isEmpty {
                Text(emptySlotsText)
                    .font(.system(size: 14))
                    .foregroundStyle(VisitStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(slots, id: \.self) { minute in
                        let selected = minute == startMinute
                        Button {
                            startMinute = minute
                            AppHaptics.selection()
                        } label: {
                            Text(PersonalVisitPlanner.clock(minute))
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(selected ? VisitStyle.onAccent : .white)
                                .background(selected ? VisitStyle.accent : VisitStyle.surface,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selected ? Color.clear : VisitStyle.line, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func dayChip(_ option: Date) -> some View {
        let calendar = Calendar.current
        let selected = calendar.isDate(option, inSameDayAs: day)
        return Button {
            selectDay(option)
        } label: {
            VStack(spacing: 2) {
                Text(dayChipTitle(option))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(CachedDateFormatters.display(format: "d").string(from: option))
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(selected ? VisitStyle.onAccent : .white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(selected ? VisitStyle.accent : VisitStyle.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.clear : VisitStyle.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var calendarChip: some View {
        Button {
            isDatePickerPresented = true
            AppHaptics.selection()
        } label: {
            Group {
                if isCustomDay {
                    VStack(spacing: 2) {
                        Text(CachedDateFormatters.display(format: "MMM").string(from: day))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(CachedDateFormatters.display(format: "d").string(from: day))
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                    }
                } else {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundStyle(isCustomDay ? VisitStyle.onAccent : .white)
            .frame(width: 52, height: 60)
            .background(isCustomDay ? VisitStyle.accent : VisitStyle.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCustomDay ? Color.clear : VisitStyle.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("Another date", "Другая дата"))
    }

    private var partPicker: some View {
        HStack(spacing: 3) {
            ForEach(VisitDayPart.allCases) { option in
                let selected = option == part
                Button {
                    guard option != part else { return }
                    withAnimation(AppMotion.quick) {
                        part = option
                    }
                    AppHaptics.selection()
                } label: {
                    Text(partTitle(option))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? .white : VisitStyle.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selected ? Color(red: 0.15, green: 0.19, blue: 0.17) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(VisitStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var durationSection: some View {
        let options = PersonalVisitPlanner.durationOptions(including: durationMinutes)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.string("How long", "Сколько"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: options.count), spacing: 8) {
                ForEach(options, id: \.self) { minutes in
                    let selected = minutes == durationMinutes
                    Button {
                        guard minutes != durationMinutes else { return }
                        durationMinutes = minutes
                        reconcileSelection()
                        AppHaptics.selection()
                    } label: {
                        Text(PersonalVisitPlanner.durationLabel(minutes, russian: isRussian))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? VisitStyle.onAccent : .white)
                            .background(selected ? VisitStyle.accent : VisitStyle.surface,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? Color.clear : VisitStyle.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        if isNoteVisible {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L10n.string("Note for yourself", "Заметка для себя"))
                TextField(
                    L10n.string("Serve practice, then rallies at the net", "Подача, потом розыгрыши у сетки"),
                    text: $comment,
                    axis: .vertical
                )
                .lineLimit(2 ... 5)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(VisitStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VisitStyle.line, lineWidth: 1))
                Text("\(commentLength)/240")
                    .font(.caption)
                    .foregroundStyle(commentLength > 240 ? VisitStyle.destructive : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            Button {
                withAnimation(AppMotion.quick) {
                    isNoteVisible = true
                }
            } label: {
                Label(L10n.string("Note for yourself", "Заметка для себя"), systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VisitStyle.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let summary {
                Text(summary)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView().tint(VisitStyle.onAccent)
                    }
                    Text(ctaTitle)
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(canSave || isSaving ? VisitStyle.onAccent : Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(canSave || isSaving ? VisitStyle.accent : VisitStyle.surface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .animation(AppMotion.quick, value: canSave)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityIdentifier("visit-composer-save")

            HStack(spacing: 4) {
                Text(L10n.string("This does not book a court", "Корт этим не бронируется"))
                if let bookingURL {
                    Text("·")
                    Button {
                        openURL(bookingURL)
                    } label: {
                        Text(L10n.string("Book with the club ↗", "Бронь у клуба ↗"))
                            .fontWeight(.semibold)
                            .foregroundStyle(VisitStyle.accent)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(VisitStyle.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(VisitStyle.sheet)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var datePickerSheet: some View {
        let today = Calendar.current.startOfDay(for: now)
        let limit = Calendar.current.date(byAdding: .day, value: 180, to: today) ?? today
        return NavigationStack {
            DatePicker(
                L10n.string("Date", "Дата"),
                selection: Binding(get: { day }, set: { selectDay($0) }),
                in: today ... limit,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(VisitStyle.accent)
            .padding(.horizontal, 16)
            .navigationTitle(L10n.string("Visit date", "Дата визита"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done", "Готово")) { isDatePickerPresented = false }
                }
            }
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: Text

    private var isRussian: Bool {
        L10n.string("en", "ru") == "ru"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VisitStyle.secondaryText)
    }

    private func dayChipTitle(_ option: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(option, inSameDayAs: now) { return L10n.string("Today", "Сегодня") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(option, inSameDayAs: tomorrow) {
            return L10n.string("Tomorrow", "Завтра")
        }
        return CachedDateFormatters.display(format: "EEEEEE").string(from: option).capitalized
    }

    private func partTitle(_ option: VisitDayPart) -> String {
        switch option {
        case .morning: return L10n.string("Morning", "Утро")
        case .afternoon: return L10n.string("Afternoon", "День")
        case .evening: return L10n.string("Evening", "Вечер")
        }
    }

    private var emptySlotsText: String {
        if dayStarts.isEmpty {
            return Calendar.current.isDate(day, inSameDayAs: now)
                ? L10n.string("Nothing left today before the club closes. Pick another day.", "Сегодня до закрытия клуба уже не успеть — выбери другой день.")
                : L10n.string("No time fits this day before closing. Pick another day.", "В этот день до закрытия не успеть — выбери другой.")
        }
        return L10n.string("No free time in this part of the day. Switch above.", "В эту часть дня времени нет — переключись выше.")
    }

    private var summary: String? {
        guard let start = selectedStart else { return nil }
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return "\(PersonalVisitDateText.day(start, now: now, style: .full)) · \(start.formattedHourMinute())–\(end.formattedHourMinute())"
    }

    private var ctaTitle: String {
        if isSaving { return L10n.string("Saving…", "Сохраняем…") }
        if selectedStart == nil { return L10n.string("Choose a time", "Выбери время") }
        return isEditing ? L10n.string("Save changes", "Сохранить изменения") : L10n.string("Plan the visit", "Запланировать визит")
    }

    private var bookingURL: URL? {
        guard let raw = court?.bookingUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    // MARK: Behaviour

    private func refreshNow() {
        now = Date()
        reconcileSelection()
    }

    private func selectDay(_ option: Date) {
        let target = Calendar.current.startOfDay(for: option)
        guard target != day else { return }
        day = target
        reconcileSelection()
        AppHaptics.selection()
    }

    /// Keeps the chosen time only while the club can still take it; opens the part of the
    /// day that has free time when the current one has none.
    private func reconcileSelection() {
        let starts = dayStarts
        if let startMinute, !starts.contains(startMinute) {
            let keepsOwnTime = isEditing && selectedStart != nil
            if !keepsOwnTime { self.startMinute = nil }
        }
        if !starts.contains(where: { part.minutes.contains($0) }),
           let open = VisitDayPart.allCases.first(where: { option in starts.contains { option.minutes.contains($0) } }) {
            part = open
        }
    }

    private func save() async {
        guard !isSaving else { return }
        refreshNow()
        guard let start = selectedStart else {
            errorMessage = L10n.string("That time has already passed. Choose another one.", "Это время уже прошло — выбери другое.")
            return
        }
        let generation = appModel.sessionGeneration
        let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        defer { isSaving = false }

        do {
            let saved: PersonalActivity
            switch mode {
            case .create(let court, _):
                saved = try await appModel.repository.createPersonalActivity(
                    PersonalActivityDraft(courtId: court.id, sport: sport, scheduledAt: start, durationMinutes: durationMinutes, comment: note)
                )
            case .edit(let activity):
                saved = try await appModel.repository.updatePersonalActivity(
                    activityId: activity.id,
                    draft: PersonalActivityUpdateDraft(
                        scheduledAt: start, durationMinutes: durationMinutes, comment: note,
                        status: nil, reportComment: nil, photoUrls: nil
                    )
                )
            }
            guard appModel.isCurrentSession(generation) else { return }
            AppHaptics.impact(.medium)
            dismiss()
            await onSaved(saved)
        } catch {
            guard appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// The club's photo when it has one, else the sport on a tinted tile.
struct PersonalVisitArtwork: View {
    let court: Court?
    let sport: Sport
    let size: CGFloat

    var body: some View {
        if let court {
            CourtImageTile(court: court, size: size, showsCarousel: false)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.court)
                SportIconView(sport: sport, color: .white.opacity(0.88), size: size * 0.4)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Day wording shared by the composer, the cards and the snackbar.
enum PersonalVisitDateText {
    enum Style { case short, full }

    /// "Сегодня", "Завтра", "Вчера", else "Пт, 2 окт." (short) or "Пт, 2 октября" (full).
    static func day(_ date: Date, now: Date = Date(), style: Style) -> String {
        if let relative = relative(date, now: now) { return relative }
        let format = style == .full ? "EE, d MMMM" : "EE, d MMM"
        let text = CachedDateFormatters.display(format: format).string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Сегодня", "Завтра" or "Вчера"; nil for any other day.
    static func relative(_ date: Date, now: Date = Date()) -> String? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        switch calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0 {
        case 0: return L10n.string("Today", "Сегодня")
        case 1: return L10n.string("Tomorrow", "Завтра")
        case -1: return L10n.string("Yesterday", "Вчера")
        default: return nil
        }
    }
}
