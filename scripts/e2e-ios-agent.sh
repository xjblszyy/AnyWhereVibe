#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
original_home="${HOME}"

host="${MRT_E2E_HOST:-127.0.0.1}"
port="${MRT_E2E_PORT:-9876}"
ios_test_filter="${MRT_E2E_TEST_FILTER:-MRTTests/AgentE2ETests}"

workspace_dir="$(mktemp -d "${TMPDIR:-/tmp}/mrt-ios-e2e.XXXXXX")"
agent_home="${workspace_dir}/agent-home"
agent_log="${workspace_dir}/agent.log"
agent_pid=""
ios_simulator_id="${IOS_SIMULATOR_ID:-}"

cleanup() {
  if [[ -n "${agent_pid}" ]]; then
    kill "${agent_pid}" >/dev/null 2>&1 || true
    wait "${agent_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "${workspace_dir}"
}
trap cleanup EXIT

require_tool() {
  local tool="$1"
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: required tool '${tool}' was not found in PATH." >&2
    exit 1
  fi
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local timeout_seconds="${3:-60}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      return 0
    fi

    if [[ -n "${agent_pid}" ]] && ! kill -0 "${agent_pid}" >/dev/null 2>&1; then
      echo "error: agent exited before opening ${host}:${port}." >&2
      if [[ -f "${agent_log}" ]]; then
        cat "${agent_log}" >&2
      fi
      return 1
    fi

    sleep 0.2
  done

  echo "error: timed out waiting for ${host}:${port} to become reachable." >&2
  if [[ -f "${agent_log}" ]]; then
    cat "${agent_log}" >&2
  fi
  return 1
}

require_tool cargo
require_tool xcodebuild
require_tool xcrun

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

mkdir -p "${agent_home}"
ios_simulator_id="$(resolve_simulator_id)"
boot_simulator "${ios_simulator_id}"

(
  cd "${repo_root}"
  HOME="${agent_home}" \
  CARGO_HOME="${CARGO_HOME:-${original_home}/.cargo}" \
  RUSTUP_HOME="${RUSTUP_HOME:-${original_home}/.rustup}" \
  cargo run -p agent -- --mock --listen "${host}:${port}"
) >"${agent_log}" 2>&1 &
agent_pid=$!

wait_for_port "${host}" "${port}"

cd "${repo_root}"
if ! MRT_E2E_HOST="${host}" \
  MRT_E2E_PORT="${port}" \
  SIMCTL_CHILD_MRT_E2E_HOST="${host}" \
  SIMCTL_CHILD_MRT_E2E_PORT="${port}" \
  xcodebuild \
    -project ios/MRT.xcodeproj \
    -scheme MRT \
    -destination "id=${ios_simulator_id}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    test \
    -only-testing:"${ios_test_filter}"; then
  cat "${agent_log}" >&2
  exit 1
fi
