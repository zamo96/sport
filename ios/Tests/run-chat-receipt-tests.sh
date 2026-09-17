#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-chat-receipts.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
{
    printf 'import Foundation\nimport CoreGraphics\n'
    sed -n '/^\/\/ MARK: - Chat receipt state/,/^\/\/ MARK: - End chat receipt state/p' "$test_dir/../TennisSearchIOS/Core/AppModels.swift"
    sed -n '/^struct ChatMessage:/,/^struct SearchResponse:/p' "$test_dir/../TennisSearchIOS/Core/AppModels.swift" | sed '$d'
    sed -n '/^struct SearchLobbyMessage:/,/^struct SearchLobbySummary:/p' "$test_dir/../TennisSearchIOS/Core/AppModels.swift" | sed '$d'
} > "$temp_dir/ChatReceiptState.swift"
swiftc "$temp_dir/ChatReceiptState.swift" "$test_dir/ChatReceiptTests.swift" -o "$temp_dir/chat-receipt-tests"
"$temp_dir/chat-receipt-tests"
