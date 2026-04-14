# AnyWhereVibe A-Slice Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable AnyWhereVibe slice: complete protobuf contract, a Rust desktop agent running in `--mock` mode over local WebSocket, and an iOS app that can connect, manage sessions, send prompts, render streaming output, and handle inline approvals.

**Architecture:** Implement the contract first in `proto/mrt.proto`, generate Rust types through `crates/proto-gen`, then build the agent around a local binary WebSocket transport with a stable `AgentAdapter` boundary and a fully working `MockAdapter`. On iOS, create a dark GitHub-style SwiftUI app that uses the same protobuf contract and connects directly to the local agent on LAN.

**Tech Stack:** Rust workspace (`cargo`, `tokio`, `tokio-tungstenite`, `prost`, `serde`, `clap`, `tracing`), Protobuf (`protoc`, `prost-build`, `swift-protobuf`), Swift / SwiftUI / XCTest, optional `Starscream` if native `URLSessionWebSocketTask` proves insufficient.

---

## Planned File Map

### Repository Root

- Create: `Cargo.toml`
- Create: `Cargo.lock`
- Modify: `.gitignore`
- Create: `scripts/proto-gen-swift.sh`
- Create: `scripts/proto-gen-kotlin.sh`
- Create: `scripts/dev-agent-mock.sh`

### Protocol

- Create: `proto/mrt.proto`
- Create: `crates/proto-gen/Cargo.toml`
- Create: `crates/proto-gen/build.rs`
- Create: `crates/proto-gen/src/lib.rs`
- Create: `crates/proto-gen/tests/envelope_roundtrip.rs`

### Desktop Agent

- Create: `crates/agent/Cargo.toml`
- Create: `crates/agent/src/lib.rs`
- Create: `crates/agent/src/error.rs`
- Create: `crates/agent/src/config.rs`
- Create: `crates/agent/src/session.rs`
- Create: `crates/agent/src/wire.rs`
- Create: `crates/agent/src/transport.rs`
- Create: `crates/agent/src/server.rs`
- Create: `crates/agent/src/daemon.rs`
- Create: `crates/agent/src/main.rs`
- Create: `crates/agent/src/test_support.rs`
- Create: `crates/agent/src/adapter/mod.rs`
- Create: `crates/agent/src/adapter/mock.rs`
- Create: `crates/agent/src/adapter/codex_appserver.rs`
- Create: `crates/agent/src/adapter/codex_cli.rs`
- Create: `crates/agent/src/codex/mod.rs`
- Create: `crates/agent/src/codex/process.rs`
- Create: `crates/agent/src/codex/rpc.rs`
- Create: `crates/agent/tests/config_defaults.rs`
- Create: `crates/agent/tests/session_store.rs`
- Create: `crates/agent/tests/wire_codec.rs`
- Create: `crates/agent/tests/mock_adapter.rs`
- Create: `crates/agent/tests/server_handshake.rs`
- Create: `crates/agent/tests/server_sessions.rs`
- Create: `crates/agent/tests/heartbeat.rs`

### iOS App

- Create: `ios/project.yml`
- Create: `ios/MRT.xcodeproj/` and the default project files needed for scheme `MRT`
- Create: `ios/MRT/Info.plist`
- Create: `ios/MRT/MRTApp.swift`
- Create: `ios/MRT/ContentView.swift`
- Create: `ios/MRT/DesignSystem/Theme.swift`
- Create: `ios/MRT/DesignSystem/Components/GHCard.swift`
- Create: `ios/MRT/DesignSystem/Components/GHButton.swift`
- Create: `ios/MRT/DesignSystem/Components/GHBadge.swift`
- Create: `ios/MRT/DesignSystem/Components/GHInput.swift`
- Create: `ios/MRT/DesignSystem/Components/GHBanner.swift`
- Create: `ios/MRT/DesignSystem/Components/GHCodeBlock.swift`
- Create: `ios/MRT/DesignSystem/Components/GHList.swift`
- Create: `ios/MRT/DesignSystem/Components/GHDiffView.swift`
- Create: `ios/MRT/DesignSystem/Components/GHStatusDot.swift`
- Create: `ios/MRT/DesignSystem/Components/GHTabBar.swift`
- Create: `ios/MRT/Core/Proto/Mrt.pb.swift`
- Create: `ios/MRT/Core/Network/ProtobufCodec.swift`
- Create: `ios/MRT/Core/Network/WebSocketClient.swift`
- Create: `ios/MRT/Core/Network/ConnectionManager.swift`
- Create: `ios/MRT/Core/Network/MessageDispatcher.swift`
- Create: `ios/MRT/Core/Models/ChatMessage.swift`
- Create: `ios/MRT/Core/Models/SessionModel.swift`
- Create: `ios/MRT/Core/Storage/Preferences.swift`
- Create: `ios/MRT/Features/Chat/ChatView.swift`
- Create: `ios/MRT/Features/Chat/ThreadMessageView.swift`
- Create: `ios/MRT/Features/Chat/StreamingTextView.swift`
- Create: `ios/MRT/Features/Chat/ApprovalBannerView.swift`
- Create: `ios/MRT/Features/Chat/ConnectionStatusBar.swift`
- Create: `ios/MRT/Features/Chat/PromptInputBar.swift`
- Create: `ios/MRT/Features/Chat/ChatViewModel.swift`
- Create: `ios/MRT/Features/Sessions/SessionSidebarView.swift`
- Create: `ios/MRT/Features/Sessions/SessionsScreen.swift`
- Create: `ios/MRT/Features/Sessions/SessionRowView.swift`
- Create: `ios/MRT/Features/Sessions/SessionViewModel.swift`
- Create: `ios/MRT/Features/Settings/SettingsView.swift`
- Create: `ios/MRT/Features/Placeholders/GitPlaceholderView.swift`
- Create: `ios/MRT/Features/Placeholders/FilesPlaceholderView.swift`
- Create: `ios/MRTTests/Network/ProtobufCodecTests.swift`
- Create: `ios/MRTTests/Network/MessageDispatcherTests.swift`
- Create: `ios/MRTTests/Network/ConnectionManagerTests.swift`
- Create: `ios/MRTTests/Features/ChatViewModelTests.swift`

### Verification Docs

- Modify: `docs/superpowers/specs/2026-04-14-anywherevibe-a-slice-design.md` only if implementation reveals a spec bug
- Create: `docs/superpowers/plans/2026-04-14-anywherevibe-a-slice.md`

## Execution Rules

- Toolchain prerequisites:
  - `brew install protobuf`
  - `brew install swift-protobuf`
  - `brew install xcodegen`
- Use `@test-driven-development` before changing code for each task.
- Use `@systematic-debugging` if any test or build step fails unexpectedly.
- Use `@verification-before-completion` before claiming the full slice works.
- Never add `Connection Node`, Android, or watchOS code in this plan.
- Do not make `codex_appserver` or `codex_cli` operational; keep them as explicit placeholders.
- Keep `scripts/proto-gen-kotlin.sh` as a non-executed helper only; do not create or validate an Android source tree in this slice.

### Task 1: Bootstrap The Workspace And Tooling

**Files:**
- Create: `Cargo.toml`
- Create: `scripts/proto-gen-swift.sh`
- Create: `scripts/proto-gen-kotlin.sh`
- Create: `scripts/dev-agent-mock.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Write the failing bootstrap check**

Create a shell verification note in the task branch by attempting workspace discovery before files exist:

```bash
test -f Cargo.toml
```

Expected: FAIL because `Cargo.toml` does not exist yet.

- [ ] **Step 2: Create the root workspace and helper scripts**

Add `Cargo.toml` with:

```toml
[workspace]
members = []
resolver = "2"
```

Add scripts:

```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p ios/MRT/Core/Proto
protoc -I proto --swift_out=ios/MRT/Core/Proto proto/mrt.proto
```

```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/generated/kotlin-proto
protoc -I proto --kotlin_out=build/generated/kotlin-proto proto/mrt.proto
```

```bash
#!/usr/bin/env bash
set -euo pipefail
cargo run -p agent -- --mock --listen 0.0.0.0:9876
```

Update `.gitignore` to keep at least:

```gitignore
.superpowers/
target/
DerivedData/
*.xcuserstate
```

Mark the helper scripts executable:

```bash
chmod +x scripts/proto-gen-swift.sh scripts/proto-gen-kotlin.sh scripts/dev-agent-mock.sh
```

- [ ] **Step 3: Verify the workspace bootstrap passes**

Run:

```bash
test -f Cargo.toml
rg -n 'members = \[\]' Cargo.toml
bash -n scripts/proto-gen-swift.sh
bash -n scripts/proto-gen-kotlin.sh
bash -n scripts/dev-agent-mock.sh
```

Expected: all commands succeed.

- [ ] **Step 4: Commit the bootstrap**

Run:

```bash
git add Cargo.toml .gitignore scripts/proto-gen-swift.sh scripts/proto-gen-kotlin.sh scripts/dev-agent-mock.sh
git commit -m "chore: bootstrap workspace tooling"
```

### Task 2: Author The Protocol Contract And Rust Codegen

**Files:**
- Create: `proto/mrt.proto`
- Create: `crates/proto-gen/Cargo.toml`
- Create: `crates/proto-gen/build.rs`
- Create: `crates/proto-gen/src/lib.rs`
- Create: `crates/proto-gen/tests/envelope_roundtrip.rs`

- [ ] **Step 1: Write the failing round-trip test**

Create `crates/proto-gen/tests/envelope_roundtrip.rs`:

```rust
use prost::Message;
use proto_gen::{Envelope, Handshake, envelope::Payload, ClientType};

#[test]
fn handshake_round_trip_preserves_protocol_and_device() {
    let envelope = Envelope {
        protocol_version: 1,
        request_id: "req-1".into(),
        timestamp_ms: 42,
        payload: Some(Payload::Handshake(Handshake {
            protocol_version: 1,
            client_type: ClientType::PhoneIos as i32,
            client_version: "1.0.0".into(),
            device_id: "iphone-1".into(),
        })),
    };

    let bytes = envelope.encode_to_vec();
    let decoded = Envelope::decode(bytes.as_slice()).unwrap();

    assert_eq!(decoded.protocol_version, 1);
    let handshake = match decoded.payload.unwrap() {
        Payload::Handshake(value) => value,
        other => panic!("unexpected payload: {other:?}"),
    };
    assert_eq!(handshake.device_id, "iphone-1");
}
```

Run:

```bash
cargo test -p proto-gen handshake_round_trip_preserves_protocol_and_device -- --exact
```

Expected: FAIL because the crate and generated types do not exist yet.

- [ ] **Step 2: Copy the protobuf contract exactly from the source spec**

Create `proto/mrt.proto` by copying the full `PROTO-T01` message set from `docs/SPEC-PROTO.md` without deleting later-phase messages.

Critical requirement snippets that must appear exactly:

```protobuf
message Envelope {
  uint32 protocol_version = 1;
  string request_id = 2;
  uint64 timestamp_ms = 3;
  oneof payload {
    Handshake handshake = 10;
    AgentCommand command = 11;
    AgentEvent event = 12;
    SessionControl session = 13;
    FileOperation file_op = 14;
    GitOperation git_op = 15;
    FileResult file_result = 16;
    GitResult git_result = 17;
    Heartbeat heartbeat = 20;
    DeviceRegister device_register = 30;
    DeviceRegisterAck device_register_ack = 31;
    ConnectToDevice connect_to_device = 32;
    ConnectToDeviceAck connect_to_device_ack = 33;
    DeviceListRequest device_list_request = 34;
    DeviceListResponse device_list_response = 35;
    IceCandidate ice_candidate = 40;
    IceOffer ice_offer = 41;
    IceAnswer ice_answer = 42;
  }
}
```

- [ ] **Step 3: Create the Rust codegen crate**

Add `crates/proto-gen/Cargo.toml`:

```toml
[package]
name = "proto-gen"
version = "0.1.0"
edition = "2021"
build = "build.rs"

[dependencies]
prost = "0.13"
prost-types = "0.13"

[build-dependencies]
prost-build = "0.13"
```

Add `crates/proto-gen/build.rs`:

```rust
fn main() {
    prost_build::compile_protos(&["../../proto/mrt.proto"], &["../../proto/"]).unwrap();
}
```

Add `crates/proto-gen/src/lib.rs`:

```rust
include!(concat!(env!("OUT_DIR"), "/mrt.rs"));
```

Update the root `Cargo.toml` to:

```toml
[workspace]
members = ["crates/proto-gen"]
resolver = "2"
```

- [ ] **Step 4: Run the round-trip test and full proto-gen suite**

Run:

```bash
cargo test -p proto-gen handshake_round_trip_preserves_protocol_and_device -- --exact
cargo test -p proto-gen
```

Expected: PASS.

If `Cargo.lock` is created by the first successful Cargo invocation, stage it with this task's commit.

- [ ] **Step 5: Commit the protocol layer**

Run:

```bash
git add Cargo.toml proto/mrt.proto crates/proto-gen/Cargo.toml crates/proto-gen/build.rs crates/proto-gen/src/lib.rs crates/proto-gen/tests/envelope_roundtrip.rs
git commit -m "feat: add protobuf contract and rust codegen"
```

### Task 3: Build Agent Foundations For Config, Sessions, And Wire Framing

**Files:**
- Create: `crates/agent/Cargo.toml`
- Create: `crates/agent/src/lib.rs`
- Create: `crates/agent/src/error.rs`
- Create: `crates/agent/src/config.rs`
- Create: `crates/agent/src/session.rs`
- Create: `crates/agent/src/wire.rs`
- Create: `crates/agent/tests/config_defaults.rs`
- Create: `crates/agent/tests/session_store.rs`
- Create: `crates/agent/tests/wire_codec.rs`

- [ ] **Step 1: Write the failing foundational tests**

Create `crates/agent/tests/config_defaults.rs`:

```rust
use agent::config::Config;

#[test]
fn config_defaults_to_local_mock_friendly_values() {
    let config = Config::default();
    assert_eq!(config.server.listen_addr, "0.0.0.0:9876");
    assert_eq!(config.agent.adapter, "codex-app-server");
    assert!(config.agent.auto_fallback);
    assert!(config.storage.sessions_path.ends_with(".mrt/sessions.json"));
}
```

Create `crates/agent/tests/session_store.rs`:

```rust
use agent::session::SessionManager;
use proto_gen::TaskStatus;
use tempfile::tempdir;

#[test]
fn session_manager_persists_sessions_to_disk() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("sessions.json");
    let mut manager = SessionManager::new(&path).unwrap();

    let session = manager.create("Main", "/tmp").unwrap();
    manager.update_status(&session.id, TaskStatus::Running);

    let reloaded = SessionManager::new(&path).unwrap();
    assert_eq!(reloaded.list().len(), 1);
    let loaded = reloaded.get(&session.id).unwrap();
    assert!(loaded.created_at_ms > 0);
    assert!(loaded.last_active_ms >= loaded.created_at_ms);
}
```

Create `crates/agent/tests/wire_codec.rs`:

```rust
use agent::wire::{decode_ws_binary_message, encode_ws_binary_message};
use proto_gen::{Envelope, Handshake, envelope::Payload, ClientType};

#[test]
fn wire_codec_round_trips_single_envelope_binary_message() {
    let envelope = Envelope {
        protocol_version: 1,
        request_id: "req-1".into(),
        timestamp_ms: 1,
        payload: Some(Payload::Handshake(Handshake {
            protocol_version: 1,
            client_type: ClientType::PhoneIos as i32,
            client_version: "1.0.0".into(),
            device_id: "device".into(),
        })),
    };

    let bytes = encode_ws_binary_message(&envelope).unwrap();
    let decoded = decode_ws_binary_message(&bytes).unwrap();
    assert_eq!(decoded.request_id, "req-1");
}
```

Run:

```bash
cargo test -p agent --test config_defaults
```

Expected: FAIL because the crate does not exist yet.

- [ ] **Step 2: Create the agent crate and foundations**

Add `crates/agent/Cargo.toml` with at least:

```toml
[package]
name = "agent"
version = "0.1.0"
edition = "2021"

[dependencies]
anyhow = "1"
async-trait = "0.1"
clap = { version = "4", features = ["derive"] }
dirs = "5"
futures-util = "0.3"
prost = "0.13"
proto-gen = { path = "../proto-gen" }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tempfile = "3"
tokio = { version = "1", features = ["full", "test-util"] }
tokio-tungstenite = "0.24"
toml = "0.8"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
uuid = { version = "1", features = ["v4"] }

[dev-dependencies]
tempfile = "3"
tokio-test = "0.4"
```

Add `crates/agent/src/lib.rs`:

```rust
pub mod config;
pub mod error;
pub mod session;
pub mod wire;
```

Implement:

Update the root `Cargo.toml` to:

```toml
[workspace]
members = ["crates/proto-gen", "crates/agent"]
resolver = "2"
```

Then implement:

```rust
// crates/agent/src/config.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub agent: AgentConfig,
    pub codex: CodexConfig,
    pub storage: StorageConfig,
    pub log: LogConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: ServerConfig { listen_addr: "0.0.0.0:9876".into() },
            agent: AgentConfig { adapter: "codex-app-server".into(), auto_fallback: true },
            codex: CodexConfig { command: "codex".into(), args: vec!["app-server".into()] },
            storage: StorageConfig::default(),
            log: LogConfig { level: "info".into() },
        }
    }
}
```

```rust
// crates/agent/src/session.rs
pub struct SessionManager {
    sessions: HashMap<String, Session>,
    storage_path: PathBuf,
}
```

The persisted `Session` model must include:

- `created_at_ms: u64`
- `last_active_ms: u64`

```rust
// crates/agent/src/wire.rs
pub fn encode_ws_binary_message(envelope: &Envelope) -> anyhow::Result<Vec<u8>>;
pub fn decode_ws_binary_message(bytes: &[u8]) -> anyhow::Result<Envelope>;
```

The wire codec must enforce:

- exactly one envelope per WebSocket binary message
- first 4 bytes are the big-endian payload length
- length must equal the remaining bytes exactly

The session layer must enforce:

- default storage directory `~/.mrt/`
- default storage file `~/.mrt/sessions.json`
- create the parent directory on startup if missing
- atomic full-file writes on every mutation by writing a temp file and renaming it
- corrupted `sessions.json` is a startup error, not an auto-reset

- [ ] **Step 3: Run the foundational tests**

Run:

```bash
cargo test -p agent --test config_defaults
cargo test -p agent --test session_store
cargo test -p agent --test wire_codec
```

Expected: PASS.

- [ ] **Step 4: Commit the agent foundations**

Run:

```bash
git add Cargo.toml crates/agent/Cargo.toml crates/agent/src/lib.rs crates/agent/src/error.rs crates/agent/src/config.rs crates/agent/src/session.rs crates/agent/src/wire.rs crates/agent/tests/config_defaults.rs crates/agent/tests/session_store.rs crates/agent/tests/wire_codec.rs
git commit -m "feat: add agent config session and wire foundations"
```

### Task 4: Implement The Agent Adapter Layer And Mock Behavior

**Files:**
- Create: `crates/agent/src/adapter/mod.rs`
- Create: `crates/agent/src/adapter/mock.rs`
- Create: `crates/agent/src/adapter/codex_appserver.rs`
- Create: `crates/agent/src/adapter/codex_cli.rs`
- Create: `crates/agent/src/codex/mod.rs`
- Create: `crates/agent/src/codex/process.rs`
- Create: `crates/agent/src/codex/rpc.rs`
- Create: `crates/agent/tests/mock_adapter.rs`

- [ ] **Step 1: Write the failing mock adapter test**

Create `crates/agent/tests/mock_adapter.rs`:

```rust
use agent::adapter::{AgentAdapter, MockAdapter};
use proto_gen::agent_event::Evt;
use tokio::time::{timeout, Duration};

#[tokio::test]
async fn mock_adapter_streams_output_and_requests_approval_every_third_prompt() {
    let mut adapter = MockAdapter::new();
    adapter.start().await.unwrap();
    let mut rx = adapter.subscribe();

    adapter.send_prompt("session-1", "first").await.unwrap();
    adapter.send_prompt("session-1", "second").await.unwrap();
    adapter.send_prompt("session-1", "third").await.unwrap();

    let mut saw_output = false;
    let mut saw_approval = false;
    for _ in 0..20 {
        let event = timeout(Duration::from_secs(2), rx.recv()).await.unwrap().unwrap();
        match event.evt {
            Some(Evt::CodexOutput(_)) => saw_output = true,
            Some(Evt::ApprovalRequest(_)) => saw_approval = true,
            _ => {}
        }
        if saw_output && saw_approval {
            break;
        }
    }

    assert!(saw_output);
    assert!(saw_approval);
}
```

Run:

```bash
cargo test -p agent --test mock_adapter
```

Expected: FAIL because the adapter layer does not exist yet.

- [ ] **Step 2: Implement the adapter trait and mock adapter**

Create `crates/agent/src/adapter/mod.rs`:

```rust
#[async_trait::async_trait]
pub trait AgentAdapter: Send + Sync + 'static {
    fn name(&self) -> &'static str;
    async fn send_prompt(&self, session_id: &str, prompt: &str) -> anyhow::Result<()>;
    async fn respond_approval(&self, approval_id: &str, approved: bool) -> anyhow::Result<()>;
    async fn cancel_task(&self, session_id: &str) -> anyhow::Result<()>;
    async fn get_status(&self, session_id: &str) -> anyhow::Result<i32>;
    fn subscribe(&self) -> tokio::sync::broadcast::Receiver<proto_gen::AgentEvent>;
    async fn start(&mut self) -> anyhow::Result<()>;
    async fn stop(&mut self) -> anyhow::Result<()>;
}
```

Create `MockAdapter` so it:

- emits `TaskStatusUpdate` with `RUNNING` before output
- emits output in small chunks with short delays
- emits an `ApprovalRequest` on every third prompt after two output chunks
- returns to `COMPLETED` and then `IDLE`

- [ ] **Step 3: Add explicit placeholders for real Codex integration**

Implement `codex_appserver.rs`, `codex_cli.rs`, `codex/process.rs`, and `codex/rpc.rs` as compile-safe placeholders:

```rust
pub async fn start(&mut self) -> anyhow::Result<()> {
    anyhow::bail!("codex app-server integration is not implemented in the A-slice")
}
```

The placeholder modules must exist so later phases do not need directory surgery.

- [ ] **Step 4: Run the adapter tests**

Run:

```bash
cargo test -p agent --test mock_adapter
cargo test -p agent mock_adapter_streams_output_and_requests_approval_every_third_prompt -- --exact
```

Expected: PASS.

- [ ] **Step 5: Commit the adapter layer**

Run:

```bash
git add crates/agent/src/adapter/mod.rs crates/agent/src/adapter/mock.rs crates/agent/src/adapter/codex_appserver.rs crates/agent/src/adapter/codex_cli.rs crates/agent/src/codex/mod.rs crates/agent/src/codex/process.rs crates/agent/src/codex/rpc.rs crates/agent/tests/mock_adapter.rs
git commit -m "feat: add agent adapters and mock backend"
```

### Task 5: Build The Agent Server, Transport, And CLI Integration

**Files:**
- Create: `crates/agent/src/transport.rs`
- Create: `crates/agent/src/server.rs`
- Create: `crates/agent/src/daemon.rs`
- Create: `crates/agent/src/main.rs`
- Create: `crates/agent/src/test_support.rs`
- Create: `crates/agent/tests/server_handshake.rs`
- Create: `crates/agent/tests/server_sessions.rs`
- Create: `crates/agent/tests/heartbeat.rs`

- [ ] **Step 1: Write the failing server integration tests**

Create `crates/agent/tests/server_handshake.rs`:

```rust
use futures_util::{SinkExt, StreamExt};
use proto_gen::ErrorEvent;
use tokio_tungstenite::connect_async;

#[tokio::test]
async fn server_rejects_non_handshake_first_message() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    socket
        .send(tokio_tungstenite::tungstenite::Message::Binary(vec![0, 0, 0, 0].into()))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
    assert!(agent::test_support::expect_socket_closed(&mut socket).await);
}

#[tokio::test]
async fn server_rejects_well_formed_non_handshake_envelope_as_first_message() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    agent::test_support::send_first_message_status_request(&mut socket).await;

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
}

#[tokio::test]
async fn server_rejects_text_frames_with_fatal_error_then_close() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    agent::test_support::send_valid_handshake(&mut socket).await;
    agent::test_support::recv_agent_info(&mut socket).await;

    socket
        .send(tokio_tungstenite::tungstenite::Message::Text("bad".into()))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
    assert!(agent::test_support::expect_socket_closed(&mut socket).await);
}

#[tokio::test]
async fn server_rejects_protocol_version_mismatch() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    agent::test_support::send_handshake_with_protocol(&mut socket, 999).await;

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "VERSION_MISMATCH");
    assert!(agent::test_support::expect_socket_closed(&mut socket).await);
}

#[tokio::test]
async fn server_rejects_malformed_binary_frame_with_fatal_error() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    socket
        .send(tokio_tungstenite::tungstenite::Message::Binary(vec![0, 0, 0, 10, 1, 2].into()))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
}

#[tokio::test]
async fn server_rejects_validly_framed_but_non_protobuf_payload_with_fatal_error() {
    let test_server = agent::test_support::spawn_mock_server().await;
    let (mut socket, _) = connect_async(test_server.ws_url()).await.unwrap();

    socket
        .send(tokio_tungstenite::tungstenite::Message::Binary(vec![0, 0, 0, 3, 1, 2, 3].into()))
        .await
        .unwrap();

    let error: ErrorEvent = agent::test_support::recv_error_event(&mut socket).await;
    assert!(error.fatal);
    assert_eq!(error.code, "PROTOCOL_ERROR");
}
```

Create `crates/agent/tests/server_sessions.rs`:

```rust
use agent::test_support::TestClient;

#[tokio::test]
async fn server_creates_session_and_broadcasts_session_list() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    client.create_session("Main", "/tmp/project").await;

    let sessions = client.expect_session_list_update().await;
    assert_eq!(sessions.sessions.len(), 1);
}

#[tokio::test]
async fn server_rejects_second_prompt_while_any_session_is_running_but_keeps_connection_open() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let first = client.create_session("One", "/tmp/one").await;
    let second = client.create_session("Two", "/tmp/two").await;

    client.send_prompt(&first.session_id, "first").await;
    let error = client.send_prompt_expect_error(&second.session_id, "second").await;

    assert!(!error.fatal);
    assert_eq!(error.code, "TASK_ALREADY_RUNNING");
    client.expect_connection_alive().await;
}

#[tokio::test]
async fn server_forwards_approval_response_and_task_resumes_to_completion() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let session = client.create_session("One", "/tmp/one").await;

    client.send_prompt(&session.session_id, "one").await;
    client.send_prompt(&session.session_id, "two").await;
    client.send_prompt(&session.session_id, "three").await;

    let approval = client.expect_approval_request().await;
    client.respond_approval(&approval.approval_id, true).await;

    client.expect_status_sequence(&["WAITING_APPROVAL", "RUNNING", "COMPLETED", "IDLE"]).await;
}

#[tokio::test]
async fn server_returns_non_fatal_error_for_missing_session() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let error = client.send_prompt_expect_error("missing-session", "oops").await;

    assert!(!error.fatal);
    assert_eq!(error.code, "SESSION_NOT_FOUND");
}

#[tokio::test]
async fn server_returns_non_fatal_error_for_unknown_approval_id() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let error = client.respond_approval_expect_error("missing-approval-id", true).await;

    assert!(!error.fatal);
    assert_eq!(error.code, "APPROVAL_NOT_FOUND");
}
```

Create `crates/agent/tests/heartbeat.rs`:

```rust
use tokio::time::{advance, Duration};

#[tokio::test(start_paused = true)]
async fn server_closes_connection_after_45_seconds_without_valid_messages() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = agent::test_support::TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    advance(Duration::from_secs(46)).await;

    client.expect_disconnect().await;
}
```

Run:

```bash
cargo test -p agent --test server_handshake
```

Expected: FAIL because the runtime server does not exist yet.

- [ ] **Step 2: Implement local transport and WebSocket server**

Create `transport.rs` with:

```rust
pub enum Transport {
    Local { listen_addr: String },
    RemoteStub,
}
```

Create `server.rs` to:

- bind `0.0.0.0:9876` by default
- accept WebSocket upgrades on `/`
- decode binary frames with `wire.rs`
- require `Handshake` as the first message
- reply to a valid handshake with `AgentInfo`
- start heartbeat timers immediately after handshake succeeds
- send heartbeat every 15 seconds once connected
- treat 45 seconds without any valid inbound message as dead and close the socket
- reject WebSocket text frames with fatal `ErrorEvent { code: "PROTOCOL_ERROR", fatal: true }` and then close
- send fatal `ErrorEvent` then close on protocol violations
- route `SessionControl`, `SendPrompt`, `ApprovalResponse`, `CancelTask`, and `Heartbeat`
- broadcast adapter events to all clients
- enforce the global concurrency rule: only one session may be `RUNNING` or `WAITING_APPROVAL` at a time; reject any new prompt during that window with a non-fatal `ErrorEvent`

- [ ] **Step 3: Implement daemon startup and CLI**

Create `daemon.rs`:

```rust
pub struct Daemon {
    pub config: Config,
}

impl Daemon {
    pub async fn run(self) -> anyhow::Result<()> {
        // create adapter, session manager, server, handle Ctrl+C
    }
}
```

Create `main.rs` using `clap` so:

- `--mock` forces `MockAdapter`
- `--config <PATH>` overrides the config file path
- `--listen` overrides the config listen address
- `--log-level` overrides logging

Update `crates/agent/src/lib.rs` in this task to export the newly created runtime modules:

```rust
pub mod adapter;
pub mod codex;
pub mod config;
pub mod daemon;
pub mod error;
pub mod session;
pub mod test_support;
pub mod transport;
pub mod wire;
```

Use `accept_hdr_async` or an equivalent API that exposes the HTTP upgrade request so the server can enforce the WebSocket path `/`.

For direct request/response envelopes, reuse the incoming `Envelope.request_id` when the spec requires pairing. For spontaneous broadcasts, mint a fresh request id.

Create `crates/agent/src/test_support.rs` to provide:

```rust
pub async fn spawn_mock_server() -> SpawnedServer;
pub async fn recv_error_event(socket: &mut TestSocket) -> proto_gen::ErrorEvent;
pub async fn recv_agent_info(socket: &mut TestSocket) -> proto_gen::AgentInfo;
pub async fn send_valid_handshake(socket: &mut TestSocket);
pub async fn send_handshake_with_protocol(socket: &mut TestSocket, version: u32);
pub async fn send_first_message_status_request(socket: &mut TestSocket);
pub async fn expect_socket_closed(socket: &mut TestSocket) -> bool;

pub struct TestClient { /* websocket wrapper */ }
```

This support module must hide repetitive handshake and binary-frame helpers so the integration tests compile cleanly.

- [ ] **Step 4: Run the full agent test and smoke-build commands**

Run:

```bash
cargo test -p agent --test server_handshake
cargo test -p agent --test server_sessions
cargo test -p agent --test heartbeat
cargo test -p agent
cargo run -p agent -- --mock --listen 127.0.0.1:9876 --log-level debug
```

Expected: tests PASS; the manual run starts listening and shuts down cleanly on `Ctrl+C`.

For this slice, all manual smoke and end-to-end verification must run the agent with `--mock`. Do not treat the default `codex-app-server` adapter path as part of the working implementation yet.

- [ ] **Step 5: Commit the agent runtime**

Run:

```bash
git add crates/agent/src/lib.rs crates/agent/src/transport.rs crates/agent/src/server.rs crates/agent/src/daemon.rs crates/agent/src/main.rs crates/agent/src/test_support.rs crates/agent/tests/server_handshake.rs crates/agent/tests/server_sessions.rs crates/agent/tests/heartbeat.rs
git commit -m "feat: add agent websocket runtime"
```

### Task 6: Create The iOS Project Skeleton And Design System

**Files:**
- Create: `ios/project.yml`
- Create: `ios/MRT.xcodeproj/`
- Create: `ios/MRT/Info.plist`
- Create: `ios/MRT/MRTApp.swift`
- Create: `ios/MRT/ContentView.swift`
- Create: `ios/MRT/DesignSystem/Theme.swift`
- Create: `ios/MRT/DesignSystem/Components/GHCard.swift`
- Create: `ios/MRT/DesignSystem/Components/GHButton.swift`
- Create: `ios/MRT/DesignSystem/Components/GHBadge.swift`
- Create: `ios/MRT/DesignSystem/Components/GHInput.swift`
- Create: `ios/MRT/DesignSystem/Components/GHBanner.swift`
- Create: `ios/MRT/DesignSystem/Components/GHCodeBlock.swift`
- Create: `ios/MRT/DesignSystem/Components/GHList.swift`
- Create: `ios/MRT/DesignSystem/Components/GHDiffView.swift`
- Create: `ios/MRT/DesignSystem/Components/GHStatusDot.swift`
- Create: `ios/MRT/DesignSystem/Components/GHTabBar.swift`

- [ ] **Step 1: Write the failing iOS build check**

Run:

```bash
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination 'generic/platform=iOS Simulator' build
```

Expected: FAIL because the Xcode project does not exist yet.

- [ ] **Step 2: Create the iOS project and root app files**

Create a reproducible iOS project with `xcodegen`.

Add `ios/project.yml`:

```yaml
name: MRT
options:
  deploymentTarget:
    iOS: "17.0"
packages:
  SwiftProtobuf:
    url: https://github.com/apple/swift-protobuf.git
    from: MATCH_INSTALLED_PROTOC_GEN_SWIFT_VERSION
targets:
  MRT:
    type: application
    platform: iOS
    sources: [MRT]
    settings:
      base:
        INFOPLIST_FILE: MRT/Info.plist
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        CODE_SIGN_IDENTITY: ""
    dependencies:
      - package: SwiftProtobuf
  MRTTests:
    type: bundle.unit-test
    platform: iOS
    sources: [MRTTests]
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        CODE_SIGN_IDENTITY: ""
    dependencies:
      - target: MRT
```

Before writing `ios/project.yml`, run:

```bash
protoc-gen-swift --version
```

Replace `MATCH_INSTALLED_PROTOC_GEN_SWIFT_VERSION` with the installed generator version so the runtime package and generator stay aligned.

Generate the project:

```bash
cd ios && xcodegen generate
```

This step must produce both the `MRT` app target and the `MRTTests` target before continuing.

Create `ios/MRT/Info.plist` with the minimum LAN settings needed for this slice:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Connect to your AnyWhereVibe desktop agent on the local network.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>
</dict>
</plist>
```

Add `ios/MRT/MRTApp.swift`:

```swift
@main
struct MRTApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
```

Add `ios/MRT/ContentView.swift` with a five-tab root using `GHTabBar` and placeholders for Chat, Sessions, Git, Files, and Settings.

- [ ] **Step 3: Implement the theme and reusable GitHub-style components**

`Theme.swift` must define the dark-first color and type tokens from `docs/SPEC-IOS.md`.

Example:

```swift
enum GHColors {
    static let bgPrimary = Color(hex: "0d1117")
    static let accentBlue = Color(hex: "58a6ff")
}
```

Implement all listed components, keeping `GHDiffView` preview-safe even though Git is not functional yet.

- [ ] **Step 4: Build the app skeleton**

Run:

```bash
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Expected: PASS.

- [ ] **Step 5: Commit the iOS shell and design system**

Run:

```bash
git add ios/project.yml ios/MRT.xcodeproj ios/MRT/Info.plist ios/MRT/MRTApp.swift ios/MRT/ContentView.swift ios/MRT/DesignSystem
git commit -m "feat: add ios app shell and design system"
```

### Task 7: Implement iOS Core Networking, Models, And Persistence

**Files:**
- Create: `ios/MRT/Core/Proto/Mrt.pb.swift`
- Create: `ios/MRT/Core/Network/ProtobufCodec.swift`
- Create: `ios/MRT/Core/Network/WebSocketClient.swift`
- Create: `ios/MRT/Core/Network/ConnectionManager.swift`
- Create: `ios/MRT/Core/Network/MessageDispatcher.swift`
- Create: `ios/MRT/Core/Models/ChatMessage.swift`
- Create: `ios/MRT/Core/Models/SessionModel.swift`
- Create: `ios/MRT/Core/Storage/Preferences.swift`
- Create: `ios/MRTTests/Network/ProtobufCodecTests.swift`
- Create: `ios/MRTTests/Network/MessageDispatcherTests.swift`
- Create: `ios/MRTTests/Network/ConnectionManagerTests.swift`
- Create: `ios/MRTTests/TestSupport/TestDoubles.swift`

- [ ] **Step 1: Write the failing codec, dispatcher, and test-double support**

Create `ios/MRTTests/TestSupport/TestDoubles.swift`:

```swift
@testable import MRT
import Foundation
import SwiftProtobuf

final class StubWebSocketClient: WebSocketClientProtocol {
    var sentData: [Data] = []
    var onReceive: ((Data) -> Void)?
    var onClose: (() -> Void)?

    func connect(url: URL) async throws {}
    func send(_ data: Data) async throws { sentData.append(data) }
    func disconnect() { onClose?() }

    func pushIncomingEnvelope(_ envelope: Mrt_Envelope) {
        let data = try! ProtobufCodec.encode(envelope)
        onReceive?(data)
    }

    func simulateClose() { onClose?() }
}

final class StubConnectionManager: ConnectionManaging {
    var sentPrompts: [String] = []

    func sendPrompt(_ prompt: String, sessionID: String) async throws {
        sentPrompts.append(prompt)
    }
}

func makeAgentInfoEnvelope() -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.event = .with { event in
        event.agentInfo = .with { info in
            info.agentVersion = "0.1.0"
            info.adapterType = "mock"
            info.hostname = "test-mac"
            info.os = "iOS"
        }
    }
    return envelope
}

func makeCodexOutput(content: String, complete: Bool) -> Mrt_Envelope {
    var envelope = Mrt_Envelope()
    envelope.event = .with { event in
        event.codexOutput = .with { output in
            output.sessionID = "session-1"
            output.content = content
            output.isComplete = complete
        }
    }
    return envelope
}

func makeApprovalRequest() -> Mrt_ApprovalRequest {
    var request = Mrt_ApprovalRequest()
    request.approvalID = "approval-1"
    request.sessionID = "session-1"
    request.description_p = "Write to file src/main.rs"
    request.command = "echo hi"
    return request
}
```

Create `ios/MRTTests/Network/ProtobufCodecTests.swift`:

```swift
@testable import MRT
import XCTest

final class ProtobufCodecTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        var envelope = Mrt_Envelope()
        envelope.protocolVersion = 1
        envelope.requestID = "req-1"
        envelope.timestampMs = 42

        let data = try ProtobufCodec.encode(envelope)
        let decoded = try ProtobufCodec.decode(data)

        XCTAssertEqual(decoded.requestID, "req-1")
    }

    func testLengthPrefixMatchesRemainingPayloadLength() throws {
        var envelope = Mrt_Envelope()
        envelope.requestID = "req-2"

        let data = try ProtobufCodec.encode(envelope)
        let length = data.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }

        XCTAssertEqual(Int(length), data.count - 4)
    }
}
```

Create `ios/MRTTests/Network/MessageDispatcherTests.swift`:

```swift
@testable import MRT
import XCTest

final class MessageDispatcherTests: XCTestCase {
    func testDispatcherAppendsStreamingCodexOutputIntoSingleMessage() throws {
        let dispatcher = MessageDispatcher()
        let first = makeCodexOutput(content: "Hello ", complete: false)
        let second = makeCodexOutput(content: "world", complete: true)

        dispatcher.apply(first)
        dispatcher.apply(second)

        XCTAssertEqual(dispatcher.messages.last?.content, "Hello world")
        XCTAssertEqual(dispatcher.messages.last?.isComplete, true)
    }
}
```

Create `ios/MRTTests/Network/ConnectionManagerTests.swift`:

```swift
@testable import MRT
import XCTest

final class ConnectionManagerTests: XCTestCase {
    func testConnectionManagerTransitionsToConnectedAfterAgentInfoAndReconnectsOnClose() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 15, timeoutInterval: 45)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        XCTAssertEqual(manager.state, .connecting)

        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())
        XCTAssertEqual(manager.state, .connected)

        socket.simulateClose()
        XCTAssertEqual(manager.state, .reconnecting)
    }

    func testConnectionManagerSendsHeartbeatEnvelopeEvery15Seconds() async throws {
        let socket = StubWebSocketClient()
        let manager = ConnectionManager(socket: socket, heartbeatInterval: 0.01, timeoutInterval: 0.02)

        try await manager.connect(host: "127.0.0.1", port: 9876)
        socket.pushIncomingEnvelope(makeAgentInfoEnvelope())

        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(socket.sentData.contains(where: { data in
            (try? ProtobufCodec.decode(data).hasHeartbeat) == true
        }))
    }
}
```

Run:

```bash
IOS_SIMULATOR_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')
test -n "$IOS_SIMULATOR_ID"
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:MRTTests/ProtobufCodecTests
```

Expected: FAIL because the core network files do not exist yet.

- [ ] **Step 2: Generate and add the Swift protobuf file**

Run:

```bash
scripts/proto-gen-swift.sh
```

If the plugin is unavailable, stop and install `swift-protobuf` before continuing. Commit the generated `ios/MRT/Core/Proto/Mrt.pb.swift` output into the repo.

The generated file must compile against the SwiftProtobuf package dependency declared in `ios/project.yml`. Do not hand-edit generated types unless code generation itself is broken.

- [ ] **Step 3: Implement the core iOS runtime**

Key responsibilities:

- `ProtobufCodec.swift`: prepend and strip the 4-byte big-endian length prefix
- `WebSocketClient.swift`: connect to `ws://<host>:9876/`, send/receive binary messages, publish connection state
- `ConnectionManager.swift`: own handshake, heartbeat, reconnect, and envelope send APIs
- `ConnectionManager.swift`: accept injectable `heartbeatInterval` and `timeoutInterval` values so tests can run with tiny intervals instead of real 15s/45s waits
- `ConnectionManager.swift`: do not mark the app as fully connected until `AgentInfo` is received after handshake
- `ConnectionManager.swift`: send `Envelope { heartbeat }` every 15 seconds after handshake success and transition to `.reconnecting` when the socket closes or after 45 seconds without any valid inbound message
- `MessageDispatcher.swift`: map incoming events into `ChatMessage`, `SessionModel`, approval state, and connection indicators
- `MessageDispatcher.swift`: render business-level `ErrorEvent` values as thread/system messages while reserving the connection status bar for transport or fatal connection failures
- `Preferences.swift`: store direct host, direct port, and connection mode using `UserDefaults` or `@AppStorage`
- define protocols such as `WebSocketClientProtocol` and `ConnectionManaging` so the test doubles in `ios/MRTTests/TestSupport/TestDoubles.swift` compile cleanly
- model the full screen/connection state enum required by the spec: `disconnected`, `connecting`, `connected`, `loading`, `showingApproval`, `reconnecting`

Key codec shape:

```swift
enum ProtobufCodec {
    static func encode(_ envelope: Mrt_Envelope) throws -> Data
    static func decode(_ data: Data) throws -> Mrt_Envelope
}
```

- [ ] **Step 4: Run the networking test suite**

Run:

```bash
IOS_SIMULATOR_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')
test -n "$IOS_SIMULATOR_ID"
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:MRTTests/ProtobufCodecTests
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:MRTTests/MessageDispatcherTests
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:MRTTests/ConnectionManagerTests
```

Expected: PASS.

- [ ] **Step 5: Commit the iOS core runtime**

Run:

```bash
git add ios/MRT/Core ios/MRTTests/Network ios/MRTTests/TestSupport
git commit -m "feat: add ios networking and models"
```

### Task 8: Implement The iOS Chat, Sessions, And Settings Features

**Files:**
- Create: `ios/MRT/Features/Chat/ChatView.swift`
- Create: `ios/MRT/Features/Chat/ThreadMessageView.swift`
- Create: `ios/MRT/Features/Chat/StreamingTextView.swift`
- Create: `ios/MRT/Features/Chat/ApprovalBannerView.swift`
- Create: `ios/MRT/Features/Chat/ConnectionStatusBar.swift`
- Create: `ios/MRT/Features/Chat/PromptInputBar.swift`
- Create: `ios/MRT/Features/Chat/ChatViewModel.swift`
- Create: `ios/MRT/Features/Sessions/SessionSidebarView.swift`
- Create: `ios/MRT/Features/Sessions/SessionsScreen.swift`
- Create: `ios/MRT/Features/Sessions/SessionRowView.swift`
- Create: `ios/MRT/Features/Sessions/SessionViewModel.swift`
- Create: `ios/MRT/Features/Settings/SettingsView.swift`
- Create: `ios/MRT/Features/Placeholders/GitPlaceholderView.swift`
- Create: `ios/MRT/Features/Placeholders/FilesPlaceholderView.swift`
- Modify: `ios/MRTTests/TestSupport/TestDoubles.swift`
- Create: `ios/MRTTests/Features/ChatViewModelTests.swift`

- [ ] **Step 1: Write the failing ChatViewModel test**

Create `ios/MRTTests/Features/ChatViewModelTests.swift`:

```swift
@testable import MRT
import XCTest

final class ChatViewModelTests: XCTestCase {
    func testSendPromptCreatesUserMessageAndStartsLoading() {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)

        viewModel.inputText = "Ship it"
        viewModel.sendPrompt()

        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(connection.sentPrompts, ["Ship it"])
    }

    func testChatViewModelCoversAllRequiredUiStates() {
        let connection = StubConnectionManager()
        let viewModel = ChatViewModel(connectionManager: connection)

        viewModel.connectionState = .disconnected
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        viewModel.connectionState = .connecting
        XCTAssertEqual(viewModel.connectionState, .connecting)
        viewModel.connectionState = .connected
        XCTAssertEqual(viewModel.connectionState, .connected)
        viewModel.isLoading = true
        XCTAssertTrue(viewModel.isLoading)
        viewModel.pendingApproval = makeApprovalRequest()
        XCTAssertNotNil(viewModel.pendingApproval)
        viewModel.connectionState = .reconnecting
        XCTAssertEqual(viewModel.connectionState, .reconnecting)
    }
}
```

Run:

```bash
IOS_SIMULATOR_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')
test -n "$IOS_SIMULATOR_ID"
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:MRTTests/ChatViewModelTests
```

Expected: FAIL because the feature layer does not exist yet.

- [ ] **Step 2: Implement the feature views and view models**

Requirements:

- `ChatView.swift`: thread layout, auto-scroll, inline approval banner, prompt bar
- `ThreadMessageView.swift`: user vs Codex visual distinction
- `StreamingTextView.swift`: code-block aware rendering with a visible streaming cursor
- `ChatViewModel.swift`: bind connection state, messages, approval state, and prompt send/cancel actions
- `ChatViewModel.swift`: explicitly model `disconnected`, `connecting`, `connected`, `loading`, `showingApproval`, and `reconnecting`
- `SessionSidebarView.swift` and `SessionsScreen.swift`: share the same backing data model and behaviors
- `SettingsView.swift`: direct LAN mode selection, host entry, port entry, and basic validation for empty or invalid values
- `GitPlaceholderView.swift` and `FilesPlaceholderView.swift`: visible but clearly marked as not yet implemented

Critical constraint:

```swift
// Sessions tab and sidebar must share one source of truth.
@StateObject var sessionViewModel: SessionViewModel
```

- [ ] **Step 3: Wire the root app together**

Update `ios/MRT/ContentView.swift` so:

- Chat uses the shared `ChatViewModel`
- Sessions tab reuses the same `SessionViewModel` used by the chat sidebar
- Settings uses persisted connection preferences
- Git and Files show placeholders without crashing

- [ ] **Step 4: Run the feature tests and simulator build**

Run:

```bash
IOS_SIMULATOR_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')
test -n "$IOS_SIMULATOR_ID"
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test -only-testing:MRTTests/ChatViewModelTests
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Expected: PASS.

- [ ] **Step 5: Commit the iOS feature layer**

Run:

```bash
git add ios/MRT/ContentView.swift ios/MRT/Features ios/MRTTests/Features
git commit -m "feat: add ios chat sessions and settings"
```

### Task 9: Verify End-To-End Agent Mock To iOS Flow

**Files:**
- Modify: `scripts/dev-agent-mock.sh`
- Modify: `ios/MRT/Core/Network/ConnectionManager.swift`
- Modify: `ios/MRT/Features/Chat/ChatViewModel.swift`
- Modify: `crates/agent/src/server.rs`
- Modify: `crates/agent/src/adapter/mock.rs`

- [ ] **Step 1: Write the failing end-to-end checklist**

Document the acceptance checklist in the task branch and attempt the full smoke test:

```bash
scripts/dev-agent-mock.sh
```

Expected: if any missing runtime behavior remains, note the first failing acceptance item:

- agent starts in `--mock` mode
- iOS connects over LAN
- handshake succeeds
- session create/switch works
- prompt sends
- output streams
- approval banner appears on every third prompt
- approve/reject round-trip works
- reconnect after disconnect shows correct status

Use `127.0.0.1:9876` for Simulator-based validation. Use the Mac's LAN IP with the same port for a physical iPhone. The agent must be listening on `0.0.0.0:9876`.

- [ ] **Step 2: Fix the remaining integration gaps**

Adjust the runtime until the full acceptance checklist passes. Typical fixes belong only in:

- `crates/agent/src/server.rs`
- `crates/agent/src/adapter/mock.rs`
- `ios/MRT/Core/Network/ConnectionManager.swift`
- `ios/MRT/Features/Chat/ChatViewModel.swift`

Do not expand scope beyond the checklist.

- [ ] **Step 3: Run the complete verification suite**

Run:

```bash
cargo test -p proto-gen
cargo test -p agent
IOS_SIMULATOR_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')
test -n "$IOS_SIMULATOR_ID"
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
```

Then run the manual smoke flow:

```bash
scripts/dev-agent-mock.sh
```

Expected: tests PASS; manual flow satisfies all eight acceptance criteria from the spec.

- [ ] **Step 4: Commit the verified A-slice**

Run:

```bash
git add crates/agent/src/server.rs crates/agent/src/adapter/mock.rs ios/MRT/Core/Network/ConnectionManager.swift ios/MRT/Features/Chat/ChatViewModel.swift scripts/dev-agent-mock.sh
git commit -m "feat: verify anywherevibe a-slice end to end"
```

### Task 10: Final Quality Pass And Branch Summary

**Files:**
- Modify: files touched during verification only if a concrete issue is found

- [ ] **Step 1: Run final repo-wide verification**

Run:

```bash
cargo test --workspace
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
IOS_SIMULATOR_ID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')
test -n "$IOS_SIMULATOR_ID"
xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination "id=$IOS_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
git status --short
```

Expected: tests and build PASS; `git status --short` shows only intended tracked changes.

- [ ] **Step 2: Request a final code review**

Dispatch a reviewer subagent with the completed implementation and ask for:

- spec compliance review
- code quality review
- testing gaps

Fix only real issues it finds.

- [ ] **Step 3: Summarize verification evidence**

Record:

- the exact `cargo test --workspace` result
- the exact `xcodebuild` result
- the manual `agent --mock` smoke-test result

- [ ] **Step 4: Commit final cleanups if needed**

Run only if Step 2 produced real fixes:

```bash
git add -A
git commit -m "chore: finalize a-slice quality fixes"
```
