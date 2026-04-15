use std::fs;
use std::path::Path;
use std::process::Command;

use agent::test_support::TestClient;
use proto_gen::git_result::Result as GitResultPayload;

#[tokio::test]
async fn git_status_returns_session_not_found_for_unknown_session() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let request_id = client.send_git_status("missing-session").await;
    let (response_request_id, result) = client.expect_git_result().await;

    assert_eq!(response_request_id, request_id);
    assert_eq!(result.session_id, "missing-session");
    match result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_SESSION_NOT_FOUND");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_status_returns_repo_not_found_for_non_repo_session() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let temp = tempfile::tempdir().unwrap();
    let session = client
        .create_session("NoRepo", temp.path().to_str().unwrap())
        .await;

    let request_id = client.send_git_status(&session.session_id).await;
    let (response_request_id, result) = client.expect_git_result().await;

    assert_eq!(response_request_id, request_id);
    assert_eq!(result.session_id, session.session_id);
    match result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_REPO_NOT_FOUND");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_status_returns_worktree_first_changes() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    fs::write(repo.path().join("modified.txt"), "hello modified\n").unwrap();
    fs::remove_file(repo.path().join("deleted.txt")).unwrap();
    fs::write(repo.path().join("staged_only.txt"), "staged only changed\n").unwrap();
    git(repo.path(), &["add", "staged_only.txt"]).unwrap();
    fs::write(repo.path().join("new file.txt"), "new file contents\n").unwrap();

    let nested = repo.path().join("nested").join("deeper");
    fs::create_dir_all(&nested).unwrap();
    let session = client
        .create_session("Repo", nested.to_str().unwrap())
        .await;

    client.send_git_status(&session.session_id).await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Status(status)) => {
            assert_eq!(status.branch, "main");
            assert_eq!(status.tracking, "");
            assert!(!status.is_clean);

            let paths_and_statuses: Vec<_> = status
                .changes
                .into_iter()
                .map(|change| (change.path, change.status))
                .collect();

            assert!(paths_and_statuses.contains(&("modified.txt".to_owned(), "modified".to_owned())));
            assert!(paths_and_statuses.contains(&("deleted.txt".to_owned(), "deleted".to_owned())));
            assert!(paths_and_statuses.contains(&("new file.txt".to_owned(), "untracked".to_owned())));
            assert!(!paths_and_statuses
                .iter()
                .any(|(path, _)| path == "staged_only.txt"));
        }
        other => panic!("expected git status, got {other:?}"),
    }
}

#[tokio::test]
async fn git_result_echoes_request_id_on_success_and_error() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    fs::write(repo.path().join("modified.txt"), "hello modified\n").unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    let status_request_id = client.send_git_status(&session.session_id).await;
    let (status_response_request_id, status_result) = client.expect_git_result().await;
    assert_eq!(status_response_request_id, status_request_id);
    assert_eq!(status_result.session_id, session.session_id);

    let diff_request_id = client.send_git_diff(&session.session_id, "../oops").await;
    let (diff_response_request_id, diff_result) = client.expect_git_result().await;
    assert_eq!(diff_response_request_id, diff_request_id);
    assert_eq!(diff_result.session_id, session.session_id);
    match diff_result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_DIFF_PATH_OUT_OF_BOUNDS");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_diff_returns_unified_diff_for_modified_file() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    fs::write(repo.path().join("modified.txt"), "hello modified\n").unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    client.send_git_diff(&session.session_id, "modified.txt").await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Diff(diff)) => {
            assert!(diff.diff.contains("@@"));
            assert!(diff.diff.contains("-hello"));
            assert!(diff.diff.contains("+hello modified"));
            assert!(diff.diff.as_bytes().len() <= 262_144);
        }
        other => panic!("expected git diff, got {other:?}"),
    }
}

#[tokio::test]
async fn git_diff_rewrites_untracked_headers_to_repo_relative_paths() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    fs::write(repo.path().join("new file.txt"), "new file contents\n").unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    client.send_git_diff(&session.session_id, "new file.txt").await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Diff(diff)) => {
            assert!(diff.diff.starts_with("diff --git a/new file.txt b/new file.txt\n--- /dev/null\n+++ b/new file.txt\n"));
            assert!(diff.diff.contains("+new file contents"));
        }
        other => panic!("expected git diff, got {other:?}"),
    }
}

#[tokio::test]
async fn git_diff_supports_deleted_tracked_file() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    fs::remove_file(repo.path().join("deleted.txt")).unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    client.send_git_diff(&session.session_id, "deleted.txt").await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Diff(diff)) => {
            assert!(diff.diff.contains("--- a/deleted.txt"));
            assert!(diff.diff.contains("+++ /dev/null"));
        }
        other => panic!("expected git diff, got {other:?}"),
    }
}

#[tokio::test]
async fn git_diff_returns_target_stale_for_no_longer_changed_path() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    fs::write(repo.path().join("modified.txt"), "hello modified\n").unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;
    fs::write(repo.path().join("modified.txt"), "hello\n").unwrap();

    client.send_git_diff(&session.session_id, "modified.txt").await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_DIFF_TARGET_STALE");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_diff_rejects_out_of_bounds_path() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    client.send_git_diff(&session.session_id, "../secret").await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_DIFF_PATH_OUT_OF_BOUNDS");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_unsupported_operations_return_git_op_unsupported() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    client.send_git_commit(&session.session_id).await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_OP_UNSUPPORTED");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_diff_returns_unsupported_for_binary_content() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let repo = init_repo_with_base().unwrap();
    fs::write(repo.path().join("binary.bin"), [0, 159, 146, 150]).unwrap();
    let session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    client.send_git_diff(&session.session_id, "binary.bin").await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_DIFF_UNSUPPORTED");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_status_returns_workdir_invalid_for_bad_session_workdir() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let bogus = std::env::temp_dir().join("missing-agent-git-workdir");
    let session = client
        .create_session("Repo", bogus.to_str().unwrap())
        .await;

    client.send_git_status(&session.session_id).await;
    let (_, result) = client.expect_git_result().await;
    match result.result {
        Some(GitResultPayload::Error(error)) => {
            assert_eq!(error.code, "GIT_WORKDIR_INVALID");
            assert!(!error.fatal);
        }
        other => panic!("expected git error, got {other:?}"),
    }
}

#[tokio::test]
async fn git_errors_always_return_fatal_false() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let temp = tempfile::tempdir().unwrap();
    let non_repo_session = client
        .create_session("NoRepo", temp.path().to_str().unwrap())
        .await;
    let repo = init_repo_with_base().unwrap();
    let repo_session = client
        .create_session("Repo", repo.path().to_str().unwrap())
        .await;

    for (request, expected_code) in [
        (GitRequest::Status(non_repo_session.session_id.clone()), "GIT_REPO_NOT_FOUND"),
        (
            GitRequest::Diff(repo_session.session_id.clone(), "../bad".to_owned()),
            "GIT_DIFF_PATH_OUT_OF_BOUNDS",
        ),
        (
            GitRequest::Status("missing-session".to_owned()),
            "GIT_SESSION_NOT_FOUND",
        ),
    ] {
        match request {
            GitRequest::Status(session_id) => {
                client.send_git_status(&session_id).await;
            }
            GitRequest::Diff(session_id, path) => {
                client.send_git_diff(&session_id, &path).await;
            }
        }
        let (_, result) = client.expect_git_result().await;
        match result.result {
            Some(GitResultPayload::Error(error)) => {
                assert_eq!(error.code, expected_code);
                assert!(!error.fatal);
            }
            other => panic!("expected git error, got {other:?}"),
        }
    }
}

enum GitRequest {
    Status(String),
    Diff(String, String),
}

fn init_repo_with_base() -> anyhow::Result<tempfile::TempDir> {
    let repo = tempfile::tempdir()?;
    git(repo.path(), &["init", "-b", "main"])?;
    git(repo.path(), &["config", "user.name", "Test User"])?;
    git(repo.path(), &["config", "user.email", "test@example.com"])?;

    fs::write(repo.path().join("modified.txt"), "hello\n")?;
    fs::write(repo.path().join("deleted.txt"), "delete me\n")?;
    fs::write(repo.path().join("staged_only.txt"), "stage me\n")?;
    git(repo.path(), &["add", "."])?;
    git(repo.path(), &["commit", "-m", "initial"])?;

    Ok(repo)
}

fn git(cwd: &Path, args: &[&str]) -> anyhow::Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(cwd)
        .args(args)
        .output()?;
    if !output.status.success() {
        anyhow::bail!("{}", String::from_utf8_lossy(&output.stderr).trim().to_owned());
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}
