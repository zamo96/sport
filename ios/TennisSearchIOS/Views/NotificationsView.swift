import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager
    @State private var collapsedGroups: Set<AppNotificationType> = []

    private var groupedNotifications: [(type: AppNotificationType, items: [AppNotification])] {
        let order: [AppNotificationType] = [.new_message, .new_match, .incoming_like, .search_response, .application_result, .hot_event]
        let groups = Dictionary(grouping: notificationManager.notifications, by: \.type)
        return order.compactMap { type in
            guard let items = groups[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if groupedNotifications.isEmpty {
                    SectionCard(title: "Пока всё спокойно", subtitle: "Когда появятся новые события, они будут собраны здесь по разделам.") {
                        EmptyStateView(
                            title: "Новых уведомлений нет",
                            subtitle: "Здесь появятся сообщения, мэтчи, входящие лайки и изменения по твоим поискам.",
                            systemImage: "bell.slash"
                        )
                    }
                } else {
                    ForEach(groupedNotifications, id: \.type) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    toggleGroup(group.type)
                                }
                            } label: {
                                HStack {
                                    Text(groupTitle(group.type))
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    AppInlineChip(
                                        text: "\(group.items.count)",
                                        tint: .white.opacity(0.12),
                                        foreground: .white.opacity(0.82)
                                    )
                                    Image(systemName: collapsedGroups.contains(group.type) ? "chevron.down" : "chevron.up")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white.opacity(0.52))
                                }
                            }
                            .buttonStyle(.plain)

                            if !collapsedGroups.contains(group.type) {
                                ForEach(group.items) { item in
                                    NotificationGroupCard(item: item, groupTitle: groupTitle(group.type)) {
                                        openNotification(item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Уведомления")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: appModel.sessionGeneration) {
            await notificationManager.refreshAuthorizationStatus()
            guard !Task.isCancelled else { return }
            await notificationManager.manualRefresh(repository: appModel.repository)
            guard !Task.isCancelled else { return }
            try? await appModel.repository.markNotificationsSeen()
            guard !Task.isCancelled else { return }
            notificationManager.markNotificationsOpened()
        }
        .refreshable {
            await notificationManager.manualRefresh(repository: appModel.repository)
            try? await appModel.repository.markNotificationsSeen()
            notificationManager.markNotificationsOpened()
        }
    }

    @ViewBuilder
    private var headerCard: some View {
        SectionCard(
            title: "Уведомления",
            subtitle: "Новые мэтчи, сообщения, входящие симпатии, отклики и срочные события."
        ) {
            if notificationManager.authorizationStatus == .notDetermined {
                Button("Разрешить уведомления") {
                    Task {
                        await notificationManager.requestAuthorization()
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            } else if notificationManager.authorizationStatus == .denied {
                Button("Открыть настройки уведомлений") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    openURL(settingsURL)
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
            }

            HStack(spacing: 8) {
                AppInlineChip(
                    text: notificationManager.authorizationStatus.title,
                    tint: notificationStatusTint,
                    foreground: notificationStatusForeground
                )
                if notificationManager.unreadNotificationCount > 0 {
                    AppInlineChip(
                        text: "Новых: \(notificationManager.unreadNotificationCount)",
                        tint: AppTheme.cream,
                        foreground: AppTheme.ink
                    )
                }
            }
        }
    }

    private var notificationStatusTint: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return AppTheme.mint
        case .denied:
            return Color.red.opacity(0.14)
        default:
            return AppTheme.cream
        }
    }

    private var notificationStatusForeground: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return AppTheme.court
        case .denied:
            return .red
        default:
            return AppTheme.ink
        }
    }

    private func groupTitle(_ type: AppNotificationType) -> String {
        switch type {
        case .new_match:
            return "Новые мэтчи"
        case .new_message:
            return "Новые сообщения"
        case .incoming_like:
            return "Хотят с тобой сыграть"
        case .search_response:
            return "Новые отклики"
        case .application_result:
            return "Решения по заявкам"
        case .hot_event:
            return "Срочные события"
        }
    }

    private func toggleGroup(_ type: AppNotificationType) {
        if collapsedGroups.contains(type) {
            collapsedGroups.remove(type)
        } else {
            collapsedGroups.insert(type)
        }
    }

    private func openNotification(_ item: AppNotification) {
        guard let target = AppNavigationTarget(notificationHref: item.href) else {
            return
        }
        appModel.navigate(to: target)
        dismiss()
    }
}

private struct NotificationGroupCard: View {
    let item: AppNotification
    let groupTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(groupTint.opacity(0.16))
                            .frame(width: 46, height: 46)
                        Image(systemName: groupIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(groupTint)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text(item.description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(.leading)

                        if let ctaLabel {
                            Text(ctaLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(groupTint)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.36))
                        .padding(.top, 4)
                }

                HStack {
                    Text(groupTitle)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.6)
                        .foregroundStyle(groupTint)
                    Spacer()
                    Text(item.createdAt.formattedDateTime())
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: cardGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var groupIcon: String {
        switch item.type {
        case .new_match:
            return "heart.fill"
        case .new_message:
            return "message.fill"
        case .incoming_like:
            return "sparkles"
        case .search_response:
            return "paperplane.fill"
        case .application_result:
            return "checkmark.seal.fill"
        case .hot_event:
            return "flame.fill"
        }
    }

    private var groupTint: Color {
        if item.type == .application_result, item.status == "rejected" {
            return Color(red: 1.0, green: 0.36, blue: 0.34)
        }

        switch item.type {
        case .new_match:
            return Color(red: 0.96, green: 0.48, blue: 0.52)
        case .new_message:
            return Color(red: 0.42, green: 0.72, blue: 1.0)
        case .incoming_like:
            return AppTheme.court
        case .search_response:
            return Color(red: 0.97, green: 0.65, blue: 0.29)
        case .application_result:
            return Color(red: 0.48, green: 0.86, blue: 0.60)
        case .hot_event:
            return Color(red: 1.0, green: 0.42, blue: 0.34)
        }
    }

    private var cardGradientColors: [Color] {
        if item.type == .application_result, item.status == "rejected" {
            return [Color.red.opacity(0.22), Color.red.opacity(0.10)]
        }

        return [Color.white.opacity(0.10), Color.white.opacity(0.05)]
    }

    private var ctaLabel: String? {
        switch item.type {
        case .application_result where item.status == "approved":
            if item.href.hasPrefix("/inbox/") {
                return "Открыть чат"
            }
            return "Открыть событие"
        case .incoming_like:
            return "Открыть игрока"
        case .new_match:
            return "Перейти в чат"
        case .new_message:
            return "Открыть переписку"
        default:
            return nil
        }
    }
}
