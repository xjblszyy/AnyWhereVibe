#!/usr/bin/env bash
set -euo pipefail
mkdir -p ios/MRT/Core/Proto
protoc -I proto --swift_out=ios/MRT/Core/Proto proto/mrt.proto
