#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
proto_file="${repo_root}/proto/mrt.proto"
android_out_dir="${repo_root}/android/app/src/main/java/com/mrt/app/proto"

if ! command -v protoc >/dev/null 2>&1; then
  echo "error: required tool 'protoc' was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${proto_file}" ]]; then
  echo "error: missing expected input '${proto_file}'." >&2
  exit 1
fi

cd "${repo_root}"
rm -rf "${android_out_dir}/mrt"
mkdir -p "${android_out_dir}"
protoc \
  -I proto \
  --java_out=lite:"${android_out_dir}" \
  --kotlin_out="${android_out_dir}" \
  proto/mrt.proto

find "${android_out_dir}/mrt" -name '*.kt' -print0 | while IFS= read -r -d '' generated_file; do
  python3 - <<'PY' "${generated_file}"
from pathlib import Path
import sys

path = Path(sys.argv[1])
contents = path.read_text()
contents = contents.replace("@file:com.google.protobuf.Generated\n", "")
path.write_text(contents)
PY
done

find "${android_out_dir}/mrt" -name '*.java' -print0 | while IFS= read -r -d '' generated_file; do
  python3 - <<'PY' "${generated_file}"
from pathlib import Path
import sys

path = Path(sys.argv[1])
contents = path.read_text()
contents = contents.replace("@com.google.protobuf.Generated\n", "")
path.write_text(contents)
PY
done
