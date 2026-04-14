# Mobile Remote Terminal — Master Spec

> Version: 6.0 | Date: 2026-04  
> This is the **master spec**. Each component has its own detailed spec file for parallel development.

## Spec Index

| File | Component | Tech Stack | Can start from |
|------|-----------|------------|---------------|
| `SPEC-PROTO.md` | Protocol definitions | Protobuf | Immediately |
| `SPEC-AGENT.md` | Desktop Agent daemon | Rust | After SPEC-PROTO |
| `SPEC-NODE.md` | Connection Node server | Rust | After SPEC-PROTO |
| `SPEC-IOS.md` | iOS App | Swift / SwiftUI, GitHub design | After SPEC-PROTO |
| `SPEC-ANDROID.md` | Android App | Kotlin / Compose, GitHub design | After SPEC-PROTO |
| `SPEC-WATCHOS.md` | watchOS App | Swift / SwiftUI native | After SPEC-IOS P0 |

**Parallel development**: PROTO first, then Agent, Node, iOS, Android all in parallel. watchOS after iOS P0. Use Agent `--mock` mode for frontend dev without Codex.

---

## 1. What We're Building

A system to control AI coding agents (Codex CLI, later Claude Code) running on a desktop from a phone or Apple Watch. Three core components:

| Component | Tech | Purpose |
|-----------|------|---------|
| Desktop Agent | Rust | Daemon managing Codex, accepting connections |
| Connection Node | Rust | Lightweight relay (self-hosted or managed) |
| iOS App | Swift / SwiftUI | Remote control (GitHub style, Remodex interaction) |
| Android App | Kotlin / Compose | Remote control (same design language) |
| watchOS App | Swift / SwiftUI | Lightweight monitor + quick approve |

---

## 2. Design System: GitHub Style

All mobile apps (iOS, Android, watchOS) follow a **GitHub-inspired design language**. This section is the authoritative design reference for all client specs.

### 2.1 Design Principles

- **Information density**: Maximize useful content per screen. Developers want data, not decoration.
- **Monochrome base + accent color**: Like GitHub's UI — mostly gray scale, blue for interactive elements.
- **Code-first**: Terminal output and code diffs are first-class content. Use monospace fonts generously.
- **Dark mode first**: Default to dark theme. Light mode supported but dark is primary.
- **Minimal chrome**: Thin borders, subtle separators, no heavy shadows. Content speaks.

### 2.2 Color Tokens

```
── Dark Mode (Primary) ──
bg-primary:       #0d1117    (page background, GitHub dark bg)
bg-secondary:     #161b22    (card / surface background)
bg-tertiary:      #21262d    (elevated surface, input fields)
bg-overlay:       #30363d    (hover states, active states)

border-default:   #30363d
border-muted:     #21262d

text-primary:     #e6edf3    (main text)
text-secondary:   #8b949e    (secondary / muted text)
text-tertiary:    #6e7681    (placeholder, disabled)

── Accent Colors ──
accent-blue:      #58a6ff    (links, primary actions, active states)
accent-green:     #3fb950    (success, approve, connected)
accent-red:       #f85149    (error, reject, destructive)
accent-yellow:    #d29922    (warning, pending approval)
accent-purple:    #bc8cff    (info, agent indicator)
accent-orange:    #f0883e    (running state)

── Light Mode ──
bg-primary:       #ffffff
bg-secondary:     #f6f8fa
bg-tertiary:      #eaeef2
border-default:   #d0d7de
text-primary:     #1f2328
text-secondary:   #656d76
accent-blue:      #0969da
accent-green:     #1a7f37
accent-red:       #cf222e
accent-yellow:    #9a6700
```

### 2.3 Typography

```
Font stack (iOS):     SF Pro Text (body), SF Mono (code)
Font stack (Android): Roboto (body), JetBrains Mono (code)

Sizes:
  title-lg:   20pt / bold
  title:      17pt / semibold
  body:       15pt / regular
  body-sm:    13pt / regular
  caption:    12pt / regular
  code:       13pt / monospace
  code-sm:    11pt / monospace
```

### 2.4 Component Library (implement in each platform natively)

Each platform implements these components using native toolkit (SwiftUI / Compose) matching the GitHub style:

| Component | Description | Usage |
|-----------|-------------|-------|
| `GHCard` | Rounded rect, `bg-secondary`, 1px `border-default`, 12px radius | Session cards, status cards |
| `GHButton` | Primary (blue fill), Secondary (border only), Danger (red fill) | Send, Approve, Reject |
| `GHBadge` | Small pill, colored bg + matching text | Status badges (Running, Idle, Error) |
| `GHInput` | `bg-tertiary` fill, 6px border-radius, `border-default` border | Prompt input, settings fields |
| `GHBanner` | Full-width bar at top/bottom, colored left border | Approval request, connection status |
| `GHList` | Items separated by 1px `border-muted`, no outer border | Session list, device list, file tree |
| `GHCodeBlock` | `bg-tertiary` bg, monospace font, optional line numbers | Codex output, diffs |
| `GHAvatar` | Circle or rounded-square with icon/initial | Device icons |
| `GHTabBar` | Bottom tab bar, icons + labels, active = `accent-blue` | Main navigation |
| `GHDiffView` | Line-by-line diff with green(+)/red(-) gutter colors | Git diff display |
| `GHStatusDot` | 8px circle: green=online, yellow=pending, red=error, gray=offline | Connection & task status |

### 2.5 Interaction Patterns (Reference: Remodex)

Based on Remodex's iOS app interaction design:

**Thread-based conversation**: Messages displayed as a continuous thread (not chat bubbles). User prompts are visually distinct (left-aligned, `text-secondary` prefix "You:") but not "bubble" style. Codex output rendered as streaming text blocks with monospace font for code.

**Inline approval**: When Codex requests permission, an approval banner slides in from bottom/top within the conversation view — NOT a separate screen. Shows command preview in a `GHCodeBlock`, two buttons: Approve (green) + Reject (red). Dismisses inline after action.

**Session sidebar**: Swipe from left edge or tap hamburger to reveal session list. Current session highlighted with `accent-blue` left border. Status dot per session. Quick session creation at top.

**Streaming output**: Text appears character-by-character (or chunk-by-chunk). A blinking cursor indicator at the end of incomplete output. When complete, cursor disappears.

**Tab bar navigation**: Bottom tabs: Chat (message icon), Sessions (stack icon), Git (branch icon), Files (folder icon), Settings (gear icon).

**Pull to refresh**: Pull down on chat to manually refresh session status.

**Connection status header**: Persistent thin bar at very top showing connection state. Green dot + "Connected" / Yellow dot + "Connecting..." / Red dot + "Disconnected". Tap to see details.

---

## 3. Two Connection Modes

### Mode A: Self-Hosted Tunnel
```
Phone ──wss──► User's Server (Connection Node) ◄──wss── Desktop Agent ── Codex
```
- Multi-user, per-user token isolation. No dependency on us.

### Mode B: Managed Service
```
P2P success:   Phone ◄──── direct UDP ────► Desktop Agent ── Codex
P2P failure:   Phone ──► Our Node (relay) ◄── Desktop Agent ── Codex
```
- ICE signaling + STUN + TURN fallback. P2P preferred (zero server bandwidth).

### Connection Negotiation (Managed Mode)
1. Phone → managed Node (WebSocket)
2. Node authenticates (JWT), finds target agent
3. ICE signaling: exchange candidates
4. Attempt UDP punch-through (3s timeout)
5. Success → P2P direct (node exits data path)
6. Failure → node relays encrypted frames (bandwidth = billing point)

---

## 4. Security Model

| Layer | Tech | Detail |
|-------|------|--------|
| E2E encryption | Noise Protocol IK | All business messages E2E encrypted |
| Key exchange | QR code pairing | First pair: scan QR with Ed25519 public key |
| Key storage | OS keyring | Keychain / Keystore / keyring |
| Transport | WSS (TLS 1.3) | Defense in depth |
| Auth | JWT (managed) / Token (self-hosted) | |
| Device auth | Ed25519 signatures | Post-pairing: signed challenge |

---

## 5. Protocol Version

`Envelope.protocol_version` field. Handshake on connect. Incompatible → error + close. Current version: `1`.

---

## 6. Codex Integration Strategy

**Primary**: `codex app-server` JSON-RPC (richer API, streaming).  
**Fallback**: `codex` CLI stdin/stdout wrapping (resilient to API changes).

`AgentAdapter` trait with `CodexAppServerAdapter`, `CodexCliAdapter`, `MockAdapter`. Auto-fallback on failure.

---

## 7. Mock Mode

`./agent --mock` — no Codex process. Simulates streaming output, periodic approval requests, realistic state transitions. Enables frontend development without backend.

---

## 8. watchOS Architecture

Native Swift/SwiftUI. Dual-channel:
- **Channel A (preferred)**: Agent → iPhone → WatchConnectivity → Watch
- **Channel B (fallback)**: Agent → Connection Node ← URLSession → Watch (independent)

---

## 9. Connection Node User Isolation

```bash
./connection-node user add --name "ming"  → Token: mrt_ak_7f3a...
./connection-node user list
./connection-node user revoke --name "hong"
```
Per-user token → device isolation. CLI-managed, SQLite storage.

---

## 10. Development Phases

| Phase | Duration | What | Depends on |
|-------|----------|------|-----------|
| P0 | 4-6 weeks | Proto + Agent core + iOS App (LAN) | Nothing |
| P1 | 3-4 weeks | Connection Node (self-hosted) + Android App | P0 |
| P2 | 3-4 weeks | NAT punch-through + managed mode | P0 |
| P3 | 2-3 weeks | E2E encryption + QR pairing + Permission Guard | P0 |
| P4 | 3-4 weeks | Push + keyboard + Git + watchOS + files | P0-P3 |
| P5 | 3-4 weeks | Billing + distribution + docs | P0-P4 |

**P1, P2, P3 can run in parallel** after P0.

---

## 11. Repository Structure

```
mobile-remote-terminal/
├── Cargo.toml                          # Rust workspace
├── proto/
│   └── mrt.proto                       # Protobuf definitions (SSOT)
├── crates/
│   ├── agent/                          # Desktop Agent
│   ├── connection-node/                # Connection Node
│   └── proto-gen/                      # Generated Rust Protobuf code
├── ios/
│   ├── MRT/                            # iOS App (SwiftUI, GitHub style)
│   │   ├── DesignSystem/               # GH-style components
│   │   ├── Core/
│   │   ├── Features/
│   │   └── Resources/
│   └── MRTWatch/                       # watchOS App (native SwiftUI)
├── android/
│   └── app/                            # Android App (Compose, GitHub style)
│       ├── designsystem/               # GH-style components
│       ├── core/
│       └── features/
├── design/
│   ├── tokens.json                     # Design tokens (colors, typography, spacing)
│   └── components.md                   # Component specifications
├── scripts/
├── deploy/
├── docs/
└── specs/
```
