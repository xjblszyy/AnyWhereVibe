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
listen_addr = "0.0.0.0:8443"
mode = "self-hosted"

[storage]
type = "sqlite"
path = "/var/lib/mrt/mrt-node.db"

[log]
level = "info"
```

Install this config at the path expected by the systemd unit:

```bash
sudo groupadd --system mrt || true
sudo useradd --system --gid mrt --home /var/lib/mrt --create-home --shell /usr/sbin/nologin mrt || true
sudo install -d -m 0755 -o root -g root /etc/mrt
sudo install -d -m 0750 -o mrt -g mrt /var/lib/mrt
sudo install -m 0640 -o root -g mrt /dev/null /etc/mrt/connection-node.toml
sudo tee /etc/mrt/connection-node.toml >/dev/null <<'EOF'
[server]
listen_addr = "0.0.0.0:8443"
mode = "self-hosted"

[storage]
type = "sqlite"
path = "/var/lib/mrt/mrt-node.db"

[log]
level = "info"
EOF
sudo chown root:mrt /etc/mrt/connection-node.toml
sudo chmod 0640 /etc/mrt/connection-node.toml
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

The container image pins `mrt` to `UID:GID 10001:10001` (override only if you also adjust host ownership).

Create host config/data directories with matching ownership:

```bash
MRT_UID=10001
MRT_GID=10001
sudo install -d -m 0755 -o root -g root /opt/mrt/config
sudo install -d -m 0750 -o "${MRT_UID}" -g "${MRT_GID}" /opt/mrt/data
sudo install -m 0640 -o root -g "${MRT_GID}" /dev/null /opt/mrt/config/connection-node.toml
sudo tee /opt/mrt/config/connection-node.toml >/dev/null <<'EOF'
[server]
listen_addr = "0.0.0.0:8443"
mode = "self-hosted"

[storage]
type = "sqlite"
path = "/var/lib/mrt/mrt-node.db"

[log]
level = "info"
EOF
sudo chown root:"${MRT_GID}" /opt/mrt/config/connection-node.toml
sudo chmod 0640 /opt/mrt/config/connection-node.toml
```

Run container:

```bash
docker run -d \
  --name mrt-connection-node \
  --restart unless-stopped \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  -p 8443:8443 \
  -v /opt/mrt/config:/etc/mrt:ro \
  -v /opt/mrt/data:/var/lib/mrt \
  mrt-connection-node
```

`--cap-drop ALL` is sufficient for the default `8443` listener. Only add
`--cap-add NET_BIND_SERVICE` if you intentionally bind a privileged port (for example `443`) inside the container.

Why this Dockerfile uses `debian:bookworm-slim` instead of `scratch`:

- The current crate build is not guaranteed to produce a fully static binary in every environment.
- Runtime SQLite and CA cert assets are easier to keep reliable with a minimal distro base.
- With the default `8443` listener, no Linux capabilities are required in the container.

## Run with systemd

Install binary, config, and service on Linux host:

```bash
sudo groupadd --system mrt || true
sudo useradd --system --gid mrt --home /var/lib/mrt --create-home --shell /usr/sbin/nologin mrt || true
sudo install -d -m 0755 -o root -g root /etc/mrt
sudo install -d -m 0750 -o mrt -g mrt /var/lib/mrt
sudo install -m 0640 -o root -g mrt /dev/null /etc/mrt/connection-node.toml
sudo tee /etc/mrt/connection-node.toml >/dev/null <<'EOF'
[server]
listen_addr = "0.0.0.0:8443"
mode = "self-hosted"

[storage]
type = "sqlite"
path = "/var/lib/mrt/mrt-node.db"

[log]
level = "info"
EOF
sudo chown root:mrt /etc/mrt/connection-node.toml
sudo chmod 0640 /etc/mrt/connection-node.toml
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
curl -fsS http://127.0.0.1:8443/health
```

Expected response body:

```text
ok
```

## Known Limitations and Future Work

- Self-hosted mode is the only production path currently.
- TLS auto-provisioning is not implemented yet (`rustls-acme` is future work).
- Default examples intentionally run plaintext on `8443` only.
- If you need external `443`/`wss`, terminate TLS with a reverse proxy/LB (for example Caddy/Nginx/HAProxy) in front of `connection-node` and proxy to `127.0.0.1:8443`.
