#!/bin/bash
# 统一测试入口：兼容「仅 CLT」与「完整 Xcode」两种环境。
# 仅 CLT 时 swift-testing 的 Testing.framework 与宏插件不在默认搜索路径，需手动注入。
set -euo pipefail
cd "$(dirname "$0")/.."

CLT_ROOT="/Library/Developer/CommandLineTools"
TESTING_FW="$CLT_ROOT/Library/Developer/Frameworks"
TESTING_LIB="$CLT_ROOT/Library/Developer/usr/lib"
TESTING_PLUGIN="$CLT_ROOT/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

if [ -d "$CLT_ROOT" ] && [ ! -d /Applications/Xcode.app ]; then
    swift test \
        -Xswiftc -F -Xswiftc "$TESTING_FW" \
        -Xcc -F -Xcc "$TESTING_FW" \
        -Xlinker -rpath -Xlinker "$TESTING_FW" \
        -Xlinker -rpath -Xlinker "$TESTING_LIB" \
        -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN"
else
    swift test
fi
