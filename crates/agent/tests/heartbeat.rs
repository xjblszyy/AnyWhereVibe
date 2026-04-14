use tokio::time::{advance, Duration};

#[tokio::test(start_paused = true)]
async fn server_closes_connection_after_45_seconds_without_valid_messages() {
    let server = agent::test_support::spawn_mock_server().await;
    let mut client = agent::test_support::TestClient::connect(server.ws_url()).await;
    client.handshake_ios().await;

    advance(Duration::from_secs(46)).await;

    client.expect_disconnect().await;
}
