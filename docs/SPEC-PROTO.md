# SPEC-PROTO — Protocol Definitions

> Dependency: None (start immediately)  
> Output: `proto/mrt.proto` + generated code for Rust, Swift, Kotlin  
> Duration: 1-2 days

This is the **shared contract** between all components. Complete this first so all other teams can start.

---

## Task List

### PROTO-T01: Create `proto/mrt.proto`

Create the file with the following complete content:

```protobuf
syntax = "proto3";
package mrt;

// ═══════════════════════════════════════════
// Envelope — every message on the wire
// ═══════════════════════════════════════════

message Envelope {
  uint32 protocol_version = 1;    // Current: 1. Increment on breaking changes.
  string request_id = 2;          // UUID v4. Used to match request/response pairs.
  uint64 timestamp_ms = 3;        // Unix millis. Used for replay protection.

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
    // Connection Node specific
    DeviceRegister device_register = 30;
    DeviceRegisterAck device_register_ack = 31;
    ConnectToDevice connect_to_device = 32;
    ConnectToDeviceAck connect_to_device_ack = 33;
    DeviceListRequest device_list_request = 34;
    DeviceListResponse device_list_response = 35;
    // ICE signaling (managed mode)
    IceCandidate ice_candidate = 40;
    IceOffer ice_offer = 41;
    IceAnswer ice_answer = 42;
  }
}

// ═══════════════════════════════════════════
// Handshake — first message on connection
// ═══════════════════════════════════════════

message Handshake {
  uint32 protocol_version = 1;
  ClientType client_type = 2;
  string client_version = 3;     // semver, e.g. "1.0.0"
  string device_id = 4;
}

enum ClientType {
  CLIENT_TYPE_UNSPECIFIED = 0;
  DESKTOP_AGENT = 1;
  PHONE_IOS = 2;
  PHONE_ANDROID = 3;
  WATCH = 4;
}

// ═══════════════════════════════════════════
// Commands (client → agent)
// ═══════════════════════════════════════════

message AgentCommand {
  oneof cmd {
    SendPrompt send_prompt = 1;
    ApprovalResponse approval_response = 2;
    CancelTask cancel_task = 3;
    GetStatus get_status = 4;
  }
}

message SendPrompt {
  string session_id = 1;
  string prompt = 2;
}

message ApprovalResponse {
  string approval_id = 1;        // matches ApprovalRequest.approval_id
  bool approved = 2;
}

message CancelTask {
  string session_id = 1;
}

message GetStatus {
  string session_id = 1;         // empty = get all sessions
}

// ═══════════════════════════════════════════
// Events (agent → client)
// ═══════════════════════════════════════════

message AgentEvent {
  oneof evt {
    CodexOutput codex_output = 1;
    ApprovalRequest approval_request = 2;
    TaskStatusUpdate status_update = 3;
    SessionListUpdate session_list = 4;
    AgentInfo agent_info = 5;
    ErrorEvent error = 10;
  }
}

message CodexOutput {
  string session_id = 1;
  string content = 2;             // text chunk (streaming)
  bool is_complete = 3;           // true = final chunk
  OutputType output_type = 4;
}

enum OutputType {
  OUTPUT_TYPE_UNSPECIFIED = 0;
  ASSISTANT_TEXT = 1;             // normal Codex response
  TOOL_CALL = 2;                  // Codex calling a tool
  TOOL_RESULT = 3;                // tool execution result
  SYSTEM = 4;                     // system message
}

message ApprovalRequest {
  string approval_id = 1;        // unique ID for this request
  string session_id = 2;
  string description = 3;         // human-readable: "Write to file auth.ts"
  string command = 4;              // actual command: "cat > auth.ts << 'EOF'..."
  ApprovalType approval_type = 5;
}

enum ApprovalType {
  APPROVAL_TYPE_UNSPECIFIED = 0;
  FILE_WRITE = 1;
  SHELL_COMMAND = 2;
  NETWORK_ACCESS = 3;
}

message TaskStatusUpdate {
  string session_id = 1;
  TaskStatus status = 2;
  string summary = 3;             // short description of what happened
}

enum TaskStatus {
  TASK_STATUS_UNSPECIFIED = 0;
  IDLE = 1;
  RUNNING = 2;
  WAITING_APPROVAL = 3;
  COMPLETED = 4;
  ERROR = 5;
  CANCELLED = 6;
}

message SessionListUpdate {
  repeated SessionInfo sessions = 1;
}

message SessionInfo {
  string session_id = 1;
  string name = 2;
  TaskStatus status = 3;
  uint64 created_at_ms = 4;
  uint64 last_active_ms = 5;
  string working_dir = 6;        // project directory for this session
}

message AgentInfo {
  string agent_version = 1;
  string adapter_type = 2;       // "codex-app-server", "codex-cli", "mock"
  string hostname = 3;
  string os = 4;
}

message ErrorEvent {
  string code = 1;                // e.g. "VERSION_MISMATCH", "AUTH_FAILED", "CODEX_UNAVAILABLE"
  string message = 2;
  bool fatal = 3;                 // if true, connection will be closed
}

// ═══════════════════════════════════════════
// Session Control
// ═══════════════════════════════════════════

message SessionControl {
  oneof action {
    CreateSession create = 1;
    SwitchSession switch_to = 2;
    CloseSession close = 3;
    ListSessions list = 4;
    RenameSession rename = 5;
  }
}

message CreateSession  { string name = 1; string working_dir = 2; }
message SwitchSession  { string session_id = 1; }
message CloseSession   { string session_id = 1; }
message ListSessions   {}
message RenameSession  { string session_id = 1; string new_name = 2; }

// ═══════════════════════════════════════════
// File Operations
// ═══════════════════════════════════════════

message FileOperation {
  string session_id = 1;         // scope to session's working_dir
  oneof op {
    ListDir list_dir = 2;
    ReadFile read_file = 3;
    WriteFile write_file = 4;
  }
}

message ListDir  { string path = 1; bool recursive = 2; uint32 max_depth = 3; }
message ReadFile { string path = 1; uint64 offset = 2; uint64 length = 3; }
message WriteFile { string path = 1; bytes content = 2; }

message FileResult {
  string session_id = 1;
  oneof result {
    DirListing dir_listing = 2;
    FileContent file_content = 3;
    FileWriteAck write_ack = 4;
    ErrorEvent error = 10;
  }
}

message DirListing {
  repeated FileEntry entries = 1;
}

message FileEntry {
  string name = 1;
  string path = 2;
  bool is_dir = 3;
  uint64 size = 4;
  uint64 modified_ms = 5;
}

message FileContent {
  string path = 1;
  bytes content = 2;
  string mime_type = 3;
}

message FileWriteAck {
  string path = 1;
  bool success = 2;
}

// ═══════════════════════════════════════════
// Git Operations
// ═══════════════════════════════════════════

message GitOperation {
  string session_id = 1;         // scope to session's working_dir
  oneof op {
    GitStatusReq status = 2;
    GitCommitReq commit = 3;
    GitPushReq push = 4;
    GitPullReq pull = 5;
    GitDiffReq diff = 6;
    GitLogReq log = 7;
    GitBranchesReq branches = 8;
    GitCheckoutReq checkout = 9;
  }
}

message GitStatusReq    {}
message GitCommitReq    { string message = 1; bool stage_all = 2; }
message GitPushReq      { string remote = 1; }
message GitPullReq      { string remote = 1; }
message GitDiffReq      { string path = 1; bool staged = 2; }
message GitLogReq       { uint32 limit = 1; }
message GitBranchesReq  {}
message GitCheckoutReq  { string branch = 1; bool create = 2; }

message GitResult {
  string session_id = 1;
  oneof result {
    GitStatusResult status = 2;
    GitDiffResult diff = 3;
    GitLogResult log = 4;
    GitBranchesResult branches = 5;
    GitOperationAck ack = 6;
    ErrorEvent error = 10;
  }
}

message GitStatusResult {
  string branch = 1;
  string tracking = 2;
  repeated GitFileChange changes = 3;
  bool is_clean = 4;
}

message GitFileChange {
  string path = 1;
  string status = 2;             // "modified", "added", "deleted", "untracked"
}

message GitDiffResult    { string diff = 1; }
message GitLogResult     { repeated GitCommitInfo commits = 1; }
message GitCommitInfo    { string hash = 1; string message = 2; string author = 3; uint64 timestamp_ms = 4; }
message GitBranchesResult { repeated string branches = 1; string current = 2; }
message GitOperationAck  { bool success = 1; string message = 2; }

// ═══════════════════════════════════════════
// Heartbeat
// ═══════════════════════════════════════════

message Heartbeat {
  uint64 timestamp_ms = 1;
}

// ═══════════════════════════════════════════
// Connection Node — Device Management
// ═══════════════════════════════════════════

message DeviceRegister {
  string device_id = 1;
  string auth_token = 2;         // per-user token (self-hosted) or JWT (managed)
  DeviceType device_type = 3;
  string display_name = 4;       // "Ming's MacBook"
  string agent_version = 5;
}

enum DeviceType {
  DEVICE_TYPE_UNSPECIFIED = 0;
  AGENT = 1;
  PHONE = 2;
  DEVICE_WATCH = 3;
}

message DeviceRegisterAck {
  bool success = 1;
  string message = 2;
}

message ConnectToDevice {
  string target_device_id = 1;
}

message ConnectToDeviceAck {
  bool success = 1;
  string message = 2;            // error reason if failed
  ConnectionType connection_type = 3;
}

enum ConnectionType {
  CONNECTION_TYPE_UNSPECIFIED = 0;
  RELAY = 1;                     // data forwarded through node
  P2P = 2;                       // direct connection established
}

message DeviceListRequest {}

message DeviceListResponse {
  repeated DeviceInfo devices = 1;
}

message DeviceInfo {
  string device_id = 1;
  DeviceType device_type = 2;
  string display_name = 3;
  bool is_online = 4;
  uint64 last_seen_ms = 5;
}

// ═══════════════════════════════════════════
// ICE Signaling (Managed Mode)
// ═══════════════════════════════════════════

message IceCandidate {
  string target_device_id = 1;
  string candidate = 2;          // SDP candidate string
  string sdp_mid = 3;
  uint32 sdp_mline_index = 4;
}

message IceOffer {
  string target_device_id = 1;
  string sdp = 2;
}

message IceAnswer {
  string target_device_id = 1;
  string sdp = 2;
}
```

### PROTO-T02: Rust Code Generation

Create `crates/proto-gen/build.rs`:
```rust
fn main() {
    prost_build::compile_protos(&["../../proto/mrt.proto"], &["../../proto/"]).unwrap();
}
```

Create `crates/proto-gen/src/lib.rs`:
```rust
include!(concat!(env!("OUT_DIR"), "/mrt.rs"));
```

Verify: `cargo build -p proto-gen` succeeds. All types importable.

### PROTO-T03: Swift Code Generation

Create `scripts/proto-gen-swift.sh`:
```bash
#!/bin/bash
protoc --swift_out=ios/MRT/Core/Proto/ proto/mrt.proto
```

Prerequisite: `brew install swift-protobuf`

### PROTO-T04: Kotlin Code Generation

Create `scripts/proto-gen-kotlin.sh`:
```bash
#!/bin/bash
protoc --kotlin_out=android/app/src/main/java/ proto/mrt.proto
```

### PROTO-T05: Wire Format Convention

Document these rules (all components must follow):

1. **WebSocket frame type**: Binary (not Text). Each frame = one Protobuf-encoded `Envelope`.
2. **Byte format**: `[4 bytes big-endian length][Protobuf payload]`. Length prefix allows receivers to frame messages correctly even if WebSocket doesn't guarantee message boundaries in some transports.
3. **request_id**: UUID v4 string. Commands carry a request_id. The response to a command reuses the same request_id for matching.
4. **timestamp_ms**: Unix milliseconds. Used for replay protection (reject messages older than 60 seconds when encryption is enabled).
5. **First message on any connection**: must be `Handshake`. If not, server closes connection.
6. **Heartbeat**: send every 15 seconds. If no heartbeat or other message received for 45 seconds, consider connection dead.

**Acceptance**: All generated code compiles. A test in each language can encode and decode an Envelope.
