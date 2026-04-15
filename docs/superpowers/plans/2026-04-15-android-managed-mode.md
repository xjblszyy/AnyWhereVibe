# Android Managed Mode Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the current Android `Managed` mode dead-end by adding persisted node settings plus the minimal connection-node list/connect flow.

**Architecture:** Extend Android preferences/settings to store `node_url` and `auth_token`, then add a small connection-node client path to `ConnectionManager` that can register the phone, request the device list, and connect to a selected agent. Keep the first UI slice minimal: a dedicated device list screen or panel reachable when Managed mode is selected.

**Tech Stack:** Kotlin, Jetpack Compose, OkHttp WebSocket, protobuf-lite, existing Android JVM tests.

---

### Task 1: Persist Managed Mode Settings

**Files:**
- Modify: `android/app/src/main/java/com/mrt/app/core/storage/Preferences.kt`
- Modify: `android/app/src/main/java/com/mrt/app/features/settings/SettingsScreen.kt`
- Modify: `android/app/src/main/java/com/mrt/app/features/settings/ConnectionSettings.kt`
- Test: `android/app/src/test/java/com/mrt/app/features/...` if needed

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run targeted test to verify it fails**
- [ ] **Step 3: Add `nodeUrl` and `authToken` to `PreferenceSnapshot` and settings UI**
- [ ] **Step 4: Run targeted test/build to verify it passes**

### Task 2: Add Managed Mode Node Registration + Device List Transport

**Files:**
- Modify: `android/app/src/main/java/com/mrt/app/core/network/ConnectionManager.kt`
- Modify: `android/app/src/main/java/com/mrt/app/core/network/MessageDispatcher.kt`
- Modify: `android/app/src/main/java/com/mrt/app/core/models/...` as needed
- Test: `android/app/src/test/java/com/mrt/app/network/ConnectionManagerTest.kt`

- [ ] **Step 1: Write failing transport tests for device register ack, device list response, and connect-to-device ack**
- [ ] **Step 2: Run targeted tests to verify they fail**
- [ ] **Step 3: Implement minimal managed-mode websocket protocol**
- [ ] **Step 4: Run targeted tests to verify they pass**

### Task 3: Surface Device List In Android UI

**Files:**
- Create/Modify: `android/app/src/main/java/com/mrt/app/features/...`
- Modify: `android/app/src/main/java/com/mrt/app/navigation/AppNavigation.kt`
- Test: view-model/UI-adjacent JVM tests where practical

- [ ] **Step 1: Write the failing state/UI tests**
- [ ] **Step 2: Run targeted tests to verify they fail**
- [ ] **Step 3: Add minimal managed device list screen and connect action**
- [ ] **Step 4: Run Android unit/build verification**

