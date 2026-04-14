# AnyWhereVibe A-Slice Design

**Date:** 2026-04-14

## References and Precedence

This design is a narrowed implementation slice derived from these source specs:

- `docs/SPEC.md`
- `docs/SPEC-PROTO.md`
- `docs/SPEC-AGENT.md`
- `docs/SPEC-IOS.md`

Precedence for this slice is:

1. this design document for scope and slice-specific tradeoffs
2. `docs/SPEC-PROTO.md` for the concrete protobuf message set and field definitions
3. `docs/SPEC-AGENT.md` for agent-specific interfaces and runtime expectations
4. `docs/SPEC-IOS.md` for iOS-specific UI structure and component intent
5. `docs/SPEC.md` for master context only

If a later-phase requirement from the source specs conflicts with this slice's scope, this design document wins for the current implementation.

## Goal

Deliver the first usable release slice of AnyWhereVibe by completing:

- shared protocol definitions in `proto/mrt.proto`
- a Rust desktop agent that runs locally in `--mock` mode
- an iOS SwiftUI client that can connect over LAN, manage sessions, send prompts, render streaming output, and handle inline approvals

This slice must be usable end-to-end without a real Codex backend. It must preserve clean extension points for later `Connection Node`, `Android`, `watchOS`, and real `codex app-server` integration.

## Scope

### In Scope

- one monorepo containing `proto/`, `crates/`, `ios/`, `scripts/`, and `docs/`
- complete protobuf contract in `proto/mrt.proto`, including later-phase message families so downstream modules can build against a stable wire contract
- Rust `proto-gen` crate for generated Rust types
- Rust `agent` crate with:
  - config loading and CLI
  - daemon startup and graceful shutdown
  - local WebSocket server
  - binary envelope framing and protobuf encode/decode
  - handshake validation and heartbeat handling
  - session persistence and session control
  - `AgentAdapter` abstraction
  - fully working `MockAdapter`
  - placeholder files and interfaces for `codex_appserver` and `codex_cli`
- iOS app with:
  - GitHub-style design system
  - direct LAN connection settings
  - connection manager and protobuf codec
  - chat thread UI
  - streaming text rendering
  - inline approval banner
  - session sidebar with create/switch
  - connection status bar
  - prompt input bar
  - placeholders for Git and Files tabs

### Out of Scope

- `Connection Node`
- managed relay, ICE, STUN, TURN
- Noise encryption
- QR pairing
- APNs
- real Git and file operations
- Android
- watchOS
- fully working `codex app-server` and `codex-cli` integrations

## Architecture

This release uses a contract-first, runnable-subset architecture.

`proto/mrt.proto` is defined once and includes both current and future message families. The runtime implementation only activates the subset required by the first release: `Handshake`, `Heartbeat`, `SessionControl`, `AgentCommand`, and `AgentEvent`.

The iOS app communicates directly with the desktop agent over LAN using binary WebSocket messages. Each business message is a protobuf `Envelope`, framed as:

```text
[4-byte big-endian length][protobuf Envelope]
```

The desktop agent owns transport, validation, session state, and adapter dispatch. In this release, the adapter is `MockAdapter`, which simulates streaming Codex output and approval requests. The iOS app owns presentation, view state, and user actions.

## Repository Structure

```text
AnyWhereVibe/
├── Cargo.toml
├── Cargo.lock
├── .gitignore
├── proto/
│   └── mrt.proto
├── crates/
│   ├── proto-gen/
│   │   ├── Cargo.toml
│   │   ├── build.rs
│   │   └── src/lib.rs
│   └── agent/
│       ├── Cargo.toml
│       └── src/
│           ├── main.rs
│           ├── config.rs
│           ├── daemon.rs
│           ├── server.rs
│           ├── transport.rs
│           ├── session.rs
│           ├── wire.rs
│           ├── error.rs
│           ├── adapter/
│           │   ├── mod.rs
│           │   ├── mock.rs
│           │   ├── codex_appserver.rs
│           │   └── codex_cli.rs
│           └── codex/
│               ├── mod.rs
│               ├── process.rs
│               └── rpc.rs
├── ios/
│   ├── MRT.xcodeproj
│   └── MRT/
│       ├── MRTApp.swift
│       ├── ContentView.swift
│       ├── DesignSystem/
│       ├── Core/
│       ├── Features/
│       └── Resources/
├── scripts/
│   ├── proto-gen-swift.sh
│   ├── proto-gen-kotlin.sh
│   └── dev-agent-mock.sh
└── docs/
```

## Component Boundaries

### Protocol

`proto/mrt.proto` is the only source of truth for the wire contract.

- It must include all message families already described in the master spec.
- The concrete required message and field set comes from `docs/SPEC-PROTO.md`, specifically `PROTO-T01`, which must be copied in full rather than reinterpreted.
- Current implementation must only depend on the P0 subset.
- Future modules must be able to generate code from the same file without requiring breaking changes to the current slice.

### Rust Proto Generation

`crates/proto-gen` only exposes generated Rust types and must not contain runtime logic.

### Desktop Agent

`crates/agent` owns:

- configuration and CLI startup
- WebSocket transport
- message framing and decoding
- handshake validation
- session storage
- adapter dispatch
- event fan-out to connected clients

The agent must support one local transport mode in this release. Remote transport is explicitly stubbed, not partially implemented.

### iOS App

`ios/MRT/Core` owns:

- generated protobuf types
- network transport
- message encoding and decoding
- connection lifecycle
- local models
- preferences

`ios/MRT/Features` owns:

- chat screen
- session sidebar
- settings
- view models
- status and approval presentation

`ios/MRT/DesignSystem` owns all GitHub-style reusable components and theme tokens.

## Runtime Flow

### Connection Flow

Defaults for this slice:

- agent listen address default: `0.0.0.0:9876`
- iOS direct-mode endpoint format: `ws://<host>:9876/`
- WebSocket path: `/`

1. iOS opens a WebSocket to the agent's local address.
2. iOS sends `Envelope { Handshake }` as the first message.
3. Agent validates `protocol_version` and first-message requirements.
4. Agent responds with `AgentInfo` or a fatal `ErrorEvent`.
5. Both sides begin heartbeat exchange using the protocol defaults from `docs/SPEC-PROTO.md`:
   - send a heartbeat every 15 seconds
   - if no heartbeat or any other valid message is received for 45 seconds, consider the connection dead
   - both sides start their heartbeat timers immediately after successful handshake handling
6. On heartbeat timeout, the agent closes the WebSocket connection and the iOS client transitions to reconnecting.

### Session Flow

1. iOS can create a new session or list existing sessions.
2. Agent persists sessions to local storage.
3. Session list updates are sent back to connected clients.
4. One session can be active in the UI at a time.

### Prompt Flow

1. User sends a prompt from the active session.
2. iOS sends `AgentCommand.SendPrompt`.
3. Agent ensures the target session exists, marks it `RUNNING`, and forwards the prompt to the adapter.
4. `MockAdapter` emits:
   - zero or more `CodexOutput` chunks
   - optional `ApprovalRequest`
   - status transitions
   - a final output chunk marked complete
5. Agent forwards adapter events to all connected clients.
6. iOS merges incoming chunks into the visible thread and updates loading state.

For deterministic behavior in this slice, `MockAdapter` requests approval on every third prompt after the first two output chunks have been emitted for that prompt.

## State Model

### Session Execution Model

The first release supports:

- multiple sessions
- one active task at a time inside each session
- at most one running task globally across the whole agent
- no task queue within a session

If a new prompt is attempted while any session is already running, the agent must reject it with a non-fatal error event.

### Agent Session Status

Allowed status transitions:

- `IDLE -> RUNNING`
- `RUNNING -> WAITING_APPROVAL`
- `WAITING_APPROVAL -> RUNNING`
- `RUNNING -> COMPLETED`
- `RUNNING -> CANCELLED`
- `RUNNING -> ERROR`
- `COMPLETED -> IDLE`
- `CANCELLED -> IDLE`

### iOS Screen State

The chat screen must explicitly model:

- disconnected
- connecting
- connected
- loading
- showing approval
- reconnecting after drop

The connection status bar is the primary source of truth for transport state. Thread messages supplement it with task-level outcomes.

## Desktop Agent Design

### Config and CLI

The agent CLI must support:

- config path override
- `--mock`
- listen address override
- log level override

`--mock` forces adapter selection to `mock`.

### Wire Handling

The agent must have a dedicated wire module for:

- framing outbound envelopes with a 4-byte big-endian length prefix
- reading inbound binary frames
- decoding protobuf payloads
- rejecting malformed frames cleanly

Operational framing rules for this slice:

- exactly one protobuf `Envelope` is carried in each WebSocket binary message
- the first 4 bytes are a big-endian unsigned length prefix
- that length prefix must exactly equal the remaining payload size in the same WebSocket message
- multiple envelopes in a single WebSocket message are invalid
- a WebSocket text message is invalid
- a binary message with fewer than 4 bytes, mismatched length, trailing bytes, or protobuf decode failure is a malformed frame
- WebSocket fragmentation is handled by the client and server WebSocket libraries before the wire module sees the complete binary message

### WebSocket Server

The server must:

- accept local client connections
- require `Handshake` as the first message
- track connected clients
- route command and session envelopes
- subscribe to adapter events and broadcast them to clients
- track heartbeat timeouts

### Session Persistence

Sessions must be persisted to a single JSON file at:

- default directory: `~/.mrt/`
- default file: `~/.mrt/sessions.json`

If the directory does not exist, the agent creates it on startup.

This slice assumes a single local agent process owns the file. Concurrent multi-process writers are out of scope.

Persistence behavior for this slice:

- load `sessions.json` on startup if it exists
- create a new empty session store if it does not exist
- write the full file atomically on every mutation
- no schema migration/versioning is required in this slice
- corrupted JSON should be surfaced as an explicit startup error, not silently discarded

Each session stores:

- id
- name
- status
- working directory
- created timestamp
- last active timestamp

### Adapter Layer

The adapter trait is locked in this release so real backends can be added later without redesigning the server.

`MockAdapter` must be fully working and emit:

- streaming assistant text in chunks
- status transitions
- deterministic periodic approval requests

`codex_appserver.rs` and `codex_cli.rs` must exist with clear placeholder implementations that return explicit "not yet implemented" errors when invoked.

## iOS App Design

### Design System

The app uses a GitHub-inspired dark-first design language:

- monochrome surfaces
- blue interactive accents
- monospace presentation for code-like content
- thin borders and dense information layout

The following reusable components must exist:

- `GHCard`
- `GHButton`
- `GHBadge`
- `GHInput`
- `GHBanner`
- `GHCodeBlock`
- `GHList`
- `GHStatusDot`
- `GHTabBar`

`GHDiffView` can exist as a placeholder type or preview-only component in this slice, because Git diff functionality is explicitly out of scope.

### Main Navigation

The root view uses a five-tab layout:

- Chat
- Sessions
- Git
- Files
- Settings

Only Chat, Sessions, and Settings are functional in this release. Git and Files are visible placeholders to preserve navigation shape for later phases.

The session sidebar remains the primary in-chat session switcher. The dedicated `Sessions` tab is not a second independent workflow; it is a full-screen wrapper around the same session list and session actions used by the sidebar, sharing one data model and one set of behaviors.

### Chat Experience

The chat view must provide:

- thread-based conversation rendering, not bubble chat
- distinct user and Codex message styling
- streaming content updates
- inline approval banner within the same screen
- input bar with send/loading state
- auto-scroll on new output

### Sessions

The sessions UI must allow:

- session listing
- session creation
- session switching
- active session highlighting

### Settings

Settings must support:

- direct LAN mode selection
- host and port entry
- persistence of connection preferences
- basic client-side validation of required fields

## Error Handling

The first release must normalize errors into a small, consistent model.

### Connection-Level Errors

These return `ErrorEvent` with `fatal = true` and then close the connection:

- first message is not `Handshake`
- protocol version mismatch
- malformed binary frame
- protobuf decode failure

### Business-Level Errors

These return `ErrorEvent` with `fatal = false` and keep the connection open:

- session not found
- duplicate or invalid session action
- prompt sent while any session is already running on the agent
- approval response for unknown approval id
- adapter execution failure

### iOS Presentation Rules

Errors surface in exactly three places:

- connection status bar for transport state
- thread/system message area for task and session errors
- settings field validation for bad local configuration

## Testing Strategy

### Protocol

- validate code generation in Rust
- verify round-trip encode/decode of `Envelope`

### Desktop Agent

- unit tests for session CRUD and persistence
- unit tests for framing and decoding
- unit tests for `MockAdapter` event emission
- integration tests for local WebSocket handshake, command handling, and event broadcast

### iOS

- unit tests for protobuf codec
- unit tests for message dispatcher
- unit tests for `ChatViewModel`
- SwiftUI previews and state coverage for key design system components
- manual end-to-end validation against `agent --mock`

## Acceptance Criteria

This design is complete when the implemented slice can do all of the following:

1. start the Rust agent locally in `--mock` mode
2. connect the iOS app to the agent over LAN
3. create and switch sessions
4. send a prompt in the active session
5. render streamed output in the thread UI
6. show an inline approval request and submit approve or reject
7. persist sessions across agent restarts
8. recover gracefully from disconnects and show clear user-facing connection state

## Deferred Extension Points

The design intentionally leaves extension points for:

- remote `Connection Node` transport in `transport.rs`
- real `codex app-server` support in `adapter/codex_appserver.rs` and `codex/process.rs`
- CLI fallback support in `adapter/codex_cli.rs`
- later Git and file features via already-defined protobuf messages
- Android and watchOS clients generated from the same protobuf contract
