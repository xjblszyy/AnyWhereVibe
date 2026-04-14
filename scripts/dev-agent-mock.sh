#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
agent_manifest="${repo_root}/crates/agent/Cargo.toml"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: required tool 'cargo' was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${agent_manifest}" ]]; then
  echo "error: missing expected input '${agent_manifest}'." >&2
  exit 1
fi

cd "${repo_root}"
echo "Starting mock agent on ws://0.0.0.0:9876/"
echo "Simulator: use 127.0.0.1:9876"
echo "Physical iPhone: use your Mac's LAN IP with port 9876"
cargo run -p agent -- --mock --listen 0.0.0.0:9876
