use std::path::{Path, PathBuf};
use std::process::Command;

use proto_gen::{GitDiffResult, GitFileChange, GitStatusResult};

const MAX_DIFF_BYTES: usize = 262_144;
const DIFF_TRUNCATION_MARKER: &str = " ... diff truncated by agent at 262144 bytes ...";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitError {
    code: &'static str,
    message: String,
}

impl GitError {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn code(&self) -> &'static str {
        self.code
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

pub struct GitService;

impl GitService {
    pub fn status_for_session_workdir(working_dir: &Path) -> std::result::Result<GitStatusResult, GitError> {
        let repo_root = discover_repo_root(working_dir)?;
        status_for_repo_root(&repo_root)
    }

    pub fn diff_for_session_workdir(
        working_dir: &Path,
        requested_path: &str,
    ) -> std::result::Result<GitDiffResult, GitError> {
        let repo_root = discover_repo_root(working_dir)?;
        let normalized_path = normalize_requested_path(requested_path)?;
        let status = status_for_repo_root(&repo_root)?;
        let Some(change) = status.changes.iter().find(|change| change.path == normalized_path) else {
            return Err(GitError::new(
                "GIT_DIFF_TARGET_STALE",
                format!("path '{}' is no longer changed", normalized_path),
            ));
        };

        let diff = match change.status.as_str() {
            "untracked" => diff_for_untracked_path(&repo_root, &normalized_path)?,
            "deleted" | "modified" => diff_for_tracked_path(&repo_root, &normalized_path)?,
            other => {
                return Err(GitError::new(
                    "GIT_DIFF_UNSUPPORTED",
                    format!("unsupported diff status '{}'", other),
                ))
            }
        };

        Ok(GitDiffResult {
            diff: truncate_diff(diff),
        })
    }

    pub fn platform_null_path() -> &'static str {
        if cfg!(windows) {
            "NUL"
        } else {
            "/dev/null"
        }
    }
}

fn discover_repo_root(working_dir: &Path) -> std::result::Result<PathBuf, GitError> {
    if working_dir.as_os_str().is_empty() || !working_dir.exists() || !working_dir.is_dir() {
        return Err(GitError::new(
            "GIT_WORKDIR_INVALID",
            format!("working dir '{}' is invalid", working_dir.display()),
        ));
    }

    let repo_root = run_git_success(
        working_dir,
        &["rev-parse", "--show-toplevel"],
        "GIT_REPO_NOT_FOUND",
    )?;
    let repo_root = PathBuf::from(trim_trailing_newline(&repo_root));
    let bare = run_git_success(
        &repo_root,
        &["rev-parse", "--is-bare-repository"],
        "GIT_REPO_NOT_FOUND",
    )?;
    if trim_trailing_newline(&bare) == "true" {
        return Err(GitError::new(
            "GIT_REPO_NOT_FOUND",
            format!("'{}' is a bare repository", repo_root.display()),
        ));
    }

    Ok(repo_root)
}

fn status_for_repo_root(repo_root: &Path) -> std::result::Result<GitStatusResult, GitError> {
    let output = run_git_success(
        repo_root,
        &[
            "-c",
            "core.quotepath=off",
            "status",
            "--porcelain=v1",
            "-z",
            "--branch",
            "--untracked-files=all",
            "--no-renames",
        ],
        "GIT_COMMAND_FAILED",
    )?;

    parse_status_output(&output)
}

fn parse_status_output(output: &str) -> std::result::Result<GitStatusResult, GitError> {
    let mut records = output.split('\0').filter(|record| !record.is_empty());
    let header_line = records.next().unwrap_or_default();
    let (branch, tracking) = parse_branch_header(header_line);

    let mut changes = Vec::new();
    for record in records {
        if record.len() < 3 {
            return Err(GitError::new(
                "GIT_COMMAND_FAILED",
                "unexpected porcelain status record",
            ));
        }
        let bytes = record.as_bytes();
        let x = bytes[0] as char;
        let y = bytes[1] as char;
        if bytes[2] != b' ' {
            return Err(GitError::new(
                "GIT_COMMAND_FAILED",
                "unexpected porcelain path separator",
            ));
        }

        let path = normalize_status_path(&record[3..]);
        let status = if x == '?' && y == '?' {
            Some("untracked")
        } else if y == ' ' {
            None
        } else if y == 'D' {
            Some("deleted")
        } else {
            Some("modified")
        };

        if let Some(status) = status {
            changes.push(GitFileChange {
                path,
                status: status.to_owned(),
            });
        }
    }

    Ok(GitStatusResult {
        branch,
        tracking,
        is_clean: changes.is_empty(),
        changes,
    })
}

fn parse_branch_header(header_line: &str) -> (String, String) {
    let header = header_line.strip_prefix("## ").unwrap_or(header_line).trim();
    if header.starts_with("HEAD ") || header == "HEAD (no branch)" {
        return ("HEAD".to_owned(), String::new());
    }

    if let Some((branch, tracking)) = header.split_once("...") {
        return (
            branch.to_owned(),
            tracking.split(" [").next().unwrap_or(tracking).to_owned(),
        );
    }

    (header.to_owned(), String::new())
}

fn normalize_status_path(path: &str) -> String {
    path.replace('\\', "/").trim_start_matches("./").to_owned()
}

fn normalize_requested_path(path: &str) -> std::result::Result<String, GitError> {
    if path.is_empty() {
        return Err(GitError::new(
            "GIT_DIFF_PATH_OUT_OF_BOUNDS",
            "diff path cannot be empty",
        ));
    }

    let candidate = Path::new(path);
    if candidate.is_absolute() {
        return Err(GitError::new(
            "GIT_DIFF_PATH_OUT_OF_BOUNDS",
            "diff path must be repo-relative",
        ));
    }

    let mut parts = Vec::new();
    for part in path.split('/') {
        if part.is_empty() || part == "." || part == ".." {
            return Err(GitError::new(
                "GIT_DIFF_PATH_OUT_OF_BOUNDS",
                format!("invalid diff path '{}'", path),
            ));
        }
        parts.push(part);
    }

    Ok(parts.join("/"))
}

fn diff_for_tracked_path(repo_root: &Path, path: &str) -> std::result::Result<String, GitError> {
    let diff = run_git_allow_diff_exit(
        repo_root,
        &["diff", "--no-ext-diff", "--no-renames", "--unified=3", "--", path],
        "GIT_COMMAND_FAILED",
    )?;
    if is_binary_diff(&diff) {
        return Err(GitError::new(
            "GIT_DIFF_UNSUPPORTED",
            format!("binary diff is not supported for '{}'", path),
        ));
    }
    Ok(diff)
}

fn diff_for_untracked_path(repo_root: &Path, path: &str) -> std::result::Result<String, GitError> {
    let absolute_path = repo_root.join(path);
    let canonical_repo_root = repo_root.canonicalize().map_err(|error| {
        GitError::new(
            "GIT_COMMAND_FAILED",
            format!("failed to canonicalize repo root '{}': {error}", repo_root.display()),
        )
    })?;
    let canonical_path = absolute_path.canonicalize().map_err(|_| {
        GitError::new(
            "GIT_DIFF_TARGET_STALE",
            format!("path '{}' is no longer changed", path),
        )
    })?;
    if !canonical_path.starts_with(&canonical_repo_root) {
        return Err(GitError::new(
            "GIT_DIFF_PATH_OUT_OF_BOUNDS",
            format!("path '{}' resolves outside repository", path),
        ));
    }

    let prefix = std::fs::read(&canonical_path)
        .map(|contents| contents.into_iter().take(8192).collect::<Vec<_>>())
        .map_err(|error| {
            GitError::new(
                "GIT_COMMAND_FAILED",
                format!("failed to read '{}': {error}", canonical_path.display()),
            )
        })?;
    if prefix.iter().any(|byte| *byte == 0) {
        return Err(GitError::new(
            "GIT_DIFF_UNSUPPORTED",
            format!("binary diff is not supported for '{}'", path),
        ));
    }

    let diff = run_git_allow_diff_exit(
        repo_root,
        &[
            "diff",
            "--no-index",
            "--no-ext-diff",
            "--",
            GitService::platform_null_path(),
            &canonical_path.to_string_lossy(),
        ],
        "GIT_COMMAND_FAILED",
    )?;

    rewrite_untracked_diff_headers(&diff, path)
}

fn rewrite_untracked_diff_headers(diff: &str, path: &str) -> std::result::Result<String, GitError> {
    let mut lines: Vec<&str> = diff.lines().collect();
    if lines.len() < 3 {
        return Err(GitError::new(
            "GIT_COMMAND_FAILED",
            "unexpected untracked diff output",
        ));
    }
    lines[0] = ""; // replaced below
    lines[1] = ""; // replaced below
    lines[2] = ""; // replaced below

    let mut rewritten = Vec::with_capacity(lines.len() + 3);
    rewritten.push(format!("diff --git a/{path} b/{path}"));
    rewritten.push("--- /dev/null".to_owned());
    rewritten.push(format!("+++ b/{path}"));
    rewritten.extend(lines.into_iter().skip(3).map(str::to_owned));
    let mut out = rewritten.join("\n");
    if diff.ends_with('\n') {
        out.push('\n');
    }
    Ok(out)
}

fn run_git_success(
    cwd: &Path,
    args: &[&str],
    code: &'static str,
) -> std::result::Result<String, GitError> {
    let output = Command::new("git")
        .arg("-C")
        .arg(cwd)
        .args(args)
        .output()
        .map_err(|error| GitError::new(code, format!("failed to launch git: {error}")))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(GitError::new(
            code,
            if stderr.is_empty() {
                format!("git {:?} failed", args)
            } else {
                stderr
            },
        ));
    }

    String::from_utf8(output.stdout)
        .map_err(|error| GitError::new(code, format!("git output was not utf-8: {error}")))
}

fn run_git_allow_diff_exit(
    cwd: &Path,
    args: &[&str],
    code: &'static str,
) -> std::result::Result<String, GitError> {
    let output = Command::new("git")
        .arg("-C")
        .arg(cwd)
        .args(args)
        .output()
        .map_err(|error| GitError::new(code, format!("failed to launch git: {error}")))?;

    let exit = output.status.code().unwrap_or_default();
    if exit != 0 && exit != 1 {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(GitError::new(
            code,
            if stderr.is_empty() {
                format!("git {:?} failed", args)
            } else {
                stderr
            },
        ));
    }

    String::from_utf8(output.stdout)
        .map_err(|error| GitError::new(code, format!("git output was not utf-8: {error}")))
}

fn trim_trailing_newline(value: &str) -> String {
    value.trim_end_matches(['\r', '\n']).to_owned()
}

fn is_binary_diff(diff: &str) -> bool {
    diff.contains("Binary files") || diff.contains("GIT binary patch")
}

fn truncate_diff(diff: String) -> String {
    if diff.as_bytes().len() <= MAX_DIFF_BYTES {
        return diff;
    }

    let marker = format!("\n{DIFF_TRUNCATION_MARKER}");
    let budget = MAX_DIFF_BYTES.saturating_sub(marker.as_bytes().len());
    let mut used = 0usize;
    let mut content = String::new();
    for line in diff.split_inclusive('\n') {
        let line_bytes = line.as_bytes().len();
        if used + line_bytes > budget {
            break;
        }
        used += line_bytes;
        content.push_str(line);
    }

    if !content.ends_with('\n') {
        content.push('\n');
    }
    content.push_str(DIFF_TRUNCATION_MARKER);
    content
}

#[cfg(test)]
mod tests {
    use super::GitService;

    #[test]
    fn platform_null_path_matches_host_family() {
        if cfg!(windows) {
            assert_eq!(GitService::platform_null_path(), "NUL");
        } else {
            assert_eq!(GitService::platform_null_path(), "/dev/null");
        }
    }
}
