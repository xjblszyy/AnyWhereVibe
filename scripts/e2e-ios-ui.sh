#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

ios_project="${IOS_PROJECT_PATH:-ios/MRT.xcodeproj}"
ios_scheme="${IOS_SCHEME:-MRT}"
ios_simulator_id="${IOS_SIMULATOR_ID:-}"
ios_ui_test_filter="${IOS_UI_TEST_FILTER:-MRTUITests/MRTUITests}"

require_tool() {
  local tool="$1"
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: required tool '${tool}' was not found in PATH." >&2
    exit 1
  fi
}

resolve_simulator_id() {
  if [[ -n "${ios_simulator_id}" ]]; then
    echo "${ios_simulator_id}"
    return 0
  fi

  local booted_iphone_id
  booted_iphone_id="$(
    xcrun simctl list devices booted available \
      | awk -F '[()]' '/iPhone/ {print $2; exit}'
  )"
  if [[ -n "${booted_iphone_id}" ]]; then
    echo "${booted_iphone_id}"
    return 0
  fi

  local available_iphone_id
  available_iphone_id="$(
    xcrun simctl list devices available \
      | awk -F '[()]' '/iPhone/ {print $2; exit}'
  )"
  if [[ -n "${available_iphone_id}" ]]; then
    echo "${available_iphone_id}"
    return 0
  fi

  echo "error: failed to locate an available iPhone simulator. Set IOS_SIMULATOR_ID explicitly." >&2
  return 1
}

boot_simulator() {
  local simulator_id="$1"
  xcrun simctl boot "${simulator_id}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${simulator_id}" -b
}

require_tool xcodebuild
require_tool xcrun

ios_simulator_id="$(resolve_simulator_id)"
boot_simulator "${ios_simulator_id}"

cd "${repo_root}"
xcodebuild \
  -project "${ios_project}" \
  -scheme "${ios_scheme}" \
  -destination "id=${ios_simulator_id}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test \
  -only-testing:"${ios_ui_test_filter}"
