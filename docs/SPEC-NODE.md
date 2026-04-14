# SPEC-NODE — Connection Node

> Language: Rust  
> Dependency: SPEC-PROTO  
> Location: `crates/connection-node/`  
> Duration: P1 2-3 weeks (self-hosted), P2 2-3 weeks (managed extensions)

---

## Overview

A lightweight Rust server deployed on a public-IP machine. Same binary, two modes configured via TOML:
- **Self-hosted mode**: WebSocket relay + session routing + multi-user device registry. No STUN/ICE/TURN.
- **Managed mode**: Everything above + ICE signaling + STUN + TURN relay + JWT auth + PostgreSQL.

---

## File Structure

```
crates/connection-node/
├── Cargo.toml
└── src/
    ├── main.rs                   # CLI: `connection-node run` / `connection-node user add`
    ├── config.rs                 # TOML config
    ├── server.rs                 # Axum HTTP + WebSocket server
    ├── router.rs                 # Session router: match phone ↔ agent
    ├── registry.rs               # Device registry (in-memory + optional persistence)
    ├── relay.rs                  # Binary frame forwarding engine
    ├── auth.rs                   # Token validation (self-hosted) / JWT (managed)
    ├── user_cli.rs               # CLI subcommands for user management
    ├── tls.rs                    # TLS + auto ACME
    ├── db.rs                     # SQLite (self-hosted) / PostgreSQL (managed)
    ├── signaling.rs              # ICE candidate exchange (managed only)
    ├── stun.rs                   # STUN server (managed only)
    └── turn.rs                   # TURN relay (managed only)
```

---

## Config File

Location: `./connection-node.toml` or `/etc/mrt/connection-node.toml`

```toml
[server]
listen_addr = "0.0.0.0:443"
mode = "self-hosted"           # "self-hosted" | "managed"

[tls]
enabled = true
cert_path = "/etc/mrt/cert.pem"
key_path = "/etc/mrt/key.pem"
# OR auto ACME:
# auto_acme = true
# acme_domain = "relay.example.com"
# acme_email = "admin@example.com"

[storage]
# Self-hosted: SQLite
type = "sqlite"
path = "./mrt-node.db"
# Managed:
# type = "postgres"
# url = "postgres://user:pass@localhost/mrt"

[log]
level = "info"

# Managed mode only:
# [managed]
# stun_port = 3478
# turn_port = 3479
# turn_secret = "your-secret"
# jwt_secret = "your-jwt-secret"
```

---

## CLI Interface

```
connection-node run [--config <PATH>]     Start the server
connection-node user add --name <NAME>    Generate auth token for a user
connection-node user list                 List all users and their tokens
connection-node user revoke --name <NAME> Revoke a user's token
connection-node user reset --name <NAME>  Regenerate a user's token
```

---

## P1 Tasks (Self-Hosted Mode)

### NODE-T01: Project Setup

`Cargo.toml` dependencies:
```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
axum = { version = "0.7", features = ["ws"] }
axum-extra = "0.9"
tokio-tungstenite = "0.24"
futures-util = "0.3"
prost = "0.13"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
uuid = { version = "1", features = ["v4"] }
clap = { version = "4", features = ["derive"] }
rusqlite = { version = "0.31", features = ["bundled"] }
rand = "0.8"
base64 = "0.22"
tower = "0.4"
tower-http = { version = "0.5", features = ["cors", "trace"] }
proto-gen = { path = "../proto-gen" }

# TLS
rustls = "0.23"
tokio-rustls = "0.26"
# rustls-acme = "0.10"  # for auto Let's Encrypt
```

Steps:
1. Set up crate with dependencies.
2. Implement `config.rs` with TOML loading.
3. Implement `main.rs` with clap subcommands.
4. Verify compilation.

**Acceptance**: `cargo run -p connection-node -- run` starts and logs "listening on ...".

---

### NODE-T02: User Management CLI

```rust
// user_cli.rs
pub fn add_user(db: &Database, name: &str) -> Result<String> {
    let token = format!("mrt_ak_{}", generate_random_hex(24));
    db.insert_user(name, &token)?;
    println!("User '{}' created. Token: {}", name, token);
    Ok(token)
}

pub fn list_users(db: &Database) -> Result<()> {
    let users = db.list_users()?;
    for u in users {
        println!("{:<20} {:<50} {}", u.name, u.token, if u.active { "active" } else { "revoked" });
    }
    Ok(())
}

pub fn revoke_user(db: &Database, name: &str) -> Result<()>;
pub fn reset_user(db: &Database, name: &str) -> Result<String>;
```

Database schema (SQLite):
```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    token TEXT UNIQUE NOT NULL,
    active BOOLEAN DEFAULT 1,
    created_at INTEGER NOT NULL
);

CREATE TABLE devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER REFERENCES users(id),
    device_id TEXT UNIQUE NOT NULL,
    device_type INTEGER NOT NULL,
    display_name TEXT,
    last_seen INTEGER
);
```

Steps:
1. Implement SQLite database layer in `db.rs`.
2. Implement user CRUD in `user_cli.rs`.
3. Wire into `main.rs` clap subcommands.

**Acceptance**: `./connection-node user add --name ming` outputs a token. `./connection-node user list` shows the user.

---

### NODE-T03: Device Registry

```rust
// registry.rs
pub struct DeviceRegistry {
    db: Database,
    /// In-memory map of currently connected devices
    online: RwLock<HashMap<String, OnlineDevice>>,
}

struct OnlineDevice {
    user_id: i64,
    device_id: String,
    device_type: DeviceType,
    display_name: String,
    ws_tx: mpsc::Sender<Vec<u8>>,   // send channel to this device's WebSocket
    connected_at: Instant,
}

impl DeviceRegistry {
    /// Validate token, register device, add to online map.
    pub async fn register(&self, msg: DeviceRegister) -> Result<DeviceRegisterAck>;

    /// Remove device from online map on disconnect.
    pub async fn unregister(&self, device_id: &str);

    /// List all online devices for a given user (by token lookup).
    pub async fn list_devices_for_user(&self, user_id: i64) -> Vec<DeviceInfo>;

    /// Find an online device by device_id, verify it belongs to the same user.
    pub async fn find_device(&self, requester_user_id: i64, target_device_id: &str) -> Option<&OnlineDevice>;

    /// Get the send channel for a device.
    pub async fn get_sender(&self, device_id: &str) -> Option<mpsc::Sender<Vec<u8>>>;
}
```

Steps:
1. Implement in-memory registry backed by the SQLite device table.
2. On WebSocket connect: first message must be `DeviceRegister`. Validate token against `users` table.
3. On disconnect: remove from online map, update `last_seen` in DB.
4. User isolation: all lookups scoped to user_id. A user cannot see or connect to another user's devices.

**Acceptance**: Two agents register with different tokens. Each token's device list only shows its own agents.

---

### NODE-T04: Session Router

```rust
// router.rs
pub struct SessionRouter {
    registry: Arc<DeviceRegistry>,
    /// Active relay sessions: phone_device_id → agent_device_id
    sessions: RwLock<HashMap<String, RelaySession>>,
}

struct RelaySession {
    phone_device_id: String,
    agent_device_id: String,
    created_at: Instant,
    bytes_forwarded: AtomicU64,
}

impl SessionRouter {
    /// Phone requests connection to an agent.
    /// Validates: both devices exist, same user, agent is online.
    pub async fn connect(&self, phone_id: &str, target_agent_id: &str) -> Result<ConnectToDeviceAck>;

    /// Disconnect a relay session.
    pub async fn disconnect(&self, phone_id: &str);

    /// Route a binary frame from phone to agent (or vice versa).
    pub async fn route(&self, from_device_id: &str, frame: Vec<u8>) -> Result<()>;
}
```

Steps:
1. Implement session creation: phone sends `ConnectToDevice` → router validates → creates `RelaySession`.
2. Implement frame routing: after session is established, all subsequent binary frames are forwarded to the paired device.
3. Implement disconnect on WebSocket close.
4. Track `bytes_forwarded` for future billing.

**Acceptance**: Agent registers → Phone registers → Phone sends `ConnectToDevice` → Phone sends Protobuf command → Agent receives it → Agent response reaches Phone.

---

### NODE-T05: Relay Engine

```rust
// relay.rs
pub struct RelayEngine;

impl RelayEngine {
    /// Forward a binary frame from one WebSocket to another.
    /// Does NOT decode, decrypt, or inspect the payload.
    /// Simply copies bytes from source sender to target sender.
    pub async fn forward(
        from: &str,
        to_tx: &mpsc::Sender<Vec<u8>>,
        frame: Vec<u8>,
    ) -> Result<()> {
        to_tx.send(frame).await.map_err(|_| Error::DeviceDisconnected)
    }
}
```

This is deliberately simple. The relay is a "dumb pipe" for encrypted bytes.

---

### NODE-T06: WebSocket Server

```rust
// server.rs — Axum-based
pub async fn run(config: Config) -> Result<()> {
    let registry = Arc::new(DeviceRegistry::new(db));
    let router = Arc::new(SessionRouter::new(registry.clone()));

    let app = Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(health))
        .with_state(AppState { registry, router });

    // Bind with TLS if configured
    // ...
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_ws(socket, state))
}

async fn handle_ws(ws: WebSocket, state: AppState) {
    let (ws_tx, ws_rx) = ws.split();
    let (send_tx, send_rx) = mpsc::channel(256);

    // Spawn writer task: send_rx → ws_tx
    // Read first message: must be DeviceRegister
    // Validate and register
    // Main read loop:
    //   - If ConnectToDevice: establish relay session
    //   - If DeviceListRequest: return device list
    //   - Otherwise: route frame to paired device
    // On disconnect: unregister
}
```

Steps:
1. Implement Axum HTTP server with WebSocket upgrade.
2. Implement connection lifecycle: handshake → register → main loop → unregister.
3. Implement frame routing via SessionRouter.
4. Add `/health` endpoint for monitoring.
5. Add TLS support (rustls).

**Acceptance**: Full end-to-end test: Agent on machine A → Connection Node on VPS → Phone on network B → can send commands and receive responses.

---

### NODE-T07: Deployment Artifacts

Steps:
1. Cross-compile: `cargo build --release --target x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl`.
2. Create `deploy/Dockerfile.connection-node`:
   ```dockerfile
   FROM scratch
   COPY target/x86_64-unknown-linux-musl/release/connection-node /
   EXPOSE 443
   ENTRYPOINT ["/connection-node", "run"]
   ```
3. Create `deploy/connection-node.service` (systemd unit).
4. Implement auto Let's Encrypt via `rustls-acme`.
5. Write `docs/self-hosted-guide.md`.

**Acceptance**: `docker run -p 443:443 -v ./config:/etc/mrt mrt-connection-node` works on a fresh VPS. TLS auto-configured.

---

## P2 Tasks (Managed Mode Extensions)

### NODE-T08: ICE Signaling

1. When managed mode is active and a phone connects to an agent:
2. Before establishing relay, attempt ICE negotiation.
3. Forward `IceOffer`, `IceAnswer`, `IceCandidate` messages between phone and agent.
4. If P2P connection established within 3s: send `ConnectToDeviceAck { connection_type: P2P }`, stop relay.
5. If timeout: send `ConnectToDeviceAck { connection_type: RELAY }`, continue relay.

### NODE-T09: STUN/TURN

1. Embed or configure external STUN server.
2. Embed or configure external TURN server (coturn integration).
3. TURN credentials: generate short-lived credentials per session.

### NODE-T10: JWT Auth (Managed Mode)

1. User registration/login API endpoints.
2. JWT issuance and validation.
3. PostgreSQL backend for user data.

## P4 Tasks

### NODE-T11: Push Notification Relay

1. APNs integration: receive push triggers from agents, forward to Apple.
2. FCM integration: same for Android.
3. Agents send push requests via a new `PushTrigger` message type.
4. Node stores device push tokens in DB.
