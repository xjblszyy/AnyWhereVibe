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
- view the changed-file list for that repository
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

- agent-side handling for `GitStatusReq` and `GitDiffReq`
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

The only supported inbound operations are:

- `GitOperation { session_id, status {} }`
- `GitOperation { session_id, diff { path, staged=false } }`

The only successful outbound result shapes are:

- `GitResult { session_id, status { branch, tracking, changes[], is_clean } }`
- `GitResult { session_id, diff { diff } }`

All other Git operations already present in the proto must return `GitResult.error` in this slice.

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

Behavior:

- if `working_dir` is the repository root, use it
- if `working_dir` is a child directory inside a repository, walk upward until a repository root is found
- if the upward walk reaches the filesystem root without finding a repository, treat the session as non-Git

### Git Status

The status request returns the repository summary needed for the first mobile screen:

- current branch name
- tracking branch text when available
- `is_clean`
- changed-file list

The changed-file list must use the current coarse proto statuses only:

- `modified`
- `added`
- `deleted`
- `untracked`

Later Git detail such as staged/unstaged split, renames, or conflicts is intentionally flattened or omitted in this slice because `GitFileChange.status` cannot represent that detail safely.

### Git Diff

The diff request is limited to a single file path.

Rules:

- `path` is interpreted relative to the resolved repository root
- only changed files from the current status result are valid diff targets
- a diff request for a path not present in the current repo change set returns an error result
- the diff payload is a unified diff string suitable for existing `GHDiffView` rendering

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

- repository root name
- branch
- tracking text when present
- clean/dirty badge

No buttons or write actions appear in this slice.

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

Required cases:

- unknown `session_id`
- session has unusable or missing `working_dir`
- no repository found for the resolved working directory
- unsupported Git operation in this slice
- diff path not found in the current repository change set
- git command failure for status or diff

The websocket connection stays healthy after these errors.

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
