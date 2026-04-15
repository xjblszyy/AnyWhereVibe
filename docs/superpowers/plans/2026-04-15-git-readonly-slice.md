# Git Read-Only Slice Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Git placeholders on iOS and Android with a real read-only Git surface backed by the desktop agent, showing worktree-first status plus single-file diff for the active session.

**Architecture:** The agent handles `Envelope.git_op` directly in the websocket runtime and computes repository data from the active session `working_dir`. Mobile clients remain thin: each platform adds a Git view model plus a read-only screen that requests status, selects one file, and renders the returned unified diff while enforcing latest-wins UI state. No adapter-layer Git integration or write operations are included in this slice.

**Tech Stack:** Rust agent, protobuf `Envelope.git_op` / `git_result`, SwiftUI + XCTest/XCUITest, Kotlin/Compose + JUnit/Compose instrumentation, existing GH design-system components.

---

## File Map

### Agent

- Modify: `crates/agent/Cargo.toml`
  - Add any Git/runtime dependencies needed for read-only repository inspection.
- Create: `crates/agent/src/git.rs`
  - Repo discovery, status parsing, path normalization, diff generation, and Git error mapping.
- Modify: `crates/agent/src/lib.rs`
  - Export the new Git module if needed by tests or server wiring.
- Modify: `crates/agent/src/server.rs`
  - Route `Payload::GitOp`, echo `request_id`, and send `GitResult` responses.
- Modify: `crates/agent/src/session.rs`
  - Only if small helper accessors are needed for session workdir lookup.
- Modify: `crates/agent/src/test_support.rs`
  - Add Git request/response helper builders for integration tests.
- Create: `crates/agent/tests/git_readonly.rs`
  - Integration coverage for status, diff, errors, and request/response correlation.

### iOS

- Create: `ios/MRT/Core/Models/GitModels.swift`
  - Small local presentation models for Git summary, file rows, and diff state.
- Modify: `ios/MRT/Core/Network/ConnectionManager.swift`
  - Send `GitOperation.status` / `GitOperation.diff`, route `GitResult`, and expose callbacks.
- Modify: `ios/MRT/Core/Network/MessageDispatcher.swift`
  - Only if dispatching shared Git parsing there is cleaner than in `ConnectionManager`.
- Create: `ios/MRT/Features/Git/GitViewModel.swift`
  - Worktree-first Git state machine, latest-wins request generation, session-change reset logic.
- Create: `ios/MRT/Features/Git/GitScreen.swift`
  - Summary card, changed-file list, and diff panel using existing GH components.
- Modify: `ios/MRT/ContentView.swift`
  - Replace `GitPlaceholderView` with the real Git screen and wire active session / connection manager access.
- Modify: `ios/MRT.xcodeproj/project.pbxproj`
  - Add new Git source files and new test files.
- Modify: `ios/MRT.xcodeproj/xcshareddata/xcschemes/MRT.xcscheme`
  - Include any new test targets/files if needed.
- Create: `ios/MRTTests/Features/GitViewModelTests.swift`
  - Unit coverage for unavailable, clean, dirty, diff error, and latest-wins behavior.
- Modify: `ios/MRTTests/Network/ConnectionManagerTests.swift`
  - Verify `GitOperation.status` / `GitOperation.diff` encoding and Git result decoding.
- Modify: `ios/MRTTests/TestSupport/TestDoubles.swift`
  - Add Git request recording and fake Git result emission.
- Create: `ios/MRTUITests/GitUITests.swift`
  - UI smoke for entering the Git tab, showing changed files, selecting a file, and rendering diff.
- Modify: `scripts/test-ios.sh`
  - Add `MRTTests/GitViewModelTests`.
- Modify: `scripts/e2e-ios-ui.sh`
  - Add `MRTUITests/GitUITests` or keep one target file that now includes Git smoke.

### Android

- Create: `android/app/src/main/java/com/mrt/app/core/models/GitModels.kt`
  - Small local models for Git summary, file rows, and diff state.
- Modify: `android/app/src/main/java/com/mrt/app/core/network/ConnectionManager.kt`
  - Send Git requests, decode Git results, and expose observable Git callbacks/state.
- Modify: `android/app/src/main/java/com/mrt/app/core/network/MessageDispatcher.kt`
  - Only if shared parsing there is the cleanest option.
- Create: `android/app/src/main/java/com/mrt/app/features/git/GitViewModel.kt`
  - Worktree-first Git state machine and latest-wins request generation.
- Create: `android/app/src/main/java/com/mrt/app/features/git/GitScreen.kt`
  - Summary card, changed-file list, and diff panel using existing GH components.
- Modify: `android/app/src/main/java/com/mrt/app/navigation/AppNavigation.kt`
  - Replace `GitPlaceholderScreen` with the real Git screen.
- Create: `android/app/src/test/java/com/mrt/app/features/git/GitViewModelTest.kt`
  - Unit coverage for unavailable, clean, dirty, diff error, and session switching.
- Modify: `android/app/src/test/java/com/mrt/app/network/ConnectionManagerTest.kt`
  - Verify Git request encoding / Git result decoding.
- Create: `android/app/src/androidTest/java/com/mrt/app/features/git/GitScreenInstrumentedTest.kt`
  - Instrumentation smoke for the Git screen.

### Docs

- Modify: `docs/SPEC-IOS.md`
  - Replace “P4 placeholder” language with implemented read-only Git slice notes if needed.
- Modify: `docs/SPEC-ANDROID.md`
  - Same as iOS.

## Task 1: Agent Git Status Contract

**Files:**
- Create: `crates/agent/tests/git_readonly.rs`
- Modify: `crates/agent/src/test_support.rs`
- Modify: `crates/agent/src/server.rs`
- Create: `crates/agent/src/git.rs`
- Modify: `crates/agent/Cargo.toml`

- [ ] **Step 1: Write the failing agent integration test for non-repo status**

```rust
#[tokio::test]
async fn git_status_returns_repo_not_found_for_non_repo_session() {
    // connect test socket
    // create session pointing at temp dir with no .git
    // send Envelope { payload = git_op { session_id, status {} } }
    // expect GitResult.error.code == "GIT_REPO_NOT_FOUND"
    // expect ErrorEvent.fatal == false
}

#[tokio::test]
async fn git_status_returns_session_not_found_for_unknown_session() {
    // send status for unknown session id
    // expect GitResult.error.code == "GIT_SESSION_NOT_FOUND"
    // expect ErrorEvent.fatal == false
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cargo test -p agent --test git_readonly git_status_returns_repo_not_found_for_non_repo_session -- --nocapture`
Expected: FAIL because `Payload::GitOp` is not routed yet.

- [ ] **Step 3: Write the failing agent integration test for repo status success**

```rust
#[tokio::test]
async fn git_status_returns_worktree_first_changes() {
    // init temp git repo
    // create one modified tracked file, one deleted tracked file, one untracked file
    // also create one staged-only change that must NOT appear in changes[]
    // create session rooted inside a repo subdirectory
    // request git status
    // assert branch/tracking/is_clean/changes
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cargo test -p agent --test git_readonly git_status_returns_worktree_first_changes -- --nocapture`
Expected: FAIL because Git status support does not exist.

- [ ] **Step 5: Implement repo discovery and status parsing in `crates/agent/src/git.rs`**

```rust
pub struct GitService;

impl GitService {
    pub fn status_for_session_workdir(working_dir: &Path) -> Result<proto_gen::GitStatusResult> {
        // discover repo with `git -C <dir> rev-parse --show-toplevel`
        // reject bare repos
        // run `git -C <repo_root> -c core.quotepath=off status --porcelain=v1 -z --branch --untracked-files=all --no-renames`
        // parse worktree-first rows into GitFileChange { path, status }
    }
}
```

- [ ] **Step 6: Route `Payload::GitOp` in `crates/agent/src/server.rs`**

```rust
Some(Payload::GitOp(git_op)) => {
    route_git_operation(state, write, envelope.request_id, git_op).await?;
    Ok(false)
}
```

- [ ] **Step 7: Add the failing request-correlation test**

```rust
#[tokio::test]
async fn git_result_echoes_request_id_on_success_and_error() {
    // send one valid git status request and one invalid git diff request
    // assert every GitResult echoes the originating Envelope.request_id
    // assert every GitResult.session_id echoes the raw request session_id
}
```

- [ ] **Step 8: Add helper builders in `crates/agent/src/test_support.rs`**

```rust
pub async fn send_git_status(socket: &mut TestSocket, session_id: &str) { /* ... */ }
pub async fn send_git_diff(socket: &mut TestSocket, session_id: &str, path: &str) { /* ... */ }
pub async fn expect_git_error(socket: &mut TestSocket, code: &str) { /* ... */ }
```

- [ ] **Step 9: Re-run the status and request-correlation tests and verify they pass**

Run: `cargo test -p agent --test git_readonly -- --nocapture`
Expected: PASS for the first status tests plus `request_id` round-trip coverage.

- [ ] **Step 10: Commit**

```bash
git add crates/agent/Cargo.toml crates/agent/src/git.rs crates/agent/src/server.rs crates/agent/src/test_support.rs crates/agent/tests/git_readonly.rs
git commit -m "feat: add agent git status support"
```

## Task 2: Agent Git Diff Contract

**Files:**
- Modify: `crates/agent/src/git.rs`
- Modify: `crates/agent/src/server.rs`
- Modify: `crates/agent/tests/git_readonly.rs`

- [ ] **Step 1: Write the failing integration test for tracked-file diff**

```rust
#[tokio::test]
async fn git_diff_returns_unified_diff_for_modified_file() {
    // create modified tracked file
    // request diff for repo-root-relative path
    // assert GitResult.diff.diff contains @@ and expected lines
    // assert payload stays within the exact 256 KiB UTF-8 byte cap when truncation is forced
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cargo test -p agent --test git_readonly git_diff_returns_unified_diff_for_modified_file -- --nocapture`
Expected: FAIL because diff handling is not implemented.

- [ ] **Step 3: Write the failing integration test for untracked-file diff**

```rust
#[tokio::test]
async fn git_diff_rewrites_untracked_headers_to_repo_relative_paths() {
    // create untracked file with text content
    // request diff
    // assert diff starts with exactly:
    // diff --git a/<path> b/<path>
    // --- /dev/null
    // +++ b/<path>
    // and that the remainder of the patch body is preserved
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cargo test -p agent --test git_readonly git_diff_rewrites_untracked_headers_to_repo_relative_paths -- --nocapture`
Expected: FAIL because untracked diff conversion is not implemented.

- [ ] **Step 5: Write the failing integration tests for deleted file, stale target, and out-of-bounds path**

```rust
#[tokio::test]
async fn git_diff_supports_deleted_tracked_file() { /* ... */ }

#[tokio::test]
async fn git_diff_returns_target_stale_for_no_longer_changed_path() { /* ... */ }

#[tokio::test]
async fn git_diff_rejects_out_of_bounds_path() { /* ... */ }

#[tokio::test]
async fn git_unsupported_operations_return_git_op_unsupported() { /* ... */ }

#[tokio::test]
async fn git_diff_returns_unsupported_for_binary_content() { /* ... */ }

#[tokio::test]
async fn git_status_returns_workdir_invalid_for_bad_session_workdir() { /* ... */ }

#[tokio::test]
async fn git_returns_command_failed_when_git_subprocess_fails() { /* ... */ }

#[tokio::test]
async fn git_errors_always_return_fatal_false() { /* ... */ }
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cargo test -p agent --test git_readonly -- --nocapture`
Expected: FAIL on the new diff-focused tests.

- [ ] **Step 7: Implement diff generation and UTF-8 byte truncation in `crates/agent/src/git.rs`**

```rust
pub fn diff_for_path(working_dir: &Path, path: &str) -> Result<proto_gen::GitDiffResult> {
    // reject empty path
    // reject absolute path
    // split on '/'
    // reject empty, '.' and '..' components with GIT_DIFF_PATH_OUT_OF_BOUNDS
    // join onto repo root
    // recompute fresh worktree-first status and validate target
    // tracked deleted/modified => git diff --no-ext-diff --no-renames --unified=3 -- <path>
    // untracked => git diff --no-index --no-ext-diff -- <platform_null_path> <absolute_path>
    // choose platform_null_path as "/dev/null" on Unix-like hosts and "NUL" on Windows
    // rewrite untracked headers exactly:
    // diff --git a/<relative_path> b/<relative_path>
    // --- /dev/null
    // +++ b/<relative_path>
    // keep the remaining patch body intact
    // reject binary/non-renderable content
    // truncate by UTF-8 byte length including the exact final line:
    //  ... diff truncated by agent at 262144 bytes ...
}
```

- [ ] **Step 8: Add a small platform-null-path unit test**

```rust
#[test]
fn platform_null_path_matches_host_family() {
    // assert "/dev/null" on unix
    // assert "NUL" on windows
}
```

- [ ] **Step 9: Re-run the full agent Git test file**

Run: `cargo test -p agent --test git_readonly -- --nocapture`
Expected: PASS for all Git status/diff tests.

- [ ] **Step 10: Commit**

```bash
git add crates/agent/src/git.rs crates/agent/src/server.rs crates/agent/tests/git_readonly.rs
git commit -m "feat: add agent git diff support"
```

## Task 3: iOS Git Transport and View Model

**Files:**
- Create: `ios/MRT/Core/Models/GitModels.swift`
- Modify: `ios/MRT/Core/Network/ConnectionManager.swift`
- Create: `ios/MRT/Features/Git/GitViewModel.swift`
- Create: `ios/MRTTests/Features/GitViewModelTests.swift`
- Modify: `ios/MRTTests/Network/ConnectionManagerTests.swift`
- Modify: `ios/MRTTests/TestSupport/TestDoubles.swift`
- Modify: `scripts/test-ios.sh`

- [ ] **Step 1: Write the failing iOS transport test for Git status encoding**

```swift
func testConnectionManagerSendsGitStatusOperation() async throws {
    // connect, handshake, request Git status
    // decode last envelope and assert payload == .gitOp with .status
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination 'id=$IOS_SIMULATOR_ID' -only-testing:MRTTests/ConnectionManagerTests test`
Expected: FAIL because `ConnectionManager` has no Git API yet.

- [ ] **Step 3: Write the failing iOS view-model tests for unavailable, dirty, clean, and latest-wins states**

```swift
@MainActor
func testGitViewModelShowsUnavailableWithoutConnectedSession() async { /* ... */ }

@MainActor
func testGitViewModelLoadsDirtyStatusAndAutoSelectsFirstFile() async { /* ... */ }

@MainActor
func testGitViewModelDropsLateResultsAfterSessionChange() async { /* ... */ }

@MainActor
func testGitViewModelSeparatesDisconnectedNoSessionAndNotRepoStates() async { /* ... */ }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `xcodebuild -project ios/MRT.xcodeproj -scheme MRT -destination 'id=$IOS_SIMULATOR_ID' -only-testing:MRTTests/GitViewModelTests test`
Expected: FAIL because the models/view model do not exist.

- [ ] **Step 5: Add Git request APIs to `ConnectionManager.swift`**

```swift
func requestGitStatus(sessionID: String) async throws
func requestGitDiff(sessionID: String, path: String) async throws
var onGitResult: ((GitResultEnvelope) -> Void)?
```

- [ ] **Step 6: Add `GitModels.swift` and `GitViewModel.swift` with latest-wins request generation**

```swift
struct GitSummaryModel { /* branch, tracking, isClean, files */ }

@MainActor
final class GitViewModel: ObservableObject {
    // unavailable/loading/clean/dirty + diff substates
    // requestGeneration counters per session
}
```

- [ ] **Step 7: Update test doubles to emit Git results**

```swift
var sentGitStatusSessionIDs: [String] = []
var sentGitDiffRequests: [(sessionID: String, path: String)] = []
```

- [ ] **Step 8: Re-run the transport and view-model tests**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/test-ios.sh`
Expected: PASS including the new `MRTTests/GitViewModelTests`.

- [ ] **Step 9: Commit**

```bash
git add ios/MRT/Core/Models/GitModels.swift ios/MRT/Core/Network/ConnectionManager.swift ios/MRT/Features/Git/GitViewModel.swift ios/MRTTests/Features/GitViewModelTests.swift ios/MRTTests/Network/ConnectionManagerTests.swift ios/MRTTests/TestSupport/TestDoubles.swift scripts/test-ios.sh
git commit -m "feat: add ios git transport and view model"
```

## Task 4: iOS Git Screen and UI Smoke

**Files:**
- Create: `ios/MRT/Features/Git/GitScreen.swift`
- Modify: `ios/MRT/ContentView.swift`
- Modify: `ios/MRT.xcodeproj/project.pbxproj`
- Create: `ios/MRTUITests/GitUITests.swift`
- Modify: `ios/MRT.xcodeproj/xcshareddata/xcschemes/MRT.xcscheme`
- Modify: `scripts/e2e-ios-ui.sh`

- [ ] **Step 1: Write the failing iOS UI smoke**

```swift
func testGitTabShowsChangedFilesAndDiff() throws {
    let app = XCUIApplication()
    app.launchArguments += ["MRT_UI_SMOKE_GIT"]
    app.launch()
    // open Git tab
    // assert changed file row exists
    // tap row
    // assert diff pane updates
}
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/e2e-ios-ui.sh`
Expected: FAIL because the Git tab is still a placeholder.

- [ ] **Step 3: Implement `GitScreen.swift` using existing GH components**

```swift
struct GitScreen: View {
    @ObservedObject var viewModel: GitViewModel
    // GHCard summary + GHList rows + GHDiffView body
}
```

- [ ] **Step 4: Replace `GitPlaceholderView` in `ContentView.swift`**

```swift
case .git:
    GitScreen(viewModel: gitViewModel)
```

- [ ] **Step 5: Add Xcode project entries and UI smoke data path**

```swift
// extend MRTApp / UITestConnectionManager with deterministic MRT_UI_SMOKE_GIT fixture:
// - active session rooted inside a temporary git repo
// - one modified file
// - one stable selected file path
// - one diff payload that can be asserted exactly
```

- [ ] **Step 6: Re-run the iOS UI smoke**

Run: `IOS_SIMULATOR_ID="$IOS_SIMULATOR_ID" bash scripts/e2e-ios-ui.sh`
Expected: PASS with the Git smoke path.

- [ ] **Step 7: Commit**

```bash
git add ios/MRT/Features/Git/GitScreen.swift ios/MRT/ContentView.swift ios/MRTUITests/GitUITests.swift ios/MRT.xcodeproj/project.pbxproj ios/MRT.xcodeproj/xcshareddata/xcschemes/MRT.xcscheme scripts/e2e-ios-ui.sh
git commit -m "feat: add ios git read-only screen"
```

## Task 5: Android Git Transport and View Model

**Files:**
- Create: `android/app/src/main/java/com/mrt/app/core/models/GitModels.kt`
- Modify: `android/app/src/main/java/com/mrt/app/core/network/ConnectionManager.kt`
- Create: `android/app/src/main/java/com/mrt/app/features/git/GitViewModel.kt`
- Create: `android/app/src/test/java/com/mrt/app/features/git/GitViewModelTest.kt`
- Modify: `android/app/src/test/java/com/mrt/app/network/ConnectionManagerTest.kt`

- [ ] **Step 1: Write the failing Android transport test for Git status encoding**

```kotlin
@Test
fun connectionManagerSendsGitStatusOperationWhenConnected() = runBlocking {
    // connect, handshake, request git status, decode last envelope
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.mrt.app.network.ConnectionManagerTest`
Expected: FAIL because the Git request API does not exist.

- [ ] **Step 3: Write the failing Android view-model tests**

```kotlin
@Test
fun gitViewModelLoadsDirtyStatusAndAutoSelectsFirstFile() = runTest { /* ... */ }

@Test
fun gitViewModelDropsLateResultsAfterSessionChange() = runTest { /* ... */ }

@Test
fun gitViewModelSeparatesDisconnectedNoSessionAndNotRepoStates() = runTest { /* ... */ }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.mrt.app.features.git.GitViewModelTest`
Expected: FAIL because the view model does not exist.

- [ ] **Step 5: Add Git request APIs and result flow to `ConnectionManager.kt`**

```kotlin
suspend fun requestGitStatus(sessionId: String)
suspend fun requestGitDiff(sessionId: String, path: String)
```

- [ ] **Step 6: Add `GitModels.kt` and `GitViewModel.kt`**

```kotlin
class GitViewModel(
    private val connectionManager: ConnectionManaging,
    private val sessionViewModel: SessionViewModel,
) { /* latest-wins state machine */ }
```

- [ ] **Step 7: Re-run Android unit tests**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: PASS including the new Git tests.

- [ ] **Step 8: Commit**

```bash
git add android/app/src/main/java/com/mrt/app/core/models/GitModels.kt android/app/src/main/java/com/mrt/app/core/network/ConnectionManager.kt android/app/src/main/java/com/mrt/app/features/git/GitViewModel.kt android/app/src/test/java/com/mrt/app/features/git/GitViewModelTest.kt android/app/src/test/java/com/mrt/app/network/ConnectionManagerTest.kt
git commit -m "feat: add android git transport and view model"
```

## Task 6: Android Git Screen and Instrumentation

**Files:**
- Create: `android/app/src/main/java/com/mrt/app/features/git/GitScreen.kt`
- Modify: `android/app/src/main/java/com/mrt/app/navigation/AppNavigation.kt`
- Create: `android/app/src/androidTest/java/com/mrt/app/features/git/GitScreenInstrumentedTest.kt`

- [ ] **Step 1: Write the failing Android instrumentation smoke**

```kotlin
@Test
fun gitScreenShowsChangedFilesAndDiff() {
    // render screen with fake Git state
    // tap a file
    // assert diff content
}
```

- [ ] **Step 2: Run the instrumentation compile/test step to verify it fails**

Run: `cd android && ./gradlew :app:assembleDebugAndroidTest`
Expected: FAIL or missing references because the Git screen is not implemented.

- [ ] **Step 3: Implement `GitScreen.kt`**

```kotlin
@Composable
fun GitScreen(viewModel: GitViewModel, modifier: Modifier = Modifier) {
    // GHCard summary
    // GHList of changed files
    // GHDiffView for selected diff
}
```

- [ ] **Step 4: Replace `GitPlaceholderScreen` in `AppNavigation.kt`**

```kotlin
AppDestination.Git -> GitScreen(...)
```

- [ ] **Step 5: Re-run Android instrumentation**

Run: `MRT_ANDROID_SDK_ROOT=/usr/local/share/android-commandlinetools MRT_ANDROID_SYSTEM_IMAGE='system-images;android-35;google_atd;arm64-v8a' bash scripts/e2e-android-ui.sh`
Expected: PASS after `scripts/e2e-android-ui.sh` is updated or confirmed to include `com.mrt.app.features.git.GitScreenInstrumentedTest`.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/com/mrt/app/features/git/GitScreen.kt android/app/src/main/java/com/mrt/app/navigation/AppNavigation.kt android/app/src/androidTest/java/com/mrt/app/features/git/GitScreenInstrumentedTest.kt scripts/e2e-android-ui.sh
git commit -m "feat: add android git read-only screen"
```

## Task 7: Spec Alignment and Final Verification

**Files:**
- Modify: `docs/SPEC-IOS.md`
- Modify: `docs/SPEC-ANDROID.md`

- [ ] **Step 1: Update platform specs to note the read-only Git slice**

```markdown
- Git tab now supports read-only worktree-first status + single-file diff.
- Write operations remain deferred.
```

- [ ] **Step 2: Run Rust verification**

Run: `cargo test -p agent --test git_readonly -- --nocapture`
Expected: PASS

- [ ] **Step 3: Run Android verification**

Run: `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebugAndroidTest`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Run Android UI verification**

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
git commit -m "docs: align mobile specs with readonly git slice"
```
