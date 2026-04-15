# AnyWhereVibe Git Read-Only Slice Design

**Date:** 2026-04-15

## References and Precedence

This design defines the first usable Git slice for the existing AnyWhereVibe mobile clients and agent.

Source references:

- `docs/SPEC.md`
- `docs/SPEC-AGENT.md`
- `docs/SPEC-IOS.md`
- `docs/SPEC-ANDROID.md`
- `proto/mrt.proto`

Precedence for this slice is:

1. this design document for slice scope, exclusions, and behavior
2. `proto/mrt.proto` for concrete message names and field shapes
3. `docs/SPEC-AGENT.md` for agent ownership and long-term Git direction
4. `docs/SPEC-IOS.md` and `docs/SPEC-ANDROID.md` for mobile structure and design-system alignment
5. `docs/SPEC.md` for master roadmap context only

If a later-phase Git capability from the source specs conflicts with this slice, this design document wins for the current implementation.

## Goal

Deliver the first end-to-end Git feature slice that is usable from both iOS and Android without introducing write operations.

This slice must let a connected mobile client:

- inspect Git status for the active session
- automatically resolve the nearest repository root from the active session's `working_dir`
- view the worktree-visible changed-file list for that repository
- open a single changed file and inspect its unified diff

This slice must not change repository state.

## User-Confirmed Decisions

The scope decisions for this slice are fixed:

- depth: read-only only
- repository context: auto-discover the nearest repository root by walking upward from the active session `working_dir`
- content depth: working-tree first, meaning branch summary, changed files, and single-file diff
- unavailable behavior: strictly depend on a live agent and active session; when unavailable, show an explicit banner rather than cached or demo data

## Scope

### In Scope

- agent-side handling for `GitOperation.op = status` (`GitStatusReq`) and `GitOperation.op = diff` (`GitDiffReq`)
- repository discovery based on active session `working_dir`
- error reporting for missing session, missing repository, unsupported Git operations, and diff failures
- iOS Git screen replacing the current placeholder
- Android Git screen replacing the current placeholder
- mobile state management for:
  - unavailable state
  - status loading and status error
  - clean repository
  - dirty repository
  - diff loading and diff error
- unit and integration coverage for the agent Git read path
- mobile UI and view-model coverage for the read-only Git flow

### Out of Scope

- all write operations: stage, unstage, commit, checkout, branch creation, push, pull
- log, branches list, stash, ahead/behind, merge-base, and conflict tooling
- repository switching UI
- cached Git snapshots
- offline or stale Git display
- staged vs unstaged grouping in mobile UI
- proto redesign for richer Git state

## Why This Slice

This is the narrowest Git feature that is both useful and stable.

- It removes the current placeholders on both mobile platforms.
- It does not overload the first Git release with write semantics or repo-management UI.
- It uses the Git wire messages that already exist in `proto/mrt.proto`.
- It preserves a clean path to later write operations without forcing a transport redesign.

## Architecture

This slice uses an agent-owned Git read service with mobile clients as thin stateful consumers.

### Ownership

- `proto/mrt.proto` remains the wire contract.
- the Rust agent owns repository discovery and Git command execution
- iOS and Android own presentation, state transitions, and selection behavior

### Agent Placement

Git handling must live in the agent server layer for this slice, not in the `AgentAdapter` abstraction.

Reasoning:

- repository inspection is local filesystem behavior, not Codex behavior
- the existing adapter interface is prompt/task oriented and contains no Git entry points
- forcing Git into the adapter layer now would widen the abstraction prematurely

This means the agent runtime handles `Envelope.git_op` directly alongside existing websocket envelope handling.

### Protocol Usage

No proto changes are required for this slice.

Proto reality for this slice:

- requests are carried in `Envelope.payload = git_op`
- the concrete request body is `GitOperation`
- responses are carried in `Envelope.payload = git_result`
- the concrete response body is `GitResult`
- when this document says `GitOperation.status` or `GitOperation.diff`, it refers to the actual `GitOperation.op` oneof field on the wire
- when this document mentions `GitStatusReq` or `GitDiffReq`, it refers only to the generated nested payload types occupying those oneof fields, not a separate transport envelope

Relevant proto fields for planning, copied from current `proto/mrt.proto` semantics:

- `GitStatusResult { string branch, string tracking, repeated GitFileChange changes, bool is_clean }`
- `GitFileChange { string path, string status }`
- `GitDiffResult { string diff }`
- `ErrorEvent { string code, string message, bool fatal }`

The only supported inbound `GitOperation.op` values are:

- `GitOperation { session_id, status {} }`
- `GitOperation { session_id, diff { path, staged=false } }`

The only successful outbound `GitResult.result` shapes are:

- `GitResult { session_id, status { branch, tracking, changes[], is_clean } }`
- `GitResult { session_id, diff { diff } }`

All other Git operations already present in the proto must return `GitResult.error` in this slice.

Example request:

```text
Envelope {
  payload = git_op {
    session_id = "session-1"
    status {}
  }
}
```

Example response:

```text
Envelope {
  payload = git_result {
    session_id = "session-1"
    status {
      branch = "main"
      tracking = "origin/main"
      is_clean = false
      changes = [...]
    }
  }
}
```

## Backend Design

### Session Resolution

Every Git request is scoped by `session_id`.

Resolution steps:

1. locate the session in `SessionManager`
2. read the session `working_dir`
3. resolve the nearest repository root by walking upward from `working_dir`
4. if no repository root is found, return a Git-scoped error result

The repository root is not stored in session state in this slice. It is derived on demand from `working_dir`.

### Repository Discovery

Repository discovery must support sessions started in subdirectories of a repository.

Discovery is defined by Git itself, not by a custom filesystem walker.

Required behavior:

- run repository discovery as `git -C <working_dir> rev-parse --show-toplevel`
- if the command succeeds, the returned path is the resolved repository root
- if the command fails, treat the session as non-Git

This intentionally inherits Git's own handling for:

- standard repositories
- subdirectories inside repositories
- worktrees
- submodules with working trees

Bare repositories are out of scope for this slice. If a session points at a bare repository or any location without a usable working tree, treat it as non-Git and return `GIT_REPO_NOT_FOUND`.

### Git Status

The status request returns the repository summary needed for the first mobile screen:

- current branch name
- tracking branch text when available
- `is_clean`
- worktree-visible changed-file list

The changed-file list must use the current coarse proto statuses only:

- `modified`
- `deleted`
- `untracked`

Although the proto also permits `added`, this slice does not emit `added` because it is intentionally worktree-first and excludes pure index-only changes.

Status collection must use a stable Git command shape:

- `git -C <repo_root> -c core.quotepath=off status --porcelain=v1 -z --branch --untracked-files=all --no-renames`

Parsing contract for branch and tracking:

- use the leading `##` header line from porcelain v1 output
- `branch` is the local branch name when present
- `tracking` is only the upstream ref name when present
- ahead/behind counts and `[gone]` annotations are not surfaced in this slice
- detached HEAD maps to `branch = "HEAD"` and `tracking = ""`
- no-upstream branch maps to `tracking = ""`

Examples:

- `## main...origin/main [ahead 1]` -> `branch = "main"`, `tracking = "origin/main"`
- `## feature` -> `branch = "feature"`, `tracking = ""`
- `## feature...origin/feature [gone]` -> `branch = "feature"`, `tracking = "origin/feature"`
- `## HEAD (no branch)` -> `branch = "HEAD"`, `tracking = ""`

Path contract:

- every `GitFileChange.path` returned by the agent is repo-root-relative
- all path separators in `GitFileChange.path` are normalized to `/`
- mobile clients must send back exactly that repo-root-relative path string in `GitDiffReq.path`
- repo-root-relative means no leading slash, no drive prefix, and no `./` prefix
- paths with spaces or non-ASCII characters are allowed and must round-trip unchanged
- path comparison is byte-for-byte on the normalized UTF-8 path string emitted by the agent

Status mapping rules:

- this slice is worktree-first, not all-changes-first
- only entries visible in the working tree are included in `changes[]`
- pure index-only changes are excluded from `changes[]` in this slice
- untracked entries map to `untracked`
- entries whose worktree state is `D` map to `deleted`
- entries whose worktree state is `M`, `T`, or `U` map to `modified`
- unresolved/conflicted entries that Git exposes through porcelain and which are not cleanly representable still map to `modified`
- submodule or similar working-tree detail that still appears in porcelain output also maps to `modified`

Operationally, “currently changed” for this slice means:

- untracked files
- tracked files with a non-space worktree column in porcelain v1 output
- not files changed only in the index

`is_clean` is also worktree-first in this slice:

- `is_clean = true` iff the derived worktree-first `changes[]` list is empty
- a repository with index-only changes and no worktree-visible changes is reported as clean in this slice

Because `--no-renames` is required, rename and copy detail is intentionally flattened before it reaches mobile clients. Later Git detail such as staged/unstaged split, renames, or conflicts is intentionally flattened or omitted in this slice because `GitFileChange.status` cannot represent that detail safely.

### Git Diff

The diff request is limited to a single file path.

Rules:

- `path` is interpreted relative to the resolved repository root
- `path` must be normalized before use
- paths containing `..` path traversal or resolving outside the repository root must be rejected with `GIT_DIFF_PATH_OUT_OF_BOUNDS`
- diff eligibility is checked against a fresh server-side status computation performed during the diff request itself
- only files currently reported as changed by that fresh worktree-first status computation are valid diff targets
- a diff request for a path that is under the repo root but is no longer changed at diff time must return `GIT_DIFF_TARGET_STALE`
- the diff payload is a unified diff string suitable for existing `GHDiffView` rendering

Normalization algorithm for incoming `GitDiffReq.path`:

1. reject empty strings
2. reject absolute paths
3. split on `/`
4. reject any empty, `.` or `..` component
5. join the remaining components onto the resolved repository root
6. for untracked-file diff generation, canonicalize the joined file path and ensure it remains under the canonicalized repository root; otherwise return `GIT_DIFF_PATH_OUT_OF_BOUNDS`

The agent does not apply Unicode normalization or case-folding in this slice. It treats paths as exact UTF-8 byte strings emitted by the earlier status response.

Diff generation rules:

- tracked changed files use `git -C <repo_root> diff --no-ext-diff --no-renames --unified=3 -- <path>`
- untracked files use `git -C <repo_root> diff --no-index --no-ext-diff -- <platform_null_path> <absolute_path_to_file>`
- binary files are not rendered inline; they return `GIT_DIFF_UNSUPPORTED`
- rename detail is not surfaced in this slice because status is already flattened to the current path and coarse change type
- `--cached` is not used in this slice because pure index-only changes are intentionally excluded from the worktree-first status surface

`platform_null_path` means:

- `/dev/null` on Unix-like agent hosts
- `NUL` on Windows agent hosts

Untracked-file rules:

- the diff returned from `git diff --no-index` is converted to repo-root-relative display paths before sending to mobile
- untracked file content is subject to the same 256 KiB response cap as any other diff
- if an untracked file is binary or cannot be rendered safely as text diff content, return `GIT_DIFF_UNSUPPORTED`

Untracked diff header rewrite is deterministic:

- first line becomes `diff --git a/<relative_path> b/<relative_path>`
- `---` line becomes exactly `--- /dev/null`
- `+++` line becomes exactly `+++ b/<relative_path>`
- all rewritten paths use the same repo-root-relative `/`-normalized path string returned in status
- the remainder of the patch body is preserved after those header rewrites, subject to the truncation rule below

To keep mobile rendering bounded, the agent must cap diff payload size in this slice:

- maximum total `GitDiffResult.diff` size: 256 KiB, including any truncation marker line
- if the diff exceeds the cap, truncate on a line boundary early enough to keep the final payload, including the truncation marker line below, within 256 KiB total
- when truncation happens, append this exact final context line:
  ` ... diff truncated by agent at 262144 bytes ...`

This truncation is presentation-oriented rather than protocol-oriented. The response still uses normal `GitDiffResult`, and truncation is signaled only by that exact final context line embedded inside `GitDiffResult.diff`.

Binary or non-renderable detection rules:

- if tracked diff output contains `Binary files` or `GIT binary patch`, return `GIT_DIFF_UNSUPPORTED`
- if an untracked file contains a NUL byte in the first 8192 bytes, return `GIT_DIFF_UNSUPPORTED`
- no textconv pipeline is used in this slice

### Unsupported Operations

The following inbound Git ops must return explicit Git errors in this slice:

- `commit`
- `push`
- `pull`
- `log`
- `branches`
- `checkout`

The error must be descriptive enough that mobile clients can show a user-facing “not available in this version” state instead of silently failing.

## Mobile Design

Both mobile clients must replace the Git placeholder with the same three-part read-only structure:

1. repository summary card
2. changed-files list
3. selected-file diff area

### Entry Preconditions

The Git screen is only functional when all of these are true:

- agent connection is live
- an active session exists
- the active session resolves to a Git repository

If any precondition fails, the screen shows a banner and no fake repository content.

### Summary Card

The summary card shows:

- branch
- tracking text when present
- clean/dirty badge

No buttons or write actions appear in this slice.

Repository root identity is intentionally not shown in this slice.

Reasoning:

- the current successful `GitStatusResult` contract does not carry repository root metadata
- adding repository identity would force either a proto change or ad hoc derivation rules on mobile
- branch, tracking, and dirty state are sufficient for the first read-only slice

### Changed Files

The changed-files list is a flat list.

Each row shows:

- path
- Git status badge

No filtering, grouping, search, or staged/unstaged sections are included.

### Diff Area

When the repository is dirty:

- the first changed file is automatically selected after status load
- selecting a row requests and displays the unified diff for that file

When the repository is clean:

- the diff area is hidden or replaced by a clean-state empty message

### Shared Selection Rules

- changing active session clears old Git state immediately
- when a fresh status result no longer contains the previously selected file, selection falls back to the first changed file
- a diff error only affects the diff area, not the status summary or changed-file list

## Mobile State Model

Both iOS and Android should model the same conceptual states.

### Top-Level Git Screen States

- `Unavailable`
  - agent disconnected
  - no active session
  - active session not inside a Git repository
- `LoadingStatus`
- `StatusError`
- `ReadyClean`
- `ReadyDirty`

### Diff Substates Inside Dirty Repositories

- `LoadingDiff`
- `DiffReady`
- `DiffError`

This split is important: a diff failure must not discard an otherwise valid Git status response.

## UI Behavior

### Refresh Triggers

This slice does not introduce a manual refresh button.

Git data refreshes automatically when:

- the Git tab becomes visible
- the active session changes
- the client reconnects to the agent

The Git screen is snapshot-based in this slice, not live-subscribed to background repository mutations while the screen remains open.

“No stale Git display” in this document means:

- no cached or offline snapshot is shown when live agent/session preconditions fail
- the screen always derives its data from a fresh request on the defined refresh triggers

It does not mean continuous background refresh while the user stays on the Git tab.

### Empty and Error Copy

Mobile clients must distinguish these user-facing cases:

- disconnected from agent
- no active session selected
- active session is not inside a Git repository
- repository is clean
- failed to load Git status
- failed to load diff for the selected file

These must be separate copy states because they imply different corrective actions.

## Backend Error Semantics

Git errors are business-level errors carried via `GitResult.error`, not transport-level disconnects.

Representation:

- `GitResult.error` uses the existing `ErrorEvent` proto shape
- `ErrorEvent.code` carries the stable Git error code string
- `ErrorEvent.message` carries human-readable detail
- `ErrorEvent.fatal` is always `false` for Git slice errors in this document

Required cases:

- unknown `session_id` -> `GIT_SESSION_NOT_FOUND`
- session has unusable or missing `working_dir` -> `GIT_WORKDIR_INVALID`
- no repository found for the resolved working directory -> `GIT_REPO_NOT_FOUND`
- unsupported Git operation in this slice -> `GIT_OP_UNSUPPORTED`
- diff path resolves outside repo root or fails normalization -> `GIT_DIFF_PATH_OUT_OF_BOUNDS`
- diff target is no longer present in the current changed-file set at diff time -> `GIT_DIFF_TARGET_STALE`
- git command failure for status or diff -> `GIT_COMMAND_FAILED`
- binary or otherwise non-renderable diff content -> `GIT_DIFF_UNSUPPORTED`

The websocket connection stays healthy after these errors.

Mobile mapping:

- `GIT_SESSION_NOT_FOUND`, `GIT_WORKDIR_INVALID`, `GIT_REPO_NOT_FOUND` -> `Unavailable`
- `GIT_COMMAND_FAILED` during status -> `StatusError`
- `GIT_COMMAND_FAILED` during diff -> `DiffError`
- `GIT_DIFF_PATH_OUT_OF_BOUNDS` -> `DiffError`
- `GIT_DIFF_TARGET_STALE` -> `DiffError`
- `GIT_DIFF_UNSUPPORTED` -> `DiffError`
- `GIT_OP_UNSUPPORTED` is not expected in normal first-slice mobile flows and should surface as a generic feature error banner if encountered

## Implementation Shape

### Agent

Expected additions:

- Git request routing in websocket envelope handling
- a small internal Git service module for:
  - repo discovery
  - status extraction
  - single-file diff extraction
- Git-to-proto mapping helpers

This should remain a narrow read-only service rather than a generic Git framework.

### iOS

Expected additions:

- Git feature folder and read-only `GitScreen`
- `ConnectionManager` support for sending Git requests and receiving `GitResult`
- Git view model/state model
- replacement of `GitPlaceholderView`

### Android

Expected additions:

- Git feature package and read-only `GitScreen`
- `ConnectionManager` support for sending Git requests and receiving `GitResult`
- Git view model/state model
- replacement of `GitPlaceholderScreen`

## Testing Requirements

### Agent

Must cover:

- `status` request against a non-Git directory returns error
- `status` request against a repository returns branch, clean flag, and changes
- session `working_dir` inside a repository subdirectory still resolves the nearest repository root
- `diff` request for a changed file returns unified diff content
- unsupported Git operations return explicit errors

### iOS

Must cover:

- unavailable banner states
- status load success with changed files
- file selection triggering diff load
- clean repository state
- session switch resetting Git state

### Android

Must cover:

- unavailable banner states
- status load success with changed files
- file selection triggering diff load
- clean repository state
- session switch resetting Git state

### UI Smoke

At least one higher-level smoke flow per mobile platform should verify:

- entering the Git tab
- rendering a changed-file list
- selecting a file
- showing a diff area update

## Acceptance Criteria

This slice is complete when all of the following are true:

- iOS Git tab is no longer a placeholder
- Android Git tab is no longer a placeholder
- the agent can answer `GitStatusReq` and `GitDiffReq`
- repository auto-discovery works from session subdirectories
- non-Git sessions show explicit unavailable states
- dirty repositories show changed files and a single-file diff
- clean repositories show a clean-state view without fake diff content
- unsupported Git operations return explicit Git errors
- fresh verification passes for agent, iOS, and Android coverage introduced by this slice

## Deferred Follow-Ups

These are intentionally deferred, not forgotten:

- staged vs unstaged modeling
- commit and stage/unstage flows
- branch and log views
- repository switching
- stale cache behavior
- ahead/behind and remote metadata
- richer proto status values for rename/conflict/staged detail
