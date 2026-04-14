# SPEC-WATCHOS — watchOS App

> Language: Native Swift / SwiftUI (WatchKit)  
> Design: GitHub style adapted for small screen  
> Dependency: SPEC-IOS (P0 complete), SPEC-PROTO  
> Location: `ios/MRTWatch/`  
> Phase: P4  
> Duration: 1-2 weeks

---

## Overview

Native SwiftUI watchOS companion app. GitHub dark theme adapted for watch screen. Dual-channel: WatchConnectivity (preferred) + independent network (fallback).

**Watch is for**: glance at status, approve permissions, quick actions. NOT for typing prompts or browsing code.

---

## File Structure

```
ios/MRTWatch/
├── MRTWatchApp.swift
├── ContentView.swift
├── DesignSystem/
│   └── WatchTheme.swift                # GH colors adapted for watch
├── Views/
│   ├── StatusCardView.swift
│   ├── ApprovalView.swift
│   ├── QuickActionsView.swift
│   ├── SessionPickerView.swift
│   └── OfflineView.swift
├── Communication/
│   ├── WatchBridge.swift               # WatchConnectivity ↔ iPhone
│   ├── IndependentClient.swift         # URLSession WebSocket (fallback)
│   └── ChannelManager.swift
├── Complication/
│   └── TaskStatusComplication.swift
└── Models/
    ├── WatchState.swift
    └── Proto/
        └── Mrt.pb.swift                # Subset
```

---

## Watch Design Tokens

Adapted from GitHub style for small screens:

```swift
// DesignSystem/WatchTheme.swift
struct WatchGH {
    // Same colors as iOS GHColors (dark mode only on watch)
    static let bgPrimary = Color(hex: "0d1117")
    static let bgSecondary = Color(hex: "161b22")
    static let bgTertiary = Color(hex: "21262d")
    static let borderDefault = Color(hex: "30363d")

    static let textPrimary = Color(hex: "e6edf3")
    static let textSecondary = Color(hex: "8b949e")
    static let textTertiary = Color(hex: "6e7681")

    static let accentBlue = Color(hex: "58a6ff")
    static let accentGreen = Color(hex: "3fb950")
    static let accentRed = Color(hex: "f85149")
    static let accentYellow = Color(hex: "d29922")
    static let accentPurple = Color(hex: "bc8cff")
    static let accentOrange = Color(hex: "f0883e")

    // Watch-specific typography (larger for readability on small screen)
    static let title = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let code = Font.system(size: 11, design: .monospaced)
}
```

---

## Tasks

### WATCH-T01: Project Setup

1. Add watchOS target to `MRT.xcodeproj`. Target: `MRTWatch`, deployment watchOS 10.
2. Share `swift-protobuf` SPM dependency.
3. Create folder structure.
4. Implement `WatchTheme.swift`.

**Acceptance**: watchOS target compiles and runs in simulator with dark GH background.

---

### WATCH-T02: WatchConnectivity Bridge (Channel A)

```swift
// Communication/WatchBridge.swift
class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published var currentState: WatchState = .disconnected
    @Published var pendingApproval: ApprovalInfo?
    @Published var sessions: [SessionSummary] = []

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // Receive state from iPhone (applicationContext for background, sendMessage for foreground)
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        DispatchQueue.main.async {
            if let data = context["watchState"] as? Data,
               let state = try? JSONDecoder().decode(WatchState.self, from: data) {
                self.currentState = state
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            if let type = message["type"] as? String {
                switch type {
                case "approval_request":
                    self.pendingApproval = ApprovalInfo(from: message)
                case "status_update":
                    if let statusRaw = message["status"] as? Int {
                        self.currentState.taskStatus = TaskDisplayStatus(rawValue: statusRaw) ?? .idle
                    }
                    if let summary = message["summary"] as? String {
                        self.currentState.lastSummary = summary
                    }
                default: break
                }
            }
            replyHandler(["received": true])
        }
    }

    func sendApprovalResponse(approvalId: String, approved: Bool) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["type": "approval_response", "approvalId": approvalId, "approved": approved],
            replyHandler: nil
        )
    }

    func sendQuickAction(_ action: String, sessionId: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["type": "quick_action", "action": action, "sessionId": sessionId],
            replyHandler: nil
        )
    }
}
```

**iOS side counterpart** (in SPEC-IOS, task IOS-T20):
The iPhone app implements `WCSessionDelegate`, translating Watch messages → Protobuf Envelopes → WebSocket, and pushing state updates back to Watch via `updateApplicationContext`.

**Acceptance**: iPhone connected to Agent → Watch receives task status within 1-2 seconds.

---

### WATCH-T03: Independent Network Client (Channel B)

```swift
// Communication/IndependentClient.swift
class IndependentClient: ObservableObject {
    @Published var state: ConnectionState = .disconnected
    private var wsTask: URLSessionWebSocketTask?

    func connect(nodeURL: String, authToken: String, targetDeviceId: String) {
        guard let url = URL(string: "\(nodeURL)/ws?token=\(authToken)") else { return }
        wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask?.resume()
        state = .connecting
        sendRegister()
        startReceiving()
    }

    func disconnect() { wsTask?.cancel(with: .normalClosure, reason: nil) }

    func send(_ envelope: Mrt_Envelope) {
        guard let data = try? ProtobufCodec.encode(envelope) else { return }
        wsTask?.send(.data(data)) { _ in }
    }

    private func startReceiving() {
        wsTask?.receive { [weak self] result in
            if case .success(.data(let data)) = result,
               let env = try? ProtobufCodec.decode(data) {
                self?.handleEnvelope(env)
            }
            self?.startReceiving()
        }
    }

    private func handleEnvelope(_ env: Mrt_Envelope) {
        // Only handle: AgentEvent (status, approval), Heartbeat
        // Update published state
    }
}
```

**Acceptance**: iPhone app closed → Watch connects to Connection Node independently → shows agent status.

---

### WATCH-T04: Channel Manager

```swift
// Communication/ChannelManager.swift
class ChannelManager: ObservableObject {
    @Published var activeChannel: ChannelType = .none
    @Published var state: WatchState = .disconnected
    @Published var pendingApproval: ApprovalInfo?

    private let bridge = WatchBridge()
    private let independent = IndependentClient()

    enum ChannelType { case watchConnectivity, independent, none }

    func updateChannel() {
        if WCSession.default.isReachable {
            activeChannel = .watchConnectivity
            independent.disconnect()
            // State comes from bridge
        } else if let nodeURL = UserDefaults.standard.string(forKey: "nodeURL"),
                  let token = UserDefaults.standard.string(forKey: "authToken") {
            activeChannel = .independent
            independent.connect(nodeURL: nodeURL, authToken: token, targetDeviceId: "...")
        } else {
            activeChannel = .none
        }
    }

    func respondApproval(id: String, approved: Bool) {
        switch activeChannel {
        case .watchConnectivity: bridge.sendApprovalResponse(approvalId: id, approved: approved)
        case .independent: /* build Envelope, send via independent client */ break
        case .none: break
        }
    }

    func quickAction(_ action: String) { ... }
}
```

---

### WATCH-T05: Status Card View

```swift
struct StatusCardView: View {
    @EnvironmentObject var channel: ChannelManager

    var body: some View {
        VStack(spacing: 6) {
            // Connection
            HStack(spacing: 4) {
                Circle()
                    .fill(channel.activeChannel == .none ? WatchGH.textTertiary : WatchGH.accentGreen)
                    .frame(width: 6, height: 6)
                Text(channel.activeChannel == .none ? "Offline" : "Connected")
                    .font(WatchGH.caption)
                    .foregroundColor(WatchGH.textTertiary)
                Spacer()
            }

            if let session = channel.state.activeSession {
                Text(session.name)
                    .font(WatchGH.title)
                    .foregroundColor(WatchGH.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    statusIcon(session.status)
                    Text(session.status.displayText)
                        .font(WatchGH.body)
                        .foregroundColor(session.status.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let summary = session.lastSummary {
                    Text(summary)
                        .font(WatchGH.caption)
                        .foregroundColor(WatchGH.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No active task")
                    .font(WatchGH.body)
                    .foregroundColor(WatchGH.textSecondary)
            }
        }
        .padding(10)
        .background(WatchGH.bgSecondary)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func statusIcon(_ status: TaskDisplayStatus) -> some View {
        Image(systemName: status.iconName)
            .font(.system(size: 12))
            .foregroundColor(status.color)
    }
}
```

---

### WATCH-T06: Approval View

```swift
struct ApprovalView: View {
    let request: ApprovalInfo
    let onRespond: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundColor(WatchGH.accentYellow)

                Text("Permission")
                    .font(WatchGH.title)
                    .foregroundColor(WatchGH.textPrimary)

                Text(request.description)
                    .font(WatchGH.caption)
                    .foregroundColor(WatchGH.textSecondary)
                    .multilineTextAlignment(.center)

                if !request.command.isEmpty {
                    Text(request.command)
                        .font(WatchGH.code)
                        .foregroundColor(WatchGH.textPrimary)
                        .lineLimit(3)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WatchGH.bgTertiary)
                        .cornerRadius(6)
                }

                HStack(spacing: 12) {
                    Button(action: { onRespond(false) }) {
                        Image(systemName: "xmark")
                            .foregroundColor(WatchGH.accentRed)
                            .frame(width: 44, height: 44)
                            .background(WatchGH.accentRed.opacity(0.15))
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onRespond(true) }) {
                        Image(systemName: "checkmark")
                            .foregroundColor(WatchGH.accentGreen)
                            .frame(width: 44, height: 44)
                            .background(WatchGH.accentGreen.opacity(0.15))
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .onAppear { WKInterfaceDevice.current().play(.notification) }
    }
}
```

---

### WATCH-T07: Quick Actions

```swift
struct QuickActionsView: View {
    @EnvironmentObject var channel: ChannelManager

    var body: some View {
        List {
            Button { channel.quickAction("continue") } label: {
                Label("Continue", systemImage: "play.fill")
                    .foregroundColor(WatchGH.accentGreen)
            }
            Button { channel.quickAction("cancel") } label: {
                Label("Cancel", systemImage: "stop.fill")
                    .foregroundColor(WatchGH.accentRed)
            }
            Button { channel.quickAction("retry") } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .foregroundColor(WatchGH.accentBlue)
            }
        }
        .listStyle(.carousel)
    }
}
```

---

### WATCH-T08: Complication

```swift
struct TaskStatusEntry: TimelineEntry {
    let date: Date
    let status: TaskDisplayStatus
    let sessionName: String?
}

struct TaskStatusComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TaskStatus", provider: TaskStatusProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: entry.status.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(entry.status.color)
                    if let name = entry.sessionName {
                        Text(name)
                            .font(.system(size: 9))
                            .foregroundColor(WatchGH.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .configurationDisplayName("Task Status")
        .description("AI coding task status")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
```

Updates via `WCSession.transferCurrentComplicationUserInfo()` from iPhone, or `BGAppRefreshTask` every 15 min if using independent channel.

---

### WATCH-T09: Haptic Feedback

```swift
// In ChannelManager or wherever events are received
func handleEvent(_ event: WatchEvent) {
    switch event {
    case .approvalRequest:
        WKInterfaceDevice.current().play(.notification)  // distinctive double-tap
    case .taskComplete:
        WKInterfaceDevice.current().play(.success)       // gentle rising feel
    case .taskError:
        WKInterfaceDevice.current().play(.failure)       // firm tap
    case .quickActionSent:
        WKInterfaceDevice.current().play(.click)         // light tap
    }
}
```

**Acceptance**: Watch vibrates distinctly for approval (double-tap), completion (rising), error (firm).

---

### WATCH-T10: Content View + Navigation

```swift
struct ContentView: View {
    @StateObject private var channel = ChannelManager()

    var body: some View {
        NavigationStack {
            if channel.activeChannel == .none {
                OfflineView()
            } else if let approval = channel.pendingApproval {
                ApprovalView(request: approval) { approved in
                    channel.respondApproval(id: approval.id, approved: approved)
                }
            } else {
                TabView {
                    StatusCardView()
                    QuickActionsView()
                    SessionPickerView()
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .environmentObject(channel)
        .onAppear { channel.updateChannel() }
        .onChange(of: WCSession.default.isReachable) { channel.updateChannel() }
    }
}
```

Navigation: vertical page TabView. Swipe up/down between Status → Quick Actions → Session Picker. Approval view takes over when pending.

**Acceptance**: Full flow on watch: see status → receive approval notification with haptic → approve from wrist → see status update to "Running" → task completes with success haptic.
