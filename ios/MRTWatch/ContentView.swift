import SwiftUI

struct ContentView: View {
    @StateObject private var bridge = WatchBridge()
    @State private var selectedSessionID: String?

    var body: some View {
        NavigationStack {
            Group {
                if shouldShowOffline {
                    OfflineView()
                } else if let approval = bridge.pendingApproval {
                    ApprovalView(request: approval) { approved in
                        bridge.sendApprovalResponse(approvalId: approval.id, approved: approved)
                    }
                } else {
                    TabView {
                        StatusCardView(state: bridge.currentState)
                            .padding(.horizontal, WatchSpacing.sm)

                        QuickActionsView(selectedSessionID: selectedSessionID) { action in
                            guard let sessionID = selectedSessionID else { return }
                            bridge.sendQuickAction(action, sessionId: sessionID)
                        }

                        SessionPickerView(
                            sessions: bridge.sessions,
                            selectedSessionID: $selectedSessionID
                        ) { sessionID in
                            bridge.selectSession(withID: sessionID)
                        }
                    }
                    .tabViewStyle(.verticalPage)
                }
            }
            .background(WatchGH.bgPrimary.ignoresSafeArea())
        }
        .background(WatchGH.bgPrimary.ignoresSafeArea())
        .onAppear {
            synchronizeSelection()
        }
        .onChange(of: bridge.sessions) {
            synchronizeSelection()
        }
    }

    private var shouldShowOffline: Bool {
        !bridge.currentState.isConnected && bridge.pendingApproval == nil && bridge.sessions.isEmpty
    }

    private func synchronizeSelection() {
        if let selectedSessionID,
           bridge.sessions.contains(where: { $0.id == selectedSessionID }) {
            bridge.selectSession(withID: selectedSessionID)
            return
        }

        guard let firstSession = bridge.sessions.first else {
            selectedSessionID = nil
            return
        }

        selectedSessionID = firstSession.id
        bridge.selectSession(withID: firstSession.id)
    }
}
