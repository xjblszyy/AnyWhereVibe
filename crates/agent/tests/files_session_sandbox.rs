use std::fs;
use std::path::Path;

use agent::test_support::TestClient;
use proto_gen::file_result::Result as FileResultPayload;

#[tokio::test]
async fn file_list_returns_session_not_found_for_unknown_session() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let request_id = client.send_list_dir("missing-session", "").await;
    let (response_request_id, result) = client.expect_file_result().await;

    assert_eq!(response_request_id, request_id);
    assert_eq!(result.session_id, "missing-session");
    match result.result {
        Some(FileResultPayload::Error(error)) => {
            assert_eq!(error.code, "FILE_SESSION_NOT_FOUND");
            assert!(!error.fatal);
        }
        other => panic!("expected file error, got {other:?}"),
    }
}

#[tokio::test]
async fn file_ops_reject_out_of_bounds_paths() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client.send_read_file(&session.session_id, "../secret").await;
    let (_, result) = client.expect_file_result().await;
    match result.result {
        Some(FileResultPayload::Error(error)) => {
            assert_eq!(error.code, "FILE_PATH_OUT_OF_BOUNDS");
            assert!(!error.fatal);
        }
        other => panic!("expected file error, got {other:?}"),
    }
}

#[tokio::test]
async fn list_dir_returns_root_entries_sorted_dirs_first() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client.send_list_dir(&session.session_id, "").await;
    let (_, result) = client.expect_file_result().await;
    match result.result {
        Some(FileResultPayload::DirListing(listing)) => {
            let names: Vec<_> = listing.entries.into_iter().map(|entry| (entry.name, entry.is_dir)).collect();
            assert_eq!(
                names,
                vec![
                    ("folder".to_owned(), true),
                    ("binary.bin".to_owned(), false),
                    ("hello.txt".to_owned(), false),
                ]
            );
        }
        other => panic!("expected dir listing, got {other:?}"),
    }
}

#[tokio::test]
async fn read_file_returns_text_content_for_small_text_file() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client.send_read_file(&session.session_id, "hello.txt").await;
    let (_, result) = client.expect_file_result().await;
    match result.result {
        Some(FileResultPayload::FileContent(file)) => {
            assert_eq!(file.path, "hello.txt");
            assert_eq!(String::from_utf8(file.content).unwrap(), "hello world\n");
            assert_eq!(file.mime_type, "text/plain");
        }
        other => panic!("expected file content, got {other:?}"),
    }
}

#[tokio::test]
async fn read_file_rejects_large_or_binary_files() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    fs::write(root.path().join("large.txt"), vec![b'a'; 1_048_577]).unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client.send_read_file(&session.session_id, "large.txt").await;
    let (_, largeResult) = client.expect_file_result().await;
    match largeResult.result {
        Some(FileResultPayload::Error(error)) => assert_eq!(error.code, "FILE_TOO_LARGE"),
        other => panic!("expected file error, got {other:?}"),
    }

    client.send_read_file(&session.session_id, "binary.bin").await;
    let (_, binaryResult) = client.expect_file_result().await;
    match binaryResult.result {
        Some(FileResultPayload::Error(error)) => assert_eq!(error.code, "FILE_UNSUPPORTED_TYPE"),
        other => panic!("expected file error, got {other:?}"),
    }
}

#[tokio::test]
async fn write_file_saves_existing_text_file() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client
        .send_write_file(&session.session_id, "hello.txt", b"updated contents\n")
        .await;
    let (_, result) = client.expect_file_result().await;
    match result.result {
        Some(FileResultPayload::WriteAck(ack)) => {
            assert_eq!(ack.path, "hello.txt");
            assert!(ack.success);
        }
        other => panic!("expected write ack, got {other:?}"),
    }

    assert_eq!(fs::read_to_string(root.path().join("hello.txt")).unwrap(), "updated contents\n");
}

#[tokio::test]
async fn create_file_and_create_dir_return_mutation_ack() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client.send_create_file(&session.session_id, "new.txt").await;
    let (_, fileResult) = client.expect_file_result().await;
    match fileResult.result {
        Some(FileResultPayload::MutationAck(ack)) => {
            assert_eq!(ack.path, "new.txt");
            assert_eq!(ack.message, "created");
        }
        other => panic!("expected mutation ack, got {other:?}"),
    }
    assert!(root.path().join("new.txt").exists());

    client.send_create_dir(&session.session_id, "newdir").await;
    let (_, dirResult) = client.expect_file_result().await;
    match dirResult.result {
        Some(FileResultPayload::MutationAck(ack)) => {
            assert_eq!(ack.path, "newdir");
            assert_eq!(ack.message, "created");
        }
        other => panic!("expected mutation ack, got {other:?}"),
    }
    assert!(root.path().join("newdir").is_dir());
}

#[tokio::test]
async fn delete_requires_recursive_for_non_empty_dirs() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client.send_delete_path(&session.session_id, "folder", false).await;
    let (_, result) = client.expect_file_result().await;
    match result.result {
        Some(FileResultPayload::Error(error)) => assert_eq!(error.code, "FILE_NOT_EMPTY"),
        other => panic!("expected file error, got {other:?}"),
    }

    client.send_delete_path(&session.session_id, "folder", true).await;
    let (_, deleted) = client.expect_file_result().await;
    match deleted.result {
        Some(FileResultPayload::MutationAck(ack)) => assert_eq!(ack.message, "deleted"),
        other => panic!("expected mutation ack, got {other:?}"),
    }
}

#[tokio::test]
async fn rename_rejects_existing_destination() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    let root = build_fixture_root().unwrap();
    let session = client
        .create_session("Files", root.path().to_str().unwrap())
        .await;

    client.send_rename_path(&session.session_id, "hello.txt", "binary.bin").await;
    let (_, result) = client.expect_file_result().await;
    match result.result {
        Some(FileResultPayload::Error(error)) => assert_eq!(error.code, "FILE_ALREADY_EXISTS"),
        other => panic!("expected file error, got {other:?}"),
    }

    client.send_rename_path(&session.session_id, "hello.txt", "renamed.txt").await;
    let (_, renamed) = client.expect_file_result().await;
    match renamed.result {
        Some(FileResultPayload::MutationAck(ack)) => assert_eq!(ack.path, "renamed.txt"),
        other => panic!("expected mutation ack, got {other:?}"),
    }
}

fn build_fixture_root() -> anyhow::Result<tempfile::TempDir> {
    let root = tempfile::tempdir()?;
    fs::create_dir(root.path().join("folder"))?;
    fs::write(root.path().join("folder").join("nested.txt"), "nested\n")?;
    fs::write(root.path().join("hello.txt"), "hello world\n")?;
    fs::write(root.path().join("binary.bin"), [0_u8, 1, 2, 3])?;
    Ok(root)
}
