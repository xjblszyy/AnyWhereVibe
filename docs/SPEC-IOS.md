# SPEC-IOS — iOS App

> Language: Swift / SwiftUI (Native)  
> Design: GitHub style (see Master SPEC §2)  
> Interaction reference: Remodex (github.com/Emanuele-web04/remodex)  
> Dependency: SPEC-PROTO  
> Location: `ios/MRT/`  
> Duration: P0 2-3 weeks (core), P1/P3/P4 incremental

---

## Overview

Native SwiftUI iOS app. GitHub-inspired design language. Remodex-style interaction: thread-based conversation, inline approval banners, session sidebar, streaming output.

Current implemented slice note:
- Chat, Sessions, Settings, and a read-only Git surface are implemented.
- The current Git slice is worktree-first status plus single-file diff only.
- Git write operations remain deferred to later phases.

---

## File Structure

```
ios/MRT/
├── MRT.xcodeproj
├── MRT/
│   ├── MRTApp.swift
│   ├── ContentView.swift                    # Root: TabBar + session sidebar
│   │
│   ├── DesignSystem/                        # GitHub-style component library
│   │   ├── Theme.swift                      # Color tokens, typography, spacing
│   │   ├── Components/
│   │   │   ├── GHCard.swift
│   │   │   ├── GHButton.swift
│   │   │   ├── GHBadge.swift
│   │   │   ├── GHInput.swift
│   │   │   ├── GHBanner.swift
│   │   │   ├── GHCodeBlock.swift
│   │   │   ├── GHList.swift
│   │   │   ├── GHDiffView.swift
│   │   │   ├── GHStatusDot.swift
│   │   │   └── GHTabBar.swift
│   │   └── Modifiers/
│   │       ├── CardStyle.swift              # .ghCard() modifier
│   │       └── CodeStyle.swift              # .ghCode() modifier
│   │
│   ├── Core/
│   │   ├── Proto/
│   │   │   └── Mrt.pb.swift                 # Generated
│   │   ├── Network/
│   │   │   ├── WebSocketClient.swift
│   │   │   ├── ProtobufCodec.swift
│   │   │   ├── ConnectionManager.swift
│   │   │   └── MessageDispatcher.swift
│   │   ├── Crypto/                          # P3
│   │   │   ├── NoiseSession.swift
│   │   │   └── KeyManager.swift
│   │   ├── Models/
│   │   │   ├── ChatMessage.swift
│   │   │   ├── SessionModel.swift
│   │   │   └── DeviceModel.swift
│   │   └── Storage/
│   │       └── Preferences.swift
│   │
│   ├── Features/
│   │   ├── Chat/
│   │   │   ├── ChatView.swift               # Thread-based conversation
│   │   │   ├── ChatViewModel.swift
│   │   │   ├── ThreadMessageView.swift      # Single message in thread
│   │   │   ├── StreamingTextView.swift      # Animated streaming text
│   │   │   ├── ApprovalBannerView.swift     # Inline approval (Remodex style)
│   │   │   └── ConnectionStatusBar.swift    # Top status bar
│   │   ├── Sessions/
│   │   │   ├── SessionSidebarView.swift     # Swipe-from-left sidebar
│   │   │   ├── SessionRowView.swift
│   │   │   └── SessionViewModel.swift
│   │   ├── Devices/                         # P1
│   │   │   ├── DeviceListView.swift
│   │   │   └── DeviceListViewModel.swift
│   │   ├── Git/                             # P4
│   │   │   ├── GitStatusView.swift
│   │   │   ├── GitDiffView.swift
│   │   │   ├── GitCommitView.swift
│   │   │   └── GitViewModel.swift
│   │   ├── Files/                           # P4
│   │   │   ├── FileBrowserView.swift
│   │   │   ├── CodeViewerView.swift
│   │   │   └── FilesViewModel.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       ├── ConnectionSettingsView.swift
│   │       └── PairDeviceView.swift         # P3: QR scanner
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── Fonts/                           # SF Mono bundled for code
│
├── MRTWatch/                                # See SPEC-WATCHOS
└── MRTTests/
```

SPM Dependencies:
- `apple/swift-protobuf`
- `daltoniam/Starscream` (WebSocket)
- `gonzalezreal/swift-markdown-ui` (optional, for rendering markdown in Codex output)

---

## Design System Implementation

### IOS-DS01: Theme.swift

```swift
// DesignSystem/Theme.swift
import SwiftUI

struct GHColors {
    // Dark mode (primary)
    static let bgPrimary = Color(hex: "0d1117")
    static let bgSecondary = Color(hex: "161b22")
    static let bgTertiary = Color(hex: "21262d")
    static let bgOverlay = Color(hex: "30363d")

    static let borderDefault = Color(hex: "30363d")
    static let borderMuted = Color(hex: "21262d")

    static let textPrimary = Color(hex: "e6edf3")
    static let textSecondary = Color(hex: "8b949e")
    static let textTertiary = Color(hex: "6e7681")

    static let accentBlue = Color(hex: "58a6ff")
    static let accentGreen = Color(hex: "3fb950")
    static let accentRed = Color(hex: "f85149")
    static let accentYellow = Color(hex: "d29922")
    static let accentPurple = Color(hex: "bc8cff")
    static let accentOrange = Color(hex: "f0883e")
}

struct GHTypography {
    static let titleLg = Font.system(size: 20, weight: .bold)
    static let title = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15)
    static let bodySm = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let code = Font.system(size: 13, design: .monospaced)
    static let codeSm = Font.system(size: 11, design: .monospaced)
}

struct GHSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
```

### IOS-DS02: Core Components

**GHCard**:
```swift
struct GHCard<Content: View>: View {
    let content: () -> Content
    var body: some View {
        content()
            .padding(GHSpacing.lg)
            .background(GHColors.bgSecondary)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GHColors.borderDefault, lineWidth: 1))
    }
}
```

**GHButton**:
```swift
enum GHButtonStyle { case primary, secondary, danger }

struct GHButton: View {
    let title: String
    let icon: String?
    let style: GHButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GHSpacing.sm) {
                if let icon { Image(systemName: icon).font(.system(size: 14)) }
                Text(title).font(GHTypography.bodySm).fontWeight(.medium)
            }
            .padding(.horizontal, GHSpacing.md)
            .padding(.vertical, GHSpacing.sm)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: style == .secondary ? 1 : 0)
            )
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return GHColors.accentBlue.opacity(0.15)
        case .secondary: return .clear
        case .danger: return GHColors.accentRed.opacity(0.15)
        }
    }
    private var foregroundColor: Color {
        switch style {
        case .primary: return GHColors.accentBlue
        case .secondary: return GHColors.textSecondary
        case .danger: return GHColors.accentRed
        }
    }
    private var borderColor: Color {
        style == .secondary ? GHColors.borderDefault : .clear
    }
}
```

**GHBadge**:
```swift
struct GHBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(GHTypography.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(10)
    }
}

// Usage: GHBadge(text: "Running", color: GHColors.accentOrange)
```

**GHCodeBlock**:
```swift
struct GHCodeBlock: View {
    let code: String
    let language: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(GHTypography.code)
                .foregroundColor(GHColors.textPrimary)
                .padding(GHSpacing.md)
        }
        .background(GHColors.bgTertiary)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(GHColors.borderDefault, lineWidth: 1))
    }
}
```

**GHStatusDot**:
```swift
struct GHStatusDot: View {
    enum Status { case online, pending, error, offline }
    let status: Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .online: return GHColors.accentGreen
        case .pending: return GHColors.accentYellow
        case .error: return GHColors.accentRed
        case .offline: return GHColors.textTertiary
        }
    }
}
```

Implement all remaining components (`GHBanner`, `GHInput`, `GHList`, `GHDiffView`, `GHTabBar`) following the same patterns.

**Acceptance**: All GH components render correctly in dark mode. Screenshots match GitHub's visual style.

---

## P0 Tasks

### IOS-T01: Project Setup

Steps:
1. Create Xcode project "MRT", deployment target iOS 17, SwiftUI lifecycle.
2. Add SPM: `swift-protobuf`, `Starscream`.
3. Generate and add `Mrt.pb.swift`.
4. Create full folder structure.
5. Implement `Theme.swift` and all `DesignSystem/Components/`.
6. Set up `ContentView.swift`: `GHTabBar` with 5 tabs (Chat, Sessions, Git, Files, Settings).
7. Set `preferredColorScheme(.dark)` as default.

**Acceptance**: App launches in dark mode with GitHub-style tab bar. All GH components available.

---

### IOS-T02: Network Layer

Same as previous SPEC-IOS (WebSocketClient, ProtobufCodec, ConnectionManager, MessageDispatcher). No design changes — this is pure infrastructure.

**Acceptance**: Can connect to agent, send/receive Protobuf Envelopes.

---

### IOS-T03: Chat View (Remodex-style Thread)

This is the core view. Reference Remodex's thread-based conversation UX.

```swift
// Features/Chat/ChatView.swift
struct ChatView: View {
    @StateObject var vm: ChatViewModel
    @State private var showSessionSidebar = false

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                // ── Connection status bar ──
                ConnectionStatusBar(state: vm.connectionState)

                // ── Thread messages ──
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(vm.messages) { msg in
                                ThreadMessageView(message: msg)
                                Divider().background(GHColors.borderMuted)
                            }
                        }
                    }
                    .onChange(of: vm.messages.count) {
                        withAnimation { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) }
                    }
                }

                // ── Inline approval banner ──
                if let approval = vm.pendingApproval {
                    ApprovalBannerView(
                        request: approval,
                        onApprove: { vm.respondApproval(true) },
                        onReject: { vm.respondApproval(false) }
                    )
                }

                // ── Input bar ──
                PromptInputBar(
                    text: $vm.inputText,
                    isLoading: vm.isLoading,
                    onSend: vm.sendPrompt
                )
            }
            .background(GHColors.bgPrimary)

            // ── Session sidebar (swipe from left) ──
            if showSessionSidebar {
                SessionSidebarView(
                    sessions: vm.sessions,
                    activeId: vm.activeSessionId,
                    onSelect: { id in vm.switchSession(id); showSessionSidebar = false },
                    onCreate: { name in vm.createSession(name) }
                )
                .transition(.move(edge: .leading))
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 80 { withAnimation { showSessionSidebar = true } }
                    if value.translation.width < -80 { withAnimation { showSessionSidebar = false } }
                }
        )
    }
}
```

### IOS-T04: Thread Message View

```swift
// Features/Chat/ThreadMessageView.swift
struct ThreadMessageView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            // ── Header: role + timestamp ──
            HStack(spacing: GHSpacing.sm) {
                roleIcon
                Text(message.role == .user ? "You" : "Codex")
                    .font(GHTypography.bodySm)
                    .fontWeight(.semibold)
                    .foregroundColor(message.role == .user ? GHColors.textPrimary : GHColors.accentPurple)
                Spacer()
                Text(message.timeAgo)
                    .font(GHTypography.caption)
                    .foregroundColor(GHColors.textTertiary)
            }

            // ── Content ──
            if message.role == .codex {
                // Codex output: render as code-aware text
                CodexOutputView(content: message.content, isStreaming: !message.isComplete)
            } else {
                Text(message.content)
                    .font(GHTypography.body)
                    .foregroundColor(GHColors.textPrimary)
            }
        }
        .padding(.horizontal, GHSpacing.lg)
        .padding(.vertical, GHSpacing.md)
    }

    private var roleIcon: some View {
        Image(systemName: message.role == .user ? "person.fill" : "cpu")
            .font(.system(size: 12))
            .foregroundColor(message.role == .user ? GHColors.textSecondary : GHColors.accentPurple)
            .frame(width: 20, height: 20)
            .background(GHColors.bgTertiary)
            .cornerRadius(4)
    }
}
```

### IOS-T05: Streaming Text View

```swift
// Features/Chat/StreamingTextView.swift
struct CodexOutputView: View {
    let content: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            // Parse content: detect code blocks (```...```) vs plain text
            ForEach(parseBlocks(content), id: \.id) { block in
                switch block.type {
                case .text:
                    Text(block.content)
                        .font(GHTypography.body)
                        .foregroundColor(GHColors.textPrimary)
                case .code(let lang):
                    GHCodeBlock(code: block.content, language: lang)
                }
            }

            // Streaming cursor
            if isStreaming {
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(GHColors.accentBlue)
                        .frame(width: 2, height: 16)
                        .opacity(cursorOpacity)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: cursorOpacity)
                }
            }
        }
    }
}
```

### IOS-T06: Approval Banner (Remodex-style Inline)

```swift
// Features/Chat/ApprovalBannerView.swift
struct ApprovalBannerView: View {
    let request: Mrt_ApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.md) {
            // ── Header ──
            HStack(spacing: GHSpacing.sm) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(GHColors.accentYellow)
                Text("Permission Required")
                    .font(GHTypography.bodySm)
                    .fontWeight(.semibold)
                    .foregroundColor(GHColors.accentYellow)
                Spacer()
                GHBadge(text: request.approvalType.displayName, color: GHColors.accentYellow)
            }

            // ── Description ──
            Text(request.description_p)
                .font(GHTypography.bodySm)
                .foregroundColor(GHColors.textSecondary)

            // ── Command preview ──
            if !request.command.isEmpty {
                GHCodeBlock(code: request.command, language: "bash")
                    .frame(maxHeight: 80)
            }

            // ── Action buttons ──
            HStack(spacing: GHSpacing.md) {
                GHButton(title: "Reject", icon: "xmark", style: .danger, action: onReject)
                GHButton(title: "Approve", icon: "checkmark", style: .primary, action: onApprove)
            }
        }
        .padding(GHSpacing.lg)
        .background(GHColors.bgSecondary)
        .overlay(
            Rectangle().fill(GHColors.accentYellow).frame(width: 3),
            alignment: .leading
        )
        .overlay(
            Rectangle().fill(GHColors.borderDefault).frame(height: 1),
            alignment: .top
        )
    }
}
```

### IOS-T07: Session Sidebar

```swift
// Features/Sessions/SessionSidebarView.swift
struct SessionSidebarView: View {
    let sessions: [SessionModel]
    let activeId: String?
    let onSelect: (String) -> Void
    let onCreate: (String) -> Void
    @State private var newSessionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──
            HStack {
                Text("Sessions")
                    .font(GHTypography.title)
                    .foregroundColor(GHColors.textPrimary)
                Spacer()
            }
            .padding(GHSpacing.lg)

            // ── New session ──
            HStack(spacing: GHSpacing.sm) {
                GHInput(text: $newSessionName, placeholder: "New session...")
                GHButton(title: "", icon: "plus", style: .primary) {
                    guard !newSessionName.isEmpty else { return }
                    onCreate(newSessionName)
                    newSessionName = ""
                }
            }
            .padding(.horizontal, GHSpacing.lg)
            .padding(.bottom, GHSpacing.md)

            Divider().background(GHColors.borderMuted)

            // ── Session list ──
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            isActive: session.id == activeId,
                            onTap: { onSelect(session.id) }
                        )
                        Divider().background(GHColors.borderMuted)
                    }
                }
            }
        }
        .frame(width: 280)
        .background(GHColors.bgSecondary)
        .overlay(Rectangle().fill(GHColors.borderDefault).frame(width: 1), alignment: .trailing)
    }
}
```

### IOS-T08: Connection Status Bar

```swift
// Features/Chat/ConnectionStatusBar.swift
struct ConnectionStatusBar: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: GHSpacing.sm) {
            GHStatusDot(status: dotStatus)
            Text(statusText)
                .font(GHTypography.caption)
                .foregroundColor(GHColors.textSecondary)
            Spacer()
            if let agentName = agentName {
                Text(agentName)
                    .font(GHTypography.caption)
                    .foregroundColor(GHColors.textTertiary)
            }
        }
        .padding(.horizontal, GHSpacing.lg)
        .padding(.vertical, GHSpacing.xs)
        .background(GHColors.bgSecondary)
        .overlay(Rectangle().fill(GHColors.borderMuted).frame(height: 1), alignment: .bottom)
    }
}
```

### IOS-T09: Prompt Input Bar

```swift
// Part of Chat/ChatView.swift or separate file
struct PromptInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(GHColors.borderDefault)
            HStack(spacing: GHSpacing.md) {
                TextField("Send a prompt to Codex...", text: $text, axis: .vertical)
                    .font(GHTypography.body)
                    .foregroundColor(GHColors.textPrimary)
                    .lineLimit(1...5)
                    .padding(GHSpacing.md)
                    .background(GHColors.bgTertiary)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(GHColors.borderDefault, lineWidth: 1))

                Button(action: onSend) {
                    Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(canSend ? GHColors.bgPrimary : GHColors.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(canSend ? GHColors.accentBlue : GHColors.bgTertiary)
                        .cornerRadius(8)
                }
                .disabled(!canSend && !isLoading)
            }
            .padding(GHSpacing.md)
            .background(GHColors.bgPrimary)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}
```

### IOS-T10: ChatViewModel

Same logic as previous SPEC-IOS `ChatViewModel` — no changes in business logic, only the view layer is redesigned.

### IOS-T11: Settings (GitHub style)

```swift
struct SettingsView: View {
    @AppStorage("connectionMode") var mode: ConnectionMode = .direct
    @AppStorage("directHost") var directHost: String = ""
    @AppStorage("nodeURL") var nodeURL: String = ""
    @AppStorage("authToken") var authToken: String = ""
    @AppStorage("managedTargetDeviceID") var managedTargetDeviceID: String = ""
    @AppStorage("managedTargetDeviceName") var managedTargetDeviceName: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GHSpacing.lg) {
                Text("Settings")
                    .font(GHTypography.titleLg)
                    .foregroundColor(GHColors.textPrimary)

                // Connection mode
                GHCard {
                    VStack(alignment: .leading, spacing: GHSpacing.md) {
                        Text("Connection").font(GHTypography.title).foregroundColor(GHColors.textPrimary)
                        Picker("Mode", selection: $mode) {
                            Text("Direct (LAN)").tag(ConnectionMode.direct)
                            Text("Managed").tag(ConnectionMode.managed)
                        }
                        .pickerStyle(.segmented)

                        if mode == .direct {
                            GHInput(text: $directHost, placeholder: "192.168.1.100")
                            GHInput(text: $directPort, placeholder: "9876")
                        } else {
                            GHInput(text: $nodeURL, placeholder: "wss://your-server.com/ws")
                            GHInput(text: $authToken, placeholder: "Auth Token")
                            // Inline relay-first device list from DeviceListResponse
                        }
                    }
                }
            }
            .padding(GHSpacing.lg)
        }
        .background(GHColors.bgPrimary)
    }
}
```

Current relay-first managed slice:
- Saving managed settings registers the phone with the Connection Node using `DeviceRegister`.
- The settings screen fetches the current online agent list with `DeviceListRequest`.
- Selecting an agent sends `ConnectToDevice`, then the app starts the normal phone handshake over the relay after `ConnectToDeviceAck(success)`.
- ICE/P2P, QR pairing, and Noise remain later phases.

**Acceptance for all P0**: App connects to mock agent → thread-based chat with GitHub styling → streaming output with cursor → inline approval banner → session sidebar with create/switch → settings with connection config. Dark mode throughout. Visually consistent with GitHub's UI language.

---

## P1 Tasks

### IOS-T12: Device List (Connection Node Mode)

GitHub-style list of online agents. `GHStatusDot` for online state. Tap to connect.

Current relay-first slice:
- The device list is rendered inline in settings, not a separate screen yet.
- The selected agent is persisted so managed mode can reconnect on launch.

### IOS-T13: Connection Node Protocol

Modify ConnectionManager: register device, list devices, connect to specific agent.

## P3 Tasks

### IOS-T14: QR Code Pairing

Camera scanner view. Parse QR → exchange keys → store in Keychain. GitHub-style confirmation card.

### IOS-T15: Noise Protocol E2E

NoiseSwift integration. All Envelopes encrypted before sending.

## P4 Tasks

### IOS-T16: Push Notifications (APNs)

Notification actions: approve/reject directly from notification.

### IOS-T17: Extended Keyboard

Custom `InputAccessoryView` with GitHub-style dark buttons. Tab, Esc, Ctrl, arrows, |, /, ~, `.

### IOS-T18: Git Feature

`GitStatusView`: file change list with `GHBadge` (modified/added/deleted). `GitDiffView` using `GHDiffView` component with green/red gutter. Commit form with `GHInput` + `GHButton`.

### IOS-T19: File Browser

File tree using `GHList`. `CodeViewerView` with `GHCodeBlock` and line numbers. Language detection for syntax hints.

### IOS-T20: WatchConnectivity Bridge

`WCSessionDelegate` implementation. Forward agent state to watchOS. Relay watch actions back to agent. See SPEC-WATCHOS.
