#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/lisse-scroll-tests.XXXXXX")"
trap 'rm -rf "$test_build_dir"' EXIT
xcrun swiftc \
  -swift-version 5 \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$test_build_dir/module-cache" \
  "$project_root/Lisse/ScrollLogic.swift" \
  "$project_root/Lisse/SettingsStore.swift" \
  "$project_root/Lisse/ScrollEngine.swift" \
  "$project_root/Tests/ScrollDelivery/main.swift" \
  -o "$test_build_dir/scroll-delivery-tests"
"$test_build_dir/scroll-delivery-tests"
