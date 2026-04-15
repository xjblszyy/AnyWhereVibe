# AnyWhereVibe Files Session Sandbox Design

**Date:** 2026-04-15

## References and Precedence

This design defines the first full Files slice for the existing AnyWhereVibe agent, iOS client, and Android client.

Source references:

- `docs/SPEC.md`
- `docs/SPEC-AGENT.md`
- `docs/SPEC-IOS.md`
- `docs/SPEC-ANDROID.md`
- `proto/mrt.proto`

Precedence for this slice is:

1. this design document for scope, behavior, and error semantics
2. `proto/mrt.proto` for current message names and field shapes
3. `docs/SPEC-AGENT.md` for long-term file-operation intent
4. `docs/SPEC-IOS.md` and `docs/SPEC-ANDROID.md` for mobile structure and design-system alignment
5. `docs/SPEC.md` for roadmap context only

If a later-phase file-management requirement from the source specs conflicts with this slice, this design document wins for the current implementation.

## Goal

Deliver the first usable Files feature slice that is complete enough for routine remote editing within a single session sandbox.

This slice must let a connected mobile client:

- browse directories under the active session `working_dir`
- open and read text files
- save text file changes back to disk
- create files
- create directories
- delete files or directories
- rename files or directories

All file operations must remain strictly confined to the active session `working_dir`.

## User-Confirmed Decisions

The scope decisions for this slice are fixed:

- root scope: only the active session `working_dir` and its descendants
- functional depth: directory browse + file view/edit + save + create file + create directory + delete + rename
- unsupported in this slice: search, upload/download, batch actions, media preview, cross-root browsing

## Scope

### In Scope

- protobuf extension for explicit file mutations
- agent-side session-root sandbox file service
- iOS Files screen replacing the current placeholder
- Android Files screen replacing the current placeholder
- latest-wins client state handling for directory loads, file loads, saves, and mutations
- deterministic UI smoke coverage on iOS and Android

### Out of Scope

- full-text search
- binary preview beyond explicit unsupported-state handling
- large-file pagination beyond the initial single-read cap
- file upload/download workflows
- batch delete / batch rename / multi-select
- symlink traversal outside the session root
- git-aware file status overlays

## Architecture

This slice uses an agent-owned file service with mobile clients as thin stateful consumers.

### Ownership

- requests are carried over the existing websocket connection in `Envelope.payload = file_op`
- responses are carried back in `Envelope.payload = file_result`
- the agent owns all filesystem access, path validation, and mutation execution
- iOS and Android own presentation, request timing, selection state, and local edit buffers

### Agent Placement

File handling lives in the agent server layer for this slice, not in `AgentAdapter`.

Reasoning:

- file operations are local filesystem behavior, not Codex process behavior
- file reads and writes must be usable independent of adapter choice
- a session-root sandbox belongs naturally beside session resolution and websocket request routing

## Protocol Usage

The existing proto already provides:

- `FileOperation { session_id, list_dir | read_file | write_file }`
- `FileResult { session_id, dir_listing | file_content | write_ack | error }`

This slice extends that shape minimally with explicit mutations instead of overloading `WriteFile`.

### Required Proto Additions

Add these new request messages:

- `CreateFile { string path = 1; }`
- `CreateDir { string path = 1; }`
- `DeletePath { string path = 1; bool recursive = 2; }`
- `RenamePath { string from_path = 1; string to_path = 2; }`

Extend `FileOperation.oneof op` with:

- `CreateFile create_file = 5;`
- `CreateDir create_dir = 6;`
- `DeletePath delete_path = 7;`
- `RenamePath rename_path = 8;`

Add a unified mutation acknowledgment:

- `FileMutationAck { string path = 1; bool success = 2; string message = 3; }`

Extend `FileResult.oneof result` with:

- `FileMutationAck mutation_ack = 5;`

`FileWriteAck` may remain for backward compatibility, but this slice should prefer `mutation_ack` for create/delete/rename and may continue using `write_ack` for plain file save.

### Proto Reality Rules

- request/response correlation uses existing `Envelope.request_id`
- the agent must echo `Envelope.request_id` unchanged on every `file_result`
- `FileResult.session_id` must always echo the raw request `session_id`, including empty string, even on errors
- `ErrorEvent.fatal` must always be `false` for Files-slice business errors

## Path Model

All client-visible paths are logical paths relative to the active session root.

### Path Contract

- root directory is represented as `""`
- all non-root paths are repo-style relative paths using `/` separators
- no returned path has a leading slash
- no returned path has a drive prefix
- no returned path has a `./` prefix
- paths may contain spaces and non-ASCII characters and must round-trip unchanged

Clients must send back exactly the relative paths previously returned by the agent.

## Sandbox Rules

The active session `working_dir` is the only root for this slice.

### Resolution

1. resolve `session_id` to the active session record
2. obtain its `working_dir`
3. canonicalize the session root
4. resolve any requested relative path underneath that canonical root
5. reject any path that escapes or cannot be proven to stay within that root

### Rejection Rules

For every incoming path:

- reject empty path when the specific operation requires a concrete file or directory target
- reject absolute paths
- reject any component equal to `.` or `..`
- reject any resolution that escapes the canonical session root

Return `FILE_PATH_OUT_OF_BOUNDS` for all such failures.

Symlinks that point outside the session root are out of scope for this slice and must be treated as out-of-bounds if resolution escapes the canonical root.

## Directory Listing

Directory listing uses existing `ListDir`.

### Behavior

- `path=""` lists the session root
- `path="<subdir>"` lists that subdirectory
- this slice does not use recursive listing from mobile UI, but agent support may keep `recursive` and `max_depth` for protocol completeness
- directory entries are returned sorted with directories first, then files, both alphabetically by name

### Returned Metadata

Each `FileEntry` must populate:

- `name`
- `path`
- `is_dir`
- `size`
- `modified_ms`

## File Reading

This slice supports direct full read of small text files only.

### Read Rules

- maximum read size: `1 MiB`
- if the file exceeds the cap, return `FILE_TOO_LARGE`
- if the file is binary or otherwise unsupported for editing, return `FILE_UNSUPPORTED_TYPE`
- read requests for directories return `FILE_UNSUPPORTED_TYPE`

### Binary Detection

Use a simple deterministic heuristic:

- read the first `8192` bytes
- if any byte is NUL, treat the file as binary and return `FILE_UNSUPPORTED_TYPE`

No MIME inference or media preview is included in this slice.

## File Writing

`WriteFile` is used only for saving text file contents to an existing logical path.

### Write Rules

- target path must already exist and be a file
- directory targets return `FILE_UNSUPPORTED_TYPE`
- writes replace the file contents atomically when feasible
- successful save returns `FileWriteAck { path, success=true }`
- failed save returns `FILE_WRITE_FAILED`

## Explicit Mutations

### Create File

- path must not already exist
- parent directory must exist inside the session root
- new file contents start empty
- success returns `FileMutationAck { path, success=true, message=\"created\" }`

### Create Directory

- path must not already exist
- parent directory must exist inside the session root
- success returns `FileMutationAck { path, success=true, message=\"created\" }`

### Delete Path

- deleting root is forbidden
- deleting a non-empty directory requires `recursive=true`
- deleting a non-empty directory with `recursive=false` returns `FILE_NOT_EMPTY`
- missing target returns `FILE_NOT_FOUND`
- success returns `FileMutationAck { path, success=true, message=\"deleted\" }`

### Rename Path

- both `from_path` and `to_path` must remain inside the session root
- source must exist
- destination must not already exist
- parent directory of destination must exist
- success returns `FileMutationAck { path=to_path, success=true, message=\"renamed\" }`

## Error Semantics

Files errors are business-level errors returned in `FileResult.error`.

Required stable codes:

- `FILE_SESSION_NOT_FOUND`
- `FILE_ROOT_INVALID`
- `FILE_PATH_OUT_OF_BOUNDS`
- `FILE_NOT_FOUND`
- `FILE_ALREADY_EXISTS`
- `FILE_NOT_EMPTY`
- `FILE_TOO_LARGE`
- `FILE_UNSUPPORTED_TYPE`
- `FILE_WRITE_FAILED`
- `FILE_DELETE_FAILED`
- `FILE_RENAME_FAILED`

Suggested mapping:

- unknown or missing `session_id` -> `FILE_SESSION_NOT_FOUND`
- invalid session root -> `FILE_ROOT_INVALID`
- traversal / out-of-root access -> `FILE_PATH_OUT_OF_BOUNDS`
- missing target -> `FILE_NOT_FOUND`
- conflicting create or rename target -> `FILE_ALREADY_EXISTS`
- deleting non-empty dir without recursive flag -> `FILE_NOT_EMPTY`
- file too large -> `FILE_TOO_LARGE`
- binary file or directory open in editor -> `FILE_UNSUPPORTED_TYPE`
- IO failure on save -> `FILE_WRITE_FAILED`
- IO failure on delete -> `FILE_DELETE_FAILED`
- IO failure on rename -> `FILE_RENAME_FAILED`

## Mobile Design

Both clients replace the current Files placeholder with a session-root sandbox file browser.

### Layout

Three sections:

1. current path / navigation bar
2. directory listing
3. file editor or preview area

### Entry Preconditions

The Files screen is functional only when:

- agent is connected
- an active session exists

Otherwise the screen shows an explicit unavailable banner and no fake file data.

### Navigation Rules

- entering the Files tab loads root `""`
- tapping a directory pushes into that relative path
- tapping a file loads the file content
- a `..` UI entry may exist visually, but the client still expresses navigation using previously known safe relative paths; it never sends raw traversal components

### Editing Rules

- text file contents are editable
- non-text files show a read-only unsupported banner
- saving keeps the editor open and refreshes the current directory
- delete/rename of the file currently open in the editor clears selection and returns focus to the directory list

## Mobile State Model

### Top-Level States

- `Unavailable`
  - disconnected
  - no active session
- `LoadingDirectory`
- `DirectoryError`
- `DirectoryReady`

### File Substates

- `NoSelection`
- `LoadingFile`
- `FileError`
- `ReadOnlyPreview`
- `EditableText`
- `Saving`
- `SaveError`

### Mutation Substates

- `Creating`
- `Renaming`
- `Deleting`
- `MutationError`

### Race Handling

Clients must use latest-wins request handling:

- apply a response only if `request_id` matches the currently tracked in-flight request of that type
- also require `session_id` to match the current active session
- late directory/file/mutation responses from older sessions or older requests are discarded silently

## Testing Requirements

### Agent

Must cover:

- unknown session -> `FILE_SESSION_NOT_FOUND`
- out-of-bounds path rejection
- root listing
- nested directory listing
- text file read success
- large file rejection
- binary file rejection
- write save success and failure
- create file success / already exists
- create directory success / already exists
- delete file success / missing target
- delete non-empty directory requires recursive flag
- rename success / destination exists / source missing
- request/response echo for `request_id` and `session_id`
- `fatal=false` on Files business errors

### iOS

Must cover:

- unavailable states
- directory load success
- file open success
- non-text file unsupported state
- save success
- create / rename / delete flows
- latest-wins handling for directory and file responses

### Android

Must cover:

- unavailable states
- directory load success
- file open success
- non-text file unsupported state
- save success
- create / rename / delete flows
- latest-wins handling for directory and file responses

### UI Smoke

At least one higher-level smoke flow per mobile platform should verify:

- entering Files
- opening a subdirectory
- opening a text file
- saving a file successfully

## Acceptance Criteria

This slice is complete when:

- iOS Files tab is no longer a placeholder
- Android Files tab is no longer a placeholder
- all file operations stay confined to the active session `working_dir`
- browsing, reading, saving, creating, deleting, and renaming work for text files/directories within the sandbox
- binary and oversized files fail with explicit unsupported/too-large behavior
- fresh cross-platform verification passes
