# Files Session Sandbox Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Files placeholders on iOS and Android with a session-root sandbox file browser that supports browse, read, save, create, delete, and rename.

**Architecture:** Extend the existing file protobuf contract with explicit mutations, implement all file operations directly in the Rust agent server layer using strict session-root path validation, and add thin stateful Files view models plus UI surfaces on iOS and Android. Use latest-wins request handling on clients and deterministic UI smoke fixtures for both platforms.

**Tech Stack:** Protobuf `Envelope.file_op` / `file_result`, Rust agent filesystem service, SwiftUI + XCTest/XCUITest, Kotlin/Compose + JUnit/Compose instrumentation.

---

## File Map

### Proto

- Modify: `proto/mrt.proto`
  - Add `CreateFile`, `CreateDir`, `DeletePath`, `RenamePath`, and `FileMutationAck`.
- Regenerate:
  - Rust via `proto-gen`
  - iOS generated types already consume `Mrt.pb.swift` from the existing generation flow
  - Android generated types already exist under `android/app/src/main/java/com/mrt/app/proto/mrt/`

### Agent

- Create: `crates/agent/src/files.rs`
  - Session-root sandbox path resolution and file operations.
- Modify: `crates/agent/src/lib.rs`
- Modify: `crates/agent/src/server.rs`
  - Route all `Payload::FileOp` cases and respond with `Payload::FileResult`.
- Modify: `crates/agent/src/test_support.rs`
  - File request/response helpers.
- Create: `crates/agent/tests/files_session_sandbox.rs`
  - Integration tests for list/read/write/mutate and error codes.

### iOS

- Create: `ios/MRT/Core/Models/FileModels.swift`
- Modify: `ios/MRT/Core/Network/ConnectionManager.swift`
- Create: `ios/MRT/Features/Files/FilesViewModel.swift`
- Create: `ios/MRT/Features/Files/FilesScreen.swift`
- Modify: `ios/MRT/ContentView.swift`
- Modify: `ios/MRT/MRTApp.swift`
  - Deterministic `MRT_UI_SMOKE_FILES` fixture.
- Modify: `ios/MRTTests/TestSupport/TestDoubles.swift`
- Create: `ios/MRTTests/Features/FilesViewModelTests.swift`
- Modify: `ios/MRTTests/Network/ConnectionManagerTests.swift`
- Create: `ios/MRTUITests/FilesUITests.swift`
- Modify: `ios/MRT.xcodeproj/project.pbxproj`
- Modify: `scripts/test-ios.sh`
- Modify: `scripts/e2e-ios-ui.sh`

### Android

- Create: `android/app/src/main/java/com/mrt/app/core/models/FileModels.kt`
- Modify: `android/app/src/main/java/com/mrt/app/core/network/ConnectionManager.kt`
- Create: `android/app/src/main/java/com/mrt/app/features/files/FilesViewModel.kt`
- Create: `android/app/src/main/java/com/mrt/app/features/files/FilesScreen.kt`
- Modify: `android/app/src/main/java/com/mrt/app/navigation/AppNavigation.kt`
- Modify: `android/app/src/test/java/com/mrt/app/features/ChatViewModelTest.kt`
  - Extend fake `ConnectionManaging`.
- Create: `android/app/src/test/java/com/mrt/app/features/files/FilesViewModelTest.kt`
- Modify: `android/app/src/test/java/com/mrt/app/network/ConnectionManagerTest.kt`
- Modify: `android/app/src/androidTest/java/com/mrt/app/features/chat/ChatScreenInstrumentedTest.kt`
  - Extend fake `ConnectionManaging`.
- Modify: `android/app/src/androidTest/java/com/mrt/app/features/sessions/SessionsScreenInstrumentedTest.kt`
  - Extend fake `ConnectionManaging`.
- Create: `android/app/src/androidTest/java/com/mrt/app/features/files/FilesScreenInstrumentedTest.kt`
- Modify: `scripts/e2e-android-ui.sh` only if needed to ensure the new instrumentation is exercised by the existing runner.

### Docs

- Modify: `docs/SPEC-IOS.md`
- Modify: `docs/SPEC-ANDROID.md`

## Task 1: Extend File Proto Contract

**Files:**
- Modify: `proto/mrt.proto`
- Regenerate: `crates/proto-gen`, iOS generated protobufs, Android generated protobufs if needed by existing repo workflow

- [ ] **Step 1: Write the failing proto-usage test in Rust agent**

```rust
#[tokio::test]
async fn file_mutation_request_round_trips_new_proto_variants() {
    // build CreateFile/DeletePath/RenamePath envelopes
    // encode/decode
    // assert new oneof fields survive round-trip
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cargo test -p agent file_mutation_request_round_trips_new_proto_variants -- --nocapture`
Expected: FAIL because the proto fields do not exist yet.

- [ ] **Step 3: Add the new proto messages and oneof entries**

```proto
message CreateFile { string path = 1; }
message CreateDir { string path = 1; }
message DeletePath { string path = 1; bool recursive = 2; }
message RenamePath { string from_path = 1; string to_path = 2; }
message FileMutationAck { string path = 1; bool success = 2; string message = 3; }
```

- [ ] **Step 4: Regenerate protobuf outputs and ensure project compiles**

Run: `cargo test -p proto-gen --no-run`
Expected: build succeeds with updated generated code.

- [ ] **Step 5: Re-run the failing round-trip test**

Run: `cargo test -p agent file_mutation_request_round_trips_new_proto_variants -- --nocapture`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add proto/mrt.proto crates/proto-gen
git commit -m "feat: extend file operation protocol"
```

## Task 2: Agent Session-Root File Service

**Files:**
- Create: `crates/agent/src/files.rs`
- Modify: `crates/agent/src/lib.rs`
- Modify: `crates/agent/src/server.rs`
- Modify: `crates/agent/src/test_support.rs`
- Create: `crates/agent/tests/files_session_sandbox.rs`

- [ ] **Step 1: Write the failing agent tests for session and path errors**

```rust
#[tokio::test]
async fn file_list_returns_session_not_found_for_unknown_session() { /* ... */ }

#[tokio::test]
async fn file_ops_reject_out_of_bounds_paths() { /* ... */ }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cargo test -p agent --test files_session_sandbox -- --nocapture`
Expected: FAIL because file op routing does not exist yet.

- [ ] **Step 3: Write the failing list/read tests**

```rust
#[tokio::test]
async fn list_dir_returns_root_entries_sorted_dirs_first() { /* ... */ }

#[tokio::test]
async fn read_file_returns_text_content_for_small_text_file() { /* ... */ }

#[tokio::test]
async fn read_file_rejects_large_or_binary_files() { /* ... */ }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cargo test -p agent --test files_session_sandbox -- --nocapture`
Expected: FAIL on list/read cases.

- [ ] **Step 5: Write the failing mutation tests**

```rust
#[tokio::test]
async fn write_file_saves_existing_text_file() { /* ... */ }

#[tokio::test]
async fn create_file_and_create_dir_return_mutation_ack() { /* ... */ }

#[tokio::test]
async fn delete_requires_recursive_for_non_empty_dirs() { /* ... */ }

#[tokio::test]
async fn rename_rejects_existing_destination() { /* ... */ }
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cargo test -p agent --test files_session_sandbox -- --nocapture`
Expected: FAIL on mutation cases.

- [ ] **Step 7: Implement strict session-root file service in `crates/agent/src/files.rs`**

```rust
pub struct FileService;

impl FileService {
    // resolve session root
    // normalize relative paths
    // reject absolute/. /.. / escapes
    // list/read/write/create/delete/rename
}
```

- [ ] **Step 8: Route `Payload::FileOp` in `crates/agent/src/server.rs`**

```rust
Some(Payload::FileOp(file_op)) => {
    route_file_operation(state, write, envelope.request_id, file_op).await?;
    Ok(false)
}
```

- [ ] **Step 9: Add request/response helpers in `crates/agent/src/test_support.rs`**

```rust
pub async fn send_list_dir(...)
pub async fn send_read_file(...)
pub async fn send_write_file(...)
pub async fn send_create_file(...)
pub async fn send_create_dir(...)
pub async fn send_delete_path(...)
pub async fn send_rename_path(...)
```

- [ ] **Step 10: Re-run the full file sandbox test suite**

Run: `cargo test -p agent --test files_session_sandbox -- --nocapture`
Expected: PASS for all list/read/write/mutate/error tests.

- [ ] **Step 11: Commit**

```bash
git add crates/agent/src/files.rs crates/agent/src/lib.rs crates/agent/src/server.rs crates/agent/src/test_support.rs crates/agent/tests/files_session_sandbox.rs
git commit -m "feat: add agent file sandbox service"
```

## Task 3: iOS File Transport and View Model

**Files:**
- Create: `ios/MRT/Core/Models/FileModels.swift`
- Modify: `ios/MRT/Core/Network/ConnectionManager.swift`
- Modify: `ios/MRTTests/TestSupport/TestDoubles.swift`
- Modify: `ios/MRTTests/Network/ConnectionManagerTests.swift`
- Create: `ios/MRT/Features/Files/FilesViewModel.swift`
- Create: `ios/MRTTests/Features/FilesViewModelTests.swift`
- Modify: `scripts/test-ios.sh`

- [ ] **Step 1: Write the failing iOS transport tests for file requests**

```swift
func testConnectionManagerSendsListDirOperation() async throws { /* ... */ }
func testConnectionManagerSendsReadFileOperation() async throws { /* ... */ }
func testConnectionManagerSendsCreateDeleteRenameOperations() async throws { /* ... */ }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/test-ios.sh`
Expected: FAIL because file APIs do not exist yet.

- [ ] **Step 3: Add file request APIs to `ConnectionManager.swift`**

```swift
func listDirectory(sessionID: String, path: String) async throws -> String
func readFile(sessionID: String, path: String) async throws -> String
func writeFile(sessionID: String, path: String, content: Data) async throws -> String
func createFile(sessionID: String, path: String) async throws -> String
func createDirectory(sessionID: String, path: String) async throws -> String
func deletePath(sessionID: String, path: String, recursive: Bool) async throws -> String
func renamePath(sessionID: String, from: String, to: String) async throws -> String
```

- [ ] **Step 4: Write the failing Files view-model tests**

```swift
@MainActor
func testFilesViewModelLoadsRootDirectory() async throws { /* ... */ }

@MainActor
func testFilesViewModelOpensTextFileAndSavesChanges() async throws { /* ... */ }

@MainActor
func testFilesViewModelHandlesCreateRenameDelete() async throws { /* ... */ }

@MainActor
func testFilesViewModelShowsUnsupportedStateForBinaryFile() async throws { /* ... */ }
```

- [ ] **Step 5: Run them to verify they fail**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/test-ios.sh`
Expected: FAIL because Files view model does not exist.

- [ ] **Step 6: Implement `FileModels.swift` and `FilesViewModel.swift`**

```swift
// path bar + entries + file editor state + mutation state
// latest-wins request correlation on directory/file/mutation loads
```

- [ ] **Step 7: Extend test doubles to emit file results**

```swift
func emitDirListing(...)
func emitFileContent(...)
func emitFileWriteAck(...)
func emitFileMutationAck(...)
func emitFileError(...)
```

- [ ] **Step 8: Re-run the targeted iOS tests**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/test-ios.sh`
Expected: PASS including `MRTTests/FilesViewModelTests`.

- [ ] **Step 9: Commit**

```bash
git add ios/MRT/Core/Models/FileModels.swift ios/MRT/Core/Network/ConnectionManager.swift ios/MRT/Features/Files/FilesViewModel.swift ios/MRTTests/Features/FilesViewModelTests.swift ios/MRTTests/Network/ConnectionManagerTests.swift ios/MRTTests/TestSupport/TestDoubles.swift scripts/test-ios.sh
git commit -m "feat: add ios file transport and view model"
```

## Task 4: iOS Files Screen and UI Smoke

**Files:**
- Create: `ios/MRT/Features/Files/FilesScreen.swift`
- Modify: `ios/MRT/ContentView.swift`
- Modify: `ios/MRT/MRTApp.swift`
- Create: `ios/MRTUITests/FilesUITests.swift`
- Modify: `ios/MRT.xcodeproj/project.pbxproj`
- Modify: `scripts/e2e-ios-ui.sh`

- [ ] **Step 1: Write the failing iOS Files UI smoke**

```swift
func testFilesTabBrowsesDirectoryAndSavesTextFile() throws {
    let app = XCUIApplication()
    app.launchArguments += ["MRT_UI_SMOKE_FILES"]
    app.launch()
    // open Files tab
    // enter subdirectory
    // open file
    // edit/save
    // assert updated content
}
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/e2e-ios-ui.sh`
Expected: FAIL because Files is still a placeholder.

- [ ] **Step 3: Implement `FilesScreen.swift`**

```swift
// path bar
// list rows for dirs/files
// text editor pane
// create/rename/delete affordances
```

- [ ] **Step 4: Replace `FilesPlaceholderView` in `ContentView.swift`**

```swift
case .files:
    FilesScreen(viewModel: filesViewModel)
```

- [ ] **Step 5: Add deterministic `MRT_UI_SMOKE_FILES` fixture in `MRTApp.swift`**

```swift
// active session rooted in a temporary fixture tree
// one subdirectory
// one text file with editable content
// predictable mutation acknowledgments
```

- [ ] **Step 6: Re-run iOS UI smoke**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/e2e-ios-ui.sh`
Expected: PASS including the Files smoke.

- [ ] **Step 7: Commit**

```bash
git add ios/MRT/Features/Files/FilesScreen.swift ios/MRT/ContentView.swift ios/MRT/MRTApp.swift ios/MRTUITests/FilesUITests.swift ios/MRT.xcodeproj/project.pbxproj scripts/e2e-ios-ui.sh
git commit -m "feat: add ios files screen"
```

## Task 5: Android File Transport and View Model

**Files:**
- Create: `android/app/src/main/java/com/mrt/app/core/models/FileModels.kt`
- Modify: `android/app/src/main/java/com/mrt/app/core/network/ConnectionManager.kt`
- Create: `android/app/src/main/java/com/mrt/app/features/files/FilesViewModel.kt`
- Create: `android/app/src/test/java/com/mrt/app/features/files/FilesViewModelTest.kt`
- Modify: `android/app/src/test/java/com/mrt/app/network/ConnectionManagerTest.kt`
- Modify: `android/app/src/test/java/com/mrt/app/features/ChatViewModelTest.kt`

- [ ] **Step 1: Write the failing Android file transport tests**

```kotlin
@Test fun connectionManagerSendsListDirOperation() = runBlocking { /* ... */ }
@Test fun connectionManagerSendsFileMutationOperations() = runBlocking { /* ... */ }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.mrt.app.network.ConnectionManagerTest`
Expected: FAIL because file APIs do not exist yet.

- [ ] **Step 3: Write the failing Files view-model tests**

```kotlin
@Test fun filesViewModelLoadsRootDirectory() = runTest { /* ... */ }
@Test fun filesViewModelOpensTextFileAndSavesChanges() = runTest { /* ... */ }
@Test fun filesViewModelHandlesCreateRenameDelete() = runTest { /* ... */ }
@Test fun filesViewModelShowsUnsupportedStateForBinaryFile() = runTest { /* ... */ }
```

- [ ] **Step 4: Run them to verify they fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.mrt.app.features.files.FilesViewModelTest`
Expected: FAIL because the view model does not exist.

- [ ] **Step 5: Implement Android file request APIs and models**

```kotlin
// listDirectory, readFile, writeFile, createFile, createDirectory, deletePath, renamePath
// FileModels.kt + FilesViewModel.kt latest-wins state machine
```

- [ ] **Step 6: Re-run Android unit tests**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: PASS including new Files tests.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/java/com/mrt/app/core/models/FileModels.kt android/app/src/main/java/com/mrt/app/core/network/ConnectionManager.kt android/app/src/main/java/com/mrt/app/features/files/FilesViewModel.kt android/app/src/test/java/com/mrt/app/features/files/FilesViewModelTest.kt android/app/src/test/java/com/mrt/app/network/ConnectionManagerTest.kt android/app/src/test/java/com/mrt/app/features/ChatViewModelTest.kt
git commit -m "feat: add android file transport and view model"
```

## Task 6: Android Files Screen and Instrumentation

**Files:**
- Create: `android/app/src/main/java/com/mrt/app/features/files/FilesScreen.kt`
- Modify: `android/app/src/main/java/com/mrt/app/navigation/AppNavigation.kt`
- Modify: `android/app/src/androidTest/java/com/mrt/app/features/chat/ChatScreenInstrumentedTest.kt`
- Modify: `android/app/src/androidTest/java/com/mrt/app/features/sessions/SessionsScreenInstrumentedTest.kt`
- Create: `android/app/src/androidTest/java/com/mrt/app/features/files/FilesScreenInstrumentedTest.kt`

- [ ] **Step 1: Write the failing Android Files instrumentation smoke**

```kotlin
@Test
fun filesScreenBrowsesDirectoryAndSavesTextFile() {
    // fake file tree
    // open dir
    // open file
    // save mutation
}
```

- [ ] **Step 2: Run instrumentation compile step to verify it fails**

Run: `cd android && ./gradlew :app:assembleDebugAndroidTest`
Expected: FAIL or missing references because FilesScreen does not exist.

- [ ] **Step 3: Implement `FilesScreen.kt`**

```kotlin
// path bar
// directory list
// editor pane
// create/rename/delete controls
```

- [ ] **Step 4: Replace `FilesPlaceholderScreen` in `AppNavigation.kt`**

```kotlin
AppDestination.Files -> FilesScreen(...)
```

- [ ] **Step 5: Re-run Android instrumentation runner**

Run: `MRT_ANDROID_SDK_ROOT=/usr/local/share/android-commandlinetools MRT_ANDROID_SYSTEM_IMAGE='system-images;android-35;google_atd;arm64-v8a' bash scripts/e2e-android-ui.sh`
Expected: PASS with Files instrumentation included.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/com/mrt/app/features/files/FilesScreen.kt android/app/src/main/java/com/mrt/app/navigation/AppNavigation.kt android/app/src/androidTest/java/com/mrt/app/features/files/FilesScreenInstrumentedTest.kt android/app/src/androidTest/java/com/mrt/app/features/chat/ChatScreenInstrumentedTest.kt android/app/src/androidTest/java/com/mrt/app/features/sessions/SessionsScreenInstrumentedTest.kt
git commit -m "feat: add android files screen"
```

## Task 7: Final Verification and Doc Alignment

**Files:**
- Modify: `docs/SPEC-IOS.md`
- Modify: `docs/SPEC-ANDROID.md`

- [ ] **Step 1: Update platform specs to reflect the Files slice**

```markdown
- Files tab now supports session-root sandbox browsing and editing.
- Search, upload/download, and batch operations remain deferred.
```

- [ ] **Step 2: Run Rust verification**

Run: `cargo test -p agent`
Expected: PASS

- [ ] **Step 3: Run Android unit verification**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Run Android instrumentation verification**

Run: `MRT_ANDROID_SDK_ROOT=/usr/local/share/android-commandlinetools MRT_ANDROID_SYSTEM_IMAGE='system-images;android-35;google_atd;arm64-v8a' bash scripts/e2e-android-ui.sh`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Run iOS targeted tests**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/test-ios.sh`
Expected: TEST SUCCEEDED

- [ ] **Step 6: Run iOS UI smoke**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/e2e-ios-ui.sh`
Expected: TEST SUCCEEDED

- [ ] **Step 7: Run hygiene checks**

Run: `git diff --check`
Expected: no output

- [ ] **Step 8: Commit**

```bash
git add docs/SPEC-IOS.md docs/SPEC-ANDROID.md
git commit -m "docs: align mobile specs with files sandbox slice"
```
