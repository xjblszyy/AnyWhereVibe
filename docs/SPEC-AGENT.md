# SPEC-AGENT — Desktop Agent

> Language: Rust  
> Dependency: SPEC-PROTO (proto-gen crate)  
> Location: `crates/agent/`  
> Duration: P0 3-4 weeks, P1/P2/P3/P4 incremental

---

## Overview

A Rust daemon that:
1. Manages a Codex (or Claude Code) process locally.
2. Accepts connections from mobile clients (direct LAN or via Connection Node).
3. Translates Protobuf commands ↔ Codex JSON-RPC calls.
4. Provides mock mode for frontend development.

---

## File Structure

```
crates/agent/
├── Cargo.toml
└── src/
    ├── main.rs                   # CLI args, config loading, daemon start
    ├── config.rs                 # TOML config structs + loading
    ├── daemon.rs                 # Tokio runtime, shutdown coordination
    ├── server.rs                 # WebSocket server for client connections
    ├── transport.rs              # Abstraction: direct vs Connection Node
    ├── session.rs                # Session lifecycle, persistence
    ├── permission.rs             # Permission Guard (P3)
    ├── crypto.rs                 # Noise Protocol E2E (P3)
    ├── adapter/
    │   ├── mod.rs                # AgentAdapter trait
    │   ├── codex_appserver.rs    # Codex app-server JSON-RPC adapter
    │   ├── codex_cli.rs          # Codex CLI stdin/stdout fallback adapter
    │   └── mock.rs               # Mock adapter for testing
    ├── codex/
    │   ├── mod.rs
    │   ├── process.rs            # Process spawn, health check, restart
    │   └── rpc.rs                # JSON-RPC client to app-server
    └── push.rs                   # Push notification triggers (P4)
```

---

## Config File

Location: `~/.mrt/agent.toml`

```toml
[server]
listen_addr = "0.0.0.0:9876"
# max_connections = 5

[agent]
# "codex-app-server" | "codex-cli" | "mock"
adapter = "codex-app-server"
# If codex-app-server fails, auto-fallback to codex-cli
auto_fallback = true

[codex]
command = "codex"
args = ["app-server"]
# working_dir = "/home/user/projects"

# Optional: connect to a Connection Node instead of (or in addition to) local server
# [connection_node]
# url = "wss://your-server.com"
# device_id = "my-macbook"
# display_name = "Ming's MacBook"
# auth_token = "mrt_ak_7f3a..."

[permissions]
# first_connect_approval = true        # Show desktop notification on first connection
# allowed_dirs = ["/home/user/projects"]
# blocked_commands = ["rm -rf /"]

[log]
level = "info"                          # trace, debug, info, warn, error
```

---

## P0 Tasks

### AGENT-T01: Project Setup + Config

**Input**: proto-gen crate  
**Output**: Compilable crate, config loading

`Cargo.toml` dependencies:
```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "0.24"
futures-util = "0.3"
prost = "0.13"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
uuid = { version = "1", features = ["v4"] }
dirs = "5"
clap = { version = "4", features = ["derive"] }
proto-gen = { path = "../proto-gen" }

[dev-dependencies]
tokio-test = "0.4"
```

CLI interface:
```
mrt-agent [OPTIONS]

Options:
  -c, --config <PATH>    Config file path [default: ~/.mrt/agent.toml]
  --mock                 Run in mock mode (no Codex process)
  --listen <ADDR>        Override listen address
  --log-level <LEVEL>    Override log level
  -h, --help
```

Steps:
1. Implement `config.rs`: load TOML, merge CLI overrides, apply defaults.
2. Implement `main.rs`: clap CLI → load config → init tracing → start daemon.
3. `daemon.rs`: tokio runtime with graceful shutdown (Ctrl+C / SIGTERM). Use `tokio::select!` with a shutdown channel.

```rust
// daemon.rs sketch
pub struct Daemon {
    config: Config,
    shutdown_tx: watch::Sender<bool>,
    shutdown_rx: watch::Receiver<bool>,
}

impl Daemon {
    pub async fn run(&self) -> Result<()> {
        let adapter = self.create_adapter().await?;
        let session_mgr = SessionManager::new(&self.config)?;
        let server = Server::new(&self.config, adapter, session_mgr);

        tokio::select! {
            r = server.run() => r,
            _ = signal::ctrl_c() => {
                tracing::info!("Shutting down...");
                self.shutdown_tx.send(true)?;
                Ok(())
            }
        }
    }
}
```

**Acceptance**: `cargo run -p agent` starts, logs config, shuts down on Ctrl+C. `cargo run -p agent -- --mock` starts in mock mode.

---

### AGENT-T02: AgentAdapter Trait

**Input**: Proto types  
**Output**: Trait definition + Mock implementation

```rust
// adapter/mod.rs
use proto_gen::*;
use tokio::sync::broadcast;

#[async_trait::async_trait]
pub trait AgentAdapter: Send + Sync + 'static {
    /// Human-readable name: "codex-app-server", "codex-cli", "mock"
    fn name(&self) -> &'static str;

    /// Send a prompt to the AI agent
    async fn send_prompt(&self, session_id: &str, prompt: &str) -> Result<()>;

    /// Respond to a permission approval request
    async fn respond_approval(&self, approval_id: &str, approved: bool) -> Result<()>;

    /// Cancel the current task in a session
    async fn cancel_task(&self, session_id: &str) -> Result<()>;

    /// Get current status of a session
    async fn get_status(&self, session_id: &str) -> Result<TaskStatus>;

    /// Subscribe to events (output chunks, approval requests, status changes)
    fn subscribe(&self) -> broadcast::Receiver<AgentEvent>;

    /// Start the adapter (spawn processes etc.)
    async fn start(&mut self) -> Result<()>;

    /// Stop the adapter gracefully
    async fn stop(&mut self) -> Result<()>;
}
```

**Mock implementation** (`adapter/mock.rs`):
```rust
pub struct MockAdapter {
    event_tx: broadcast::Sender<AgentEvent>,
    prompt_count: AtomicU32,
}

impl AgentAdapter for MockAdapter {
    fn name(&self) -> &'static str { "mock" }

    async fn send_prompt(&self, session_id: &str, prompt: &str) -> Result<()> {
        let count = self.prompt_count.fetch_add(1, Ordering::SeqCst);
        let tx = self.event_tx.clone();
        let sid = session_id.to_string();

        tokio::spawn(async move {
            // Simulate streaming response
            let response = format!("I received your prompt: \"{}\". Let me work on that...", prompt);
            for (i, chunk) in response.chars().collect::<Vec<_>>().chunks(10).enumerate() {
                tokio::time::sleep(Duration::from_millis(200)).await;
                let content: String = chunk.iter().collect();
                let is_last = i == response.len() / 10;
                tx.send(AgentEvent {
                    evt: Some(Evt::CodexOutput(CodexOutput {
                        session_id: sid.clone(),
                        content,
                        is_complete: is_last,
                        output_type: OutputType::AssistantText as i32,
                    })),
                }).ok();
            }

            // Every 3rd prompt, simulate an approval request
            if count % 3 == 2 {
                tokio::time::sleep(Duration::from_secs(1)).await;
                tx.send(AgentEvent {
                    evt: Some(Evt::ApprovalRequest(ApprovalRequest {
                        approval_id: Uuid::new_v4().to_string(),
                        session_id: sid.clone(),
                        description: "Write to file src/main.rs".into(),
                        command: "cat > src/main.rs << 'EOF'\nfn main() { ... }\nEOF".into(),
                        approval_type: ApprovalType::FileWrite as i32,
                    })),
                }).ok();
            }
        });
        Ok(())
    }

    // ... other methods return sensible defaults
}
```

**Acceptance**: MockAdapter compiles and produces realistic streaming output + periodic approval requests.

---

### AGENT-T03: Codex Process Manager

**Input**: Config  
**Output**: `CodexProcessManager` that spawns and monitors `codex app-server`

```rust
// codex/process.rs
pub struct CodexProcessManager {
    config: CodexConfig,
    child: Option<Child>,
    ws_url: Option<String>,
    restart_count: u32,
}

impl CodexProcessManager {
    pub fn new(config: CodexConfig) -> Self;

    /// Spawn codex app-server, parse stdout for WebSocket URL.
    /// Returns the ws:// URL to connect to.
    pub async fn start(&mut self) -> Result<String>;

    /// Send SIGTERM, wait 5s, SIGKILL.
    pub async fn stop(&mut self) -> Result<()>;

    /// Stop + start. Exponential backoff: 1s, 2s, 4s, ..., max 30s.
    pub async fn restart(&mut self) -> Result<String>;

    /// Check if child process is still running.
    pub fn is_running(&self) -> bool;

    /// Monitor loop: check health every 5s, restart if dead.
    pub async fn monitor(&mut self, shutdown: watch::Receiver<bool>) -> Result<()>;
}
```

Stdout parsing: `codex app-server` prints a line like `Listening on ws://127.0.0.1:XXXXX` on startup. Scan stdout line by line for this pattern.

Steps:
1. Implement process spawning with `tokio::process::Command`.
2. Implement stdout line scanning for WebSocket URL (regex: `ws://[\d.]+:\d+`).
3. Implement graceful shutdown (SIGTERM → wait → SIGKILL).
4. Implement restart with exponential backoff.
5. Implement health monitor as a tokio task.
6. Handle edge case: if `codex` binary not found, return clear error.

**Acceptance**: Start agent → codex app-server spawns → kill codex → agent restarts it within backoff period → log shows restart count.

---

### AGENT-T04: JSON-RPC Client to Codex

**Input**: `ws_url` from ProcessManager  
**Output**: `CodexRpcClient` for bidirectional JSON-RPC

```rust
// codex/rpc.rs

/// JSON-RPC 2.0 message structures
#[derive(Serialize)]
struct JsonRpcRequest {
    jsonrpc: &'static str,  // "2.0"
    id: String,
    method: String,
    params: serde_json::Value,
}

#[derive(Deserialize)]
struct JsonRpcResponse {
    id: Option<String>,
    result: Option<serde_json::Value>,
    error: Option<JsonRpcError>,
}

#[derive(Deserialize)]
struct JsonRpcError {
    code: i32,
    message: String,
}

pub struct CodexRpcClient {
    ws_write: SplitSink<WebSocketStream<...>, Message>,
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<serde_json::Value>>>>,
    event_tx: broadcast::Sender<CodexEvent>,
}

pub enum CodexEvent {
    Output { session_id: String, content: String, is_complete: bool },
    ApprovalRequest { id: String, session_id: String, description: String, command: String },
    StatusChange { session_id: String, status: String },
}

impl CodexRpcClient {
    /// Connect to codex app-server WebSocket.
    pub async fn connect(url: &str) -> Result<Self>;

    /// Send a JSON-RPC request and wait for response.
    async fn call(&self, method: &str, params: serde_json::Value) -> Result<serde_json::Value>;

    /// Send prompt. Streaming output arrives via event_tx.
    pub async fn send_prompt(&self, session_id: &str, prompt: &str) -> Result<()>;

    pub async fn respond_approval(&self, request_id: &str, approved: bool) -> Result<()>;

    pub async fn cancel(&self, session_id: &str) -> Result<()>;

    /// Subscribe to Codex events.
    pub fn subscribe(&self) -> broadcast::Receiver<CodexEvent>;

    /// Internal: read loop that processes incoming WebSocket messages.
    /// Matches responses to pending requests, emits notifications as events.
    async fn read_loop(
        ws_read: SplitStream<WebSocketStream<...>>,
        pending: Arc<Mutex<HashMap<String, oneshot::Sender<serde_json::Value>>>>,
        event_tx: broadcast::Sender<CodexEvent>,
    );
}
```

Steps:
1. Implement WebSocket connection using `tokio-tungstenite`.
2. Implement JSON-RPC request/response matching: each request has a UUID id, store `oneshot::Sender` in pending map, read loop matches responses by id.
3. Implement notification handling: Codex sends JSON-RPC notifications (no id) for streaming output and approval requests. Parse and emit as `CodexEvent`.
4. Implement auto-reconnect: if WebSocket drops, reconnect using ProcessManager's `ws_url`.
5. Test with real `codex app-server` if possible, otherwise write unit tests with mock WebSocket server.

**Acceptance**: Can send a prompt, receive streaming chunks, handle approval requests. Reconnects after disconnect.

---

### AGENT-T05: CodexAppServerAdapter

**Input**: ProcessManager + RpcClient  
**Output**: `AgentAdapter` implementation that wires everything together

```rust
// adapter/codex_appserver.rs
pub struct CodexAppServerAdapter {
    process: CodexProcessManager,
    rpc: Option<CodexRpcClient>,
    event_tx: broadcast::Sender<AgentEvent>,
}

impl AgentAdapter for CodexAppServerAdapter {
    fn name(&self) -> &'static str { "codex-app-server" }

    async fn start(&mut self) -> Result<()> {
        let ws_url = self.process.start().await?;
        self.rpc = Some(CodexRpcClient::connect(&ws_url).await?);
        // Start monitoring process health in background
        // Start forwarding CodexEvents → AgentEvents
        Ok(())
    }

    async fn send_prompt(&self, session_id: &str, prompt: &str) -> Result<()> {
        self.rpc.as_ref().ok_or(Error::NotStarted)?.send_prompt(session_id, prompt).await
    }

    // ... other methods delegate to self.rpc
}
```

Steps:
1. Implement `CodexAppServerAdapter`.
2. Implement event forwarding: `CodexEvent` → map to `AgentEvent` → broadcast.
3. Handle RPC connection loss: if WebSocket drops, attempt reconnect to same URL first, then restart process.

**Acceptance**: Full pipeline works: start adapter → send prompt → receive streamed AgentEvents.

---

### AGENT-T06: CodexCliAdapter (Fallback)

**Input**: AgentAdapter trait  
**Output**: Fallback adapter that wraps `codex` CLI via stdin/stdout

```rust
// adapter/codex_cli.rs
pub struct CodexCliAdapter {
    config: CodexConfig,
    child: Option<Child>,
    stdin: Option<ChildStdin>,
    event_tx: broadcast::Sender<AgentEvent>,
}
```

This adapter:
1. Spawns `codex` (not `codex app-server`) as a child process.
2. Writes user prompts to stdin.
3. Reads stdout line by line, parses output, emits as `AgentEvent::CodexOutput`.
4. Detects approval prompts in stdout (pattern matching), emits `ApprovalRequest`.
5. Writes "y" or "n" to stdin for approval responses.

Steps:
1. Implement process spawn with stdin/stdout pipes.
2. Implement stdout parser: detect Codex output patterns.
3. Implement approval detection: Codex prints permission prompts to stdout.
4. Handle process lifecycle.

**Acceptance**: `adapter = "codex-cli"` in config → agent uses CLI wrapping → basic prompts and approvals work.

---

### AGENT-T07: Auto-Fallback Logic

In `daemon.rs`, when creating the adapter:

```rust
async fn create_adapter(&self) -> Result<Box<dyn AgentAdapter>> {
    match self.config.agent.adapter.as_str() {
        "mock" => Ok(Box::new(MockAdapter::new())),
        "codex-cli" => Ok(Box::new(CodexCliAdapter::new(self.config.codex.clone()))),
        "codex-app-server" | _ => {
            let mut adapter = CodexAppServerAdapter::new(self.config.codex.clone());
            match adapter.start().await {
                Ok(()) => Ok(Box::new(adapter)),
                Err(e) if self.config.agent.auto_fallback => {
                    tracing::warn!("codex app-server failed: {}. Falling back to codex-cli.", e);
                    let mut cli = CodexCliAdapter::new(self.config.codex.clone());
                    cli.start().await?;
                    Ok(Box::new(cli))
                }
                Err(e) => Err(e),
            }
        }
    }
}
```

**Acceptance**: If `codex app-server` binary doesn't exist, agent auto-falls back to `codex` CLI with a warning log.

---

### AGENT-T08: WebSocket Server

**Input**: AgentAdapter + SessionManager  
**Output**: Server accepts mobile client connections, translates Protobuf ↔ adapter calls

```rust
// server.rs
pub struct Server {
    config: ServerConfig,
    adapter: Arc<Box<dyn AgentAdapter>>,
    sessions: Arc<Mutex<SessionManager>>,
    clients: Arc<Mutex<HashMap<String, ClientConnection>>>,
}

struct ClientConnection {
    device_id: String,
    client_type: ClientType,
    ws_tx: mpsc::Sender<Vec<u8>>,  // send Protobuf-encoded Envelope
}

impl Server {
    pub async fn run(&self) -> Result<()>;

    /// Handle a new WebSocket connection
    async fn handle_connection(&self, ws: WebSocketStream<...>);

    /// Process incoming Envelope from client
    async fn handle_envelope(&self, client_id: &str, envelope: Envelope) -> Result<Option<Envelope>>;

    /// Forward AgentEvents to all connected clients
    async fn event_broadcast_loop(&self);
}
```

Message handling dispatch:

```rust
async fn handle_envelope(&self, client_id: &str, env: Envelope) -> Result<Option<Envelope>> {
    match env.payload {
        Some(Payload::Handshake(hs)) => {
            // Validate protocol_version
            if hs.protocol_version != CURRENT_PROTOCOL_VERSION {
                return Ok(Some(make_error("VERSION_MISMATCH", "Please update", true)));
            }
            // Send back AgentInfo
            Ok(Some(make_agent_info(&self.adapter)))
        }
        Some(Payload::Command(cmd)) => {
            match cmd.cmd {
                Some(Cmd::SendPrompt(sp)) => {
                    self.adapter.send_prompt(&sp.session_id, &sp.prompt).await?;
                    Ok(None) // Response comes via event stream
                }
                Some(Cmd::ApprovalResponse(ar)) => {
                    self.adapter.respond_approval(&ar.approval_id, ar.approved).await?;
                    Ok(None)
                }
                Some(Cmd::CancelTask(ct)) => {
                    self.adapter.cancel_task(&ct.session_id).await?;
                    Ok(None)
                }
                Some(Cmd::GetStatus(gs)) => {
                    let status = self.adapter.get_status(&gs.session_id).await?;
                    Ok(Some(make_status_update(&gs.session_id, status)))
                }
                _ => Ok(None)
            }
        }
        Some(Payload::Session(sc)) => self.handle_session_control(sc).await,
        Some(Payload::FileOp(fo)) => self.handle_file_op(fo).await,
        Some(Payload::GitOp(go)) => self.handle_git_op(go).await,
        Some(Payload::Heartbeat(_)) => Ok(Some(make_heartbeat())),
        _ => Ok(None)
    }
}
```

Steps:
1. Implement WebSocket listener with `tokio-tungstenite`.
2. Implement Protobuf encode/decode on binary frames (with 4-byte length prefix).
3. Implement handshake validation.
4. Implement command dispatch as above.
5. Implement event broadcast: subscribe to adapter events, forward to all connected clients.
6. Implement client tracking: add/remove from `clients` map on connect/disconnect.
7. Implement heartbeat: respond to pings, detect dead connections (45s timeout).

**Acceptance**: Start agent → connect with `websocat` or custom test client → send binary Protobuf Envelope → receive response.

---

### AGENT-T09: Session Manager

```rust
// session.rs
pub struct SessionManager {
    sessions: HashMap<String, Session>,
    storage_path: PathBuf,  // ~/.mrt/sessions.json
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Session {
    pub id: String,
    pub name: String,
    pub status: i32,        // TaskStatus enum value
    pub working_dir: String,
    pub created_at_ms: u64,
    pub last_active_ms: u64,
}

impl SessionManager {
    pub fn new(storage_path: &Path) -> Result<Self>;  // Load from disk if exists
    pub fn create(&mut self, name: &str, working_dir: &str) -> Result<Session>;
    pub fn get(&self, id: &str) -> Option<&Session>;
    pub fn list(&self) -> Vec<SessionInfo>;            // Proto type
    pub fn update_status(&mut self, id: &str, status: TaskStatus);
    pub fn rename(&mut self, id: &str, new_name: &str) -> Result<()>;
    pub fn close(&mut self, id: &str) -> Result<()>;
    pub fn save(&self) -> Result<()>;                   // JSON to disk
}
```

Steps:
1. Implement CRUD operations.
2. Implement JSON persistence to `~/.mrt/sessions.json`.
3. Auto-save on every mutation.
4. Load on startup.
5. Wire SessionControl messages in server.

**Acceptance**: Create sessions → restart agent → sessions still there.

---

### AGENT-T10: Transport Abstraction (Connection Node Mode)

```rust
// transport.rs
pub enum Transport {
    /// Direct WebSocket server on local network
    Local { listener: TcpListener },
    /// Connect to remote Connection Node
    Remote { node_url: String, device_id: String, auth_token: String },
}

impl Transport {
    pub async fn from_config(config: &Config) -> Result<Self>;

    /// Start accepting connections (local) or register with node (remote)
    pub async fn run(
        &self,
        on_connection: impl Fn(WebSocketStream<...>) + Send + Sync,
    ) -> Result<()>;
}
```

For P0, only `Local` mode is implemented. `Remote` mode is stubbed and implemented in P1.

Steps:
1. Define the `Transport` enum.
2. Implement `Local` variant: bind TCP, accept WebSocket upgrades.
3. Stub `Remote` variant: return error "Connection Node not yet supported".
4. Wire into `Server::run()`.

**Acceptance**: Agent works in local mode. Config with `connection_node` section logs "not yet supported".

---

## P1 Tasks (Connection Node Mode)

### AGENT-T11: Remote Transport

Implement the `Remote` variant of `Transport`:
1. Connect to Connection Node via WebSocket.
2. Send `DeviceRegister` with device_id, auth_token, display_name.
3. Wait for `DeviceRegisterAck`.
4. When Connection Node forwards a client connection (incoming `ConnectToDevice`), create a virtual WebSocket channel and pass to the server's `handle_connection`.
5. Auto-reconnect on disconnect.

## P2 Tasks (NAT Punch-Through)

### AGENT-T12: ICE Integration

1. Add `webrtc-rs` dependency (ICE module only, not full WebRTC).
2. When managed Connection Node signals ICE negotiation, gather candidates.
3. Exchange candidates via Connection Node signaling channel.
4. Attempt P2P connectivity.
5. On success: switch data channel to P2P, stop using Connection Node relay.
6. On failure (3s timeout): continue using Connection Node relay.

## P3 Tasks (Security)

### AGENT-T13: Noise Protocol E2E

1. Add `snow = "0.9"` dependency.
2. Generate Ed25519 keypair on first run, store in OS keyring.
3. On client connection: perform Noise IK handshake before any business messages.
4. All subsequent Envelope messages encrypted/decrypted via Noise session.

### AGENT-T14: QR Code Pairing

1. On `--pair` flag: generate temporary pairing payload (public key + connection info), encode as QR.
2. Print QR to terminal using `qr2term` crate.
3. Wait for client to scan and complete handshake.
4. Store paired device public key in `~/.mrt/paired_devices.json`.

### AGENT-T15: Permission Guard

1. Load `[permissions]` from config.
2. Before forwarding any command to Codex, check against rules.
3. On first connection from unknown device: show desktop notification (via `notify-rust` crate), wait for user approval.

## P4 Tasks (Experience)

### AGENT-T16: Git Operations Handler

1. Add `git2 = "0.19"` dependency.
2. Implement all `GitOperation` handlers using libgit2 bindings.
3. Scope all operations to session's `working_dir`.

### AGENT-T17: File Operations Handler

1. Implement `ListDir`: directory listing with file metadata.
2. Implement `ReadFile`: read file content (cap at 1MB per read).
3. Implement `WriteFile`: write file with path validation (must be within session's working_dir).

### AGENT-T18: Push Notification Triggers

1. When `ApprovalRequest` is emitted and no client is connected: send push trigger through Connection Node.
2. When task completes: send push trigger.
3. Push payload: `{ type: "approval_request" | "task_complete" | "task_error", session_id, message }`.
4. Connection Node forwards to APNs/FCM (managed mode only).
