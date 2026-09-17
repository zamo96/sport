#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-mock-inbox.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

# Exercise the repository's actual counting/seen/reset methods with real message
# models; only unrelated profile, search, and match payload fields are replaced.
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
source_dir = Path(sys.argv[1]).parent / "TennisSearchIOS"
core = (source_dir / "Core/AppModels.swift").read_text()
repository = (source_dir / "Services/MockRepository.swift").read_text()

def declaration(source, name):
    start = source.index(name)
    opening = source.index("{", start)
    depth, index = 1, opening + 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[start:index]

assert "inboxBadgeCount: unseenInboxThreadIDs.count," in declaration(repository, "    func fetchActivitySummary(")
result = "import Foundation\nimport CoreGraphics\n"
result += core[core.index("// MARK: - Chat receipt state"):core.index("// MARK: - End chat receipt state")]
result += core[core.index("struct ChatMessage:"):core.index("struct SearchResponse:")]
result += """
struct InboxMatch { let id: String; var status: String = "active" }
struct InboxUser { let id: String }
final class MockInboxHarness {
    var currentUser = InboxUser(id: "self")
    var matches: [InboxMatch] = []
    var messagesByMatch: [String: [ChatMessage]] = [:]
    var searches: [Int] = []
    var notifications: [Int] = []
    var discoverUsers: [Int] = []
    var incomingLikes: [Int] = []
    var inboxBadgeCount: Int { unseenInboxThreadIDs.count }
"""
for name in ["seenInboxMatchIDs", "seenInboxIncomingMessageIDs"]:
    line = next(line for line in repository.splitlines() if f"private var {name}:" in line)
    result += line.replace("private ", "") + "\n"
for name in ["    private var unseenInboxThreadIDs:", "    func markInboxSeen(", "    func deleteAccount("]:
    result += declaration(repository, name) + "\n"
result += "}\n"
(Path(sys.argv[2]) / "MockInboxProduction.swift").write_text(result)
PY
swiftc "$temp_dir/MockInboxProduction.swift" "$test_dir/MockInboxSeenTests.swift" -o "$temp_dir/mock-inbox-tests"
"$temp_dir/mock-inbox-tests"
