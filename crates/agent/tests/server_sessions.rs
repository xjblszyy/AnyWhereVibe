use std::sync::Arc;

use agent::test_support::{PromptStartOutcome, TestClient};
use tokio::sync::Barrier;

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

#[tokio::test]
async fn server_allows_only_one_of_multiple_concurrent_prompts_to_start() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut owner = TestClient::connect(server.ws_url()).await;

    owner.handshake_ios().await;
    let session_one = owner.create_session("One", "/tmp/one").await;
    let session_two = owner.create_session("Two", "/tmp/two").await;
    let session_three = owner.create_session("Three", "/tmp/three").await;
    let session_four = owner.create_session("Four", "/tmp/four").await;

    let mut client_two = TestClient::connect(server.ws_url()).await;
    client_two.handshake_ios().await;
    let mut client_three = TestClient::connect(server.ws_url()).await;
    client_three.handshake_ios().await;
    let mut client_four = TestClient::connect(server.ws_url()).await;
    client_four.handshake_ios().await;

    let barrier = Arc::new(Barrier::new(5));

    let one_id = session_one.session_id.clone();
    let barrier_one = barrier.clone();
    let one = tokio::spawn(async move {
        barrier_one.wait().await;
        owner.send_prompt(&one_id, "one").await;
        owner.expect_prompt_start_or_error(&one_id).await
    });

    let two_id = session_two.session_id.clone();
    let barrier_two = barrier.clone();
    let two = tokio::spawn(async move {
        barrier_two.wait().await;
        client_two.send_prompt(&two_id, "two").await;
        client_two.expect_prompt_start_or_error(&two_id).await
    });

    let three_id = session_three.session_id.clone();
    let barrier_three = barrier.clone();
    let three = tokio::spawn(async move {
        barrier_three.wait().await;
        client_three.send_prompt(&three_id, "three").await;
        client_three.expect_prompt_start_or_error(&three_id).await
    });

    let four_id = session_four.session_id.clone();
    let barrier_four = barrier.clone();
    let four = tokio::spawn(async move {
        barrier_four.wait().await;
        client_four.send_prompt(&four_id, "four").await;
        client_four.expect_prompt_start_or_error(&four_id).await
    });

    barrier.wait().await;

    let outcomes = [
        one.await.unwrap(),
        two.await.unwrap(),
        three.await.unwrap(),
        four.await.unwrap(),
    ];

    let started = outcomes
        .iter()
        .filter(|outcome| matches!(outcome, PromptStartOutcome::Started))
        .count();
    let rejected = outcomes
        .iter()
        .filter(|outcome| {
            matches!(
                outcome,
                PromptStartOutcome::Error(error) if error.code == "TASK_ALREADY_RUNNING" && !error.fatal
            )
        })
        .count();

    assert_eq!(started, 1, "only one concurrent prompt may start");
    assert_eq!(rejected, 3, "all remaining prompts must be rejected");
}

#[tokio::test]
async fn server_closes_session_and_broadcasts_updated_session_list() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let first = client.create_session("One", "/tmp/one").await;
    let second = client.create_session("Two", "/tmp/two").await;
    loop {
        let sessions = client.expect_session_list_update().await;
        if sessions.sessions.iter().any(|session| session.session_id == first.session_id)
            && sessions.sessions.iter().any(|session| session.session_id == second.session_id)
        {
            break;
        }
    }

    client.close_session(&first.session_id).await;

    let sessions = loop {
        let sessions = client.expect_session_list_update().await;
        let ids: Vec<_> = sessions
            .sessions
            .iter()
            .map(|session| session.session_id.clone())
            .collect();
        if !ids.contains(&first.session_id) && ids.contains(&second.session_id) {
            break sessions;
        }
    };
    let ids: Vec<_> = sessions.sessions.into_iter().map(|session| session.session_id).collect();
    assert!(!ids.contains(&first.session_id));
    assert!(ids.contains(&second.session_id));
}

#[tokio::test]
async fn server_rejects_close_for_running_session_but_keeps_connection_open() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = TestClient::connect(server.ws_url()).await;

    client.handshake_ios().await;
    let session = client.create_session("Busy", "/tmp/busy").await;
    loop {
        let sessions = client.expect_session_list_update().await;
        if sessions.sessions.iter().any(|item| item.session_id == session.session_id) {
            break;
        }
    }

    client.send_prompt(&session.session_id, "busy").await;
    let started = client.expect_prompt_start_or_error(&session.session_id).await;
    assert!(matches!(started, PromptStartOutcome::Started));

    client.close_session(&session.session_id).await;
    let error = client.expect_error().await;
    assert!(!error.fatal);
    assert_eq!(error.code, "SESSION_BUSY");
    client.expect_connection_alive().await;
}
