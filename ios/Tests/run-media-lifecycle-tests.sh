#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-media-lifecycle.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]).parent / 'TennisSearchIOS/Views/RemoteMedia.swift').read_text()
# Exercise actual cache/task lifecycle; UIKit decoding is replaced with a labeled image.
start = source.index('struct RemoteImageSource {')
end = source.index('    private static func decode(')
text = '''import Foundation
enum ContentMode { case fit, fill }
final class UIImage: NSObject {
    let label: String
    init(_ label: String) { self.label = label }
}
''' + source[start:end]
text += '''    private static func decode(_ data: Data, fitting pixelSize: CGSize, contentMode: ContentMode) -> UIImage? {
        UIImage(String(decoding: data, as: UTF8.self))
    }
    private static func cost(of image: UIImage) -> Int { 1 }
}
'''
start = source.index('struct RemoteImageRequest {')
end = source.index('// MARK: - Loading indicators')
text += source[start:end]
(Path(sys.argv[2]) / 'MediaProduction.swift').write_text(text)
PY
swiftc "$temp_dir/MediaProduction.swift" "$test_dir/MediaLifecycleTests.swift" -o "$temp_dir/media-lifecycle-tests"
"$temp_dir/media-lifecycle-tests"
