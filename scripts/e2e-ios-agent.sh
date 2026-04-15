#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
original_home="${HOME}"

host="${MRT_E2E_HOST:-127.0.0.1}"
port="${MRT_E2E_PORT:-9876}"
test_filter="${MRT_E2E_TEST_FILTER:-AgentE2ETests/testMockAgentHappyPathStreamsOutputAndResumesAfterApproval}"

workspace_dir="$(mktemp -d "${TMPDIR:-/tmp}/mrt-ios-e2e.XXXXXX")"
package_dir="${workspace_dir}/package"
agent_home="${workspace_dir}/agent-home"
agent_log="${workspace_dir}/agent.log"
agent_pid=""

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
require_tool swift

mkdir -p "${package_dir}/Sources/MRT" "${package_dir}/Tests/MRTTests/Integration"
mkdir -p "${agent_home}"

cat > "${package_dir}/Package.swift" <<'EOF'
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MRTE2EHarness",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MRT", targets: ["MRT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.36.1"),
    ],
    targets: [
        .target(
            name: "MRT",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/MRT"
        ),
        .testTarget(
            name: "MRTTests",
            dependencies: ["MRT"],
            path: "Tests/MRTTests"
        ),
    ]
)
EOF

for source in \
  ios/MRT/Core/Models/ChatMessage.swift \
  ios/MRT/Core/Models/SessionModel.swift \
  ios/MRT/Core/Network/ConnectionManager.swift \
  ios/MRT/Core/Network/MessageDispatcher.swift \
  ios/MRT/Core/Network/ProtobufCodec.swift \
  ios/MRT/Core/Network/WebSocketClient.swift \
  ios/MRT/Core/Proto/Mrt.pb.swift
do
  ln -s "${repo_root}/${source}" "${package_dir}/Sources/MRT/$(basename "${source}")"
done

ln -s \
  "${repo_root}/ios/MRTTests/Integration/AgentE2ETests.swift" \
  "${package_dir}/Tests/MRTTests/Integration/AgentE2ETests.swift"

(
  cd "${repo_root}"
  HOME="${agent_home}" \
  CARGO_HOME="${CARGO_HOME:-${original_home}/.cargo}" \
  RUSTUP_HOME="${RUSTUP_HOME:-${original_home}/.rustup}" \
  cargo run -p agent -- --mock --listen "127.0.0.1:${port}"
) >"${agent_log}" 2>&1 &
agent_pid=$!

wait_for_port "127.0.0.1" "${port}"

cd "${package_dir}"
MRT_E2E_HOST="${host}" MRT_E2E_PORT="${port}" swift test --filter "${test_filter}"
