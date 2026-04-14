#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
proto_file="${repo_root}/proto/mrt.proto"

if ! command -v protoc >/dev/null 2>&1; then
  echo "error: required tool 'protoc' was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${proto_file}" ]]; then
  echo "error: missing expected input '${proto_file}'." >&2
  exit 1
fi

cd "${repo_root}"
mkdir -p build/generated/kotlin-proto
protoc -I proto --kotlin_out=build/generated/kotlin-proto proto/mrt.proto
