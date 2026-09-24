#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-upcoming-widget.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
# Compile the actual production projection/timeline/provider and app store code.
# WidgetKit/ActivityKit entry points and unrelated presentation model fields are stubs.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent
out = Path(sys.argv[2])
widget_source = (root / 'TennisSearchUpcomingWidget/UpcomingGamesWidget.swift').read_text()
widget = widget_source.split('struct UpcomingGamesWidgetEntryView:')[0]
widget += widget_source[widget_source.index('private final class WidgetAuthenticatedSessionDelegate:'):]
widget = widget.replace('import ActivityKit\n', '').replace('import SwiftUI\n', '').replace('import WidgetKit', 'import Foundation')
widget = widget.replace('struct UpcomingGamesProvider: TimelineProvider {', 'struct UpcomingGamesProvider {')
widget = widget.replace('private ', '').replace('group.shop.sportsearch.app', 'widget.tests.' + out.name)
stubs = '''
struct SecureSessionStore {
    init(baseURL: URL) {}
    func read() -> String? { nil }
    static func origin(for url: URL) -> String { url.absoluteString }
}
protocol TimelineEntry {}
struct Context {}
struct Timeline<E> { enum Policy { case after(Date) }; let entries: [E]; let policy: Policy }
'''
(out / 'WidgetProduction.swift').write_text(stubs + widget)
store = (root / 'TennisSearchIOS/Services/UpcomingGamesWidgetStore.swift').read_text().split('private enum UpcomingGameLiveActivityManager')[0]
store = store.replace('import ActivityKit\n', '').replace('import WidgetKit\n', '').replace('private ', '')
store = store.replace('group.shop.sportsearch.app', 'widget.store.tests.' + out.name)
core = (root / 'TennisSearchIOS/Core/AppModels.swift').read_text()
def declaration(source, name):
    start = source.index(name)
    index = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index]
# Preserve the real PersonalActivity decoding, scheduledDate, and history predicate.
personal = declaration(core, 'struct PersonalActivity:')
photos = declaration(core, 'struct PersonalActivityPhoto:')
parse = declaration(widget, 'extension String {')
store_stubs = '''
struct WidgetCenter { static let shared = Self(); func reloadTimelines(ofKind: String) {} }
enum UpcomingGameLiveActivityManager {
    static func sync(gameRequests: [MatchGameRequest], currentUserId: String?) {}
    static func endAll() {}
}
struct Court: Codable { let name: String; let address: String }
struct Sport: Codable {
    let title: String
    let defaultDurationMinutes: Int
    var venuePendingTitle: String { "Корт уточняется" }
}
struct MatchGameRequest {
    let id: String
    let proposedDate: Date?
    let durationMinutes: Int?
    let status: String
    let outcome: String?
    let sport: Sport
    var proposedCourt: Court? { nil }
    var statusLabel: String { "Игра подтверждена" }
    func upcomingDisplayName(currentUserId: String?) -> String { "Игрок" }
}
extension PersonalActivity { var widgetStatusLabel: String { "Визит запланирован" } }
'''
(out / 'StoreProduction.swift').write_text('\n'.join([store, personal, photos, parse, store_stubs]))
PY
swiftc "$temp_dir/WidgetProduction.swift" "$test_dir/UpcomingGamesWidgetTests.swift" -o "$temp_dir/widget-tests"
"$temp_dir/widget-tests"
swiftc -D STORE_TESTS "$temp_dir/StoreProduction.swift" "$test_dir/UpcomingGamesWidgetTests.swift" -o "$temp_dir/store-tests"
"$temp_dir/store-tests"
