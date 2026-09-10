#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 6 -strict-concurrency=complete \
  SwiftWhisper/SwiftWhisper/Platform/DiagnosticsLog.swift \
  Verification/DiagnosticsSmoke.swift -o "$test_dir/diagnostics-check"
"$test_dir/diagnostics-check"
