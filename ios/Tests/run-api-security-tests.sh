#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-api-security.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]).parent / 'TennisSearchIOS'
source = (root / 'Services/APIClient.swift').read_text()
source = source[:source.index('final class LiveTennisRepository:')]
source += '''
enum AppLocale: String { case en, ru }
struct RealtimeEvent: Decodable { var id: String?; var type: String?; var createdAt: String?; var title: String?; var body: String?; var href: String?; var matchId: String?; var searchId: String?; var messageId: String?; var gameRequestId: String?; var status: String? }
private struct ErrorEnvelope: Decodable { let error: String }
private struct LogoutRequest: Encodable { let pushDeviceToken: String? }
struct SecureSessionStore {
    init(baseURL: URL) {}
    func migrateLegacyToken(baseURL: URL) -> String? { nil }
    func write(_ token: String) throws {}
    func clear() {}
    static func origin(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "https"
        return "\\(scheme)://\\(url.host?.lowercased() ?? ""):\\(url.port ?? (scheme == "https" ? 443 : 80))"
    }
}
'''
(Path(sys.argv[2]) / 'APIProduction.swift').write_text(source)
PY
swiftc -swift-version 5 "$temp_dir/APIProduction.swift" "$test_dir/APISecurityTests.swift" -o "$temp_dir/api-security-tests"
"$temp_dir/api-security-tests"
