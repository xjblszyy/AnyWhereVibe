use agent::test_support::TestClient;

#[tokio::test]
async fn server_creates_session_and_broadcasts_session_list() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    client.create_session("Main", "/tmp/project").await;

    let sessions = client.expect_session_list_update().await;
    assert_eq!(sessions.sessions.len(), 1);
}

#[tokio::test]
async fn server_rejects_second_prompt_while_any_session_is_running_but_keeps_connection_open() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let first = client.create_session("One", "/tmp/one").await;
    let second = client.create_session("Two", "/tmp/two").await;

    client.send_prompt(&first.session_id, "first").await;
    let error = client
        .send_prompt_expect_error(&second.session_id, "second")
        .await;

    assert!(!error.fatal);
    assert_eq!(error.code, "TASK_ALREADY_RUNNING");
    client.expect_connection_alive().await;
}

#[tokio::test]
async fn server_forwards_approval_response_and_task_resumes_to_completion() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let session = client.create_session("One", "/tmp/one").await;

    client.send_prompt(&session.session_id, "one").await;
    client
        .expect_status_sequence(&["RUNNING", "COMPLETED", "IDLE"])
        .await;

    client.send_prompt(&session.session_id, "two").await;
    client
        .expect_status_sequence(&["RUNNING", "COMPLETED", "IDLE"])
        .await;

    client.send_prompt(&session.session_id, "three").await;
    client
        .expect_status_sequence(&["RUNNING", "WAITING_APPROVAL"])
        .await;

    let approval = client.expect_approval_request().await;
    client.respond_approval(&approval.approval_id, true).await;

    client
        .expect_status_sequence(&["RUNNING", "COMPLETED", "IDLE"])
        .await;
}

#[tokio::test]
async fn server_returns_non_fatal_error_for_missing_session() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let error = client
        .send_prompt_expect_error("missing-session", "oops")
        .await;

    assert!(!error.fatal);
    assert_eq!(error.code, "SESSION_NOT_FOUND");
}

#[tokio::test]
async fn server_returns_non_fatal_error_for_unknown_approval_id() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let error = client
        .respond_approval_expect_error("missing-approval-id", true)
        .await;

    assert!(!error.fatal);
    assert_eq!(error.code, "APPROVAL_NOT_FOUND");
}
