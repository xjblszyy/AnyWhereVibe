# Self-Hosted Connection Node Guide

This guide covers the current self-hosted deployment path for `connection-node` in this repository.

## Current Scope

- Supported: self-hosted mode with SQLite-backed user/token management and `/ws` + `/health`.
- Not supported yet: managed mode runtime, PostgreSQL runtime path, STUN/TURN, and TLS automation (`rustls-acme`).

## Build the Binary

From the repo root:

```bash
cargo build -p connection-node --release
```

Binary path:

```text
target/release/connection-node
```

Optional cross-compilation (if your toolchain has those targets installed):

```bash
cargo build -p connection-node --release --target x86_64-unknown-linux-musl
cargo build -p connection-node --release --target aarch64-unknown-linux-musl
```

## Configure `connection-node.toml`

The binary checks config in this order:

1. `--config <PATH>` when provided
2. `./connection-node.toml`
3. `/etc/mrt/connection-node.toml`

Example config:

```toml
[server]
listen_addr = "0.0.0.0:443"
mode = "self-hosted"

[storage]
type = "sqlite"
path = "/var/lib/mrt/mrt-node.db"

[log]
level = "info"
```

## Create App Users and Tokens

Use the same binary for user management:

```bash
./target/release/connection-node --config /etc/mrt/connection-node.toml user add --name alice
./target/release/connection-node --config /etc/mrt/connection-node.toml user list
./target/release/connection-node --config /etc/mrt/connection-node.toml user reset --name alice
./target/release/connection-node --config /etc/mrt/connection-node.toml user revoke --name alice
```

## Run with Docker

Build image:

```bash
docker build -f deploy/Dockerfile.connection-node -t mrt-connection-node .
```

Create host config/data directories:

```bash
sudo mkdir -p /opt/mrt/config /opt/mrt/data
sudo tee /opt/mrt/config/connection-node.toml >/dev/null <<'EOF'
[server]
listen_addr = "0.0.0.0:443"
mode = "self-hosted"

[storage]
type = "sqlite"
path = "/var/lib/mrt/mrt-node.db"

[log]
level = "info"
EOF
```

Run container:

```bash
docker run -d \
  --name mrt-connection-node \
  --restart unless-stopped \
  --cap-add NET_BIND_SERVICE \
  -p 443:443 \
  -v /opt/mrt/config:/etc/mrt \
  -v /opt/mrt/data:/var/lib/mrt \
  mrt-connection-node
```

Why this Dockerfile uses `debian:bookworm-slim` instead of `scratch`:

- The current crate build is not guaranteed to produce a fully static binary in every environment.
- Runtime SQLite and CA cert assets are easier to keep reliable with a minimal distro base.

## Run with systemd

Install binary, config, and service on Linux host:

```bash
sudo useradd --system --home /var/lib/mrt --create-home --shell /usr/sbin/nologin mrt || true
sudo install -d -m 0755 -o mrt -g mrt /etc/mrt /var/lib/mrt
sudo install -m 0755 ./target/release/connection-node /usr/local/bin/connection-node
sudo install -m 0644 ./deploy/connection-node.service /etc/systemd/system/connection-node.service
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now connection-node
sudo systemctl status connection-node --no-pager
```

## Health Checks

Local check:

```bash
curl -fsS http://127.0.0.1:443/health
```

Expected response body:

```text
ok
```

## Known Limitations and Future Work

- Self-hosted mode is the only production path currently.
- TLS auto-provisioning is not implemented yet (`rustls-acme` is future work).
- If you need TLS today, terminate TLS with a reverse proxy/LB (for example Caddy/Nginx/HAProxy) in front of `connection-node`.
