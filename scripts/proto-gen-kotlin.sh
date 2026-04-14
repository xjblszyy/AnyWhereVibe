#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/generated/kotlin-proto
protoc -I proto --kotlin_out=build/generated/kotlin-proto proto/mrt.proto
