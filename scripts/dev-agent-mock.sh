#!/usr/bin/env bash
set -euo pipefail
cargo run -p agent -- --mock --listen 0.0.0.0:9876
